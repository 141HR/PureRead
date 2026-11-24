import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/js_plugin/js_plugin_provider.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

class _MockJsPluginServer {
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
    if (req.method == 'POST' && path == '/api/search') {
      final rawBody = await utf8.decoder.bind(req).join();
      final payload = jsonDecode(rawBody) as Map<String, dynamic>;
      final sig = req.headers.value('x-sig') ?? '';
      if (sig.isEmpty) {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
        return;
      }
      final kw = payload['keyword']?.toString() ?? '';
      _writeJson(req.response, <String, Object?>{
        'sig': sig,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'title': '《$kw·星海纪元》',
            'author': '青衫客',
            'bookUrl': '/book/101',
            'coverUrl': '/covers/101.jpg',
            'intro': '跨越星海的求道之旅。',
            'latestChapter': '第二章 灵气潮汐',
            'kind': '科幻修真',
          },
        ],
      });
      return;
    }

    if (req.method == 'GET' && path == '/book/101') {
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>星海纪元</title></head>
<body>
  <div class="detail">
    <h1 class="title">《星海纪元》</h1>
    <span class="author">青衫客</span>
    <span class="kind">科幻修真</span>
    <span class="words">128000</span>
    <p class="intro">浩瀚星海中，古修文明重燃。</p>
    <a class="toc-link" href="/toc/101">查看目录</a>
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
    <li><a href="/chapter/1">第一章 启航</a></li>
    <li><a href="/chapter/2">第二章 灵气潮汐</a></li>
  </ul>
</body>
</html>
''');
      return;
    }

    if (req.method == 'GET' && path == '/chapter/1') {
      _writeHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>第一章 启航</title></head>
<body>
  <div id="chapter-content">
    <p>夜色深沉，港口灯火如星河垂落。</p>
    <p>林舟站在甲板前端，望向无垠深空。</p>
  </div>
</body>
</html>
''');
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

  void _writeHtml(HttpResponse resp, String html) {
    resp.statusCode = HttpStatus.ok;
    resp.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
    resp.add(utf8.encode(html));
    resp.close();
  }
}

const String _fullPluginScript = r'''
async function search(keyword, page) {
  host.log("search:" + keyword + ":" + page);
  const sig = host.md5(keyword + ":" + page);
  const b64 = host.base64Decode(host.base64Encode("ok"));
  const resp = await host.httpPost(
    "/api/search",
    JSON.stringify({ keyword, page }),
    { "Content-Type": "application/json", "X-Sig": sig }
  );
  const titles = host.jsonPath(resp.body, "$.items[*].title");
  const data = JSON.parse(resp.body);
  return data.items.map((item, idx) => ({
    title: titles[idx] || item.title,
    author: item.author,
    bookUrl: item.bookUrl,
    coverUrl: item.coverUrl,
    intro: item.intro + " [" + b64 + "]",
    latestChapterTitle: item.latestChapter,
    kind: item.kind
  }));
}

async function detail(bookUrl) {
  const resp = await host.httpGet(bookUrl);
  return {
    title: host.xpath(resp.body, "//h1[@class='title']/text()")[0],
    author: host.cssSelectOne(resp.body, "span.author@text"),
    kind: host.cssSelectOne(resp.body, "span.kind@text"),
    wordCount: host.cssSelectOne(resp.body, "span.words@text"),
    intro: host.cssSelectOne(resp.body, "p.intro@text"),
    tocUrl: host.cssSelectOne(resp.body, "a.toc-link@href")
  };
}

async function toc(tocUrl) {
  const resp = await host.httpGet(tocUrl);
  const blocks = host.cssElements(resp.body, "ul.toc-list li");
  return blocks.map((li) => ({
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

void main() {
  late _MockJsPluginServer server;
  late SourceHttpClient httpClient;

  setUp(() async {
    server = _MockJsPluginServer();
    await server.start();
    httpClient = SourceHttpClient();
  });

  tearDown(() async {
    httpClient.close();
    await server.close();
  });

  test('executes full 4-method search->detail->toc->content pipeline with host bridge and traces', () async {
    final provider = JsPluginProvider(
      providerId: 'js-full-test',
      sourceName: 'JS Test Source',
      baseUrl: server.baseUrl,
      pluginScript: _fullPluginScript,
      httpClient: httpClient,
      rateLimitMs: 0,
    );

    final searchRes = await provider.search('星海', page: 2);
    expect(searchRes.items, hasLength(1));
    final item = searchRes.items.first;
    expect(item.title, '《星海·星海纪元》');
    expect(item.author, '青衫客');
    expect(item.bookUrl, '${server.baseUrl}/book/101');
    expect(item.coverUrl, '${server.baseUrl}/covers/101.jpg');
    expect(item.intro, contains('[ok]'));
    expect(searchRes.trace.step, 'search');
    expect(searchRes.trace.httpStatus, 200);
    expect(searchRes.trace.logs, contains('search:星海:2'));

    final detailRes = await provider.getBookDetail(item.bookUrl);
    expect(detailRes.detail.title, '《星海纪元》');
    expect(detailRes.detail.wordCount, 128000);
    expect(detailRes.detail.tocUrl, '${server.baseUrl}/toc/101');
    expect(detailRes.trace.step, 'detail');

    final tocRes = await provider.getToc(detailRes.detail.tocUrl);
    expect(tocRes.chapters, hasLength(2));
    expect(tocRes.chapters.first.title, '第一章 启航');
    expect(tocRes.chapters.first.url, '${server.baseUrl}/chapter/1');
    expect(tocRes.trace.step, 'toc');

    final contentRes = await provider.getChapterContent(tocRes.chapters.first);
    expect(contentRes.content.rawText, contains('夜色深沉，港口灯火如星河垂落。'));
    expect(contentRes.content.rawText, contains('林舟站在甲板前端，望向无垠深空。'));
    expect(contentRes.trace.step, 'content');
  });

  test('supports CommonJS module.exports and maps HTTP/JS/parse/cancel errors cleanly', () async {
    const cjsPlugin = r'''
    module.exports = {
      async search(keyword) {
        const resp = await host.httpGet("/missing-endpoint");
        return resp;
      },
      async detail() {
        return { title: "" };
      },
      async toc() {
        while (true) {}
      },
      async content() {
        return { text: "ok" };
      }
    };
    ''';

    final provider = JsPluginProvider(
      providerId: 'js-errors',
      sourceName: 'JS Errors',
      baseUrl: server.baseUrl,
      pluginScript: cjsPlugin,
      httpClient: httpClient,
      rateLimitMs: 0,
      scriptTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(
      () => provider.search('x'),
      throwsA(
        isA<NetworkFailure>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );

    await expectLater(
      () => provider.getBookDetail('/book/101'),
      throwsA(isA<SourceParseFailure>()),
    );

    await expectLater(
      () => provider.getToc('/toc/101'),
      throwsA(
        isA<JsExecutionFailure>().having((e) => e.isTimeout, 'isTimeout', isTrue),
      ),
    );

    final cancelled = CancellationToken()..cancel();
    await expectLater(
      () => provider.search('x', cancelToken: cancelled),
      throwsA(isA<CancelledFailure>()),
    );
  });
}
