import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/app/app.dart';
import 'package:pureread/app/providers.dart';
import 'package:pureread/application/backup/backup.dart';
import 'package:pureread/application/bookshelf/bookshelf_controller.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_session_controller.dart';
import 'package:pureread/application/reader/reader_session_state.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/local_epub/local_epub.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/database/database.dart';
import 'package:pureread/infrastructure/database/drift_backup_repository.dart';
import 'package:pureread/infrastructure/js/js_crypto_helpers.dart';
import 'package:pureread/infrastructure/js/qjs_sandbox_runtime.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/infrastructure/storage/chapter_cache_store.dart';
import 'package:pureread/infrastructure/storage/storage.dart';
import 'package:pureread/presentation/bookshelf/bookshelf_page.dart';
import 'package:pureread/presentation/reader/reader_page.dart';
import 'package:pureread/presentation/reader/reader_page_turn_view.dart';
import 'package:pureread/presentation/reader/simulation_page_curl.dart';

class _FakePlatformBridge implements PlatformBridge {
  List<String> filesToPick = const <String>[];
  List<String>? lastPickExtensions;

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async {
    lastPickExtensions = extensions;
    return filesToPick;
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async {}

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents =>
      const Stream<VolumeKeyDirection>.empty();

  @override
  Future<void> setImmersiveMode(bool enabled) async {}

  @override
  Future<void> bossKeyHide() async {}
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
  final crcInput = <int>[...typeBytes, ...data];
  final crc = _crc32(crcInput);
  final crcBytes = <int>[
    (crc >>> 24) & 0xFF,
    (crc >>> 16) & 0xFF,
    (crc >>> 8) & 0xFF,
    crc & 0xFF,
  ];
  return <int>[...lengthBytes, ...typeBytes, ...data, ...crcBytes];
}

Uint8List _buildValid1x1Png(int r, int g, int b) {
  final ihdr = _pngChunk('IHDR', <int>[
    0, 0, 0, 1, // width = 1
    0, 0, 0, 1, // height = 1
    8, // bit depth
    2, // RGB
    0, 0, 0,
  ]);
  final compressed = const ZLibEncoder().encode(<int>[0, r, g, b]);
  final idat = _pngChunk('IDAT', compressed);
  final iend = _pngChunk('IEND', const <int>[]);
  return Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...ihdr,
    ...idat,
    ...iend,
  ]);
}

Uint8List _buildZipBytes(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _buildEpub2Bytes(Uint8List coverPng) {
  return _buildZipBytes(<String, List<int>>{
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
    <dc:title>EPUB Two Chronicle</dc:title>
    <dc:creator>EPUB2 Author</dc:creator>
    <dc:description>Synthetic EPUB 2 NCX novel.</dc:description>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="cover-img" href="images/cover.png" media-type="image/png"/>
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
      <navLabel><text>第一章 初入古卷</text></navLabel>
      <content src="text/ch1.xhtml"/>
    </navPoint>
    <navPoint id="np2" playOrder="2">
      <navLabel><text>第二章 风云再起</text></navLabel>
      <content src="text/ch2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
'''),
    'OEBPS/images/cover.png': coverPng,
    'OEBPS/text/ch1.xhtml': _utf8('''
<html><body>
  <h1>第一章 初入古卷</h1>
  <p>EPUB2ChapterOne：青石长街尽头，古卷缓缓展开。</p>
</body></html>
'''),
    'OEBPS/text/ch2.xhtml': _utf8('''
<html><body>
  <h1>第二章 风云再起</h1>
  <p>EPUB2ChapterTwo：风起苍梧，云卷长天。</p>
</body></html>
'''),
  });
}

Uint8List _buildEpub3MultiAnchorBytes(Uint8List coverPng) {
  final alphaParas = List<String>.generate(
    18,
    (i) =>
        '<p>AlphaParagraph${i + 1}：山岚初散，第一锚点章节正文连续铺陈，'
        '用于校验多锚点切片与仿真卷页排版「，。！？」。</p>',
  ).join('\n');
  final betaParas = List<String>.generate(
    24,
    (i) =>
        '<p>BetaParagraph${i + 1}：星辉垂落，第二锚点章节正文独立呈现，'
        '支持仿真翻页拖拽与 charOffset 精确落盘。</p>',
  ).join('\n');
  final gammaParas = List<String>.generate(
    10,
    (i) => '<p>GammaParagraph${i + 1}：沧海余韵，第三锚点章节严禁向前泄漏。</p>',
  ).join('\n');

  return _buildZipBytes(<String, List<int>>{
    'mimetype': _utf8('application/epub+zip'),
    'META-INF/container.xml': _utf8('''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
    'OPS/package.opf': _utf8('''
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>EPUB Three Guide</dc:title>
    <dc:creator>EPUB3 Author</dc:creator>
    <dc:description>Synthetic EPUB 3 NAV multi-anchor book.</dc:description>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover" href="media/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="story" href="text/story.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="story"/>
  </spine>
</package>
'''),
    'OPS/nav.xhtml': _utf8('''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="text/story.xhtml#s1">Section Alpha</a></li>
        <li><a href="text/story.xhtml#s2">Section Beta</a></li>
        <li><a href="text/story.xhtml#s3">Section Gamma</a></li>
      </ol>
    </nav>
  </body>
</html>
'''),
    'OPS/media/cover.png': coverPng,
    'OPS/text/story.xhtml': _utf8('''
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <section id="s1">
      <h1>Section Alpha</h1>
      <p>【EPUB广告：测试水印待净化】</p>
      $alphaParas
    </section>
    <h2 id="s2">Section Beta</h2>
    <p>【EPUB广告：第二章水印待净化】</p>
    $betaParas
    <a name="s3"></a>
    <h3>Section Gamma</h3>
    $gammaParas
  </body>
</html>
'''),
  });
}

class _M3LegadoLoopbackServer {
  HttpServer? _server;

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    if (req.uri.path == '/search') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<html><body>
  <div class="item" data-id="77">
    <a href="/book/77">太虚剑典</a>
    <span class="author">玄微子</span>
  </div>
</body></html>
''');
      await req.response.close();
      return;
    }
    if (req.uri.path == '/book/77') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<html><body>
  <h1>太虚剑典</h1>
  <div class="author">玄微子</div>
  <a id="toc" href="/toc/77">目录</a>
</body></html>
''');
      await req.response.close();
      return;
    }
    if (req.uri.path == '/toc/77') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<html><body>
  <a data-cid="c1" href="/ch/c1">第一章 剑起太虚</a>
</body></html>
''');
      await req.response.close();
      return;
    }
    if (req.uri.path == '/ch/c1') {
      final encrypted = JsCryptoHelpers.aesEncryptBase64(
        '太虚一剑，破尽虚妄。\nAES 解密正文完整呈现。',
        'f041c49714d39908',
        transformation: 'AES/CBC/PKCS5Padding',
        iv: '0123456789abcdef',
      );
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(<String, Object?>{'cipher': encrypted}));
      await req.response.close();
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxIterations = 350,
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
  fail(
    'Timed out waiting for async/UI condition'
    '${label != null ? ' ($label)' : ''}.',
  );
}

Future<T> _runWhilePumping<T>(
  WidgetTester tester,
  Future<T> future, {
  int maxIterations = 500,
  String? label,
}) async {
  var done = false;
  late T value;
  Object? capturedError;
  StackTrace? capturedStack;

  unawaited(
    future.then<void>(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object err, StackTrace st) {
        capturedError = err;
        capturedStack = st;
        done = true;
      },
    ),
  );

  await _pumpUntil(
    tester,
    () => done,
    maxIterations: maxIterations,
    label: label,
  );

  if (capturedError != null) {
    Error.throwWithStackTrace(capturedError!, capturedStack!);
  }
  return value;
}

void _assertPaginatorLayoutValid(ReaderSessionState state) {
  final config = state.paginationConfig;
  expect(config, isNotNull);
  expect(state.currentPages, isNotEmpty);
  for (final page in state.currentPages) {
    for (final line in page.lines) {
      expect(
        line.y + line.height,
        lessThanOrEqualTo(config!.columnHeight + 0.5),
      );
      expect(
        line.x + line.width,
        lessThanOrEqualTo(config.columnWidth + 0.5),
      );
    }
  }
}

PureReadRuntime _createRuntime({
  required AppPathResolver pathResolver,
  required AppDatabase database,
}) {
  final worker = TxtIsolateWorker();
  final txtProvider = LocalTxtProvider(worker: worker);
  final epubProvider = LocalEpubProvider();
  final fontStorage = FontStorageService(pathResolver);
  final httpClient = SourceHttpClient();
  final cacheStore = ChapterCacheStore(pathResolver);
  final providerFactory = BookProviderFactory(httpClient: httpClient);
  const importExportService = SourceImportExportService();
  final backupRepo = DriftBackupRepository(database, pathResolver);

  return PureReadRuntime(
    pathResolver: pathResolver,
    database: database,
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
}

List<Override> _overridesFromRuntime(
  PureReadRuntime runtime,
  PlatformBridge platformBridge,
) {
  return buildPureReadOverrides(
    database: runtime.database,
    pathResolver: runtime.pathResolver,
    localTxtProvider: runtime.localTxtProvider,
    localEpubProvider: runtime.localEpubProvider,
    fontStorageService: runtime.fontStorageService,
    platformBridge: platformBridge,
    sourceHttpClient: runtime.sourceHttpClient,
    chapterCacheStore: runtime.chapterCacheStore,
    bookProviderFactory: runtime.bookProviderFactory,
    sourceImportExportService: runtime.sourceImportExportService,
    backupRepository: runtime.backupRepository,
  );
}

void main() {
  testWidgets(
    'M3 Full E2E: EPUB 2/3 unified import + cover, F1.3 group CRUD, multi-anchor reader + simulation curl, backup restore, and cache-cleanup delete',
    (tester) async {
      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('pureread_m3_e2e_'),
      );
      expect(tempDir, isNotNull);

      PureReadRuntime? activeRuntime;
      addTearDown(() async {
        PaintingBinding.instance.imageCache.clear();
        await activeRuntime?.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (await tempDir!.exists()) {
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {
            // Best-effort cleanup if SQLite handle closes asynchronously on failure.
          }
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

      final epub2File = File(p.join(booksDir.path, 'epub2_chronicle.epub'));
      final epub3File = File(p.join(booksDir.path, 'epub3_multianchor.epub'));
      await tester.runAsync(() async {
        await epub2File.writeAsBytes(
          _buildEpub2Bytes(_buildValid1x1Png(42, 110, 72)),
        );
        await epub3File.writeAsBytes(
          _buildEpub3MultiAnchorBytes(_buildValid1x1Png(60, 95, 140)),
        );
      });

      var db = AppDatabase.forFile(
        pathResolver.databaseFile,
        backupsDirPath: pathResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      var runtime = _createRuntime(pathResolver: pathResolver, database: db);
      activeRuntime = runtime;
      final platformBridge = _FakePlatformBridge();

      // Seed a global ReplaceRule to verify EPUB prose passes ContentSanitizerImpl.
      await tester.runAsync(() async {
        await DriftSourceRepository(db).saveReplaceRule(
          ReplaceRule(
            id: 'm3-epub-watermark',
            name: '清理EPUB广告',
            pattern: r'【EPUB广告：.*?】',
            replacement: '',
            isRegex: true,
            scopeType: RuleScopeType.global,
            enabled: true,
            sortOrder: 0,
            updatedAt: DateTime.utc(2026, 11, 25),
          ),
        );
      });

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 820);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey<String>('m3-session-1'),
          overrides: _overridesFromRuntime(runtime, platformBridge),
          child: const PureReadApp(),
        ),
      );
      await _pumpUntil(
        tester,
        () => !ProviderScope.containerOf(
          tester.element(find.byType(PureReadApp)),
          listen: false,
        ).read(bookshelfControllerProvider).isLoading,
        label: 'm3-session1-init',
      );

      final container1 = ProviderScope.containerOf(
        tester.element(find.byType(PureReadApp)),
        listen: false,
      );

      // 1. Unified Bookshelf import picking both EPUB 2 & EPUB 3 files.
      platformBridge.filesToPick = <String>[epub2File.path, epub3File.path];
      await tester.tap(find.text('导入本地 TXT'));
      await _pumpUntil(
        tester,
        () =>
            !container1.read(bookshelfControllerProvider).isImporting &&
            container1.read(bookshelfControllerProvider).books.length == 2,
        label: 'unified-epub-import',
      );

      expect(platformBridge.lastPickExtensions, equals(<String>['txt', 'epub']));
      final shelfAfterImport = container1.read(bookshelfControllerProvider);
      final epub2Book = shelfAfterImport.books.firstWhere(
        (b) => b.title == 'EPUB Two Chronicle',
      );
      final epub3Book = shelfAfterImport.books.firstWhere(
        (b) => b.title == 'EPUB Three Guide',
      );
      expect(epub2Book.providerType, ProviderType.localEpub);
      expect(epub3Book.providerType, ProviderType.localEpub);
      expect(epub2Book.totalChapters, 2);
      expect(epub3Book.totalChapters, 3);
      expect(epub2Book.coverPath, isNotNull);
      expect(epub3Book.coverPath, isNotNull);
      expect(
        p.isWithin(pathResolver.coversDir.path, epub2Book.coverPath!),
        isTrue,
      );
      expect(
        p.isWithin(pathResolver.coversDir.path, epub3Book.coverPath!),
        isTrue,
      );
      expect(File(epub2Book.coverPath!).existsSync(), isTrue);
      expect(File(epub3Book.coverPath!).existsSync(), isTrue);

      // Cover images are rendered on BookshelfPage without exceptions.
      expect(find.byType(Image), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      final dbEpub3Chapters = await _runWhilePumping(
        tester,
        container1.read(bookRepositoryProvider).listChapters(epub3Book.id),
        label: 'list-epub3-chapters',
      );
      expect(
        dbEpub3Chapters.map((c) => c.epubHref).toList(),
        equals(<String>[
          'OPS/text/story.xhtml#s1',
          'OPS/text/story.xhtml#s2',
          'OPS/text/story.xhtml#s3',
        ]),
      );

      // 2. F1.3 Group CRUD: create -> rename -> move book -> filter -> delete.
      await tester.tap(find.byTooltip('新建分组'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, '精选EPUB');
      await tester.tap(find.text('创建'));
      await _pumpUntil(
        tester,
        () => container1
            .read(bookshelfControllerProvider)
            .groups
            .any((g) => g.name == '精选EPUB'),
        label: 'create-group',
      );

      // Rename '精选EPUB' -> '收藏EPUB' via Manage Groups dialog.
      await tester.tap(find.byTooltip('管理分组'));
      await _settle(tester);
      await tester.tap(find.byTooltip('重命名分组').last);
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, '收藏EPUB');
      await tester.tap(find.text('保存'));
      await _pumpUntil(
        tester,
        () => container1
            .read(bookshelfControllerProvider)
            .groups
            .any((g) => g.name == '收藏EPUB'),
        label: 'rename-group',
      );
      await tester.tap(find.text('完成'));
      await _settle(tester);

      final renamedGroup = container1
          .read(bookshelfControllerProvider)
          .groups
          .firstWhere((g) => g.name == '收藏EPUB');

      // Move EPUB 3 into '收藏EPUB'.
      await _runWhilePumping(
        tester,
        container1
            .read(bookshelfControllerProvider.notifier)
            .moveBookToGroup(epub3Book.id, renamedGroup.id),
        label: 'move-epub3-to-group',
      );

      // Filter by '收藏EPUB' -> only EPUB Three Guide shown.
      final favoriteChip = find.widgetWithText(ChoiceChip, '收藏EPUB');
      await tester.ensureVisible(favoriteChip);
      await _settle(tester);
      await tester.tap(favoriteChip);
      await _settle(tester);
      expect(
        container1.read(bookshelfControllerProvider).filteredBooks.map((b) => b.id),
        equals(<String>[epub3Book.id]),
      );
      expect(find.text('EPUB Three Guide'), findsOneWidget);
      expect(find.text('EPUB Two Chronicle'), findsNothing);

      // Filter by '未分组' -> only EPUB Two Chronicle shown.
      final ungroupedChip = find.widgetWithText(ChoiceChip, '未分组');
      await tester.ensureVisible(ungroupedChip);
      await _settle(tester);
      await tester.tap(ungroupedChip);
      await _settle(tester);
      expect(
        container1.read(bookshelfControllerProvider).filteredBooks.map((b) => b.id),
        equals(<String>[epub2Book.id]),
      );

      // Select '收藏EPUB' again, then delete it -> resets selectedGroupId to null & returns EPUB 3 to ungrouped.
      await tester.ensureVisible(favoriteChip);
      await _settle(tester);
      await tester.tap(favoriteChip);
      await _settle(tester);
      await tester.tap(find.byTooltip('管理分组'));
      await _settle(tester);
      await tester.tap(find.byTooltip('删除分组').last);
      await _settle(tester);
      await tester.tap(find.text('删除'));
      await _pumpUntil(
        tester,
        () => !container1
            .read(bookshelfControllerProvider)
            .groups
            .any((g) => g.id == renamedGroup.id),
        label: 'delete-group',
      );
      await tester.tap(find.text('完成'));
      await _settle(tester);

      final epub3AfterGroupDelete = await _runWhilePumping(
        tester,
        container1.read(bookRepositoryProvider).getBookById(epub3Book.id),
        label: 'check-epub3-ungrouped',
      );
      expect(epub3AfterGroupDelete?.groupId, isNull);
      expect(
        container1.read(bookshelfControllerProvider).selectedGroupId,
        isNull,
      );

      // Create '长篇归档' and move EPUB 3 into it before backup/restore.
      final archiveGroup = await _runWhilePumping(
        tester,
        container1
            .read(bookshelfControllerProvider.notifier)
            .createGroup('长篇归档'),
        label: 'create-archive-group',
      );
      expect(archiveGroup, isNotNull);
      await _runWhilePumping(
        tester,
        container1
            .read(bookshelfControllerProvider.notifier)
            .moveBookToGroup(epub3Book.id, archiveGroup!.id),
        label: 'move-epub3-to-archive-group',
      );

      // Switch back to '全部' before opening EPUB 3.
      final allChip = find.widgetWithText(ChoiceChip, '全部');
      await tester.ensureVisible(allChip);
      await _settle(tester);
      await tester.tap(allChip);
      await _settle(tester);

      // 3. Open EPUB 3 in ReaderPage, verify #fragment slicing, switch to simulation curl & turn pages.
      await tester.tap(find.text('EPUB Three Guide').first);
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final rState = container1.read(
          readerSessionControllerProvider(epub3Book.id),
        );
        return !rState.isLoading &&
            !rState.isPaginating &&
            rState.currentPages.isNotEmpty &&
            rState.paginationConfig != null;
      }, label: 'open-epub3-reader');

      ReaderSessionState readEpub3State() =>
          container1.read(readerSessionControllerProvider(epub3Book.id));

      final ch0State = readEpub3State();
      expect(ch0State.currentChapterIndex, 0);
      expect(ch0State.currentChapterText, contains('AlphaParagraph1'));
      expect(ch0State.currentChapterText, isNot(contains('BetaParagraph')));
      expect(ch0State.currentChapterText, isNot(contains('GammaParagraph')));
      expect(ch0State.currentChapterText, isNot(contains('EPUB广告')));
      _assertPaginatorLayoutValid(ch0State);

      // Jump to Section Beta (#s2) via controller/TOC and verify clean #s2 boundaries.
      await _runWhilePumping(
        tester,
        container1
            .read(readerSessionControllerProvider(epub3Book.id).notifier)
            .jumpToChapter(1),
        label: 'jump-to-section-beta',
      );
      await _pumpUntil(
        tester,
        () =>
            !readEpub3State().isPaginating &&
            readEpub3State().currentChapterIndex == 1,
        label: 'section-beta-loaded',
      );
      final ch1State = readEpub3State();
      expect(ch1State.currentChapterText, contains('BetaParagraph1'));
      expect(ch1State.currentChapterText, isNot(contains('AlphaParagraph')));
      expect(ch1State.currentChapterText, isNot(contains('GammaParagraph')));
      expect(ch1State.currentChapterText, isNot(contains('EPUB广告')));
      _assertPaginatorLayoutValid(ch1State);

      // Switch page turn mode to PageTurnMode.simulation in ReaderSettingsSheet.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.text('设置'));
      await _settle(tester);
      await tester.ensureVisible(find.text('仿真'));
      await _settle(tester);
      await tester.tap(find.text('仿真'));
      await _pumpUntil(
        tester,
        () =>
            readEpub3State().activeTheme.pageTurnMode ==
                PageTurnMode.simulation &&
            !readEpub3State().isPaginating,
        label: 'switch-to-simulation-mode',
      );
      await tester.ensureVisible(find.byIcon(Icons.close).last);
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.close).last);
      await _settle(tester);
      expect(readEpub3State().showOverlay, isFalse);
      expect(find.byType(SimulationPageCurlView), findsOneWidget);

      // Perform a full interactive curl drag forward inside Section Beta.
      await tester.drag(
        find.byType(ReaderPageTurnView),
        const Offset(-220, 0),
      );
      await _pumpUntil(
        tester,
        () =>
            !readEpub3State().isPaginating &&
            readEpub3State().currentPageIndex > 0 &&
            readEpub3State().anchorOffset > 0,
        label: 'curl-turn-forward',
      );

      final savedChapterIndex = readEpub3State().currentChapterIndex;
      final savedCharOffset = readEpub3State().anchorOffset;
      expect(savedChapterIndex, 1);
      expect(savedCharOffset, greaterThan(0));

      await _runWhilePumping(
        tester,
        container1
            .read(readerSessionControllerProvider(epub3Book.id).notifier)
            .flushProgress(),
        label: 'flush-epub3-progress',
      );

      // Exit Reader back to BookshelfPage.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.byTooltip('返回书架'));
      await _pumpUntil(
        tester,
        () => find.byType(BookshelfPage).evaluate().isNotEmpty,
        label: 'back-to-bookshelf',
      );

      // 4. Export .pureread.zip, wipe DB + epub2 cover file, and restore into fresh DB.
      final backupController1 = container1.read(
        backupControllerProvider.notifier,
      );
      await _pumpUntil(
        tester,
        () => !container1.read(backupControllerProvider).isLoading,
        label: 'backup-init-1',
      );
      final exportedPath = await _runWhilePumping(
        tester,
        backupController1.exportBackup(),
        label: 'export-m3-backup',
      );
      expect(exportedPath, isNotNull);
      expect(File(exportedPath!).existsSync(), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await runtime.dispose();
        if (await pathResolver.dbDir.exists()) {
          await pathResolver.dbDir.delete(recursive: true);
        }
        // Delete epub2 cover file on disk to assert graceful placeholder fallback!
        final epub2Cover = File(epub2Book.coverPath!);
        if (await epub2Cover.exists()) {
          await epub2Cover.delete();
        }
        await pathResolver.ensureDirectoriesExist();
      });
      activeRuntime = null;

      db = AppDatabase.forFile(
        pathResolver.databaseFile,
        backupsDirPath: pathResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      runtime = _createRuntime(pathResolver: pathResolver, database: db);
      activeRuntime = runtime;

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey<String>('m3-session-2'),
          overrides: _overridesFromRuntime(runtime, platformBridge),
          child: const PureReadApp(),
        ),
      );
      await _pumpUntil(
        tester,
        () => !ProviderScope.containerOf(
          tester.element(find.byType(PureReadApp)),
          listen: false,
        ).read(bookshelfControllerProvider).isLoading,
        label: 'm3-session2-init',
      );

      final container2 = ProviderScope.containerOf(
        tester.element(find.byType(PureReadApp)),
        listen: false,
      );
      expect(container2.read(bookshelfControllerProvider).books, isEmpty);

      final backupController2 = container2.read(
        backupControllerProvider.notifier,
      );
      await _pumpUntil(
        tester,
        () => !container2.read(backupControllerProvider).isLoading,
        label: 'backup-init-2',
      );
      final restoredOk = await _runWhilePumping(
        tester,
        backupController2.restoreBackup(
          mode: BackupRestoreMode.overwrite,
          archivePath: exportedPath,
        ),
        label: 'restore-m3-backup',
      );
      expect(restoredOk, isTrue);

      await _runWhilePumping(
        tester,
        container2.read(bookshelfControllerProvider.notifier).refresh(),
        label: 'refresh-shelf-after-restore',
      );
      await _pumpUntil(
        tester,
        () => container2.read(bookshelfControllerProvider).books.length == 2,
        label: 'shelf-restored-books',
      );

      final restoredShelf = container2.read(bookshelfControllerProvider);
      expect(
        restoredShelf.groups.any(
          (g) => g.id == archiveGroup.id && g.name == '长篇归档',
        ),
        isTrue,
      );
      final restoredEpub2 = restoredShelf.books.firstWhere(
        (b) => b.id == epub2Book.id,
      );
      final restoredEpub3 = restoredShelf.books.firstWhere(
        (b) => b.id == epub3Book.id,
      );
      expect(restoredEpub2.coverPath, epub2Book.coverPath);
      expect(restoredEpub3.coverPath, epub3Book.coverPath);
      expect(restoredEpub3.groupId, archiveGroup.id);

      // epub2 cover missing -> fallback placeholder renders cleanly; epub3 cover still exists -> 1 Image widget.
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);

      final restoredProgress = await _runWhilePumping(
        tester,
        container2.read(bookRepositoryProvider).getProgress(epub3Book.id),
        label: 'read-restored-epub3-progress',
      );
      expect(restoredProgress?.chapterIndex, savedChapterIndex);
      expect(restoredProgress?.charOffset, savedCharOffset);

      // Reopen restored EPUB 3 -> chapters rebuild from localFilePath, simulation mode & progress recover cleanly.
      await tester.tap(find.text('EPUB Three Guide').first);
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final rState = container2.read(
          readerSessionControllerProvider(epub3Book.id),
        );
        return !rState.isLoading &&
            !rState.isPaginating &&
            rState.currentPages.isNotEmpty;
      }, label: 'reopen-restored-epub3');

      final reopenedState = container2.read(
        readerSessionControllerProvider(epub3Book.id),
      );
      expect(reopenedState.currentChapterIndex, savedChapterIndex);
      expect(reopenedState.anchorOffset, savedCharOffset);
      expect(
        reopenedState.activeTheme.pageTurnMode,
        PageTurnMode.simulation,
      );
      expect(reopenedState.currentChapterText, contains('BetaParagraph1'));
      expect(reopenedState.currentChapterText, isNot(contains('AlphaParagraph')));
      expect(reopenedState.currentChapterText, isNot(contains('GammaParagraph')));
      expect(find.byType(SimulationPageCurlView), findsOneWidget);

      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.byTooltip('返回书架'));
      await _pumpUntil(
        tester,
        () => find.byType(BookshelfPage).evaluate().isNotEmpty,
        label: 'back-to-bookshelf-2',
      );

      // 5. Delete book with optional cached-chapter cleanup (`deleteCachedChapters`).
      await tester.runAsync(() async {
        await runtime.chapterCacheStore.writeChapter(
          epub2Book.id,
          0,
          'cached-ch0-text',
        );
        await runtime.chapterCacheStore.writeChapter(
          epub3Book.id,
          0,
          'cached-epub3-text',
        );
      });
      expect(
        await tester.runAsync(
          () => runtime.chapterCacheStore.readChapter(epub2Book.id, 0),
        ),
        'cached-ch0-text',
      );

      // Switch to list mode so per-book delete button is directly tappable.
      await tester.tap(find.byTooltip('切换列表视图'));
      await _settle(tester);

      // Delete first book (EPUB Three Guide) WITHOUT cache cleanup.
      await tester.tap(find.byTooltip('删除书籍').first);
      await _settle(tester);
      expect(find.text('移除书籍'), findsOneWidget);
      expect(find.text('同时清理已缓存章节'), findsOneWidget);
      await tester.tap(find.text('移除'));
      await _pumpUntil(
        tester,
        () => container2.read(bookshelfControllerProvider).books.length == 1,
        label: 'delete-without-cache-cleanup',
      );
      expect(
        await tester.runAsync(
          () => runtime.chapterCacheStore.readChapter(epub3Book.id, 0),
        ),
        'cached-epub3-text',
      );

      // Delete remaining book (EPUB Two Chronicle) WITH cache cleanup checked.
      await tester.tap(find.byTooltip('删除书籍').first);
      await _settle(tester);
      await tester.tap(find.text('同时清理已缓存章节'));
      await _settle(tester);
      await tester.tap(find.text('移除'));
      await _pumpUntil(
        tester,
        () => container2.read(bookshelfControllerProvider).books.isEmpty,
        label: 'delete-with-cache-cleanup',
      );
      expect(
        await tester.runAsync(
          () => runtime.chapterCacheStore.readChapter(epub2Book.id, 0),
        ),
        isNull,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await runtime.dispose();
      });
      activeRuntime = null;
      await tester.pump(const Duration(seconds: 4));
    },
  );

  test(
    'M3 Legado compat E2E: QuickJS java.createSymmetricCrypto AES decryption + :regex \$1/\$2 list extraction',
    () async {
      final prevHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevHttpOverrides);

      // Direct QjsSandboxRuntime probe mirroring M2/M3 QuickJS host bridge.
      final qjsProbe = QjsSandboxRuntime(sourceId: 'm3-e2e-qjs-probe');
      try {
        final probeRes = await qjsProbe.evaluate('''
          const enc = host.symmetricCrypto(
            "encryptBase64",
            "AES/CBC/PKCS5Padding",
            "f041c49714d39908",
            "0123456789abcdef",
            "M3-QuickJS-OK"
          );
          host.symmetricCrypto(
            "decryptBase64Str",
            "AES/CBC/PKCS5Padding",
            "f041c49714d39908",
            "0123456789abcdef",
            enc
          );
        ''');
        expect(probeRes.value, 'M3-QuickJS-OK');
      } finally {
        await qjsProbe.dispose();
      }

      final server = _M3LegadoLoopbackServer();
      await server.start();
      final httpClient = SourceHttpClient();

      try {
        final legadoJson = jsonEncode(<String, Object?>{
          'bookSourceName': 'M3 Crypto Regex 源',
          'bookSourceUrl': server.baseUrl,
          'bookSourceType': 0,
          'concurrentRate': '0',
          'searchUrl': '/search?q={{key}}',
          'ruleSearch': <String, Object?>{
            'bookList':
                r':(?is)<div class="item" data-id="(\d+)">\s*<a href="([^"]+)">(.*?)</a>\s*<span class="author">(.*?)</span>',
            'name': r'$3',
            'author': r'$4',
            'bookUrl': r'/book/$1',
          },
          'ruleBookInfo': <String, Object?>{
            'name': 'h1@text',
            'author': '.author@text',
            'tocUrl': '#toc@href',
          },
          'ruleToc': <String, Object?>{
            'chapterList':
                r'@regex:(?is)<a data-cid="([^"]+)" href="([^"]+)">(.*?)</a>',
            'chapterName': r'$3',
            'chapterUrl': r'/ch/$1',
          },
          'ruleContent': <String, Object?>{
            'content': '''
<js>
const payload = JSON.parse(result);
java.createSymmetricCrypto("AES/CBC/PKCS5Padding", "f041c49714d39908", "0123456789abcdef").decryptStr(payload.cipher);
</js>
''',
          },
        });

        final factory = BookProviderFactory(httpClient: httpClient);
        final now = DateTime.utc(2026, 11, 25);
        final provider = factory.createProvider(
          BookSource(
            id: 'm3-legado-src',
            name: 'M3 Crypto Regex 源',
            engineType: SourceEngineType.legado,
            baseUrl: server.baseUrl,
            rawDefinition: legadoJson,
            rateLimitMs: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final searchRes = await provider.search('太虚');
        expect(searchRes.items, hasLength(1));
        expect(searchRes.items.single.title, '太虚剑典');
        expect(searchRes.items.single.author, '玄微子');
        expect(searchRes.items.single.bookUrl, '${server.baseUrl}/book/77');

        final detailRes = await provider.getBookDetail(
          searchRes.items.single.bookUrl,
        );
        expect(detailRes.detail.tocUrl, '${server.baseUrl}/toc/77');

        final tocRes = await provider.getToc(detailRes.detail.tocUrl);
        expect(tocRes.chapters, hasLength(1));
        expect(tocRes.chapters.single.title, '第一章 剑起太虚');
        expect(tocRes.chapters.single.url, '${server.baseUrl}/ch/c1');

        final contentRes = await provider.getChapterContent(
          tocRes.chapters.single,
        );
        expect(
          contentRes.content.rawText,
          '太虚一剑，破尽虚妄。\nAES 解密正文完整呈现。',
        );
      } finally {
        httpClient.close();
        await server.close();
      }
    },
  );
}
