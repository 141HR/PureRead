import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_compat.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

class _Stage1MockServer {
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
    final method = req.method.toUpperCase();
    requestedPaths.add(
      req.uri.hasQuery ? '$path?${req.uri.query}' : path,
    );

    if (path == '/toc') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(<String, Object?>{
          'chapters': <Map<String, Object?>>[
            <String, Object?>{'id': '274535', 'name': '第一章 剑起'},
            <String, Object?>{'id': 'ch_alpha_99', 'name': '第二章 问道'},
          ],
        }),
      );
      await req.response.close();
      return;
    }

    if (method == 'POST' && path == '/api/chapter') {
      final body = await utf8.decoder.bind(req).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final cid = decoded['cid']?.toString() ?? '';
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(<String, Object?>{'text': 'API正文:$cid'}),
      );
      await req.response.close();
      return;
    }

    if (path == '/chapter/274535' ||
        path == '/274535.html' ||
        path == '/chapter.php' ||
        path == '/274535') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<div id="content">HTTP正文:$path</div>');
      await req.response.close();
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }
}

void main() {
  group('LegadoRuleEvaluator JS comment mustache skipping', () {
    test(
      'skips {{...}} in // and /* ... */ comments while evaluating quoted/template URLs',
      () async {
        const evaluator = LegadoRuleEvaluator(sourceId: 'js-comments');
        const jsonInput = '{"id":42,"foo":"bar","path":"tail"}';

        final out = await evaluator.evaluateString(
          jsonInput,
          r'''
@js:
// example {{$.foo}} with invalid JS syntax if evaluated: \ {{bad}}
/* multi-line block comment
   {{$.foo}}
   // nested {{$.missing}}
*/
// unclosed {{ in line comment must not swallow next line
const s1 = "https://example.com/book/{{$.id}}";
const s2 = 'http://cdn.example.com/{{$.foo}}';
const s3 = `https://tpl.example.com/${/* {{$.broken}} */ "v1"}/{{$.path}}`;
const rx1 = /['"]/; // {{$.broken}}
const rx2 = /https?:\/\//; /* {{$.broken}} */
const ratio = 10 / 2; /* {{$.broken}} */
const inlineComment = "/* not-comment {{$.foo}} */"; // real-comment {{$.broken}}
JSON.stringify({s1, s2, s3, rxOk: rx1.test("'") && rx2.test("https://"), ratio, inlineComment});
''',
          baseUrl: 'https://example.com',
        );

        final decoded = jsonDecode(out) as Map<String, dynamic>;
        expect(decoded['s1'], 'https://example.com/book/42');
        expect(decoded['s2'], 'http://cdn.example.com/bar');
        expect(decoded['s3'], 'https://tpl.example.com/v1/tail');
        expect(decoded['rxOk'], isTrue);
        expect(decoded['ratio'], 5);
        expect(decoded['inlineComment'], '/* not-comment bar */');
      },
    );

    test(
      'skips commented {{...}} and {{key}}/{{page}} inside parseUrlSpecAsync @js: while interpolating quoted URLs',
      () async {
        const evaluator = LegadoRuleEvaluator(sourceId: 'url-js-comments');

        final spec = await evaluator.parseUrlSpecAsync(
          r'''
@js:
// sample {{$.invalid}} and {{key}} comment \
/* block {{page}} {{$.invalid}} */
const target = "https://api.example.com/search?q={{key}}&page={{page}}";
target;
''',
          baseUrl: 'https://api.example.com',
          keyword: '剑来',
          page: 3,
        );

        expect(spec.url, 'https://api.example.com/search?q=剑来&page=3');
      },
    );

    test(
      'preserves {{...}} evaluation in non-JS URL templates and XPath rules containing //',
      () async {
        const evaluator = LegadoRuleEvaluator(sourceId: 'non-js-mustache');

        final urlVal = await evaluator.evaluateString(
          '{"id":88}',
          r'https://example.com/book/{{$.id}}',
          baseUrl: 'https://example.com',
        );
        expect(urlVal, 'https://example.com/book/88');

        final xpathVal = await evaluator.evaluateString(
          '<div><a href="/x">Link</a></div>',
          '@XPath://a/@href',
          baseUrl: 'https://example.com',
        );
        expect(xpathVal, '/x');
      },
    );
  });

  group('LegadoCompatProvider bare non-HTTP chapter ID handling', () {
    late _Stage1MockServer server;
    late SourceHttpClient httpClient;

    setUp(() async {
      server = _Stage1MockServer();
      await server.start();
      httpClient = SourceHttpClient();
    });

    tearDown(() async {
      httpClient.close();
      await server.close();
    });

    test(
      'skips HTTP GET for bare non-HTTP IDs when ruleContent.content starts with @js: or <js>',
      () async {
        for (final contentRule in <String>[
          r'''
@js:
// comment {{$.ignored}}
const resp = java.post("/api/chapter", JSON.stringify({cid: result}), {});
JSON.parse(resp.body()).text + "|" + chapter.url;
''',
          '''
<js>
const resp = java.post("/api/chapter", JSON.stringify({cid: result}), {});
JSON.parse(resp.body()).text + "|" + chapter.url;
</js>
''',
        ]) {
          server.requestedPaths.clear();
          final source = LegadoBookSource.fromJson(<String, Object?>{
            'bookSourceName': 'BareIdSource',
            'bookSourceUrl': server.baseUrl,
            'bookSourceType': 0,
            'ruleToc': <String, Object?>{
              'chapterList': r'$.chapters[*]',
              'chapterName': 'name',
              'chapterUrl': 'id',
            },
            'ruleContent': <String, Object?>{'content': contentRule},
          });
          final provider = LegadoCompatProvider(
            providerId: 'bare-id',
            source: source,
            httpClient: httpClient,
            rateLimitMsOverride: 0,
          );

          final tocRes = await provider.getToc('${server.baseUrl}/toc');
          expect(tocRes.chapters, hasLength(2));
          expect(tocRes.chapters[0].url, '274535');
          expect(tocRes.chapters[1].url, 'ch_alpha_99');

          server.requestedPaths.clear();
          final ch0 = await provider.getChapterContent(tocRes.chapters[0]);
          expect(ch0.content.rawText, 'API正文:274535|274535');
          expect(server.requestedPaths, equals(<String>['/api/chapter']));
          expect(server.requestedPaths, isNot(contains('/274535')));

          server.requestedPaths.clear();
          final ch1 = await provider.getChapterContent(tocRes.chapters[1]);
          expect(ch1.content.rawText, 'API正文:ch_alpha_99|ch_alpha_99');
          expect(server.requestedPaths, equals(<String>['/api/chapter']));
          expect(server.requestedPaths, isNot(contains('/ch_alpha_99')));
        }
      },
    );

    test(
      'still performs HTTP GET for path/extension/HTTP URLs with @js: content or bare IDs with selector content',
      () async {
        final jsSource = LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'HttpUrlsWithJsContent',
          'bookSourceUrl': server.baseUrl,
          'bookSourceType': 0,
          'ruleContent': <String, Object?>{
            'content': '@js:java.getString("#content@text", result)',
          },
        });
        final jsProvider = LegadoCompatProvider(
          providerId: 'http-js',
          source: jsSource,
          httpClient: httpClient,
          rateLimitMsOverride: 0,
        );

        for (final url in <String>[
          '/chapter/274535',
          '274535.html',
          'chapter.php?id=274535',
          '${server.baseUrl}/274535',
        ]) {
          server.requestedPaths.clear();
          final res = await jsProvider.getChapterContent(
            ChapterMeta(
              bookId: 'b1',
              chapterIndex: 0,
              title: 'Ch',
              url: url,
              updatedAt: DateTime.utc(2026),
            ),
          );
          expect(res.content.rawText, startsWith('HTTP正文:'));
          expect(server.requestedPaths, hasLength(1), reason: 'url=$url');
        }

        // Bare ID with non-JS selector rule still resolves & fetches over HTTP.
        final selectorSource = LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'BareIdSelectorContent',
          'bookSourceUrl': server.baseUrl,
          'bookSourceType': 0,
          'ruleContent': <String, Object?>{'content': '#content@text'},
        });
        final selectorProvider = LegadoCompatProvider(
          providerId: 'bare-selector',
          source: selectorSource,
          httpClient: httpClient,
          rateLimitMsOverride: 0,
        );

        server.requestedPaths.clear();
        final selRes = await selectorProvider.getChapterContent(
          ChapterMeta(
            bookId: 'b1',
            chapterIndex: 0,
            title: 'Ch',
            url: '274535',
            updatedAt: DateTime.utc(2026),
          ),
        );
        expect(selRes.content.rawText, 'HTTP正文:/274535');
        expect(server.requestedPaths, equals(<String>['/274535']));
      },
    );
  });
}
