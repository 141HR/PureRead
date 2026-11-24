import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_compat.dart';
import 'package:pureread/engine/source_engine/parsing/legado_selector_engine.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

class _MockLegadoServer {
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

    if (method == 'POST' && path == '/gbk/search') {
      final body = await utf8.decoder.bind(req).join();
      final token = req.headers.value('x-client-token');
      // Expect GBK URL-encoded '剑来' -> %BD%A3%C0%B4
      if (token != 'pureread-m2' || !body.contains('searchkey=%BD%A3%C0%B4')) {
        req.response.statusCode = HttpStatus.forbidden;
        req.response.write('bad token or body=$body');
        await req.response.close();
        return;
      }
      _writeGbk(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>搜索</title></head>
<body>
  <div id="main">
    <ul>
      <li class="header-row">书名/作者</li>
      <li class="book-row">
        <a class="name" href="/gbk/book/202">剑来青冥【测试】</a>
        <span class="author">作者：风起青萍</span>
        <span class="latest">最新：第二章 问剑山巅</span>
        <p class="intro">山河万里，一剑可平。</p>
      </li>
    </ul>
  </div>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/gbk/book/202') {
      _writeGbk(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>剑来青冥</title></head>
<body>
  <div id="info">
    <h1>剑来青冥</h1>
    <div class="writer">风起青萍</div>
    <div class="summary">少年背剑出青冥，斩破长夜迎朝霞。</div>
    <a id="all-chapters" href="/gbk/toc/202/1">全部章节</a>
  </div>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/gbk/book/202/extra') {
      _writeGbk(req.response, '<span id="extra-tag">东方玄幻</span>');
      return;
    }

    if (method == 'GET' && path == '/gbk/toc/202/1') {
      _writeGbk(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>目录1</title></head>
<body>
  <dl class="chapter-dl">
    <dd><a href="/gbk/chapter/1_1">第一章 初入山门</a></dd>
  </dl>
  <a href="/gbk/toc/202/2">下一页</a>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/gbk/toc/202/2') {
      _writeGbk(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>目录2</title></head>
<body>
  <dl class="chapter-dl">
    <dd><a href="/gbk/chapter/2">第二章 问剑山巅</a></dd>
  </dl>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/gbk/chapter/1_1') {
      _writeGbk(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>第一章</title></head>
<body>
  <div id="content">
    第一章 初入山门<br/>
    山风拂过石阶，带来松涛阵阵！<br/>
    【广告：测试推广请忽略】
  </div>
  <a href="/gbk/chapter/1_2">下一页</a>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/gbk/chapter/1_2') {
      _writeGbk(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>第一章(2)</title></head>
<body>
  <div id="content">
    少年抬头望向山门匾额，“原来这里便是青冥宗。”<br/>
    请收藏本站：http://example.local
  </div>
</body>
</html>
''');
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  void _writeGbk(HttpResponse resp, String html) {
    resp.statusCode = HttpStatus.ok;
    resp.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=gbk');
    resp.add(gbk.encode(html));
    resp.close();
  }
}

void main() {
  group('LegadoSelectorEngine', () {
    test('supports CSS, @css:, Legado chained rules, !exclusions, children, text., XPath, JSONPath, combinators, and ##regex', () {
      const html = '''
      <html><body>
        <div id="main">
          <ul class="list">
            <li class="row"><span>Header</span></li>
            <li class="row"><a href="/b/1">书名A（精校）</a><i>作者甲</i></li>
            <li class="row"><a href="/b/2">书名B</a><i>作者乙</i></li>
            <li class="row"><span>Footer</span></li>
          </ul>
        </div>
        <div class="pager"><a href="/next">下一页</a></div>
        <div id="txt">Direct Line<span>Child</span></div>
      </body></html>
      ''';

      // Chained class/tag/!exclusion/index
      expect(
        LegadoSelectorEngine.selectElements(html, 'id.main@class.list@children!0:-1'),
        hasLength(2),
      );
      expect(
        LegadoSelectorEngine.selectValues(html, 'id.main@class.row.1@tag.a.0@text##（(.*?)）##[\$1]###'),
        ['书名A[精校]'],
      );
      expect(
        LegadoSelectorEngine.selectOne(html, 'text.下一页@href'),
        '/next',
      );
      expect(
        LegadoSelectorEngine.selectOne(html, '@css:#txt@ownText'),
        'Direct Line',
      );

      // XPath
      expect(
        LegadoSelectorEngine.selectValues(html, '@XPath://li[@class="row"]/a/@href'),
        ['/b/1', '/b/2'],
      );

      // JSONPath + combinators
      const jsonDoc = '{"a":[{"n":"一"},{"n":"二"}],"b":[{"n":"甲"},{"n":"乙"}]}';
      expect(
        LegadoSelectorEngine.selectValues(jsonDoc, r'$.missing[*]||$.a[*].n'),
        ['一', '二'],
      );
      expect(
        LegadoSelectorEngine.selectValues(jsonDoc, r'$.a[*].n&&$.b[*].n'),
        ['一', '二', '甲', '乙'],
      );
      expect(
        LegadoSelectorEngine.selectValues(jsonDoc, r'$.a[*].n%%$.b[*].n'),
        ['一', '甲', '二', '乙'],
      );
    });
  });

  group('LegadoCompatProvider & Registry', () {
    late _MockLegadoServer server;
    late SourceHttpClient httpClient;

    setUp(() async {
      server = _MockLegadoServer();
      await server.start();
      httpClient = SourceHttpClient();
    });

    tearDown(() async {
      httpClient.close();
      await server.close();
    });

    test('executes POST+GBK+fragment-URL+nextTocUrl+nextContentUrl+replaceRegex+<js> pipeline', () async {
      final rawJson = jsonEncode(<String, Object?>{
        'bookSourceName': '青冥书阁',
        'bookSourceUrl': '${server.baseUrl}#🎃',
        'bookSourceGroup': '精选',
        'bookSourceType': 0,
        'charset': 'GBK',
        'header': '<js>JSON.stringify({"X-Client-Token": "pureread-m2"})</js>',
        'searchUrl':
            '{{cookie.removeCookie(source.getKey())}}/gbk/search,{ method: "POST", body: "searchkey={{key}}&page={{page}}", charset: "GBK" }',
        'ruleSearch': <String, Object?>{
          'bookList': 'id.main@tag.li!0',
          'name': 'a.name@text##【测试】##',
          'author': 'span.author@text##^作者：##',
          'bookUrl': 'a.name@href',
          'intro': 'p.intro@text',
          'lastChapter': 'span.latest@text##^最新：##',
        },
        'ruleBookInfo': <String, Object?>{
          'init': '@put:{n:"id.info@tag.h1@text", a:"#info .writer@text"}',
          'name': '@get:{n}',
          'author': '@get:{a}',
          'intro': '#info .summary@text',
          'kind': '<js>var extra = java.ajax("/gbk/book/202/extra"); java.setContent(extra); java.getString("id.extra-tag@text")</js>',
          'tocUrl': '#all-chapters@href',
        },
        'ruleToc': <String, Object?>{
          'chapterList': 'class.chapter-dl@tag.dd',
          'chapterName': 'a@text<js>java.toNumChapter(result)</js>',
          'chapterUrl': 'a@href',
          'nextTocUrl': 'text.下一页@href',
        },
        'ruleContent': <String, Object?>{
          'content':
              r'#content@html##【广告：.*?】##'
              '\n'
              r'<js>result.replace(/请收藏本站：.*$/m, "").trim()</js>',
          'nextContentUrl': 'text.下一页@href',
          'replaceRegex': '##{{chapter.title}}##',
        },
      });

      final batch = await LegadoSourceParser.parseBatch(rawJson, useIsolate: false);
      expect(batch.totalCount, 1);
      expect(batch.fragmentTaggedCount, 1);
      expect(batch.supportedCount, 1);

      final factory = BookProviderFactory(httpClient: httpClient);
      final provider = factory.createProvider(batch.items.first.domainSource);
      expect(provider, isA<LegadoCompatProvider>());

      final searchRes = await provider.search('剑来', page: 1);
      expect(searchRes.items, hasLength(1));
      expect(searchRes.items.first.title, '剑来青冥');
      expect(searchRes.items.first.author, '风起青萍');
      expect(searchRes.items.first.bookUrl, '${server.baseUrl}/gbk/book/202');

      final detailRes = await provider.getBookDetail(searchRes.items.first.bookUrl);
      expect(detailRes.detail.title, '剑来青冥');
      expect(detailRes.detail.kind, '东方玄幻');
      expect(detailRes.detail.tocUrl, '${server.baseUrl}/gbk/toc/202/1');

      final tocRes = await provider.getToc(detailRes.detail.tocUrl);
      expect(tocRes.chapters, hasLength(2));
      expect(tocRes.chapters[0].title, '第1章 初入山门');
      expect(tocRes.chapters[1].title, '第2章 问剑山巅');

      final contentRes = await provider.getChapterContent(tocRes.chapters[0]);
      expect(contentRes.content.rawText, contains('山风拂过石阶，带来松涛阵阵！'));
      expect(contentRes.content.rawText, contains('原来这里便是青冥宗。'));
      expect(contentRes.content.rawText, isNot(contains('广告')));
      expect(contentRes.content.rawText, isNot(contains('请收藏本站')));
      expect(contentRes.content.rawText, isNot(contains('第1章 初入山门')));
    });

    test('executes expanded java.*, cookie.*, and source.* host APIs inside <js>', () async {
      final evaluator = LegadoRuleEvaluator(
        sourceId: 'api-test',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'API测试源',
          'bookSourceUrl': '${server.baseUrl}#tag',
        }),
        httpClient: httpClient,
      );
      await httpClient.setCookie('${server.baseUrl}/', 'uid=u99');

      final session = LegadoEvalSession(sourceVariable: 'init-var');
      final out = await evaluator.evaluateString(
        '<div class="item"><span>alpha</span></div>',
        '''
        <js>
        java.put("k", "v");
        source.setVariable("next-var");
        java.log("logged");
        java.toast("toasted");
        const ck = cookie.getKey(source.getKey(), "uid");
        const fullCk = cookie.getCookie(source.bookSourceUrl);
        cookie.removeCookie(source.key);
        const elem = java.getElement(".item");
        const elems = java.getElements(".item span");
        JSON.stringify({
          v: java.get("k"),
          m32: java.md5Encode("abc"),
          m16: java.md5Encode16("abc"),
          b64: java.base64Decode(java.base64Encode("净读")),
          ts: java.timeFormat(0).length,
          num: java.toNumChapter("第二十三章 归来"),
          ck,
          fullCk,
          srcVar: source.getVariable(),
          elemLen: elem.length > 0,
          elemsLen: elems.length,
        });
        </js>
        ''',
        baseUrl: server.baseUrl,
        session: session,
      );

      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['v'], 'v');
      expect(decoded['m32'], '900150983cd24fb0d6963f7d28e17f72');
      expect(decoded['m16'], '3cd24fb0d6963f7d');
      expect(decoded['b64'], '净读');
      expect(decoded['ts'], 19);
      expect(decoded['num'], '第23章 归来');
      expect(decoded['ck'], 'u99');
      expect(decoded['fullCk'], 'uid=u99');
      expect(decoded['srcVar'], 'next-var');
      expect(decoded['elemLen'], isTrue);
      expect(decoded['elemsLen'], 1);
      expect(session.logs, contains('logged'));
      expect(session.logs, contains('[toast] toasted'));
      expect(await httpClient.getCookie(server.baseUrl), isEmpty);
    });

    test('returns UnsupportedLegadoRuleFailure for webView, startBrowserAwait, and Rhino Packages', () async {
      final webViewProvider = LegadoCompatProvider(
        providerId: 'wv',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'WV',
          'bookSourceUrl': server.baseUrl,
          'webView': true,
          'searchUrl': '/gbk/search',
        }),
        httpClient: httpClient,
      );
      await expectLater(
        () => webViewProvider.search('x'),
        throwsA(
          isA<UnsupportedLegadoRuleFailure>()
              .having((e) => e.feature, 'feature', 'webView'),
        ),
      );

      final browserProvider = LegadoCompatProvider(
        providerId: 'browser',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'Browser',
          'bookSourceUrl': server.baseUrl,
          'searchUrl': '<js>java.startBrowserAwait("https://a.b","")</js>',
        }),
        httpClient: httpClient,
      );
      await expectLater(
        () => browserProvider.search('x'),
        throwsA(
          isA<UnsupportedLegadoRuleFailure>()
              .having((e) => e.feature, 'feature', 'webView'),
        ),
      );

      final rhinoProvider = LegadoCompatProvider(
        providerId: 'rhino',
        source: LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'Rhino',
          'bookSourceUrl': server.baseUrl,
          'searchUrl': '/gbk/search',
          'ruleSearch': <String, Object?>{
            'bookList': 'div.book-row',
            'name': 'a@text<js>Packages.java.lang.System.currentTimeMillis()</js>',
            'bookUrl': 'a@href',
          },
        }),
        httpClient: httpClient,
      );
      await expectLater(
        () => rhinoProvider.search('x'),
        throwsA(
          isA<UnsupportedLegadoRuleFailure>()
              .having((e) => e.feature, 'feature', 'rhino_java_api'),
        ),
      );
    });

    test('SourceImportExportService auto-detects Legado JSON vs JS plugin and classifies non-HTTP / non-text sources', () async {
      const svc = SourceImportExportService();

      const legadoJson = '''
      [
        {
          "bookSourceName": "正常文本源",
          "bookSourceUrl": "https://example.com#🎃",
          "bookSourceType": 0,
          "searchUrl": "/s?q={{key}}"
        },
        {
          "bookSourceName": "有声听书源",
          "bookSourceUrl": "https://audio.example.com",
          "bookSourceType": 1,
          "searchUrl": "/s?q={{key}}"
        },
        {
          "bookSourceName": "融合标签源",
          "bookSourceUrl": "晴天融合VIP4.0",
          "bookSourceType": 0,
          "searchUrl": "/s?q={{key}}"
        }
      ]
      ''';

      final batch = await svc.importFromText(legadoJson, useIsolate: false);
      expect(batch.skippedNonTextCount, 1);
      expect(batch.sources, hasLength(2));
      expect(batch.sources[0].engineType, SourceEngineType.legado);
      expect(batch.sources[1].lastCheckStatus, SourceCheckStatus.error);

      const jsPlugin = '''
      // @name 示例JS源
      // @baseUrl https://js.example.com
      // @group 自制
      async function search(keyword, page) { return []; }
      ''';
      final jsBatch = await svc.importFromText(jsPlugin, fileName: 'demo.js');
      expect(jsBatch.sources, hasLength(1));
      expect(jsBatch.sources.first.engineType, SourceEngineType.jsPlugin);
      expect(jsBatch.sources.first.name, '示例JS源');

      final mixedExport = svc.exportSources(<BookSource>[
        batch.sources.first,
        jsBatch.sources.first,
      ]);
      final reimported = await svc.importFromText(mixedExport, useIsolate: false);
      expect(reimported.sources, hasLength(2));
      expect(reimported.sources[0].engineType, SourceEngineType.legado);
      expect(reimported.sources[1].engineType, SourceEngineType.jsPlugin);
    });
  });
}
