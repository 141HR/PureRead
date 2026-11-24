import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../domain/failures/app_failure.dart';
import 'database_backup_guard.dart';
import 'default_seeds.dart';
import 'drift_mappers.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Signature for custom upgrade hooks (primarily used in migration tests).
typedef DatabaseUpgradeHandler =
    Future<void> Function(Migrator migrator, int from, int to);

/// Primary Drift SQLite database for PureRead.
@DriftDatabase(
  tables: [
    BookGroups,
    Books,
    Chapters,
    ReadingProgressRecords,
    Bookmarks,
    BookSources,
    ReplaceRules,
    ReaderThemes,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Absolute path to the backing database file when file-backed, or `null`
  /// for in-memory databases.
  final String? dbFilePath;

  /// Optional pre-upgrade backup guard invoked before executing upgrade SQL.
  final DatabaseBackupGuard? backupGuard;

  /// Target schema version (defaults to `1`, overridable in migration tests).
  @override
  final int schemaVersion;

  /// Optional custom upgrade hook (primarily used in migration tests).
  final DatabaseUpgradeHandler? onUpgradeOverride;

  final DateTime Function() _nowProvider;

  /// Creates an [AppDatabase] backed by [executor].
  AppDatabase(
    super.executor, {
    this.dbFilePath,
    this.backupGuard,
    this.schemaVersion = 1,
    this.onUpgradeOverride,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? _defaultNow;

  /// Opens a file-backed [AppDatabase] with [DatabaseBackupGuard] attached.
  factory AppDatabase.forFile(
    File dbFile, {
    required String backupsDirPath,
    int maxBackups = 3,
    bool logStatements = false,
    bool useBackgroundIsolate = true,
    int schemaVersion = 1,
    DatabaseUpgradeHandler? onUpgradeOverride,
    DateTime Function()? nowProvider,
  }) {
    final executor = useBackgroundIsolate
        ? NativeDatabase.createInBackground(
            dbFile,
            logStatements: logStatements,
          )
        : NativeDatabase(dbFile, logStatements: logStatements);

    return AppDatabase(
      executor,
      dbFilePath: dbFile.path,
      backupGuard: DatabaseBackupGuard(
        backupsDirPath: backupsDirPath,
        maxBackups: maxBackups,
      ),
      schemaVersion: schemaVersion,
      onUpgradeOverride: onUpgradeOverride,
      nowProvider: nowProvider,
    );
  }

  /// Opens an in-memory [AppDatabase] suitable for fast unit tests.
  factory AppDatabase.inMemory({
    bool logStatements = false,
    int schemaVersion = 1,
    DatabaseUpgradeHandler? onUpgradeOverride,
    DateTime Function()? nowProvider,
  }) {
    return AppDatabase(
      NativeDatabase.memory(logStatements: logStatements),
      schemaVersion: schemaVersion,
      onUpgradeOverride: onUpgradeOverride,
      nowProvider: nowProvider,
    );
  }

  static DateTime _defaultNow() => DateTime.now().toUtc();

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      String? snapshotPath;
      try {
        if (from < to && backupGuard != null && dbFilePath != null) {
          snapshotPath = await backupGuard!.backupBeforeUpgrade(
            dbFilePath: dbFilePath!,
            oldVersion: from,
            checkpointWal: () =>
                customStatement('PRAGMA wal_checkpoint(TRUNCATE);'),
          );
        }

        await transaction(() async {
          if (onUpgradeOverride != null) {
            await onUpgradeOverride!(m, from, to);
          }
        });
      } catch (error, stackTrace) {
        if (error is DatabaseFailure) {
          rethrow;
        }
        throw DatabaseFailure(
          message: 'Database migration failed from v$from to v$to: $error',
          backupSnapshotPath: snapshotPath,
          cause: error,
          stackTrace: stackTrace,
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
      await customStatement('PRAGMA journal_mode = WAL;');
      await customStatement('PRAGMA synchronous = NORMAL;');
      await customStatement('PRAGMA temp_store = MEMORY;');

      if (details.wasCreated) {
        await _seedInitialData();
      }
    },
  );

  Future<void> _seedInitialData() async {
    final now = _nowProvider().toUtc();
    final defaultGroup = DefaultDatabaseSeeds.defaultGroup(now);
    final themes = DefaultDatabaseSeeds.builtInThemes(now);

    await transaction(() async {
      await into(bookGroups).insert(
        bookGroupToCompanion(defaultGroup),
        mode: InsertMode.insertOrIgnore,
      );
      await batch((b) {
        b.insertAll(
          readerThemes,
          themes.map(readerThemeToCompanion).toList(growable: false),
          mode: InsertMode.insertOrIgnore,
        );
      });
    });
  }
}
