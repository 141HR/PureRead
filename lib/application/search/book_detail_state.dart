import '../../domain/domain.dart';
import 'search_state.dart';

/// Immutable state managed by [BookDetailController].
class BookDetailState {
  final AggregatedSearchBook? aggregatedBook;
  final int selectedSourceIndex;
  final BookDetail? detail;
  final List<ChapterMeta> chapters;
  final Book? existingBookshelfBook;
  final bool isLoadingDetail;
  final bool isLoadingToc;
  final bool isSavingToShelf;
  final SourceDebugTrace? detailTrace;
  final SourceDebugTrace? tocTrace;
  final String? errorMessage;
  final String? statusMessage;

  const BookDetailState({
    this.aggregatedBook,
    this.selectedSourceIndex = 0,
    this.detail,
    this.chapters = const <ChapterMeta>[],
    this.existingBookshelfBook,
    this.isLoadingDetail = false,
    this.isLoadingToc = false,
    this.isSavingToShelf = false,
    this.detailTrace,
    this.tocTrace,
    this.errorMessage,
    this.statusMessage,
  });

  AggregatedSearchSourceEntry? get activeSourceEntry {
    final book = aggregatedBook;
    if (book == null || book.sources.isEmpty) return null;
    final idx = selectedSourceIndex.clamp(0, book.sources.length - 1);
    return book.sources[idx];
  }

  bool get isOnBookshelf => existingBookshelfBook != null;

  bool get isBusy => isLoadingDetail || isLoadingToc || isSavingToShelf;

  String get displayTitle {
    final detailTitle = detail?.title.trim() ?? '';
    if (detailTitle.isNotEmpty) return detailTitle;
    return aggregatedBook?.title ?? '';
  }

  String get displayAuthor {
    final detailAuthor = detail?.author.trim() ?? '';
    if (detailAuthor.isNotEmpty) return detailAuthor;
    return aggregatedBook?.author ?? '';
  }

  String get displayIntro {
    final detailIntro = detail?.intro.trim() ?? '';
    if (detailIntro.isNotEmpty) return detailIntro;
    return aggregatedBook?.intro ?? '';
  }

  String? get displayCoverUrl {
    final detailCover = detail?.coverUrl?.trim();
    if (detailCover != null && detailCover.isNotEmpty) return detailCover;
    return aggregatedBook?.coverUrl;
  }

  BookDetailState copyWith({
    AggregatedSearchBook? aggregatedBook,
    bool clearAggregatedBook = false,
    int? selectedSourceIndex,
    BookDetail? detail,
    bool clearDetail = false,
    List<ChapterMeta>? chapters,
    Book? existingBookshelfBook,
    bool clearExistingBook = false,
    bool? isLoadingDetail,
    bool? isLoadingToc,
    bool? isSavingToShelf,
    SourceDebugTrace? detailTrace,
    bool clearDetailTrace = false,
    SourceDebugTrace? tocTrace,
    bool clearTocTrace = false,
    String? errorMessage,
    bool clearError = false,
    String? statusMessage,
    bool clearStatus = false,
  }) {
    return BookDetailState(
      aggregatedBook: clearAggregatedBook
          ? null
          : (aggregatedBook ?? this.aggregatedBook),
      selectedSourceIndex: selectedSourceIndex ?? this.selectedSourceIndex,
      detail: clearDetail ? null : (detail ?? this.detail),
      chapters: chapters ?? this.chapters,
      existingBookshelfBook: clearExistingBook
          ? null
          : (existingBookshelfBook ?? this.existingBookshelfBook),
      isLoadingDetail: isLoadingDetail ?? this.isLoadingDetail,
      isLoadingToc: isLoadingToc ?? this.isLoadingToc,
      isSavingToShelf: isSavingToShelf ?? this.isSavingToShelf,
      detailTrace: clearDetailTrace ? null : (detailTrace ?? this.detailTrace),
      tocTrace: clearTocTrace ? null : (tocTrace ?? this.tocTrace),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      statusMessage: clearStatus
          ? null
          : (statusMessage ?? this.statusMessage),
    );
  }
}
