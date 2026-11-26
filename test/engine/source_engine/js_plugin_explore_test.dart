import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/js_plugin/js_plugin_provider.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

class _MockJsExploreServer {
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
    final path = req.uri.path;
    if (req.method == 'GET' && path == '/api/explore/cats') {
      _writeJson(req.response, <Map<String, Object?>>[
        <String, Object?>{'title': '热门分类', 'url': ''},
        <String, Object?>{
          'title': '玄幻奇幻',
          'url': '/rank/xuanhuan',
          'layoutFlexBasisPercent': 0.25,
        },
        <String, Object?>{
          'title': '科幻未来',
          'url': '/rank/scifi',
          'style': <String, Object?>{'layout_flexBasisPercent': 0.5},
        },
      ]);
      return;
    }

    if (req.method == 'GET' && path == '/rank/xuanhuan') {
      final page = req.uri.queryParameters['page'] ?? '1';
      final title = req.uri.queryParameters['title'] ?? '';
      _writeJson(req.response, <String, Object?>{
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'title': '$title-第$page页-剑来',
            'author': '烽火',
            'bookUrl': '/book/1',
            'coverUrl': '/cover/1.jpg',
            'intro': '大千世界。',
            'latestChapterTitle': '第100章 问剑',
            'kind': title,
          },
        ],
      });
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  void _writeJson(HttpResponse resp, Object payload) {
    resp.statusCode = HttpStatus.ok;
    resp.headers.contentType = ContentType.json;
    resp.add(utf8.encode(jsonEncode(payload)));
    resp.close();
  }
}

void main() {
  late _MockJsExploreServer server;
  late SourceHttpClient httpClient;

  setUp(() async {
    server = _MockJsExploreServer();
    await server.start();
    httpClient = SourceHttpClient();
  });

  tearDown(() async {
    httpClient.close();
    await server.close();
  });

  JsPluginProvider buildProvider(String script) {
    return JsPluginProvider(
      providerId: 'js-explore-test',
      sourceName: 'JS Explore',
      baseUrl: server.baseUrl,
      pluginScript: script,
      httpClient: httpClient,
      rateLimitMs: 0,
    );
  }

  group('JsPluginProvider static explore detection', () {
    test('detects explore support across function, CommonJS, globalThis, and ignores comments/strings', () {
      final noExplore = buildProvider('''
        // async function exploreCategories() { return []; }
        /* module.exports = { explore() {} }; */
        const note = "explore books online";
        async function search(keyword, page) { return []; }
        async function detail(url) { return { title: "a" }; }
        async function toc(url) { return []; }
        async function content(url) { return { text: "t" }; }
      ''');
      expect(noExplore.capabilities.supportsExplore, isFalse);

      final topLevelFn = buildProvider('''
        async function exploreCategories() { return []; }
        async function explore(url, page, title) { return []; }
      ''');
      expect(topLevelFn.capabilities.supportsExplore, isTrue);

      final cjsShorthand = buildProvider('''
        module.exports = {
          async exploreCategories() { return []; },
          async explore(url, page, title) { return []; }
        };
      ''');
      expect(cjsShorthand.capabilities.supportsExplore, isTrue);

      final exportsAssign = buildProvider('''
        exports.explore = async (url, page, title) => [];
      ''');
      expect(exportsAssign.capabilities.supportsExplore, isTrue);

      final globalPlugin = buildProvider('''
        globalThis.plugin = {
          exploreCategories: async function() { return []; }
        };
      ''');
      expect(globalPlugin.capabilities.supportsExplore, isTrue);

      final constArrow = buildProvider('''
        const explore = async (url, page, title) => [];
      ''');
      expect(constArrow.capabilities.supportsExplore, isTrue);
    });
  });

  group('JsPluginProvider explore execution', () {
    test('getExploreCategories decodes JSON array and explore passes [url, page, title]', () async {
      final provider = buildProvider(r'''
        async function exploreCategories() {
          const resp = await host.httpGet("/api/explore/cats");
          return JSON.parse(resp.body);
        }

        async function explore(url, page, title) {
          host.log("explore:" + url + ":" + page + ":" + title);
          const resp = await host.httpGet(url + "?page=" + page + "&title=" + encodeURIComponent(title));
          return JSON.parse(resp.body).items;
        }

        async function search(keyword, page) { return []; }
        async function detail(url) { return { title: "t" }; }
        async function toc(url) { return []; }
        async function content(url) { return { text: "t" }; }
      ''');

      expect(provider.capabilities.supportsExplore, isTrue);

      final catsRes = await provider.getExploreCategories();
      expect(catsRes.trace.step, 'explore_categories');
      expect(catsRes.trace.httpStatus, 200);
      expect(catsRes.categories, hasLength(3));
      expect(catsRes.categories[0].isGroupHeader, isTrue);
      expect(catsRes.categories[0].title, '热门分类');
      expect(catsRes.categories[1].title, '玄幻奇幻');
      expect(catsRes.categories[1].group, '热门分类');
      expect(catsRes.categories[1].layoutFlexBasisPercent, 0.25);
      expect(catsRes.categories[2].layoutFlexBasisPercent, 0.5);

      final exploreRes = await provider.explore(catsRes.categories[1], page: 2);
      expect(exploreRes.trace.step, 'explore');
      expect(exploreRes.trace.httpStatus, 200);
      expect(exploreRes.trace.logs, contains('explore:/rank/xuanhuan:2:玄幻奇幻'));
      expect(exploreRes.items, hasLength(1));
      final book = exploreRes.items.first;
      expect(book.title, '玄幻奇幻-第2页-剑来');
      expect(book.author, '烽火');
      expect(book.bookUrl, '${server.baseUrl}/book/1');
      expect(book.coverUrl, '${server.baseUrl}/cover/1.jpg');
      expect(book.latestChapterTitle, '第100章 问剑');
      expect(book.kind, '玄幻奇幻');
    });

    test('getExploreCategories parses delimited Legado-style string via LegadoExploreParser', () async {
      final provider = buildProvider(r'''
        module.exports = {
          async exploreCategories() {
            return "排行榜::\n热榜::/rank/hot&&完本::/rank/done";
          },
          async explore(url, page, title) {
            return [{ title: title + ":" + page, bookUrl: url }];
          }
        };
      ''');

      final catsRes = await provider.getExploreCategories();
      expect(catsRes.categories, hasLength(3));
      expect(catsRes.categories[0].isGroupHeader, isTrue);
      expect(catsRes.categories[1].title, '热榜');
      expect(catsRes.categories[1].group, '排行榜');
      expect(catsRes.categories[2].url, '/rank/done');

      final exploreRes = await provider.explore(catsRes.categories[1], page: 3);
      expect(exploreRes.items.single.title, '热榜:3');
      expect(exploreRes.items.single.bookUrl, '${server.baseUrl}/rank/hot');
    });

    test('maps errors and cancellation cleanly in explore methods', () async {
      final badProvider = buildProvider(r'''
        module.exports = {
          async exploreCategories() {
            return { unexpected: true };
          },
          async explore(url, page, title) {
            await host.httpGet("/missing");
            return [];
          }
        };
      ''');

      await expectLater(
        badProvider.getExploreCategories,
        throwsA(
          isA<SourceParseFailure>().having(
            (e) => e.step,
            'step',
            'explore_categories',
          ),
        ),
      );

      await expectLater(
        () => badProvider.explore(const ExploreCategory(title: '组', url: '')),
        throwsA(
          isA<SourceParseFailure>().having((e) => e.step, 'step', 'explore'),
        ),
      );

      await expectLater(
        () => badProvider.explore(
          const ExploreCategory(title: '缺失', url: '/missing'),
        ),
        throwsA(
          isA<NetworkFailure>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );

      final missingMethodProvider = buildProvider('''
        async function search() { return []; }
      ''');
      await expectLater(
        missingMethodProvider.getExploreCategories,
        throwsA(isA<JsExecutionFailure>()),
      );

      final cancelled = CancellationToken()..cancel();
      await expectLater(
        () => badProvider.getExploreCategories(cancelToken: cancelled),
        throwsA(isA<CancelledFailure>()),
      );
      await expectLater(
        () => badProvider.explore(
          const ExploreCategory(title: '正常', url: '/rank/xuanhuan'),
          cancelToken: cancelled,
        ),
        throwsA(isA<CancelledFailure>()),
      );
    });
  });
}
