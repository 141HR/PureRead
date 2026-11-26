import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_compat.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_explore_parser.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

class _ExploreMockServer {
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
    final method = req.method.toUpperCase();

    if (method == 'GET' && path == '/api/cats') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.text;
      req.response.write('玄幻::/rank/xuanhuan/{{page}}.html\n都市::/rank/dushi');
      await req.response.close();
      return;
    }

    if (method == 'GET' && path == '/rank/xuanhuan/1.html') {
      final customHdr = req.headers.value('x-explore-hdr') ?? '';
      if (customHdr != 'ok') {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html><body>
  <div class="explore-list">
    <div class="book-card">
      <a class="book-title" href="/book/1001">玄幻榜首</a>
      <span class="author">青莲剑仙</span>
      <img class="cover" src="/covers/1001.jpg"/>
      <p class="intro">一剑破万法。</p>
      <span class="latest">第999章 大结局</span>
      <span class="cat">玄幻</span>
    </div>
    <div class="book-card">
      <a class="book-title" href="/book/1002">问道长生</a>
      <span class="author">南宫月</span>
      <img class="cover" src="/covers/1002.jpg"/>
      <p class="intro">问道于天地之间。</p>
      <span class="latest">第120章 初出茅庐</span>
      <span class="cat">仙侠</span>
    </div>
  </div>
</body></html>
''');
      return;
    }

    if (method == 'GET' && path == '/rank/xuanhuan/2.html') {
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html><body>
  <div class="explore-list"></div>
</body></html>
''');
      return;
    }

    if (method == 'POST' && path == '/api/rank') {
      final body = await utf8.decoder.bind(req).join();
      final page = req.uri.queryParameters['page'] ?? '';
      if (!body.contains('type=hot') || !body.contains('p=$page')) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html><body>
  <ul class="search-list">
    <li>
      <a class="name" href="/book/2001">热榜第$page页</a>
      <span class="writer">辰风</span>
      <span class="latest">第10章 风起</span>
      <p class="desc">热门榜单第$page页书籍。</p>
      <span class="cat">热销</span>
    </li>
  </ul>
</body></html>
''');
      return;
    }

    if (method == 'GET' && path == '/rank/first') {
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html><body>
  <div class="search-list">
    <div>
      <a class="name" href="/book/3001">首页直达</a>
      <span class="writer">墨客</span>
    </div>
  </div>
</body></html>
''');
      return;
    }

    if (method == 'GET' && path == '/rank/page_2') {
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html><body>
  <div class="search-list">
    <div>
      <a class="name" href="/book/3002">第二页书目</a>
      <span class="writer">流年</span>
    </div>
  </div>
</body></html>
''');
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  void _writeHtml(HttpResponse resp, String html) {
    resp.statusCode = HttpStatus.ok;
    resp.headers.contentType = ContentType.html;
    resp.add(utf8.encode(html));
    resp.close();
  }
}

void main() {
  group('Domain explore contracts', () {
    test('ExploreCategory supports isGroupHeader, copyWith, equality, and toString', () {
      const header = ExploreCategory(title: '热门榜单', url: '  ');
      expect(header.isGroupHeader, isTrue);

      const cat = ExploreCategory(
        title: '玄幻',
        url: '/xuanhuan/{{page}}',
        group: '热门榜单',
        layoutFlexBasisPercent: 0.25,
      );
      expect(cat.isGroupHeader, isFalse);

      final copied = cat.copyWith(title: '奇幻', layoutFlexBasisPercent: 0.5);
      expect(copied.title, '奇幻');
      expect(copied.url, '/xuanhuan/{{page}}');
      expect(copied.group, '热门榜单');
      expect(copied.layoutFlexBasisPercent, 0.5);

      expect(
        cat,
        equals(
          const ExploreCategory(
            title: '玄幻',
            url: '/xuanhuan/{{page}}',
            group: '热门榜单',
            layoutFlexBasisPercent: 0.25,
          ),
        ),
      );
      expect(cat.hashCode, isNot(equals(copied.hashCode)));
      expect(cat.toString(), contains('ExploreCategory('));
    });

    test('ProviderCapabilities supportsExplore defaults to false and updates equality', () {
      const base = ProviderCapabilities(
        isLocal: false,
        supportsSearch: true,
        supportsUpdateCheck: true,
        supportsChangeSource: true,
      );
      const explicitFalse = ProviderCapabilities(
        isLocal: false,
        supportsSearch: true,
        supportsUpdateCheck: true,
        supportsChangeSource: true,
        supportsExplore: false,
      );
      const explicitTrue = ProviderCapabilities(
        isLocal: false,
        supportsSearch: true,
        supportsUpdateCheck: true,
        supportsChangeSource: true,
        supportsExplore: true,
      );

      expect(base.supportsExplore, isFalse);
      expect(base, equals(explicitFalse));
      expect(base.hashCode, equals(explicitFalse.hashCode));
      expect(base, isNot(equals(explicitTrue)));
      expect(explicitTrue.toString(), contains('supportsExplore: true'));
    });
  });

  group('LegadoExploreRule & LegadoBookSource', () {
    test('parses ruleExplore, enabledExplore, exploreUrl, features, and colonRegex without altering M3 classifySource', () {
      final source = LegadoBookSource.fromJson(<String, Object?>{
        'bookSourceName': '发现测试源',
        'bookSourceUrl': 'https://example.com',
        'bookSourceType': 0,
        'enabledExplore': true,
        'exploreUrl': '玄幻::/xuanhuan',
        'ruleExplore': <String, Object?>{
          'bookList': ':<li><a href="([^"]+)">([^<]+)</a></li>',
          'name': r'$2',
          'bookUrl': r'$1',
          'webView': true,
        },
      });

      expect(source.enabledExplore, isTrue);
      expect(source.hasExplore, isTrue);
      expect(source.ruleExplore.isEmpty, isFalse);
      expect(source.ruleExplore.webView, isTrue);

      final classification = LegadoSourceParser.classifySource(
        source,
        source.rawJson,
      );
      expect(classification.compatibility, LegadoCompatibilityStatus.supported);
      expect(classification.features, containsAll(<String>['exploreUrl', 'colonRegex']));

      final disabledBool = LegadoBookSource.fromJson(<String, Object?>{
        'bookSourceName': 'DisabledBool',
        'bookSourceUrl': 'https://example.com',
        'enabledExplore': false,
        'exploreUrl': '玄幻::/xuanhuan',
      });
      expect(disabledBool.enabledExplore, isFalse);
      expect(disabledBool.hasExplore, isFalse);

      final disabledString = LegadoBookSource.fromJson(<String, Object?>{
        'bookSourceName': 'DisabledStr',
        'bookSourceUrl': 'https://example.com',
        'enabledExplore': 'false',
        'exploreUrl': '玄幻::/xuanhuan',
      });
      expect(disabledString.enabledExplore, isFalse);
      expect(disabledString.hasExplore, isFalse);

      const emptyRule = LegadoExploreRule();
      expect(emptyRule.isEmpty, isTrue);
    });
  });

  group('LegadoExploreParser', () {
    test('parses strict and lenient JSON array formats with style and group headers', () {
      const strictJson = '''
[
  {"title": "热门榜单", "url": "", "style": {"layout_flexBasisPercent": 1}},
  {"title": "玄幻", "url": "/rank/xuanhuan", "style": {"layout_flexBasisPercent": 0.25}},
  {"title": "都市", "url": "/rank/dushi", "style": {"layout_flexBasisPercent": 0.5}}
]
''';
      final strictCats = LegadoExploreParser.parse(strictJson);
      expect(strictCats, hasLength(3));
      expect(strictCats[0].isGroupHeader, isTrue);
      expect(strictCats[0].layoutFlexBasisPercent, 1.0);
      expect(strictCats[1].title, '玄幻');
      expect(strictCats[1].url, '/rank/xuanhuan');
      expect(strictCats[1].group, '热门榜单');
      expect(strictCats[1].layoutFlexBasisPercent, 0.25);
      expect(strictCats[2].group, '热门榜单');
      expect(strictCats[2].layoutFlexBasisPercent, 0.5);

      const lenientJson = '''
[
  {title: '分类', url: '', style: {layout_flexBasisPercent: 1},},
  {title: '科幻', url: '/sci-fi', style: {layout_flexBasisPercent: 0.33},},
]
''';
      final lenientCats = LegadoExploreParser.parse(lenientJson);
      expect(lenientCats, hasLength(2));
      expect(lenientCats[0].isGroupHeader, isTrue);
      expect(lenientCats[1].title, '科幻');
      expect(lenientCats[1].group, '分类');
      expect(lenientCats[1].layoutFlexBasisPercent, 0.33);
    });

    test('parses && and \\n delimited entries without splitting && inside JSON options, quotes, or <js>', () {
      const raw = '''
排行榜::
日榜::/rank/day,{"method":"POST","body":"type=1&&page={{page}}"}&&周榜::/rank/week?a=1&b=2&&"A&&B"::/ab
男生频道
玄幻/奇幻
Reader's Pick::/pick&&脚本::<js>if(a&&b){"/1"}else{"/2"}</js>
''';
      final cats = LegadoExploreParser.parse(raw);
      expect(cats, hasLength(8));

      expect(cats[0].title, '排行榜');
      expect(cats[0].isGroupHeader, isTrue);

      expect(cats[1].title, '日榜');
      expect(
        cats[1].url,
        '/rank/day,{"method":"POST","body":"type=1&&page={{page}}"}',
      );
      expect(cats[1].group, '排行榜');

      expect(cats[2].title, '周榜');
      expect(cats[2].url, '/rank/week?a=1&b=2');
      expect(cats[2].group, '排行榜');

      expect(cats[3].title, '"A&&B"');
      expect(cats[3].url, '/ab');
      expect(cats[3].group, '排行榜');

      expect(cats[4].title, '男生频道');
      expect(cats[4].isGroupHeader, isTrue);

      expect(cats[5].title, '玄幻/奇幻');
      expect(cats[5].isGroupHeader, isTrue);

      expect(cats[6].title, "Reader's Pick");
      expect(cats[6].url, '/pick');
      expect(cats[6].group, '玄幻/奇幻');

      expect(cats[7].title, '脚本');
      expect(cats[7].url, '<js>if(a&&b){"/1"}else{"/2"}</js>');
      expect(cats[7].group, '玄幻/奇幻');
    });

    test('parses bare HTTP and relative URLs without :: as clickable 发现 category', () {
      final httpCats = LegadoExploreParser.parse('https://example.com/top');
      expect(httpCats, hasLength(1));
      expect(httpCats.first.isGroupHeader, isFalse);
      expect(httpCats.first.title, '发现');
      expect(httpCats.first.url, 'https://example.com/top');

      final relCats = LegadoExploreParser.parse(
        '/rank/{{page}}.html,{"headers":{"X-A":"1::2"}}',
      );
      expect(relCats, hasLength(1));
      expect(relCats.first.title, '发现');
      expect(relCats.first.url, '/rank/{{page}}.html,{"headers":{"X-A":"1::2"}}');

      expect(LegadoExploreParser.parse('   \n  '), isEmpty);
    });
  });

  group('LegadoCompatProvider explore', () {
    late _ExploreMockServer server;
    late SourceHttpClient httpClient;

    setUp(() async {
      server = _ExploreMockServer();
      await server.start();
      httpClient = SourceHttpClient();
    });

    tearDown(() async {
      httpClient.close();
      await server.close();
    });

    test('getExploreCategories caches results and evaluates <js> and @JS: rules', () async {
      final disabledProvider = LegadoCompatProvider(
        providerId: 'disabled-explore',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'Disabled',
          'bookSourceUrl': server.baseUrl,
          'enabledExplore': false,
          'exploreUrl': '玄幻::/rank/xuanhuan/1.html',
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );
      expect(disabledProvider.capabilities.supportsExplore, isFalse);
      final emptyRes = await disabledProvider.getExploreCategories();
      expect(emptyRes.categories, isEmpty);
      expect(emptyRes.trace.step, 'explore_categories');

      final jsAjaxProvider = LegadoCompatProvider(
        providerId: 'js-ajax-explore',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'JS Ajax Explore',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl': '<js>java.ajax("/api/cats")</js>',
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );
      expect(jsAjaxProvider.capabilities.supportsExplore, isTrue);
      final firstCall = await jsAjaxProvider.getExploreCategories();
      expect(firstCall.categories, hasLength(2));
      expect(firstCall.categories[0].title, '玄幻');
      expect(firstCall.categories[0].url, '/rank/xuanhuan/{{page}}.html');
      expect(firstCall.trace.step, 'explore_categories');

      // Second call uses per-instance cache.
      final secondCall = await jsAjaxProvider.getExploreCategories();
      expect(identical(firstCall.categories, secondCall.categories), isTrue);
      expect(secondCall.trace.matchedPreview, contains('cached'));

      // Case-insensitive @JS: returning JSON array must preserve all items.
      final jsJsonProvider = LegadoCompatProvider(
        providerId: 'js-json-explore',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'JS JSON Explore',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl':
              '@JS: JSON.stringify([{title:"热榜",url:"/api/rank"},{title:"完本",url:"/done"}])',
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );
      final jsonCats = await jsJsonProvider.getExploreCategories();
      expect(jsonCats.categories, hasLength(2));
      expect(jsonCats.categories[0].title, '热榜');
      expect(jsonCats.categories[1].title, '完本');
    });

    test('explore merges ruleExplore with ruleSearch fallback, supports POST/headers/page conditionals, and handles pagination end', () async {
      final provider = LegadoCompatProvider(
        providerId: 'explore-merge',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'Explore Merge',
          'bookSourceUrl': server.baseUrl,
          'header': '<js>JSON.stringify({"X-Explore-Hdr": "ok"})</js>',
          'exploreUrl': '''
分类::
玄幻::/rank/xuanhuan/{{page}}.html
热榜::/api/rank?page={{page}},{"method":"POST","body":"type=hot&p={{page}}"}
翻页::/rank/<first,page_{{page}}>
''',
          'ruleSearch': <String, Object?>{
            'bookList': '.search-list > div, .search-list > li',
            'name': '.name@text',
            'author': '.writer@text',
            'bookUrl': '.name@href',
            'intro': '.desc@text',
            'lastChapter': '.latest@text',
            'kind': '.cat@text',
          },
          'ruleExplore': <String, Object?>{
            'bookList': '.explore-list .book-card',
            'name': '.book-title@text',
            'author': '.author@text',
            'bookUrl': '.book-title@href',
            'coverUrl': '.cover@src',
            'intro': '.intro@text',
          },
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );

      final catRes = await provider.getExploreCategories();
      expect(catRes.categories, hasLength(4));
      final xuanhuan = catRes.categories[1];

      // Page 1 uses ruleExplore + falls back to ruleSearch for lastChapter & kind.
      final p1 = await provider.explore(xuanhuan, page: 1);
      expect(p1.trace.step, 'explore');
      expect(p1.items, hasLength(2));
      expect(p1.items.first.title, '玄幻榜首');
      expect(p1.items.first.author, '青莲剑仙');
      expect(p1.items.first.bookUrl, '${server.baseUrl}/book/1001');
      expect(p1.items.first.coverUrl, '${server.baseUrl}/covers/1001.jpg');
      expect(p1.items.first.latestChapterTitle, '第999章 大结局');
      expect(p1.items.first.kind, '玄幻');

      // Page 2 matches 0 blocks -> returns empty list cleanly instead of throwing.
      final p2 = await provider.explore(xuanhuan, page: 2);
      expect(p2.items, isEmpty);
      expect(p2.trace.step, 'explore');

      // Pure fallback to ruleSearch when ruleExplore is empty + POST request.
      final fallbackProvider = LegadoCompatProvider(
        providerId: 'explore-fallback',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'Explore Fallback',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl':
              '热榜::/api/rank?page={{page}},{"method":"POST","body":"type=hot&p={{page}}"}\n翻页::/rank/<first,page_{{page}}>',
          'ruleSearch': <String, Object?>{
            'bookList': '.search-list > div, .search-list > li',
            'name': '.name@text',
            'author': '.writer@text',
            'bookUrl': '.name@href',
            'intro': '.desc@text',
            'lastChapter': '.latest@text',
            'kind': '.cat@text',
          },
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );
      final fallbackCats = await fallbackProvider.getExploreCategories();
      final postRes = await fallbackProvider.explore(fallbackCats.categories[0], page: 3);
      expect(postRes.items, hasLength(1));
      expect(postRes.items.first.title, '热榜第3页');
      expect(postRes.items.first.author, '辰风');
      expect(postRes.items.first.kind, '热销');

      final condP1 = await fallbackProvider.explore(fallbackCats.categories[1], page: 1);
      expect(condP1.items.first.title, '首页直达');
      final condP2 = await fallbackProvider.explore(fallbackCats.categories[1], page: 2);
      expect(condP2.items.first.title, '第二页书目');
    });

    test('explore guards empty URL, empty bookList/0 blocks on page 1, webView, Rhino APIs, and cancellation', () async {
      final provider = LegadoCompatProvider(
        providerId: 'explore-guards',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'Guards',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl': '榜单::\n空页::/rank/xuanhuan/2.html',
          'ruleExplore': <String, Object?>{
            'bookList': '.explore-list .book-card',
            'name': '.book-title@text',
            'bookUrl': '.book-title@href',
          },
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );

      // Empty category URL (group header) -> SourceParseFailure(step: 'explore')
      await expectLater(
        () => provider.explore(const ExploreCategory(title: '榜单', url: '')),
        throwsA(
          isA<SourceParseFailure>().having((e) => e.step, 'step', 'explore'),
        ),
      );

      // Page 1 with 0 matched blocks -> SourceParseFailure(step: 'explore')
      await expectLater(
        () => provider.explore(
          const ExploreCategory(title: '空页', url: '/rank/xuanhuan/2.html'),
          page: 1,
        ),
        throwsA(
          isA<SourceParseFailure>().having((e) => e.step, 'step', 'explore'),
        ),
      );

      // Empty bookList on page 1 -> SourceParseFailure(step: 'explore')
      final noRuleProvider = LegadoCompatProvider(
        providerId: 'no-booklist',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'NoRule',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl': '排行::/rank/first',
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );
      await expectLater(
        () => noRuleProvider.explore(
          const ExploreCategory(title: '排行', url: '/rank/first'),
          page: 1,
        ),
        throwsA(
          isA<SourceParseFailure>().having((e) => e.step, 'step', 'explore'),
        ),
      );

      // ruleExplore.webView -> UnsupportedLegadoRuleFailure
      final webViewProvider = LegadoCompatProvider(
        providerId: 'wv-explore',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'WVExplore',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl': '排行::/rank/first',
          'ruleExplore': <String, Object?>{
            'webView': true,
            'bookList': 'div',
            'name': 'a@text',
            'bookUrl': 'a@href',
          },
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );
      await expectLater(
        () => webViewProvider.explore(
          const ExploreCategory(title: '排行', url: '/rank/first'),
        ),
        throwsA(
          isA<UnsupportedLegadoRuleFailure>().having(
            (e) => e.feature,
            'feature',
            'webView',
          ),
        ),
      );

      // Rhino Java API -> UnsupportedLegadoRuleFailure
      final rhinoProvider = LegadoCompatProvider(
        providerId: 'rhino-explore',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'RhinoExplore',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl': '排行::/rank/first',
          'ruleExplore': <String, Object?>{
            'bookList': 'div',
            'name': '<js>Packages.java.lang.System.currentTimeMillis()</js>',
            'bookUrl': 'a@href',
          },
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );
      await expectLater(
        () => rhinoProvider.explore(
          const ExploreCategory(title: '排行', url: '/rank/first'),
        ),
        throwsA(
          isA<UnsupportedLegadoRuleFailure>().having(
            (e) => e.feature,
            'feature',
            'rhino_java_api',
          ),
        ),
      );

      // CancellationToken
      final cancelled = CancellationToken()..cancel();
      await expectLater(
        () => provider.getExploreCategories(cancelToken: cancelled),
        throwsA(isA<CancelledFailure>()),
      );
      await expectLater(
        () => provider.explore(
          const ExploreCategory(title: '空页', url: '/rank/xuanhuan/2.html'),
          cancelToken: cancelled,
        ),
        throwsA(isA<CancelledFailure>()),
      );
    });

    test('preserves per-category <js> URLs in mixed text and JSON exploreUrl and evaluates them per-page in explore()', () async {
      final mixedTextProvider = LegadoCompatProvider(
        providerId: 'mixed-per-category-js',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'MixedPerCategoryJs',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl': '''
榜单::
静态::/rank/first
脚本::<js>page > 1 ? "/rank/page_2" : "/rank/first"</js>
''',
          'ruleExplore': <String, Object?>{
            'bookList': '.search-list > div',
            'name': '.name@text',
            'author': '.writer@text',
            'bookUrl': '.name@href',
          },
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );

      final textCats = await mixedTextProvider.getExploreCategories();
      expect(textCats.categories, hasLength(3));
      expect(textCats.categories[0].isGroupHeader, isTrue);
      expect(textCats.categories[1].url, '/rank/first');
      expect(
        textCats.categories[2].url,
        '<js>page > 1 ? "/rank/page_2" : "/rank/first"</js>',
      );

      final staticRes = await mixedTextProvider.explore(
        textCats.categories[1],
        page: 1,
      );
      expect(staticRes.items.single.title, '首页直达');

      final jsPage1 = await mixedTextProvider.explore(
        textCats.categories[2],
        page: 1,
      );
      expect(jsPage1.items.single.title, '首页直达');

      final jsPage2 = await mixedTextProvider.explore(
        textCats.categories[2],
        page: 2,
      );
      expect(jsPage2.items.single.title, '第二页书目');

      final jsonWithPerCatJsProvider = LegadoCompatProvider(
        providerId: 'json-per-category-js',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'JsonPerCategoryJs',
          'bookSourceUrl': server.baseUrl,
          'exploreUrl': jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'title': '动态页',
              'url': '<js>page > 1 ? "/rank/page_2" : "/rank/first"</js>',
            },
            <String, Object?>{
              'title': '静态页',
              'url': '/rank/first',
            },
          ]),
          'ruleExplore': <String, Object?>{
            'bookList': '.search-list > div',
            'name': '.name@text',
            'author': '.writer@text',
            'bookUrl': '.name@href',
          },
        }),
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );

      final jsonCats = await jsonWithPerCatJsProvider.getExploreCategories();
      expect(jsonCats.categories, hasLength(2));
      expect(
        jsonCats.categories[0].url,
        '<js>page > 1 ? "/rank/page_2" : "/rank/first"</js>',
      );
      final jsonDynamicP2 = await jsonWithPerCatJsProvider.explore(
        jsonCats.categories[0],
        page: 2,
      );
      expect(jsonDynamicP2.items.single.title, '第二页书目');
    });
  });
}
