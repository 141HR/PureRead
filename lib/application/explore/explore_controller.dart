import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import '../search/book_detail_controller.dart';
import '../search/book_detail_state.dart';
import '../search/search_controller.dart';
import '../search/search_state.dart';
import 'explore_state.dart';

final exploreControllerProvider =
    NotifierProvider<ExploreController, ExploreState>(ExploreController.new);

/// Dedicated [BookDetailController] provider for Explore detail preview so it
/// never clobbers SearchPage's [bookDetailControllerProvider].
final exploreBookDetailControllerProvider =
    NotifierProvider<BookDetailController, BookDetailState>(
      BookDetailController.new,
    );

/// Orchestrates online book source discovery/rankings browsing, per-source
/// category caching, paginated feed loading with URL deduplication,
/// cooperative request cancellation, and isolated detail preview loading.
class ExploreController extends Notifier<ExploreState> {
  bool _disposed = false;
  int _sourcesEpoch = 0;
  int _sourceEpoch = 0;
  int _booksEpoch = 0;
  CancellationToken? _categoryCancelToken;
  CancellationToken? _booksCancelToken;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  ExploreState build() {
    _disposed = false;
    _sourcesEpoch = 0;
    _sourceEpoch = 0;
    _booksEpoch = 0;
    ref.onDispose(() {
      _disposed = true;
      _cancelCategoryLoad();
      _cancelBooksLoad();
    });
    return const ExploreState();
  }

  /// Loads enabled online sources supporting explore, isolating malformed source
  /// definitions, and sorting valid sources by `weight DESC, name ASC`.
  Future<void> loadExploreSources({bool forceRefresh = false}) async {
    if (!_isAlive) return;

    final epoch = ++_sourcesEpoch;
    state = state.copyWith(
      isLoadingSources: true,
      clearError: true,
      categoryCacheBySourceId: forceRefresh
          ? const <String, List<ExploreCategory>>{}
          : state.categoryCacheBySourceId,
    );

    final sourceRepo = ref.read(sourceRepositoryProvider);
    final explorableSources = <BookSource>[];
    try {
      final fetched = await sourceRepo.listSources(enabledOnly: true);
      if (!_isAlive || epoch != _sourcesEpoch) return;

      for (final source in fetched) {
        if (!_isAlive || epoch != _sourcesEpoch) return;
        if (!source.enabled) continue;
        try {
          final provider = await _resolveExplorableProvider(source);
          if (!_isAlive || epoch != _sourcesEpoch) return;
          if (provider != null) {
            explorableSources.add(source);
          }
        } catch (_) {
          // Isolate broken source JSON/definitions so valid sources still load.
        }
      }
    } catch (error) {
      if (!_isAlive || epoch != _sourcesEpoch) return;
      state = state.copyWith(
        isLoadingSources: false,
        errorMessage: _formatError(error, '加载发现书源失败'),
      );
      return;
    }

    if (!_isAlive || epoch != _sourcesEpoch) return;

    explorableSources.sort((a, b) {
      final weightCmp = b.weight.compareTo(a.weight);
      if (weightCmp != 0) return weightCmp;
      final nameCmp = a.name.compareTo(b.name);
      if (nameCmp != 0) return nameCmp;
      return a.id.compareTo(b.id);
    });

    final sorted = List<BookSource>.unmodifiable(explorableSources);
    if (sorted.isEmpty) {
      _cancelCategoryLoad();
      _cancelBooksLoad();
      _sourceEpoch++;
      _booksEpoch++;
      state = state.copyWith(
        exploreSources: sorted,
        clearSelectedSource: true,
        isLoadingSources: false,
        isLoadingCategories: false,
        categories: const <ExploreCategory>[],
        clearSelectedCategory: true,
        items: const <BookSearchItem>[],
        currentPage: 1,
        isLoadingBooks: false,
        isLoadingMore: false,
        hasMore: false,
        clearSelectedBookUrl: true,
        clearLastTrace: true,
      );
      return;
    }

    final currentSelectedId = state.selectedSourceId;
    final isSelectedStillValid =
        currentSelectedId != null &&
        sorted.any((source) => source.id == currentSelectedId);

    state = state.copyWith(
      exploreSources: sorted,
      isLoadingSources: false,
    );

    if (isSelectedStillValid) {
      if (forceRefresh ||
          !state.categoryCacheBySourceId.containsKey(currentSelectedId)) {
        await selectSource(
          currentSelectedId,
          forceReloadCategories: forceRefresh,
        );
      }
      return;
    }

    await selectSource(
      sorted.first.id,
      forceReloadCategories: forceRefresh,
    );
  }

  /// Updates the filter query applied by [ExploreState.filteredSources].
  void setSourceFilterQuery(String query) {
    if (!_isAlive) return;
    state = state.copyWith(sourceFilterQuery: query);
  }

  /// Selects an explore source by [sourceId], reusing cached categories unless
  /// [forceReloadCategories] is true or missing, and auto-selecting the first
  /// clickable category.
  Future<void> selectSource(
    String sourceId, {
    bool forceReloadCategories = false,
  }) async {
    if (!_isAlive) return;

    _cancelCategoryLoad();
    _cancelBooksLoad();
    final sourceEpoch = ++_sourceEpoch;
    _booksEpoch++;

    final cachedCategories = forceReloadCategories
        ? null
        : state.categoryCacheBySourceId[sourceId];

    state = state.copyWith(
      selectedSourceId: sourceId,
      isLoadingCategories: cachedCategories == null,
      categories: cachedCategories ?? const <ExploreCategory>[],
      clearSelectedCategory: true,
      items: const <BookSearchItem>[],
      currentPage: 1,
      isLoadingBooks: false,
      isLoadingMore: false,
      hasMore: false,
      clearSelectedBookUrl: true,
      clearLastTrace: true,
      clearError: true,
    );

    if (cachedCategories != null) {
      final firstClickable = _firstClickableCategory(cachedCategories);
      if (firstClickable != null) {
        await selectCategory(firstClickable);
      }
      return;
    }

    final token = CancellationToken();
    _categoryCancelToken = token;

    try {
      final source = await _resolveSource(sourceId);
      if (!_isAlive || sourceEpoch != _sourceEpoch || token.isCancelled) return;
      if (source == null) {
        state = state.copyWith(
          isLoadingCategories: false,
          errorMessage: '未找到书源 ($sourceId)',
        );
        return;
      }

      final provider = await _resolveExplorableProvider(source);
      if (!_isAlive || sourceEpoch != _sourceEpoch || token.isCancelled) return;
      if (provider == null) {
        state = state.copyWith(
          isLoadingCategories: false,
          errorMessage: '书源「${source.name}」不支持发现功能',
        );
        return;
      }

      final result = await provider.getExploreCategories(cancelToken: token);
      if (!_isAlive || sourceEpoch != _sourceEpoch || token.isCancelled) return;

      final categories = List<ExploreCategory>.unmodifiable(result.categories);
      final nextCache = Map<String, List<ExploreCategory>>.from(
        state.categoryCacheBySourceId,
      )..[sourceId] = categories;

      state = state.copyWith(
        isLoadingCategories: false,
        categories: categories,
        categoryCacheBySourceId:
            Map<String, List<ExploreCategory>>.unmodifiable(nextCache),
        lastTrace: result.trace,
      );

      final firstClickable = _firstClickableCategory(categories);
      if (firstClickable != null) {
        await selectCategory(firstClickable);
      }
    } on CancelledFailure {
      return;
    } catch (error) {
      if (!_isAlive || sourceEpoch != _sourceEpoch || token.isCancelled) return;
      state = state.copyWith(
        isLoadingCategories: false,
        errorMessage: _formatError(error, '加载发现分类失败'),
      );
    } finally {
      if (identical(_categoryCancelToken, token)) {
        _categoryCancelToken = null;
      }
      token.dispose();
    }
  }

  /// Selects a clickable [category] and loads page 1 of its books.
  Future<void> selectCategory(ExploreCategory category) async {
    if (!_isAlive || category.isGroupHeader) return;
    final sourceId = state.selectedSourceId;
    if (sourceId == null) return;

    _cancelBooksLoad();
    final epoch = ++_booksEpoch;
    final token = CancellationToken();
    _booksCancelToken = token;

    state = state.copyWith(
      selectedCategory: category,
      items: const <BookSearchItem>[],
      currentPage: 1,
      isLoadingBooks: true,
      isLoadingMore: false,
      hasMore: false,
      clearSelectedBookUrl: true,
      clearError: true,
    );

    final result = await _executeExploreFetch(
      sourceId: sourceId,
      category: category,
      page: 1,
      epoch: epoch,
      cancelToken: token,
      errorPrefix: '加载发现书籍失败',
      onFailure: (message) {
        state = state.copyWith(
          isLoadingBooks: false,
          hasMore: false,
          errorMessage: message,
        );
      },
    );
    if (result == null) return;

    final items = List<BookSearchItem>.unmodifiable(result.items);
    state = state.copyWith(
      items: items,
      currentPage: 1,
      isLoadingBooks: false,
      hasMore: items.isNotEmpty,
      lastTrace: result.trace,
    );
  }

  /// Reloads the currently selected category from page 1.
  Future<void> refreshCurrentCategory() async {
    if (!_isAlive) return;
    final currentCategory = state.selectedCategory;
    if (currentCategory != null) {
      await selectCategory(currentCategory);
      return;
    }
    final sourceId = state.selectedSourceId;
    if (sourceId != null) {
      await selectSource(sourceId, forceReloadCategories: true);
    }
  }

  /// Loads `currentPage + 1` for the selected category, deduplicating appended
  /// entries by `bookUrl` and stopping pagination when no new items arrive.
  Future<void> loadNextPage() async {
    if (!_isAlive) return;
    if (state.isLoadingSources ||
        state.isLoadingCategories ||
        state.isLoadingBooks ||
        state.isLoadingMore ||
        !state.hasMore ||
        state.items.isEmpty) {
      return;
    }

    final category = state.selectedCategory;
    final sourceId = state.selectedSourceId;
    if (category == null || category.isGroupHeader || sourceId == null) {
      return;
    }

    _cancelBooksLoad();
    final epoch = ++_booksEpoch;
    final token = CancellationToken();
    _booksCancelToken = token;
    final nextPage = state.currentPage + 1;

    state = state.copyWith(
      isLoadingMore: true,
      clearError: true,
    );

    final result = await _executeExploreFetch(
      sourceId: sourceId,
      category: category,
      page: nextPage,
      epoch: epoch,
      cancelToken: token,
      errorPrefix: '加载更多失败',
      onFailure: (message) {
        state = state.copyWith(
          isLoadingMore: false,
          errorMessage: message,
        );
      },
    );
    if (result == null) return;

    final existingUrls = state.items.map((item) => item.bookUrl).toSet();
    final newItems = <BookSearchItem>[];
    for (final item in result.items) {
      if (existingUrls.add(item.bookUrl)) {
        newItems.add(item);
      }
    }

    if (result.items.isEmpty || newItems.isEmpty) {
      state = state.copyWith(
        isLoadingMore: false,
        hasMore: false,
        lastTrace: result.trace,
      );
      return;
    }

    state = state.copyWith(
      items: List<BookSearchItem>.unmodifiable(<BookSearchItem>[
        ...state.items,
        ...newItems,
      ]),
      currentPage: nextPage,
      isLoadingMore: false,
      hasMore: true,
      lastTrace: result.trace,
    );
  }

  /// Selects an explore [item] and loads its single-source preview into the
  /// isolated [exploreBookDetailControllerProvider].
  Future<void> selectBookForDetail(BookSearchItem item) async {
    if (!_isAlive) return;
    state = state.copyWith(selectedBookUrl: item.bookUrl);

    var source = _findSourceInState(item.sourceId);
    if (source == null) {
      try {
        source = await _resolveSource(item.sourceId);
      } catch (_) {
        // Fall back to item metadata when source lookup fails.
      }
      if (!_isAlive || state.selectedBookUrl != item.bookUrl) return;
    }

    final aggregated = AggregatedSearchBook(
      groupKey: SearchController.buildAggregationKey(item.title, item.author),
      title: item.title,
      author: item.author,
      coverUrl: item.coverUrl,
      intro: item.intro,
      latestChapterTitle: item.latestChapterTitle,
      kind: item.kind,
      sources: <AggregatedSearchSourceEntry>[
        AggregatedSearchSourceEntry(
          item: item,
          sourceName: source?.name ?? item.sourceId,
          sourceWeight: source?.weight ?? 0,
        ),
      ],
    );

    await ref
        .read(exploreBookDetailControllerProvider.notifier)
        .loadAggregatedBook(aggregated);
  }

  /// Clears the current transient error banner message.
  void clearError() {
    if (!_isAlive) return;
    state = state.copyWith(clearError: true);
  }

  Future<({List<BookSearchItem> items, SourceDebugTrace trace})?>
  _executeExploreFetch({
    required String sourceId,
    required ExploreCategory category,
    required int page,
    required int epoch,
    required CancellationToken cancelToken,
    required String errorPrefix,
    required void Function(String message) onFailure,
  }) async {
    try {
      final source = await _resolveSource(sourceId);
      if (!_isAlive || epoch != _booksEpoch || cancelToken.isCancelled) {
        return null;
      }
      if (source == null) {
        onFailure('未找到书源 ($sourceId)');
        return null;
      }

      final provider = await _resolveExplorableProvider(source);
      if (!_isAlive || epoch != _booksEpoch || cancelToken.isCancelled) {
        return null;
      }
      if (provider == null) {
        onFailure('书源「${source.name}」不支持发现功能');
        return null;
      }

      final result = await provider.explore(
        category,
        page: page,
        cancelToken: cancelToken,
      );
      if (!_isAlive || epoch != _booksEpoch || cancelToken.isCancelled) {
        return null;
      }
      return result;
    } on CancelledFailure {
      return null;
    } catch (error) {
      if (!_isAlive || epoch != _booksEpoch || cancelToken.isCancelled) {
        return null;
      }
      onFailure(_formatError(error, errorPrefix));
      return null;
    } finally {
      if (identical(_booksCancelToken, cancelToken)) {
        _booksCancelToken = null;
      }
      cancelToken.dispose();
    }
  }

  BookSource? _findSourceInState(String sourceId) {
    for (final source in state.exploreSources) {
      if (source.id == sourceId) return source;
    }
    return null;
  }

  Future<BookSource?> _resolveSource(String sourceId) async {
    return _findSourceInState(sourceId) ??
        await ref.read(sourceRepositoryProvider).getSourceById(sourceId);
  }

  Future<ExplorableBookProvider?> _resolveExplorableProvider(
    BookSource source,
  ) async {
    final provider = await ref
        .read(bookProviderFactoryProvider)
        .createProvider(source);
    if (!provider.capabilities.supportsExplore ||
        provider is! ExplorableBookProvider) {
      return null;
    }
    return provider;
  }

  ExploreCategory? _firstClickableCategory(List<ExploreCategory> categories) {
    for (final category in categories) {
      if (!category.isGroupHeader) return category;
    }
    return null;
  }

  void _cancelCategoryLoad() {
    _categoryCancelToken?.cancel();
    _categoryCancelToken?.dispose();
    _categoryCancelToken = null;
  }

  void _cancelBooksLoad() {
    _booksCancelToken?.cancel();
    _booksCancelToken?.dispose();
    _booksCancelToken = null;
  }

  String _formatError(Object error, String prefix) {
    if (error is AppFailure) return error.message;
    return '$prefix：$error';
  }
}
