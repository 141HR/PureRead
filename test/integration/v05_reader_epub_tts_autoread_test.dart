import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/app/providers.dart';
import 'package:pureread/application/reader/auto_read_controller.dart';
import 'package:pureread/application/reader/auto_read_state.dart';
import 'package:pureread/application/reader/epub_image_cache.dart';
import 'package:pureread/application/reader/in_book_search_service.dart';
import 'package:pureread/application/reader/reader_session_controller.dart';
import 'package:pureread/application/reader/tts_controller.dart';
import 'package:pureread/application/reader/tts_state.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/inline_image_marker.dart';
import 'package:pureread/engine/source_engine/local_epub/local_epub.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/database/database.dart';
import 'package:pureread/infrastructure/database/drift_backup_repository.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/infrastructure/storage/chapter_cache_store.dart';
import 'package:pureread/infrastructure/storage/storage.dart';
import 'package:pureread/infrastructure/tts/tts.dart';
import 'package:pureread/presentation/reader/epub_image_viewer_dialog.dart';
import 'package:pureread/presentation/reader/reader_auto_read_bar.dart';
import 'package:pureread/presentation/reader/reader_auto_read_overlay.dart';
import 'package:pureread/presentation/reader/reader_page.dart';
import 'package:pureread/presentation/reader/reader_page_painter.dart';
import 'package:pureread/presentation/reader/reader_page_turn_view.dart';
import 'package:pureread/presentation/reader/reader_tts_bar.dart';
import 'package:pureread/presentation/reader/reader_tts_settings_sheet.dart';

class _TestPlatformBridge implements PlatformBridge {
  final List<bool> keepScreenOnCalls = <bool>[];
  final List<bool> immersiveCalls = <bool>[];

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async => const <String>[];

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    keepScreenOnCalls.add(enabled);
  }

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async {}

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents =>
      const Stream<VolumeKeyDirection>.empty();

  @override
  Future<void> setImmersiveMode(bool enabled) async {
    immersiveCalls.add(enabled);
  }

  @override
  Future<void> bossKeyHide() async {}
}

class _FakeTtsEngine implements TtsEngine {
  final StreamController<TtsEvent> _events =
      StreamController<TtsEvent>.broadcast();

  final List<String> spokenTexts = <String>[];
  final List<String> spokenUtteranceIds = <String>[];
  int stopCalls = 0;
  int pauseNotificationCalls = 0;
  bool isDisposed = false;

  void emitCompleteForCurrent() {
    if (spokenUtteranceIds.isEmpty) return;
    emit(TtsCompleteEvent(utteranceId: spokenUtteranceIds.last));
  }

  void emit(TtsEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  @override
  Future<TtsInitResult> initialize() async =>
      const TtsInitResult(available: true, engine: 'fake_tts');

  @override
  Future<List<TtsEngineInfo>> getEngines() async => const <TtsEngineInfo>[
    TtsEngineInfo(id: 'fake_tts', label: '测试引擎', isDefault: true),
  ];

  @override
  Future<bool> setEngine(String engineId) async => engineId == 'fake_tts';

  @override
  Future<List<TtsVoiceInfo>> getVoices() async => const <TtsVoiceInfo>[
    TtsVoiceInfo(id: 'zh_cn_1', name: '晓晓', locale: 'zh-CN'),
    TtsVoiceInfo(id: 'en_us_1', name: 'Aria', locale: 'en-US'),
  ];

  @override
  Future<bool> setVoice(String voiceId) async => true;

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<bool> speak({
    required String text,
    required String utteranceId,
    String? bookTitle,
    String? chapterTitle,
  }) async {
    spokenTexts.add(text);
    spokenUtteranceIds.add(utteranceId);
    emit(TtsStartEvent(utteranceId: utteranceId));
    return true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> pauseNotification({
    String? bookTitle,
    String? chapterTitle,
  }) async {
    pauseNotificationCalls++;
  }

  @override
  Future<void> updateMetadata({
    String? bookTitle,
    String? chapterTitle,
    required bool isPlaying,
  }) async {}

  @override
  Future<void> shutdown() async {}

  @override
  Stream<TtsEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _events.close();
  }
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : (crc >>> 1);
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _pngChunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final lengthBytes = <int>[
    (data.length >>> 24) & 0xFF,
    (data.length >>> 16) & 0xFF,
    (data.length >>> 8) & 0xFF,
    data.length & 0xFF,
  ];
  final crc = _crc32(<int>[...typeBytes, ...data]);
  final crcBytes = <int>[
    (crc >>> 24) & 0xFF,
    (crc >>> 16) & 0xFF,
    (crc >>> 8) & 0xFF,
    crc & 0xFF,
  ];
  return <int>[...lengthBytes, ...typeBytes, ...data, ...crcBytes];
}

Uint8List _buildValidPng(int width, int height, int r, int g, int b) {
  final rawScanlines = BytesBuilder(copy: false);
  final row = Uint8List(1 + width * 4);
  row[0] = 0;
  for (var x = 0; x < width; x++) {
    row[1 + x * 4] = r;
    row[1 + x * 4 + 1] = g;
    row[1 + x * 4 + 2] = b;
    row[1 + x * 4 + 3] = 0xFF;
  }
  for (var y = 0; y < height; y++) {
    rawScanlines.add(row);
  }
  final ihdr = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final compressed = const ZLibEncoder().encode(rawScanlines.toBytes());
  return Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ..._pngChunk('IHDR', ihdr.buffer.asUint8List()),
    ..._pngChunk('IDAT', compressed),
    ..._pngChunk('IEND', const <int>[]),
  ]);
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _buildEpubWithInlineImageBytes({required Uint8List illustrationPng}) {
  final longTailParagraphs = List<String>.generate(
    28,
    (i) =>
        '<p>第${i + 1}段正文：春风吹过青石古道，远处峰峦叠翠，行人驻足观望山间云岚。'
        '这段文字用于构建跨越多页的阅读内容以验证翻页、朗读高亮与分离浏览。</p>',
  ).join('\n');

  final ch2Paragraphs = List<String>.generate(
    10,
    (i) => '<p>第二章第${i + 1}句：夜色低垂，孤舟灯火微明，江水拍岸作响。</p>',
  ).join('\n');

  final archive = Archive();
  final entries = <String, List<int>>{
    'mimetype': _utf8('application/epub+zip'),
    'META-INF/container.xml': _utf8('''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
    'OEBPS/content.opf': _utf8('''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>山川插画纪</dc:title>
    <dc:creator>测试作者</dc:creator>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="scene" href="images/scene.png" media-type="image/png"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>
'''),
    'OEBPS/toc.ncx': _utf8('''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>第一章 云岚初见</text></navLabel>
      <content src="text/ch1.xhtml"/>
    </navPoint>
    <navPoint id="np2" playOrder="2">
      <navLabel><text>第二章 江夜孤舟</text></navLabel>
      <content src="text/ch2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
'''),
    'OEBPS/images/scene.png': illustrationPng,
    'OEBPS/text/ch1.xhtml': _utf8('''
<html><body>
  <h1>第一章 云岚初见</h1>
  <p>序言引子：清晨山谷初醒，薄雾漫过林梢。</p>
  <img src="../images/scene.png" alt="山川图卷"/>
  $longTailParagraphs
</body></html>
'''),
    'OEBPS/text/ch2.xhtml': _utf8('''
<html><body>
  <h1>第二章 江夜孤舟</h1>
  $ch2Paragraphs
</body></html>
'''),
  };

  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 40),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 4),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxIterations = 300,
  String? label,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (predicate()) {
      await tester.pump();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail(
    'Timed out waiting for condition${label != null ? ' ($label)' : ''}.',
  );
}

Future<T> _runWhilePumping<T>(
  WidgetTester tester,
  Future<T> future, {
  String? label,
}) async {
  var done = false;
  late T result;
  Object? err;
  StackTrace? st;

  unawaited(
    future.then<void>(
      (v) {
        result = v;
        done = true;
      },
      onError: (Object error, StackTrace stackTrace) {
        err = error;
        st = stackTrace;
        done = true;
      },
    ),
  );

  await _pumpUntil(tester, () => done, label: label);
  if (err != null) {
    Error.throwWithStackTrace(err!, st!);
  }
  return result;
}

class _V05Harness {
  _V05Harness({
    required this.tempDir,
    required this.runtime,
    required this.platformBridge,
    required this.ttsEngine,
    required this.book,
    required this.chapters,
    required this.overrides,
  });

  final Directory tempDir;
  final PureReadRuntime runtime;
  final _TestPlatformBridge platformBridge;
  final _FakeTtsEngine ttsEngine;
  final Book book;
  final List<ChapterMeta> chapters;
  final List<Override> overrides;

  Future<void> dispose() async {
    PaintingBinding.instance.imageCache.clear();
    await ttsEngine.dispose();
    await runtime.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

Future<_V05Harness> _createHarness(WidgetTester tester) async {
  final tempDir = await tester.runAsync(
    () => Directory.systemTemp.createTemp('pureread_v05_e2e_'),
  );
  expect(tempDir, isNotNull);

  final dataRoot = Directory(p.join(tempDir!.path, 'data'));
  final cacheRoot = Directory(p.join(tempDir.path, 'cache'));
  final booksDir = Directory(p.join(tempDir.path, 'books'));
  await tester.runAsync(() => booksDir.create(recursive: true));

  final pathResolver = AppPathResolver.fromRoots(
    dataRootDir: dataRoot,
    cacheRootDir: cacheRoot,
  );
  await tester.runAsync(pathResolver.ensureDirectoriesExist);

  final epubFile = File(p.join(booksDir.path, 'illustrated_story.epub'));
  await tester.runAsync(() async {
    await epubFile.writeAsBytes(
      _buildEpubWithInlineImageBytes(
        illustrationPng: _buildValidPng(240, 160, 48, 128, 92),
      ),
    );
  });

  final db = AppDatabase.forFile(
    pathResolver.databaseFile,
    backupsDirPath: pathResolver.dbBackupsDir.path,
    useBackgroundIsolate: false,
  );
  final worker = TxtIsolateWorker();
  final txtProvider = LocalTxtProvider(worker: worker);
  final epubProvider = LocalEpubProvider();
  final fontStorage = FontStorageService(pathResolver);
  final httpClient = SourceHttpClient();
  final cacheStore = ChapterCacheStore(pathResolver);
  final providerFactory = BookProviderFactory(httpClient: httpClient);
  const importExportService = SourceImportExportService();
  final backupRepo = DriftBackupRepository(db, pathResolver);

  final runtime = PureReadRuntime(
    pathResolver: pathResolver,
    database: db,
    txtIsolateWorker: worker,
    localTxtProvider: txtProvider,
    localEpubProvider: epubProvider,
    fontStorageService: fontStorage,
    sourceHttpClient: httpClient,
    chapterCacheStore: cacheStore,
    bookProviderFactory: providerFactory,
    sourceImportExportService: importExportService,
    backupRepository: backupRepo,
  );

  final imported = await tester.runAsync(
    () => epubProvider.importEpubFile(
      epubFile.path,
      coverSaveDir: pathResolver.coversDir.path,
    ),
  );
  expect(imported, isNotNull);

  final bookRepo = DriftBookRepository(db);
  await tester.runAsync(() async {
    await bookRepo.saveBook(imported!.book);
    await bookRepo.replaceChapters(imported.book.id, imported.chapters);
  });

  final platformBridge = _TestPlatformBridge();
  final ttsEngine = _FakeTtsEngine();
  final overrides = buildPureReadOverrides(
    database: runtime.database,
    pathResolver: runtime.pathResolver,
    localTxtProvider: runtime.localTxtProvider,
    localEpubProvider: runtime.localEpubProvider,
    fontStorageService: runtime.fontStorageService,
    platformBridge: platformBridge,
    ttsEngine: ttsEngine,
    sourceHttpClient: runtime.sourceHttpClient,
    chapterCacheStore: runtime.chapterCacheStore,
    bookProviderFactory: runtime.bookProviderFactory,
    sourceImportExportService: runtime.sourceImportExportService,
    backupRepository: runtime.backupRepository,
  );

  return _V05Harness(
    tempDir: tempDir,
    runtime: runtime,
    platformBridge: platformBridge,
    ttsEngine: ttsEngine,
    book: imported!.book,
    chapters: imported.chapters,
    overrides: overrides,
  );
}

void main() {
  testWidgets(
    'v0.5.0 E2E 1: EPUB inline image extraction, search/bookmark stripping, painter/hitTestImage, and EpubImageViewerDialog zoom & close',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 820);
      addTearDown(tester.view.reset);

      final harness = await _createHarness(tester);
      addTearDown(harness.dispose);

      final container = ProviderContainer(overrides: harness.overrides);
      addTearDown(container.dispose);

      // Verify InBookSearchService skips InlineImageMarker lines & cleans snippets.
      final rawCh0 = await _runWhilePumping(
        tester,
        harness.runtime.localEpubProvider.readChapterText(
          filePath: harness.book.localFilePath!,
          chapter: harness.chapters.first,
          chapters: harness.chapters,
        ),
        label: 'read-ch0-raw',
      );
      expect(rawCh0, contains(InlineImageMarker.prefix));

      final markerQueryResult = InBookSearchService.searchInText(
        text: rawCh0,
        query: 'primg',
        chapterIndex: 0,
        chapterTitle: '第一章 云岚初见',
      );
      expect(markerQueryResult.matches, isEmpty);

      final filenameQueryResult = InBookSearchService.searchInText(
        text: rawCh0,
        query: 'scene.png',
        chapterIndex: 0,
        chapterTitle: '第一章 云岚初见',
      );
      expect(filenameQueryResult.matches, isEmpty);

      final proseMatchResult = InBookSearchService.searchInText(
        text: rawCh0,
        query: '春风吹过',
        chapterIndex: 0,
        chapterTitle: '第一章 云岚初见',
        contextBefore: 48,
        contextAfter: 24,
      );
      expect(proseMatchResult.matches, isNotEmpty);
      expect(
        proseMatchResult.matches.first.snippet,
        isNot(contains(InlineImageMarker.prefix)),
      );
      expect(
        proseMatchResult.matches.first.snippet.substring(
          proseMatchResult.matches.first.matchStartInSnippet,
          proseMatchResult.matches.first.matchStartInSnippet + 4,
        ),
        '春风吹过',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ReaderPage(bookId: harness.book.id)),
        ),
      );

      await _pumpUntil(tester, () {
        final s = container.read(readerSessionControllerProvider(harness.book.id));
        return !s.isLoading &&
            !s.isPaginating &&
            s.currentPages.isNotEmpty &&
            s.paginationConfig != null;
      }, label: 'reader-image-ready');

      final sessionState = container.read(
        readerSessionControllerProvider(harness.book.id),
      );
      final imageCache = container.read(epubImageCacheProvider);
      await _pumpUntil(
        tester,
        () =>
            imageCache.getCached(harness.book.id, 'OEBPS/images/scene.png') !=
            null,
        label: 'epub-image-decoded',
      );
      await tester.pump();

      final firstSlice = sessionState.leftPage!;
      final config = sessionState.paginationConfig!;
      final turnViewBox = tester.renderObject<RenderBox>(
        find.byType(ReaderPageTurnView),
      );
      final turnViewSize = turnViewBox.size;

      // Verify ReaderPagePainter paints the decoded image cleanly.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      ReaderPagePainter(
        config: config,
        leftPage: firstSlice,
        backgroundColor: const Color(0xFFF7F4EC),
        textColor: const Color(0xFF2C2A26),
        secondaryTextColor: const Color(0xFF78736A),
        epubImageCache: imageCache,
        book: harness.book,
      ).paint(canvas, turnViewSize);
      final picture = recorder.endRecording();
      expect(picture.approximateBytesUsed, greaterThan(0));
      picture.dispose();

      // Verify hitTestImage hits the illustration and misses top-left corner.
      final imageLine = firstSlice.lines.firstWhere(
        (l) => InlineImageMarker.isImageLine(l.text),
      );
      final originX = (turnViewSize.width - config.columnWidth) / 2;
      final expectedRect = ReaderPagePainter.computeImageRect(
        sliceOrigin: Offset(originX < 0 ? 0 : originX, 0),
        line: imageLine,
      );
      final hit = ReaderPagePainter.hitTestImage(
        localPosition: expectedRect.center,
        size: turnViewSize,
        config: config,
        leftPage: firstSlice,
        rightPage: null,
      );
      expect(hit, isNotNull);
      expect(hit!.ref.archivePath, 'OEBPS/images/scene.png');
      expect(hit.ref.width, 240);
      expect(hit.ref.height, 160);
      expect(hit.ref.alt, '山川图卷');
      expect(
        ReaderPagePainter.hitTestImage(
          localPosition: const Offset(2, 2),
          size: turnViewSize,
          config: config,
          leftPage: firstSlice,
          rightPage: null,
        ),
        isNull,
      );

      // Verify bookmark excerpt strips InlineImageMarker cleanly.
      await _runWhilePumping(
        tester,
        container
            .read(readerSessionControllerProvider(harness.book.id).notifier)
            .addBookmark(),
        label: 'add-bookmark-on-image-page',
      );
      final bookmarks = container
          .read(readerSessionControllerProvider(harness.book.id))
          .bookmarks;
      expect(bookmarks, hasLength(1));
      expect(bookmarks.first.excerpt, isNot(contains(InlineImageMarker.prefix)));

      // Tap the inline illustration inside ReaderPageTurnView -> opens viewer dialog.
      final globalHitPoint = turnViewBox.localToGlobal(expectedRect.center);
      await tester.tapAt(globalHitPoint);
      await _settle(tester);

      expect(find.byType(EpubImageViewerDialog), findsOneWidget);
      expect(find.text('山川图卷'), findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, 1.0);
      expect(viewer.maxScale, 5.0);
      expect(find.byType(RawImage), findsOneWidget);

      // Double-tap toggles zoom in and back out.
      final viewerCenter = tester.getCenter(find.byType(InteractiveViewer));
      await tester.tapAt(viewerCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(viewerCenter);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1.5),
      );

      await tester.tapAt(viewerCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(viewerCenter);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        closeTo(1.0, 0.01),
      );

      // Escape dismisses the modal viewer cleanly.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byType(EpubImageViewerDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'v0.5.0 E2E 2: Auto-Read curtain & timedTurn, 360dp narrow overlay without overflow, pause/resume, keepScreenOn, and TTS mutual exclusion',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);

      final harness = await _createHarness(tester);
      addTearDown(harness.dispose);

      final container = ProviderContainer(overrides: harness.overrides);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ReaderPage(bookId: harness.book.id)),
        ),
      );

      await _pumpUntil(tester, () {
        final s = container.read(readerSessionControllerProvider(harness.book.id));
        return !s.isLoading && !s.isPaginating && s.currentPages.isNotEmpty;
      }, label: 'autoread-init');

      // Open overlay on 360dp phone and verify all 6 action buttons fit with zero overflow.
      final turnRect = tester.getRect(find.byType(ReaderPageTurnView));
      await tester.tapAt(Offset(turnRect.center.dx, turnRect.bottom - 16));
      await _settle(tester);

      final isDark = container
          .read(readerSessionControllerProvider(harness.book.id))
          .activeTheme
          .isDark;
      expect(find.text('目录'), findsOneWidget);
      expect(find.text(isDark ? '日间' : '夜间'), findsOneWidget);
      expect(find.text('听书'), findsOneWidget);
      expect(find.text('自动'), findsOneWidget);
      expect(find.text('书签'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Start Auto-Read in curtain mode via bottom overlay button.
      await tester.tap(find.text('自动'));
      await _pumpUntil(
        tester,
        () => container.read(autoReadControllerProvider).isRunning,
        label: 'autoread-started',
      );
      await tester.pump();

      expect(find.byType(ReaderAutoReadOverlay), findsOneWidget);
      expect(find.byType(ReaderAutoReadBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('auto_read_curtain_scan_line')),
        findsOneWidget,
      );
      expect(harness.platformBridge.keepScreenOnCalls.last, isTrue);

      // Speed up curtain to 6s so full sweep completes promptly.
      await _runWhilePumping(
        tester,
        container.read(autoReadControllerProvider.notifier).setCurtainSeconds(6),
        label: 'set-curtain-6s',
      );
      final startPageIdx = container
          .read(readerSessionControllerProvider(harness.book.id))
          .currentPageIndex;

      await tester.pump(const Duration(seconds: 6, milliseconds: 80));
      await _pumpUntil(
        tester,
        () =>
            container
                .read(readerSessionControllerProvider(harness.book.id))
                .currentPageIndex >
            startPageIdx,
        label: 'curtain-advanced-page',
      );

      // Switch to timedTurn mode from ReaderAutoReadBar.
      await tester.tap(find.text('定时翻页'));
      await _pumpUntil(
        tester,
        () =>
            container.read(autoReadControllerProvider).mode ==
            AutoReadMode.timedTurn,
        label: 'switched-to-timedTurn',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('auto_read_timed_progress')),
        findsOneWidget,
      );

      // Space pauses Auto-Read and restores keepScreenOn = false.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(container.read(autoReadControllerProvider).isPaused, isTrue);
      expect(harness.platformBridge.keepScreenOnCalls.last, isFalse);

      // Space resumes Auto-Read and enables keepScreenOn = true.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(container.read(autoReadControllerProvider).isRunning, isTrue);
      expect(harness.platformBridge.keepScreenOnCalls.last, isTrue);

      // Advance timedTurn interval -> turns another page cleanly.
      await _runWhilePumping(
        tester,
        container.read(autoReadControllerProvider.notifier).setTurnSeconds(3),
        label: 'set-turn-3s',
      );
      final pageBeforeTimed = container
          .read(readerSessionControllerProvider(harness.book.id))
          .currentPageIndex;
      await tester.pump(const Duration(seconds: 3, milliseconds: 80));
      await _pumpUntil(
        tester,
        () =>
            container
                .read(readerSessionControllerProvider(harness.book.id))
                .currentPageIndex >
            pageBeforeTimed,
        label: 'timedTurn-advanced-page',
      );

      // Mutual exclusion: starting TTS stops Auto-Read and restores keepScreenOn.
      final sessionCtrl = container.read(
        readerSessionControllerProvider(harness.book.id).notifier,
      );
      final sessionState = container.read(
        readerSessionControllerProvider(harness.book.id),
      );
      await _runWhilePumping(
        tester,
        container.read(ttsControllerProvider.notifier).start(
          bookId: harness.book.id,
          bookTitle: harness.book.title,
          host: TtsReaderHost(
            loadChapterText: sessionCtrl.readChapterTextForTts,
            navigateToPosition: sessionCtrl.jumpToTtsAnchor,
            getChapterTitle: (i) => harness.chapters[i].title,
            getChapterCount: () => harness.chapters.length,
          ),
          chapterIndex: sessionState.currentChapterIndex,
          chapterText: sessionState.currentChapterText,
        ),
        label: 'tts-stops-autoread',
      );
      await tester.pump();
      expect(container.read(autoReadControllerProvider).isActive, isFalse);
      expect(container.read(ttsControllerProvider).isPlaying, isTrue);
      expect(harness.platformBridge.keepScreenOnCalls.last, isFalse);

      // Mutual exclusion reverse: starting Auto-Read stops active TTS.
      container.read(autoReadControllerProvider.notifier).start();
      await _pumpUntil(
        tester,
        () => container.read(ttsControllerProvider).status == TtsStatus.idle,
        label: 'autoread-stops-tts',
      );
      expect(container.read(autoReadControllerProvider).isRunning, isTrue);
      expect(harness.ttsEngine.stopCalls, greaterThan(0));

      // Tap 停止 on ReaderAutoReadBar and flush pending debounce timer cleanly.
      await tester.pump();
      await tester.tap(find.text('停止'));
      await tester.pump();
      expect(container.read(autoReadControllerProvider).isActive, isFalse);
      expect(harness.platformBridge.keepScreenOnCalls.last, isFalse);
      await _runWhilePumping(
        tester,
        sessionCtrl.flushProgress(),
        label: 'flush-progress',
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'v0.5.0 E2E 3: TTS playback, sentence highlight, detached browsing & jump-back, cross-chapter continuation, sleep timer, and lifecycle',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 820);
      addTearDown(tester.view.reset);

      final harness = await _createHarness(tester);
      addTearDown(harness.dispose);

      final container = ProviderContainer(overrides: harness.overrides);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReaderPage(bookId: harness.book.id),
                        ),
                      );
                    },
                    child: const Text('打开阅读'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开阅读'));
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final s = container.read(readerSessionControllerProvider(harness.book.id));
        return !s.isLoading && !s.isPaginating && s.currentPages.isNotEmpty;
      }, label: 'open-reader-route');
      await _settle(tester);

      // Tap center to open bottom overlay and start TTS via 「听书」.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.text('听书'));
      await _pumpUntil(
        tester,
        () =>
            container.read(ttsControllerProvider).isPlaying &&
            harness.ttsEngine.spokenTexts.isNotEmpty,
        label: 'tts-started',
      );
      await _settle(tester);

      expect(find.byType(ReaderTtsBar), findsOneWidget);
      final ttsState = container.read(ttsControllerProvider);
      expect(ttsState.speakingChapterIndex, 0);
      expect(ttsState.activeHighlightRange, isNotNull);

      // Verify active sentence highlight is forwarded to ReaderPageTurnView & painted by ReaderPagePainter.
      final turnView = tester.widget<ReaderPageTurnView>(
        find.byType(ReaderPageTurnView),
      );
      final hlRange = ttsState.activeHighlightRange!;
      expect(turnView.ttsHighlightChapterIndex, 0);
      expect(turnView.ttsHighlightStartOffset, hlRange.$1);
      expect(turnView.ttsHighlightEndOffset, hlRange.$2);

      final sessionState = container.read(
        readerSessionControllerProvider(harness.book.id),
      );
      final hlRecorder = ui.PictureRecorder();
      ReaderPagePainter(
        config: sessionState.paginationConfig!,
        leftPage: sessionState.leftPage,
        backgroundColor: const Color(0xFFF7F4EC),
        textColor: const Color(0xFF2C2A26),
        secondaryTextColor: const Color(0xFF78736A),
        ttsHighlightChapterIndex: 0,
        ttsHighlightStartOffset: hlRange.$1,
        ttsHighlightEndOffset: hlRange.$2,
        ttsHighlightColor: const Color(0x404A6B53),
      ).paint(hlRecorder.letCanvas, const Size(420, 740));
      // Helper call below cleans up recorder cleanly.
      hlRecorder.endRecording().dispose();

      // User navigates away manually -> detached browsing triggers 「回到朗读处」 without stopping speech.
      await _runWhilePumping(
        tester,
        container
            .read(readerSessionControllerProvider(harness.book.id).notifier)
            .jumpToChapter(1, pushUndo: false),
        label: 'user-flips-to-ch1-detached',
      );
      await _pumpUntil(
        tester,
        () => container.read(ttsControllerProvider).isDetached,
        label: 'tts-detached',
      );
      await tester.pump();
      expect(find.text('回到朗读处'), findsOneWidget);
      expect(container.read(ttsControllerProvider).isPlaying, isTrue);

      // Tapping 「回到朗读处」 jumps back to chapter 0 without polluting jumpUndoStack.
      await tester.tap(find.text('回到朗读处'));
      await _pumpUntil(
        tester,
        () =>
            !container.read(ttsControllerProvider).isDetached &&
            container
                    .read(readerSessionControllerProvider(harness.book.id))
                    .currentChapterIndex ==
                0,
        label: 'tts-jumped-back',
      );
      await _settle(tester);
      expect(
        container
            .read(readerSessionControllerProvider(harness.book.id))
            .jumpUndoStack,
        isEmpty,
      );

      // Complete all remaining utterances in Chapter 0 -> continues seamlessly into Chapter 1.
      final ch0UtteranceCount = container
          .read(ttsControllerProvider)
          .utterances
          .length;
      for (var i = 0; i < ch0UtteranceCount; i++) {
        harness.ttsEngine.emitCompleteForCurrent();
        await _pumpUntil(
          tester,
          () {
            final s = container.read(ttsControllerProvider);
            return s.speakingChapterIndex == 1 ||
                s.currentUtteranceIndex == i + 1;
          },
          label: 'advance-ch0-utterance-$i',
        );
      }
      await _pumpUntil(
        tester,
        () =>
            container.read(ttsControllerProvider).speakingChapterIndex == 1 &&
            container.read(ttsControllerProvider).isPlaying,
        label: 'crossed-to-ch1',
      );
      expect(
        container
            .read(readerSessionControllerProvider(harness.book.id))
            .currentChapterIndex,
        1,
      );

      // Open TTS settings sheet and enable 「读完本章」 sleep timer.
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await _settle(tester);
      expect(find.byType(ReaderTtsSettingsSheet), findsOneWidget);
      await tester.tap(find.text('读完本章'));
      await _settle(tester);
      expect(
        container.read(ttsControllerProvider).sleepTimerMode,
        TtsSleepTimerMode.endOfChapter,
      );
      await tester.tap(find.byTooltip('关闭').last);
      await _settle(tester);

      // Finish remaining Chapter 1 utterances -> sleep timer stops TTS cleanly at chapter end.
      final ch1Total = container.read(ttsControllerProvider).utterances.length;
      final ch1Current = container
          .read(ttsControllerProvider)
          .currentUtteranceIndex;
      for (var i = ch1Current; i < ch1Total; i++) {
        harness.ttsEngine.emitCompleteForCurrent();
        await tester.pump(const Duration(milliseconds: 20));
      }
      await _pumpUntil(
        tester,
        () => container.read(ttsControllerProvider).status == TtsStatus.idle,
        label: 'sleep-timer-end-of-chapter-stopped',
      );

      // Re-start TTS, send app to background -> TTS keeps playing for Android notification playback!
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.text('听书'));
      await _pumpUntil(
        tester,
        () => container.read(ttsControllerProvider).isPlaying,
        label: 'tts-restarted',
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(container.read(ttsControllerProvider).isPlaying, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Explicit exit via top-left back button stops TTS & Auto-Read cleanly.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.byTooltip('返回书架'));
      await _settle(tester);

      expect(find.byType(ReaderPage), findsNothing);
      expect(container.read(ttsControllerProvider).status, TtsStatus.idle);
      expect(container.read(autoReadControllerProvider).isActive, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

extension on ui.PictureRecorder {
  Canvas get letCanvas => Canvas(this);
}
