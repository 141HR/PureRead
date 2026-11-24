import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../reader/reader_theme_x.dart';
import 'backup_providers.dart';
import 'backup_state.dart';

const String _kActiveThemeKey = 'active_theme_id';

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);

/// Orchestrates `.pureread.zip` local backup export, archive pick & manifest
/// validation, merge/overwrite restore with pre-restore DB snapshot protection,
/// snapshot listing, chapter cache clearing, and settings theme/font updates.
class BackupController extends Notifier<BackupState> {
  bool _disposed = false;
  bool _initialized = false;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  BackupState build() {
    _disposed = false;
    _initialized = false;
    ref.onDispose(() {
      _disposed = true;
    });
    Future<void>.microtask(_initialize);
    return BackupState(
      isLoading: true,
      activeTheme: buildDefaultReaderThemes().first,
    );
  }

  Future<void> _initialize() async {
    if (!_isAlive || _initialized) return;
    _initialized = true;
    await refresh();
  }

  /// Reloads DB snapshots, chapter cache usage, and reader theme/font settings.
  Future<void> refresh() async {
    if (!_isAlive) return;
    final backupRepo = ref.read(backupRepositoryProvider);
    final cacheGateway = ref.read(cacheManagementGatewayProvider);
    final themeRepo = ref.read(themeRepositoryProvider);
    final fontGateway = ref.read(fontLoaderGatewayProvider);

    var snapshots = state.databaseSnapshots;
    var cacheStats = state.cacheStats;
    var themes = state.availableThemes;
    var activeTheme = state.activeTheme;
    String? errorMsg;

    try {
      snapshots = await backupRepo.listDatabaseSnapshots();
    } catch (error) {
      errorMsg ??= _formatError(error);
    }
    if (!_isAlive) return;

    try {
      cacheStats = await cacheGateway.getCacheStats();
    } catch (error) {
      errorMsg ??= _formatError(error);
    }
    if (!_isAlive) return;

    try {
      final storedThemes = await themeRepo.listThemes();
      if (!_isAlive) return;
      themes = storedThemes.isNotEmpty
          ? storedThemes
          : buildDefaultReaderThemes();
      final activeSetting = await themeRepo.getSetting(_kActiveThemeKey);
      if (!_isAlive) return;
      if (activeSetting != null) {
        activeTheme = themes.firstWhere(
          (t) => t.id == activeSetting.value,
          orElse: () => themes.first,
        );
      } else {
        activeTheme = themes.first;
      }

      if (activeTheme.fontPath != null && activeTheme.fontPath!.isNotEmpty) {
        try {
          await fontGateway.ensureFontLoaded(
            activeTheme.fontFamily,
            activeTheme.fontPath,
          );
        } catch (_) {
          // Keep settings responsive if a restored/moved font file is missing.
        }
      }
    } catch (error) {
      themes = themes.isNotEmpty ? themes : buildDefaultReaderThemes();
      activeTheme ??= themes.first;
      errorMsg ??= _formatError(error);
    }

    if (!_isAlive) return;
    state = state.copyWith(
      isLoading: false,
      databaseSnapshots: snapshots,
      cacheStats: cacheStats,
      availableThemes: themes,
      activeTheme: activeTheme,
      errorMessage: errorMsg,
      clearError: errorMsg == null,
    );
  }

  /// Updates whether custom `.ttf`/`.otf` fonts are packaged during export.
  void setIncludeCustomFonts(bool includeCustomFonts) {
    if (!_isAlive) return;
    state = state.copyWith(includeCustomFonts: includeCustomFonts);
  }

  /// Exports a `.pureread.zip` archive to [targetArchivePath] (or the default
  /// resolved export location when omitted).
  Future<String?> exportBackup({
    String? targetArchivePath,
    bool? includeCustomFonts,
  }) async {
    if (!_isAlive || state.isBusy) return null;
    final backupRepo = ref.read(backupRepositoryProvider);
    final pathResolver = ref.read(backupExportPathResolverProvider);
    final includeFonts = includeCustomFonts ?? state.includeCustomFonts;

    state = state.copyWith(
      isExporting: true,
      clearStatus: true,
      clearError: true,
    );

    try {
      final resolvedPath = (targetArchivePath != null &&
              targetArchivePath.trim().isNotEmpty)
          ? targetArchivePath.trim()
          : await pathResolver(DateTime.now().toUtc());
      if (!_isAlive) return null;

      final exportedPath = await backupRepo.exportBackup(
        resolvedPath,
        includeCustomFonts: includeFonts,
      );
      if (!_isAlive) return null;

      state = state.copyWith(
        isExporting: false,
        lastExportedPath: exportedPath,
        statusMessage: '已成功导出整库备份至：$exportedPath',
      );
      return exportedPath;
    } catch (error) {
      if (!_isAlive) return null;
      state = state.copyWith(
        isExporting: false,
        errorMessage: _formatError(error),
      );
      return null;
    }
  }

  /// Opens the native file picker for a `.pureread.zip` archive and inspects its
  /// manifest & archive integrity before prompting for restore mode.
  Future<BackupManifest?> pickAndInspectBackup() async {
    if (!_isAlive || state.isBusy) return null;
    final platform = ref.read(platformBridgeProvider);

    state = state.copyWith(
      isInspecting: true,
      clearStatus: true,
      clearError: true,
    );

    try {
      final paths = await platform.pickFiles(
        extensions: const <String>['zip'],
        allowMultiple: false,
      );
      if (!_isAlive) return null;
      if (paths.isEmpty) {
        state = state.copyWith(isInspecting: false);
        return null;
      }
      return await _inspectArchiveInternal(paths.first);
    } catch (error) {
      if (!_isAlive) return null;
      state = state.copyWith(
        isInspecting: false,
        clearInspectedBackup: true,
        errorMessage: _formatError(error),
      );
      return null;
    }
  }

  /// Validates [archivePath] and stages its [BackupManifest] for user preview.
  Future<BackupManifest?> inspectBackupFile(String archivePath) async {
    if (!_isAlive || state.isBusy) return null;
    state = state.copyWith(
      isInspecting: true,
      clearStatus: true,
      clearError: true,
    );
    return _inspectArchiveInternal(archivePath);
  }

  Future<BackupManifest?> _inspectArchiveInternal(String archivePath) async {
    final backupRepo = ref.read(backupRepositoryProvider);
    try {
      final manifest = await backupRepo.inspectBackup(archivePath);
      if (!_isAlive) return null;
      state = state.copyWith(
        isInspecting: false,
        inspectedArchivePath: archivePath,
        inspectedManifest: manifest,
      );
      return manifest;
    } catch (error) {
      if (!_isAlive) return null;
      state = state.copyWith(
        isInspecting: false,
        clearInspectedBackup: true,
        errorMessage: _formatError(error),
      );
      return null;
    }
  }

  /// Dismisses the currently inspected archive preview without restoring.
  void clearInspectedBackup() {
    if (!_isAlive) return;
    state = state.copyWith(clearInspectedBackup: true);
  }

  /// Executes [BackupRepository.restoreBackup] using [mode] (`merge` or
  /// `overwrite`) on [archivePath] (or the staged [BackupState.inspectedArchivePath]).
  Future<bool> restoreBackup({
    required BackupRestoreMode mode,
    String? archivePath,
  }) async {
    if (!_isAlive || state.isBusy) return false;
    final targetPath = archivePath ?? state.inspectedArchivePath;
    if (targetPath == null || targetPath.trim().isEmpty) {
      return false;
    }

    final backupRepo = ref.read(backupRepositoryProvider);
    state = state.copyWith(
      isRestoring: true,
      clearStatus: true,
      clearError: true,
    );

    try {
      await backupRepo.restoreBackup(targetPath, mode: mode);
      if (!_isAlive) return false;

      state = state.copyWith(
        isRestoring: false,
        clearInspectedBackup: true,
        statusMessage: mode == BackupRestoreMode.merge
            ? '已按合并模式恢复整库备份，并已自动生成恢复前数据库快照'
            : '已按覆盖模式恢复整库备份，并已自动生成恢复前数据库快照',
      );
      await refresh();
      return true;
    } catch (error) {
      if (!_isAlive) return false;
      state = state.copyWith(
        isRestoring: false,
        errorMessage: _formatError(error),
      );
      return false;
    }
  }

  /// Clears online chapter text & temporary caches without touching shelf or
  /// reading progress.
  Future<int?> clearChapterCache() async {
    if (!_isAlive || state.isBusy) return null;
    final cacheGateway = ref.read(cacheManagementGatewayProvider);

    state = state.copyWith(
      isClearingCache: true,
      clearStatus: true,
      clearError: true,
    );

    try {
      final freedBytes = await cacheGateway.clearChapterCache();
      if (!_isAlive) return null;
      final updatedStats = await cacheGateway.getCacheStats();
      if (!_isAlive) return null;

      state = state.copyWith(
        isClearingCache: false,
        cacheStats: updatedStats,
        statusMessage: freedBytes > 0
            ? '已清理章节缓存，释放 ${formatByteSize(freedBytes)}'
            : '章节缓存已清空',
      );
      return freedBytes;
    } catch (error) {
      if (!_isAlive) return null;
      state = state.copyWith(
        isClearingCache: false,
        errorMessage: _formatError(error),
      );
      return null;
    }
  }

  /// Persists the active default [ReaderTheme] selection.
  Future<void> selectTheme(String themeId) async {
    if (!_isAlive || state.isBusy) return;
    final themeRepo = ref.read(themeRepositoryProvider);
    final fontGateway = ref.read(fontLoaderGatewayProvider);

    final target = state.availableThemes.firstWhere(
      (t) => t.id == themeId,
      orElse: () => state.activeTheme ?? buildDefaultReaderThemes().first,
    );

    try {
      if (target.fontPath != null && target.fontPath!.isNotEmpty) {
        try {
          await fontGateway.ensureFontLoaded(target.fontFamily, target.fontPath);
        } catch (_) {
          // Continue switching theme even if custom font file is missing.
        }
        if (!_isAlive) return;
      }

      await themeRepo.saveSetting(
        AppSetting(
          key: _kActiveThemeKey,
          value: target.id,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (!_isAlive) return;

      state = state.copyWith(
        activeTheme: target,
        statusMessage: '已将默认阅读主题切换为「${target.name}」',
        clearError: true,
      );
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Picks a `.ttf` or `.otf` font file, registers it, and applies it to the
  /// active reader theme.
  Future<void> importCustomFont() async {
    if (!_isAlive || state.isBusy) return;
    final platform = ref.read(platformBridgeProvider);
    final fontGateway = ref.read(fontLoaderGatewayProvider);
    final themeRepo = ref.read(themeRepositoryProvider);

    try {
      final paths = await platform.pickFiles(
        extensions: const <String>['ttf', 'otf'],
        allowMultiple: false,
      );
      if (!_isAlive || paths.isEmpty) return;

      final loaded = await fontGateway.importAndRegisterFont(paths.first);
      if (!_isAlive) return;

      final current = state.activeTheme ?? buildDefaultReaderThemes().first;
      final updated = current.copyWith(
        fontFamily: loaded.fontFamily,
        fontPath: loaded.relativeFontPath,
        updatedAt: DateTime.now().toUtc(),
      );
      await themeRepo.saveTheme(updated);
      if (!_isAlive) return;
      await themeRepo.saveSetting(
        AppSetting(
          key: _kActiveThemeKey,
          value: updated.id,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (!_isAlive) return;

      final updatedThemes = state.availableThemes
          .map((t) => t.id == updated.id ? updated : t)
          .toList(growable: false);

      state = state.copyWith(
        activeTheme: updated,
        availableThemes: updatedThemes.any((t) => t.id == updated.id)
            ? updatedThemes
            : <ReaderTheme>[...updatedThemes, updated],
        statusMessage: '已导入并应用自定义字体：${loaded.fontFamily}',
        clearError: true,
      );
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: '导入字体失败：${_formatError(error)}');
    }
  }

  /// Resets the active reader theme's font back to system default.
  Future<void> resetCustomFont() async {
    if (!_isAlive || state.isBusy) return;
    final themeRepo = ref.read(themeRepositoryProvider);
    final current = state.activeTheme;
    if (current == null || current.fontFamily == 'system') return;

    try {
      final updated = current.copyWith(
        fontFamily: 'system',
        clearFontPath: true,
        updatedAt: DateTime.now().toUtc(),
      );
      await themeRepo.saveTheme(updated);
      if (!_isAlive) return;

      final updatedThemes = state.availableThemes
          .map((t) => t.id == updated.id ? updated : t)
          .toList(growable: false);

      state = state.copyWith(
        activeTheme: updated,
        availableThemes: updatedThemes,
        statusMessage: '已恢复系统默认字体',
        clearError: true,
      );
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Dismisses active status or error banners.
  void clearBanner() {
    if (!_isAlive) return;
    state = state.copyWith(clearStatus: true, clearError: true);
  }

  String _formatError(Object error) {
    if (error is DatabaseFailure && error.backupSnapshotPath != null) {
      return '${error.message}（安全快照：${error.backupSnapshotPath}）';
    }
    if (error is AppFailure) return error.message;
    return error.toString();
  }
}
