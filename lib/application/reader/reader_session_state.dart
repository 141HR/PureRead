import '../../domain/domain.dart';

/// Immutable state exposed by [ReaderSessionController].
class ReaderSessionState {
  final String bookId;
  final bool isLoading;
  final bool isPaginating;
  final String? errorMessage;
  final Book? book;
  final List<ChapterMeta> chapters;
  final int currentChapterIndex;
  final int anchorOffset;
  final String currentChapterText;
  final List<PageSlice> currentPages;
  final int currentPageIndex;
  final int columnCount;
  final PaginationConfig? paginationConfig;
  final List<ReaderTheme> availableThemes;
  final ReaderTheme activeTheme;
  final List<Bookmark> bookmarks;
  final List<ReadingAnchor> jumpUndoStack;
  final bool keepScreenOn;
  final bool volumeKeyPaging;
  final bool isImmersive;
  final bool safeAreaEnabled;
  final bool showOverlay;
  final bool isTocReversed;

  const ReaderSessionState({
    required this.bookId,
    this.isLoading = true,
    this.isPaginating = false,
    this.errorMessage,
    this.book,
    this.chapters = const <ChapterMeta>[],
    this.currentChapterIndex = 0,
    this.anchorOffset = 0,
    this.currentChapterText = '',
    this.currentPages = const <PageSlice>[],
    this.currentPageIndex = 0,
    this.columnCount = 1,
    this.paginationConfig,
    this.availableThemes = const <ReaderTheme>[],
    required this.activeTheme,
    this.bookmarks = const <Bookmark>[],
    this.jumpUndoStack = const <ReadingAnchor>[],
    this.keepScreenOn = false,
    this.volumeKeyPaging = false,
    this.isImmersive = false,
    this.safeAreaEnabled = true,
    this.showOverlay = false,
    this.isTocReversed = false,
  });

  String get currentChapterTitle {
    if (currentChapterIndex >= 0 && currentChapterIndex < chapters.length) {
      return chapters[currentChapterIndex].title;
    }
    return book?.title ?? '';
  }

  PageSlice? get leftPage {
    if (currentPages.isEmpty) return null;
    final idx = currentPageIndex.clamp(0, currentPages.length - 1);
    return currentPages[idx];
  }

  PageSlice? get rightPage {
    if (columnCount != 2 || currentPages.isEmpty) return null;
    final rightIdx = currentPageIndex + 1;
    if (rightIdx < 0 || rightIdx >= currentPages.length) return null;
    return currentPages[rightIdx];
  }

  bool get canUndoJump => jumpUndoStack.isNotEmpty;

  bool get canGoPrev =>
      currentPageIndex > 0 || currentChapterIndex > 0;

  bool get canGoNext {
    if (currentPages.isNotEmpty &&
        currentPageIndex + columnCount < currentPages.length) {
      return true;
    }
    return currentChapterIndex + 1 < chapters.length;
  }

  double get overallProgressPercent {
    if (chapters.isEmpty) return 0.0;
    final chapterLen = currentChapterText.length;
    final intraRatio = chapterLen > 0
        ? (anchorOffset / chapterLen).clamp(0.0, 0.9999)
        : 0.0;
    return ((currentChapterIndex + intraRatio) / chapters.length).clamp(
      0.0,
      1.0,
    );
  }

  ReaderSessionState copyWith({
    bool? isLoading,
    bool? isPaginating,
    String? errorMessage,
    bool clearError = false,
    Book? book,
    List<ChapterMeta>? chapters,
    int? currentChapterIndex,
    int? anchorOffset,
    String? currentChapterText,
    List<PageSlice>? currentPages,
    int? currentPageIndex,
    int? columnCount,
    PaginationConfig? paginationConfig,
    List<ReaderTheme>? availableThemes,
    ReaderTheme? activeTheme,
    List<Bookmark>? bookmarks,
    List<ReadingAnchor>? jumpUndoStack,
    bool? keepScreenOn,
    bool? volumeKeyPaging,
    bool? isImmersive,
    bool? safeAreaEnabled,
    bool? showOverlay,
    bool? isTocReversed,
  }) {
    return ReaderSessionState(
      bookId: bookId,
      isLoading: isLoading ?? this.isLoading,
      isPaginating: isPaginating ?? this.isPaginating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      book: book ?? this.book,
      chapters: chapters ?? this.chapters,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      anchorOffset: anchorOffset ?? this.anchorOffset,
      currentChapterText: currentChapterText ?? this.currentChapterText,
      currentPages: currentPages ?? this.currentPages,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      columnCount: columnCount ?? this.columnCount,
      paginationConfig: paginationConfig ?? this.paginationConfig,
      availableThemes: availableThemes ?? this.availableThemes,
      activeTheme: activeTheme ?? this.activeTheme,
      bookmarks: bookmarks ?? this.bookmarks,
      jumpUndoStack: jumpUndoStack ?? this.jumpUndoStack,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      volumeKeyPaging: volumeKeyPaging ?? this.volumeKeyPaging,
      isImmersive: isImmersive ?? this.isImmersive,
      safeAreaEnabled: safeAreaEnabled ?? this.safeAreaEnabled,
      showOverlay: showOverlay ?? this.showOverlay,
      isTocReversed: isTocReversed ?? this.isTocReversed,
    );
  }
}
