import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';

/// Deterministic loopback HTTP server serving UTF-8 JSON/HTML and GBK HTML
/// fixtures for offline `JsPluginProvider` and `LegadoCompatProvider` tests.
class MockBookServer {
  HttpServer? _server;

  String get baseUrl {
    final server = _server;
    if (server == null) {
      throw StateError('MockBookServer has not been started.');
    }
    return 'http://127.0.0.1:${server.port}';
  }

  final List<String> recordedRequests = [];

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final path = req.uri.path;
    final method = req.method.toUpperCase();
    recordedRequests.add('$method ${req.uri}');

    if (method == 'GET' && path == '/api/search') {
      final keyword = req.uri.queryParameters['q'] ?? '';
      final page = req.uri.queryParameters['page'] ?? '1';
      _writeUtf8Json(req.response, {
        'page': int.tryParse(page) ?? 1,
        'items': [
          {
            'id': '101',
            'title': '《$keyword·星海纪元》',
            'author': '青衫客',
            'bookUrl': '/utf8/book/101',
            'coverUrl': '/covers/101.jpg',
            'intro': '一场跨越星海的求道之旅。',
            'latestChapter': '第二章 灵气潮汐',
            'kind': '科幻修真',
          },
        ],
      });
      return;
    }

    if (method == 'GET' && path == '/utf8/book/101') {
      _writeUtf8Html(req.response, '''
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>星海纪元</title></head>
<body>
  <div class="book-detail">
    <h1 class="title">《星海纪元》</h1>
    <span class="author">青衫客</span>
    <span class="kind">科幻修真</span>
    <span class="words">128000</span>
    <p class="intro">浩瀚星海中，古修文明重燃。</p>
    <a class="toc-link" href="/utf8/toc/101">查看目录</a>
  </div>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/utf8/toc/101') {
      _writeUtf8Html(req.response, '''
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>目录</title></head>
<body>
  <ul class="toc-list">
    <li><a href="/utf8/chapter/1">第一章 启航</a></li>
    <li><a href="/utf8/chapter/2">第二章 灵气潮汐</a></li>
  </ul>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/utf8/chapter/1') {
      _writeUtf8Html(req.response, '''
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>第一章 启航</title></head>
<body>
  <div id="chapter-content">
    <p>夜色深沉，港口灯火如星河垂落。</p>
    <p>林舟站在甲板前端，望向无垠深空，“出发吧，去寻找那座失落的图书馆！”</p>
  </div>
</body>
</html>
''');
      return;
    }

    // GBK-encoded endpoints for LegadoCompatProvider testing.
    if (method == 'POST' && path == '/gbk/search') {
      final token = req.headers.value('X-Client-Token');
      final body = await utf8.decoder.bind(req).join();
      if (token != 'pureread-poc' || !body.contains('keyword=')) {
        req.response.statusCode = HttpStatus.forbidden;
        req.response.write('Missing expected header or POST body');
        await req.response.close();
        return;
      }
      _writeGbkHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta http-equiv="Content-Type" content="text/html; charset=gbk"><title>搜索结果</title></head>
<body>
  <div class="result-list">
    <div class="book-item">
      <a class="name" href="/gbk/book/202">剑来青冥【测试】</a>
      <span class="author">作者：风起青萍</span>
      <span class="latest">最新：第二章 问剑山巅</span>
      <p class="intro">山河万里，一剑可平。</p>
    </div>
  </div>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/gbk/book/202') {
      _writeGbkHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>剑来青冥</title></head>
<body>
  <div id="info">
    <h1>剑来青冥</h1>
    <div class="writer">风起青萍</div>
    <div class="summary">少年背剑出青冥，斩破长夜迎朝霞。</div>
    <a id="all-chapters" href="/gbk/toc/202">全部章节</a>
  </div>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/gbk/toc/202') {
      _writeGbkHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>章节目录</title></head>
<body>
  <dl class="chapter-dl">
    <dd><a href="/gbk/chapter/1">第一章 初入山门</a></dd>
    <dd><a href="/gbk/chapter/2">第二章 问剑山巅</a></dd>
  </dl>
</body>
</html>
''');
      return;
    }

    if (method == 'GET' && path == '/gbk/chapter/1') {
      _writeGbkHtml(req.response, '''
<!DOCTYPE html>
<html>
<head><meta charset="gbk"><title>第一章 初入山门</title></head>
<body>
  <div id="content">
    山风拂过石阶，带来松涛阵阵！<br/>
    【广告：测试推广请忽略】<br/>
    少年抬头望向山门匾额，轻声自语：“原来这里便是青冥宗。”<br/>
    请收藏本站：http://example.local
  </div>
</body>
</html>
''');
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    req.response.write('Not Found: $path');
    await req.response.close();
  }

  void _writeUtf8Json(HttpResponse response, Object payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.add(bytes);
    response.close();
  }

  void _writeUtf8Html(HttpResponse response, String html) {
    final bytes = utf8.encode(html);
    response.statusCode = HttpStatus.ok;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/html; charset=utf-8',
    );
    response.add(bytes);
    response.close();
  }

  void _writeGbkHtml(HttpResponse response, String html) {
    final bytes = gbk.encode(html);
    response.statusCode = HttpStatus.ok;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/html; charset=gbk',
    );
    response.add(bytes);
    response.close();
  }
}
