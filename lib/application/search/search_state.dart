import '../../domain/domain.dart';

/// A single source's hit inside an [AggregatedSearchBook].
class AggregatedSearchSourceEntry {
  final BookSearchItem item;
  final String sourceName;
  final int sourceWeight;

  const AggregatedSearchSourceEntry({
    required this.item,
    required this.sourceName,
    required this.sourceWeight,
  });
}

/// Search result aggregated across multiple enabled sources by `(title, author)`.
class AggregatedSearchBook {
  final String groupKey;
  final String title;
  final String author;
  final String? coverUrl;
  final String intro;
  final String latestChapterTitle;
  final String? kind;
  final List<AggregatedSearchSourceEntry> sources;

  const AggregatedSearchBook({
    required this.groupKey,
    required this.title,
    required this.author,
    this.coverUrl,
    this.intro = '',
    this.latestChapterTitle = '',
    this.kind,
    required this.sources,
  });

  int get sourceCount => sources.length;

  int get bestWeight =>
      sources.isEmpty ? 0 : sources.first.sourceWeight;

  AggregatedSearchBook copyWith({
    String? groupKey,
    String? title,
    String? author,
    String? coverUrl,
    String? intro,
    String? latestChapterTitle,
    String? kind,
    List<AggregatedSearchSourceEntry>? sources,
  }) {
    return AggregatedSearchBook(
      groupKey: groupKey ?? this.groupKey,
      title: title ?? this.title,
      author: author ?? this.author,
      coverUrl: coverUrl ?? this.coverUrl,
      intro: intro ?? this.intro,
      latestChapterTitle: latestChapterTitle ?? this.latestChapterTitle,
      kind: kind ?? this.kind,
      sources: sources ?? this.sources,
    );
  }
}

/// Immutable state managed by [SearchController].
class SearchState {
  final String query;
  final bool isSearching;
  final int totalSources;
  final int completedSources;
  final List<AggregatedSearchBook> results;
  final Map<String, String> sourceErrors;
  final String? selectedGroupKey;
  final String? errorMessage;

  const SearchState({
    this.query = '',
    this.isSearching = false,
    this.totalSources = 0,
    this.completedSources = 0,
    this.results = const <AggregatedSearchBook>[],
    this.sourceErrors = const <String, String>{},
    this.selectedGroupKey,
    this.errorMessage,
  });

  AggregatedSearchBook? get selectedBook {
    if (selectedGroupKey == null) return null;
    for (final book in results) {
      if (book.groupKey == selectedGroupKey) return book;
    }
    return null;
  }

  SearchState copyWith({
    String? query,
    bool? isSearching,
    int? totalSources,
    int? completedSources,
    List<AggregatedSearchBook>? results,
    Map<String, String>? sourceErrors,
    String? selectedGroupKey,
    bool clearSelectedBook = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      totalSources: totalSources ?? this.totalSources,
      completedSources: completedSources ?? this.completedSources,
      results: results ?? this.results,
      sourceErrors: sourceErrors ?? this.sourceErrors,
      selectedGroupKey: clearSelectedBook
          ? null
          : (selectedGroupKey ?? this.selectedGroupKey),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
