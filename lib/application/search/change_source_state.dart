import '../../domain/domain.dart';
import 'chapter_title_matcher.dart';

/// A single candidate source option presented during source switching.
class ChangeSourceCandidate {
  final BookSource source;
  final BookSearchItem searchItem;
  final bool isCurrentSource;
  final BookDetail? detail;
  final List<ChapterMeta>? chapters;
  final ChapterMatchResult? matchResult;
  final bool isLoadingToc;
  final String? errorMessage;

  const ChangeSourceCandidate({
    required this.source,
    required this.searchItem,
    this.isCurrentSource = false,
    this.detail,
    this.chapters,
    this.matchResult,
    this.isLoadingToc = false,
    this.errorMessage,
  });

  String get latestChapterDisplay {
    final detailLatest = detail?.latestChapterTitle.trim() ?? '';
    if (detailLatest.isNotEmpty) return detailLatest;
    if (chapters != null && chapters!.isNotEmpty) {
      return chapters!.last.title;
    }
    final searchLatest = searchItem.latestChapterTitle.trim();
    return searchLatest.isNotEmpty ? searchLatest : '未知最新章节';
  }

  ChangeSourceCandidate copyWith({
    BookSource? source,
    BookSearchItem? searchItem,
    bool? isCurrentSource,
    BookDetail? detail,
    List<ChapterMeta>? chapters,
    ChapterMatchResult? matchResult,
    bool? isLoadingToc,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChangeSourceCandidate(
      source: source ?? this.source,
      searchItem: searchItem ?? this.searchItem,
      isCurrentSource: isCurrentSource ?? this.isCurrentSource,
      detail: detail ?? this.detail,
      chapters: chapters ?? this.chapters,
      matchResult: matchResult ?? this.matchResult,
      isLoadingToc: isLoadingToc ?? this.isLoadingToc,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Payload returned when a source switch completes and persists.
class ChangeSourceSwitchResult {
  final Book updatedBook;
  final List<ChapterMeta> chapters;
  final int targetChapterIndex;
  final String targetChapterTitle;

  const ChangeSourceSwitchResult({
    required this.updatedBook,
    required this.chapters,
    required this.targetChapterIndex,
    required this.targetChapterTitle,
  });
}

/// Immutable state managed by [ChangeSourceController].
class ChangeSourceState {
  final Book? book;
  final int currentChapterIndex;
  final String currentChapterTitle;
  final bool isSearching;
  final int totalSources;
  final int completedSources;
  final List<ChangeSourceCandidate> candidates;
  final int? selectedCandidateIndex;
  final int? selectedTargetChapterIndex;
  final bool showManualPicker;
  final String chapterFilterQuery;
  final bool isSwitching;
  final String? errorMessage;

  const ChangeSourceState({
    this.book,
    this.currentChapterIndex = 0,
    this.currentChapterTitle = '',
    this.isSearching = false,
    this.totalSources = 0,
    this.completedSources = 0,
    this.candidates = const <ChangeSourceCandidate>[],
    this.selectedCandidateIndex,
    this.selectedTargetChapterIndex,
    this.showManualPicker = false,
    this.chapterFilterQuery = '',
    this.isSwitching = false,
    this.errorMessage,
  });

  ChangeSourceCandidate? get selectedCandidate {
    final idx = selectedCandidateIndex;
    if (idx == null || idx < 0 || idx >= candidates.length) return null;
    return candidates[idx];
  }

  List<ChapterMeta> get filteredSelectedChapters {
    final chapters = selectedCandidate?.chapters ?? const <ChapterMeta>[];
    final query = chapterFilterQuery.trim().toLowerCase();
    if (query.isEmpty) return chapters;
    return chapters
        .where((c) => c.title.toLowerCase().contains(query))
        .toList(growable: false);
  }

  ChangeSourceState copyWith({
    Book? book,
    int? currentChapterIndex,
    String? currentChapterTitle,
    bool? isSearching,
    int? totalSources,
    int? completedSources,
    List<ChangeSourceCandidate>? candidates,
    int? selectedCandidateIndex,
    bool clearSelectedCandidate = false,
    int? selectedTargetChapterIndex,
    bool clearSelectedTargetChapter = false,
    bool? showManualPicker,
    String? chapterFilterQuery,
    bool? isSwitching,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChangeSourceState(
      book: book ?? this.book,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      currentChapterTitle: currentChapterTitle ?? this.currentChapterTitle,
      isSearching: isSearching ?? this.isSearching,
      totalSources: totalSources ?? this.totalSources,
      completedSources: completedSources ?? this.completedSources,
      candidates: candidates ?? this.candidates,
      selectedCandidateIndex: clearSelectedCandidate
          ? null
          : (selectedCandidateIndex ?? this.selectedCandidateIndex),
      selectedTargetChapterIndex: clearSelectedTargetChapter
          ? null
          : (selectedTargetChapterIndex ?? this.selectedTargetChapterIndex),
      showManualPicker: showManualPicker ?? this.showManualPicker,
      chapterFilterQuery: chapterFilterQuery ?? this.chapterFilterQuery,
      isSwitching: isSwitching ?? this.isSwitching,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
