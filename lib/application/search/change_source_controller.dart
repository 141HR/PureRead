import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import 'change_source_state.dart';
import 'chapter_title_matcher.dart';
import 'search_controller.dart';

final changeSourceControllerProvider =
    NotifierProvider.autoDispose<ChangeSourceController, ChangeSourceState>(
      ChangeSourceController.new,
    );

/// Discovers alternative sources for an online book, aligns the target
/// source's TOC via normalized chapter-title similarity matching, and falls
/// back to a manual chapter picker when confidence is low.
class ChangeSourceController extends Notifier<ChangeSourceState> {
  bool _disposed = false;
  int _searchEpoch = 0;
  int _tocEpoch = 0;
  CancellationToken? _searchToken;
  CancellationToken? _tocToken;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  ChangeSourceState build() {
    _disposed = false;
    _searchEpoch = 0;
    _tocEpoch = 0;
    ref.onDispose(() {
      _disposed = true;
      _searchToken?.cancel();
      _searchToken = null;
      _tocToken?.cancel();
      _tocToken = null;
    });
    return const ChangeSourceState();
  }

  /// Searches enabled sources for alternatives matching [book.title] and
  /// [book.author].
  Future<void> loadCandidates({
    required Book book,
    required int currentChapterIndex,
    required String currentChapterTitle,
  }) async {
    if (!_isAlive) return;
    _searchToken?.cancel();
    _tocToken?.cancel();

    final searchToken = CancellationToken();
    _searchToken = searchToken;
    final epoch = ++_searchEpoch;

    final sourceRepo = ref.read(sourceRepositoryProvider);
    final providerFactory = ref.read(bookProviderFactoryProvider);
    final concurrencyLimit = math.max(
      1,
      ref.read(searchConcurrencyLimitProvider),
    );

    state = ChangeSourceState(
      book: book,
      currentChapterIndex: currentChapterIndex,
      currentChapterTitle: currentChapterTitle,
      isSearching: true,
    );

    List<BookSource> sources;
    try {
      final fetched = await sourceRepo.listSources(enabledOnly: true);
      if (!_isAlive || epoch != _searchEpoch || searchToken.isCancelled) return;
      sources = fetched.where((s) => s.enabled).toList(growable: false)
        ..sort((a, b) {
          final wCmp = b.weight.compareTo(a.weight);
          if (wCmp != 0) return wCmp;
          return a.name.compareTo(b.name);
        });
    } catch (error) {
      if (!_isAlive || epoch != _searchEpoch) return;
      state = state.copyWith(
        isSearching: false,
        errorMessage: error is AppFailure ? error.message : '加载书源失败：$error',
      );
      return;
    }

    if (sources.isEmpty) {
      state = state.copyWith(
        isSearching: false,
        totalSources: 0,
        errorMessage: '暂无可用在线书源。',
      );
      return;
    }

    state = state.copyWith(totalSources: sources.length, completedSources: 0);

    final normBookTitle = _normalizeMeta(book.title);
    final normBookAuthor = _normalizeAuthor(book.author);
    final found = <ChangeSourceCandidate>[];
    var nextIdx = 0;
    var completed = 0;

    Future<void> worker() async {
      while (true) {
        if (!_isAlive || epoch != _searchEpoch || searchToken.isCancelled) {
          return;
        }
        if (nextIdx >= sources.length) return;
        final source = sources[nextIdx++];

        try {
          final provider = await providerFactory.createProvider(source);
          if (!_isAlive || epoch != _searchEpoch || searchToken.isCancelled) {
            return;
          }
          if (!provider.capabilities.supportsSearch) {
            completed++;
            continue;
          }
          final res = await provider.search(
            book.title,
            page: 1,
            cancelToken: searchToken,
          );
          if (!_isAlive || epoch != _searchEpoch || searchToken.isCancelled) {
            return;
          }

          for (final item in res.items) {
            if (_normalizeMeta(item.title) != normBookTitle) continue;
            final itemAuthor = _normalizeAuthor(item.author);
            if (normBookAuthor.isNotEmpty &&
                itemAuthor.isNotEmpty &&
                itemAuthor != normBookAuthor) {
              continue;
            }
            final isCurrent =
                item.sourceId == book.sourceId &&
                (book.originBookUrl == null ||
                    item.bookUrl == book.originBookUrl);
            final duplicate = found.any(
              (c) =>
                  c.source.id == source.id &&
                  c.searchItem.bookUrl == item.bookUrl,
            );
            if (!duplicate) {
              found.add(
                ChangeSourceCandidate(
                  source: source,
                  searchItem: item,
                  isCurrentSource: isCurrent,
                ),
              );
            }
          }
        } on CancelledFailure {
          return;
        } catch (_) {
          // Isolate per-source failures during candidate discovery.
        }

        completed++;
        if (!_isAlive || epoch != _searchEpoch || searchToken.isCancelled) {
          return;
        }
        state = state.copyWith(
          completedSources: completed,
          candidates: _sortCandidates(found),
        );
      }
    }

    final workerCount = math.min(concurrencyLimit, sources.length);
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    if (!_isAlive || epoch != _searchEpoch) return;
    state = state.copyWith(
      isSearching: false,
      completedSources: completed,
      candidates: _sortCandidates(found),
    );
  }

  /// Selects candidate [index], fetches its TOC, and runs normalized chapter
  /// title similarity matching against the current reading chapter.
  Future<void> selectCandidate(int index) async {
    if (!_isAlive || index < 0 || index >= state.candidates.length) return;
    _tocToken?.cancel();
    final tocToken = CancellationToken();
    _tocToken = tocToken;
    final tocEpoch = ++_tocEpoch;

    final candidate = state.candidates[index];
    final existingChapters = candidate.chapters;
    if (existingChapters != null && existingChapters.isNotEmpty) {
      final match =
          candidate.matchResult ??
          ChapterTitleMatcher.findBestMatch(
            state.currentChapterTitle,
            existingChapters,
            preferredIndex: state.currentChapterIndex,
          );
      state = state.copyWith(
        selectedCandidateIndex: index,
        selectedTargetChapterIndex: match.matchedIndex,
        showManualPicker: !match.isConfident,
        chapterFilterQuery: '',
        clearError: true,
      );
      return;
    }

    final updatedList = List<ChangeSourceCandidate>.of(state.candidates);
    updatedList[index] = candidate.copyWith(
      isLoadingToc: true,
      clearError: true,
    );
    state = state.copyWith(
      candidates: List<ChangeSourceCandidate>.unmodifiable(updatedList),
      selectedCandidateIndex: index,
      clearSelectedTargetChapter: true,
      showManualPicker: false,
      chapterFilterQuery: '',
      clearError: true,
    );

    final providerFactory = ref.read(bookProviderFactoryProvider);

    try {
      final provider = await providerFactory.createProvider(candidate.source);
      if (!_isAlive || tocEpoch != _tocEpoch || tocToken.isCancelled) return;

      BookDetail? detail;
      try {
        final detailRes = await provider.getBookDetail(
          candidate.searchItem.bookUrl,
          cancelToken: tocToken,
        );
        if (!_isAlive || tocEpoch != _tocEpoch || tocToken.isCancelled) return;
        detail = detailRes.detail;
      } on CancelledFailure {
        return;
      } catch (_) {
        // Fallback to search item URL for TOC if detail step fails.
      }

      final tocUrl = (detail?.tocUrl.trim().isNotEmpty ?? false)
          ? detail!.tocUrl.trim()
          : candidate.searchItem.bookUrl;

      final tocRes = await provider.getToc(tocUrl, cancelToken: tocToken);
      if (!_isAlive || tocEpoch != _tocEpoch || tocToken.isCancelled) return;

      final targetBookId = state.book?.id ?? '';
      final normalizedChapters = tocRes.chapters
          .asMap()
          .entries
          .map(
            (e) => e.value.copyWith(
              bookId: targetBookId,
              chapterIndex: e.key,
            ),
          )
          .toList(growable: false);

      final match = ChapterTitleMatcher.findBestMatch(
        state.currentChapterTitle,
        normalizedChapters,
        preferredIndex: state.currentChapterIndex,
      );

      final nextCandidates = List<ChangeSourceCandidate>.of(state.candidates);
      if (index < nextCandidates.length) {
        nextCandidates[index] = nextCandidates[index].copyWith(
          detail: detail,
          chapters: normalizedChapters,
          matchResult: match,
          isLoadingToc: false,
          clearError: true,
        );
      }

      state = state.copyWith(
        candidates: List<ChangeSourceCandidate>.unmodifiable(nextCandidates),
        selectedTargetChapterIndex: match.matchedIndex,
        showManualPicker: !match.isConfident,
        errorMessage: normalizedChapters.isEmpty ? '目标书源目录为空' : null,
      );
    } on CancelledFailure {
      return;
    } catch (error) {
      if (!_isAlive || tocEpoch != _tocEpoch) return;
      final message = error is AppFailure ? error.message : '目录解析失败：$error';
      final nextCandidates = List<ChangeSourceCandidate>.of(state.candidates);
      if (index < nextCandidates.length) {
        nextCandidates[index] = nextCandidates[index].copyWith(
          isLoadingToc: false,
          errorMessage: message,
        );
      }
      state = state.copyWith(
        candidates: List<ChangeSourceCandidate>.unmodifiable(nextCandidates),
        errorMessage: message,
      );
    }
  }

  /// Toggles visibility of the manual fallback chapter picker.
  void toggleManualPicker([bool? show]) {
    if (!_isAlive) return;
    state = state.copyWith(showManualPicker: show ?? !state.showManualPicker);
  }

  /// Updates the chapter search filter inside the manual fallback picker.
  void setChapterFilterQuery(String query) {
    if (!_isAlive) return;
    state = state.copyWith(chapterFilterQuery: query);
  }

  /// Picks a specific target chapter index manually from the candidate TOC.
  void selectManualChapter(int chapterIndex) {
    if (!_isAlive) return;
    final chapters = state.selectedCandidate?.chapters;
    if (chapters == null || chapters.isEmpty) return;
    final clamped = chapterIndex.clamp(0, chapters.length - 1);
    state = state.copyWith(selectedTargetChapterIndex: clamped);
  }

  /// Stops candidate discovery cleanly.
  void cancelSearch() {
    if (!_isAlive) return;
    _searchEpoch++;
    _searchToken?.cancel();
    _searchToken = null;
    if (state.isSearching) {
      state = state.copyWith(isSearching: false);
    }
  }

  /// Commits the source switch by updating [BookRepository], clearing stale
  /// online chapter cache for the book, replacing TOC chapters, and saving the
  /// aligned [ReadingProgress].
  Future<ChangeSourceSwitchResult?> confirmSwitch() async {
    if (!_isAlive) return null;
    final currentBook = state.book;
    final candidate = state.selectedCandidate;
    final chapters = candidate?.chapters;
    final targetChapterIndex = state.selectedTargetChapterIndex;

    if (currentBook == null ||
        candidate == null ||
        chapters == null ||
        chapters.isEmpty ||
        targetChapterIndex == null) {
      return null;
    }

    final bookRepo = ref.read(bookRepositoryProvider);
    final cacheGateway = ref.read(chapterCacheGatewayProvider);
    final scheduler = ref.read(chapterPreloadSchedulerProvider);

    state = state.copyWith(isSwitching: true, clearError: true);

    try {
      scheduler.cancelBookTasks(currentBook.id);
      await cacheGateway.deleteBookCache(currentBook.id);
      if (!_isAlive) return null;

      final now = DateTime.now().toUtc();
      final clampedIndex = targetChapterIndex.clamp(0, chapters.length - 1);
      final normalizedChapters = chapters
          .asMap()
          .entries
          .map(
            (e) => e.value.copyWith(
              bookId: currentBook.id,
              chapterIndex: e.key,
              isCached: false,
              updatedAt: now,
            ),
          )
          .toList(growable: false);

      final detail = candidate.detail;
      final newOriginUrl = (detail?.bookUrl.trim().isNotEmpty ?? false)
          ? detail!.bookUrl.trim()
          : candidate.searchItem.bookUrl;
      final newTocUrl = (detail?.tocUrl.trim().isNotEmpty ?? false)
          ? detail!.tocUrl.trim()
          : candidate.searchItem.bookUrl;

      final updatedBook = currentBook.copyWith(
        sourceId: candidate.source.id,
        providerType: candidate.searchItem.providerType,
        originBookUrl: newOriginUrl,
        tocUrl: newTocUrl,
        coverPath:
            (detail?.coverUrl?.trim().isNotEmpty ?? false)
                ? detail!.coverUrl!.trim()
                : (candidate.searchItem.coverUrl ?? currentBook.coverPath),
        intro: (detail?.intro.trim().isNotEmpty ?? false)
            ? detail!.intro.trim()
            : currentBook.intro,
        totalChapters: normalizedChapters.length,
        lastChapterTitle: normalizedChapters.last.title,
        latestChapterAt: now,
        updatedAt: now,
      );

      await bookRepo.saveBook(updatedBook);
      if (!_isAlive) return null;
      await bookRepo.replaceChapters(currentBook.id, normalizedChapters);
      if (!_isAlive) return null;

      final existingProgress = await bookRepo.getProgress(currentBook.id);
      if (!_isAlive) return null;
      final targetChapter = normalizedChapters[clampedIndex];
      await bookRepo.saveProgress(
        ReadingProgress(
          bookId: currentBook.id,
          chapterIndex: clampedIndex,
          charOffset: 0,
          chapterTitleSnapshot: targetChapter.title,
          progressPercent: (clampedIndex + 1) / normalizedChapters.length,
          readingDurationSec: existingProgress?.readingDurationSec ?? 0,
          updatedAt: now,
        ),
      );
      if (!_isAlive) return null;

      state = state.copyWith(isSwitching: false, book: updatedBook);
      return ChangeSourceSwitchResult(
        updatedBook: updatedBook,
        chapters: normalizedChapters,
        targetChapterIndex: clampedIndex,
        targetChapterTitle: targetChapter.title,
      );
    } catch (error) {
      if (!_isAlive) return null;
      state = state.copyWith(
        isSwitching: false,
        errorMessage: error is AppFailure ? error.message : '切换书源失败：$error',
      );
      return null;
    }
  }

  List<ChangeSourceCandidate> _sortCandidates(
    List<ChangeSourceCandidate> input,
  ) {
    final sorted = List<ChangeSourceCandidate>.of(input)
      ..sort((a, b) {
        if (a.isCurrentSource != b.isCurrentSource) {
          return a.isCurrentSource ? 1 : -1;
        }
        final wCmp = b.source.weight.compareTo(a.source.weight);
        if (wCmp != 0) return wCmp;
        return a.source.name.compareTo(b.source.name);
      });
    return List<ChangeSourceCandidate>.unmodifiable(sorted);
  }

  static String _normalizeMeta(String raw) => raw
      .trim()
      .replaceAll('《', '')
      .replaceAll('》', '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();

  static String _normalizeAuthor(String raw) => raw
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceFirst(RegExp(r'^作者[:：]'), '')
      .replaceFirst(RegExp(r'著$'), '')
      .toLowerCase();
}
