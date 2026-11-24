import '../../domain/domain.dart';

/// Display layout mode for the bookshelf.
enum BookshelfViewMode { grid, list }

/// Sort order options for bookshelf entries (pinned books always stay on top).
enum BookshelfSortMode { recentRead, updatedAt, title }

/// Immutable state managed by [BookshelfController].
class BookshelfState {
  final List<Book> books;
  final Map<String, ReadingProgress> progressByBookId;
  final BookshelfViewMode viewMode;
  final BookshelfSortMode sortMode;
  final bool isLoading;
  final bool isImporting;
  final int importDoneCount;
  final int importTotalCount;
  final String? importStatusMessage;
  final String? errorMessage;
  final String searchQuery;

  const BookshelfState({
    this.books = const <Book>[],
    this.progressByBookId = const <String, ReadingProgress>{},
    this.viewMode = BookshelfViewMode.grid,
    this.sortMode = BookshelfSortMode.recentRead,
    this.isLoading = false,
    this.isImporting = false,
    this.importDoneCount = 0,
    this.importTotalCount = 0,
    this.importStatusMessage,
    this.errorMessage,
    this.searchQuery = '',
  });

  List<Book> get filteredBooks {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return books;
    return books
        .where(
          (book) =>
              book.title.toLowerCase().contains(query) ||
              book.author.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  BookshelfState copyWith({
    List<Book>? books,
    Map<String, ReadingProgress>? progressByBookId,
    BookshelfViewMode? viewMode,
    BookshelfSortMode? sortMode,
    bool? isLoading,
    bool? isImporting,
    int? importDoneCount,
    int? importTotalCount,
    String? importStatusMessage,
    bool clearImportStatus = false,
    String? errorMessage,
    bool clearError = false,
    String? searchQuery,
  }) {
    return BookshelfState(
      books: books ?? this.books,
      progressByBookId: progressByBookId ?? this.progressByBookId,
      viewMode: viewMode ?? this.viewMode,
      sortMode: sortMode ?? this.sortMode,
      isLoading: isLoading ?? this.isLoading,
      isImporting: isImporting ?? this.isImporting,
      importDoneCount: importDoneCount ?? this.importDoneCount,
      importTotalCount: importTotalCount ?? this.importTotalCount,
      importStatusMessage: clearImportStatus
          ? null
          : (importStatusMessage ?? this.importStatusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}
