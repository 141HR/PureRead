import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../m2_providers.dart';

/// Default concurrent source probe limit for batch health checks.
final healthCheckConcurrencyProvider = Provider<int>(
  (ref) => SourceHealthChecker.defaultConcurrency,
);

/// Default per-source timeout duration for batch health checks.
final healthCheckTimeoutProvider = Provider<Duration>(
  (ref) => SourceHealthChecker.defaultPerSourceTimeout,
);

/// Batch source health checker wired to the active [BookProviderFactoryGateway]
/// and [SourceRepository].
final sourceHealthCheckerProvider = Provider<SourceHealthChecker>((ref) {
  return SourceHealthChecker(
    providerFactory: ref.watch(bookProviderFactoryProvider),
    sourceRepository: ref.watch(sourceRepositoryProvider),
    concurrency: ref.watch(healthCheckConcurrencyProvider),
    perSourceTimeout: ref.watch(healthCheckTimeoutProvider),
  );
});

/// Fine-grained outcome of probing a single [BookSource].
enum SourceHealthOutcome { ok, failed, timeout, unsupported }

/// Maps a [SourceHealthOutcome] to the persisted domain [SourceCheckStatus].
extension SourceHealthOutcomeX on SourceHealthOutcome {
  SourceCheckStatus toCheckStatus() {
    return switch (this) {
      SourceHealthOutcome.ok => SourceCheckStatus.ok,
      SourceHealthOutcome.failed ||
      SourceHealthOutcome.timeout => SourceCheckStatus.error,
      SourceHealthOutcome.unsupported => SourceCheckStatus.unsupported,
    };
  }
}

/// Diagnostic result produced for one [BookSource] during a health check run.
class SourceHealthCheckItemResult {
  final String sourceId;
  final String sourceName;
  final SourceHealthOutcome outcome;
  final SourceCheckStatus persistedStatus;
  final String? errorSummary;
  final String testKeyword;
  final int elapsedMs;

  const SourceHealthCheckItemResult({
    required this.sourceId,
    required this.sourceName,
    required this.outcome,
    required this.persistedStatus,
    this.errorSummary,
    required this.testKeyword,
    required this.elapsedMs,
  });
}

/// Incremental progress snapshot emitted by [SourceHealthChecker.checkSources].
class SourceHealthCheckProgress {
  final int totalCount;
  final int checkedCount;
  final int okCount;
  final int failedCount;
  final int timeoutCount;
  final int unsupportedCount;
  final bool isCancelled;
  final bool isCompleted;
  final SourceHealthCheckItemResult? lastResult;

  const SourceHealthCheckProgress({
    required this.totalCount,
    required this.checkedCount,
    required this.okCount,
    required this.failedCount,
    required this.timeoutCount,
    required this.unsupportedCount,
    this.isCancelled = false,
    this.isCompleted = false,
    this.lastResult,
  });

  /// Combined count of failed and timed-out sources (`SourceCheckStatus.error`).
  int get totalErrorCount => failedCount + timeoutCount;
}

/// Final summary returned when [SourceHealthChecker.checkSources] completes or
/// is cancelled.
class SourceHealthCheckSummary {
  final int totalCount;
  final int checkedCount;
  final int okCount;
  final int failedCount;
  final int timeoutCount;
  final int unsupportedCount;
  final bool isCancelled;
  final List<SourceHealthCheckItemResult> results;
  final List<BookSource> updatedSources;

  const SourceHealthCheckSummary({
    required this.totalCount,
    required this.checkedCount,
    required this.okCount,
    required this.failedCount,
    required this.timeoutCount,
    required this.unsupportedCount,
    required this.isCancelled,
    required this.results,
    required this.updatedSources,
  });

  /// Combined count of failed and timed-out sources (`SourceCheckStatus.error`).
  int get totalErrorCount => failedCount + timeoutCount;
}

/// Executes bounded-concurrency batch search health checks across [BookSource]s,
/// persisting status updates in batches via [SourceRepository].
class SourceHealthChecker {
  static const int defaultConcurrency = 5;
  static const Duration defaultPerSourceTimeout = Duration(seconds: 8);
  static const int defaultPersistBatchSize = 10;
  static const String defaultFallbackKeyword = '凡人';
  static const int maxErrorSummaryLength = 120;

  final BookProviderFactoryGateway providerFactory;
  final SourceRepository sourceRepository;
  final int concurrency;
  final Duration perSourceTimeout;
  final int persistBatchSize;
  final String fallbackKeyword;

  const SourceHealthChecker({
    required this.providerFactory,
    required this.sourceRepository,
    this.concurrency = defaultConcurrency,
    this.perSourceTimeout = defaultPerSourceTimeout,
    this.persistBatchSize = defaultPersistBatchSize,
    this.fallbackKeyword = defaultFallbackKeyword,
  });

  /// Extracts a probe search keyword from Legado `ruleSearch.checkKeyWord`
  /// when present and non-empty, falling back to [fallback].
  static String extractTestKeyword(
    BookSource source, {
    String fallback = defaultFallbackKeyword,
  }) {
    if (source.engineType == SourceEngineType.legado) {
      final decoded = _tryDecodeJsonMap(source.rawDefinition);
      if (decoded != null) {
        final ruleSearch = decoded['ruleSearch'];
        if (ruleSearch is Map) {
          final rawKeyword = ruleSearch['checkKeyWord']?.toString().trim();
          if (rawKeyword != null && rawKeyword.isNotEmpty) {
            return rawKeyword;
          }
        }
      }
    }
    return fallback;
  }

  /// Checks [sources] concurrently up to [concurrency], persisting updated
  /// [BookSource] health metadata in batches and emitting [onProgress]
  /// snapshots.
  Future<SourceHealthCheckSummary> checkSources(
    List<BookSource> sources, {
    CancellationToken? cancelToken,
    void Function(SourceHealthCheckProgress progress)? onProgress,
  }) async {
    final total = sources.length;
    if (total == 0) {
      onProgress?.call(
        SourceHealthCheckProgress(
          totalCount: 0,
          checkedCount: 0,
          okCount: 0,
          failedCount: 0,
          timeoutCount: 0,
          unsupportedCount: 0,
          isCancelled: cancelToken?.isCancelled ?? false,
          isCompleted: true,
        ),
      );
      return SourceHealthCheckSummary(
        totalCount: 0,
        checkedCount: 0,
        okCount: 0,
        failedCount: 0,
        timeoutCount: 0,
        unsupportedCount: 0,
        isCancelled: cancelToken?.isCancelled ?? false,
        results: const <SourceHealthCheckItemResult>[],
        updatedSources: const <BookSource>[],
      );
    }

    final workerCount = math.min(math.max(1, concurrency), total);
    final batchLimit = math.max(1, persistBatchSize);

    var nextIndex = 0;
    var checkedCount = 0;
    var okCount = 0;
    var failedCount = 0;
    var timeoutCount = 0;
    var unsupportedCount = 0;

    final resultsByIndex = List<SourceHealthCheckItemResult?>.filled(total, null);
    final updatedByIndex = List<BookSource?>.filled(total, null);
    final pendingPersist = <BookSource>[];
    var persistChain = Future<void>.value();

    void enqueueBatchPersist({bool force = false}) {
      if (pendingPersist.isEmpty) return;
      if (!force && pendingPersist.length < batchLimit) return;
      final batch = List<BookSource>.unmodifiable(pendingPersist);
      pendingPersist.clear();
      persistChain = persistChain.then(
        (_) => sourceRepository.saveSources(batch),
      );
    }

    Future<void> worker() async {
      while (true) {
        if (cancelToken?.isCancelled ?? false) return;
        if (nextIndex >= total) return;

        final index = nextIndex++;
        final source = sources[index];

        final checkOutput = await _checkSingleSource(
          source,
          batchCancelToken: cancelToken,
        );
        if (checkOutput == null) {
          // Batch cancellation aborted this source mid-flight.
          return;
        }

        final (:itemResult, :updatedSource) = checkOutput;
        resultsByIndex[index] = itemResult;
        updatedByIndex[index] = updatedSource;

        checkedCount++;
        switch (itemResult.outcome) {
          case SourceHealthOutcome.ok:
            okCount++;
          case SourceHealthOutcome.failed:
            failedCount++;
          case SourceHealthOutcome.timeout:
            timeoutCount++;
          case SourceHealthOutcome.unsupported:
            unsupportedCount++;
        }

        pendingPersist.add(updatedSource);
        enqueueBatchPersist();

        onProgress?.call(
          SourceHealthCheckProgress(
            totalCount: total,
            checkedCount: checkedCount,
            okCount: okCount,
            failedCount: failedCount,
            timeoutCount: timeoutCount,
            unsupportedCount: unsupportedCount,
            isCancelled: cancelToken?.isCancelled ?? false,
            isCompleted: false,
            lastResult: itemResult,
          ),
        );
      }
    }

    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    enqueueBatchPersist(force: true);
    await persistChain;

    final isCancelled = cancelToken?.isCancelled ?? false;
    final completedResults = resultsByIndex
        .whereType<SourceHealthCheckItemResult>()
        .toList(growable: false);
    final completedSources = updatedByIndex
        .whereType<BookSource>()
        .toList(growable: false);

    onProgress?.call(
      SourceHealthCheckProgress(
        totalCount: total,
        checkedCount: checkedCount,
        okCount: okCount,
        failedCount: failedCount,
        timeoutCount: timeoutCount,
        unsupportedCount: unsupportedCount,
        isCancelled: isCancelled,
        isCompleted: true,
      ),
    );

    return SourceHealthCheckSummary(
      totalCount: total,
      checkedCount: checkedCount,
      okCount: okCount,
      failedCount: failedCount,
      timeoutCount: timeoutCount,
      unsupportedCount: unsupportedCount,
      isCancelled: isCancelled,
      results: List<SourceHealthCheckItemResult>.unmodifiable(completedResults),
      updatedSources: List<BookSource>.unmodifiable(completedSources),
    );
  }

  Future<({SourceHealthCheckItemResult itemResult, BookSource updatedSource})?>
  _checkSingleSource(
    BookSource source, {
    CancellationToken? batchCancelToken,
  }) async {
    if (batchCancelToken?.isCancelled ?? false) return null;

    final sw = Stopwatch()..start();
    final testKeyword = extractTestKeyword(source, fallback: fallbackKeyword);

    SourceHealthCheckItemResult buildResult(
      SourceHealthOutcome outcome, {
      String? summary,
    }) {
      sw.stop();
      final persistedStatus = outcome.toCheckStatus();
      final conciseSummary = summary == null ? null : _conciseSummary(summary);
      return SourceHealthCheckItemResult(
        sourceId: source.id,
        sourceName: source.name,
        outcome: outcome,
        persistedStatus: persistedStatus,
        errorSummary: conciseSummary,
        testKeyword: testKeyword,
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    BookSource buildUpdatedSource(SourceHealthCheckItemResult result) {
      return source.copyWith(
        lastCheckStatus: result.persistedStatus,
        lastErrorSummary: result.errorSummary,
        clearLastErrorSummary: result.errorSummary == null,
        updatedAt: DateTime.now().toUtc(),
      );
    }

    if (!source.enabled) {
      final result = buildResult(
        SourceHealthOutcome.unsupported,
        summary: '书源已禁用',
      );
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    }

    final staticUnsupportedReason = _detectStaticUnsupportedReason(source);
    if (staticUnsupportedReason != null) {
      final result = buildResult(
        SourceHealthOutcome.unsupported,
        summary: staticUnsupportedReason,
      );
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    }

    final sourceToken = CancellationToken();
    var timedOut = false;
    void onBatchCancel() {
      sourceToken.cancel();
    }

    batchCancelToken?.addListener(onBatchCancel);

    final completer =
        Completer<
          ({
            SourceHealthOutcome outcome,
            String? summary,
          })
        >();
    final timeoutTimer = Timer(perSourceTimeout, () {
      timedOut = true;
      sourceToken.cancel();
      if (!completer.isCompleted) {
        completer.complete((
          outcome: SourceHealthOutcome.timeout,
          summary: '请求超时 (>${perSourceTimeout.inSeconds}s)',
        ));
      }
    });

    unawaited(
      Future<void>(() async {
        final provider = await providerFactory.createProvider(source);
        sourceToken.throwIfCancelled();

        if (!provider.capabilities.supportsSearch) {
          if (!completer.isCompleted) {
            completer.complete((
              outcome: SourceHealthOutcome.unsupported,
              summary: '未配置搜索规则',
            ));
          }
          return;
        }

        final searchRes = await provider.search(
          testKeyword,
          page: 1,
          cancelToken: sourceToken,
        );
        sourceToken.throwIfCancelled();

        if (searchRes.items.isEmpty) {
          if (!completer.isCompleted) {
            completer.complete((
              outcome: SourceHealthOutcome.failed,
              summary: '搜索无结果（测试词：$testKeyword）',
            ));
          }
          return;
        }

        if (!completer.isCompleted) {
          completer.complete((outcome: SourceHealthOutcome.ok, summary: null));
        }
      }).catchError((Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }),
    );

    try {
      final outcomePair = await completer.future;
      if (batchCancelToken?.isCancelled ?? false) {
        return null;
      }
      final result = buildResult(
        outcomePair.outcome,
        summary: outcomePair.summary,
      );
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    } on CancelledFailure {
      if (batchCancelToken?.isCancelled ?? false) {
        return null;
      }
      if (timedOut) {
        final result = buildResult(
          SourceHealthOutcome.timeout,
          summary: '请求超时 (>${perSourceTimeout.inSeconds}s)',
        );
        return (itemResult: result, updatedSource: buildUpdatedSource(result));
      }
      final result = buildResult(
        SourceHealthOutcome.failed,
        summary: '测活请求已取消',
      );
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    } on UnsupportedLegadoRuleFailure catch (error) {
      if (batchCancelToken?.isCancelled ?? false) return null;
      final result = buildResult(
        SourceHealthOutcome.unsupported,
        summary: error.message,
      );
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    } on TimeoutException {
      if (batchCancelToken?.isCancelled ?? false) return null;
      final result = buildResult(
        SourceHealthOutcome.timeout,
        summary: '请求超时 (>${perSourceTimeout.inSeconds}s)',
      );
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    } on NetworkFailure catch (error) {
      if (batchCancelToken?.isCancelled ?? false) return null;
      final outcome = error.isTimeout
          ? SourceHealthOutcome.timeout
          : SourceHealthOutcome.failed;
      final result = buildResult(outcome, summary: error.message);
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    } on JsExecutionFailure catch (error) {
      if (batchCancelToken?.isCancelled ?? false) return null;
      final outcome = error.isTimeout
          ? SourceHealthOutcome.timeout
          : SourceHealthOutcome.failed;
      final result = buildResult(outcome, summary: error.message);
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    } catch (error) {
      if (batchCancelToken?.isCancelled ?? false) return null;
      final message = error is AppFailure ? error.message : error.toString();
      final result = buildResult(SourceHealthOutcome.failed, summary: message);
      return (itemResult: result, updatedSource: buildUpdatedSource(result));
    } finally {
      timeoutTimer.cancel();
      batchCancelToken?.removeListener(onBatchCancel);
      sourceToken.dispose();
    }
  }

  static Map<String, Object?>? _tryDecodeJsonMap(String rawJson) {
    final trimmed = rawJson.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String? _detectStaticUnsupportedReason(BookSource source) {
    if (source.engineType != SourceEngineType.legado) return null;
    final decoded = _tryDecodeJsonMap(source.rawDefinition);
    if (decoded == null) return null;

    final rawType = decoded['bookSourceType'];
    if (rawType != null) {
      final parsedType = rawType is int
          ? rawType
          : int.tryParse(rawType.toString().trim());
      if (parsedType != null && parsedType != 0) {
        return '非小说文本书源 (type=$parsedType)';
      }
    }

    if (decoded['webView'] == true) {
      return '需要 WebView（暂不支持）';
    }
    final ruleSearch = decoded['ruleSearch'];
    if (ruleSearch is Map && ruleSearch['webView'] == true) {
      return '搜索规则需要 WebView（暂不支持）';
    }
    return null;
  }

  static String _conciseSummary(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return '未知错误';
    if (collapsed.length <= maxErrorSummaryLength) return collapsed;
    return '${collapsed.substring(0, maxErrorSummaryLength - 1)}…';
  }
}
