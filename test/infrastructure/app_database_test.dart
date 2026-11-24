import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/database/database.dart';

void main() {
  late AppDatabase db;
  late DriftBookRepository bookRepo;
  late DriftThemeRepository themeRepo;
  late DriftSourceRepository sourceRepo;

  setUp(() {
    db = AppDatabase.inMemory();
    bookRepo = DriftBookRepository(db);
    themeRepo = DriftThemeRepository(db);
    sourceRepo = DriftSourceRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase schema, PRAGMAs, and seeding', () {
    test('creates all 9 tables, 6 indexes, PRAGMAs, and default seeds', () async {
      // Trigger database initialization via a repository call.
      final groups = await bookRepo.listGroups();
      final themes = await themeRepo.listThemes();

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
          )
          .get();
      final tableNames = tables
          .map((row) => row.read<String>('name'))
          .toSet();

      expect(
        tableNames,
        equals({
          'book_groups',
          'books',
          'chapters',
          'reading_progress',
          'bookmarks',
          'book_sources',
          'replace_rules',
          'reader_themes',
          'app_settings',
        }),
      );

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%';",
          )
          .get();
      final indexNames = indexes
          .map((row) => row.read<String>('name'))
          .toSet();

      expect(
        indexNames,
        containsAll(<String>{
          'idx_books_shelf_sort',
          'idx_books_source_url',
          'idx_chapters_book_index',
          'idx_bookmarks_book_pos',
          'idx_sources_enabled_weight',
          'idx_replace_rules_active',
        }),
      );

      final fkRow = await db.customSelect('PRAGMA foreign_keys;').getSingle();
      expect(fkRow.read<int>('foreign_keys'), 1);

      final tempStoreRow = await db
          .customSelect('PRAGMA temp_store;')
          .getSingle();
      expect(tempStoreRow.read<int>('temp_store'), 2);

      final syncRow = await db.customSelect('PRAGMA synchronous;').getSingle();
      expect(syncRow.read<int>('synchronous'), 1);

      expect(groups.map((g) => g.id), contains('default'));
      expect(
        groups.firstWhere((g) => g.id == 'default').name,
        DefaultDatabaseSeeds.defaultGroupName,
      );

      expect(themes.length, 4);
      final themeMap = {for (final t in themes) t.id: t};
      expect(themeMap['eye_care_ivory']?.name, '米白护眼');
      expect(themeMap['eye_care_ivory']?.isDark, isFalse);
      expect(themeMap['eye_care_ivory']?.isBuiltin, isTrue);
      expect(themeMap['parchment_warm']?.name, '羊皮纸感');
      expect(themeMap['parchment_warm']?.isDark, isFalse);
      expect(themeMap['slate_night']?.name, '静谧暗灰');
      expect(themeMap['slate_night']?.isDark, isTrue);
      expect(themeMap['oled_pure_black']?.name, 'OLED 纯黑');
      expect(themeMap['oled_pure_black']?.isDark, isTrue);
    });

    test('enables WAL journal mode on file-backed database', () async {
      final tempDir = await Directory.systemTemp.createTemp('pureread_wal_');
      final fileDb = AppDatabase.forFile(
        File(p.join(tempDir.path, 'pureread.db')),
        backupsDirPath: p.join(tempDir.path, 'backups'),
        useBackgroundIsolate: false,
      );
      try {
        final journalRow = await fileDb
            .customSelect('PRAGMA journal_mode;')
            .getSingle();
        expect(journalRow.read<String>('journal_mode').toLowerCase(), 'wal');
      } finally {
        await fileDb.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });

  group('DriftBookRepository', () {
    test('supports BookGroup and Book CRUD, sorting, and ON DELETE SET NULL', () async {
      final t1 = DateTime.utc(2026, 11, 24, 10, 0, 0, 100);
      final t2 = DateTime.utc(2026, 11, 24, 11, 0, 0, 200);
      final t3 = DateTime.utc(2026, 11, 24, 12, 0, 0, 300);

      final group = BookGroup(
        id: 'serial',
        name: '追更中',
        sortOrder: 1,
        createdAt: t1,
        updatedAt: t1,
      );
      await bookRepo.saveGroup(group);
      expect((await bookRepo.listGroups()).map((g) => g.id), ['default', 'serial']);

      final localBook = Book(
        id: 'book-local',
        providerType: ProviderType.localTxt,
        title: '凡人修仙传',
        author: '忘语',
        localFilePath: r'D:\books\fanren.txt',
        fileEncoding: 'gb18030',
        fileSizeBytes: 31457280,
        fileHash: 'abc123',
        groupId: 'serial',
        isPinned: false,
        totalChapters: 2000,
        lastReadAt: t3,
        createdAt: t1,
        updatedAt: t3,
      );
      final pinnedBook = Book(
        id: 'book-pinned',
        sourceId: 'src-1',
        providerType: ProviderType.legado,
        originBookUrl: 'https://example.com/book/42',
        tocUrl: 'https://example.com/book/42/toc',
        title: '诡秘之主',
        author: '爱潜水的乌贼',
        groupId: 'serial',
        isPinned: true,
        unreadCount: 3,
        lastChapterTitle: '第100章',
        lastReadAt: t2,
        latestChapterAt: t3,
        createdAt: t1,
        updatedAt: t2,
      );
      final unreadBook = Book(
        id: 'book-unread',
        sourceId: 'src-2',
        providerType: ProviderType.jsPlugin,
        originBookUrl: 'https://example.org/99',
        title: '未读书籍',
        groupId: 'default',
        createdAt: t1,
        updatedAt: t1,
      );

      await bookRepo.saveBook(localBook);
      await bookRepo.saveBook(pinnedBook);
      await bookRepo.saveBook(unreadBook);

      final watchedSerial = expectLater(
        bookRepo.watchBooks(groupId: 'serial'),
        emits(
          predicate<List<Book>>(
            (list) => list.map((b) => b.id).join(',') == 'book-pinned,book-local',
          ),
        ),
      );
      await watchedSerial;

      final allBooks = await bookRepo.listBooks();
      expect(
        allBooks.map((b) => b.id).toList(),
        equals(['book-pinned', 'book-local', 'book-unread']),
      );

      final serialBooks = await bookRepo.listBooks(groupId: 'serial');
      expect(serialBooks.map((b) => b.id), ['book-pinned', 'book-local']);

      final foundByUrl = await bookRepo.findBySourceAndUrl(
        'src-1',
        'https://example.com/book/42',
      );
      expect(foundByUrl, equals(pinnedBook));
      expect(
        await bookRepo.findBySourceAndUrl('src-1', 'https://missing'),
        isNull,
      );

      // Clearing nullable groupId persists NULL on conflict update.
      await bookRepo.saveBook(localBook.copyWith(clearGroupId: true));
      final updatedLocal = await bookRepo.getBookById('book-local');
      expect(updatedLocal?.groupId, isNull);

      // Deleting group sets referencing books' groupId to NULL (ON DELETE SET NULL).
      await bookRepo.deleteGroup('serial');
      final afterGroupDelete = await bookRepo.getBookById('book-pinned');
      expect(afterGroupDelete, isNotNull);
      expect(afterGroupDelete!.groupId, isNull);
    });

    test('supports chapters, unique constraint, progress, bookmarks, and cascade deletes', () async {
      final now = DateTime.utc(2026, 11, 24, 12, 0, 0, 500);
      final book = Book(
        id: 'book-1',
        providerType: ProviderType.localTxt,
        title: '雪中悍刀行',
        createdAt: now,
        updatedAt: now,
      );
      await bookRepo.saveBook(book);

      final chapters = [
        ChapterMeta(
          bookId: 'book-1',
          chapterIndex: 0,
          title: '第一章 小二上酒',
          byteStart: 0,
          byteEnd: 2048,
          updatedAt: now,
        ),
        ChapterMeta(
          bookId: 'book-1',
          chapterIndex: 1,
          title: '第二章 江湖夜雨',
          url: 'https://example.com/c2',
          updatedAt: now,
        ),
      ];
      await bookRepo.replaceChapters('book-1', chapters);

      final loadedChapters = await bookRepo.listChapters('book-1');
      expect(loadedChapters.length, 2);
      expect(loadedChapters.first.title, '第一章 小二上酒');

      await bookRepo.markChapterCached(
        'book-1',
        1,
        'book-1/1.txt',
        wordCount: 3500,
      );
      final cachedChapter = await bookRepo.getChapter('book-1', 1);
      expect(cachedChapter?.isCached, isTrue);
      expect(cachedChapter?.cacheKey, 'book-1/1.txt');
      expect(cachedChapter?.wordCount, 3500);

      // Duplicate (book_id, chapter_index) triggers UNIQUE violation -> DatabaseFailure
      // and rolls back replaceChapters cleanly.
      await expectLater(
        () => bookRepo.replaceChapters('book-1', [
          ChapterMeta(
            bookId: 'book-1',
            chapterIndex: 0,
            title: '重复章',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'book-1',
            chapterIndex: 0,
            title: '重复章2',
            updatedAt: now,
          ),
        ]),
        throwsA(isA<DatabaseFailure>()),
      );
      expect((await bookRepo.listChapters('book-1')).length, 2);

      // ReadingProgress CRUD
      final progress = ReadingProgress(
        bookId: 'book-1',
        chapterIndex: 1,
        charOffset: 420,
        chapterTitleSnapshot: '第二章 江湖夜雨',
        progressPercent: 0.5,
        readingDurationSec: 180,
        updatedAt: now,
        deviceId: 'win-dev',
      );
      await bookRepo.saveProgress(progress);
      expect(await bookRepo.getProgress('book-1'), equals(progress));

      // Bookmarks CRUD & ordering
      final bm2 = Bookmark(
        id: 'bm-2',
        bookId: 'book-1',
        chapterIndex: 1,
        charOffset: 300,
        excerpt: '北凉铁骑',
        note: '名场面',
        createdAt: now,
      );
      final bm1 = Bookmark(
        id: 'bm-1',
        bookId: 'book-1',
        chapterIndex: 0,
        charOffset: 100,
        excerpt: '江湖夜雨十年灯',
        createdAt: now,
      );
      await bookRepo.saveBookmark(bm2);
      await bookRepo.saveBookmark(bm1);
      expect(
        (await bookRepo.listBookmarks('book-1')).map((b) => b.id),
        ['bm-1', 'bm-2'],
      );

      await bookRepo.deleteBookmark('bm-1');
      expect((await bookRepo.listBookmarks('book-1')).map((b) => b.id), ['bm-2']);

      // Deleting the book cascades to chapters, reading_progress, and bookmarks.
      await bookRepo.deleteBook('book-1');
      expect(await bookRepo.getBookById('book-1'), isNull);
      expect(await bookRepo.listChapters('book-1'), isEmpty);
      expect(await bookRepo.getProgress('book-1'), isNull);
      expect(await bookRepo.listBookmarks('book-1'), isEmpty);
    });

    test('maps foreign key violation to DatabaseFailure', () async {
      final now = DateTime.utc(2026, 11, 24);
      await expectLater(
        () => bookRepo.saveProgress(
          ReadingProgress(bookId: 'non-existent', updatedAt: now),
        ),
        throwsA(isA<DatabaseFailure>()),
      );

      await expectLater(
        () => bookRepo.saveBookmark(
          Bookmark(
            id: 'bm-bad',
            bookId: 'non-existent',
            chapterIndex: 0,
            charOffset: 0,
            excerpt: 'bad',
            createdAt: now,
          ),
        ),
        throwsA(isA<DatabaseFailure>()),
      );
    });
  });

  group('DriftThemeRepository', () {
    test('supports ReaderTheme and AppSetting CRUD plus reactive stream', () async {
      final now = DateTime.utc(2026, 11, 24, 15, 30, 0, 250);
      final customTheme = ReaderTheme(
        id: 'custom-green',
        name: '豆沙绿',
        isBuiltin: false,
        isDark: false,
        bgColor: 0xFFC7EDCC,
        textColor: 0xFF1E2B1E,
        secondaryTextColor: 0xFF546854,
        fontFamily: 'pureread_kai',
        fontPath: 'fonts/kai.ttf',
        fontSize: 20.0,
        fontWeight: 500,
        lineHeight: 1.8,
        paragraphSpacing: 16.0,
        letterSpacing: 0.4,
        paragraphIndentChars: 2,
        marginHorizontal: 24.0,
        marginVertical: 28.0,
        columnMode: ColumnMode.double,
        maxContentWidth: 820.0,
        pageTurnMode: PageTurnMode.slide,
        enablePunctuationHanging: true,
        enableCjkSpacing: false,
        updatedAt: now,
      );

      final emission = expectLater(
        themeRepo.watchThemes(),
        emitsThrough(
          predicate<List<ReaderTheme>>(
            (list) => list.any((t) => t.id == 'custom-green'),
          ),
        ),
      );

      await themeRepo.saveTheme(customTheme);
      await emission;

      expect(await themeRepo.getThemeById('custom-green'), equals(customTheme));

      await themeRepo.deleteTheme('custom-green');
      expect(await themeRepo.getThemeById('custom-green'), isNull);

      final setting = AppSetting(
        key: 'active_theme_id',
        value: 'eye_care_ivory',
        updatedAt: now,
      );
      await themeRepo.saveSetting(setting);
      await themeRepo.saveSetting(
        AppSetting(
          key: 'volume_key_turn',
          value: 'true',
          updatedAt: now,
        ),
      );

      expect(await themeRepo.getSetting('active_theme_id'), equals(setting));
      expect(
        (await themeRepo.listSettings()).map((s) => s.key),
        ['active_theme_id', 'volume_key_turn'],
      );
    });
  });

  group('DriftSourceRepository', () {
    test('supports BookSource batch CRUD, weight sorting, and watch stream', () async {
      final now = DateTime.utc(2026, 11, 24, 9, 0, 0, 123);
      final s1 = BookSource(
        id: 'src-low',
        name: '低权重源',
        engineType: SourceEngineType.jsPlugin,
        baseUrl: 'https://low.example',
        rawDefinition: 'function search(){}',
        enabled: true,
        weight: 10,
        createdAt: now,
        updatedAt: now,
      );
      final s2 = BookSource(
        id: 'src-high',
        name: '高权重源',
        engineType: SourceEngineType.legado,
        baseUrl: 'https://high.example',
        rawDefinition: '{"bookSourceName":"高权重源"}',
        enabled: true,
        weight: 100,
        lastCheckStatus: SourceCheckStatus.ok,
        createdAt: now,
        updatedAt: now,
      );
      final sDisabled = BookSource(
        id: 'src-off',
        name: '停用源',
        engineType: SourceEngineType.legado,
        baseUrl: 'https://off.example',
        rawDefinition: '{}',
        enabled: false,
        weight: 999,
        lastCheckStatus: SourceCheckStatus.unsupported,
        lastErrorSummary: 'webView unsupported',
        createdAt: now,
        updatedAt: now,
      );

      await sourceRepo.saveSources([s1, s2, sDisabled]);
      expect(
        (await sourceRepo.listSources()).map((s) => s.id),
        ['src-off', 'src-high', 'src-low'],
      );
      expect(
        (await sourceRepo.listSources(enabledOnly: true)).map((s) => s.id),
        ['src-high', 'src-low'],
      );
      expect(await sourceRepo.getSourceById('src-high'), equals(s2));

      final watched = expectLater(
        sourceRepo.watchSources(),
        emitsThrough(
          predicate<List<BookSource>>((list) => list.length == 2),
        ),
      );
      await sourceRepo.deleteSource('src-off');
      await watched;
    });

    test('filters ReplaceRules by enabledOnly and global/source/book priority', () async {
      final now = DateTime.utc(2026, 11, 24);
      final rules = [
        ReplaceRule(
          id: 'r-book',
          name: '单书规则',
          pattern: 'ads',
          scopeType: RuleScopeType.book,
          scopeTargetId: 'book-1',
          sortOrder: 0,
          updatedAt: now,
        ),
        ReplaceRule(
          id: 'r-other-book',
          name: '其他书规则',
          pattern: 'other',
          scopeType: RuleScopeType.book,
          scopeTargetId: 'book-2',
          sortOrder: 0,
          updatedAt: now,
        ),
        ReplaceRule(
          id: 'r-source',
          name: '书源规则',
          pattern: 'watermark',
          scopeType: RuleScopeType.source,
          scopeTargetId: 'src-1',
          sortOrder: 1,
          updatedAt: now,
        ),
        ReplaceRule(
          id: 'r-global-2',
          name: '全局规则2',
          pattern: 'b',
          scopeType: RuleScopeType.global,
          sortOrder: 2,
          updatedAt: now,
        ),
        ReplaceRule(
          id: 'r-global-1',
          name: '全局规则1',
          pattern: 'a',
          scopeType: RuleScopeType.global,
          sortOrder: 1,
          updatedAt: now,
        ),
        ReplaceRule(
          id: 'r-disabled',
          name: '禁用全局规则',
          pattern: 'off',
          scopeType: RuleScopeType.global,
          enabled: false,
          sortOrder: 0,
          updatedAt: now,
        ),
      ];

      for (final rule in rules) {
        await sourceRepo.saveReplaceRule(rule);
      }

      expect((await sourceRepo.listReplaceRules()).length, 6);

      final activeForOnlineBook = await sourceRepo.listReplaceRules(
        enabledOnly: true,
        sourceId: 'src-1',
        bookId: 'book-1',
      );
      expect(
        activeForOnlineBook.map((r) => r.id).toList(),
        equals(['r-global-1', 'r-global-2', 'r-source', 'r-book']),
      );

      final activeForLocalBook = await sourceRepo.listReplaceRules(
        enabledOnly: true,
        bookId: 'book-1',
      );
      expect(
        activeForLocalBook.map((r) => r.id).toList(),
        equals(['r-global-1', 'r-global-2', 'r-book']),
      );

      await sourceRepo.deleteReplaceRule('r-disabled');
      expect((await sourceRepo.listReplaceRules()).length, 5);
    });
  });

  test('maps operations after close into DatabaseFailure', () async {
    final isolatedDb = AppDatabase.inMemory();
    final isolatedRepo = DriftBookRepository(isolatedDb);
    await isolatedRepo.listBooks();
    await isolatedDb.close();

    await expectLater(
      isolatedRepo.listBooks,
      throwsA(isA<DatabaseFailure>()),
    );
  });
}
