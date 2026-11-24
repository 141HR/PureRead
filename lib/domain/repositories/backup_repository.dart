/// Metadata summary stored in `manifest.json` of a `.pureread.zip` backup.
class BackupManifest {
  final int formatVersion;
  final String appVersion;
  final int schemaVersion;
  final DateTime exportedAt;
  final Map<String, int> recordCounts;

  const BackupManifest({
    required this.formatVersion,
    required this.appVersion,
    required this.schemaVersion,
    required this.exportedAt,
    required this.recordCounts,
  });
}

/// Strategy for restoring a `.pureread.zip` archive.
enum BackupRestoreMode { merge, overwrite }

/// Repository contract for `.pureread.zip` export/restore and DB snapshots.
abstract interface class BackupRepository {
  Future<BackupManifest> inspectBackup(String archivePath);

  Future<String> exportBackup(
    String targetArchivePath, {
    bool includeCustomFonts = true,
  });

  Future<void> restoreBackup(
    String archivePath, {
    BackupRestoreMode mode = BackupRestoreMode.merge,
  });

  Future<List<String>> listDatabaseSnapshots();
}
