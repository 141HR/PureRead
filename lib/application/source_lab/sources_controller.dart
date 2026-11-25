import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import 'source_health_checker.dart';
import 'sources_state.dart';

final sourcesControllerProvider =
    NotifierProvider<SourcesController, SourcesState>(SourcesController.new);

/// Manages book source batch import (`.json`/`.js` files or pasted text),
/// deduplication, grouping, filtering, batch health checking, enable toggling,
/// weight priority, failed-source cleanup, deletion, and export.
class SourcesController extends Notifier<SourcesState> {
  StreamSubscription<List<BookSource>>? _sourcesSub;
  CancellationToken? _healthCheckCancelToken;
  int _healthCheckEpoch = 0;
  bool _disposed = false;
  bool _initialized = false;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  SourcesState build() {
    _disposed = false;
    _initialized = false;
    _healthCheckEpoch = 0;
    ref.onDispose(() {
      _disposed = true;
      _healthCheckCancelToken?.cancel();
      _healthCheckCancelToken?.dispose();
      _healthCheckCancelToken = null;
      unawaited(_sourcesSub?.cancel());
      _sourcesSub = null;
    });
    Future<void>.microtask(_initialize);
    return const SourcesState(isLoading: true);
  }

  Future<void> _initialize() async {
    if (!_isAlive || _initialized) return;
    _initialized = true;

    final sourceRepo = ref.read(sourceRepositoryProvider);
    await _sourcesSub?.cancel();
    if (!_isAlive) return;

    _sourcesSub = sourceRepo.watchSources().listen(
      (sources) {
        if (!_isAlive) return;
        _applyLoadedSources(sources);
      },
      onError: (Object error) {
        if (!_isAlive) return;
        state = state.copyWith(
          isLoading: false,
          errorMessage: _formatError(error),
        );
      },
    );

    await refresh();
  }

  /// Reloads all configured [BookSource] records from [SourceRepository].
  Future<void> refresh() async {
    if (!_isAlive) return;
    final sourceRepo = ref.read(sourceRepositoryProvider);
    try {
      final sources = await sourceRepo.listSources();
      if (!_isAlive) return;
      _applyLoadedSources(sources);
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _formatError(error),
      );
    }
  }

  void _applyLoadedSources(List<BookSource> sources) {
    final availableIds = sources.map((s) => s.id).toSet();
    final retainedSelection = state.selectedIds
        .where(availableIds.contains)
        .toSet();
    final currentGroups = <String>{
      '全部',
      ...sources.map(
        (s) => s.groupName.trim().isEmpty ? '默认' : s.groupName.trim(),
      ),
    };
    final nextGroup = currentGroups.contains(state.selectedGroup)
        ? state.selectedGroup
        : '全部';

    state = state.copyWith(
      sources: List<BookSource>.unmodifiable(sources),
      selectedGroup: nextGroup,
      selectedIds: Set<String>.unmodifiable(retainedSelection),
      isLoading: false,
    );
  }

  /// Selects a group filter chip (`'全部'` for all groups).
  void selectGroup(String groupName) {
    if (!_isAlive) return;
    state = state.copyWith(selectedGroup: groupName);
  }

  /// Updates search keyword filtering sources by name, URL, or group.
  void setSearchQuery(String query) {
    if (!_isAlive) return;
    state = state.copyWith(searchQuery: query);
  }

  /// Updates enablement status filter.
  void setEnabledFilter(SourceEnabledFilter filter) {
    if (!_isAlive) return;
    state = state.copyWith(enabledFilter: filter);
  }

  /// Updates health check status filter.
  void setHealthFilter(SourceHealthFilter filter) {
    if (!_isAlive) return;
    state = state.copyWith(healthFilter: filter);
  }

  /// Normalizes a book source [rawUrl] for deduplication by stripping
  /// `#fragment` tags, normalizing scheme/host case, omitting default ports,
  /// and trimming trailing slashes.
  static String normalizeBaseUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (url.isEmpty) return '';
    final hashIdx = url.indexOf('#');
    if (hashIdx >= 0) {
      url = url.substring(0, hashIdx).trim();
    }
    if (url.isEmpty) return '';

    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      final scheme = parsed.scheme.toLowerCase();
      final host = parsed.host.toLowerCase();
      final hasDefaultPort =
          (scheme == 'http' && parsed.port == 80) ||
          (scheme == 'https' && parsed.port == 443);
      final portPart = (parsed.hasPort && !hasDefaultPort)
          ? ':${parsed.port}'
          : '';
      var path = parsed.path;
      while (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      final queryPart = parsed.hasQuery ? '?${parsed.query}' : '';
      return '$scheme://$host$portPart$path$queryPart';
    }

    url = url.toLowerCase();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Computes a canonical deduplication key from normalized `baseUrl` and `name`.
  static String sourceDedupeKey(BookSource source) {
    final normUrl = normalizeBaseUrl(source.baseUrl);
    final normName = source.name.trim().toLowerCase();
    return '$normUrl||$normName';
  }

  /// Opens the native multi-select picker for `.json` / `.js` files and
  /// imports selected sources.
  Future<void> importFromFiles() async {
    if (!_isAlive || state.isImporting) return;
    final platform = ref.read(platformBridgeProvider);
    try {
      final paths = await platform.pickFiles(
        extensions: const <String>['json', 'js'],
        allowMultiple: true,
      );
      if (!_isAlive || paths.isEmpty) return;
      await importFilePaths(paths);
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(
        isImporting: false,
        errorMessage: '选择书源文件失败：${_formatError(error)}',
      );
    }
  }

  /// Imports `.json` / `.js` source files at [filePaths] in batch, deduplicating
  /// against existing sources and within the batch by normalized `baseUrl` +
  /// `name`.
  Future<void> importFilePaths(List<String> filePaths) async {
    if (!_isAlive || filePaths.isEmpty) return;
    final gateway = ref.read(sourceImportExportGatewayProvider);
    final sourceRepo = ref.read(sourceRepositoryProvider);

    state = state.copyWith(
      isImporting: true,
      clearStatus: true,
      clearError: true,
    );

    final parsedSources = <BookSource>[];
    var skippedNonText = 0;
    var invalidCount = 0;
    final warnings = <String>[];
    final errors = <String>[];

    for (final filePath in filePaths) {
      if (!_isAlive) return;
      try {
        final result = await gateway.parseImportFile(filePath);
        if (!_isAlive) return;
        parsedSources.addAll(result.sources);
        skippedNonText += result.skippedNonTextCount;
        invalidCount += result.invalidCount;
        warnings.addAll(result.messages);
      } catch (error) {
        errors.add('${p.basename(filePath)}：${_formatError(error)}');
      }
    }

    var uniqueSources = const <BookSource>[];
    var duplicateSkipped = 0;
    if (parsedSources.isNotEmpty) {
      try {
        final deduped = await _deduplicateImportSources(
          sourceRepo,
          parsedSources,
        );
        if (!_isAlive) return;
        uniqueSources = deduped.sources;
        duplicateSkipped = deduped.duplicateCount;
        if (uniqueSources.isNotEmpty) {
          await sourceRepo.saveSources(uniqueSources);
        }
      } catch (error) {
        errors.add(_formatError(error));
      }
    }
    if (!_isAlive) return;

    await refresh();
    if (!_isAlive) return;

    final statusParts = <String>[];
    if (uniqueSources.isNotEmpty) {
      statusParts.add('已导入 ${uniqueSources.length} 个书源');
    }
    if (duplicateSkipped > 0) {
      statusParts.add('跳过 $duplicateSkipped 个重复书源');
    }
    if (skippedNonText > 0) {
      statusParts.add('跳过 $skippedNonText 个非文本源');
    }
    if (invalidCount > 0) {
      statusParts.add('忽略 $invalidCount 条无效项');
    }
    if (statusParts.isEmpty && warnings.isNotEmpty) {
      statusParts.addAll(warnings);
    }

    state = state.copyWith(
      isImporting: false,
      statusMessage: statusParts.isNotEmpty ? statusParts.join(' · ') : null,
      errorMessage: errors.isNotEmpty ? errors.join('\n') : null,
    );
  }

  /// Parses pasted Legado JSON or JS plugin source text, deduplicates by
  /// normalized `baseUrl` + `name`, and saves valid non-duplicate sources.
  Future<bool> importFromText(String rawText, {String? fileName}) async {
    if (!_isAlive || state.isImporting) return false;
    final gateway = ref.read(sourceImportExportGatewayProvider);
    final sourceRepo = ref.read(sourceRepositoryProvider);

    state = state.copyWith(
      isImporting: true,
      clearStatus: true,
      clearError: true,
    );

    try {
      final result = await gateway.parseImportText(rawText, fileName: fileName);
      if (!_isAlive) return false;

      if (result.sources.isEmpty) {
        state = state.copyWith(
          isImporting: false,
          errorMessage: result.messages.isNotEmpty
              ? result.messages.join('\n')
              : '未识别到有效书源内容',
        );
        return false;
      }

      final deduped = await _deduplicateImportSources(
        sourceRepo,
        result.sources,
      );
      if (!_isAlive) return false;
      final uniqueSources = deduped.sources;
      final duplicateSkipped = deduped.duplicateCount;

      if (uniqueSources.isNotEmpty) {
        await sourceRepo.saveSources(uniqueSources);
        if (!_isAlive) return false;
      }
      await refresh();
      if (!_isAlive) return false;

      final summaryParts = <String>[
        if (uniqueSources.isNotEmpty) '已导入 ${uniqueSources.length} 个书源',
        if (duplicateSkipped > 0) '跳过 $duplicateSkipped 个重复书源',
        if (result.skippedNonTextCount > 0)
          '跳过 ${result.skippedNonTextCount} 个非文本源',
        if (result.invalidCount > 0) '忽略 ${result.invalidCount} 条无效项',
      ];

      state = state.copyWith(
        isImporting: false,
        statusMessage: summaryParts.isNotEmpty
            ? summaryParts.join(' · ')
            : null,
      );
      return true;
    } catch (error) {
      if (!_isAlive) return false;
      state = state.copyWith(
        isImporting: false,
        errorMessage: _formatError(error),
      );
      return false;
    }
  }

  Future<({List<BookSource> sources, int duplicateCount})>
  _deduplicateImportSources(
    SourceRepository sourceRepo,
    List<BookSource> candidates,
  ) async {
    final existing = await sourceRepo.listSources();
    final seenKeys = <String>{
      for (final source in existing) sourceDedupeKey(source),
    };
    final accepted = <BookSource>[];
    var duplicateCount = 0;
    for (final candidate in candidates) {
      if (seenKeys.add(sourceDedupeKey(candidate))) {
        accepted.add(candidate);
      } else {
        duplicateCount++;
      }
    }
    return (
      sources: List<BookSource>.unmodifiable(accepted),
      duplicateCount: duplicateCount,
    );
  }

  /// Starts a bounded-concurrency batch health check across visible (or all)
  /// configured sources.
  Future<void> startBatchHealthCheck({bool visibleOnly = true}) async {
    if (!_isAlive || state.isCheckingHealth) return;
    final targets = visibleOnly
        ? state.filteredSources
        : List<BookSource>.unmodifiable(state.sources);
    if (targets.isEmpty) {
      state = state.copyWith(statusMessage: '当前没有可测活的书源');
      return;
    }

    _healthCheckCancelToken?.cancel();
    _healthCheckCancelToken?.dispose();
    final cancelToken = CancellationToken();
    _healthCheckCancelToken = cancelToken;
    final epoch = ++_healthCheckEpoch;

    final checker = ref.read(sourceHealthCheckerProvider);

    state = state.copyWith(
      isCheckingHealth: true,
      healthCheckedCount: 0,
      healthTotalCount: targets.length,
      healthOkCount: 0,
      healthFailedCount: 0,
      clearStatus: true,
      clearError: true,
    );

    try {
      final summary = await checker.checkSources(
        targets,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (!_isAlive || epoch != _healthCheckEpoch) return;
          state = state.copyWith(
            healthCheckedCount: progress.checkedCount,
            healthTotalCount: progress.totalCount,
            healthOkCount: progress.okCount,
            healthFailedCount: progress.totalErrorCount,
          );
        },
      );
      if (!_isAlive || epoch != _healthCheckEpoch) return;

      await refresh();
      if (!_isAlive || epoch != _healthCheckEpoch) return;

      final String statusMsg;
      if (summary.isCancelled) {
        statusMsg =
            '已停止测活（已完成 ${summary.checkedCount}/${summary.totalCount}，正常 ${summary.okCount}，失效 ${summary.totalErrorCount}）';
      } else {
        final parts = <String>[
          '测活完成：正常 ${summary.okCount}',
          '失效 ${summary.totalErrorCount}',
          if (summary.timeoutCount > 0) '超时 ${summary.timeoutCount}',
          if (summary.unsupportedCount > 0) '不支持 ${summary.unsupportedCount}',
        ];
        statusMsg = parts.join(' · ');
      }

      state = state.copyWith(
        isCheckingHealth: false,
        healthCheckedCount: summary.checkedCount,
        healthTotalCount: summary.totalCount,
        healthOkCount: summary.okCount,
        healthFailedCount: summary.totalErrorCount,
        statusMessage: statusMsg,
      );
    } catch (error) {
      if (!_isAlive || epoch != _healthCheckEpoch) return;
      state = state.copyWith(
        isCheckingHealth: false,
        errorMessage: '批量测活失败：${_formatError(error)}',
      );
    } finally {
      if (identical(_healthCheckCancelToken, cancelToken)) {
        _healthCheckCancelToken = null;
      }
      cancelToken.dispose();
    }
  }

  /// Cancels any active batch source health check run while preserving
  /// already-checked results.
  void cancelBatchHealthCheck() {
    if (!_isAlive) return;
    _healthCheckCancelToken?.cancel();
    if (state.isCheckingHealth) {
      state = state.copyWith(
        isCheckingHealth: false,
        statusMessage:
            '正在停止测活（已完成 ${state.healthCheckedCount}/${state.healthTotalCount}，正常 ${state.healthOkCount}，失效 ${state.healthFailedCount}）',
      );
    }
  }

  /// Disables all currently enabled sources whose last health check status is
  /// [SourceCheckStatus.error].
  Future<void> disableFailedSources() async {
    if (!_isAlive) return;
    final failedSources = state.sources
        .where((s) => s.lastCheckStatus == SourceCheckStatus.error)
        .toList(growable: false);
    if (failedSources.isEmpty) {
      state = state.copyWith(statusMessage: '暂无失效书源');
      return;
    }

    final now = DateTime.now().toUtc();
    final toDisable = failedSources
        .where((s) => s.enabled)
        .map((s) => s.copyWith(enabled: false, updatedAt: now))
        .toList(growable: false);
    if (toDisable.isEmpty) {
      state = state.copyWith(statusMessage: '所有失效书源均已处于禁用状态');
      return;
    }

    final sourceRepo = ref.read(sourceRepositoryProvider);
    try {
      await sourceRepo.saveSources(toDisable);
      if (!_isAlive) return;
      await refresh();
      if (!_isAlive) return;
      state = state.copyWith(
        statusMessage: '已禁用 ${toDisable.length} 个失效书源',
      );
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Deletes all sources whose last health check status is
  /// [SourceCheckStatus.error].
  Future<void> deleteFailedSources() async {
    if (!_isAlive) return;
    final failedIds = state.sources
        .where((s) => s.lastCheckStatus == SourceCheckStatus.error)
        .map((s) => s.id)
        .toList(growable: false);
    if (failedIds.isEmpty) {
      state = state.copyWith(statusMessage: '暂无失效书源可清理');
      return;
    }

    final sourceRepo = ref.read(sourceRepositoryProvider);
    try {
      for (final id in failedIds) {
        if (!_isAlive) return;
        await sourceRepo.deleteSource(id);
      }
      if (!_isAlive) return;
      await refresh();
      if (!_isAlive) return;
      state = state.copyWith(
        statusMessage: '已清理 ${failedIds.length} 个失效书源',
      );
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Toggles whether [sourceId] is enabled for search and source switching.
  Future<void> toggleEnabled(String sourceId) async {
    if (!_isAlive) return;
    final idx = state.sources.indexWhere((s) => s.id == sourceId);
    if (idx < 0) return;
    final current = state.sources[idx];
    await _saveUpdatedSource(
      current.copyWith(
        enabled: !current.enabled,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Updates the priority [weight] of [sourceId].
  Future<void> updateWeight(String sourceId, int weight) async {
    if (!_isAlive) return;
    final idx = state.sources.indexWhere((s) => s.id == sourceId);
    if (idx < 0) return;
    final current = state.sources[idx];
    await _saveUpdatedSource(
      current.copyWith(
        weight: weight,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Batch enables or disables all currently selected sources.
  Future<void> setSelectedEnabled(bool enabled) async {
    if (!_isAlive || state.selectedIds.isEmpty) return;
    final sourceRepo = ref.read(sourceRepositoryProvider);
    final now = DateTime.now().toUtc();
    final updated = state.sources
        .where((s) => state.selectedIds.contains(s.id))
        .map((s) => s.copyWith(enabled: enabled, updatedAt: now))
        .toList(growable: false);
    if (updated.isEmpty) return;

    try {
      await sourceRepo.saveSources(updated);
      if (!_isAlive) return;
      await refresh();
      if (!_isAlive) return;
      state = state.copyWith(
        statusMessage:
            '已${enabled ? "启用" : "禁用"} ${updated.length} 个书源',
      );
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Deletes a single source by [sourceId].
  Future<void> deleteSource(String sourceId) async {
    if (!_isAlive) return;
    final sourceRepo = ref.read(sourceRepositoryProvider);
    try {
      await sourceRepo.deleteSource(sourceId);
      if (!_isAlive) return;
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Deletes all currently selected sources.
  Future<void> deleteSelected() async {
    if (!_isAlive || state.selectedIds.isEmpty) return;
    final sourceRepo = ref.read(sourceRepositoryProvider);
    final ids = state.selectedIds.toList(growable: false);
    try {
      for (final id in ids) {
        if (!_isAlive) return;
        await sourceRepo.deleteSource(id);
      }
      if (!_isAlive) return;
      await refresh();
      if (!_isAlive) return;
      state = state.copyWith(
        selectedIds: const <String>{},
        statusMessage: '已删除 ${ids.length} 个书源',
      );
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Toggles multi-selection of [sourceId].
  void toggleSelection(String sourceId) {
    if (!_isAlive) return;
    final next = Set<String>.from(state.selectedIds);
    if (!next.add(sourceId)) {
      next.remove(sourceId);
    }
    state = state.copyWith(selectedIds: Set<String>.unmodifiable(next));
  }

  /// Selects all currently visible sources (or clears if all are selected).
  void toggleSelectAllVisible() {
    if (!_isAlive) return;
    final visibleIds = state.filteredSources.map((s) => s.id).toSet();
    if (visibleIds.isEmpty) return;
    final allSelected = visibleIds.every(state.selectedIds.contains);
    if (allSelected) {
      final next = Set<String>.from(state.selectedIds)
        ..removeAll(visibleIds);
      state = state.copyWith(selectedIds: Set<String>.unmodifiable(next));
    } else {
      final next = Set<String>.from(state.selectedIds)..addAll(visibleIds);
      state = state.copyWith(selectedIds: Set<String>.unmodifiable(next));
    }
  }

  /// Clears multi-selection.
  void clearSelection() {
    if (!_isAlive) return;
    state = state.copyWith(selectedIds: const <String>{});
  }

  /// Serializes selected sources (or all visible sources if none selected) for
  /// export.
  Future<String> exportSources({List<String>? sourceIds}) async {
    final gateway = ref.read(sourceImportExportGatewayProvider);
    final List<BookSource> targets;
    if (sourceIds != null) {
      final idSet = sourceIds.toSet();
      targets = state.sources
          .where((s) => idSet.contains(s.id))
          .toList(growable: false);
    } else if (state.selectedIds.isNotEmpty) {
      targets = state.sources
          .where((s) => state.selectedIds.contains(s.id))
          .toList(growable: false);
    } else {
      targets = state.filteredSources;
    }

    try {
      return await gateway.exportSources(targets);
    } catch (error) {
      if (_isAlive) {
        state = state.copyWith(errorMessage: _formatError(error));
      }
      return '[]';
    }
  }

  /// Dismisses active status/error banners.
  void clearBanner() {
    if (!_isAlive) return;
    state = state.copyWith(clearStatus: true, clearError: true);
  }

  Future<void> _saveUpdatedSource(BookSource source) async {
    final sourceRepo = ref.read(sourceRepositoryProvider);
    try {
      await sourceRepo.saveSource(source);
      if (!_isAlive) return;
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  String _formatError(Object error) =>
      error is AppFailure ? error.message : error.toString();
}
