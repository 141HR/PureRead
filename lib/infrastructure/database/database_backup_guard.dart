import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../../domain/failures/app_failure.dart';

/// Pre-upgrade SQLite backup guard implementing rolling snapshot retention.
///
/// Before executing any schema upgrade SQL, [DatabaseBackupGuard] flushes WAL
/// pages into the primary database file, copies the database snapshot to
/// `db/backups/pureread_v{oldVersion}_{timestamp}.db`, and trims older backup
/// files so at most [maxBackups] (default `3`) snapshots are retained.
class DatabaseBackupGuard {
  static const List<int> _sqliteHeaderBytes = <int>[
    0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
    0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
  ];

  static final RegExp _backupFilePattern = RegExp(
    r'^pureread_v(\d+)_(\d{8}_\d{6}_\d{3}(?:_\d+)?)\.db$',
  );

  final String backupsDirPath;
  final int maxBackups;
  final DateTime Function() nowProvider;

  const DatabaseBackupGuard({
    required this.backupsDirPath,
    this.maxBackups = 3,
    this.nowProvider = _defaultNow,
  }) : assert(maxBackups > 0, 'maxBackups must be positive');

  static DateTime _defaultNow() => DateTime.now().toUtc();

  /// Checks whether [dbFilePath] has `user_version < targetSchemaVersion` and
  /// creates a pre-upgrade snapshot if an upgrade is pending.
  Future<String?> checkAndBackupIfUpgrading({
    required String dbFilePath,
    required int targetSchemaVersion,
  }) async {
    final dbFile = File(dbFilePath);
    if (!await dbFile.exists()) {
      return null;
    }

    int? oldVersion;
    try {
      final isSqlite = await _hasSqliteHeader(dbFile);
      if (isSqlite) {
        final executor = NativeDatabase(dbFile, enableMigrations: false);
        try {
          await executor.ensureOpen(_NoOpExecutorUser());
          final rows = await executor.runSelect(
            'PRAGMA user_version;',
            const [],
          );
          if (rows.isNotEmpty) {
            final rawVersion = rows.first['user_version'];
            if (rawVersion is int) {
              oldVersion = rawVersion;
            }
          }
        } finally {
          await executor.close();
        }
      }
    } catch (error, stackTrace) {
      throw DatabaseFailure(
        message: 'Failed to inspect SQLite schema version before upgrade',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (oldVersion == null ||
        oldVersion <= 0 ||
        oldVersion >= targetSchemaVersion) {
      return null;
    }

    return backupBeforeUpgrade(
      dbFilePath: dbFilePath,
      oldVersion: oldVersion,
    );
  }

  /// Snapshots [dbFilePath] into `backupsDirPath/pureread_v{oldVersion}_{ts}.db`
  /// and rotates older backups so at most [maxBackups] remain.
  Future<String?> backupBeforeUpgrade({
    required String dbFilePath,
    required int oldVersion,
    Future<void> Function()? checkpointWal,
  }) async {
    final dbFile = File(dbFilePath);
    if (!await dbFile.exists()) {
      return null;
    }

    try {
      final backupsDir = Directory(backupsDirPath);
      if (!await backupsDir.exists()) {
        await backupsDir.create(recursive: true);
      }

      if (checkpointWal != null) {
        await checkpointWal();
      } else if (await _hasSqliteHeader(dbFile)) {
        final executor = NativeDatabase(dbFile, enableMigrations: false);
        try {
          await executor.ensureOpen(_NoOpExecutorUser());
          await executor.runCustom('PRAGMA wal_checkpoint(TRUNCATE);');
        } finally {
          await executor.close();
        }
      }

      final targetFile = await _allocateUniqueBackupFile(oldVersion);
      await dbFile.copy(targetFile.path);
      await pruneOldBackups();
      return targetFile.path;
    } catch (error, stackTrace) {
      if (error is DatabaseFailure) rethrow;
      throw DatabaseFailure(
        message: 'Failed to create pre-upgrade database backup: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Lists existing backup snapshot paths ordered from newest to oldest.
  Future<List<String>> listBackups() async {
    final backupsDir = Directory(backupsDirPath);
    if (!await backupsDir.exists()) {
      return const [];
    }

    try {
      final entries = <_BackupEntry>[];
      await for (final entity in backupsDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final fileName = p.basename(entity.path);
        final match = _backupFilePattern.firstMatch(fileName);
        if (match == null) continue;
        entries.add(
          _BackupEntry(
            path: entity.path,
            timestampKey: match.group(2)!,
          ),
        );
      }

      entries.sort((a, b) => b.compareKey.compareTo(a.compareKey));
      return entries.map((e) => e.path).toList(growable: false);
    } catch (error, stackTrace) {
      throw DatabaseFailure(
        message: 'Failed to list database backups: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Removes older backups beyond the newest [maxBackups] files.
  Future<void> pruneOldBackups() async {
    final backups = await listBackups();
    if (backups.length <= maxBackups) {
      return;
    }

    for (final stalePath in backups.skip(maxBackups)) {
      final staleFile = File(stalePath);
      if (await staleFile.exists()) {
        await staleFile.delete();
      }
    }
  }

  /// Restores [backupFilePath] over [targetDbPath], cleaning stale WAL/SHM
  /// sidecars so the restored database opens cleanly.
  ///
  /// The caller must close any open database connections to [targetDbPath]
  /// before invoking this method.
  Future<void> restoreFromBackup({
    required String backupFilePath,
    required String targetDbPath,
  }) async {
    final backupFile = File(backupFilePath);
    if (!await backupFile.exists()) {
      throw DatabaseFailure(
        message: 'Backup snapshot not found at $backupFilePath',
        backupSnapshotPath: backupFilePath,
      );
    }

    try {
      final targetFile = File(targetDbPath);
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }

      for (final suffix in const ['-wal', '-shm', '-journal']) {
        final sidecar = File('$targetDbPath$suffix');
        if (await sidecar.exists()) {
          await sidecar.delete();
        }
      }

      await backupFile.copy(targetDbPath);
    } catch (error, stackTrace) {
      if (error is DatabaseFailure) rethrow;
      throw DatabaseFailure(
        message: 'Failed to restore database from backup: $error',
        backupSnapshotPath: backupFilePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<File> _allocateUniqueBackupFile(int oldVersion) async {
    final baseTimestamp = _formatTimestamp(nowProvider().toUtc());
    var candidate = File(
      p.join(backupsDirPath, 'pureread_v${oldVersion}_$baseTimestamp.db'),
    );
    var suffix = 1;
    while (await candidate.exists()) {
      final paddedSuffix = suffix.toString().padLeft(3, '0');
      candidate = File(
        p.join(
          backupsDirPath,
          'pureread_v${oldVersion}_${baseTimestamp}_$paddedSuffix.db',
        ),
      );
      suffix++;
    }
    return candidate;
  }

  static String _formatTimestamp(DateTime utc) {
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final mm = utc.minute.toString().padLeft(2, '0');
    final ss = utc.second.toString().padLeft(2, '0');
    final ms = utc.millisecond.toString().padLeft(3, '0');
    return '$y$m${d}_$hh$mm${ss}_$ms';
  }

  static Future<bool> _hasSqliteHeader(File file) async {
    final length = await file.length();
    if (length < _sqliteHeaderBytes.length) {
      return false;
    }
    final raf = await file.open();
    try {
      final bytes = await raf.read(_sqliteHeaderBytes.length);
      if (bytes.length < _sqliteHeaderBytes.length) {
        return false;
      }
      for (var i = 0; i < _sqliteHeaderBytes.length; i++) {
        if (bytes[i] != _sqliteHeaderBytes[i]) {
          return false;
        }
      }
      return true;
    } finally {
      await raf.close();
    }
  }
}

class _NoOpExecutorUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

class _BackupEntry {
  final String path;
  final String timestampKey;

  const _BackupEntry({
    required this.path,
    required this.timestampKey,
  });

  /// Normalizes `yyyyMMdd_HHmmss_SSS` and `yyyyMMdd_HHmmss_SSS_seq` so
  /// lexicographical sorting places newer snapshots (and higher collision
  /// sequences within the same millisecond) first.
  String get compareKey {
    final normalizedTs = timestampKey.length == 19
        ? '${timestampKey}_000'
        : timestampKey;
    return '$normalizedTs|$path';
  }
}
