import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/application/backup/backup.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/database/database.dart';
import 'package:pureread/infrastructure/database/drift_backup_repository.dart';
import 'package:pureread/infrastructure/storage/storage.dart';

Future<AppPathResolver> _createTempPathResolver(
  Directory root, {
  String folderName = 'app',
}) {
  final base = p.join(root.path, folderName);
  return AppPathResolver.resolve(
    executablePath: p.join(base, 'pureread.exe'),
    isWindowsOverride: false,
    supportDirProvider: () async => Directory(p.join(base, 'support')),
    cacheDirProvider: () async => Directory(p.join(base, 'cache')),
  );
}

Future<void> _seedSampleDatabase({
  required AppDatabase db,
  required AppPathResolver pathResolver,
  required DateTime timestamp,
}) async {
  final bookRepo = DriftBookRepository(db);
  final themeRepo = DriftThemeRepository(db);
  final sourceRepo = DriftSourceRepository(db);

  await bookRepo.saveGroup(
    BookGroup(
      id: 'serial',
      name: '追更中',
      sortOrder: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
  );

  await bookRepo.saveBook(
    Book(
      id: 'book-txt-1',
      providerType: ProviderType.localTxt,
      title: '凡人修仙传',
      author: '忘语',
      intro: '山村穷小子修仙之路',
      localFilePath: r'D:\Books\fanren.txt',
      fileEncoding: 'gb18030',
      fileSizeBytes: 31457280,
      fileHash: 'hash-fanren',
      groupId: 'serial',
      isPinned: true,
      totalChapters: 1200,
      unreadCount: 0,
      lastChapterTitle: '第10章 墨大夫',
      lastReadAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
  );

  await bookRepo.replaceChapters('book-txt-1', [
    ChapterMeta(
      bookId: 'book-txt-1',
      chapterIndex: 0,
      title: '第一章 山边小村',
      byteStart: 0,
      byteEnd: 2048,
      wordCount: 800,
      updatedAt: timestamp,
    ),
  ]);

  await bookRepo.saveProgress(
    ReadingProgress(
      bookId: 'book-txt-1',
      chapterIndex: 9,
      charOffset: 1234,
      chapterTitleSnapshot: '第10章 墨大夫',
      progressPercent: 0.42,
      readingDurationSec: 3600,
      updatedAt: timestamp,
      deviceId: 'win-desktop',
    ),
  );

  await bookRepo.saveBookmark(
    Bookmark(
      id: 'bm-1',
      bookId: 'book-txt-1',
      chapterIndex: 9,
      charOffset: 1200,
      excerpt: '七玄门收徒大典',
      note: '关键伏笔',
      createdAt: timestamp,
    ),
  );

  await sourceRepo.saveSource(
    BookSource(
      id: 'src-legado-1',
      name: '测试书源',
      groupName: '精品',
      engineType: SourceEngineType.legado,
      baseUrl: 'https://source.example',
      rawDefinition: '{"bookSourceName":"测试书源"}',
      enabled: true,
      weight: 80,
      rateLimitMs: 600,
      lastCheckStatus: SourceCheckStatus.ok,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
  );

  await sourceRepo.saveReplaceRule(
    ReplaceRule(
      id: 'rule-1',
      name: '去广告',
      groupName: '通用',
      pattern: r'\[广告.*?\]',
      replacement: '',
      isRegex: true,
      scopeType: RuleScopeType.global,
      enabled: true,
      sortOrder: 1,
      updatedAt: timestamp,
    ),
  );

  final customFontFile = File(
    p.join(pathResolver.fontsDir.path, 'wenkai_test.ttf'),
  );
  await customFontFile.parent.create(recursive: true);
  final fakeFontBytes = Uint8List.fromList([0, 1, 0, 0, 11, 22, 33, 44]);
  await customFontFile.writeAsBytes(fakeFontBytes, flush: true);

  await themeRepo.saveTheme(
    ReaderTheme(
      id: 'custom-theme',
      name: '青竹护眼',
      isBuiltin: false,
      isDark: false,
      bgColor: 0xFFE3EDCD,
      textColor: 0xFF1F2D21,
      secondaryTextColor: 0xFF5D6E60,
      fontFamily: 'pureread_wenkai_test',
      fontPath: 'fonts/wenkai_test.ttf',
      fontSize: 20.5,
      fontWeight: 500,
      lineHeight: 1.75,
      paragraphSpacing: 14.0,
      letterSpacing: 0.3,
      paragraphIndentChars: 2,
      marginHorizontal: 24.0,
      marginVertical: 28.0,
      columnMode: ColumnMode.double,
      maxContentWidth: 800.0,
      pageTurnMode: PageTurnMode.slide,
      enablePunctuationHanging: true,
      enableCjkSpacing: true,
      updatedAt: timestamp,
    ),
  );

  await themeRepo.saveSetting(
    AppSetting(
      key: 'active_theme_id',
      value: 'custom-theme',
      updatedAt: timestamp,
    ),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pureread_backup_repo_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'exportBackup writes valid .pureread.zip with manifest, 8 JSON tables, and optional fonts',
    () async {
      final resolver = await _createTempPathResolver(tempDir, folderName: 'exp');
      final db = AppDatabase.forFile(
        resolver.databaseFile,
        backupsDirPath: resolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      final fixedTime = DateTime.utc(2026, 11, 24, 19, 10, 5);
      final backupRepo = DriftBackupRepository(
        db,
        resolver,
        appVersion: '1.0.0+1',
        nowProvider: () => fixedTime,
      );

      try {
        await _seedSampleDatabase(
          db: db,
          pathResolver: resolver,
          timestamp: fixedTime,
        );

        final withFontsPath = p.join(tempDir.path, 'full.pureread.zip');
        final returnedPath = await backupRepo.exportBackup(
          withFontsPath,
          includeCustomFonts: true,
        );
        expect(returnedPath, withFontsPath);
        expect(await File(withFontsPath).exists(), isTrue);

        final manifest = await backupRepo.inspectBackup(withFontsPath);
        expect(manifest.formatVersion, 1);
        expect(manifest.appVersion, '1.0.0+1');
        expect(manifest.schemaVersion, 1);
        expect(manifest.exportedAt, fixedTime);
        expect(manifest.recordCounts['book_groups'], 2); // default + serial
        expect(manifest.recordCounts['books'], 1);
        expect(manifest.recordCounts['reading_progress'], 1);
        expect(manifest.recordCounts['bookmarks'], 1);
        expect(manifest.recordCounts['book_sources'], 1);
        expect(manifest.recordCounts['replace_rules'], 1);
        expect(manifest.recordCounts['reader_themes'], 5); // 4 built-in + 1 custom
        expect(manifest.recordCounts['app_settings'], 1);
        expect(manifest.recordCounts['fonts'], 1);

        final archive = ZipDecoder().decodeBytes(
          await File(withFontsPath).readAsBytes(),
          verify: true,
          throwOnError: true,
        );
        try {
          final entryNames = archive.files.map((e) => e.name).toSet();
          expect(entryNames, contains('manifest.json'));
          for (final dataFile in DriftBackupRepository.requiredDataEntries) {
            expect(entryNames, contains(dataFile));
          }
          expect(entryNames, contains('fonts/wenkai_test.ttf'));
          expect(entryNames, isNot(contains('data/chapters.json')));
        } finally {
          archive.clearSync();
        }

        // Export without custom fonts omits fonts/* entries.
        final withoutFontsPath = p.join(tempDir.path, 'nofonts.pureread.zip');
        await backupRepo.exportBackup(
          withoutFontsPath,
          includeCustomFonts: false,
        );
        final noFontManifest = await backupRepo.inspectBackup(withoutFontsPath);
        expect(noFontManifest.recordCounts['fonts'], 0);
        final noFontArchive = ZipDecoder().decodeBytes(
          await File(withoutFontsPath).readAsBytes(),
          verify: true,
          throwOnError: true,
        );
        try {
          expect(
            noFontArchive.files.any((f) => f.name.startsWith('fonts/')),
            isFalse,
          );
        } finally {
          noFontArchive.clearSync();
        }
      } finally {
        await db.close();
      }
    },
  );

  test(
    'inspectBackup throws FileAccessFailure on missing, corrupt, invalid manifest, or unsafe archive',
    () async {
      final resolver = await _createTempPathResolver(tempDir, folderName: 'val');
      final db = AppDatabase.inMemory();
      final backupRepo = DriftBackupRepository(db, resolver);

      try {
        // Missing file
        await expectLater(
          () => backupRepo.inspectBackup(
            p.join(tempDir.path, 'missing.pureread.zip'),
          ),
          throwsA(isA<FileAccessFailure>()),
        );

        // Empty file
        final emptyFile = File(p.join(tempDir.path, 'empty.pureread.zip'));
        await emptyFile.writeAsBytes(const <int>[]);
        await expectLater(
          () => backupRepo.inspectBackup(emptyFile.path),
          throwsA(isA<FileAccessFailure>()),
        );

        // Corrupt zip bytes
        final corruptFile = File(p.join(tempDir.path, 'corrupt.pureread.zip'));
        await corruptFile.writeAsString('not-a-zip-archive');
        await expectLater(
          () => backupRepo.inspectBackup(corruptFile.path),
          throwsA(isA<FileAccessFailure>()),
        );

        // Zip missing manifest.json
        final noManifestPath = p.join(tempDir.path, 'no_manifest.pureread.zip');
        final noManifestArchive = Archive()
          ..addFile(ArchiveFile.string('data/books.json', '[]'));
        await File(noManifestPath).writeAsBytes(
          ZipEncoder().encodeBytes(noManifestArchive),
        );
        noManifestArchive.clearSync();
        await expectLater(
          () => backupRepo.inspectBackup(noManifestPath),
          throwsA(isA<FileAccessFailure>()),
        );

        // Zip with unsupported formatVersion
        final futureFormatPath = p.join(tempDir.path, 'future_fmt.pureread.zip');
        final futureArchive = Archive()
          ..addFile(
            ArchiveFile.string(
              'manifest.json',
              jsonEncode({
                'formatVersion': 99,
                'appVersion': '2.0.0',
                'schemaVersion': 1,
                'exportedAt': DateTime.utc(2026, 11, 24).toIso8601String(),
                'counts': <String, int>{},
              }),
            ),
          );
        for (final entry in DriftBackupRepository.requiredDataEntries) {
          futureArchive.addFile(ArchiveFile.string(entry, '[]'));
        }
        await File(futureFormatPath).writeAsBytes(
          ZipEncoder().encodeBytes(futureArchive),
        );
        futureArchive.clearSync();
        await expectLater(
          () => backupRepo.inspectBackup(futureFormatPath),
          throwsA(isA<FileAccessFailure>()),
        );

        // Zip missing one of the 8 required data/*.json files
        final incompletePath = p.join(tempDir.path, 'incomplete.pureread.zip');
        final incompleteArchive = Archive()
          ..addFile(
            ArchiveFile.string(
              'manifest.json',
              jsonEncode({
                'formatVersion': 1,
                'appVersion': '1.0.0+1',
                'schemaVersion': 1,
                'exportedAt': DateTime.utc(2026, 11, 24).toIso8601String(),
                'counts': <String, int>{},
              }),
            ),
          )
          ..addFile(ArchiveFile.string('data/books.json', '[]'));
        await File(incompletePath).writeAsBytes(
          ZipEncoder().encodeBytes(incompleteArchive),
        );
        incompleteArchive.clearSync();
        await expectLater(
          () => backupRepo.inspectBackup(incompletePath),
          throwsA(isA<FileAccessFailure>()),
        );

        // Zip with path traversal entry
        final traversalPath = p.join(tempDir.path, 'traversal.pureread.zip');
        final traversalArchive = Archive()
          ..addFile(
            ArchiveFile.string(
              'manifest.json',
              jsonEncode({
                'formatVersion': 1,
                'appVersion': '1.0.0+1',
                'schemaVersion': 1,
                'exportedAt': DateTime.utc(2026, 11, 24).toIso8601String(),
                'counts': <String, int>{},
              }),
            ),
          );
        for (final entry in DriftBackupRepository.requiredDataEntries) {
          traversalArchive.addFile(ArchiveFile.string(entry, '[]'));
        }
        traversalArchive.addFile(
          ArchiveFile.bytes('fonts/../escape.ttf', [1, 2, 3]),
        );
        await File(traversalPath).writeAsBytes(
          ZipEncoder().encodeBytes(traversalArchive),
        );
        traversalArchive.clearSync();
        await expectLater(
          () => backupRepo.inspectBackup(traversalPath),
          throwsA(isA<FileAccessFailure>()),
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'restoreBackup overwrite creates pre-restore snapshot and replaces all 8 tables + fonts',
    () async {
      final srcResolver = await _createTempPathResolver(
        tempDir,
        folderName: 'src_ow',
      );
      final dstResolver = await _createTempPathResolver(
        tempDir,
        folderName: 'dst_ow',
      );
      final srcDb = AppDatabase.forFile(
        srcResolver.databaseFile,
        backupsDirPath: srcResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      final dstDb = AppDatabase.forFile(
        dstResolver.databaseFile,
        backupsDirPath: dstResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );

      final srcTime = DateTime.utc(2026, 11, 24, 10, 0);
      final dstTime = DateTime.utc(2026, 11, 24, 11, 0);

      final archivePath = p.join(tempDir.path, 'overwrite.pureread.zip');

      try {
        await _seedSampleDatabase(
          db: srcDb,
          pathResolver: srcResolver,
          timestamp: srcTime,
        );
        final srcBackupRepo = DriftBackupRepository(srcDb, srcResolver);
        await srcBackupRepo.exportBackup(archivePath, includeCustomFonts: true);

        // Populate destination DB with distinct pre-restore state.
        final dstBookRepo = DriftBookRepository(dstDb);
        await dstBookRepo.saveBook(
          Book(
            id: 'old-local-book',
            providerType: ProviderType.localTxt,
            title: '将被覆盖的旧书',
            createdAt: dstTime,
            updatedAt: dstTime,
          ),
        );

        final dstBackupRepo = DriftBackupRepository(dstDb, dstResolver);
        expect(await dstBackupRepo.listDatabaseSnapshots(), isEmpty);

        await dstBackupRepo.restoreBackup(
          archivePath,
          mode: BackupRestoreMode.overwrite,
        );

        // Pre-restore snapshot was automatically generated before overwrite.
        final snapshots = await dstBackupRepo.listDatabaseSnapshots();
        expect(snapshots, hasLength(1));
        expect(await File(snapshots.first).exists(), isTrue);

        // Verify the snapshot still preserves the pre-restore DB content.
        final snapshotDb = AppDatabase.forFile(
          File(snapshots.first),
          backupsDirPath: dstResolver.dbBackupsDir.path,
          useBackgroundIsolate: false,
        );
        try {
          final oldBookInSnap = await DriftBookRepository(
            snapshotDb,
          ).getBookById('old-local-book');
          expect(oldBookInSnap?.title, '将被覆盖的旧书');
        } finally {
          await snapshotDb.close();
        }

        // Verify destination DB now matches source backup and wiped old-local-book.
        expect(await dstBookRepo.getBookById('old-local-book'), isNull);
        final restoredBook = await dstBookRepo.getBookById('book-txt-1');
        expect(restoredBook?.title, '凡人修仙传');
        expect(restoredBook?.localFilePath, r'D:\Books\fanren.txt');
        expect(restoredBook?.isPinned, isTrue);

        final restoredProgress = await dstBookRepo.getProgress('book-txt-1');
        expect(restoredProgress?.charOffset, 1234);
        expect(restoredProgress?.chapterIndex, 9);

        final restoredBookmarks = await dstBookRepo.listBookmarks('book-txt-1');
        expect(restoredBookmarks.map((b) => b.id), ['bm-1']);

        final dstSourceRepo = DriftSourceRepository(dstDb);
        expect(
          (await dstSourceRepo.listSources()).map((s) => s.id),
          ['src-legado-1'],
        );
        expect(
          (await dstSourceRepo.listReplaceRules()).map((r) => r.id),
          ['rule-1'],
        );

        final dstThemeRepo = DriftThemeRepository(dstDb);
        expect(
          (await dstThemeRepo.getSetting('active_theme_id'))?.value,
          'custom-theme',
        );
        expect(
          (await dstThemeRepo.getThemeById('custom-theme'))?.fontPath,
          'fonts/wenkai_test.ttf',
        );
        expect(
          await dstResolver.resolveDataRelativeFile('fonts/wenkai_test.ttf').exists(),
          isTrue,
        );
      } finally {
        await srcDb.close();
        await dstDb.close();
      }
    },
  );

  test(
    'restoreBackup merge preserves non-conflicting local data, chapters, and updates overlapping keys',
    () async {
      final srcResolver = await _createTempPathResolver(
        tempDir,
        folderName: 'src_merge',
      );
      final dstResolver = await _createTempPathResolver(
        tempDir,
        folderName: 'dst_merge',
      );
      final srcDb = AppDatabase.forFile(
        srcResolver.databaseFile,
        backupsDirPath: srcResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      final dstDb = AppDatabase.forFile(
        dstResolver.databaseFile,
        backupsDirPath: dstResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );

      final t1 = DateTime.utc(2026, 11, 24, 10, 0);
      final t2 = DateTime.utc(2026, 11, 24, 12, 0);
      final archivePath = p.join(tempDir.path, 'merge.pureread.zip');

      try {
        await _seedSampleDatabase(
          db: srcDb,
          pathResolver: srcResolver,
          timestamp: t2,
        );
        await DriftBackupRepository(
          srcDb,
          srcResolver,
        ).exportBackup(archivePath, includeCustomFonts: true);

        // Seed destination DB with:
        // 1) local-only book + chapters + progress
        // 2) overlapping book-txt-1 with existing chapters that must NOT be
        //    cascade-deleted during upsert merge.
        final dstBookRepo = DriftBookRepository(dstDb);
        await dstBookRepo.saveBook(
          Book(
            id: 'local-only',
            providerType: ProviderType.localTxt,
            title: '本地独有书籍',
            createdAt: t1,
            updatedAt: t1,
          ),
        );
        await dstBookRepo.saveBook(
          Book(
            id: 'book-txt-1',
            providerType: ProviderType.localTxt,
            title: '凡人修仙传（旧标题）',
            createdAt: t1,
            updatedAt: t1,
          ),
        );
        await dstBookRepo.replaceChapters('book-txt-1', [
          ChapterMeta(
            bookId: 'book-txt-1',
            chapterIndex: 0,
            title: '本地已索引第一章',
            byteStart: 0,
            byteEnd: 512,
            updatedAt: t1,
          ),
        ]);

        final dstBackupRepo = DriftBackupRepository(dstDb, dstResolver);
        await dstBackupRepo.restoreBackup(
          archivePath,
          mode: BackupRestoreMode.merge,
        );

        final snapshots = await dstBackupRepo.listDatabaseSnapshots();
        expect(snapshots, hasLength(1));

        // Local-only book remains.
        expect((await dstBookRepo.getBookById('local-only'))?.title, '本地独有书籍');

        // Overlapping book updated from backup while keeping its indexed chapters.
        final mergedBook = await dstBookRepo.getBookById('book-txt-1');
        expect(mergedBook?.title, '凡人修仙传');
        expect(mergedBook?.author, '忘语');
        expect(
          (await dstBookRepo.listChapters('book-txt-1')).map((c) => c.title),
          ['本地已索引第一章'],
        );

        // Restored progress, bookmarks, sources, rules, themes all present.
        expect((await dstBookRepo.getProgress('book-txt-1'))?.charOffset, 1234);
        expect((await dstBookRepo.listBookmarks('book-txt-1')), hasLength(1));
      } finally {
        await srcDb.close();
        await dstDb.close();
      }
    },
  );

  test(
    'restoreBackup handles dangling foreign keys gracefully and rejects corrupt archives before snapshotting',
    () async {
      final resolver = await _createTempPathResolver(tempDir, folderName: 'fk');
      final db = AppDatabase.forFile(
        resolver.databaseFile,
        backupsDirPath: resolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      final backupRepo = DriftBackupRepository(db, resolver);

      try {
        // Corrupt zip must fail before creating a snapshot.
        final badPath = p.join(tempDir.path, 'bad.pureread.zip');
        await File(badPath).writeAsString('bad-zip');
        await expectLater(
          () => backupRepo.restoreBackup(badPath),
          throwsA(isA<FileAccessFailure>()),
        );
        expect(await backupRepo.listDatabaseSnapshots(), isEmpty);

        // Backup referencing missing group_id and orphan progress/bookmark.
        final now = DateTime.utc(2026, 11, 24);
        final ts = now.millisecondsSinceEpoch;
        final weirdPath = p.join(tempDir.path, 'dangling_fk.pureread.zip');
        final archive = Archive()
          ..addFile(
            ArchiveFile.string(
              'manifest.json',
              jsonEncode({
                'formatVersion': 1,
                'appVersion': '1.0.0+1',
                'schemaVersion': 1,
                'exportedAt': now.toIso8601String(),
                'counts': <String, int>{
                  'book_groups': 0,
                  'books': 1,
                  'reading_progress': 1,
                  'bookmarks': 1,
                  'book_sources': 0,
                  'replace_rules': 0,
                  'reader_themes': 0,
                  'app_settings': 0,
                },
              }),
            ),
          )
          ..addFile(ArchiveFile.string('data/book_groups.json', '[]'))
          ..addFile(
            ArchiveFile.string(
              'data/books.json',
              jsonEncode([
                {
                  'id': 'b1',
                  'provider_type': 'local_txt',
                  'title': '无分组测试书',
                  'group_id': 'deleted-group-id',
                  'created_at': ts,
                  'updated_at': ts,
                },
              ]),
            ),
          )
          ..addFile(
            ArchiveFile.string(
              'data/reading_progress.json',
              jsonEncode([
                {
                  'book_id': 'orphan-book',
                  'chapter_index': 2,
                  'char_offset': 50,
                  'updated_at': ts,
                },
              ]),
            ),
          )
          ..addFile(
            ArchiveFile.string(
              'data/bookmarks.json',
              jsonEncode([
                {
                  'id': 'bm-orphan',
                  'book_id': 'orphan-book',
                  'chapter_index': 0,
                  'char_offset': 0,
                  'excerpt': 'orphan',
                  'created_at': ts,
                },
              ]),
            ),
          )
          ..addFile(ArchiveFile.string('data/book_sources.json', '[]'))
          ..addFile(ArchiveFile.string('data/replace_rules.json', '[]'))
          ..addFile(ArchiveFile.string('data/reader_themes.json', '[]'))
          ..addFile(ArchiveFile.string('data/app_settings.json', '[]'));

        await File(weirdPath).writeAsBytes(ZipEncoder().encodeBytes(archive));
        archive.clearSync();

        await backupRepo.restoreBackup(
          weirdPath,
          mode: BackupRestoreMode.overwrite,
        );

        final bookRepo = DriftBookRepository(db);
        final book = await bookRepo.getBookById('b1');
        expect(book, isNotNull);
        expect(book!.groupId, isNull);
        expect(await bookRepo.getProgress('orphan-book'), isNull);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'DirectoryCacheManagementGateway measures and clears chapter/tmp caches without touching db or fonts',
    () async {
      final resolver = await _createTempPathResolver(
        tempDir,
        folderName: 'cache',
      );
      final chapterFile1 = resolver.chapterCacheFile('book-1', 0);
      final chapterFile2 = resolver.chapterCacheFile('book-1', 1);
      await chapterFile1.parent.create(recursive: true);
      await chapterFile1.writeAsString('第一章缓存正文');
      await chapterFile2.writeAsString('第二章缓存正文内容');

      final tmpFile = File(p.join(resolver.tmpCacheDir.path, 'staging.tmp'));
      await tmpFile.parent.create(recursive: true);
      await tmpFile.writeAsBytes([1, 2, 3, 4, 5]);

      final fontFile = File(p.join(resolver.fontsDir.path, 'keep_font.ttf'));
      await fontFile.parent.create(recursive: true);
      await fontFile.writeAsBytes([9, 8, 7]);

      var clearedHookCalled = false;
      final gateway = DirectoryCacheManagementGateway(
        chaptersCacheDir: resolver.chaptersCacheDir,
        tmpCacheDir: resolver.tmpCacheDir,
        onChapterCacheCleared: () async {
          clearedHookCalled = true;
        },
      );

      final before = await gateway.getCacheStats();
      expect(before.cachedFileCount, 2);
      expect(before.chapterCacheBytes, greaterThan(0));
      expect(before.tempCacheBytes, 5);
      expect(before.totalBytes, before.chapterCacheBytes + 5);

      final freed = await gateway.clearChapterCache();
      expect(freed, before.totalBytes);
      expect(clearedHookCalled, isTrue);

      final after = await gateway.getCacheStats();
      expect(after.cachedFileCount, 0);
      expect(after.totalBytes, 0);
      expect(await fontFile.exists(), isTrue);
    },
  );
}
