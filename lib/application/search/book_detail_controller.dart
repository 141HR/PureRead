import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import 'book_detail_state.dart';
import 'search_state.dart';

final bookDetailControllerProvider =
    NotifierProvider<BookDetailController, BookDetailState>(
      BookDetailController.new,
    );

/// Loads online book details and TOC preview, adds books to the bookshelf,
/// and prepares books + initial chapters before opening the reader.
class BookDetailController extends Notifier<BookDetailState> {
  bool _disposed = false;
  int _loadEpoch = 0;
  CancellationToken? _activeCancelToken;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  BookDetailState build() {
    _disposed = false;
    _loadEpoch = 0;
    ref.onDispose(() {
      _disposed = true;
      _activeCancelToken?.cancel();
      _activeCancelToken = null;
    });
    return const BookDetailState();
  }

  /// Derives a URL-safe deterministic ID for an online book from its
  /// [sourceId] and [originBookUrl].
  static String deriveOnlineBookId(String sourceId, String originBookUrl) {
    var h1 = 0x811c9dc5;
    var h2 = 0x9e3779b9;
    for (final unit in utf8.encode('$sourceId::$originBookUrl')) {
      h1 ^= unit;
      h1 = (h1 * 0x01000193) & 0x7fffffff;
      h2 ^= unit;
      h2 = (h2 * 0x85ebca6b) & 0x7fffffff;
    }
    return 'online_${h1.toRadixString(16)}_${h2.toRadixString(16)}';
  }

  /// Loads detail and chapter TOC preview for [book] at [initialSourceIndex].
  Future<void> loadAggregatedBook(
    AggregatedSearchBook book, {
    int initialSourceIndex = 0,
  }) async {
    if (!_isAlive || book.sources.isEmpty) return;
    final clampedIdx = initialSourceIndex.clamp(0, book.sources.length - 1);
    await _loadSelection(book, clampedIdx);
  }

  /// Switches the active preview source within the currently loaded book.
  Future<void> selectSourceIndex(int index) async {
    final currentBook = state.aggregatedBook;
    if (!_isAlive || currentBook == null || currentBook.sources.isEmpty) return;
    final clamped = index.clamp(0, currentBook.sources.length - 1);
    await _loadSelection(currentBook, clamped);
  }

  /// Retries loading the currently selected source detail and TOC.
  Future<void> reload() async {
    final currentBook = state.aggregatedBook;
    if (!_isAlive || currentBook == null) return;
    await _loadSelection(currentBook, state.selectedSourceIndex);
  }

  /// Persists the selected book and its TOC chapters to [BookRepository].
  Future<Book?> addToBookshelf() async {
    if (!_isAlive) return null;
    final book = state.aggregatedBook;
    final entry = state.activeSourceEntry;
    if (book == null || entry == null) return null;

    final bookRepo = ref.read(bookRepositoryProvider);
    state = state.copyWith(
      isSavingToShelf: true,
      clearError: true,
      clearStatus: true,
    );

    try {
      final existing =
          state.existingBookshelfBook ??
          await bookRepo.findBySourceAndUrl(
            entry.item.sourceId,
            entry.item.bookUrl,
          );
      if (!_isAlive) return null;

      final now = DateTime.now().toUtc();
      final targetBookId =
          existing?.id ??
          deriveOnlineBookId(entry.item.sourceId, entry.item.bookUrl);
      final normalizedChapters = state.chapters
          .asMap()
          .entries
          .map(
            (e) => e.value.copyWith(
              bookId: targetBookId,
              chapterIndex: e.key,
              updatedAt: now,
            ),
          )
          .toList(growable: false);

      final detail = state.detail;
      final resolvedTitle = (detail?.title.trim().isNotEmpty ?? false)
          ? detail!.title.trim()
          : entry.item.title.trim();
      final resolvedAuthor = (detail?.author.trim().isNotEmpty ?? false)
          ? detail!.author.trim()
          : entry.item.author.trim();
      final resolvedIntro = (detail?.intro.trim().isNotEmpty ?? false)
          ? detail!.intro.trim()
          : entry.item.intro.trim();
      final resolvedCover =
          (detail?.coverUrl?.trim().isNotEmpty ?? false)
              ? detail!.coverUrl!.trim()
              : entry.item.coverUrl;
      final resolvedTocUrl = (detail?.tocUrl.trim().isNotEmpty ?? false)
          ? detail!.tocUrl.trim()
          : entry.item.bookUrl;
      final resolvedLastChapter = normalizedChapters.isNotEmpty
          ? normalizedChapters.last.title
          : ((detail?.latestChapterTitle.trim().isNotEmpty ?? false)
                ? detail!.latestChapterTitle.trim()
                : entry.item.latestChapterTitle);

      final savedBook = Book(
        id: targetBookId,
        sourceId: entry.item.sourceId,
        providerType: entry.item.providerType,
        originBookUrl: detail?.bookUrl ?? entry.item.bookUrl,
        tocUrl: resolvedTocUrl,
        title: resolvedTitle,
        author: resolvedAuthor,
        coverPath: resolvedCover,
        intro: resolvedIntro,
        groupId: existing?.groupId,
        isPinned: existing?.isPinned ?? false,
        totalChapters: normalizedChapters.isNotEmpty
            ? normalizedChapters.length
            : (existing?.totalChapters ?? 0),
        unreadCount: existing?.unreadCount ?? 0,
        lastChapterTitle: resolvedLastChapter,
        lastReadAt: existing?.lastReadAt,
        latestChapterAt: now,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      await bookRepo.saveBook(savedBook);
      if (!_isAlive) return null;
      if (normalizedChapters.isNotEmpty) {
        await bookRepo.replaceChapters(targetBookId, normalizedChapters);
        if (!_isAlive) return null;
      }

      state = state.copyWith(
        isSavingToShelf: false,
        existingBookshelfBook: savedBook,
        chapters: normalizedChapters.isNotEmpty
            ? normalizedChapters
            : state.chapters,
        statusMessage: '已将《${savedBook.title}》加入书架',
      );
      return savedBook;
    } catch (error) {
      if (!_isAlive) return null;
      state = state.copyWith(
        isSavingToShelf: false,
        errorMessage: error is AppFailure ? error.message : '加入书架失败：$error',
      );
      return null;
    }
  }

  /// Ensures the book is saved in [BookRepository], optionally sets the
  /// starting chapter [initialChapterIndex], and returns the persisted `bookId`
  /// ready for navigating to the reader route.
  Future<String?> prepareForReader({int? initialChapterIndex}) async {
    final saved = await addToBookshelf();
    if (!_isAlive || saved == null) return null;

    if (initialChapterIndex != null && state.chapters.isNotEmpty) {
      final bookRepo = ref.read(bookRepositoryProvider);
      final targetIdx = initialChapterIndex.clamp(0, state.chapters.length - 1);
      final targetChapter = state.chapters[targetIdx];
      try {
        final existingProgress = await bookRepo.getProgress(saved.id);
        if (!_isAlive) return null;
        await bookRepo.saveProgress(
          ReadingProgress(
            bookId: saved.id,
            chapterIndex: targetIdx,
            charOffset: 0,
            chapterTitleSnapshot: targetChapter.title,
            progressPercent: (targetIdx + 1) / state.chapters.length,
            readingDurationSec: existingProgress?.readingDurationSec ?? 0,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      } catch (error) {
        if (!_isAlive) return null;
        state = state.copyWith(
          errorMessage: error is AppFailure ? error.message : '保存阅读章节失败：$error',
        );
        return null;
      }
    }

    return saved.id;
  }

  /// Clears transient feedback messages.
  void clearMessages() {
    if (!_isAlive) return;
    state = state.copyWith(clearError: true, clearStatus: true);
  }

  Future<void> _loadSelection(
    AggregatedSearchBook book,
    int sourceIndex,
  ) async {
    _activeCancelToken?.cancel();
    final token = CancellationToken();
    _activeCancelToken = token;
    final epoch = ++_loadEpoch;

    final entry = book.sources[sourceIndex];
    final bookRepo = ref.read(bookRepositoryProvider);
    final sourceRepo = ref.read(sourceRepositoryProvider);
    final providerFactory = ref.read(bookProviderFactoryProvider);

    state = BookDetailState(
      aggregatedBook: book,
      selectedSourceIndex: sourceIndex,
      isLoadingDetail: true,
      isLoadingToc: true,
    );

    try {
      final existing = await bookRepo.findBySourceAndUrl(
        entry.item.sourceId,
        entry.item.bookUrl,
      );
      if (!_isAlive || epoch != _loadEpoch || token.isCancelled) return;
      state = state.copyWith(existingBookshelfBook: existing);

      final source = await sourceRepo.getSourceById(entry.item.sourceId);
      if (!_isAlive || epoch != _loadEpoch || token.isCancelled) return;
      if (source == null) {
        state = state.copyWith(
          isLoadingDetail: false,
          isLoadingToc: false,
          errorMessage: '未找到书源「${entry.sourceName}」',
        );
        return;
      }

      final provider = await providerFactory.createProvider(source);
      if (!_isAlive || epoch != _loadEpoch || token.isCancelled) return;

      BookDetail? detail;
      try {
        final detailRes = await provider.getBookDetail(
          entry.item.bookUrl,
          cancelToken: token,
        );
        if (!_isAlive || epoch != _loadEpoch || token.isCancelled) return;
        detail = detailRes.detail;
        state = state.copyWith(
          detail: detail,
          detailTrace: detailRes.trace,
          isLoadingDetail: false,
        );
      } on CancelledFailure {
        return;
      } catch (error) {
        if (!_isAlive || epoch != _loadEpoch || token.isCancelled) return;
        state = state.copyWith(
          isLoadingDetail: false,
          errorMessage: error is AppFailure ? error.message : '详情加载失败：$error',
        );
      }

      final tocUrl = (detail?.tocUrl.trim().isNotEmpty ?? false)
          ? detail!.tocUrl.trim()
          : entry.item.bookUrl;

      try {
        final tocRes = await provider.getToc(tocUrl, cancelToken: token);
        if (!_isAlive || epoch != _loadEpoch || token.isCancelled) return;
        final tempBookId =
            existing?.id ??
            deriveOnlineBookId(entry.item.sourceId, entry.item.bookUrl);
        final normalizedChapters = tocRes.chapters
            .asMap()
            .entries
            .map(
              (e) => e.value.copyWith(
                bookId: tempBookId,
                chapterIndex: e.key,
              ),
            )
            .toList(growable: false);
        state = state.copyWith(
          chapters: normalizedChapters,
          tocTrace: tocRes.trace,
          isLoadingToc: false,
          clearError: detail != null,
        );
      } on CancelledFailure {
        return;
      } catch (error) {
        if (!_isAlive || epoch != _loadEpoch || token.isCancelled) return;
        state = state.copyWith(
          isLoadingToc: false,
          errorMessage: error is AppFailure ? error.message : '目录加载失败：$error',
        );
      }
    } on CancelledFailure {
      return;
    } catch (error) {
      if (!_isAlive || epoch != _loadEpoch) return;
      state = state.copyWith(
        isLoadingDetail: false,
        isLoadingToc: false,
        errorMessage: error is AppFailure ? error.message : '加载书籍信息失败：$error',
      );
    }
  }
}
