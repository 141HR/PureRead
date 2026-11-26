import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/app/app.dart';
import 'package:pureread/app/providers.dart';
import 'package:pureread/application/bookshelf/bookshelf_controller.dart';
import 'package:pureread/application/explore/explore_controller.dart';
import 'package:pureread/application/reader/reader_session_controller.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/database/database.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/infrastructure/storage/chapter_cache_store.dart';
import 'package:pureread/infrastructure/storage/storage.dart';
import 'package:pureread/presentation/explore/explore_page.dart';
import 'package:pureread/presentation/reader/reader_page.dart';
import 'package:pureread/presentation/reader/reader_page_turn_view.dart';

class _FakePlatformBridge implements PlatformBridge {
  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async => const <String>[];

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

class _ExploreLoopbackServer {
  HttpServer? _server;
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
    final page = req.uri.queryParameters['page'] ?? '1';
    requestedPaths.add('$path?page=$page');

    if (req.method == 'GET' && path == '/rank/hot') {
      if (page == '1') {
        _writeHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>热门总榜</title></head>
<body>
  <ul class="explore-list">
    <li class="rank-item">
      <a class="book-title" href="/book/101">《星海问道》</a>
      <span class="author">云中客</span>
      <span class="kind">仙侠</span>
      <span class="latest">第2章 剑鸣星海</span>
      <p class="intro">热门总榜第一名，星海漫游，问道苍穹。</p>
    </li>
    <li class="rank-item">
      <a class="book-title" href="/book/102">《青莲剑歌》</a>
      <span class="author">南宫月</span>
      <span class="kind">玄幻</span>
      <span class="latest">第80章 剑意初鸣</span>
      <p class="intro">热门总榜第二名，一剑破万法。</p>
    </li>
  </ul>
</body>
</html>
''');
        return;
      }
      if (page == '2') {
        _writeHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>热门总榜第2页</title></head>
<body>
  <ul class="explore-list">
    <li class="rank-item">
      <a class="book-title" href="/book/103">《沧海长歌》</a>
      <span class="author">陆沉</span>
      <span class="kind">历史</span>
      <span class="latest">第50章 潮起</span>
      <p class="intro">第2页新增榜单书目。</p>
    </li>
  </ul>
</body>
</html>
''');
        return;
      }
      _writeHtml(req.response, '<html><body><ul class="explore-list"></ul></body></html>');
      return;
    }

    if (req.method == 'GET' && path == '/rank/new') {
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>新书潜力榜</title></head>
<body>
  <ul class="explore-list">
    <li class="rank-item">
      <a class="book-title" href="/book/201">《新秀风云》</a>
      <span class="author">听雨</span>
      <span class="kind">都市</span>
      <span class="latest">第15章 扬帆</span>
      <p class="intro">新书潜力榜首。</p>
    </li>
  </ul>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path == '/book/101') {
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>星海问道</title></head>
<body>
  <div id="info">
    <h1>星海问道</h1>
    <div class="author">云中客</div>
    <p class="intro">热门总榜第一名，星海漫游，问道苍穹。</p>
    <a id="toc" href="/toc/101">查看目录</a>
  </div>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path == '/toc/101') {
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>目录</title></head>
<body>
  <ul class="toc-list">
    <li><a href="/ch/0">第1章 风起青萍</a></li>
    <li><a href="/ch/1">第2章 剑鸣星海</a></li>
  </ul>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path.startsWith('/ch/')) {
      final idx = int.tryParse(path.substring('/ch/'.length));
      if (idx == 0 || idx == 1) {
        final paragraphs = List<String>.generate(
          8,
          (i) =>
              '<p>星海问道第${idx! + 1}章第${i + 1}段：风起青萍之末，云中客踏浪而来，'
              '验证发现排行榜端到端阅读渲染流程。</p>',
        ).join('\n');
        _writeHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>第${idx! + 1}章</title></head>
<body>
  <div id="content">
    <p>星海问道第${idx + 1}章正文开始</p>
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

  void _writeHtml(HttpResponse resp, String html) {
    resp.statusCode = HttpStatus.ok;
    resp.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
    resp.add(utf8.encode(html));
    resp.close();
  }
}

String _buildExploreLegadoSourceJson(String baseUrl) =>
    jsonEncode(<String, Object?>{
      'bookSourceName': '星海Legado发现源',
      'bookSourceUrl': baseUrl,
      'bookSourceGroup': 'E2E发现',
      'bookSourceType': 0,
      'weight': 100,
      'concurrentRate': '0',
      'enabledExplore': true,
      'exploreUrl':
          '榜单推荐::\n热门总榜::/rank/hot?page={{page}}\n新书潜力榜::/rank/new?page={{page}}',
      'ruleExplore': <String, Object?>{
        'bookList': 'class.explore-list@tag.li',
        'name': 'a.book-title@text##《|》##',
        'author': 'span.author@text',
        'bookUrl': 'a.book-title@href',
        'kind': 'span.kind@text',
        'lastChapter': 'span.latest@text',
        'intro': 'p.intro@text',
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
    'Timed out waiting for condition'
    '${label != null ? ' ($label)' : ''}.',
  );
}

void main() {
  testWidgets(
    'Explore E2E: Legado exploreUrl + ruleExplore -> 发现 tab -> rankings -> detail + TOC -> add to bookshelf -> ReaderPage renders chapter content',
    (tester) async {
      final prevHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevHttpOverrides);

      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('pureread_explore_e2e_'),
      );
      expect(tempDir, isNotNull);

      final server = _ExploreLoopbackServer();
      await tester.runAsync(server.start);

      final pathResolver = AppPathResolver.fromRoots(
        dataRootDir: Directory(p.join(tempDir!.path, 'data')),
        cacheRootDir: Directory(p.join(tempDir.path, 'cache')),
      );
      await tester.runAsync(pathResolver.ensureDirectoriesExist);

      final db = AppDatabase.inMemory();
      final httpClient = SourceHttpClient();
      final txtWorker = TxtIsolateWorker();
      final txtProvider = LocalTxtProvider(worker: txtWorker);
      final cacheStore = ChapterCacheStore(pathResolver);
      final providerFactory = BookProviderFactory(httpClient: httpClient);
      const importService = SourceImportExportService();

      addTearDown(() async {
        httpClient.close();
        await txtProvider.dispose();
        await txtWorker.dispose();
        await db.close();
        await server.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      // Import and persist Legado explore source into in-memory Drift DB.
      await tester.runAsync(() async {
        final imported = await importService.importFromText(
          _buildExploreLegadoSourceJson(server.baseUrl),
          fileName: 'legado_explore.json',
        );
        expect(imported.sources, hasLength(1));
        await DriftSourceRepository(db).saveSources(imported.sources);
      });

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildPureReadOverrides(
            database: db,
            pathResolver: pathResolver,
            localTxtProvider: txtProvider,
            platformBridge: _FakePlatformBridge(),
            sourceHttpClient: httpClient,
            chapterCacheStore: cacheStore,
            bookProviderFactory: providerFactory,
            sourceImportExportService: importService,
          ),
          child: const PureReadApp(),
        ),
      );
      await _pumpUntil(
        tester,
        () => !ProviderScope.containerOf(
          tester.element(find.byType(PureReadApp)),
          listen: false,
        ).read(bookshelfControllerProvider).isLoading,
        label: 'bookshelf-init',
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PureReadApp)),
        listen: false,
      );

      // 1. Open 发现 tab and verify grouped categories & ranked books load via LegadoCompatProvider.
      await tester.tap(find.text('发现').last);
      await _pumpUntil(
        tester,
        () {
          final eState = container.read(exploreControllerProvider);
          return find.byType(ExplorePage).evaluate().isNotEmpty &&
              !eState.isLoadingSources &&
              !eState.isLoadingCategories &&
              !eState.isLoadingBooks &&
              eState.items.length == 2;
        },
        label: 'explore-initial-rankings',
      );

      expect(find.text('星海Legado发现源'), findsOneWidget);
      expect(find.text('榜单推荐'), findsOneWidget);
      expect(find.text('热门总榜'), findsOneWidget);
      expect(find.text('新书潜力榜'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('星海问道'), findsOneWidget);
      expect(find.text('青莲剑歌'), findsOneWidget);

      // Verify pagination 加载更多 fetches page 2 from loopback server.
      await tester.scrollUntilVisible(
        find.text('加载更多'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('加载更多'));
      await _pumpUntil(
        tester,
        () =>
            !container.read(exploreControllerProvider).isLoadingMore &&
            container.read(exploreControllerProvider).items.length == 3,
        label: 'explore-page-2',
      );
      expect(find.text('沧海长歌'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);

      // Switch category to 新书潜力榜 and back to 热门总榜.
      await tester.tap(find.text('新书潜力榜'));
      await _pumpUntil(
        tester,
        () =>
            !container.read(exploreControllerProvider).isLoadingBooks &&
            find.text('新秀风云').evaluate().isNotEmpty,
        label: 'explore-switch-category',
      );
      await tester.tap(find.text('热门总榜'));
      await _pumpUntil(
        tester,
        () =>
            !container.read(exploreControllerProvider).isLoadingBooks &&
            find.text('星海问道').evaluate().isNotEmpty,
        label: 'explore-back-to-hot',
      );

      // 2. Select ranked book and verify detail + TOC preview load in isolated exploreBookDetailControllerProvider.
      await tester.tap(find.text('星海问道'));
      await _pumpUntil(
        tester,
        () {
          final detail = container.read(exploreBookDetailControllerProvider);
          return !detail.isBusy && detail.chapters.length == 2;
        },
        label: 'explore-book-detail-and-toc',
      );
      expect(find.text('目录预览 (2 章)'), findsOneWidget);
      expect(find.text('第1章 风起青萍'), findsOneWidget);
      expect(find.text('第2章 剑鸣星海'), findsOneWidget);

      // 3. Tap 加入书架 and verify persistence + UI update.
      await tester.tap(find.text('加入书架'));
      await _pumpUntil(
        tester,
        () =>
            !container
                .read(exploreBookDetailControllerProvider)
                .isSavingToShelf &&
            container.read(exploreBookDetailControllerProvider).isOnBookshelf,
        label: 'explore-add-to-bookshelf',
      );
      expect(find.text('已在书架'), findsOneWidget);
      expect(find.text('继续阅读'), findsOneWidget);

      final savedBook = container
          .read(exploreBookDetailControllerProvider)
          .existingBookshelfBook;
      expect(savedBook, isNotNull);
      expect(savedBook!.title, '星海问道');

      // 4. Tap 继续阅读 -> navigate to ReaderPage -> verify chapter content rendered!
      await tester.tap(find.text('继续阅读'));
      await _pumpUntil(
        tester,
        () {
          if (find.byType(ReaderPage).evaluate().isEmpty) return false;
          final rState = container.read(
            readerSessionControllerProvider(savedBook.id),
          );
          return !rState.isLoading &&
              !rState.isPaginating &&
              rState.currentPages.isNotEmpty;
        },
        label: 'open-reader-from-explore',
      );

      expect(find.byType(ReaderPage), findsOneWidget);
      expect(find.byType(ReaderPageTurnView), findsOneWidget);
      final readerState = container.read(
        readerSessionControllerProvider(savedBook.id),
      );
      expect(readerState.currentChapterIndex, 0);
      expect(readerState.currentChapterText, contains('星海问道第1章正文开始'));
      expect(readerState.currentChapterText, contains('风起青萍之末'));
      expect(
        readerState.currentPages.first.lines
            .map((line) => line.text)
            .join(),
        contains('星海问道第1章正文开始'),
      );
      expect(tester.takeException(), isNull);

      // Cleanly unmount widget tree and drain HttpClient idle timers before tearDown.
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        httpClient.close();
        await server.close();
      });
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
