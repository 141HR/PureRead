import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/application/reader/chapter_preload_scheduler.dart';
import 'package:pureread/domain/domain.dart';

class _FakeBookRepo implements BookRepository {
  final Map<String, List<ChapterMeta>> chaptersByBook =
      <String, List<ChapterMeta>>{};
  final List<({String bookId, int chapterIndex, String cacheKey, int? wordCount})>
      markedCached =
      <({String bookId, int chapterIndex, String cacheKey, int? wordCount})>[];

  @override
  Stream<List<Book>> watchBooks({String? groupId}) =>
      const Stream<List<Book>>.empty();

  @override
  Future<List<Book>> listBooks({String? groupId}) async => const <Book>[];

  @override
  Future<Book?> getBookById(String bookId) async => null;

  @override
  Future<Book?> findBySourceAndUrl(
    String sourceId,
    String originBookUrl,
  ) async => null;

  @override
  Future<void> saveBook(Book book) async {}

  @override
  Future<void> deleteBook(String bookId) async {}

  @override
  Future<List<BookGroup>> listGroups() async => const <BookGroup>[];

  @override
  Future<void> saveGroup(BookGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<List<ChapterMeta>> listChapters(String bookId) async =>
      chaptersByBook[bookId] ?? const <ChapterMeta>[];

  @override
  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex) async => null;

  @override
  Future<void> replaceChapters(String bookId, List<ChapterMeta> chapters) async {
    chaptersByBook[bookId] = chapters;
  }

  @override
  Future<void> markChapterCached(
    String bookId,
    int chapterIndex,
    String cacheKey, {
    int? wordCount,
  }) async {
    markedCached.add((
      bookId: bookId,
      chapterIndex: chapterIndex,
      cacheKey: cacheKey,
      wordCount: wordCount,
    ));
  }

  @override
  Future<ReadingProgress?> getProgress(String bookId) async => null;

  @override
  Future<void> saveProgress(ReadingProgress progress) async {}

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async =>
      const <Bookmark>[];

  @override
  Future<void> saveBookmark(Bookmark bookmark) async {}

  @override
  Future<void> deleteBookmark(String bookmarkId) async {}
}

class _FakeSourceRepo implements SourceRepository {
  final Map<String, BookSource> sources = <String, BookSource>{};

  @override
  Stream<List<BookSource>> watchSources() =>
      Stream<List<BookSource>>.value(sources.values.toList(growable: false));

  @override
  Future<List<BookSource>> listSources({bool enabledOnly = false}) async =>
      sources.values.toList(growable: false);

  @override
  Future<BookSource?> getSourceById(String sourceId) async => sources[sourceId];

  @override
  Future<void> saveSource(BookSource source) async {
    sources[source.id] = source;
  }

  @override
  Future<void> saveSources(List<BookSource> list) async {
    for (final s in list) {
      sources[s.id] = s;
    }
  }

  @override
  Future<void> deleteSource(String sourceId) async {
    sources.remove(sourceId);
  }

  @override
  Future<List<ReplaceRule>> listReplaceRules({
    bool enabledOnly = false,
    String? sourceId,
    String? bookId,
  }) async => const <ReplaceRule>[];

  @override
  Future<void> saveReplaceRule(ReplaceRule rule) async {}

  @override
  Future<void> deleteReplaceRule(String ruleId) async {}
}

class _FakeCacheGateway implements ChapterCacheGateway {
  final Map<String, String> files = <String, String>{};

  @override
  String buildCacheKey(String bookId, int chapterIndex) =>
      '$bookId/$chapterIndex.txt';

  @override
  Future<String?> readChapterText(String bookId, int chapterIndex) async =>
      files[buildCacheKey(bookId, chapterIndex)];

  @override
  Future<String> writeChapterText(
    String bookId,
    int chapterIndex,
    String rawText,
  ) async {
    final key = buildCacheKey(bookId, chapterIndex);
    files[key] = rawText;
    return key;
  }

  @override
  Future<void> deleteBookCache(String bookId) async {
    files.removeWhere((k, _) => k.startsWith('$bookId/'));
  }

  @override
  Future<int> getTotalCacheBytes() async => 0;

  @override
  Future<void> clearAllCache() async => files.clear();
}

typedef _ContentHandler = Future<String> Function(
  ChapterMeta chapter,
  CancellationToken? cancelToken,
);

class _FakeBookProvider implements BookProvider {
  _FakeBookProvider(this.providerId, this._handler);

  @override
  final String providerId;

  final _ContentHandler _handler;
  final List<int> requestedIndices = <int>[];

  @override
  ProviderType get type => ProviderType.legado;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    isLocal: false,
    supportsSearch: true,
    supportsUpdateCheck: true,
    supportsChangeSource: true,
  );

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    requestedIndices.add(chapter.chapterIndex);
    final text = await _handler(chapter, cancelToken);
    cancelToken?.throwIfCancelled();
    return (
      content: ChapterContent(
        chapterIndex: chapter.chapterIndex,
        title: chapter.title,
        rawText: text,
        sourceUrl: chapter.url,
        fetchedAt: DateTime.utc(2026, 11, 24),
      ),
      trace: const SourceDebugTrace(step: 'content', elapsedMs: 5, httpStatus: 200),
    );
  }
}

class _FakeFactoryGateway implements BookProviderFactoryGateway {
  _FakeFactoryGateway(this._provider);

  final BookProvider _provider;

  @override
  BookProvider createProvider(BookSource source) => _provider;
}

void main() {
  group('ChapterPreloadScheduler', () {
    late _FakeBookRepo bookRepo;
    late _FakeSourceRepo sourceRepo;
    late _FakeCacheGateway cacheGateway;
    late Book book;
    late List<ChapterMeta> chapters;

    setUp(() {
      final now = DateTime.utc(2026, 11, 24);
      bookRepo = _FakeBookRepo();
      sourceRepo = _FakeSourceRepo();
      cacheGateway = _FakeCacheGateway();

      sourceRepo.sources['s1'] = BookSource(
        id: 's1',
        name: '测试源1',
        engineType: SourceEngineType.legado,
        baseUrl: 'https://example.com',
        rawDefinition: '{}',
        createdAt: now,
        updatedAt: now,
      );

      book = Book(
        id: 'book_1',
        sourceId: 's1',
        providerType: ProviderType.legado,
        originBookUrl: 'https://example.com/book/1',
        title: '凡人修仙传',
        totalChapters: 8,
        createdAt: now,
        updatedAt: now,
      );

      chapters = List<ChapterMeta>.generate(
        8,
        (i) => ChapterMeta(
          bookId: 'book_1',
          chapterIndex: i,
          title: '第${i + 1}章',
          url: 'https://example.com/book/1/$i',
          updatedAt: now,
        ),
      );
    });

    test('active fetch preempts queued N+1..N+3 preloads', () async {
      final ch1Gate = Completer<String>();
      final provider = _FakeBookProvider('s1', (chapter, token) async {
        if (chapter.chapterIndex == 1) {
          return ch1Gate.future;
        }
        return '正文-${chapter.chapterIndex}';
      });

      final scheduler = ChapterPreloadScheduler(
        bookRepository: bookRepo,
        sourceRepository: sourceRepo,
        providerFactory: _FakeFactoryGateway(provider),
        cacheGateway: cacheGateway,
        maxConcurrentTasks: 1,
        maxBackgroundTasks: 1,
      );
      addTearDown(scheduler.dispose);

      // Start silent ahead preload for chapter 0 -> queues 1, 2, 3.
      final aheadFuture = scheduler.scheduleAhead(
        book: book,
        chapters: chapters,
        currentChapterIndex: 0,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.requestedIndices, <int>[1]);

      // Active user jumps to chapter 5 -> must preempt chapters 2 and 3.
      final activeFuture = scheduler.fetchActiveChapter(
        book: book,
        chapter: chapters[5],
      );
      ch1Gate.complete('正文-1');

      expect(await activeFuture, '正文-5');
      await aheadFuture;

      expect(provider.requestedIndices, <int>[1, 5, 2, 3]);
      expect(cacheGateway.files['book_1/5.txt'], '正文-5');
      expect(cacheGateway.files['book_1/2.txt'], '正文-2');
      expect(cacheGateway.files['book_1/3.txt'], '正文-3');
    });

    test('scheduleAhead skips already-cached chapters and logs errors silently', () async {
      chapters[1] = chapters[1].copyWith(isCached: true, cacheKey: 'book_1/1.txt');
      cacheGateway.files['book_1/1.txt'] = 'cached-1';

      final provider = _FakeBookProvider('s1', (chapter, token) async {
        if (chapter.chapterIndex == 2) {
          throw const NetworkFailure(
            message: '模拟 502 错误',
            statusCode: 502,
          );
        }
        return '正文-${chapter.chapterIndex}';
      });

      final scheduler = ChapterPreloadScheduler(
        bookRepository: bookRepo,
        sourceRepository: sourceRepo,
        providerFactory: _FakeFactoryGateway(provider),
        cacheGateway: cacheGateway,
      );
      addTearDown(scheduler.dispose);

      // Must complete without throwing despite chapter 2 failing.
      await scheduler.scheduleAhead(
        book: book,
        chapters: chapters,
        currentChapterIndex: 0,
      );

      expect(provider.requestedIndices, <int>[2, 3]);
      expect(cacheGateway.files['book_1/3.txt'], '正文-3');
      expect(scheduler.recentLogs.length, 1);
      expect(scheduler.recentLogs.single.chapterIndex, 2);
      expect(scheduler.recentLogs.single.message, contains('502'));
    });

    test('cacheRange caches range, skips cached items, and respects CancellationToken', () async {
      chapters[0] = chapters[0].copyWith(isCached: true, cacheKey: 'book_1/0.txt');
      cacheGateway.files['book_1/0.txt'] = 'cached-0';

      final ch1Gate = Completer<String>();
      final provider = _FakeBookProvider('s1', (chapter, token) async {
        if (chapter.chapterIndex == 1) {
          return ch1Gate.future;
        }
        return '正文-${chapter.chapterIndex}';
      });

      final scheduler = ChapterPreloadScheduler(
        bookRepository: bookRepo,
        sourceRepository: sourceRepo,
        providerFactory: _FakeFactoryGateway(provider),
        cacheGateway: cacheGateway,
        maxConcurrentTasks: 1,
        maxBackgroundTasks: 1,
      );
      addTearDown(scheduler.dispose);

      final cancelToken = CancellationToken();
      final progressEvents = <PreloadBatchProgress>[];

      final rangeFuture = scheduler.cacheRange(
        book: book,
        chapters: chapters,
        startChapterIndex: 0,
        endChapterIndex: 4,
        cancelToken: cancelToken,
        onProgress: progressEvents.add,
      );

      await Future<void>.delayed(Duration.zero);
      // Chapter 0 was skipped; chapter 1 is running.
      expect(provider.requestedIndices, <int>[1]);

      // Cancel remaining queued chapters (2, 3, 4) before completing ch1.
      cancelToken.cancel();
      ch1Gate.complete('正文-1');

      final summary = await rangeFuture;
      expect(summary.cancelled, isTrue);
      expect(summary.skippedCachedCount, 1);
      expect(provider.requestedIndices, <int>[1]);
      expect(progressEvents, isNotEmpty);
    });
  });
}
