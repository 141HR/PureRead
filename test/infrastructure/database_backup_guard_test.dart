import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/database/database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late Directory backupsDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pureread_backup_');
    dbFile = File(p.join(tempDir.path, 'db', 'pureread.db'));
    await dbFile.parent.create(recursive: true);
    backupsDir = Directory(p.join(tempDir.path, 'db', 'backups'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('creates snapshot with checkpointed WAL data and retains newest 3 backups', () async {
    final db = AppDatabase.forFile(
      dbFile,
      backupsDirPath: backupsDir.path,
      useBackgroundIsolate: false,
    );
    final repo = DriftBookRepository(db);
    final now = DateTime.utc(2026, 11, 24, 12, 0);

    await repo.saveBook(
      Book(
        id: 'wal-book',
        providerType: ProviderType.localTxt,
        title: 'WAL 持久测试',
        createdAt: now,
        updatedAt: now,
      ),
    );

    var tick = 0;
    final guard = DatabaseBackupGuard(
      backupsDirPath: backupsDir.path,
      maxBackups: 3,
      nowProvider: () {
        final ts = DateTime.utc(2026, 11, 24, 12, 0, tick, 100);
        tick++;
        return ts;
      },
    );

    // Snapshot while DB is still open in WAL mode by checkpointing WAL first.
    final liveSnapshotPath = await guard.backupBeforeUpgrade(
      dbFilePath: dbFile.path,
      oldVersion: 1,
      checkpointWal: () => db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);'),
    );
    expect(liveSnapshotPath, isNotNull);

    await db.close();

    // Verify checkAndBackupIfUpgrading returns null when target <= current version,
    // and creates a backup when targetSchemaVersion > user_version.
    expect(
      await guard.checkAndBackupIfUpgrading(
        dbFilePath: dbFile.path,
        targetSchemaVersion: 1,
      ),
      isNull,
    );
    final upgradeCheckSnapshot = await guard.checkAndBackupIfUpgrading(
      dbFilePath: dbFile.path,
      targetSchemaVersion: 2,
    );
    expect(upgradeCheckSnapshot, isNotNull);
    expect(
      p.basename(upgradeCheckSnapshot!),
      matches(RegExp(r'^pureread_v1_\d{8}_\d{6}_\d{3}.*\.db$')),
    );

    final createdPaths = <String>[liveSnapshotPath!, upgradeCheckSnapshot];
    for (var i = 2; i <= 4; i++) {
      final path = await guard.backupBeforeUpgrade(
        dbFilePath: dbFile.path,
        oldVersion: i,
      );
      expect(path, isNotNull);
      expect(
        p.basename(path!),
        matches(RegExp('^pureread_v${i}_\\d{8}_\\d{6}_\\d{3}.*\\.db\$')),
      );
      createdPaths.add(path);
    }

    final retained = await guard.listBackups();
    expect(retained.length, 3);
    expect(retained, equals([createdPaths[4], createdPaths[3], createdPaths[2]]));
    expect(await File(createdPaths[0]).exists(), isFalse);
    expect(await File(createdPaths[1]).exists(), isFalse);

    // Verify snapshot is a valid standalone SQLite database containing WAL data.
    final restoredDb = AppDatabase.forFile(
      File(retained.first),
      backupsDirPath: backupsDir.path,
      useBackgroundIsolate: false,
    );
    try {
      final restoredRepo = DriftBookRepository(restoredDb);
      final book = await restoredRepo.getBookById('wal-book');
      expect(book?.title, 'WAL 持久测试');
    } finally {
      await restoredDb.close();
    }
  });

  test('runs pre-upgrade backup automatically before AppDatabase migration', () async {
    final v1Db = AppDatabase.forFile(
      dbFile,
      backupsDirPath: backupsDir.path,
      useBackgroundIsolate: false,
      schemaVersion: 1,
    );
    final v1Repo = DriftBookRepository(v1Db);
    final now = DateTime.utc(2026, 11, 24);
    await v1Repo.saveBook(
      Book(
        id: 'book-before-upgrade',
        providerType: ProviderType.localTxt,
        title: '升级前书籍',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await v1Db.close();

    var backupsCountDuringUpgrade = 0;
    final v2Db = AppDatabase.forFile(
      dbFile,
      backupsDirPath: backupsDir.path,
      useBackgroundIsolate: false,
      schemaVersion: 2,
      onUpgradeOverride: (m, from, to) async {
        expect(from, 1);
        expect(to, 2);
        backupsCountDuringUpgrade = await backupsDir.exists()
            ? backupsDir.listSync().whereType<File>().length
            : 0;
        await m.database.customStatement(
          'ALTER TABLE app_settings ADD COLUMN note TEXT;',
        );
      },
    );
    final v2Repo = DriftBookRepository(v2Db);
    final bookAfter = await v2Repo.getBookById('book-before-upgrade');
    final versionRow = await v2Db
        .customSelect('PRAGMA user_version;')
        .getSingle();
    await v2Db.close();

    expect(backupsCountDuringUpgrade, 1);
    expect(bookAfter?.title, '升级前书籍');
    expect(versionRow.read<int>('user_version'), 2);
  });

  test('rolls back failed migration, emits DatabaseFailure with snapshot path, and restores', () async {
    final v1Db = AppDatabase.forFile(
      dbFile,
      backupsDirPath: backupsDir.path,
      useBackgroundIsolate: false,
      schemaVersion: 1,
    );
    final v1Repo = DriftBookRepository(v1Db);
    final now = DateTime.utc(2026, 11, 24);
    await v1Repo.saveBook(
      Book(
        id: 'book-safe',
        providerType: ProviderType.localTxt,
        title: '回滚保护书',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await v1Db.close();

    final brokenV2 = AppDatabase.forFile(
      dbFile,
      backupsDirPath: backupsDir.path,
      useBackgroundIsolate: false,
      schemaVersion: 2,
      onUpgradeOverride: (m, from, to) async {
        await m.database.customStatement(
          'CREATE TABLE temp_migration_artifact (id INTEGER PRIMARY KEY);',
        );
        throw StateError('simulated migration crash');
      },
    );

    DatabaseFailure? caughtFailure;
    try {
      await brokenV2.customSelect('SELECT 1;').get();
    } on DatabaseFailure catch (failure) {
      caughtFailure = failure;
    } finally {
      await brokenV2.close();
    }

    expect(caughtFailure, isNotNull);
    expect(caughtFailure!.backupSnapshotPath, isNotNull);
    expect(await File(caughtFailure.backupSnapshotPath!).exists(), isTrue);

    final guard = DatabaseBackupGuard(backupsDirPath: backupsDir.path);
    await guard.restoreFromBackup(
      backupFilePath: caughtFailure.backupSnapshotPath!,
      targetDbPath: dbFile.path,
    );

    final recoveredDb = AppDatabase.forFile(
      dbFile,
      backupsDirPath: backupsDir.path,
      useBackgroundIsolate: false,
      schemaVersion: 1,
    );
    try {
      final recoveredRepo = DriftBookRepository(recoveredDb);
      expect((await recoveredRepo.getBookById('book-safe'))?.title, '回滚保护书');
      final tempTables = await recoveredDb
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'temp_migration_artifact';",
          )
          .get();
      expect(tempTables, isEmpty);
    } finally {
      await recoveredDb.close();
    }
  });
}
