import '../../domain/domain.dart';

/// Ordered pipeline steps executed by [SourceDebugController].
enum DebugStepKind { search, detail, toc, content }

/// Execution status of a single step in [SourceDebugState].
enum DebugStepStatus { idle, running, success, failed, cancelled, skipped }

/// Diagnostic record for a single pipeline step (`search`, `detail`, `toc`,
/// or `content`).
class DebugStepReport {
  final DebugStepKind step;
  final DebugStepStatus status;
  final SourceDebugTrace? trace;
  final String? summary;
  final String? errorMessage;
  final String? stackPreview;

  const DebugStepReport({
    required this.step,
    this.status = DebugStepStatus.idle,
    this.trace,
    this.summary,
    this.errorMessage,
    this.stackPreview,
  });

  DebugStepReport copyWith({
    DebugStepStatus? status,
    SourceDebugTrace? trace,
    String? summary,
    String? errorMessage,
    String? stackPreview,
  }) {
    return DebugStepReport(
      step: step,
      status: status ?? this.status,
      trace: trace ?? this.trace,
      summary: summary ?? this.summary,
      errorMessage: errorMessage ?? this.errorMessage,
      stackPreview: stackPreview ?? this.stackPreview,
    );
  }
}

/// Immutable state managed by [SourceDebugController].
class SourceDebugState {
  final String? selectedSourceId;
  final String keyword;
  final int selectedChapterIndex;
  final bool isRunning;
  final DebugStepKind? currentStep;
  final Map<DebugStepKind, DebugStepReport> steps;
  final List<BookSearchItem> searchItems;
  final BookDetail? detail;
  final List<ChapterMeta> chapters;
  final ChapterContent? rawContent;
  final String? sanitizedContent;
  final String? errorMessage;

  const SourceDebugState({
    this.selectedSourceId,
    this.keyword = '凡人修仙传',
    this.selectedChapterIndex = 0,
    this.isRunning = false,
    this.currentStep,
    this.steps = const <DebugStepKind, DebugStepReport>{
      DebugStepKind.search: DebugStepReport(step: DebugStepKind.search),
      DebugStepKind.detail: DebugStepReport(step: DebugStepKind.detail),
      DebugStepKind.toc: DebugStepReport(step: DebugStepKind.toc),
      DebugStepKind.content: DebugStepReport(step: DebugStepKind.content),
    },
    this.searchItems = const <BookSearchItem>[],
    this.detail,
    this.chapters = const <ChapterMeta>[],
    this.rawContent,
    this.sanitizedContent,
    this.errorMessage,
  });

  static Map<DebugStepKind, DebugStepReport> initialSteps() {
    return const <DebugStepKind, DebugStepReport>{
      DebugStepKind.search: DebugStepReport(step: DebugStepKind.search),
      DebugStepKind.detail: DebugStepReport(step: DebugStepKind.detail),
      DebugStepKind.toc: DebugStepReport(step: DebugStepKind.toc),
      DebugStepKind.content: DebugStepReport(step: DebugStepKind.content),
    };
  }

  SourceDebugState copyWith({
    String? selectedSourceId,
    bool clearSelectedSource = false,
    String? keyword,
    int? selectedChapterIndex,
    bool? isRunning,
    DebugStepKind? currentStep,
    bool clearCurrentStep = false,
    Map<DebugStepKind, DebugStepReport>? steps,
    List<BookSearchItem>? searchItems,
    BookDetail? detail,
    bool clearDetail = false,
    List<ChapterMeta>? chapters,
    ChapterContent? rawContent,
    bool clearContent = false,
    String? sanitizedContent,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SourceDebugState(
      selectedSourceId: clearSelectedSource
          ? null
          : (selectedSourceId ?? this.selectedSourceId),
      keyword: keyword ?? this.keyword,
      selectedChapterIndex: selectedChapterIndex ?? this.selectedChapterIndex,
      isRunning: isRunning ?? this.isRunning,
      currentStep: clearCurrentStep ? null : (currentStep ?? this.currentStep),
      steps: steps ?? this.steps,
      searchItems: searchItems ?? this.searchItems,
      detail: clearDetail ? null : (detail ?? this.detail),
      chapters: chapters ?? this.chapters,
      rawContent: clearContent ? null : (rawContent ?? this.rawContent),
      sanitizedContent: clearContent
          ? null
          : (sanitizedContent ?? this.sanitizedContent),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
