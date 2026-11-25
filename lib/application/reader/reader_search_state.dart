import 'in_book_search_service.dart';

/// Immutable UI/application state exposed by [ReaderSearchController].
class ReaderSearchState {
  final String bookId;
  final String query;
  final InBookSearchScope scope;
  final bool isSearching;
  final List<InBookSearchMatch> matches;
  final bool isCapped;
  final int scannedChapters;
  final int totalCandidateChapters;
  final int skippedUncachedChapters;
  final String? errorMessage;
  final bool hasSearched;

  const ReaderSearchState({
    required this.bookId,
    this.query = '',
    this.scope = InBookSearchScope.wholeBook,
    this.isSearching = false,
    this.matches = const <InBookSearchMatch>[],
    this.isCapped = false,
    this.scannedChapters = 0,
    this.totalCandidateChapters = 0,
    this.skippedUncachedChapters = 0,
    this.errorMessage,
    this.hasSearched = false,
  });

  ReaderSearchState copyWith({
    String? query,
    InBookSearchScope? scope,
    bool? isSearching,
    List<InBookSearchMatch>? matches,
    bool? isCapped,
    int? scannedChapters,
    int? totalCandidateChapters,
    int? skippedUncachedChapters,
    String? errorMessage,
    bool clearError = false,
    bool? hasSearched,
  }) {
    return ReaderSearchState(
      bookId: bookId,
      query: query ?? this.query,
      scope: scope ?? this.scope,
      isSearching: isSearching ?? this.isSearching,
      matches: matches ?? this.matches,
      isCapped: isCapped ?? this.isCapped,
      scannedChapters: scannedChapters ?? this.scannedChapters,
      totalCandidateChapters:
          totalCandidateChapters ?? this.totalCandidateChapters,
      skippedUncachedChapters:
          skippedUncachedChapters ?? this.skippedUncachedChapters,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}
