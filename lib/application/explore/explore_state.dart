import '../../domain/domain.dart';

/// Immutable state managed by [ExploreController] for online book source
/// discovery and rankings (发现 / 排行榜).
class ExploreState {
  final List<BookSource> exploreSources;
  final String? selectedSourceId;
  final String sourceFilterQuery;
  final bool isLoadingSources;
  final bool isLoadingCategories;
  final List<ExploreCategory> categories;
  final ExploreCategory? selectedCategory;
  final Map<String, List<ExploreCategory>> categoryCacheBySourceId;
  final List<BookSearchItem> items;
  final int currentPage;
  final bool isLoadingBooks;
  final bool isLoadingMore;
  final bool hasMore;
  final String? selectedBookUrl;
  final SourceDebugTrace? lastTrace;
  final String? errorMessage;

  const ExploreState({
    this.exploreSources = const <BookSource>[],
    this.selectedSourceId,
    this.sourceFilterQuery = '',
    this.isLoadingSources = false,
    this.isLoadingCategories = false,
    this.categories = const <ExploreCategory>[],
    this.selectedCategory,
    this.categoryCacheBySourceId = const <String, List<ExploreCategory>>{},
    this.items = const <BookSearchItem>[],
    this.currentPage = 1,
    this.isLoadingBooks = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.selectedBookUrl,
    this.lastTrace,
    this.errorMessage,
  });

  /// Returns [exploreSources] filtered case-insensitively by [name] or
  /// [groupName] using [sourceFilterQuery].
  List<BookSource> get filteredSources {
    final query = sourceFilterQuery.trim().toLowerCase();
    if (query.isEmpty) return exploreSources;
    return exploreSources
        .where(
          (source) =>
              source.name.toLowerCase().contains(query) ||
              source.groupName.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  /// Currently selected [BookSource] within [exploreSources], if present.
  BookSource? get selectedSource {
    final id = selectedSourceId;
    if (id == null) return null;
    for (final source in exploreSources) {
      if (source.id == id) return source;
    }
    return null;
  }

  /// Discovery categories excluding visual group headers.
  List<ExploreCategory> get clickableCategories =>
      categories.where((c) => !c.isGroupHeader).toList(growable: false);

  ExploreState copyWith({
    List<BookSource>? exploreSources,
    String? selectedSourceId,
    bool clearSelectedSource = false,
    String? sourceFilterQuery,
    bool? isLoadingSources,
    bool? isLoadingCategories,
    List<ExploreCategory>? categories,
    ExploreCategory? selectedCategory,
    bool clearSelectedCategory = false,
    Map<String, List<ExploreCategory>>? categoryCacheBySourceId,
    List<BookSearchItem>? items,
    int? currentPage,
    bool? isLoadingBooks,
    bool? isLoadingMore,
    bool? hasMore,
    String? selectedBookUrl,
    bool clearSelectedBookUrl = false,
    SourceDebugTrace? lastTrace,
    bool clearLastTrace = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ExploreState(
      exploreSources: exploreSources ?? this.exploreSources,
      selectedSourceId: clearSelectedSource
          ? null
          : (selectedSourceId ?? this.selectedSourceId),
      sourceFilterQuery: sourceFilterQuery ?? this.sourceFilterQuery,
      isLoadingSources: isLoadingSources ?? this.isLoadingSources,
      isLoadingCategories: isLoadingCategories ?? this.isLoadingCategories,
      categories: categories ?? this.categories,
      selectedCategory: clearSelectedCategory
          ? null
          : (selectedCategory ?? this.selectedCategory),
      categoryCacheBySourceId:
          categoryCacheBySourceId ?? this.categoryCacheBySourceId,
      items: items ?? this.items,
      currentPage: currentPage ?? this.currentPage,
      isLoadingBooks: isLoadingBooks ?? this.isLoadingBooks,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      selectedBookUrl: clearSelectedBookUrl
          ? null
          : (selectedBookUrl ?? this.selectedBookUrl),
      lastTrace: clearLastTrace ? null : (lastTrace ?? this.lastTrace),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
