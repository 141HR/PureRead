import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math' as math;

import '../../domain/domain.dart';
import '../m2_providers.dart';

/// Priority tiers for chapter fetching and background caching.
///
/// Active user reads always preempt batch downloads and silent `N+1..N+3`
/// ahead preloads.
enum PreloadPriority {
  active(0),
  batch(1),
  ahead(2);

  const PreloadPriority(this.rank);

  final int rank;
}

/// Diagnostic log entry emitted silently when a background preload or batch
/// caching task fails or is skipped.
class PreloadLogEntry {
  final DateTime timestamp;
  final String bookId;
  final int chapterIndex;
  final PreloadPriority priority;
  final String message;
  final Object? error;

  const PreloadLogEntry({
    required this.timestamp,
    required this.bookId,
    required this.chapterIndex,
    required this.priority,
    required this.message,
    this.error,
  });
}

/// Progress snapshot emitted while running [ChapterPreloadScheduler.cacheRange].
class PreloadBatchProgress {
  final int total;
  final int completed;
  final int cachedCount;
  final int skippedCachedCount;
  final int failedCount;
  final bool isCancelled;

  const PreloadBatchProgress({
    required this.total,
    required this.completed,
    required this.cachedCount,
    required this.skippedCachedCount,
    required this.failedCount,
    this.isCancelled = false,
  });

  double get ratio => total <= 0 ? 1.0 : (completed / total).clamp(0.0, 1.0);
}

/// Final summary returned by [ChapterPreloadScheduler.cacheRange].
class PreloadBatchResult {
  final int total;
  final int cachedCount;
  final int skippedCachedCount;
  final int failedCount;
  final List<int> failedChapterIndices;
  final bool cancelled;

  const PreloadBatchResult({
    required this.total,
    required this.cachedCount,
    required this.skippedCachedCount,
    required this.failedCount,
    this.failedChapterIndices = const <int>[],
    this.cancelled = false,
  });
}

/// Priority-scheduled online chapter fetcher and silent preloader.
///
/// - Active user reads ([fetchActiveChapter]) have highest priority and
///   preempt queued batch downloads and silent `N+1..N+3` preloads.
/// - Silent ahead preloads ([scheduleAhead]) skip already-cached chapters
///   (`isCached == true` or cache hit) and record failures silently without
///   throwing unhandled errors to UI.
/// - Batch offline caching ([cacheRange]) caches chapter ranges cooperatively
///   under [CancellationToken] and reports incremental progress.
class ChapterPreloadScheduler {
  ChapterPreloadScheduler({
    required this._bookRepository,
    required this._sourceRepository,
    required this._providerFactory,
    required this._cacheGateway,
    int maxConcurrentTasks = 2,
    int maxBackgroundTasks = 1,
    int maxLogEntries = 200,
  })  : _maxConcurrentTasks = math.max(1, maxConcurrentTasks),
        _maxBackgroundTasks = math.max(
          1,
          math.min(maxBackgroundTasks, math.max(1, maxConcurrentTasks)),
        ),
        _maxLogEntries = math.max(10, maxLogEntries);

  final BookRepository _bookRepository;
  final SourceRepository _sourceRepository;
  final BookProviderFactoryGateway _providerFactory;
  final ChapterCacheGateway _cacheGateway;
  final int _maxConcurrentTasks;
  final int _maxBackgroundTasks;
  final int _maxLogEntries;

  final List<_QueuedChapterTask> _pendingQueue = <_QueuedChapterTask>[];
  final Map<_ChapterTaskKey, _QueuedChapterTask> _queuedByKey =
      <_ChapterTaskKey, _QueuedChapterTask>{};
  final Map<_ChapterTaskKey, _QueuedChapterTask> _inFlightByKey =
      <_ChapterTaskKey, _QueuedChapterTask>{};
  final Map<String, CancellationToken> _aheadTokensByBook =
      <String, CancellationToken>{};
  final ListQueue<PreloadLogEntry> _logs = ListQueue<PreloadLogEntry>();
  final StreamController<PreloadLogEntry> _logController =
      StreamController<PreloadLogEntry>.broadcast();

  bool _disposed = false;
  int _nextSequence = 0;
  int _runningTotal = 0;
  int _runningBackground = 0;

  bool get isDisposed => _disposed;

  /// Number of queued tasks waiting to start.
  int get pendingCount => _pendingQueue.length;

  /// Number of tasks currently executing.
  int get runningCount => _runningTotal;

  /// Unmodifiable snapshot of silent preload diagnostic logs.
  List<PreloadLogEntry> get recentLogs =>
      List<PreloadLogEntry>.unmodifiable(_logs);

  /// Stream of silent failure/diagnostic log entries.
  Stream<PreloadLogEntry> get logStream => _logController.stream;

  /// Fetches an active chapter at highest priority, reading from disk cache
  /// first when available and preempting any queued background preloads.
  Future<String> fetchActiveChapter({
    required Book book,
    required ChapterMeta chapter,
    CancellationToken? cancelToken,
  }) async {
    _ensureNotDisposed();
    cancelToken?.throwIfCancelled();

    final cachedText = await _readFromCacheIfPresent(book, chapter);
    if (cachedText != null) {
      cancelToken?.throwIfCancelled();
      return cachedText;
    }

    final text = await _enqueueOrAttach(
      book: book,
      chapter: chapter,
      priority: PreloadPriority.active,
      cancelToken: cancelToken,
      throwOnError: true,
    );
    return text ?? '';
  }

  /// Silently schedules `currentChapterIndex + 1 .. currentChapterIndex + lookAheadCount`
  /// for low-priority background caching, skipping already-cached chapters.
  ///
  /// Failures are logged silently and never throw to callers.
  Future<void> scheduleAhead({
    required Book book,
    required List<ChapterMeta> chapters,
    required int currentChapterIndex,
    int lookAheadCount = 3,
    CancellationToken? cancelToken,
  }) async {
    if (_disposed || chapters.isEmpty || lookAheadCount <= 0) return;
    if (cancelToken?.isCancelled ?? false) return;
    if (!_supportsOnlineCaching(book)) return;

    final startIdx = math.max(0, currentChapterIndex + 1);
    final endIdx = math.min(
      chapters.length - 1,
      currentChapterIndex + lookAheadCount,
    );
    if (startIdx > endIdx) {
      _cancelStaleAheadTasks(book.id, const <int>{});
      return;
    }

    final targetIndices = <int>{
      for (var i = startIdx; i <= endIdx; i++) chapters[i].chapterIndex,
    };
    _cancelStaleAheadTasks(book.id, targetIndices);

    final linkedToken = CancellationToken();
    _aheadTokensByBook[book.id] = linkedToken;

    void forwardCancel() => linkedToken.cancel();
    cancelToken?.addListener(forwardCancel);

    final futures = <Future<String?>>[];
    for (var i = startIdx; i <= endIdx; i++) {
      if (_disposed || linkedToken.isCancelled) break;
      final chapter = chapters[i];
      if (chapter.isCached) continue;

      final existingCached = await _readFromCacheIfPresent(book, chapter);
      if (existingCached != null) continue;
      if (_disposed || linkedToken.isCancelled) break;

      futures.add(
        _enqueueOrAttach(
          book: book,
          chapter: chapter,
          priority: PreloadPriority.ahead,
          cancelToken: linkedToken,
          throwOnError: false,
        ),
      );
    }

    try {
      await Future.wait<String?>(futures);
    } finally {
      cancelToken?.removeListener(forwardCancel);
      if (identical(_aheadTokensByBook[book.id], linkedToken)) {
        _aheadTokensByBook.remove(book.id);
      }
      linkedToken.dispose();
    }
  }

  /// Batch-caches chapters from [startChapterIndex] through [endChapterIndex]
  /// (inclusive) at medium ([PreloadPriority.batch]) priority.
  ///
  /// Already-cached chapters are skipped cleanly. Cancellation via [cancelToken]
  /// stops unstarted queued chapters immediately.
  Future<PreloadBatchResult> cacheRange({
    required Book book,
    required List<ChapterMeta> chapters,
    int startChapterIndex = 0,
    int? endChapterIndex,
    CancellationToken? cancelToken,
    void Function(PreloadBatchProgress progress)? onProgress,
  }) async {
    if (_disposed || chapters.isEmpty || !_supportsOnlineCaching(book)) {
      return const PreloadBatchResult(
        total: 0,
        cachedCount: 0,
        skippedCachedCount: 0,
        failedCount: 0,
      );
    }

    final start = startChapterIndex.clamp(0, chapters.length - 1);
    final end = (endChapterIndex ?? chapters.length - 1).clamp(
      start,
      chapters.length - 1,
    );
    final slice = chapters.sublist(start, end + 1);
    final total = slice.length;

    var completed = 0;
    var cachedCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    final failedIndices = <int>[];

    void emitProgress() {
      onProgress?.call(
        PreloadBatchProgress(
          total: total,
          completed: completed,
          cachedCount: cachedCount,
          skippedCachedCount: skippedCount,
          failedCount: failedCount,
          isCancelled: cancelToken?.isCancelled ?? false,
        ),
      );
    }

    emitProgress();

    final pendingTasks = <Future<void>>[];
    for (final chapter in slice) {
      if (_disposed || (cancelToken?.isCancelled ?? false)) {
        break;
      }

      if (chapter.isCached) {
        final existing = await _readFromCacheIfPresent(book, chapter);
        if (existing != null || chapter.isCached) {
          skippedCount++;
          completed++;
          emitProgress();
          continue;
        }
      } else {
        final existing = await _readFromCacheIfPresent(book, chapter);
        if (existing != null) {
          skippedCount++;
          completed++;
          emitProgress();
          continue;
        }
      }

      if (_disposed || (cancelToken?.isCancelled ?? false)) {
        break;
      }

      final taskFuture = _enqueueOrAttach(
        book: book,
        chapter: chapter,
        priority: PreloadPriority.batch,
        cancelToken: cancelToken,
        throwOnError: false,
      ).then((text) {
        if (_disposed || (cancelToken?.isCancelled ?? false)) {
          return;
        }
        if (text != null) {
          cachedCount++;
        } else {
          failedCount++;
          failedIndices.add(chapter.chapterIndex);
        }
        completed++;
        emitProgress();
      });
      pendingTasks.add(taskFuture);
    }

    if (pendingTasks.isNotEmpty) {
      await Future.wait<void>(pendingTasks);
    }

    final wasCancelled = cancelToken?.isCancelled ?? false;
    return PreloadBatchResult(
      total: total,
      cachedCount: cachedCount,
      skippedCachedCount: skippedCount,
      failedCount: failedCount,
      failedChapterIndices: List<int>.unmodifiable(failedIndices),
      cancelled: wasCancelled,
    );
  }

  /// Cancels all queued and in-flight ahead tasks for [bookId].
  void cancelBookTasks(String bookId) {
    _aheadTokensByBook.remove(bookId)?.cancel();
    final toCancel = _pendingQueue
        .where((task) => task.key.bookId == bookId)
        .toList(growable: false);
    for (final task in toCancel) {
      _cancelTaskCompletely(task);
    }
    for (final task in _inFlightByKey.values.toList(growable: false)) {
      if (task.key.bookId == bookId) {
        _cancelTaskCompletely(task);
      }
    }
  }

  /// Cancels all pending and in-flight preload tasks across all books.
  void cancelAll() {
    for (final token in _aheadTokensByBook.values.toList(growable: false)) {
      token.cancel();
    }
    _aheadTokensByBook.clear();
    for (final task in _pendingQueue.toList(growable: false)) {
      _cancelTaskCompletely(task);
    }
    for (final task in _inFlightByKey.values.toList(growable: false)) {
      _cancelTaskCompletely(task);
    }
  }

  /// Releases scheduler resources and cancels pending work.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelAll();
    if (!_logController.isClosed) {
      unawaited(_logController.close());
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const CancelledFailure(message: 'ChapterPreloadScheduler已释放');
    }
  }

  bool _supportsOnlineCaching(Book book) {
    if (book.providerType == ProviderType.localTxt ||
        book.providerType == ProviderType.localEpub) {
      return false;
    }
    return book.sourceId != null && book.sourceId!.isNotEmpty;
  }

  void _cancelStaleAheadTasks(String bookId, Set<int> keepIndices) {
    final prev = _aheadTokensByBook.remove(bookId);
    if (prev != null) {
      final stale = _pendingQueue
          .where(
            (task) =>
                task.key.bookId == bookId &&
                task.priority == PreloadPriority.ahead &&
                !keepIndices.contains(task.key.chapterIndex),
          )
          .toList(growable: false);
      for (final task in stale) {
        _cancelTaskCompletely(task);
      }
      if (keepIndices.isEmpty) {
        prev.cancel();
      }
    }
  }

  Future<String?> _readFromCacheIfPresent(
    Book book,
    ChapterMeta chapter,
  ) async {
    try {
      final cached = await _cacheGateway.readChapterText(
        book.id,
        chapter.chapterIndex,
      );
      if (cached != null && !chapter.isCached) {
        final cacheKey = _cacheGateway.buildCacheKey(
          book.id,
          chapter.chapterIndex,
        );
        unawaited(
          _markCachedQuietly(
            book.id,
            chapter.chapterIndex,
            cacheKey,
            wordCount: cached.length,
          ),
        );
      }
      return cached;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _enqueueOrAttach({
    required Book book,
    required ChapterMeta chapter,
    required PreloadPriority priority,
    required CancellationToken? cancelToken,
    required bool throwOnError,
  }) {
    if (_disposed) {
      return throwOnError
          ? Future<String?>.error(const CancelledFailure())
          : Future<String?>.value(null);
    }
    if (cancelToken?.isCancelled ?? false) {
      return throwOnError
          ? Future<String?>.error(const CancelledFailure())
          : Future<String?>.value(null);
    }

    final key = _ChapterTaskKey(book.id, chapter.chapterIndex);
    var task = _inFlightByKey[key] ?? _queuedByKey[key];
    if (task == null) {
      task = _QueuedChapterTask(
        key: key,
        book: book,
        chapter: chapter,
        priority: priority,
        sequence: _nextSequence++,
      );
      _queuedByKey[key] = task;
      _pendingQueue.add(task);
    } else if (priority.rank < task.priority.rank) {
      task.priority = priority;
    }

    final subscriber = _TaskSubscriber(
      throwOnError: throwOnError,
      cancelToken: cancelToken,
    );
    task.subscribers.add(subscriber);

    if (cancelToken != null) {
      final targetTask = task;
      void onCancelled() {
        _handleSubscriberCancelled(targetTask, subscriber);
      }

      subscriber.cancelListener = onCancelled;
      cancelToken.addListener(onCancelled);
    }

    _pumpQueue();
    return subscriber.completer.future;
  }

  void _handleSubscriberCancelled(
    _QueuedChapterTask task,
    _TaskSubscriber subscriber,
  ) {
    if (!subscriber.completer.isCompleted) {
      if (subscriber.throwOnError) {
        subscriber.completer.completeError(const CancelledFailure());
      } else {
        subscriber.completer.complete(null);
      }
    }

    final hasActiveSubscriber = task.subscribers.any(
      (sub) => !sub.completer.isCompleted,
    );
    if (!hasActiveSubscriber) {
      _cancelTaskCompletely(task);
    }
  }

  void _cancelTaskCompletely(_QueuedChapterTask task) {
    task.internalCancelToken.cancel();
    if (_pendingQueue.remove(task)) {
      _queuedByKey.remove(task.key);
    }
    for (final sub in task.subscribers) {
      sub.detachCancelListener();
      if (!sub.completer.isCompleted) {
        if (sub.throwOnError) {
          sub.completer.completeError(const CancelledFailure());
        } else {
          sub.completer.complete(null);
        }
      }
    }
  }

  void _pumpQueue() {
    if (_disposed) return;

    while (_pendingQueue.isNotEmpty && _runningTotal < _maxConcurrentTasks) {
      _pendingQueue.sort((a, b) {
        final pCmp = a.priority.rank.compareTo(b.priority.rank);
        if (pCmp != 0) return pCmp;
        return a.sequence.compareTo(b.sequence);
      });

      final next = _pendingQueue.first;
      final isBackground = next.priority != PreloadPriority.active;
      if (isBackground && _runningBackground >= _maxBackgroundTasks) {
        break;
      }

      _pendingQueue.removeAt(0);
      _queuedByKey.remove(next.key);
      _inFlightByKey[next.key] = next;
      _runningTotal++;
      if (isBackground) {
        _runningBackground++;
      }

      unawaited(_executeTask(next, isBackground: isBackground));
    }
  }

  Future<void> _executeTask(
    _QueuedChapterTask task, {
    required bool isBackground,
  }) async {
    try {
      task.internalCancelToken.throwIfCancelled();

      final cached = await _readFromCacheIfPresent(task.book, task.chapter);
      if (cached != null) {
        task.internalCancelToken.throwIfCancelled();
        _completeTaskSuccess(task, cached);
        return;
      }

      final sourceId = task.book.sourceId;
      if (sourceId == null || sourceId.isEmpty) {
        throw const SourceParseFailure(
          message: '书籍缺少书源标识，无法拉取在线章节',
          step: 'content',
        );
      }

      final source = await _sourceRepository.getSourceById(sourceId);
      task.internalCancelToken.throwIfCancelled();
      if (source == null) {
        throw SourceParseFailure(
          message: '找不到书源 ($sourceId)',
          sourceId: sourceId,
          step: 'content',
        );
      }

      final provider = await _providerFactory.createProvider(source);
      task.internalCancelToken.throwIfCancelled();

      final response = await provider.getChapterContent(
        task.chapter,
        cancelToken: task.internalCancelToken,
      );
      task.internalCancelToken.throwIfCancelled();

      final rawText = response.content.rawText;
      await _persistCacheQuietly(task.book.id, task.chapter, rawText);
      _completeTaskSuccess(task, rawText);
    } catch (error, stackTrace) {
      _completeTaskFailure(task, error, stackTrace);
    } finally {
      _inFlightByKey.remove(task.key);
      _runningTotal = math.max(0, _runningTotal - 1);
      if (isBackground) {
        _runningBackground = math.max(0, _runningBackground - 1);
      }
      if (!_disposed) {
        _pumpQueue();
      }
    }
  }

  Future<void> _persistCacheQuietly(
    String bookId,
    ChapterMeta chapter,
    String rawText,
  ) async {
    try {
      final cacheKey = await _cacheGateway.writeChapterText(
        bookId,
        chapter.chapterIndex,
        rawText,
      );
      await _markCachedQuietly(
        bookId,
        chapter.chapterIndex,
        cacheKey,
        wordCount: rawText.length,
      );
    } catch (error) {
      _recordSilentLog(
        bookId: bookId,
        chapterIndex: chapter.chapterIndex,
        priority: PreloadPriority.ahead,
        message: '写入章节缓存失败：$error',
        error: error,
      );
    }
  }

  Future<void> _markCachedQuietly(
    String bookId,
    int chapterIndex,
    String cacheKey, {
    required int wordCount,
  }) async {
    try {
      await _bookRepository.markChapterCached(
        bookId,
        chapterIndex,
        cacheKey,
        wordCount: wordCount,
      );
    } catch (_) {
      // Ignore metadata update failures when book is previewed or removed.
    }
  }

  void _completeTaskSuccess(_QueuedChapterTask task, String rawText) {
    for (final sub in task.subscribers) {
      sub.detachCancelListener();
      if (!sub.completer.isCompleted) {
        sub.completer.complete(rawText);
      }
    }
  }

  void _completeTaskFailure(
    _QueuedChapterTask task,
    Object error,
    StackTrace stackTrace,
  ) {
    final normalizedError = error is AppFailure
        ? error
        : NetworkFailure(
            message: '章节加载失败：$error',
            cause: error,
            stackTrace: stackTrace,
          );

    var hadSilentSubscriber = false;
    for (final sub in task.subscribers) {
      sub.detachCancelListener();
      if (sub.completer.isCompleted) continue;
      if (sub.throwOnError) {
        sub.completer.completeError(normalizedError, stackTrace);
      } else {
        hadSilentSubscriber = true;
        sub.completer.complete(null);
      }
    }

    if (hadSilentSubscriber && normalizedError is! CancelledFailure) {
      _recordSilentLog(
        bookId: task.book.id,
        chapterIndex: task.chapter.chapterIndex,
        priority: task.priority,
        message: normalizedError.message,
        error: normalizedError,
      );
    }
  }

  void _recordSilentLog({
    required String bookId,
    required int chapterIndex,
    required PreloadPriority priority,
    required String message,
    Object? error,
  }) {
    final entry = PreloadLogEntry(
      timestamp: DateTime.now().toUtc(),
      bookId: bookId,
      chapterIndex: chapterIndex,
      priority: priority,
      message: message,
      error: error,
    );
    if (_logs.length >= _maxLogEntries) {
      _logs.removeFirst();
    }
    _logs.addLast(entry);
    developer.log(
      '[Preload:${priority.name}] book=$bookId ch=$chapterIndex: $message',
      name: 'PureRead.ChapterPreloadScheduler',
      error: error,
    );
    if (!_disposed && !_logController.isClosed) {
      _logController.add(entry);
    }
  }
}

class _ChapterTaskKey {
  final String bookId;
  final int chapterIndex;

  const _ChapterTaskKey(this.bookId, this.chapterIndex);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ChapterTaskKey &&
          bookId == other.bookId &&
          chapterIndex == other.chapterIndex;

  @override
  int get hashCode => Object.hash(bookId, chapterIndex);
}

class _QueuedChapterTask {
  _QueuedChapterTask({
    required this.key,
    required this.book,
    required this.chapter,
    required this.priority,
    required this.sequence,
  });

  final _ChapterTaskKey key;
  final Book book;
  final ChapterMeta chapter;
  PreloadPriority priority;
  final int sequence;
  final CancellationToken internalCancelToken = CancellationToken();
  final List<_TaskSubscriber> subscribers = <_TaskSubscriber>[];
}

class _TaskSubscriber {
  _TaskSubscriber({required this.throwOnError, required this.cancelToken});

  final bool throwOnError;
  final CancellationToken? cancelToken;
  final Completer<String?> completer = Completer<String?>();
  void Function()? cancelListener;

  void detachCancelListener() {
    final listener = cancelListener;
    if (listener != null) {
      cancelToken?.removeListener(listener);
      cancelListener = null;
    }
  }
}
