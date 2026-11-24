import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import 'source_debug_state.dart';
import 'sources_controller.dart';

final sourceDebugControllerProvider =
    NotifierProvider<SourceDebugController, SourceDebugState>(
      SourceDebugController.new,
    );

/// Executes and traces the 4-step online source pipeline
/// (`search -> detail -> toc -> content`) with cooperative cancellation and
/// raw-vs-sanitized text inspection.
class SourceDebugController extends Notifier<SourceDebugState> {
  bool _disposed = false;
  int _runEpoch = 0;
  CancellationToken? _activeCancelToken;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  SourceDebugState build() {
    _disposed = false;
    _runEpoch = 0;
    ref.onDispose(() {
      _disposed = true;
      _activeCancelToken?.cancel();
      _activeCancelToken = null;
    });
    return const SourceDebugState();
  }

  /// Selects the source to debug.
  void selectSource(String? sourceId) {
    if (!_isAlive) return;
    state = state.copyWith(
      selectedSourceId: sourceId,
      clearSelectedSource: sourceId == null,
    );
  }

  /// Updates the search keyword used by step 1 (`search`).
  void setKeyword(String keyword) {
    if (!_isAlive) return;
    state = state.copyWith(keyword: keyword);
  }

  /// Runs the complete `search -> detail -> toc -> content` trace for
  /// [sourceId] (or [SourceDebugState.selectedSourceId]) and [keyword].
  Future<void> startDebug({
    String? sourceId,
    String? keyword,
    int chapterIndex = 0,
  }) async {
    if (!_isAlive) return;

    final targetSourceId = sourceId ?? state.selectedSourceId;
    final targetKeyword = (keyword ?? state.keyword).trim();
    if (targetSourceId == null || targetSourceId.isEmpty) {
      state = state.copyWith(errorMessage: '请先选择要调试的书源');
      return;
    }
    if (targetKeyword.isEmpty) {
      state = state.copyWith(errorMessage: '请输入调试搜索关键词');
      return;
    }

    _activeCancelToken?.cancel();
    final cancelToken = CancellationToken();
    _activeCancelToken = cancelToken;
    final epoch = ++_runEpoch;

    final sourceRepo = ref.read(sourceRepositoryProvider);
    final providerFactory = ref.read(bookProviderFactoryProvider);

    final steps = Map<DebugStepKind, DebugStepReport>.from(
      SourceDebugState.initialSteps(),
    );
    state = SourceDebugState(
      selectedSourceId: targetSourceId,
      keyword: targetKeyword,
      selectedChapterIndex: chapterIndex,
      isRunning: true,
      currentStep: DebugStepKind.search,
      steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
    );

    BookSource? source;
    try {
      source = await sourceRepo.getSourceById(targetSourceId);
      if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;
      if (source == null) {
        state = state.copyWith(
          isRunning: false,
          clearCurrentStep: true,
          errorMessage: '未找到书源 ($targetSourceId)',
        );
        return;
      }

      final provider = await providerFactory.createProvider(source);
      if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;

      // Step 1: search
      _setStep(steps, DebugStepKind.search, DebugStepStatus.running);
      final searchRes = await provider.search(
        targetKeyword,
        page: 1,
        cancelToken: cancelToken,
      );
      if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;

      _setStep(
        steps,
        DebugStepKind.search,
        DebugStepStatus.success,
        trace: searchRes.trace,
        summary: '命中 ${searchRes.items.length} 条书籍结果',
      );
      state = state.copyWith(
        searchItems: searchRes.items,
        steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
      );

      if (searchRes.items.isEmpty) {
        _skipRemainingSteps(steps, DebugStepKind.detail);
        state = state.copyWith(
          isRunning: false,
          clearCurrentStep: true,
          steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
          errorMessage: '搜索无命中结果，已停止后续步骤',
        );
        return;
      }

      // Step 2: detail
      final firstItem = searchRes.items.first;
      state = state.copyWith(currentStep: DebugStepKind.detail);
      _setStep(steps, DebugStepKind.detail, DebugStepStatus.running);
      final detailRes = await provider.getBookDetail(
        firstItem.bookUrl,
        cancelToken: cancelToken,
      );
      if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;

      _setStep(
        steps,
        DebugStepKind.detail,
        DebugStepStatus.success,
        trace: detailRes.trace,
        summary: '书名：${detailRes.detail.title} · 作者：${detailRes.detail.author}',
      );
      state = state.copyWith(
        detail: detailRes.detail,
        steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
      );

      // Step 3: toc
      final tocUrl = detailRes.detail.tocUrl.trim().isNotEmpty
          ? detailRes.detail.tocUrl.trim()
          : firstItem.bookUrl;
      state = state.copyWith(currentStep: DebugStepKind.toc);
      _setStep(steps, DebugStepKind.toc, DebugStepStatus.running);
      final tocRes = await provider.getToc(tocUrl, cancelToken: cancelToken);
      if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;

      _setStep(
        steps,
        DebugStepKind.toc,
        DebugStepStatus.success,
        trace: tocRes.trace,
        summary: '解析共 ${tocRes.chapters.length} 章',
      );
      state = state.copyWith(
        chapters: tocRes.chapters,
        steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
      );

      if (tocRes.chapters.isEmpty) {
        _skipRemainingSteps(steps, DebugStepKind.content);
        state = state.copyWith(
          isRunning: false,
          clearCurrentStep: true,
          steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
          errorMessage: '目录为空，无法抓取正文',
        );
        return;
      }

      // Step 4: content
      final targetIdx = chapterIndex.clamp(0, tocRes.chapters.length - 1);
      await _runContentStep(
        source: source,
        provider: provider,
        chapters: tocRes.chapters,
        chapterIndex: targetIdx,
        steps: steps,
        cancelToken: cancelToken,
        epoch: epoch,
      );
    } on CancelledFailure {
      _handleCancelled(steps, epoch);
    } catch (error, stackTrace) {
      await _handleStepFailure(
        source: source,
        steps: steps,
        error: error,
        stackTrace: stackTrace,
        epoch: epoch,
      );
    }
  }

  /// Re-runs step 4 (`content`) on a different [chapterIndex] from the already
  /// fetched TOC.
  Future<void> debugChapter(int chapterIndex) async {
    if (!_isAlive || state.isRunning) return;
    final sourceId = state.selectedSourceId;
    if (sourceId == null || state.chapters.isEmpty) return;

    _activeCancelToken?.cancel();
    final cancelToken = CancellationToken();
    _activeCancelToken = cancelToken;
    final epoch = ++_runEpoch;

    final sourceRepo = ref.read(sourceRepositoryProvider);
    final providerFactory = ref.read(bookProviderFactoryProvider);
    final steps = Map<DebugStepKind, DebugStepReport>.from(state.steps);
    final targetIdx = chapterIndex.clamp(0, state.chapters.length - 1);

    state = state.copyWith(
      selectedChapterIndex: targetIdx,
      isRunning: true,
      currentStep: DebugStepKind.content,
      clearContent: true,
      clearError: true,
    );

    BookSource? source;
    try {
      source = await sourceRepo.getSourceById(sourceId);
      if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;
      if (source == null) {
        state = state.copyWith(
          isRunning: false,
          clearCurrentStep: true,
          errorMessage: '未找到书源 ($sourceId)',
        );
        return;
      }
      final provider = await providerFactory.createProvider(source);
      if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;

      await _runContentStep(
        source: source,
        provider: provider,
        chapters: state.chapters,
        chapterIndex: targetIdx,
        steps: steps,
        cancelToken: cancelToken,
        epoch: epoch,
      );
    } on CancelledFailure {
      _handleCancelled(steps, epoch);
    } catch (error, stackTrace) {
      await _handleStepFailure(
        source: source,
        steps: steps,
        error: error,
        stackTrace: stackTrace,
        epoch: epoch,
      );
    }
  }

  /// Cancels any active debug pipeline run.
  void cancelDebug() {
    if (!_isAlive) return;
    _runEpoch++;
    _activeCancelToken?.cancel();
    _activeCancelToken = null;
    if (!state.isRunning) return;

    final steps = Map<DebugStepKind, DebugStepReport>.from(state.steps);
    final activeStep = state.currentStep;
    if (activeStep != null) {
      _setStep(
        steps,
        activeStep,
        DebugStepStatus.cancelled,
        errorMessage: '用户取消调试',
      );
      _skipRemainingSteps(steps, activeStep, inclusive: false);
    }
    state = state.copyWith(
      isRunning: false,
      clearCurrentStep: true,
      steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
    );
  }

  Future<void> _runContentStep({
    required BookSource source,
    required BookProvider provider,
    required List<ChapterMeta> chapters,
    required int chapterIndex,
    required Map<DebugStepKind, DebugStepReport> steps,
    required CancellationToken cancelToken,
    required int epoch,
  }) async {
    final sanitizer = ref.read(contentSanitizerProvider);
    final sourceRepo = ref.read(sourceRepositoryProvider);
    final targetChapter = chapters[chapterIndex];

    state = state.copyWith(
      selectedChapterIndex: chapterIndex,
      currentStep: DebugStepKind.content,
      steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
    );
    _setStep(steps, DebugStepKind.content, DebugStepStatus.running);
    state = state.copyWith(
      steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
    );

    final contentRes = await provider.getChapterContent(
      targetChapter,
      cancelToken: cancelToken,
    );
    if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;

    final sanitized = await sanitizer.sanitize(
      contentRes.content.rawText,
      SanitizeContext(
        bookId: 'debug_${source.id}',
        sourceId: source.id,
        chapterTitle: targetChapter.title,
      ),
    );
    if (!_isAlive || epoch != _runEpoch || cancelToken.isCancelled) return;

    _setStep(
      steps,
      DebugStepKind.content,
      DebugStepStatus.success,
      trace: contentRes.trace,
      summary:
          '原始 ${contentRes.content.rawText.length} 字 · 净化后 ${sanitized.length} 字',
    );

    await _updateSourceStatus(
      sourceRepo,
      source,
      status: SourceCheckStatus.ok,
      errorSummary: null,
    );
    if (!_isAlive || epoch != _runEpoch) return;

    state = state.copyWith(
      isRunning: false,
      clearCurrentStep: true,
      rawContent: contentRes.content,
      sanitizedContent: sanitized,
      steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
      clearError: true,
    );
  }

  void _handleCancelled(
    Map<DebugStepKind, DebugStepReport> steps,
    int epoch,
  ) {
    if (!_isAlive || epoch != _runEpoch) return;
    final activeStep = state.currentStep;
    if (activeStep != null) {
      _setStep(
        steps,
        activeStep,
        DebugStepStatus.cancelled,
        errorMessage: '调试已取消',
      );
      _skipRemainingSteps(steps, activeStep, inclusive: false);
    }
    state = state.copyWith(
      isRunning: false,
      clearCurrentStep: true,
      steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
    );
  }

  Future<void> _handleStepFailure({
    required BookSource? source,
    required Map<DebugStepKind, DebugStepReport> steps,
    required Object error,
    required StackTrace stackTrace,
    required int epoch,
  }) async {
    if (!_isAlive || epoch != _runEpoch) return;

    final failedStep = state.currentStep ?? DebugStepKind.search;
    final message = error is AppFailure ? error.message : error.toString();
    final String? stackPreview;
    if (error is JsExecutionFailure && error.jsStackTrace != null) {
      stackPreview = error.jsStackTrace;
    } else {
      final stText =
          (error is AppFailure ? error.stackTrace : null) ?? stackTrace;
      stackPreview = stText.toString().split('\n').take(8).join('\n');
    }

    _setStep(
      steps,
      failedStep,
      DebugStepStatus.failed,
      errorMessage: message,
      stackPreview: stackPreview,
    );
    _skipRemainingSteps(steps, failedStep, inclusive: false);

    if (source != null) {
      final status = error is UnsupportedLegadoRuleFailure
          ? SourceCheckStatus.unsupported
          : SourceCheckStatus.error;
      final sourceRepo = ref.read(sourceRepositoryProvider);
      await _updateSourceStatus(
        sourceRepo,
        source,
        status: status,
        errorSummary: message,
      );
    }

    if (!_isAlive || epoch != _runEpoch) return;
    state = state.copyWith(
      isRunning: false,
      clearCurrentStep: true,
      steps: Map<DebugStepKind, DebugStepReport>.unmodifiable(steps),
      errorMessage: message,
    );
  }

  Future<void> _updateSourceStatus(
    SourceRepository sourceRepo,
    BookSource source, {
    required SourceCheckStatus status,
    required String? errorSummary,
  }) async {
    try {
      await sourceRepo.saveSource(
        source.copyWith(
          lastCheckStatus: status,
          lastErrorSummary: errorSummary,
          clearLastErrorSummary: errorSummary == null,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (_isAlive) {
        unawaited(ref.read(sourcesControllerProvider.notifier).refresh());
      }
    } catch (_) {
      // Non-critical diagnostic status update.
    }
  }

  void _setStep(
    Map<DebugStepKind, DebugStepReport> steps,
    DebugStepKind kind,
    DebugStepStatus status, {
    SourceDebugTrace? trace,
    String? summary,
    String? errorMessage,
    String? stackPreview,
  }) {
    final current = steps[kind] ?? DebugStepReport(step: kind);
    steps[kind] = current.copyWith(
      status: status,
      trace: trace,
      summary: summary,
      errorMessage: errorMessage,
      stackPreview: stackPreview,
    );
  }

  void _skipRemainingSteps(
    Map<DebugStepKind, DebugStepReport> steps,
    DebugStepKind fromStep, {
    bool inclusive = true,
  }) {
    const order = DebugStepKind.values;
    final start = order.indexOf(fromStep);
    final begin = inclusive ? start : start + 1;
    for (var i = begin; i < order.length; i++) {
      final kind = order[i];
      _setStep(steps, kind, DebugStepStatus.skipped);
    }
  }
}
