import '../../domain/domain.dart';
import 'backup_providers.dart';

/// Immutable UI & application state managed by [BackupController].
class BackupState {
  final bool isLoading;
  final bool isExporting;
  final bool isInspecting;
  final bool isRestoring;
  final bool isClearingCache;
  final bool includeCustomFonts;
  final String? lastExportedPath;
  final String? inspectedArchivePath;
  final BackupManifest? inspectedManifest;
  final List<String> databaseSnapshots;
  final CacheStats cacheStats;
  final List<ReaderTheme> availableThemes;
  final ReaderTheme? activeTheme;
  final String? statusMessage;
  final String? errorMessage;

  const BackupState({
    this.isLoading = false,
    this.isExporting = false,
    this.isInspecting = false,
    this.isRestoring = false,
    this.isClearingCache = false,
    this.includeCustomFonts = true,
    this.lastExportedPath,
    this.inspectedArchivePath,
    this.inspectedManifest,
    this.databaseSnapshots = const <String>[],
    this.cacheStats = const CacheStats(
      chapterCacheBytes: 0,
      cachedFileCount: 0,
    ),
    this.availableThemes = const <ReaderTheme>[],
    this.activeTheme,
    this.statusMessage,
    this.errorMessage,
  });

  bool get isBusy =>
      isExporting || isInspecting || isRestoring || isClearingCache;

  BackupState copyWith({
    bool? isLoading,
    bool? isExporting,
    bool? isInspecting,
    bool? isRestoring,
    bool? isClearingCache,
    bool? includeCustomFonts,
    String? lastExportedPath,
    String? inspectedArchivePath,
    BackupManifest? inspectedManifest,
    bool clearInspectedBackup = false,
    List<String>? databaseSnapshots,
    CacheStats? cacheStats,
    List<ReaderTheme>? availableThemes,
    ReaderTheme? activeTheme,
    String? statusMessage,
    bool clearStatus = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return BackupState(
      isLoading: isLoading ?? this.isLoading,
      isExporting: isExporting ?? this.isExporting,
      isInspecting: isInspecting ?? this.isInspecting,
      isRestoring: isRestoring ?? this.isRestoring,
      isClearingCache: isClearingCache ?? this.isClearingCache,
      includeCustomFonts: includeCustomFonts ?? this.includeCustomFonts,
      lastExportedPath: lastExportedPath ?? this.lastExportedPath,
      inspectedArchivePath: clearInspectedBackup
          ? null
          : (inspectedArchivePath ?? this.inspectedArchivePath),
      inspectedManifest: clearInspectedBackup
          ? null
          : (inspectedManifest ?? this.inspectedManifest),
      databaseSnapshots: databaseSnapshots ?? this.databaseSnapshots,
      cacheStats: cacheStats ?? this.cacheStats,
      availableThemes: availableThemes ?? this.availableThemes,
      activeTheme: activeTheme ?? this.activeTheme,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
