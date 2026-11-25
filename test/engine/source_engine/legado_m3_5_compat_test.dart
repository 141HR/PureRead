import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_compat.dart';
import 'package:pureread/infrastructure/js/js_crypto_helpers.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

class _M35MockServer {
  HttpServer? _server;
  int activeAjaxAllRequests = 0;
  int peakAjaxAllRequests = 0;

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

    if (path == '/' || path.isEmpty) {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html><body><h1>Home</h1></body></html>');
      await req.response.close();
      return;
    }

    if (path == '/headers-echo') {
      final token = req.headers.value('x-connect-token') ?? '';
      final ua = req.headers.value('user-agent') ?? '';
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(<String, Object?>{'token': token, 'ua': ua}));
      await req.response.close();
      return;
    }

    if (method == 'POST' && path == '/post-redir') {
      final body = await utf8.decoder.bind(req).join();
      if (!body.contains('searchkey=')) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.found;
      req.response.headers.set(HttpHeaders.locationHeader, '/search-target');
      await req.response.close();
      return;
    }

    if (path == '/search-target') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<div class="item"><a href="/book/1">Found</a></div>');
      await req.response.close();
      return;
    }

    if (path.startsWith('/batch/')) {
      activeAjaxAllRequests++;
      if (activeAjaxAllRequests > peakAjaxAllRequests) {
        peakAjaxAllRequests = activeAjaxAllRequests;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      activeAjaxAllRequests--;
      final idx = path.substring('/batch/'.length);
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<span class="val">batch-$idx</span>');
      await req.response.close();
      return;
    }

    if (path == '/jsoup-connect-target') {
      final hdr = req.headers.value('x-jsoup') ?? '';
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write(
        '<div id="jc"><span class="hdr">$hdr</span><p>Connected OK</p></div>',
      );
      await req.response.close();
      return;
    }

    if (path == '/search-redirect') {
      req.response.statusCode = HttpStatus.found;
      req.response.headers.set(HttpHeaders.locationHeader, '/book/777');
      await req.response.close();
      return;
    }

    if (path == '/book/777') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:novel:book_name" content="重定向剑道" />
  <meta property="og:novel:author" content="青莲居士" />
</head>
<body>
  <div id="info">
    <h1>重定向剑道</h1>
    <p class="author">青莲居士</p>
    <img class="cover" src="/covers/777.jpg" />
    <div class="intro">搜索直达详情页回退测试。</div>
    <a id="toc-link" href="/toc/777">章节目录</a>
  </div>
</body>
</html>
''');
      await req.response.close();
      return;
    }

    if (path == '/toc/777') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<!DOCTYPE html>
<html><body>
  <div class="BCsectionTwo-top-chapter" data-x="2">
    <a href="/ch/2">第二章 剑出</a>
  </div>
  <div class="BCsectionTwo-top-chapter" data-x="1">
    <a href="/ch/1">第一章 问心</a>
  </div>
</body></html>
''');
      await req.response.close();
      return;
    }

    if (path == '/ch/1') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write(
        '<div id="content"><p>第一章正文内容。</p><p>第二段内容。</p></div>',
      );
      await req.response.close();
      return;
    }

    if (path == '/json-search') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(<String, Object?>{
          'data': <String, Object?>{
            'list': <Map<String, Object?>>[
              <String, Object?>{
                'id': 88,
                'bookName': 'JSONApi小说',
                'authorName': '测试作者',
                'bookPic': '/covers/88.png',
              },
            ],
          },
        }),
      );
      await req.response.close();
      return;
    }

    if (path == '/json-book/88') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(<String, Object?>{
          'data': <String, Object?>{
            'book': <String, Object?>{
              'id': 88,
              'bookName': 'JSONApi小说',
              'authorName': '测试作者',
              'intro': '简介',
            },
          },
        }),
      );
      await req.response.close();
      return;
    }

    if (path == '/json-toc/88') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(<String, Object?>{
          'data': <Map<String, Object?>>[
            <String, Object?>{'chapterId': 1001, 'chapterName': '第1章 启程'},
          ],
        }),
      );
      await req.response.close();
      return;
    }

    if (path == '/json-ch/1001') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(<String, Object?>{'content': 'JSON章节正文内容'}),
      );
      await req.response.close();
      return;
    }

    if (path == '/jsonp-chapter') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.text;
      req.response.write("callback({'content':'第一段内容。'});");
      await req.response.close();
      return;
    }

    if (method == 'POST' && path == '/jiumo-init') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"status":"succeed","id":"hub-9988"}');
      await req.response.close();
      return;
    }

    if (method == 'POST' && path == '/post-book-detail') {
      final body = await utf8.decoder.bind(req).join();
      final hdr = req.headers.value('x-session-token') ?? '';
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(<String, Object?>{
          'data': <String, Object?>{
            'book': <String, Object?>{
              'id': 88,
              'bookName': 'POST会话书籍:$body:$hdr',
              'authorName': '测试作者',
              'intro': '简介',
            },
          },
        }),
      );
      await req.response.close();
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }
}

void main() {
  group('M3.5 Classifier & Guard Unlock', () {
    test(
      'supports org.jsoup / Packages.org.jsoup / importClass(org.jsoup.*) and populates extended features',
      () {
        final rawJson = jsonEncode(<String, Object?>{
          'bookSourceName': 'Jsoup + Features Test',
          'bookSourceUrl': 'https://example.com#tag',
          'bookSourceType': 0,
          'searchUrl': '/s?q={{key}}',
          'ruleSearch': <String, Object?>{
            'checkKeyWord': '剑来',
            'bookList':
                ':(?is)<div class="b">(.*?)</div>\n<js>importClass(org.jsoup.Jsoup); var d = Packages.org.jsoup.Jsoup.parse(src); java.ajaxAll(["/1"]); book.getVariable("x"); java.digestHex("a", "SHA-256"); java.createSymmetricCrypto("AES/ECB/PKCS5Padding", "0123456789abcdef"); result</js>',
            'name': r'$1',
            'bookUrl': '/book/1',
          },
          'ruleToc': <String, Object?>{
            'preUpdateJs': 'java.refreshTocUrl()',
            'chapterList': '.ch a',
            'chapterName': 'text',
            'chapterUrl': 'href',
          },
          'ruleContent': <String, Object?>{'content': '#c@html'},
        });

        final batch = LegadoSourceParser.parseBatchSync(rawJson);
        expect(batch.totalCount, 1);
        final parsed = batch.items.single;
        expect(parsed.compatibility, LegadoCompatibilityStatus.supported);
        expect(parsed.legado.ruleSearch.checkKeyWord, '剑来');
        expect(parsed.legado.ruleToc.preUpdateJs, 'java.refreshTocUrl()');
        expect(
          parsed.detectedFeatures,
          containsAll(<String>[
            'jsoup',
            'colonRegex',
            'symmetricCrypto',
            'ajaxAll',
            'digestHmac',
            'bookVariable',
            'checkKeyWord',
            'preUpdateJs',
          ]),
        );

        const evaluator = LegadoRuleEvaluator(sourceId: 'jsoup-allowed');
        expect(
          () => evaluator.guardUnsupportedRules(<String?>[
            parsed.legado.ruleSearch.bookList,
            parsed.legado.ruleToc.preUpdateJs,
          ]),
          returnsNormally,
        );
      },
    );

    test('still rejects non-Jsoup Rhino APIs in classifier and evaluator guards', () {
      for (final snippet in <String>[
        '<js>Packages.java.lang.System.currentTimeMillis()</js>',
        '<js>java.lang.Thread.sleep(10)</js>',
        '<js>new java.net.URL("https://a.b")</js>',
        '<js>java.io.File("/tmp/x")</js>',
        '<js>new java.util.HashMap()</js>',
        '<js>importClass(java.util.Date)</js>',
      ]) {
        final src = LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'BadRhino',
          'bookSourceUrl': 'https://example.com',
          'bookSourceType': 0,
          'searchUrl': '/s?q={{key}}',
          'ruleSearch': <String, Object?>{
            'bookList': 'li',
            'name': snippet,
            'bookUrl': 'a@href',
          },
        });
        final classification = LegadoSourceParser.classifySource(
          src,
          src.rawJson,
        );
        expect(
          classification.compatibility,
          LegadoCompatibilityStatus.unsupportedRhino,
          reason: snippet,
        );

        const evaluator = LegadoRuleEvaluator(sourceId: 'bad-rhino');
        expect(
          () => evaluator.guardUnsupportedRules(<String?>[snippet]),
          throwsA(
            isA<UnsupportedLegadoRuleFailure>().having(
              (e) => e.feature,
              'feature',
              'rhino_java_api',
            ),
          ),
        );
      }
    });
  });

  group('M3.5 JS Runtime Bridges (Jsoup, Digest/HMAC, Time, URL, Book, Cache)', () {
    test('wires LegadoJsoupBridge, src binding, and elementBlocks in evaluateListBlocks', () async {
      const evaluator = LegadoRuleEvaluator(sourceId: 'jsoup-blocks');
      const html = '''
      <html>
        <head><script>var marker = "use-data-x";</script></head>
        <body>
          <div class="wrap" data-x="2"><a href="/c2">第二章</a><span class="ad">ad</span></div>
          <div class="wrap" data-x="1"><a href="/c1">第一章</a></div>
        </body>
      </html>
      ''';

      final res = await evaluator.evaluateListBlocks(
        html,
        '''
class.wrap
<js>
if (src.match(/use-data-x/)) {
  result.select(".ad").remove();
  result.sort((a, b) => a.attr("data-x") - b.attr("data-x"));
  result.select("a");
} else {
  [];
}
</js>
''',
        baseUrl: 'https://example.com/book/1/',
      );

      expect(res.items, hasLength(2));
      expect(
        await evaluator.evaluateString(
          res.items[0],
          'text',
          baseUrl: 'https://example.com',
        ),
        '第一章',
      );
      expect(
        await evaluator.evaluateString(
          res.items[1],
          'href',
          baseUrl: 'https://example.com',
        ),
        '/c2',
      );
    });

    test('exposes digestHex, digestBase64, sha*, hexEncodeToString, HMacHex, createDigest, createHMac, randomUUID, timeFormatUTC, toURL, htmlFormat', () async {
      const evaluator = LegadoRuleEvaluator(sourceId: 'js-apis');
      final out = await evaluator.evaluateString(
        '<div id="x"><p>第一行&nbsp;<b>加粗</b></p><p>第二行</p></div>',
        '''
<js>
const dHex = java.digestHex("abc", "SHA-256");
const dB64 = java.digestBase64("abc", "SHA-256");
const s256 = java.sha256Encode("abc");
const s1 = java.sha1Encode("abc");
const hx = java.hexEncodeToString("AB");

const dig = java.createDigest("SHA-256");
const digHex = dig.digestHex("abc");
const digB64 = dig.digestBase64("abc");
const digBytes = dig.digest("abc");

const hmacObj = java.createHMac("HmacSHA256", "secret");
const hmHex = hmacObj.digestHex("hello");
const hmB64 = hmacObj.digestBase64("hello");
const hmBytes = hmacObj.digest("hello");
const hmDirect = java.HMacHex("hello", "HmacSHA256", "secret");

const uuid = java.randomUUID();
const t2 = java.timeFormatUTC(0, 8);
const t3Hours = java.timeFormatUTC("1700000000000", "yyyy-MM-dd HH:mm:ss", 8);
const t3DateMs = java.timeFormatUTC(new Date(1700000000000), "yyyyMMdd", 28800000);
const u = java.toURL("/novel/123?p=1", "https://api.example.com/base/");
const formatted = java.htmlFormat(result);

JSON.stringify({
  dHex,
  dB64,
  s256,
  s1,
  hx,
  digHex,
  digB64,
  digLen: digBytes.length,
  hmHex,
  hmB64,
  hmBytesLen: hmBytes.length,
  hmDirect,
  uuid,
  t2,
  t3Hours,
  t3DateMs,
  host: u.host,
  path: u.path,
  file: u.file,
  urlStr: String(u),
  formatted,
  srcLen: src.length
});
</js>
''',
        baseUrl: 'https://example.com',
      );

      final m = jsonDecode(out) as Map<String, dynamic>;
      expect(m['dHex'], JsCryptoHelpers.digestHex('abc', 'SHA-256'));
      expect(m['dB64'], JsCryptoHelpers.digestBase64('abc', 'SHA-256'));
      expect(m['s256'], m['dHex']);
      expect(m['s1'], JsCryptoHelpers.digestHex('abc', 'SHA-1'));
      expect(m['hx'], '4142');
      expect(m['digHex'], m['dHex']);
      expect(m['digB64'], m['dB64']);
      expect(m['digLen'], 32);
      expect(m['hmHex'], JsCryptoHelpers.hmacHex('hello', 'secret', 'HmacSHA256'));
      expect(m['hmB64'], JsCryptoHelpers.hmacBase64('hello', 'secret', 'HmacSHA256'));
      expect(m['hmBytesLen'], 32);
      expect(m['hmDirect'], m['hmHex']);
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(m['uuid'] as String),
        isTrue,
      );
      expect(m['t2'], '1970-01-01 08:00:00');
      expect(m['t3Hours'], '2023-11-15 06:13:20');
      expect(m['t3DateMs'], '20231115');
      expect(m['host'], 'api.example.com');
      expect(m['path'], '/novel/123');
      expect(m['file'], '/novel/123?p=1');
      expect(m['urlStr'], 'https://api.example.com/novel/123?p=1');
      expect(m['formatted'], '第一行 加粗\n第二行');
      expect(m['srcLen'], greaterThan(10));
    });

    test('supports book variables, cache with TTL, source login stubs, and var book redeclaration', () async {
      final session = LegadoEvalSession(
        bookName: '凡人修仙传',
        bookUrl: 'https://example.com/b/1',
        tocUrl: 'https://example.com/t/1',
      );
      const evaluator = LegadoRuleEvaluator(sourceId: 'book-cache');

      final out1 = await evaluator.evaluateString(
        '',
        '''
<js>
book.putVariable("mode", "fast");
book.putCustomVariable("custom-tag");
cache.put("k1", "v1", 60);
cache.put("k_exp", "old", 1);
const info = {
  bName: book.name,
  bUrl: book.bookUrl,
  bToc: book.tocUrl,
  vMode: book.getVariable("mode"),
  vAll: book.variable,
  vCustom: book.getCustomVariable(),
  c1: cache.get("k1"),
  loginInfo: source.getLoginInfo(),
  loginInfoMap: source.getLoginInfoMap(),
  loginHeader: source.getLoginHeader(),
  loginHeaderMap: source.getLoginHeaderMap(),
};
cache.delete("k1");
info.c1AfterDel = cache.get("k1");
JSON.stringify(info);
</js>
''',
        baseUrl: 'https://example.com',
        session: session,
      );

      final m1 = jsonDecode(out1) as Map<String, dynamic>;
      expect(m1['bName'], '凡人修仙传');
      expect(m1['bUrl'], 'https://example.com/b/1');
      expect(m1['bToc'], 'https://example.com/t/1');
      expect(m1['vMode'], 'fast');
      expect(jsonDecode(m1['vAll'] as String), <String, Object?>{'mode': 'fast'});
      expect(m1['vCustom'], 'custom-tag');
      expect(m1['c1'], 'v1');
      expect(m1['c1AfterDel'], isNull);
      expect(m1['loginInfo'], '');
      expect(m1['loginInfoMap'], isEmpty);
      expect(m1['loginHeader'], '');
      expect(m1['loginHeaderMap'], isEmpty);

      // Force expiration check and verify `var book = {...}` does not throw SyntaxError.
      session.cacheEntries['k_exp'] = LegadoCacheEntry(
        'old',
        DateTime.now().millisecondsSinceEpoch - 1000,
      );
      final out2 = await evaluator.evaluateString(
        '',
        '''
<js>
var expired = cache.get("k_exp");
var book = { name: "ShadowBook" };
JSON.stringify({ expired: expired, shadowed: book.name });
</js>
''',
        baseUrl: 'https://example.com',
        session: session,
      );
      final m2 = jsonDecode(out2) as Map<String, dynamic>;
      expect(m2['expired'], isNull);
      expect(m2['shadowed'], 'ShadowBook');
    });
  });

  group('M3.5 Loopback HTTP: ajaxAll, connect(headers), trailing /, Location, redirect fallback, preUpdateJs', () {
    late _M35MockServer server;
    late SourceHttpClient httpClient;

    setUp(() async {
      server = _M35MockServer();
      await server.start();
      httpClient = SourceHttpClient();
    });

    tearDown(() async {
      httpClient.close();
      await server.close();
    });

    test('supports java.ajaxAll (bounded concurrency 4, ordered), java.connect(url, headers), trailing /, Location, and Jsoup.connect', () async {
      final source = LegadoBookSource.fromJson(<String, Object?>{
        'bookSourceName': 'HTTP JS Test',
        'bookSourceUrl': '${server.baseUrl}#🎃',
        'bookSourceType': 0,
      });
      final evaluator = LegadoRuleEvaluator(
        sourceId: 'http-js',
        source: source,
        httpClient: httpClient,
      );

      final out = await evaluator.evaluateString(
        '',
        '''
<js>
const rootUrl = java.connect(source.getKey()).raw().request().url();
const connEcho = java.connect("/headers-echo", {"X-Connect-Token": "tok-42"}).body();
const postResp = java.post(rootUrl + "post-redir", "searchkey=test", {});
const loc = postResp.header("Location");
const locs = postResp.headers("Location");
const urls = ["/batch/0", "/batch/1", "/batch/2", "/batch/3", "/batch/4", "/batch/5"];
const batchRes = java.ajaxAll(urls).map(r => r.body());
const jdoc = org.jsoup.Jsoup.connect("/jsoup-connect-target").header("X-Jsoup", "j-ok").get();
JSON.stringify({
  rootUrl,
  connEcho: JSON.parse(connEcho),
  loc,
  locs,
  batchRes,
  jsoupText: jdoc.select("#jc p").text(),
  jsoupHdr: jdoc.select("#jc .hdr").text(),
});
</js>
''',
        baseUrl: server.baseUrl,
      );

      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['rootUrl'], '${server.baseUrl}/');
      expect((decoded['connEcho'] as Map)['token'], 'tok-42');
      expect(decoded['loc'], '/search-target');
      expect(decoded['locs'], <String>['/search-target']);
      expect(decoded['batchRes'], <String>[
        '<span class="val">batch-0</span>',
        '<span class="val">batch-1</span>',
        '<span class="val">batch-2</span>',
        '<span class="val">batch-3</span>',
        '<span class="val">batch-4</span>',
        '<span class="val">batch-5</span>',
      ]);
      expect(server.peakAjaxAllRequests, lessThanOrEqualTo(4));
      expect(decoded['jsoupText'], 'Connected OK');
      expect(decoded['jsoupHdr'], 'j-ok');
    });

    test('LegadoCompatProvider handles search redirect-to-detail fallback, preUpdateJs, and Jsoup sorted TOC', () async {
      final source = LegadoBookSource.fromJson(<String, Object?>{
        'bookSourceName': 'Redirect + preUpdateJs + Jsoup',
        'bookSourceUrl': server.baseUrl,
        'bookSourceType': 0,
        'searchUrl': '/search-redirect?q={{key}}',
        'ruleSearch': <String, Object?>{
          'bookList': 'class.nonexistent-search-row',
          'name': 'a@text',
          'bookUrl': 'a@href',
        },
        'ruleBookInfo': <String, Object?>{
          'init': '@put:{n:"h1@text", a:".author@text"}',
          'name': '@get:{n}',
          'author': '@get:{a}',
          'coverUrl': 'img.cover@src',
          'intro': '.intro@text',
          'tocUrl': '#toc-link@href',
        },
        'ruleToc': <String, Object?>{
          'preUpdateJs': 'java.refreshTocUrl(); cache.put("toc_ran", "yes", 60);',
          'chapterList': '''
class.BCsectionTwo-top-chapter
<js>
if (src.match(/data-x/)) {
  result.sort((a, b) => a.attr("data-x") - b.attr("data-x"));
  result.select("a");
} else {
  result;
}
</js>
''',
          'chapterName': 'text',
          'chapterUrl': 'href',
        },
        'ruleContent': <String, Object?>{
          'content': '<js>cache.get("toc_ran") + ":" + java.htmlFormat(java.getString("id.content@html"))</js>',
        },
      });

      final provider = LegadoCompatProvider(
        providerId: 'm35-redirect',
        source: source,
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );

      final searchRes = await provider.search('重定向');
      expect(searchRes.items, hasLength(1));
      expect(searchRes.items.first.title, '重定向剑道');
      expect(searchRes.items.first.author, '青莲居士');
      expect(searchRes.items.first.bookUrl, '${server.baseUrl}/book/777');
      expect(searchRes.items.first.coverUrl, '${server.baseUrl}/covers/777.jpg');

      final detailRes = await provider.getBookDetail(searchRes.items.first.bookUrl);
      expect(detailRes.detail.tocUrl, '${server.baseUrl}/toc/777');

      final tocRes = await provider.getToc(detailRes.detail.tocUrl);
      expect(tocRes.chapters, hasLength(2));
      expect(tocRes.chapters[0].title, '第一章 问心');
      expect(tocRes.chapters[1].title, '第二章 剑出');

      final contentRes = await provider.getChapterContent(tocRes.chapters[0]);
      expect(contentRes.content.rawText, 'yes:第一章正文内容。\n第二段内容。');
    });

    test('LegadoCompatProvider supports bare JSONPath/field rules without \$. prefix', () async {
      final source = LegadoBookSource.fromJson(<String, Object?>{
        'bookSourceName': 'Bare JSON Rules',
        'bookSourceUrl': server.baseUrl,
        'bookSourceType': 0,
        'searchUrl': '/json-search?q={{key}}',
        'ruleSearch': <String, Object?>{
          'bookList': 'data.list[*]',
          'name': 'bookName',
          'author': 'authorName',
          'bookUrl': r'/json-book/{{$.id}}',
          'coverUrl': 'bookPic',
        },
        'ruleBookInfo': <String, Object?>{
          'init': 'data.book',
          'name': 'bookName',
          'author': 'authorName',
          'intro': 'intro',
          'tocUrl': r'/json-toc/{{$.id}}',
        },
        'ruleToc': <String, Object?>{
          'chapterList': 'data[*]',
          'chapterName': 'chapterName',
          'chapterUrl': r'/json-ch/{{$.chapterId}}',
        },
        'ruleContent': <String, Object?>{'content': 'content'},
      });

      final provider = LegadoCompatProvider(
        providerId: 'm35-bare-json',
        source: source,
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );

      final searchRes = await provider.search('JSON');
      expect(searchRes.items, hasLength(1));
      expect(searchRes.items.first.title, 'JSONApi小说');
      expect(searchRes.items.first.author, '测试作者');

      final detailRes = await provider.getBookDetail(searchRes.items.first.bookUrl);
      expect(detailRes.detail.title, 'JSONApi小说');

      final tocRes = await provider.getToc(detailRes.detail.tocUrl);
      expect(tocRes.chapters, hasLength(1));
      expect(tocRes.chapters.first.title, '第1章 启程');

      final contentRes = await provider.getChapterContent(tocRes.chapters.first);
      expect(contentRes.content.rawText, 'JSON章节正文内容');
    });

    test('evaluates async scripts with non-empty source.header, getHeaderMap(), and regex literals safely', () async {
      final source = LegadoBookSource.fromJson(<String, Object?>{
        'bookSourceName': 'Header + Regex Async JS',
        'bookSourceUrl': server.baseUrl,
        'bookSourceType': 0,
        'header': jsonEncode(<String, String>{
          'User-Agent': 'PureRead-Agent/1.0',
          'X-Extra': 'ok',
        }),
      });
      final evaluator = LegadoRuleEvaluator(
        sourceId: 'hdr-regex-js',
        source: source,
        httpClient: httpClient,
      );

      final out = await evaluator.evaluateString(
        '<input id="bookPartResourceUrl" value="/jsonp-chapter">',
        r'''
#bookPartResourceUrl@value@js:
result = String(java.ajax(result)).replace(/(callback.+?:')|('\}\);?)/g,"");
const hdrUa = source.getHeaderMap()["User-Agent"];
const id = java.ajax('/jiumo-init,' + JSON.stringify({method: "POST", body: "q=test"})).match(/id":"([^"]+)"/)[1];
const joined = String(baseUrl).replace(/([^\/])$/i, '$1/') + 'sub'.replace(/^\//, '');
JSON.stringify({result, hdrUa, id, joined});
''',
        baseUrl: server.baseUrl,
      );

      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['result'], '第一段内容。');
      expect(decoded['hdrUa'], 'PureRead-Agent/1.0');
      expect(decoded['id'], 'hub-9988');
      expect(decoded['joined'], '${server.baseUrl}/sub');
    });

    test('evaluates {{...}} inside @js: stages, binds chapter title, preserves POST bookUrl options, and runs @js: replaceRegex', () async {
      final source = LegadoBookSource.fromJson(<String, Object?>{
        'bookSourceName': 'Mustache JS + Shared Session',
        'bookSourceUrl': server.baseUrl,
        'bookSourceType': 0,
        'searchUrl': '''
@js:
java.put("tok", "tok-abc");
"/json-search?q=" + key;
''',
        'ruleSearch': <String, Object?>{
          'bookList': 'data.list[*]',
          'name': 'bookName',
          'author': 'authorName',
          'bookUrl': r'''
@js:
let option = {
  method: "POST",
  headers: {"X-Session-Token": java.get("tok")},
  body: "bookId={{$.id}}"
};
"/post-book-detail," + JSON.stringify(option);
''',
        },
        'ruleBookInfo': <String, Object?>{
          'init': 'data.book',
          'name': 'bookName',
          'author': 'authorName',
          'tocUrl': r'/json-toc/{{$.id}}',
        },
        'ruleToc': <String, Object?>{
          'chapterList': 'data[*]',
          'chapterName': 'chapterName',
          'chapterUrl': r'/json-ch/{{$.chapterId}}',
        },
        'ruleContent': <String, Object?>{
          'content': r'''
@js:
const pat = new RegExp("章节({{
const m = title.match(/第\d+章/);
m ? m[0] : '';
}})?");
result + ":" + pat.test("章节第1章");
''',
          'replaceRegex': '@js:result.replace("JSON", "HARDENED")',
        },
      });

      final provider = LegadoCompatProvider(
        providerId: 'm35-mustache-js',
        source: source,
        httpClient: httpClient,
        rateLimitMsOverride: 0,
      );

      final searchRes = await provider.search('测试');
      expect(searchRes.items, hasLength(1));
      expect(searchRes.items.first.bookUrl, contains('/post-book-detail,'));

      final detailRes = await provider.getBookDetail(searchRes.items.first.bookUrl);
      expect(detailRes.detail.title, 'POST会话书籍:bookId=88:tok-abc');
      expect(detailRes.detail.tocUrl, '${server.baseUrl}/json-toc/88');

      final tocRes = await provider.getToc(detailRes.detail.tocUrl);
      expect(tocRes.chapters, hasLength(1));

      final contentRes = await provider.getChapterContent(tocRes.chapters.first);
      expect(
        contentRes.content.rawText,
        '{"content":"HARDENED章节正文内容"}:true',
      );
    });
  });
}
