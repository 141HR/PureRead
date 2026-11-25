import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../../infrastructure/platform/platform_bridge.dart';
import '../bookshelf/local_epub_providers.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import '../search/change_source_state.dart';
import 'chapter_preload_scheduler.dart';
import 'local_epub_reader_provider.dart';
import 'reader_session_state.dart';
import 'reader_theme_x.dart';

const String _kActiveThemeKey = 'active_theme_id';
const String _kKeepScreenOnKey = 'reader_keep_screen_on';
const String _kVolumeKeyPagingKey = 'reader_volume_key_paging';
const String _kSafeAreaEnabledKey = 'reader_safe_area_enabled';

const double kDualColumnBreakpoint = 840.0;
const double kReaderColumnGap = 32.0;

final readerSessionControllerProvider = NotifierProvider.autoDispose
    .family<ReaderSessionController, ReaderSessionState, String>(
      ReaderSessionController.new,
    );

/// Session controller managing chapter loading, session-stable `anchorOffset`
/// preservation across repaginations, adjacent-chapter page caching,
/// debounced/immediate progress persistence, jump-undo history, bookmarks,
/// typography/themes, custom font import, and platform hardware controls.
class ReaderSessionController extends Notifier<ReaderSessionState> {
  ReaderSessionController(this.bookId);

  final String bookId;

  bool _disposed = false;
  bool _initialized = false;
  Timer? _saveDebounceTimer;
  Timer? _resizeDebounceTimer;
  StreamSubscription<VolumeKeyDirection>? _volumeSub;

  Size? _viewportSize;
  int _sessionEpoch = 0;
  int _layoutEpoch = 0;
  int _sourceEpoch = 0;
  late ReaderSessionState _snapshot;
  ChapterPreloadScheduler? _preloadScheduler;
  CancellationToken? _batchCacheCancelToken;

  final Map<int, String> _chapterTextCache = <int, String>{};
  final Map<int, Future<String>> _inFlightChapterLoads = <int, Future<String>>{};
  final Map<int, List<PageSlice>> _chapterPagesCache = <int, List<PageSlice>>{};
  PaginationConfig? _cachedPagesConfig;

  bool get _isAlive => !_disposed && ref.mounted;

  static bool _isOnlineBook(Book book) =>
      book.providerType == ProviderType.jsPlugin ||
      book.providerType == ProviderType.legado;

  ChapterPreloadScheduler _ensurePreloadScheduler() {
    final existing = _preloadScheduler;
    if (existing != null) return existing;
    final created = ref.read(chapterPreloadSchedulerProvider);
    _preloadScheduler = created;
    return created;
  }

  Future<List<ChapterMeta>> _fetchAndPersistOnlineToc({
    required Book book,
    required BookRepository bookRepo,
  }) async {
    final sourceId = book.sourceId?.trim() ?? '';
    if (sourceId.isEmpty) return const <ChapterMeta>[];
    final sourceRepo = ref.read(sourceRepositoryProvider);
    final providerFactory = ref.read(bookProviderFactoryProvider);
    final source = await sourceRepo.getSourceById(sourceId);
    if (!_isAlive || source == null) return const <ChapterMeta>[];
    final provider = await providerFactory.createProvider(source);
    if (!_isAlive) return const <ChapterMeta>[];

    var tocUrl = book.tocUrl?.trim() ?? '';
    if (tocUrl.isEmpty) {
      final originUrl = book.originBookUrl?.trim() ?? '';
      if (originUrl.isEmpty) return const <ChapterMeta>[];
      try {
        final detailRes = await provider.getBookDetail(originUrl);
        if (!_isAlive) return const <ChapterMeta>[];
        tocUrl = detailRes.detail.tocUrl.trim().isNotEmpty
            ? detailRes.detail.tocUrl.trim()
            : originUrl;
      } catch (_) {
        tocUrl = originUrl;
      }
    }

    final tocRes = await provider.getToc(tocUrl);
    if (!_isAlive) return const <ChapterMeta>[];
    final now = DateTime.now().toUtc();
    final normalized = tocRes.chapters
        .asMap()
        .entries
        .map(
          (entry) => entry.value.copyWith(
            bookId: book.id,
            chapterIndex: entry.key,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    if (normalized.isNotEmpty) {
      await bookRepo.replaceChapters(book.id, normalized);
    }
    return normalized;
  }

  Future<List<ChapterMeta>> _rebuildAndPersistLocalEpubToc({
    required Book book,
    required BookRepository bookRepo,
  }) async {
    final filePath = book.localFilePath?.trim() ?? '';
    if (filePath.isEmpty) return const <ChapterMeta>[];
    final epubImporter = ref.read(epubBookImporterProvider);
    final imported = await epubImporter(filePath);
    if (!_isAlive) return const <ChapterMeta>[];
    final now = DateTime.now().toUtc();
    final normalized = imported.chapters
        .asMap()
        .entries
        .map(
          (entry) => entry.value.copyWith(
            bookId: book.id,
            chapterIndex: entry.key,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    if (normalized.isNotEmpty) {
      await bookRepo.replaceChapters(book.id, normalized);
    }
    return normalized;
  }

  void _commit(ReaderSessionState next) {
    if (!_isAlive) return;
    _snapshot = next;
    state = next;
  }

  @override
  ReaderSessionState build() {
    _disposed = false;
    _initialized = false;
    _sessionEpoch = 0;
    _layoutEpoch = 0;
    _sourceEpoch = 0;
    _viewportSize = null;
    _preloadScheduler = null;
    _batchCacheCancelToken?.cancel();
    _batchCacheCancelToken = null;
    _chapterTextCache.clear();
    _inFlightChapterLoads.clear();
    _chapterPagesCache.clear();
    _cachedPagesConfig = null;

    final bookRepo = ref.read(bookRepositoryProvider);
    final platform = ref.read(platformBridgeProvider);
    final defaultTheme = buildDefaultReaderThemes().first;

    final initial = ReaderSessionState(
      bookId: bookId,
      isLoading: true,
      activeTheme: defaultTheme,
    );
    _snapshot = initial;

    ref.onDispose(() {
      _disposed = true;
      _saveDebounceTimer?.cancel();
      _saveDebounceTimer = null;
      _resizeDebounceTimer?.cancel();
      _resizeDebounceTimer = null;
      _batchCacheCancelToken?.cancel();
      _batchCacheCancelToken = null;
      unawaited(_volumeSub?.cancel());
      _volumeSub = null;
      _inFlightChapterLoads.clear();

      // Read cached plain-Dart snapshot rather than Riverpod `state`/`ref`
      // inside `onDispose` to comply with Riverpod 3 lifecycle assertions.
      final snap = _snapshot;
      if (snap.book != null) {
        if (_isOnlineBook(snap.book!)) {
          _preloadScheduler?.cancelBookTasks(snap.book!.id);
        }
        unawaited(
          _persistProgressSnapshot(
            bookRepo: bookRepo,
            book: snap.book!,
            chapterIndex: snap.currentChapterIndex,
            charOffset: snap.anchorOffset,
            chapterTitle: snap.currentChapterTitle,
            progressPercent: snap.overallProgressPercent,
          ),
        );
      }

      // Restore system defaults when leaving reader (PRD F3.4).
      if (snap.keepScreenOn) {
        unawaited(platform.setKeepScreenOn(false));
      }
      if (snap.volumeKeyPaging) {
        unawaited(platform.setVolumeKeyPaging(false));
      }
      if (snap.isImmersive) {
        unawaited(platform.setImmersiveMode(false));
      }
    });

    Future<void>.microtask(_initialize);

    return initial;
  }

  Future<void> _initialize() async {
    if (!_isAlive || _initialized) return;
    _initialized = true;

    final themeRepo = ref.read(themeRepositoryProvider);
    final bookRepo = ref.read(bookRepositoryProvider);
    final platform = ref.read(platformBridgeProvider);
    final fontGateway = ref.read(fontLoaderGatewayProvider);

    var themes = buildDefaultReaderThemes();
    var activeTheme = themes.first;
    var keepScreenOn = false;
    var volumeKeyPaging = false;
    var safeAreaEnabled = true;

    try {
      final storedThemes = await themeRepo.listThemes();
      if (!_isAlive) return;
      if (storedThemes.isNotEmpty) {
        themes = storedThemes;
      }
      final activeThemeSetting = await themeRepo.getSetting(_kActiveThemeKey);
      if (!_isAlive) return;
      if (activeThemeSetting != null) {
        activeTheme = themes.firstWhere(
          (t) => t.id == activeThemeSetting.value,
          orElse: () => themes.first,
        );
      } else {
        activeTheme = themes.first;
      }

      final keepSetting = await themeRepo.getSetting(_kKeepScreenOnKey);
      if (!_isAlive) return;
      keepScreenOn = keepSetting?.value == 'true';

      final volSetting = await themeRepo.getSetting(_kVolumeKeyPagingKey);
      if (!_isAlive) return;
      volumeKeyPaging = volSetting?.value == 'true';

      final safeSetting = await themeRepo.getSetting(_kSafeAreaEnabledKey);
      if (!_isAlive) return;
      if (safeSetting != null) {
        safeAreaEnabled = safeSetting.value != 'false';
      }
    } catch (_) {
      // Keep default themes/preferences on storage error.
    }

    if (!_isAlive) return;

    if (activeTheme.fontPath != null && activeTheme.fontPath!.isNotEmpty) {
      try {
        await fontGateway.ensureFontLoaded(
          activeTheme.fontFamily,
          activeTheme.fontPath,
        );
      } catch (_) {
        // Fallback silently to system font if custom font file is unavailable.
      }
    }

    if (!_isAlive) return;

    await _volumeSub?.cancel();
    if (!_isAlive) return;
    _volumeSub = platform.volumeKeyEvents.listen((direction) {
      if (!_isAlive || !state.volumeKeyPaging) return;
      if (direction == VolumeKeyDirection.up) {
        unawaited(prevPage());
      } else {
        unawaited(nextPage());
      }
    });

    if (keepScreenOn) {
      await platform.setKeepScreenOn(true);
      if (!_isAlive) return;
    }
    if (volumeKeyPaging) {
      await platform.setVolumeKeyPaging(true);
      if (!_isAlive) return;
    }

    try {
      final loadedBook = await bookRepo.getBookById(bookId);
      if (!_isAlive) return;

      if (loadedBook == null) {
        _commit(
          state.copyWith(
            isLoading: false,
            availableThemes: themes,
            activeTheme: activeTheme,
            keepScreenOn: keepScreenOn,
            volumeKeyPaging: volumeKeyPaging,
            safeAreaEnabled: safeAreaEnabled,
            errorMessage: '未找到指定书籍 ($bookId)。',
          ),
        );
        return;
      }

      var effectiveBook = loadedBook;
      if (_isOnlineBook(loadedBook)) {
        _ensurePreloadScheduler();
      }
      if (loadedBook.unreadCount > 0) {
        effectiveBook = loadedBook.copyWith(
          unreadCount: 0,
          updatedAt: DateTime.now().toUtc(),
        );
        try {
          await bookRepo.saveBook(effectiveBook);
        } catch (_) {
          // Non-critical unread count reset failure.
        }
        if (!_isAlive) return;
      }

      var chapters = await bookRepo.listChapters(bookId);
      if (!_isAlive) return;
      if (chapters.isEmpty && _isOnlineBook(effectiveBook)) {
        chapters = await _fetchAndPersistOnlineToc(
          book: effectiveBook,
          bookRepo: bookRepo,
        );
        if (!_isAlive) return;
      } else if (chapters.isEmpty &&
          effectiveBook.providerType == ProviderType.localEpub) {
        chapters = await _rebuildAndPersistLocalEpubToc(
          book: effectiveBook,
          bookRepo: bookRepo,
        );
        if (!_isAlive) return;
      }
      final progress = await bookRepo.getProgress(bookId);
      if (!_isAlive) return;
      final bookmarks = await bookRepo.listBookmarks(bookId);
      if (!_isAlive) return;

      final initialChapter = chapters.isEmpty
          ? 0
          : (progress?.chapterIndex ?? 0).clamp(0, chapters.length - 1);
      final initialOffset = math.max(0, progress?.charOffset ?? 0);

      _commit(
        state.copyWith(
          isLoading: false,
          book: effectiveBook,
          chapters: chapters,
          currentChapterIndex: initialChapter,
          anchorOffset: initialOffset,
          availableThemes: themes,
          activeTheme: activeTheme,
          bookmarks: bookmarks,
          keepScreenOn: keepScreenOn,
          volumeKeyPaging: volumeKeyPaging,
          safeAreaEnabled: safeAreaEnabled,
        ),
      );

      if (chapters.isNotEmpty) {
        await _loadChapterAndPaginate(
          chapterIndex: initialChapter,
          targetCharOffset: initialOffset,
          landAtEnd: false,
          preserveAnchor: true,
        );
      }
    } catch (error) {
      if (!_isAlive) return;
      _commit(
        state.copyWith(
          isLoading: false,
          availableThemes: themes,
          activeTheme: activeTheme,
          errorMessage: _formatError(error),
        ),
      );
    }
  }

  /// Updates the reader canvas viewport dimensions.
  ///
  /// The very first layout applies immediately; subsequent live window resizes
  /// use a `~40ms` debounce when [debounce] is true, always preserving
  /// `state.anchorOffset` without overwriting it.
  void updateViewportSize(Size size, {bool debounce = true}) {
    if (!_isAlive || size.width <= 0 || size.height <= 0) return;
    final previous = _viewportSize;
    if (previous != null &&
        (previous.width - size.width).abs() < 0.5 &&
        (previous.height - size.height).abs() < 0.5) {
      return;
    }

    _viewportSize = size;
    if (previous == null || !debounce || state.paginationConfig == null) {
      _resizeDebounceTimer?.cancel();
      unawaited(_repaginateCurrentChapterPreservingAnchor());
      return;
    }

    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 40), () {
      if (_isAlive) {
        unawaited(_repaginateCurrentChapterPreservingAnchor());
      }
    });
  }

  /// Resolves [PaginationConfig] and column count for [viewportSize] and
  /// [theme].
  static ({PaginationConfig config, int columnCount}) resolveLayoutConfig(
    Size viewportSize,
    ReaderTheme theme,
  ) {
    final marginH = theme.marginHorizontal.clamp(8.0, 80.0);
    final marginV = theme.marginVertical.clamp(4.0, 64.0);
    final availableWidth = math.max(120.0, viewportSize.width - marginH * 2);
    final availableHeight = math.max(100.0, viewportSize.height - marginV * 2);

    final columnCount = switch (theme.columnMode) {
      ColumnMode.single => 1,
      ColumnMode.double => 2,
      ColumnMode.auto => viewportSize.width >= kDualColumnBreakpoint ? 2 : 1,
    };

    final double logicalWidth;
    if (columnCount == 2) {
      final maxSpreadWidth = theme.maxContentWidth * 2 + kReaderColumnGap;
      final spreadWidth = math.min(availableWidth, maxSpreadWidth);
      logicalWidth = math.max(80.0, (spreadWidth - kReaderColumnGap) / 2);
    } else {
      logicalWidth = math.max(
        80.0,
        math.min(availableWidth, theme.maxContentWidth),
      );
    }

    final config = theme.toPaginationConfig(
      columnWidth: logicalWidth,
      columnHeight: availableHeight,
      columnCount: columnCount,
      columnGap: kReaderColumnGap,
    );
    return (config: config, columnCount: columnCount);
  }

  Future<void> _repaginateCurrentChapterPreservingAnchor() async {
    if (!_isAlive || _viewportSize == null) return;
    if (state.chapters.isEmpty) return;
    // If initial chapter load is already in flight and has not resolved text yet,
    // let `_loadChapterAndPaginate` pick up the updated `_viewportSize` on completion
    // rather than triggering a duplicate concurrent isolate read.
    if (state.isPaginating && state.currentChapterText.isEmpty) return;

    final resolved = resolveLayoutConfig(_viewportSize!, state.activeTheme);
    final newConfig = resolved.config;
    if (newConfig == state.paginationConfig &&
        state.currentPages.isNotEmpty &&
        state.currentChapterText.isNotEmpty) {
      return;
    }

    final layoutEpoch = ++_layoutEpoch;
    if (_cachedPagesConfig != newConfig) {
      _chapterPagesCache.clear();
      _cachedPagesConfig = newConfig;
    }

    // Never mutate state.anchorOffset here! Always anchor from state.anchorOffset.
    final anchor = state.anchorOffset;
    final chapterIdx = state.currentChapterIndex;
    final text = state.currentChapterText.isNotEmpty
        ? state.currentChapterText
        : await _getOrLoadChapterText(chapterIdx, schedulePreload: false);
    if (!_isAlive || layoutEpoch != _layoutEpoch) return;

    final pages = await _paginateChapterCached(
      chapterIndex: chapterIdx,
      sanitizedText: text,
      config: newConfig,
      priorityCharOffset: anchor,
      layoutEpoch: layoutEpoch,
    );
    if (!_isAlive || layoutEpoch != _layoutEpoch) return;

    final pageIdx = findPageIndexByCharOffset(pages, anchor);
    final displayIdx = _alignPageIndex(pageIdx, resolved.columnCount);

    _commit(
      state.copyWith(
        currentChapterText: text,
        currentPages: pages,
        currentPageIndex: displayIdx,
        columnCount: resolved.columnCount,
        paginationConfig: newConfig,
        isPaginating: false,
        clearError: true,
      ),
    );

    unawaited(_prewarmAdjacentChapters(chapterIdx, newConfig, layoutEpoch));
  }

  Future<void> _loadChapterAndPaginate({
    required int chapterIndex,
    required int targetCharOffset,
    required bool landAtEnd,
    required bool preserveAnchor,
  }) async {
    if (!_isAlive || state.chapters.isEmpty) return;
    final clampedChapter = chapterIndex.clamp(0, state.chapters.length - 1);
    final sessionEpoch = ++_sessionEpoch;
    final layoutEpoch = _layoutEpoch;

    _commit(state.copyWith(isPaginating: true, clearError: true));

    try {
      final text = await _getOrLoadChapterText(clampedChapter);
      if (!_isAlive || sessionEpoch != _sessionEpoch) return;

      final clampedOffset = text.isEmpty
          ? 0
          : targetCharOffset.clamp(0, text.length - 1);

      final viewport = _viewportSize;
      if (viewport == null) {
        _commit(
          state.copyWith(
            currentChapterIndex: clampedChapter,
            currentChapterText: text,
            anchorOffset: preserveAnchor ? state.anchorOffset : clampedOffset,
            isPaginating: false,
          ),
        );
        return;
      }

      final resolved = resolveLayoutConfig(viewport, state.activeTheme);
      final config = resolved.config;
      if (_cachedPagesConfig != config) {
        _chapterPagesCache.clear();
        _cachedPagesConfig = config;
      }

      final pages = await _paginateChapterCached(
        chapterIndex: clampedChapter,
        sanitizedText: text,
        config: config,
        priorityCharOffset: landAtEnd ? null : clampedOffset,
        layoutEpoch: layoutEpoch,
      );
      if (!_isAlive || sessionEpoch != _sessionEpoch) return;

      final int rawPageIdx;
      if (landAtEnd) {
        rawPageIdx = pages.isEmpty ? 0 : pages.length - 1;
      } else {
        rawPageIdx = findPageIndexByCharOffset(pages, clampedOffset);
      }
      final displayIdx = _alignPageIndex(rawPageIdx, resolved.columnCount);
      final resolvedAnchor = preserveAnchor
          ? state.anchorOffset
          : (landAtEnd && pages.isNotEmpty
                ? pages[displayIdx].startCharOffset
                : clampedOffset);

      _commit(
        state.copyWith(
          currentChapterIndex: clampedChapter,
          currentChapterText: text,
          currentPages: pages,
          currentPageIndex: displayIdx,
          anchorOffset: resolvedAnchor,
          columnCount: resolved.columnCount,
          paginationConfig: config,
          isPaginating: false,
          clearError: true,
        ),
      );

      unawaited(_prewarmAdjacentChapters(clampedChapter, config, layoutEpoch));
    } catch (error) {
      if (!_isAlive || sessionEpoch != _sessionEpoch) return;
      _commit(
        state.copyWith(
          isPaginating: false,
          errorMessage: _formatError(error),
        ),
      );
    }
  }

  Future<String> _getOrLoadChapterText(
    int chapterIndex, {
    bool schedulePreload = true,
  }) {
    if (!_isAlive) return Future<String>.value('');
    final cached = _chapterTextCache[chapterIndex];
    if (cached != null) {
      if (schedulePreload) {
        _scheduleOnlineAheadIfNeeded(chapterIndex);
      }
      return Future<String>.value(cached);
    }

    final inFlight = _inFlightChapterLoads[chapterIndex];
    if (inFlight != null) {
      if (schedulePreload) {
        _scheduleOnlineAheadIfNeeded(chapterIndex);
      }
      return inFlight;
    }

    final future = _fetchAndSanitizeChapter(
      chapterIndex,
      schedulePreload: schedulePreload,
    );
    _inFlightChapterLoads[chapterIndex] = future;
    return future.whenComplete(() {
      if (identical(_inFlightChapterLoads[chapterIndex], future)) {
        _inFlightChapterLoads.remove(chapterIndex);
      }
    });
  }

  void _scheduleOnlineAheadIfNeeded(int chapterIndex) {
    if (!_isAlive) return;
    final book = state.book;
    final chapters = state.chapters;
    if (book == null || !_isOnlineBook(book) || chapters.isEmpty) return;
    if (chapterIndex < 0 || chapterIndex >= chapters.length) return;
    final scheduler = _ensurePreloadScheduler();
    unawaited(
      scheduler.scheduleAhead(
        book: book,
        chapters: chapters,
        currentChapterIndex: chapterIndex,
      ),
    );
  }

  Future<String> _fetchAndSanitizeChapter(
    int chapterIndex, {
    bool schedulePreload = true,
  }) async {
    if (!_isAlive) return '';

    final sourceEpoch = _sourceEpoch;
    final sanitizer = ref.read(contentSanitizerProvider);
    final book = state.book;
    final chapters = state.chapters;

    if (book == null ||
        chapterIndex < 0 ||
        chapterIndex >= chapters.length) {
      return '';
    }
    final chapter = chapters[chapterIndex];
    final chapterTitle = chapter.title;
    final String rawText;
    switch (book.providerType) {
      case ProviderType.localTxt:
        final localTxtReader = ref.read(localTxtChapterReaderProvider);
        rawText = await localTxtReader(book, chapter);
      case ProviderType.localEpub:
        final localEpubReader = ref.read(localEpubChapterReaderProvider);
        rawText = await localEpubReader(
          book,
          chapter,
          chapters: chapters,
        );
      case ProviderType.jsPlugin:
      case ProviderType.legado:
        final scheduler = _ensurePreloadScheduler();
        rawText = await scheduler.fetchActiveChapter(
          book: book,
          chapter: chapter,
        );
        if (!_isAlive || sourceEpoch != _sourceEpoch) return '';
        if (schedulePreload) {
          unawaited(
            scheduler.scheduleAhead(
              book: book,
              chapters: chapters,
              currentChapterIndex: chapterIndex,
            ),
          );
        }
    }
    if (!_isAlive || sourceEpoch != _sourceEpoch) return '';

    final sanitized = await sanitizer.sanitize(
      rawText,
      SanitizeContext(
        bookId: bookId,
        sourceId: book.sourceId,
        chapterTitle: chapterTitle,
      ),
    );
    if (!_isAlive || sourceEpoch != _sourceEpoch) return '';
    _chapterTextCache[chapterIndex] = sanitized;
    return sanitized;
  }

  Future<List<PageSlice>> _paginateChapterCached({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    required int? priorityCharOffset,
    required int layoutEpoch,
  }) async {
    if (!_isAlive) return const <PageSlice>[];
    if (_cachedPagesConfig == config) {
      final cached = _chapterPagesCache[chapterIndex];
      if (cached != null) return cached;
    }

    final paginator = ref.read(readerPaginatorProvider);
    final pages = await paginator.paginateChapter(
      chapterIndex: chapterIndex,
      sanitizedText: sanitizedText,
      config: config,
      priorityCharOffset: priorityCharOffset,
    );

    if (_isAlive && layoutEpoch == _layoutEpoch) {
      if (_cachedPagesConfig != config) {
        _chapterPagesCache.clear();
        _cachedPagesConfig = config;
      }
      _chapterPagesCache[chapterIndex] = pages;
    }
    return pages;
  }

  Future<void> _prewarmAdjacentChapters(
    int centerChapterIndex,
    PaginationConfig config,
    int layoutEpoch,
  ) async {
    if (!_isAlive) return;
    final sourceEpoch = _sourceEpoch;
    // Evict chapters outside the {N-1, N, N+1} sliding window.
    _chapterTextCache.removeWhere(
      (idx, _) => (idx - centerChapterIndex).abs() > 1,
    );
    _chapterPagesCache.removeWhere(
      (idx, _) => (idx - centerChapterIndex).abs() > 1,
    );

    final targets = <int>[centerChapterIndex + 1, centerChapterIndex - 1];
    for (final targetIdx in targets) {
      if (!_isAlive ||
          layoutEpoch != _layoutEpoch ||
          sourceEpoch != _sourceEpoch) {
        return;
      }
      if (targetIdx < 0 || targetIdx >= state.chapters.length) continue;
      if (_cachedPagesConfig == config &&
          _chapterPagesCache.containsKey(targetIdx)) {
        continue;
      }
      try {
        final text = await _getOrLoadChapterText(
          targetIdx,
          schedulePreload: false,
        );
        if (!_isAlive ||
            layoutEpoch != _layoutEpoch ||
            sourceEpoch != _sourceEpoch) {
          return;
        }
        await _paginateChapterCached(
          chapterIndex: targetIdx,
          sanitizedText: text,
          config: config,
          priorityCharOffset: targetIdx > centerChapterIndex ? 0 : null,
          layoutEpoch: layoutEpoch,
        );
      } catch (_) {
        // Silent pre-cache failure; user-initiated navigation handles errors.
      }
    }
  }

  /// Advances forward by one page (1-column) or one spread (2-column), or
  /// transitions seamlessly to the next chapter at chapter end.
  Future<void> nextPage() async {
    if (!_isAlive || state.isLoading) return;
    final pages = state.currentPages;
    final targetIdx = state.currentPageIndex + state.columnCount;

    if (pages.isNotEmpty && targetIdx < pages.length) {
      final aligned = _alignPageIndex(targetIdx, state.columnCount);
      final newAnchor = pages[aligned].startCharOffset;
      _commit(
        state.copyWith(
          currentPageIndex: aligned,
          anchorOffset: newAnchor,
        ),
      );
      _scheduleProgressSave();
      return;
    }

    if (state.currentChapterIndex + 1 < state.chapters.length) {
      await _loadChapterAndPaginate(
        chapterIndex: state.currentChapterIndex + 1,
        targetCharOffset: 0,
        landAtEnd: false,
        preserveAnchor: false,
      );
      if (!_isAlive) return;
      _scheduleProgressSave();
    }
  }

  /// Steps backward by one page (1-column) or one spread (2-column), or
  /// transitions cleanly to the last page/spread of the previous chapter.
  Future<void> prevPage() async {
    if (!_isAlive || state.isLoading) return;
    final pages = state.currentPages;

    if (pages.isNotEmpty && state.currentPageIndex > 0) {
      final rawTarget = math.max(0, state.currentPageIndex - state.columnCount);
      final aligned = _alignPageIndex(rawTarget, state.columnCount);
      final newAnchor = pages[aligned].startCharOffset;
      _commit(
        state.copyWith(
          currentPageIndex: aligned,
          anchorOffset: newAnchor,
        ),
      );
      _scheduleProgressSave();
      return;
    }

    if (state.currentChapterIndex > 0) {
      await _loadChapterAndPaginate(
        chapterIndex: state.currentChapterIndex - 1,
        targetCharOffset: 0,
        landAtEnd: true,
        preserveAnchor: false,
      );
      if (!_isAlive) return;
      _scheduleProgressSave();
    }
  }

  /// Jumps directly to [chapterIndex] at [charOffset], recording the previous
  /// position on [ReaderSessionState.jumpUndoStack] when [pushUndo] is true.
  Future<void> jumpToChapter(
    int chapterIndex, {
    int charOffset = 0,
    bool pushUndo = true,
  }) async {
    if (!_isAlive || state.chapters.isEmpty) return;
    final target = chapterIndex.clamp(0, state.chapters.length - 1);
    if (pushUndo) {
      _pushJumpUndoAnchor();
    }
    await _loadChapterAndPaginate(
      chapterIndex: target,
      targetCharOffset: charOffset,
      landAtEnd: false,
      preserveAnchor: false,
    );
    if (!_isAlive) return;
    await flushProgress();
  }

  /// Seeks to overall reading progress [ratio] (`0.0..1.0`), pushing the
  /// previous position onto [ReaderSessionState.jumpUndoStack].
  Future<void> jumpToProgressRatio(double ratio) async {
    if (!_isAlive || state.chapters.isEmpty) return;
    final clamped = ratio.clamp(0.0, 1.0);
    _pushJumpUndoAnchor();

    final scaled = clamped * state.chapters.length;
    final targetChapter = scaled.floor().clamp(0, state.chapters.length - 1);
    final intraRatio = (scaled - targetChapter).clamp(0.0, 0.9999);

    final text = await _getOrLoadChapterText(
      targetChapter,
      schedulePreload: false,
    );
    if (!_isAlive) return;
    final targetOffset = text.isEmpty
        ? 0
        : (text.length * intraRatio).floor().clamp(0, text.length - 1);

    await _loadChapterAndPaginate(
      chapterIndex: targetChapter,
      targetCharOffset: targetOffset,
      landAtEnd: false,
      preserveAnchor: false,
    );
    if (!_isAlive) return;
    await flushProgress();
  }

  /// Restores the most recent pre-jump position from `jumpUndoStack`.
  Future<void> undoLastJump() async {
    if (!_isAlive || state.jumpUndoStack.isEmpty) return;
    final stack = List<ReadingAnchor>.from(state.jumpUndoStack);
    final targetAnchor = stack.removeLast();
    _commit(state.copyWith(jumpUndoStack: stack));

    await _loadChapterAndPaginate(
      chapterIndex: targetAnchor.chapterIndex,
      targetCharOffset: targetAnchor.charOffset,
      landAtEnd: false,
      preserveAnchor: false,
    );
    if (!_isAlive) return;
    await flushProgress();
  }

  /// Updates the active anchor while continuously scrolling in
  /// [PageTurnMode.scroll].
  void updateScrollAnchor(int charOffset) {
    if (!_isAlive || state.currentChapterText.isEmpty) return;
    final clamped = charOffset.clamp(0, state.currentChapterText.length - 1);
    final pageIdx = findPageIndexByCharOffset(state.currentPages, clamped);
    if (clamped == state.anchorOffset && pageIdx == state.currentPageIndex) {
      return;
    }
    _commit(state.copyWith(anchorOffset: clamped, currentPageIndex: pageIdx));
    _scheduleProgressSave();
  }

  void _pushJumpUndoAnchor() {
    if (!_isAlive) return;
    final anchor = ReadingAnchor(
      chapterIndex: state.currentChapterIndex,
      charOffset: state.anchorOffset,
      chapterTitleSnapshot: state.currentChapterTitle,
    );
    final next = <ReadingAnchor>[...state.jumpUndoStack, anchor];
    if (next.length > 20) {
      next.removeAt(0);
    }
    _commit(state.copyWith(jumpUndoStack: next));
  }

  /// Adds a bookmark at the current reading anchor.
  Future<void> addBookmark({String note = ''}) async {
    if (!_isAlive || state.book == null) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    final excerpt = _extractExcerpt(state.currentChapterText, state.anchorOffset);
    final now = DateTime.now();
    final bookmark = Bookmark(
      id: 'bm_${bookId}_${state.currentChapterIndex}_${state.anchorOffset}_${now.microsecondsSinceEpoch}',
      bookId: bookId,
      chapterIndex: state.currentChapterIndex,
      charOffset: state.anchorOffset,
      excerpt: excerpt.isEmpty ? state.currentChapterTitle : excerpt,
      note: note.trim(),
      createdAt: now,
    );
    try {
      await bookRepo.saveBookmark(bookmark);
      if (!_isAlive) return;
      final updated = await bookRepo.listBookmarks(bookId);
      if (!_isAlive) return;
      _commit(state.copyWith(bookmarks: updated));
    } catch (error) {
      if (!_isAlive) return;
      _commit(state.copyWith(errorMessage: _formatError(error)));
    }
  }

  /// Deletes bookmark [bookmarkId].
  Future<void> deleteBookmark(String bookmarkId) async {
    if (!_isAlive) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    try {
      await bookRepo.deleteBookmark(bookmarkId);
      if (!_isAlive) return;
      final updated = await bookRepo.listBookmarks(bookId);
      if (!_isAlive) return;
      _commit(state.copyWith(bookmarks: updated));
    } catch (error) {
      if (!_isAlive) return;
      _commit(state.copyWith(errorMessage: _formatError(error)));
    }
  }

  /// Jumps to a saved [bookmark], pushing the current anchor onto undo stack.
  Future<void> jumpToBookmark(Bookmark bookmark) async {
    await jumpToChapter(
      bookmark.chapterIndex,
      charOffset: bookmark.charOffset,
      pushUndo: true,
    );
  }

  /// Activates a saved/built-in theme by [themeId] and repaginates preserving
  /// `anchorOffset`.
  Future<void> selectTheme(String themeId) async {
    if (!_isAlive) return;
    final target = state.availableThemes.firstWhere(
      (t) => t.id == themeId,
      orElse: () => state.activeTheme,
    );
    await updateTheme(target, persistTheme: false);
    if (!_isAlive) return;
    await _saveSetting(_kActiveThemeKey, target.id);
  }

  /// Quickly toggles between a light day theme and a dark night theme.
  Future<void> toggleDayNightTheme() async {
    if (!_isAlive) return;
    final wantDark = !state.activeTheme.isDark;
    final match = state.availableThemes.where((t) => t.isDark == wantDark);
    if (match.isNotEmpty) {
      await selectTheme(match.first.id);
    } else {
      final toggled = state.activeTheme.copyWith(
        isDark: wantDark,
        bgColor: wantDark ? 0xFF1E2022 : 0xFFF7F4EC,
        textColor: wantDark ? 0xFFCFCFCF : 0xFF2C2A26,
        secondaryTextColor: wantDark ? 0xFF8C9299 : 0xFF78736A,
        updatedAt: DateTime.now(),
      );
      await updateTheme(toggled);
    }
  }

  /// Updates typography or colors on [updated] via [ThemeRepository],
  /// preserving `anchorOffset`.
  Future<void> updateTheme(
    ReaderTheme updated, {
    bool persistTheme = true,
  }) async {
    if (!_isAlive) return;
    final fontGateway = ref.read(fontLoaderGatewayProvider);
    final themeRepo = ref.read(themeRepositoryProvider);

    final withTimestamp = updated.copyWith(updatedAt: DateTime.now());
    if (withTimestamp.fontPath != null && withTimestamp.fontPath!.isNotEmpty) {
      try {
        await fontGateway.ensureFontLoaded(
          withTimestamp.fontFamily,
          withTimestamp.fontPath,
        );
      } catch (_) {
        // Continue safely with fallback font if load fails.
      }
      if (!_isAlive) return;
    }

    final updatedThemes = List<ReaderTheme>.from(state.availableThemes);
    final idx = updatedThemes.indexWhere((t) => t.id == withTimestamp.id);
    if (idx >= 0) {
      updatedThemes[idx] = withTimestamp;
    } else {
      updatedThemes.add(withTimestamp);
    }

    final needsRepaginate = _paginationAffectingChanged(
      state.activeTheme,
      withTimestamp,
    );

    _commit(
      state.copyWith(
        activeTheme: withTimestamp,
        availableThemes: updatedThemes,
      ),
    );

    if (persistTheme) {
      try {
        await themeRepo.saveTheme(withTimestamp);
        if (!_isAlive) return;
        await _saveSetting(_kActiveThemeKey, withTimestamp.id);
        if (!_isAlive) return;
      } catch (error) {
        if (_isAlive) {
          _commit(state.copyWith(errorMessage: _formatError(error)));
        }
      }
    }

    if (_isAlive && needsRepaginate && _viewportSize != null) {
      await _repaginateCurrentChapterPreservingAnchor();
    }
  }

  /// Picks a local `.ttf` / `.otf` file via [PlatformBridge], registers it via
  /// [FontLoaderGateway], and applies it to the active theme.
  Future<void> importCustomFont() async {
    if (!_isAlive) return;
    final platform = ref.read(platformBridgeProvider);
    final fontGateway = ref.read(fontLoaderGatewayProvider);
    try {
      final paths = await platform.pickFiles(
        extensions: const <String>['ttf', 'otf'],
        allowMultiple: false,
      );
      if (!_isAlive || paths.isEmpty) return;

      final loaded = await fontGateway.importAndRegisterFont(paths.first);
      if (!_isAlive) return;

      await updateTheme(
        state.activeTheme.copyWith(
          fontFamily: loaded.fontFamily,
          fontPath: loaded.relativeFontPath,
        ),
      );
    } catch (error) {
      if (!_isAlive) return;
      _commit(state.copyWith(errorMessage: '导入字体失败：${_formatError(error)}'));
    }
  }

  void toggleOverlay() {
    if (!_isAlive) return;
    _commit(state.copyWith(showOverlay: !state.showOverlay));
  }

  void setOverlayVisible(bool visible) {
    if (!_isAlive || state.showOverlay == visible) return;
    _commit(state.copyWith(showOverlay: visible));
  }

  void toggleTocReversed() {
    if (!_isAlive) return;
    _commit(state.copyWith(isTocReversed: !state.isTocReversed));
  }

  Future<void> toggleKeepScreenOn() async {
    if (!_isAlive) return;
    final platform = ref.read(platformBridgeProvider);
    final next = !state.keepScreenOn;
    _commit(state.copyWith(keepScreenOn: next));
    await platform.setKeepScreenOn(next);
    if (!_isAlive) return;
    await _saveSetting(_kKeepScreenOnKey, next ? 'true' : 'false');
  }

  Future<void> toggleVolumeKeyPaging() async {
    if (!_isAlive) return;
    final platform = ref.read(platformBridgeProvider);
    final next = !state.volumeKeyPaging;
    _commit(state.copyWith(volumeKeyPaging: next));
    await platform.setVolumeKeyPaging(next);
    if (!_isAlive) return;
    await _saveSetting(_kVolumeKeyPagingKey, next ? 'true' : 'false');
  }

  Future<void> toggleImmersive() async {
    if (!_isAlive) return;
    final platform = ref.read(platformBridgeProvider);
    final next = !state.isImmersive;
    _commit(state.copyWith(isImmersive: next));
    await platform.setImmersiveMode(next);
  }

  Future<void> setImmersive(bool enabled) async {
    if (!_isAlive || state.isImmersive == enabled) return;
    final platform = ref.read(platformBridgeProvider);
    _commit(state.copyWith(isImmersive: enabled));
    await platform.setImmersiveMode(enabled);
  }

  Future<void> toggleSafeArea() async {
    if (!_isAlive) return;
    final next = !state.safeAreaEnabled;
    _commit(state.copyWith(safeAreaEnabled: next));
    await _saveSetting(_kSafeAreaEnabledKey, next ? 'true' : 'false');
  }

  Future<void> triggerBossKeyHide() async {
    if (!_isAlive) return;
    final platform = ref.read(platformBridgeProvider);
    await flushProgress();
    await platform.bossKeyHide();
  }

  /// Applies a confirmed source switch result, replaces chapter metadata,
  /// clears cached text/pages, jumps to [ChangeSourceSwitchResult.targetChapterIndex]
  /// at offset `0`, and persists updated progress.
  Future<void> applyChangeSourceResult(ChangeSourceSwitchResult result) async {
    if (!_isAlive) return;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _batchCacheCancelToken?.cancel();
    _batchCacheCancelToken = null;

    if (_isOnlineBook(result.updatedBook)) {
      _ensurePreloadScheduler().cancelBookTasks(result.updatedBook.id);
    }

    _sourceEpoch++;
    _layoutEpoch++;
    _chapterTextCache.clear();
    _inFlightChapterLoads.clear();
    _chapterPagesCache.clear();
    _cachedPagesConfig = null;

    final chapters = result.chapters;
    final targetIndex = chapters.isEmpty
        ? 0
        : result.targetChapterIndex.clamp(0, chapters.length - 1);

    _commit(
      state.copyWith(
        book: result.updatedBook,
        chapters: chapters,
        currentChapterIndex: targetIndex,
        anchorOffset: 0,
        currentChapterText: '',
        currentPages: const <PageSlice>[],
        currentPageIndex: 0,
        clearError: true,
      ),
    );

    if (chapters.isNotEmpty) {
      await _loadChapterAndPaginate(
        chapterIndex: targetIndex,
        targetCharOffset: 0,
        landAtEnd: false,
        preserveAnchor: false,
      );
      if (!_isAlive) return;
    }

    await flushProgress();
  }

  /// Batch-caches up to [count] chapters ahead from the current reading
  /// position via [ChapterPreloadScheduler.cacheRange].
  Future<PreloadBatchResult?> cacheChaptersAhead(
    int count, {
    void Function(PreloadBatchProgress progress)? onProgress,
  }) async {
    if (!_isAlive || state.book == null) {
      return null;
    }
    final book = state.book!;
    if (!_isOnlineBook(book) || state.chapters.isEmpty || count <= 0) {
      return null;
    }
    final scheduler = _ensurePreloadScheduler();
    _batchCacheCancelToken?.cancel();
    final token = CancellationToken();
    _batchCacheCancelToken = token;

    final start = state.currentChapterIndex.clamp(0, state.chapters.length - 1);
    final end = math.min(state.chapters.length - 1, start + count);
    try {
      return await scheduler.cacheRange(
        book: book,
        chapters: state.chapters,
        startChapterIndex: start,
        endChapterIndex: end,
        cancelToken: token,
        onProgress: onProgress,
      );
    } finally {
      if (identical(_batchCacheCancelToken, token)) {
        _batchCacheCancelToken = null;
      }
      token.dispose();
    }
  }

  /// Flushes the current reading anchor to persistent storage immediately.
  Future<void> flushProgress() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (!_isAlive || state.book == null) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    await _persistProgressSnapshot(
      bookRepo: bookRepo,
      book: state.book!,
      chapterIndex: state.currentChapterIndex,
      charOffset: state.anchorOffset,
      chapterTitle: state.currentChapterTitle,
      progressPercent: state.overallProgressPercent,
    );
  }

  void _scheduleProgressSave() {
    if (!_isAlive || state.book == null) return;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (_isAlive) {
        unawaited(flushProgress());
      }
    });
  }

  static Future<void> _persistProgressSnapshot({
    required BookRepository bookRepo,
    required Book book,
    required int chapterIndex,
    required int charOffset,
    required String chapterTitle,
    required double progressPercent,
  }) async {
    final now = DateTime.now();
    try {
      await bookRepo.saveProgress(
        ReadingProgress(
          bookId: book.id,
          chapterIndex: chapterIndex,
          charOffset: charOffset,
          chapterTitleSnapshot: chapterTitle,
          progressPercent: progressPercent,
          updatedAt: now,
        ),
      );
      await bookRepo.saveBook(
        book.copyWith(
          lastChapterTitle: chapterTitle,
          lastReadAt: now,
          updatedAt: now,
        ),
      );
    } catch (_) {
      // Avoid crashing reader navigation if storage write fails transiently.
    }
  }

  /// Binary-searches [pages] for the slice containing [charOffset].
  static int findPageIndexByCharOffset(
    List<PageSlice> pages,
    int charOffset,
  ) {
    if (pages.isEmpty) return 0;
    if (charOffset <= pages.first.startCharOffset) return 0;
    if (charOffset >= pages.last.endCharOffset) return pages.length - 1;

    var low = 0;
    var high = pages.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final page = pages[mid];
      if (charOffset < page.startCharOffset) {
        high = mid - 1;
      } else if (charOffset >= page.endCharOffset &&
          page.startCharOffset != page.endCharOffset) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return low.clamp(0, pages.length - 1);
  }

  static int _alignPageIndex(int pageIndex, int columnCount) {
    if (pageIndex <= 0) return 0;
    if (columnCount == 2) {
      return pageIndex & ~1;
    }
    return pageIndex;
  }

  static bool _paginationAffectingChanged(ReaderTheme a, ReaderTheme b) {
    return a.fontFamily != b.fontFamily ||
        a.fontPath != b.fontPath ||
        a.fontSize != b.fontSize ||
        a.fontWeight != b.fontWeight ||
        a.lineHeight != b.lineHeight ||
        a.paragraphSpacing != b.paragraphSpacing ||
        a.letterSpacing != b.letterSpacing ||
        a.paragraphIndentChars != b.paragraphIndentChars ||
        a.marginHorizontal != b.marginHorizontal ||
        a.marginVertical != b.marginVertical ||
        a.columnMode != b.columnMode ||
        a.maxContentWidth != b.maxContentWidth ||
        a.enablePunctuationHanging != b.enablePunctuationHanging ||
        a.enableCjkSpacing != b.enableCjkSpacing;
  }

  Future<void> _saveSetting(String key, String value) async {
    if (!_isAlive) return;
    final themeRepo = ref.read(themeRepositoryProvider);
    try {
      await themeRepo.saveSetting(
        AppSetting(key: key, value: value, updatedAt: DateTime.now()),
      );
    } catch (_) {
      // Non-critical setting save error.
    }
  }

  String _extractExcerpt(String text, int offset) {
    if (text.isEmpty) return '';
    final start = offset.clamp(0, text.length - 1);
    final end = math.min(text.length, start + 48);
    return text.substring(start, end).replaceAll('\n', ' ').trim();
  }

  String _formatError(Object error) {
    if (error is AppFailure) return error.message;
    return error.toString();
  }
}
