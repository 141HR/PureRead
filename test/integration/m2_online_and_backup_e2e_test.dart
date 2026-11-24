import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
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
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/application/reader/reader_session_controller.dart';
import 'package:pureread/application/reader/reader_session_state.dart';
import 'package:pureread/application/search/book_detail_controller.dart';
import 'package:pureread/application/search/change_source_controller.dart';
import 'package:pureread/application/search/search_controller.dart';
import 'package:pureread/application/source_lab/source_debug_controller.dart';
import 'package:pureread/application/source_lab/source_debug_state.dart';
import 'package:pureread/application/source_lab/sources_controller.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/database/database.dart';
import 'package:pureread/infrastructure/database/drift_backup_repository.dart';
import 'package:pureread/infrastructure/js/qjs_sandbox_runtime.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/infrastructure/storage/chapter_cache_store.dart';
import 'package:pureread/infrastructure/storage/storage.dart';
import 'package:pureread/presentation/bookshelf/bookshelf_page.dart';
import 'package:pureread/presentation/reader/reader_page.dart';
import 'package:pureread/presentation/reader/reader_page_turn_view.dart';
import 'package:pureread/presentation/search/change_source_sheet.dart';

class _FakePlatformBridge implements PlatformBridge {
  List<String> filesToPick = const <String>[];

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async => filesToPick;

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

class _M2LoopbackNovelServer {
  HttpServer? _server;
  bool enableUpdatedChapter = false;
  final List<String> requestedPaths = <String>[];

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
    final path = req.uri.path;
    requestedPaths.add(path);

    if (req.method == 'POST' && path == '/legado/search') {
      final rawBody = await utf8.decoder.bind(req).join();
      final token = req.headers.value('x-legado-token');
      if (token != 'm2-e2e' || !rawBody.contains('searchkey=')) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      final queryMatch = RegExp(r'searchkey=([^&]+)').firstMatch(rawBody);
      final encodedKw = queryMatch?.group(1) ?? '';
      final decodedKw = _decodeGbkFormValue(encodedKw);
      if (!decodedKw.contains('星海')) {
        _writeGbkHtml(req.response, '<html><body><ul id="results"></ul></body></html>');
        return;
      }
      _writeGbkHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>Legado搜索</title></head>
<body>
  <ul id="results">
    <li class="book-row">
      <a class="book-name" href="/legado/book/100">《星海剑歌》</a>
      <span class="author">作者：云中客</span>
      <span class="latest">最新：第6章 剑意初成</span>
      <p class="intro">山海潮生，一剑破万法。</p>
    </li>
  </ul>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path == '/legado/book/100') {
      _writeGbkHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>星海剑歌</title></head>
<body>
  <div id="info">
    <h1>星海剑歌</h1>
    <div class="author">云中客</div>
    <p class="intro">山海潮生，一剑破万法。</p>
    <a id="toc" href="/legado/toc/100">查看目录</a>
  </div>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path == '/legado/toc/100') {
      final chaptersHtml = <String>[
        '<li><a href="/legado/ch/0">第1章 风起青萍</a></li>',
        '<li><a href="/legado/ch/1">第2章 剑气初鸣</a></li>',
        '<li><a href="/legado/ch/2">第3章 山海问道</a></li>',
        '<li><a href="/legado/ch/3">第4章 星河夜话</a></li>',
        '<li><a href="/legado/ch/4">第5章 破晓时分</a></li>',
        '<li><a href="/legado/ch/5">第6章 剑意初成</a></li>',
      ].join('\n');
      _writeGbkHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>目录</title></head>
<body>
  <ul class="toc-list">
    $chaptersHtml
  </ul>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path.startsWith('/legado/ch/')) {
      final idx = int.tryParse(path.substring('/legado/ch/'.length));
      if (idx != null && idx >= 0 && idx <= 5) {
        final paragraphs = List<String>.generate(
          22,
          (i) =>
              '<p>LegadoCh${idx + 1}Para${i + 1}：剑风掠过青萍之末，云中客踏波而来，'
              '验证 GBK 解码、正则净化与增量分页「，。！？」。</p>',
        ).join('\n');
        _writeGbkHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>第${idx + 1}章</title></head>
<body>
  <div id="content">
    <p>第${idx + 1}章 正文开始</p>
    <p>【广告水印：盗版站点 www.fake-legado.test】</p>
    $paragraphs
  </div>
</body>
</html>
''');
        return;
      }
    }

    if (req.method == 'POST' && path == '/js/search') {
      final rawBody = await utf8.decoder.bind(req).join();
      final sig = req.headers.value('x-sig') ?? '';
      if (sig.isEmpty) {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
        return;
      }
      final payload = jsonDecode(rawBody) as Map<String, dynamic>;
      final kw = payload['keyword']?.toString() ?? '';
      if (!kw.contains('星海')) {
        _writeJson(req.response, <String, Object?>{'items': const <Object?>[]});
        return;
      }
      _writeJson(req.response, <String, Object?>{
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'title': '星海剑歌',
            'author': '云中客',
            'bookUrl': '/js/book/100',
            'intro': 'JS 源：星河入梦，长剑问天。',
            'latestChapter': enableUpdatedChapter
                ? '第七章 沧海归途'
                : '第六章 剑意初成',
            'kind': '仙侠奇幻',
          },
        ],
      });
      return;
    }

    if (req.method == 'GET' && path == '/js/book/100') {
      _writeUtf8Html(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>星海剑歌</title></head>
<body>
  <div class="detail">
    <h1 class="title">星海剑歌</h1>
    <span class="author">云中客</span>
    <p class="intro">JS 源：星河入梦，长剑问天。</p>
    <a class="toc-link" href="/js/toc/100">目录</a>
  </div>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path == '/js/toc/100') {
      final items = <String>[
        '<li><a href="/js/ch/0">第一章 风起青萍</a></li>',
        '<li><a href="/js/ch/1">第二章 剑气初鸣</a></li>',
        '<li><a href="/js/ch/2">第三章 山海问道</a></li>',
        '<li><a href="/js/ch/3">第四章 星河夜话</a></li>',
        '<li><a href="/js/ch/4">第五章 破晓时分</a></li>',
        '<li><a href="/js/ch/5">第六章 剑意初成</a></li>',
        if (enableUpdatedChapter)
          '<li><a href="/js/ch/6">第七章 沧海归途</a></li>',
      ].join('\n');
      _writeUtf8Html(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>JS目录</title></head>
<body>
  <ul class="toc-list">
    $items
  </ul>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path.startsWith('/js/ch/')) {
      final idx = int.tryParse(path.substring('/js/ch/'.length));
      if (idx != null && idx >= 0 && idx <= 6) {
        final paragraphs = List<String>.generate(
          22,
          (i) =>
              '<p>JsSourceCh${idx + 1}Para${i + 1}：星辉洒满长阶，换源后剧情衔接丝滑如初，'
              '继续检验排版几何与持久化精度！</p>',
        ).join('\n');
        _writeUtf8Html(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>第${idx + 1}章</title></head>
<body>
  <div id="chapter-content">
    <p>第${idx + 1}章（JS源）</p>
    <p>【广告水印：盗版站点 www.fake-js.test】</p>
    $paragraphs
  </div>
</body>
</html>
''');
        return;
      }
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  static String _decodeGbkFormValue(String encoded) {
    final bytes = <int>[];
    for (var i = 0; i < encoded.length; i++) {
      final ch = encoded[i];
      if (ch == '+') {
        bytes.add(0x20);
      } else if (ch == '%' && i + 2 < encoded.length) {
        final hex = encoded.substring(i + 1, i + 3);
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed != null) {
          bytes.add(parsed);
          i += 2;
        } else {
          bytes.addAll(utf8.encode(ch));
        }
      } else {
        bytes.addAll(utf8.encode(ch));
      }
    }
    return gbk.decode(bytes, allowMalformed: true);
  }

  void _writeGbkHtml(HttpResponse resp, String html) {
    resp.statusCode = HttpStatus.ok;
    resp.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=gbk');
    resp.add(gbk.encode(html));
    resp.close();
  }

  void _writeUtf8Html(HttpResponse resp, String html) {
    resp.statusCode = HttpStatus.ok;
    resp.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
    resp.add(utf8.encode(html));
    resp.close();
  }

  void _writeJson(HttpResponse resp, Object payload) {
    resp.statusCode = HttpStatus.ok;
    resp.headers.contentType = ContentType.json;
    resp.add(utf8.encode(jsonEncode(payload)));
    resp.close();
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

Future<void> _pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() asyncPredicate, {
  int maxIterations = 350,
  String? label,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    final matched = await tester.runAsync(asyncPredicate) ?? false;
    if (matched) {
      await _settle(tester);
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  fail(
    'Timed out waiting for async disk/network condition'
    '${label != null ? ' ($label)' : ''}.',
  );
}

void _assertPaginatorLayoutValid(ReaderSessionState state) {
  final config = state.paginationConfig;
  expect(config, isNotNull);
  expect(state.currentPages, isNotEmpty);

  var sawJustifiedLine = false;
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

String _buildJsPluginScript(String baseUrl) => '''
// @id js_e2e_source
// @name JS插件星海源
// @baseUrl $baseUrl
// @group E2E测试
// @rateLimitMs 0
async function search(keyword, page) {
  const sig = host.md5(keyword + ":" + page);
  const resp = await host.httpPost(
    "/js/search",
    JSON.stringify({ keyword, page }),
    { "Content-Type": "application/json", "X-Sig": sig }
  );
  const data = JSON.parse(resp.body);
  return data.items.map((item) => ({
    title: item.title,
    author: item.author,
    bookUrl: item.bookUrl,
    intro: item.intro,
    latestChapterTitle: item.latestChapter,
    kind: item.kind
  }));
}

async function detail(bookUrl) {
  const resp = await host.httpGet(bookUrl);
  return {
    title: host.cssSelectOne(resp.body, "h1.title@text"),
    author: host.cssSelectOne(resp.body, "span.author@text"),
    intro: host.cssSelectOne(resp.body, "p.intro@text"),
    tocUrl: host.cssSelectOne(resp.body, "a.toc-link@href")
  };
}

async function toc(tocUrl) {
  const resp = await host.httpGet(tocUrl);
  const items = host.cssElements(resp.body, "ul.toc-list li");
  return items.map((li) => ({
    title: host.cssSelectOne(li, "a@text"),
    url: host.cssSelectOne(li, "a@href")
  }));
}

async function content(chapterUrl) {
  const resp = await host.httpGet(chapterUrl);
  return {
    text: host.cssSelectOne(resp.body, "#chapter-content@html")
  };
}
''';

String _buildLegadoGbkSourceJson(String baseUrl) => jsonEncode(<String, Object?>{
  'bookSourceName': 'LegadoGBK星海源',
  'bookSourceUrl': '$baseUrl#gbk',
  'bookSourceGroup': 'E2E测试',
  'bookSourceType': 0,
  'weight': 100,
  'concurrentRate': '0',
  'charset': 'GBK',
  'header': '<js>JSON.stringify({"X-Legado-Token": "m2-e2e"})</js>',
  'searchUrl':
      '/legado/search,{ method: "POST", body: "searchkey={{key}}&page={{page}}", charset: "GBK" }',
  'ruleSearch': <String, Object?>{
    'bookList': 'id.results@tag.li',
    'name': 'a.book-name@text##《|》##',
    'author': 'span.author@text##^作者：##',
    'bookUrl': 'a.book-name@href',
    'intro': 'p.intro@text',
    'lastChapter': 'span.latest@text##^最新：##',
  },
  'ruleBookInfo': <String, Object?>{
    'name': 'id.info@tag.h1@text',
    'author': '#info .author@text',
    'intro': '#info .intro@text',
    'tocUrl': '#toc@href',
  },
  'ruleToc': <String, Object?>{
    'chapterList': 'class.toc-list@tag.li',
    'chapterName': 'a@text',
    'chapterUrl': 'a@href',
  },
  'ruleContent': <String, Object?>{
    'content': '#content@html',
  },
});

PureReadRuntime _createTestRuntime({
  required AppPathResolver pathResolver,
  required AppDatabase database,
}) {
  final worker = TxtIsolateWorker();
  final txtProvider = LocalTxtProvider(worker: worker);
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
    'M2 Full Online & Backup E2E: import Legado GBK + JS plugin, 4-step debug, multi-source search, detail, online reader + N+1..N+3 preload, change source, update check, backup export & fresh DB restore',
    (tester) async {
      final prevHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevHttpOverrides);

      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('pureread_m2_e2e_'),
      );
      expect(tempDir, isNotNull);

      final server = _M2LoopbackNovelServer();
      await tester.runAsync(server.start);

      PureReadRuntime? activeRuntime;
      addTearDown(() async {
        await activeRuntime?.dispose();
        await server.close();
        if (await tempDir!.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      // Verify QjsSandboxRuntime directly alongside JsPluginProvider.
      final qjsCheck = await tester.runAsync(() async {
        final sandbox = QjsSandboxRuntime(sourceId: 'e2e-qjs-probe');
        try {
          return await sandbox.evaluate(
            'JSON.stringify({ md5: host.md5("pureread"), sum: 21 + 21 })',
          );
        } finally {
          await sandbox.dispose();
        }
      });
      expect(jsonDecode(qjsCheck!.value), containsPair('sum', 42));

      final dataRoot = Directory(p.join(tempDir!.path, 'data'));
      final cacheRoot = Directory(p.join(tempDir.path, 'cache'));
      final pathResolver = AppPathResolver.fromRoots(
        dataRootDir: dataRoot,
        cacheRootDir: cacheRoot,
      );
      await tester.runAsync(pathResolver.ensureDirectoriesExist);

      var db = AppDatabase.forFile(
        pathResolver.databaseFile,
        backupsDirPath: pathResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      var runtime = _createTestRuntime(pathResolver: pathResolver, database: db);
      activeRuntime = runtime;
      final platformBridge = _FakePlatformBridge();

      // Seed global ReplaceRule to verify ContentSanitizerImpl on online chapters.
      final sourceRepo1 = DriftSourceRepository(db);
      await tester.runAsync(() async {
        await sourceRepo1.saveReplaceRule(
          ReplaceRule(
            id: 'e2e-global-watermark',
            name: '清理在线广告水印',
            pattern: r'【广告水印：.*?】',
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
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey<String>('m2-session-1'),
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
        label: 'm2-session1-init',
      );

      final container1 = ProviderScope.containerOf(
        tester.element(find.byType(PureReadApp)),
        listen: false,
      );

      // 1. Import Legado GBK + JS plugin sources via SourcesController.
      final sourcesController = container1.read(
        sourcesControllerProvider.notifier,
      );
      final legadoImported = await _runWhilePumping(
        tester,
        sourcesController.importFromText(
          _buildLegadoGbkSourceJson(server.baseUrl),
          fileName: 'legado_gbk.json',
        ),
        label: 'import-legado-source',
      );
      final jsImported = await _runWhilePumping(
        tester,
        sourcesController.importFromText(
          _buildJsPluginScript(server.baseUrl),
          fileName: 'js_plugin.js',
        ),
        label: 'import-js-source',
      );
      expect(legadoImported, isTrue);
      expect(jsImported, isTrue);

      await _pumpUntil(
        tester,
        () => container1.read(sourcesControllerProvider).sources.length == 2,
        label: 'sources-imported',
      );
      final importedSources = container1.read(sourcesControllerProvider).sources;
      final legadoSource = importedSources.firstWhere(
        (s) => s.engineType == SourceEngineType.legado,
      );
      final jsSource = importedSources.firstWhere(
        (s) => s.engineType == SourceEngineType.jsPlugin,
      );

      // 2. Run 4-step SourceDebugController on Legado GBK & JS plugin sources.
      final debugController = container1.read(
        sourceDebugControllerProvider.notifier,
      );
      await _runWhilePumping(
        tester,
        debugController.startDebug(
          sourceId: legadoSource.id,
          keyword: '星海',
        ),
        label: 'debug-legado',
      );
      await _pumpUntil(
        tester,
        () => !container1.read(sourceDebugControllerProvider).isRunning,
        label: 'debug-legado-done',
      );
      final legadoDebug = container1.read(sourceDebugControllerProvider);
      expect(
        legadoDebug.steps.values.every(
          (step) => step.status == DebugStepStatus.success,
        ),
        isTrue,
        reason:
            'Legado debug failed: ${legadoDebug.errorMessage} | '
            '${legadoDebug.steps.values.map((s) => '${s.step.name}=${s.status.name}(${s.errorMessage})').join(', ')}',
      );
      expect(legadoDebug.rawContent?.rawText, contains('广告水印'));
      expect(legadoDebug.sanitizedContent, isNot(contains('广告水印')));
      expect(legadoDebug.sanitizedContent, contains('LegadoCh1Para1'));

      await _runWhilePumping(
        tester,
        debugController.startDebug(
          sourceId: jsSource.id,
          keyword: '星海',
        ),
        label: 'debug-js',
      );
      await _pumpUntil(
        tester,
        () => !container1.read(sourceDebugControllerProvider).isRunning,
        label: 'debug-js-done',
      );
      final jsDebug = container1.read(sourceDebugControllerProvider);
      expect(
        jsDebug.steps.values.every(
          (step) => step.status == DebugStepStatus.success,
        ),
        isTrue,
        reason:
            'JS debug failed: ${jsDebug.errorMessage} | '
            '${jsDebug.steps.values.map((s) => '${s.step.name}=${s.status.name}(${s.errorMessage})').join(', ')}',
      );
      expect(jsDebug.sanitizedContent, contains('JsSourceCh1Para1'));
      expect(jsDebug.sanitizedContent, isNot(contains('广告水印')));

      // 3. Run multi-source SearchController and verify aggregation.
      await _runWhilePumping(
        tester,
        container1.read(searchControllerProvider.notifier).search('星海'),
        label: 'search-star-sea',
      );
      await _pumpUntil(
        tester,
        () =>
            !container1.read(searchControllerProvider).isSearching &&
            container1.read(searchControllerProvider).results.isNotEmpty,
        label: 'multi-source-search',
      );
      final searchState = container1.read(searchControllerProvider);
      expect(searchState.results, hasLength(1));
      final aggregatedBook = searchState.results.first;
      expect(aggregatedBook.title, '星海剑歌');
      expect(aggregatedBook.author, '云中客');
      expect(aggregatedBook.sourceCount, 2);
      expect(aggregatedBook.sources.first.item.sourceId, legadoSource.id);

      // 4. Load detail + TOC and add book via BookDetailController.
      final detailController = container1.read(
        bookDetailControllerProvider.notifier,
      );
      await _runWhilePumping(
        tester,
        detailController.loadAggregatedBook(aggregatedBook),
        label: 'load-book-detail',
      );
      await _pumpUntil(
        tester,
        () =>
            !container1.read(bookDetailControllerProvider).isBusy &&
            container1.read(bookDetailControllerProvider).chapters.length == 6,
        label: 'book-detail-loaded',
      );
      final addedBook = await _runWhilePumping(
        tester,
        detailController.addToBookshelf(),
        label: 'add-to-bookshelf',
      );
      expect(addedBook, isNotNull);
      expect(addedBook!.sourceId, legadoSource.id);
      expect(addedBook.providerType, ProviderType.legado);
      expect(addedBook.totalChapters, 6);

      await _pumpUntil(
        tester,
        () =>
            container1.read(bookshelfControllerProvider).books.length == 1 &&
            find.text('星海剑歌').evaluate().isNotEmpty,
        label: 'bookshelf-shows-online-book',
      );

      // 5. Open ReaderPage from PureReadApp, verify sanitizer, paginator, disk cache, and silent N+1..N+3 preload.
      server.requestedPaths.clear();
      await tester.tap(find.text('星海剑歌').first);
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final rState = container1.read(
          readerSessionControllerProvider(addedBook.id),
        );
        return !rState.isLoading &&
            !rState.isPaginating &&
            rState.currentPages.isNotEmpty &&
            rState.paginationConfig != null;
      }, label: 'open-online-reader');

      ReaderSessionState readOnlineState() =>
          container1.read(readerSessionControllerProvider(addedBook.id));

      final ch0State = readOnlineState();
      expect(ch0State.currentChapterIndex, 0);
      expect(ch0State.currentChapterText, contains('LegadoCh1Para1'));
      expect(ch0State.currentChapterText, isNot(contains('广告水印')));
      expect(ch0State.currentChapterText, isNot(contains('\uFFFD')));
      _assertPaginatorLayoutValid(ch0State);
      expect(tester.takeException(), isNull);

      // Verify chapter 0 AND silent N+1..N+3 (chapters 1, 2, 3) exist in disk cache while 4 & 5 do not.
      await _pumpUntilAsync(tester, () async {
        final ch0 = await runtime.chapterCacheStore.readChapter(addedBook.id, 0);
        final ch1 = await runtime.chapterCacheStore.readChapter(addedBook.id, 1);
        final ch2 = await runtime.chapterCacheStore.readChapter(addedBook.id, 2);
        final ch3 = await runtime.chapterCacheStore.readChapter(addedBook.id, 3);
        return ch0 != null && ch1 != null && ch2 != null && ch3 != null;
      }, label: 'silent-preload-n1-to-n3');

      expect(
        await tester.runAsync(
          () => runtime.chapterCacheStore.readChapter(addedBook.id, 4),
        ),
        isNull,
      );
      expect(
        await tester.runAsync(
          () => runtime.chapterCacheStore.readChapter(addedBook.id, 5),
        ),
        isNull,
      );

      // Jump to Chapter 1 ("第2章 剑气初鸣") and turn forward one page so charOffset > 0.
      await _runWhilePumping(
        tester,
        container1
            .read(readerSessionControllerProvider(addedBook.id).notifier)
            .jumpToChapter(1),
        label: 'jump-to-ch1-run',
      );
      await _pumpUntil(
        tester,
        () =>
            !readOnlineState().isPaginating &&
            readOnlineState().currentChapterIndex == 1,
        label: 'jump-to-ch1',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _pumpUntil(
        tester,
        () =>
            !readOnlineState().isPaginating &&
            readOnlineState().anchorOffset > 0,
        label: 'turn-inside-ch1',
      );

      // 6. Switch source via ChangeSourceSheet & ChangeSourceController preserving chapter alignment.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      expect(find.byTooltip('换源'), findsOneWidget);
      expect(find.byTooltip('缓存章节'), findsOneWidget);

      await tester.tap(find.byTooltip('换源'));
      await _pumpUntil(
        tester,
        () =>
            find.byType(ChangeSourceSheet).evaluate().isNotEmpty &&
            !container1.read(changeSourceControllerProvider).isSearching &&
            find.text(jsSource.name).evaluate().isNotEmpty,
        label: 'change-source-sheet-candidates',
      );

      await tester.tap(find.text(jsSource.name));
      await _pumpUntil(
        tester,
        () {
          final cs = container1.read(changeSourceControllerProvider);
          return !cs.isSearching &&
              !(cs.selectedCandidate?.isLoadingToc ?? true) &&
              find.textContaining('自动匹配成功').evaluate().isNotEmpty;
        },
        label: 'change-source-matched',
      );

      await tester.tap(find.text('确认切换'));
      await _pumpUntil(
        tester,
        () =>
            find.byType(ChangeSourceSheet).evaluate().isEmpty &&
            !readOnlineState().isPaginating &&
            readOnlineState().book?.sourceId == jsSource.id &&
            readOnlineState().currentChapterText.contains('JsSourceCh2Para1'),
        label: 'applied-js-source',
      );

      final switchedState = readOnlineState();
      expect(switchedState.book!.providerType, ProviderType.jsPlugin);
      expect(switchedState.currentChapterIndex, 1);
      expect(switchedState.currentChapterTitle, '第二章 剑气初鸣');
      expect(switchedState.anchorOffset, 0);
      expect(switchedState.currentChapterText, isNot(contains('广告水印')));
      _assertPaginatorLayoutValid(switchedState);

      // Advance one page inside Chapter 1 on the new JS source so saved progress has charOffset > 0.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _pumpUntil(
        tester,
        () =>
            !readOnlineState().isPaginating &&
            readOnlineState().anchorOffset > 0,
        label: 'advance-after-switch',
      );
      final expectedProgressChapter = readOnlineState().currentChapterIndex;
      final expectedProgressOffset = readOnlineState().anchorOffset;
      expect(expectedProgressChapter, 1);
      expect(expectedProgressOffset, greaterThan(0));

      // Verify silent N+1..N+3 preload (chapters 2, 3, 4) after switching to JS source.
      await _pumpUntilAsync(tester, () async {
        final ch1 = await runtime.chapterCacheStore.readChapter(addedBook.id, 1);
        final ch2 = await runtime.chapterCacheStore.readChapter(addedBook.id, 2);
        final ch3 = await runtime.chapterCacheStore.readChapter(addedBook.id, 3);
        final ch4 = await runtime.chapterCacheStore.readChapter(addedBook.id, 4);
        return ch1 != null &&
            ch1.contains('JsSourceCh2Para1') &&
            ch2 != null &&
            ch3 != null &&
            ch4 != null;
      }, label: 'js-source-preload-n1-to-n3');

      await _runWhilePumping(
        tester,
        container1
            .read(readerSessionControllerProvider(addedBook.id).notifier)
            .flushProgress(),
        label: 'flush-progress',
      );

      // 7. Return to BookshelfPage, add a new chapter on server, and trigger BookshelfController.checkUpdates().
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.byTooltip('返回书架'));
      await _pumpUntil(
        tester,
        () => find.byType(BookshelfPage).evaluate().isNotEmpty,
        label: 'back-to-bookshelf',
      );

      server.enableUpdatedChapter = true;
      await tester.tap(find.byTooltip('检查更新'));
      await _pumpUntil(
        tester,
        () {
          final shelfState = container1.read(bookshelfControllerProvider);
          return !shelfState.isCheckingUpdates &&
              shelfState.updateStatusMessage != null &&
              shelfState.books.isNotEmpty &&
              shelfState.books.first.totalChapters == 7;
        },
        label: 'bookshelf-update-check',
      );

      final shelfAfterUpdate = container1.read(bookshelfControllerProvider);
      final updatedBook = shelfAfterUpdate.books.first;
      expect(updatedBook.totalChapters, 7);
      expect(updatedBook.unreadCount, 1);
      expect(updatedBook.lastChapterTitle, '第七章 沧海归途');
      expect(updatedBook.latestChapterAt, isNotNull);
      expect(shelfAfterUpdate.updateStatusMessage, contains('+1 章'));
      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // 8. Select non-default theme ('slate_night') and export .pureread.zip via BackupController.
      final backupController1 = container1.read(backupControllerProvider.notifier);
      await _pumpUntil(
        tester,
        () => !container1.read(backupControllerProvider).isLoading,
        label: 'backup-controller-init',
      );
      await _runWhilePumping(
        tester,
        backupController1.selectTheme(DefaultDatabaseSeeds.slateNightId),
        label: 'select-slate-night',
      );
      final exportedPath = await _runWhilePumping(
        tester,
        backupController1.exportBackup(),
        label: 'export-backup',
      );
      expect(exportedPath, isNotNull);
      expect(exportedPath!, endsWith('.pureread.zip'));
      expect(File(exportedPath).existsSync(), isTrue);

      // Unmount Session 1 and wipe SQLite DB files to simulate fresh reinstall.
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await runtime.dispose();
        if (await pathResolver.dbDir.exists()) {
          await pathResolver.dbDir.delete(recursive: true);
        }
        if (await pathResolver.chaptersCacheDir.exists()) {
          await pathResolver.chaptersCacheDir.delete(recursive: true);
        }
        await pathResolver.ensureDirectoriesExist();
      });
      activeRuntime = null;

      // Session 2: open brand new empty DB and restore .pureread.zip.
      db = AppDatabase.forFile(
        pathResolver.databaseFile,
        backupsDirPath: pathResolver.dbBackupsDir.path,
        useBackgroundIsolate: false,
      );
      runtime = _createTestRuntime(pathResolver: pathResolver, database: db);
      activeRuntime = runtime;

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey<String>('m2-session-2'),
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
        label: 'm2-session2-init',
      );

      final container2 = ProviderScope.containerOf(
        tester.element(find.byType(PureReadApp)),
        listen: false,
      );
      expect(container2.read(bookshelfControllerProvider).books, isEmpty);
      expect(
        await _runWhilePumping(
          tester,
          container2.read(sourceRepositoryProvider).listSources(),
          label: 'list-sources-before-restore',
        ),
        isEmpty,
      );

      final backupController2 = container2.read(backupControllerProvider.notifier);
      await _pumpUntil(
        tester,
        () => !container2.read(backupControllerProvider).isLoading,
      );
      final manifest = await _runWhilePumping(
        tester,
        backupController2.inspectBackupFile(exportedPath),
        label: 'inspect-backup',
      );
      expect(manifest, isNotNull);
      expect(manifest!.recordCounts['books'], 1);
      expect(manifest.recordCounts['book_sources'], 2);
      expect(manifest.recordCounts['replace_rules'], 1);

      final restoredOk = await _runWhilePumping(
        tester,
        backupController2.restoreBackup(
          mode: BackupRestoreMode.overwrite,
          archivePath: exportedPath,
        ),
        label: 'restore-backup',
      );
      expect(restoredOk, isTrue);

      // Verify repositories & controllers recover books, progress, sources, rules, and themes cleanly.
      await _runWhilePumping(
        tester,
        container2.read(bookshelfControllerProvider.notifier).refresh(),
        label: 'refresh-bookshelf',
      );
      await _runWhilePumping(
        tester,
        container2.read(sourcesControllerProvider.notifier).refresh(),
        label: 'refresh-sources',
      );
      await _pumpUntil(
        tester,
        () =>
            container2.read(bookshelfControllerProvider).books.length == 1 &&
            container2.read(sourcesControllerProvider).sources.length == 2,
        label: 'post-restore-ui-refresh',
      );

      final restoredBook = container2
          .read(bookshelfControllerProvider)
          .books
          .single;
      expect(restoredBook.id, addedBook.id);
      expect(restoredBook.title, '星海剑歌');
      expect(restoredBook.sourceId, jsSource.id);
      expect(restoredBook.providerType, ProviderType.jsPlugin);
      expect(restoredBook.totalChapters, 7);
      expect(restoredBook.lastChapterTitle, '第七章 沧海归途');

      final restoredProgress = await _runWhilePumping(
        tester,
        container2.read(bookRepositoryProvider).getProgress(addedBook.id),
        label: 'read-restored-progress',
      );
      expect(restoredProgress, isNotNull);
      expect(restoredProgress!.chapterIndex, expectedProgressChapter);
      expect(restoredProgress.charOffset, expectedProgressOffset);

      final restoredSources = await _runWhilePumping(
        tester,
        container2.read(sourceRepositoryProvider).listSources(),
        label: 'read-restored-sources',
      );
      expect(restoredSources, hasLength(2));
      expect(
        restoredSources.map((s) => s.id),
        containsAll(<String>[legadoSource.id, jsSource.id]),
      );

      final restoredRules = await _runWhilePumping(
        tester,
        container2.read(sourceRepositoryProvider).listReplaceRules(),
        label: 'read-restored-rules',
      );
      expect(restoredRules, hasLength(1));
      expect(restoredRules.single.id, 'e2e-global-watermark');

      final restoredThemeSetting = await _runWhilePumping(
        tester,
        container2
            .read(themeRepositoryProvider)
            .getSetting('active_theme_id'),
        label: 'read-restored-theme',
      );
      expect(restoredThemeSetting?.value, DefaultDatabaseSeeds.slateNightId);
      expect(
        container2.read(backupControllerProvider).activeTheme?.id,
        DefaultDatabaseSeeds.slateNightId,
      );
      expect(
        container2.read(backupControllerProvider).databaseSnapshots,
        isNotEmpty,
      );

      // Reopen restored online book and confirm TOC rebuilds, progress/theme recover, and unreadCount clears.
      await tester.tap(find.text('星海剑歌').first);
      await _pumpUntil(tester, () {
        if (find.byType(ReaderPage).evaluate().isEmpty) return false;
        final rState = container2.read(
          readerSessionControllerProvider(addedBook.id),
        );
        return !rState.isLoading &&
            !rState.isPaginating &&
            rState.currentPages.isNotEmpty &&
            rState.activeTheme.id == DefaultDatabaseSeeds.slateNightId;
      }, label: 'reopen-restored-reader');
      final reopenedState = container2.read(
        readerSessionControllerProvider(addedBook.id),
      );
      expect(reopenedState.activeTheme.id, DefaultDatabaseSeeds.slateNightId);
      expect(reopenedState.currentChapterIndex, expectedProgressChapter);
      expect(reopenedState.anchorOffset, expectedProgressOffset);
      expect(reopenedState.currentChapterText, contains('JsSourceCh2Para1'));
      expect(reopenedState.currentChapterText, isNot(contains('广告水印')));
      expect(reopenedState.book?.unreadCount, 0);
      _assertPaginatorLayoutValid(reopenedState);

      // Test batch chapter caching via "缓存章节" menu and CacheManagementGateway clear.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await _settle(tester);
      await tester.tap(find.byTooltip('缓存章节'));
      await _settle(tester);
      await tester.tap(find.text('缓存后续 50 章'));
      await _pumpUntilAsync(tester, () async {
        final ch5 = await runtime.chapterCacheStore.readChapter(addedBook.id, 5);
        final ch6 = await runtime.chapterCacheStore.readChapter(addedBook.id, 6);
        return ch5 != null && ch6 != null;
      }, label: 'batch-cache-50');

      final statsBeforeClear = await _runWhilePumping(
        tester,
        container2.read(cacheManagementGatewayProvider).getCacheStats(),
        label: 'cache-stats-before-clear',
      );
      expect(statsBeforeClear.cachedFileCount, greaterThanOrEqualTo(6));
      expect(statsBeforeClear.chapterCacheBytes, greaterThan(0));

      final freed = await _runWhilePumping(
        tester,
        container2.read(cacheManagementGatewayProvider).clearChapterCache(),
        label: 'clear-chapter-cache',
      );
      expect(freed, greaterThan(0));
      final chaptersAfterClear = await _runWhilePumping(
        tester,
        container2.read(bookRepositoryProvider).listChapters(addedBook.id),
        label: 'chapters-after-cache-clear',
      );
      expect(chaptersAfterClear.every((c) => !c.isCached), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await runtime.dispose();
        await server.close();
      });
      activeRuntime = null;
      await tester.pump(const Duration(seconds: 4));
    },
  );

  test(
    'M2 Real 1031-Source Corpus Import: import via SourceImportExportGateway, persist into DriftSourceRepository, and verify query/filter performance',
    () async {
      const corpusPath = r'd:\QQ\Downloads\超级精品书源1031个10月10日.json';
      if (!File(corpusPath).existsSync()) {
        markTestSkipped(
          'Real 1031-source corpus file not found at $corpusPath; skipping gracefully.',
        );
        return;
      }

      final tempDir = await Directory.systemTemp.createTemp(
        'pureread_m2_corpus_',
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
      final runtime = _createTestRuntime(pathResolver: resolver, database: db);
      final container = ProviderContainer(
        overrides: _overridesFromRuntime(runtime, _FakePlatformBridge()),
      );

      addTearDown(() async {
        container.dispose();
        await runtime.dispose();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final gateway = container.read(sourceImportExportGatewayProvider);
      final sourceRepo = container.read(sourceRepositoryProvider);

      final importSw = Stopwatch()..start();
      final importResult = await gateway.parseImportFile(corpusPath);
      importSw.stop();

      expect(importResult.invalidCount, 0);
      expect(importResult.skippedNonTextCount, 0);
      expect(importResult.sources, hasLength(1031));

      final saveSw = Stopwatch()..start();
      await sourceRepo.saveSources(importResult.sources);
      saveSw.stop();

      final querySw = Stopwatch()..start();
      final allPersisted = await sourceRepo.listSources();
      final enabledPersisted = await sourceRepo.listSources(enabledOnly: true);
      querySw.stop();

      expect(allPersisted, hasLength(1031));
      expect(enabledPersisted.length, greaterThan(0));
      expect(querySw.elapsedMilliseconds, lessThan(2000));

      final sourcesCtrl = container.read(sourcesControllerProvider.notifier);
      container.read(sourcesControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sourcesCtrl.refresh();

      final filterSw = Stopwatch()..start();
      final loadedState = container.read(sourcesControllerProvider);
      expect(loadedState.sources, hasLength(1031));
      expect(loadedState.groups.length, greaterThan(1));

      final sampleGroup = loadedState.groups.firstWhere(
        (g) => g != '全部',
      );
      sourcesCtrl.selectGroup(sampleGroup);
      final byGroup = container.read(sourcesControllerProvider).filteredSources;
      expect(byGroup, isNotEmpty);

      sourcesCtrl.selectGroup('全部');
      sourcesCtrl.setSearchQuery(allPersisted.first.name);
      final bySearch = container.read(sourcesControllerProvider).filteredSources;
      expect(bySearch, isNotEmpty);
      filterSw.stop();

      expect(filterSw.elapsedMilliseconds, lessThan(1000));
    },
  );

  test(
    'M2 BookshelfController.checkUpdates skips missing/broken sources gracefully while updating valid online books',
    () async {
      final prevHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevHttpOverrides);

      final server = _M2LoopbackNovelServer()..enableUpdatedChapter = true;
      await server.start();
      final tempDir = await Directory.systemTemp.createTemp(
        'pureread_m2_update_skip_',
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
      final runtime = _createTestRuntime(pathResolver: resolver, database: db);
      final container = ProviderContainer(
        overrides: _overridesFromRuntime(runtime, _FakePlatformBridge()),
      );

      addTearDown(() async {
        container.dispose();
        await runtime.dispose();
        await server.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final gateway = container.read(sourceImportExportGatewayProvider);
      final sourceRepo = container.read(sourceRepositoryProvider);
      final bookRepo = container.read(bookRepositoryProvider);

      final parsed = await gateway.parseImportText(
        _buildJsPluginScript(server.baseUrl),
        fileName: 'js_plugin.js',
      );
      final validSource = parsed.sources.single;
      await sourceRepo.saveSource(validSource);

      final now = DateTime.utc(2026, 11, 25);
      await bookRepo.saveBook(
        Book(
          id: 'online-valid',
          sourceId: validSource.id,
          providerType: ProviderType.jsPlugin,
          originBookUrl: '${server.baseUrl}/js/book/100',
          tocUrl: '${server.baseUrl}/js/toc/100',
          title: '星海剑歌',
          author: '云中客',
          totalChapters: 6,
          unreadCount: 0,
          lastChapterTitle: '第六章 剑意初成',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await bookRepo.saveBook(
        Book(
          id: 'online-missing-source',
          sourceId: 'non_existent_source',
          providerType: ProviderType.legado,
          originBookUrl: '${server.baseUrl}/missing/book',
          tocUrl: '${server.baseUrl}/missing/toc',
          title: '断源之书',
          author: '无名',
          totalChapters: 3,
          unreadCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final shelfCtrl = container.read(bookshelfControllerProvider.notifier);
      container.read(bookshelfControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await shelfCtrl.checkUpdates();
      final state = container.read(bookshelfControllerProvider);

      expect(state.isCheckingUpdates, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.updateStatusMessage, contains('1 本书有新章节'));
      expect(state.updateStatusMessage, contains('1 本书源不可用已跳过'));

      final updatedValid = await bookRepo.getBookById('online-valid');
      final untouchedMissing = await bookRepo.getBookById('online-missing-source');
      expect(updatedValid?.totalChapters, 7);
      expect(updatedValid?.unreadCount, 1);
      expect(updatedValid?.lastChapterTitle, '第七章 沧海归途');
      expect(untouchedMissing?.totalChapters, 3);
      expect(untouchedMissing?.unreadCount, 0);
    },
  );
}
