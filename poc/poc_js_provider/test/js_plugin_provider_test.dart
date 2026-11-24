import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:poc_js_provider/domain/domain.dart';
import 'package:poc_js_provider/engine/source_engine/js_plugin/js_plugin_provider.dart';
import 'package:poc_js_provider/infrastructure/js/qjs_sandbox_runtime.dart';
import 'package:poc_js_provider/infrastructure/network/source_http_client.dart';
import 'package:qjs/qjs.dart';

import 'fixtures/mock_book_server.dart';

const String _samplePluginScript = r'''
async function search(keyword, page) {
  host.log("js search: " + keyword + " page=" + page);
  const resp = await host.httpGet("/api/search?q=" + encodeURIComponent(keyword) + "&page=" + page);
  const titles = host.jsonPath(resp.body, "$.items[*].title");
  const parsed = JSON.parse(resp.body);
  return parsed.items.map((item, idx) => ({
    title: titles[idx] || item.title,
    author: item.author,
    bookUrl: item.bookUrl,
    coverUrl: item.coverUrl,
    intro: item.intro,
    latestChapterTitle: item.latestChapter,
    kind: item.kind,
  }));
}

async function detail(bookUrl) {
  host.log("js detail: " + bookUrl);
  const resp = await host.httpGet(bookUrl);
  return {
    title: host.cssSelectOne(resp.body, "h1.title@text"),
    author: host.cssSelectOne(resp.body, "span.author@text"),
    kind: host.cssSelectOne(resp.body, "span.kind@text"),
    wordCount: host.cssSelectOne(resp.body, "span.words@text"),
    intro: host.cssSelectOne(resp.body, "p.intro@text"),
    tocUrl: host.cssSelectOne(resp.body, "a.toc-link@href"),
  };
}

async function toc(tocUrl) {
  host.log("js toc: " + tocUrl);
  const resp = await host.httpGet(tocUrl);
  const blocks = host.cssElements(resp.body, "ul.toc-list li");
  return blocks.map((li) => ({
    title: host.cssSelectOne(li, "a@text"),
    url: host.cssSelectOne(li, "a@href"),
  }));
}

async function content(chapterUrl) {
  host.log("js content: " + chapterUrl);
  const resp = await host.httpGet(chapterUrl);
  return {
    text: host.cssSelectOne(resp.body, "#chapter-content@html"),
  };
}
''';

void main() {
  late MockBookServer server;
  late SourceHttpClient httpClient;

  setUp(() async {
    server = MockBookServer();
    await server.start();
    httpClient = SourceHttpClient();
  });

  tearDown(() async {
    httpClient.close();
    await server.close();
  });

  test('JsPluginProvider executes 4-method search->detail->toc->content against loopback server', () async {
    final provider = JsPluginProvider(
      providerId: 'js-demo',
      sourceName: 'JS Demo Source',
      baseUrl: server.baseUrl,
      pluginScript: _samplePluginScript,
      httpClient: httpClient,
    );

    final searchRes = await provider.search('星海', page: 1);
    expect(searchRes.items, hasLength(1));
    final first = searchRes.items.first;
    expect(first.title, '《星海·星海纪元》');
    expect(first.author, '青衫客');
    expect(first.bookUrl, '${server.baseUrl}/utf8/book/101');
    expect(searchRes.trace.httpStatus, 200);
    expect(searchRes.trace.logs, contains('js search: 星海 page=1'));

    final detailRes = await provider.getBookDetail(first.bookUrl);
    expect(detailRes.detail.title, '《星海纪元》');
    expect(detailRes.detail.author, '青衫客');
    expect(detailRes.detail.wordCount, 128000);
    expect(detailRes.detail.tocUrl, '${server.baseUrl}/utf8/toc/101');

    final tocRes = await provider.getToc(detailRes.detail.tocUrl);
    expect(tocRes.chapters, hasLength(2));
    expect(tocRes.chapters.first.title, '第一章 启航');
    expect(tocRes.chapters.first.url, '${server.baseUrl}/utf8/chapter/1');

    final contentRes = await provider.getChapterContent(tocRes.chapters.first);
    expect(contentRes.content.rawText, contains('夜色深沉，港口灯火如星河垂落。'));
    expect(contentRes.content.rawText, contains('去寻找那座失落的图书馆！'));

    // Print latency metrics for PoC benchmark capture.
    // ignore: avoid_print
    print(
      '[BENCHMARK][JsPluginProvider] '
      'search=${searchRes.trace.elapsedMs}ms, '
      'detail=${detailRes.trace.elapsedMs}ms, '
      'toc=${tocRes.trace.elapsedMs}ms, '
      'content=${contentRes.trace.elapsedMs}ms',
    );
  });

  test('QjsSandboxRuntime interrupts synchronous infinite loop without crashing host', () async {
    final runtime = QjsSandboxRuntime(sourceId: 'runaway-sync');
    try {
      final sw = Stopwatch()..start();
      await expectLater(
        () => runtime.evaluate(
          'let n = 0; while (true) { n++; }',
          timeout: const Duration(milliseconds: 80),
        ),
        throwsA(
          isA<JsExecutionFailure>().having((e) => e.isTimeout, 'isTimeout', isTrue),
        ),
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));

      // Verify runtime remains healthy and usable after interruption.
      final recovery = await runtime.evaluate('6 * 7');
      expect(recovery.value, '42');
      // ignore: avoid_print
      print('[BENCHMARK][Timeout][SyncLoop] interrupted in ${sw.elapsedMilliseconds}ms');
    } finally {
      await runtime.dispose();
    }
  });

  test('JsPluginProvider interrupts post-await async infinite loop cleanly', () async {
    const runawayAfterAwaitScript = r'''
async function search(keyword, page) {
  const resp = await host.httpGet("/api/search?q=" + encodeURIComponent(keyword));
  if (resp.status === 200) {
    while (true) {}
  }
  return [];
}
''';
    final provider = JsPluginProvider(
      providerId: 'js-runaway-async',
      sourceName: 'Runaway Async',
      baseUrl: server.baseUrl,
      pluginScript: runawayAfterAwaitScript,
      httpClient: httpClient,
      scriptTimeout: const Duration(milliseconds: 120),
    );

    final sw = Stopwatch()..start();
    await expectLater(
      () => provider.search('test'),
      throwsA(
        isA<JsExecutionFailure>().having((e) => e.isTimeout, 'isTimeout', isTrue),
      ),
    );
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1500));
    // ignore: avoid_print
    print('[BENCHMARK][Timeout][PostAwaitLoop] interrupted in ${sw.elapsedMilliseconds}ms');
  });

  test('QjsSandboxRuntime isolates JS memory exhaustion and syntax/runtime errors', () async {
    final runtime = QjsSandboxRuntime(
      sourceId: 'memory-limit',
      memoryLimitBytes: 2 * 1024 * 1024, // 2 MiB hard cap
    );
    try {
      await expectLater(
        () => runtime.evaluate(
          'const chunks = []; for (let i = 0; i < 10000; i++) { chunks.push("x".repeat(4096)); }',
          timeout: const Duration(seconds: 2),
        ),
        throwsA(isA<JsExecutionFailure>()),
      );

      runtime.resetRuntime();

      await expectLater(
        () => runtime.evaluate('function broken() { throw new Error("boom"); } broken();'),
        throwsA(
          isA<JsExecutionFailure>()
              .having((e) => e.isTimeout, 'isTimeout', isFalse)
              .having((e) => e.message, 'message', contains('boom')),
        ),
      );
    } finally {
      await runtime.dispose();
    }
  });

  test('Background Isolate QuickJS supports cooperative CancellationToken interrupt', () async {
    final cancelToken = CancellationToken();
    final handlePort = ReceivePort();
    final sendPort = handlePort.sendPort;

    final futureResult = Isolate.run(() async {
      final rt = JSRuntime.create(const JSRuntimeConfig.hardened());
      sendPort.send(rt.interruptHandle);
      try {
        rt.evaluateJavascript('while (true) {}');
        return 'finished';
      } on JSException catch (e) {
        return e.toString();
      } finally {
        rt.release();
      }
    });

    final handle = await handlePort.first as JSInterruptHandle;
    handlePort.close();
    cancelToken.addListener(() {
      handle.requestInterrupt();
    });

    await Future<void>.delayed(const Duration(milliseconds: 60));
    cancelToken.cancel();

    final result = await futureResult;
    expect(result, contains('interrupted'));
  });

  test('JsPluginProvider maps HTTP 404 to NetworkFailure and measures warm latency', () async {
    final provider = JsPluginProvider(
      providerId: 'js-demo-warm',
      sourceName: 'JS Demo Source',
      baseUrl: server.baseUrl,
      pluginScript: _samplePluginScript,
      httpClient: httpClient,
    );

    await expectLater(
      () => provider.getBookDetail('/non-existent-book'),
      throwsA(
        isA<NetworkFailure>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );

    // Warm up once, then measure 10 iterations of chapter content fetch + CSS extraction.
    final chapter = ChapterMeta(
      bookId: '101',
      chapterIndex: 0,
      title: '第一章 启航',
      url: '${server.baseUrl}/utf8/chapter/1',
      updatedAt: DateTime.now().toUtc(),
    );
    await provider.getChapterContent(chapter);

    final samplesMs = <int>[];
    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      final res = await provider.getChapterContent(chapter);
      sw.stop();
      expect(res.content.rawText, contains('失落的图书馆'));
      samplesMs.add(sw.elapsedMilliseconds);
    }
    final avgMs = samplesMs.reduce((a, b) => a + b) / samplesMs.length;
    // ignore: avoid_print
    print('[BENCHMARK][JsPluginProvider][WarmContentAvg10] ${avgMs.toStringAsFixed(2)}ms (samples=$samplesMs)');
  });
}
