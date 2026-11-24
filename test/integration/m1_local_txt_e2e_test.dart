import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/app/app.dart';
import 'package:pureread/app/providers.dart';
import 'package:pureread/application/bookshelf/bookshelf_controller.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_session_controller.dart';
import 'package:pureread/application/reader/reader_session_state.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';
import 'package:pureread/infrastructure/database/database.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/infrastructure/storage/storage.dart';
import 'package:pureread/presentation/bookshelf/bookshelf_page.dart';
import 'package:pureread/presentation/reader/reader_page.dart';
import 'package:pureread/presentation/reader/reader_page_turn_view.dart';

class _FakePlatformBridge implements PlatformBridge {
  List<String> filesToPick = const <String>[];
  final List<bool> keepScreenOnCalls = <bool>[];
  final List<bool> volumeKeyPagingCalls = <bool>[];
  final List<bool> immersiveModeCalls = <bool>[];
  int bossKeyHideCalls = 0;

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async {
    return filesToPick;
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    keepScreenOnCalls.add(enabled);
  }

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async {
    volumeKeyPagingCalls.add(enabled);
  }

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents =>
      const Stream<VolumeKeyDirection>.empty();

  @override
  Future<void> setImmersiveMode(bool enabled) async {
    immersiveModeCalls.add(enabled);
  }

  @override
  Future<void> bossKeyHide() async {
    bossKeyHideCalls++;
  }
}

/// Pumps both real event-loop micro-ticks (for background Isolates / disk I/O)
/// and FakeAsync frames/timers until [predicate] returns `true`.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

/// Pumps both real event-loop micro-ticks (for background Isolates / disk I/O)
/// and FakeAsync frames/timers until [predicate] returns `true`.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxIterations = 250,
  String? label,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (predicate()) {
      await _settle(tester);
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  fail('Timed out waiting for async/UI condition${label != null ? ' ($label)' : ''}.');
}

void _assertNoPageLayoutOverflow(ReaderSessionState state) {
  final config = state.paginationConfig;
  expect(config, isNotNull);
  expect(state.currentPages, isNotEmpty);

  var sawJustifiedLine = false;
  for (final page in state.currentPages) {
    for (final line in page.lines) {
      expect(
        line.y + line.height,
        lessThanOrEqualTo(config!.columnHeight + 0.5),
        reason: 'Line vertical extent overflows columnHeight',
      );
      expect(
        line.x + line.width,
        lessThanOrEqualTo(config.columnWidth + 0.5),
        reason: 'Line horizontal extent overflows columnWidth',
      );
      if (line.charXOffsets != null) {
        sawJustifiedLine = true;
      }
    }
  }
  expect(
    sawJustifiedLine,
    isTrue,
    reason: 'Expected IncrementalTextPaginator to populate LayoutLine.charXOffsets',
  );
}

String _buildTestNovelText({
  required String titlePrefix,
  required String watermark,
}) {
  final ch1Paras = List<String>.generate(
    24,
    (i) =>
        '$titlePrefix 第一章第${i + 1}段：山海风起，PureRead 2026 E2E v${i + 1} 混排测试开启。'
        '包含中文标点「，。！？、》」《（）」，验证避头尾禁则与微距排版。',
  ).join('\n');

  final ch2Paras = List<String>.generate(
    24,
    (i) =>
        '$titlePrefix 第二章第${i + 1}段：沧海月明，TestToken-${i + 1} 记录精准偏移量，'
        '断句优雅、排版严谨！',
  ).join('\n');

  return '第1章 初入山海\n'
      '$watermark\n'
      '$ch1Paras\n'
      '第2章 沧海月明\n'
      '$watermark\n'
      '$ch2Paras\n';
}

void main() {
  testWidgets(
    'M1 Full Local TXT E2E: import UTF-8 & GB18030, sanitize, paginate, resize, bookmark, theme, and restart persistence',
    (tester) async {
      const watermark = '【广告水印：盗版站点 www.fake-ad.test 请勿传播】';
      const utf8Title = '山海秘卷_utf8';
      const gbTitle = '星辰古录_gb18030';

      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('pureread_m1_e2e_1_'),
      );
      expect(tempDir, isNotNull);

      AppDatabase? activeDb;
      LocalTxtProvider? activeTxtProvider;
      TxtIsolateWorker? activeWorker;

      addTearDown(() async {
        await activeTxtProvider?.dispose();
        await activeWorker?.dispose();
        await activeDb?.close();
        if (await tempDir!.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dataRoot = Directory(p.join(tempDir!.path, 'data'));
      final cacheRoot = Directory(p.join(tempDir.path, 'cache'));
      final booksDir = Directory(p.join(tempDir.path, 'books'));
      await tester.runAsync(() => booksDir.create(recursive: true));

      final pathResolver = AppPathResolver.fromRoots(
        dataRootDir: dataRoot,
        cacheRootDir: cacheRoot,
      );
      await tester.runAsync(pathResolver.ensureDirectoriesExist);

      final utf8File = File(p.join(booksDir.path, '$utf8Title.txt'));
      final gbFile = File(p.join(booksDir.path, '$gbTitle.txt'));
      await tester.runAsync(() async {
        await utf8File.writeAsBytes(
          utf8.encode(
            _buildTestNovelText(titlePrefix: 'UTF8卷', watermark: watermark),
          ),
        );
        await gbFile.writeAsBytes(
          gbk.encode(
            _buildTestNovelText(titlePrefix: 'GB卷', watermark: watermark),
          ),
        );
      });

      // Session 1 setup
      var db = AppDatabase.forFile(
        pathResolver.databaseFile,
        backupsDirPath: pathResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      activeDb = db;
      var worker = TxtIsolateWorker();
      activeWorker = worker;
      var txtProvider = LocalTxtProvider(worker: worker);
      activeTxtProvider = txtProvider;
      var fontStorage = FontStorageService(pathResolver);
      final platformBridge = _FakePlatformBridge();

      final sourceRepo = DriftSourceRepository(db);
      await tester.runAsync(() async {
        await sourceRepo.saveReplaceRule(
          ReplaceRule(
            id: 'e2e-global-watermark',
            name: '清理测试广告水印',
            pattern: r'【广告水印：.*?】',
            replacement: '',
            isRegex: true,
            scopeType: RuleScopeType.global,
            enabled: true,
            sortOrder: 0,
            updatedAt: DateTime.utc(2026, 11, 24),
          ),
        );
      });

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey<String>('session-1'),
          overrides: buildPureReadOverrides(
            database: db,
            pathResolver: pathResolver,
            localTxtProvider: txtProvider,
            fontStorageService: fontStorage,
            platformBridge: platformBridge,
          ),
          child: const PureReadApp(),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            !ProviderScope.containerOf(
              tester.element(find.byType(PureReadApp)),
              listen: false,
            ).read(bookshelfControllerProvider).isLoading,
        label: 'session1-bookshelf-init',
      );

      final container1 = ProviderScope.containerOf(
        tester.element(find.byType(PureReadApp)),
        listen: false,
      );

      // Import UTF-8 and GB18030 files through BookshelfController.
      unawaited(
        container1
            .read(bookshelfControllerProvider.notifier)
            .importFilePaths(<String>[utf8File.path, gbFile.path]),
      );
      await _pumpUntil(
        tester,
        () =>
            !container1.read(bookshelfControllerProvider).isImporting &&
            container1.read(bookshelfControllerProvider).books.length == 2 &&
            find.text(utf8Title).evaluate().isNotEmpty &&
            find.text(gbTitle).evaluate().isNotEmpty,
        label: 'bookshelf-shows-imported-books',
      );

      expect(find.byType(BookshelfPage), findsOneWidget);
      expect(find.text(utf8Title), findsNWidgets(2));
      expect(find.text(gbTitle), findsNWidgets(2));

      final importedBooks = container1.read(bookshelfControllerProvider).books;
      final utf8Book = importedBooks.firstWhere((b) => b.title == utf8Title);
      final gbBook = importedBooks.firstWhere((b) => b.title == gbTitle);
      expect(utf8Book.fileEncoding, 'UTF-8');
      expect(gbBook.fileEncoding, 'GB18030');
      expect(utf8Book.totalChapters, 2);
      expect(gbBook.totalChapters, 2);

      // Open UTF-8 book in ReaderPage.
      await tester.tap(find.text(utf8Title).first);
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final rState = container1.read(
          readerSessionControllerProvider(utf8Book.id),
        );
        return !rState.isLoading &&
            !rState.isPaginating &&
            rState.currentPages.isNotEmpty &&
            rState.paginationConfig != null;
      }, label: 'open-utf8-reader');

      ReaderSessionState readUtf8State() =>
          container1.read(readerSessionControllerProvider(utf8Book.id));

      final initialReaderState = readUtf8State();
      expect(initialReaderState.columnCount, 1);
      expect(initialReaderState.currentChapterIndex, 0);
      expect(initialReaderState.anchorOffset, 0);
      expect(initialReaderState.currentChapterText, isNot(contains('广告水印')));
      expect(initialReaderState.currentChapterText, isNot(contains('fake-ad')));
      expect(
        initialReaderState.currentChapterText,
        contains('PureRead 2026 E2E v1'),
      );
      for (final slice in initialReaderState.currentPages) {
        for (final line in slice.lines) {
          expect(line.text, isNot(contains('广告水印')));
        }
      }
      _assertNoPageLayoutOverflow(initialReaderState);
      expect(tester.takeException(), isNull);

      // Turn pages forward until we enter Chapter 2 and advance inside it so
      // both chapterIndex (> 0) and charOffset (> 0) are non-zero.
      var turnSafety = 0;
      while (readUtf8State().currentChapterIndex == 0 && turnSafety < 20) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _pumpUntil(tester, () => !readUtf8State().isPaginating);
        turnSafety++;
      }
      expect(readUtf8State().currentChapterIndex, 1);
      expect(readUtf8State().currentChapterText, isNot(contains('广告水印')));
      expect(readUtf8State().currentChapterText, contains('沧海月明'));

      // Advance one more page inside Chapter 2 so charOffset > 0.
      final beforeTurnOffset = readUtf8State().anchorOffset;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _pumpUntil(
        tester,
        () =>
            !readUtf8State().isPaginating &&
            readUtf8State().anchorOffset > beforeTurnOffset,
        label: 'advance-ch2',
      );
      final targetChapterIndex = readUtf8State().currentChapterIndex;
      final targetCharOffset = readUtf8State().anchorOffset;
      expect(targetChapterIndex, 1);
      expect(targetCharOffset, greaterThan(0));

      // Open overlay and save a bookmark at the current anchor.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.text('书签'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'E2E 关键书签');
      await tester.tap(find.text('添加书签'));
      await _pumpUntil(
        tester,
        () => readUtf8State().bookmarks.length == 1,
        label: 'bookmark-saved',
      );
      expect(readUtf8State().bookmarks.first.chapterIndex, targetChapterIndex);
      expect(readUtf8State().bookmarks.first.charOffset, targetCharOffset);
      expect(readUtf8State().bookmarks.first.note, 'E2E 关键书签');

      await tester.tap(find.byIcon(Icons.close).last);
      await _settle(tester);

      // Resize from mobile (400x800 1-col) -> desktop (1280x720 2-col).
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            !readUtf8State().isPaginating &&
            readUtf8State().columnCount == 2 &&
            readUtf8State().paginationConfig?.columnCount == 2,
        label: 'resize-desktop',
      );

      final desktopState = readUtf8State();
      expect(desktopState.columnCount, 2);
      expect(desktopState.currentChapterIndex, targetChapterIndex);
      expect(desktopState.anchorOffset, targetCharOffset);
      _assertNoPageLayoutOverflow(desktopState);
      expect(tester.takeException(), isNull);
      final leftSlice = desktopState.leftPage!;
      final rightSlice = desktopState.rightPage;
      final spreadEndOffset =
          rightSlice?.endCharOffset ?? leftSlice.endCharOffset;
      expect(
        targetCharOffset >= leftSlice.startCharOffset &&
            targetCharOffset < spreadEndOffset,
        isTrue,
        reason: 'Desktop 2-col spread must contain the preserved charOffset',
      );

      // Resize back to mobile (400x800 1-col) -> anchor still preserved.
      tester.view.physicalSize = const Size(400, 800);
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            !readUtf8State().isPaginating &&
            readUtf8State().columnCount == 1 &&
            readUtf8State().paginationConfig?.columnCount == 1,
      );

      final mobileRestoredState = readUtf8State();
      expect(mobileRestoredState.columnCount, 1);
      expect(mobileRestoredState.anchorOffset, targetCharOffset);
      expect(
        mobileRestoredState.leftPage!.containsOffset(targetCharOffset),
        isTrue,
      );
      _assertNoPageLayoutOverflow(mobileRestoredState);
      expect(tester.takeException(), isNull);

      // Open settings sheet and switch theme to slate_night ('静谧暗灰').
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.text('设置'));
      await _settle(tester);
      await tester.tap(find.text('静谧暗灰'));
      await _pumpUntil(
        tester,
        () =>
            readUtf8State().activeTheme.id ==
                DefaultDatabaseSeeds.slateNightId &&
            !readUtf8State().isPaginating,
      );

      await tester.tap(find.byIcon(Icons.close).last);
      await _settle(tester);

      final readerScaffold = tester.widget<Scaffold>(
        find.byType(Scaffold).last,
      );
      expect(readerScaffold.backgroundColor, const Color(0xFF1E2228));

      // Flush progress and simulate app shutdown cleanly.
      await tester.runAsync(
        () => container1
            .read(readerSessionControllerProvider(utf8Book.id).notifier)
            .flushProgress(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await txtProvider.dispose();
        await worker.dispose();
        await db.close();
      });
      activeTxtProvider = null;
      activeWorker = null;
      activeDb = null;

      // Session 2: reopen AppDatabase.forFile from the same pureread.db file.
      db = AppDatabase.forFile(
        pathResolver.databaseFile,
        backupsDirPath: pathResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      activeDb = db;
      worker = TxtIsolateWorker();
      activeWorker = worker;
      txtProvider = LocalTxtProvider(worker: worker);
      activeTxtProvider = txtProvider;
      fontStorage = FontStorageService(pathResolver);

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey<String>('session-2'),
          overrides: buildPureReadOverrides(
            database: db,
            pathResolver: pathResolver,
            localTxtProvider: txtProvider,
            fontStorageService: fontStorage,
            platformBridge: platformBridge,
          ),
          child: const PureReadApp(),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            !ProviderScope.containerOf(
              tester.element(find.byType(PureReadApp)),
              listen: false,
            ).read(bookshelfControllerProvider).isLoading &&
            find.text(utf8Title).evaluate().isNotEmpty &&
            find.text(gbTitle).evaluate().isNotEmpty,
      );

      final container2 = ProviderScope.containerOf(
        tester.element(find.byType(PureReadApp)),
        listen: false,
      );

      // Reopen the UTF-8 book and verify full restart persistence.
      await tester.tap(find.text(utf8Title).first);
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final rState = container2.read(
          readerSessionControllerProvider(utf8Book.id),
        );
        return !rState.isLoading &&
            !rState.isPaginating &&
            rState.currentPages.isNotEmpty;
      });

      final restartedState = container2.read(
        readerSessionControllerProvider(utf8Book.id),
      );
      expect(restartedState.currentChapterIndex, targetChapterIndex);
      expect(restartedState.anchorOffset, targetCharOffset);
      expect(restartedState.activeTheme.id, DefaultDatabaseSeeds.slateNightId);
      expect(restartedState.bookmarks.length, 1);
      expect(restartedState.bookmarks.first.chapterIndex, targetChapterIndex);
      expect(restartedState.bookmarks.first.charOffset, targetCharOffset);
      expect(restartedState.bookmarks.first.note, 'E2E 关键书签');
      expect(restartedState.currentChapterText, isNot(contains('广告水印')));
      expect(tester.takeException(), isNull);

      // Return to bookshelf and open the GB18030 book to verify encoding &
      // ReplaceRule sanitization work end-to-end across restarts too.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.byTooltip('返回书架'));
      await _pumpUntil(
        tester,
        () => find.byType(BookshelfPage).evaluate().isNotEmpty,
      );

      await tester.tap(find.text(gbTitle).first);
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final rState = container2.read(
          readerSessionControllerProvider(gbBook.id),
        );
        return !rState.isLoading &&
            !rState.isPaginating &&
            rState.currentPages.isNotEmpty;
      });

      final gbState = container2.read(
        readerSessionControllerProvider(gbBook.id),
      );
      expect(gbState.currentChapterText, contains('GB卷 第一章第1段'));
      expect(gbState.currentChapterText, isNot(contains('\uFFFD')));
      expect(gbState.currentChapterText, isNot(contains('广告水印')));
      _assertNoPageLayoutOverflow(gbState);
      expect(tester.takeException(), isNull);

      // Unmount widget tree cleanly before addTearDown disposes DB/worker.
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    },
  );

  testWidgets(
    'M1 Missing local TXT resilience: deleted file and missing path yield graceful FileAccessFailure',
    (tester) async {
      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('pureread_m1_missing_'),
      );
      expect(tempDir, isNotNull);

      final dataRoot = Directory(p.join(tempDir!.path, 'data'));
      final cacheRoot = Directory(p.join(tempDir.path, 'cache'));
      final pathResolver = AppPathResolver.fromRoots(
        dataRootDir: dataRoot,
        cacheRootDir: cacheRoot,
      );
      await tester.runAsync(pathResolver.ensureDirectoriesExist);

      final db = AppDatabase.forFile(
        pathResolver.databaseFile,
        backupsDirPath: pathResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      final worker = TxtIsolateWorker();
      final txtProvider = LocalTxtProvider(worker: worker);
      final fontStorage = FontStorageService(pathResolver);
      final platformBridge = _FakePlatformBridge();

      addTearDown(() async {
        await txtProvider.dispose();
        await worker.dispose();
        await db.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final txtFile = File(p.join(tempDir.path, '消失的书.txt'));
      await tester.runAsync(
        () => txtFile.writeAsBytes(
          utf8.encode('第1章 缘起\n这是一段会被删除的本地书籍测试文本。\n'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildPureReadOverrides(
            database: db,
            pathResolver: pathResolver,
            localTxtProvider: txtProvider,
            fontStorageService: fontStorage,
            platformBridge: platformBridge,
          ),
          child: const PureReadApp(),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            !ProviderScope.containerOf(
              tester.element(find.byType(PureReadApp)),
              listen: false,
            ).read(bookshelfControllerProvider).isLoading,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PureReadApp)),
        listen: false,
      );

      // Verify empty localFilePath validation throws FileAccessFailure.
      final now = DateTime.utc(2026, 11, 24);
      await expectLater(
        () => container.read(localTxtChapterReaderProvider)(
          Book(
            id: 'no-path',
            providerType: ProviderType.localTxt,
            title: '无路径书籍',
            createdAt: now,
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'no-path',
            chapterIndex: 0,
            title: '第1章',
            updatedAt: now,
          ),
        ),
        throwsA(isA<FileAccessFailure>()),
      );

      unawaited(
        container
            .read(bookshelfControllerProvider.notifier)
            .importFilePaths(<String>[txtFile.path]),
      );
      await _pumpUntil(
        tester,
        () =>
            !container.read(bookshelfControllerProvider).isImporting &&
            container.read(bookshelfControllerProvider).books.length == 1,
        label: 'missing-test-import',
      );
      final importedBook = container.read(bookshelfControllerProvider).books.first;

      // Delete the TXT file from disk before opening in ReaderPage.
      await tester.runAsync(txtFile.delete);

      await tester.tap(find.text('消失的书').first);
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final rState = container.read(
          readerSessionControllerProvider(importedBook.id),
        );
        return !rState.isLoading && !rState.isPaginating;
      });

      final readerState = container.read(
        readerSessionControllerProvider(importedBook.id),
      );
      expect(readerState.errorMessage, isNotNull);
      expect(readerState.errorMessage, contains('TXT file does not exist'));
      expect(find.textContaining('TXT file does not exist'), findsOneWidget);
      expect(find.text('返回书架'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Navigating back from the error view returns cleanly to BookshelfPage.
      await tester.tap(find.text('返回书架'));
      await _pumpUntil(
        tester,
        () => find.byType(BookshelfPage).evaluate().isNotEmpty,
      );
      expect(find.byType(BookshelfPage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    },
  );

  test(
    'M1 Default seeds & backup hygiene on fresh file-backed DB and idempotent PureReadRuntime.dispose',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pureread_m1_seeds_',
      );
      final resolver = AppPathResolver.fromRoots(
        dataRootDir: Directory(p.join(tempDir.path, 'data')),
        cacheRootDir: Directory(p.join(tempDir.path, 'cache')),
      );
      await resolver.ensureDirectoriesExist();

      final db = AppDatabase.forFile(
        resolver.databaseFile,
        backupsDirPath: resolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      final worker = TxtIsolateWorker();
      final txtProvider = LocalTxtProvider(worker: worker);
      final fontStorage = FontStorageService(resolver);
      final runtime = PureReadRuntime(
        pathResolver: resolver,
        database: db,
        txtIsolateWorker: worker,
        localTxtProvider: txtProvider,
        fontStorageService: fontStorage,
      );

      addTearDown(() async {
        await runtime.dispose();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final bookRepo = DriftBookRepository(db);
      final themeRepo = DriftThemeRepository(db);

      final groups = await bookRepo.listGroups();
      expect(groups.map((g) => g.id), contains(DefaultDatabaseSeeds.defaultGroupId));
      expect(
        groups.firstWhere((g) => g.id == DefaultDatabaseSeeds.defaultGroupId).name,
        DefaultDatabaseSeeds.defaultGroupName,
      );

      final themes = await themeRepo.listThemes();
      expect(themes.length, 4);
      final themeById = <String, ReaderTheme>{
        for (final theme in themes) theme.id: theme,
      };
      expect(
        themeById.keys,
        containsAll(<String>[
          DefaultDatabaseSeeds.eyeCareIvoryId,
          DefaultDatabaseSeeds.parchmentWarmId,
          DefaultDatabaseSeeds.slateNightId,
          DefaultDatabaseSeeds.oledPureBlackId,
        ]),
      );
      expect(themeById[DefaultDatabaseSeeds.eyeCareIvoryId]!.isBuiltin, isTrue);
      expect(themeById[DefaultDatabaseSeeds.eyeCareIvoryId]!.isDark, isFalse);
      expect(themeById[DefaultDatabaseSeeds.parchmentWarmId]!.isBuiltin, isTrue);
      expect(themeById[DefaultDatabaseSeeds.parchmentWarmId]!.isDark, isFalse);
      expect(themeById[DefaultDatabaseSeeds.slateNightId]!.isBuiltin, isTrue);
      expect(themeById[DefaultDatabaseSeeds.slateNightId]!.isDark, isTrue);
      expect(themeById[DefaultDatabaseSeeds.oledPureBlackId]!.isBuiltin, isTrue);
      expect(themeById[DefaultDatabaseSeeds.oledPureBlackId]!.isDark, isTrue);

      // Fresh schema v1 startup must not clutter db/backups/ with spurious backups.
      expect(db.backupGuard, isNotNull);
      expect(db.backupGuard!.backupsDirPath, resolver.dbBackupsDir.path);
      expect(db.backupGuard!.maxBackups, 3);
      expect(await db.backupGuard!.listBackups(), isEmpty);
      expect(await resolver.dbBackupsDir.list().toList(), isEmpty);

      final journalRow = await db.customSelect('PRAGMA journal_mode;').getSingle();
      expect(journalRow.read<String>('journal_mode').toLowerCase(), 'wal');

      // Runtime disposal is idempotent across concurrent/repeated calls.
      await Future.wait<void>(<Future<void>>[
        runtime.dispose(),
        runtime.dispose(),
      ]);
      expect(runtime.isDisposed, isTrue);
      expect(worker.isDisposed, isTrue);
    },
  );
}
