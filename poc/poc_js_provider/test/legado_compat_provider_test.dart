import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poc_js_provider/domain/domain.dart';
import 'package:poc_js_provider/engine/source_engine/legado_compat/legado_compat_provider.dart';
import 'package:poc_js_provider/engine/source_engine/legado_compat/legado_source.dart';
import 'package:poc_js_provider/infrastructure/network/source_http_client.dart';

import 'fixtures/mock_book_server.dart';

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

  test('LegadoCompatProvider executes POST+Headers+GBK+CSS+Regex+<js> pipeline against loopback server', () async {
    final sourceJson = jsonEncode({
      'bookSourceName': '青冥书阁 (GBK 测试源)',
      'bookSourceUrl': server.baseUrl,
      'charset': 'GBK',
      'header': jsonEncode({'X-Client-Token': 'pureread-poc'}),
      'searchUrl':
          '/gbk/search,{"method":"POST","body":"keyword={{key}}&page={{page}}","charset":"GBK"}',
      'ruleSearch': {
        'bookList': 'div.book-item',
        'name': 'a.name@text##【测试】##',
        'author': 'span.author@text##^作者：##',
        'bookUrl': 'a.name@href',
        'intro': 'p.intro@text',
        'lastChapter': 'span.latest@text##^最新：##',
      },
      'ruleBookInfo': {
        'name': '#info h1@text',
        'author': '#info .writer@text',
        'intro': '#info .summary@text',
        'tocUrl': '#all-chapters@href',
      },
      'ruleToc': {
        'chapterList': 'dl.chapter-dl dd',
        'chapterName': 'a@text',
        'chapterUrl': 'a@href',
      },
      'ruleContent': {
        'content':
            r'#content@html##【广告：.*?】##'
            '\n'
            r'<js>result.replace(/请收藏本站：.*$/m, "").trim()</js>',
      },
    });

    final source = LegadoBookSource.fromJsonString(sourceJson);
    final provider = LegadoCompatProvider(
      providerId: 'legado-gbk-demo',
      source: source,
      httpClient: httpClient,
    );

    final searchRes = await provider.search('剑来', page: 1);
    expect(searchRes.items, hasLength(1));
    final book = searchRes.items.first;
    expect(book.title, '剑来青冥');
    expect(book.author, '风起青萍');
    expect(book.latestChapterTitle, '第二章 问剑山巅');
    expect(book.bookUrl, '${server.baseUrl}/gbk/book/202');
    expect(searchRes.trace.matchedPreview, contains('charset=gbk'));

    final detailRes = await provider.getBookDetail(book.bookUrl);
    expect(detailRes.detail.title, '剑来青冥');
    expect(detailRes.detail.author, '风起青萍');
    expect(detailRes.detail.tocUrl, '${server.baseUrl}/gbk/toc/202');

    final tocRes = await provider.getToc(detailRes.detail.tocUrl);
    expect(tocRes.chapters, hasLength(2));
    expect(tocRes.chapters.first.title, '第一章 初入山门');
    expect(tocRes.chapters.first.url, '${server.baseUrl}/gbk/chapter/1');

    final contentRes = await provider.getChapterContent(tocRes.chapters.first);
    expect(contentRes.content.rawText, contains('山风拂过石阶，带来松涛阵阵！'));
    expect(contentRes.content.rawText, contains('“原来这里便是青冥宗。”'));
    expect(contentRes.content.rawText, isNot(contains('广告')));
    expect(contentRes.content.rawText, isNot(contains('请收藏本站')));

    // ignore: avoid_print
    print(
      '[BENCHMARK][LegadoCompatProvider] '
      'search=${searchRes.trace.elapsedMs}ms, '
      'detail=${detailRes.trace.elapsedMs}ms, '
      'toc=${tocRes.trace.elapsedMs}ms, '
      'content=${contentRes.trace.elapsedMs}ms',
    );
  });

  test('LegadoCompatProvider returns structured UnsupportedLegadoRuleFailure when webView: true', () async {
    final topLevelWebViewSource = LegadoBookSource.fromJson({
      'bookSourceName': 'Cloudflare WebView Source',
      'bookSourceUrl': server.baseUrl,
      'webView': true,
      'searchUrl': '/gbk/search',
      'ruleSearch': {'bookList': 'div.book-item', 'name': 'a@text', 'bookUrl': 'a@href'},
    });
    final provider1 = LegadoCompatProvider(
      providerId: 'legado-webview-top',
      source: topLevelWebViewSource,
      httpClient: httpClient,
    );

    await expectLater(
      () => provider1.search('test'),
      throwsA(
        isA<UnsupportedLegadoRuleFailure>()
            .having((e) => e.feature, 'feature', 'webView')
            .having((e) => e.message, 'message', contains('webView: true')),
      ),
    );

    final urlOptionWebViewSource = LegadoBookSource.fromJson({
      'bookSourceName': 'SearchUrl WebView Source',
      'bookSourceUrl': server.baseUrl,
      'searchUrl': '/gbk/search,{"webView":true}',
      'ruleSearch': {'bookList': 'div.book-item', 'name': 'a@text', 'bookUrl': 'a@href'},
    });
    final provider2 = LegadoCompatProvider(
      providerId: 'legado-webview-url',
      source: urlOptionWebViewSource,
      httpClient: httpClient,
    );

    await expectLater(
      () => provider2.search('test'),
      throwsA(
        isA<UnsupportedLegadoRuleFailure>()
            .having((e) => e.feature, 'feature', 'webView'),
      ),
    );
  });

  test('LegadoCompatProvider catches runaway <js> infinite loop safely', () async {
    final badJsSource = LegadoBookSource.fromJson({
      'bookSourceName': 'Malicious JS Legado Source',
      'bookSourceUrl': server.baseUrl,
      'charset': 'GBK',
      'header': {'X-Client-Token': 'pureread-poc'},
      'searchUrl': '/gbk/search,{"method":"POST","body":"keyword={{key}}"}',
      'ruleSearch': {
        'bookList': 'div.book-item',
        'name': 'a.name@text<js>while(true){}</js>',
        'bookUrl': 'a.name@href',
      },
    });

    final provider = LegadoCompatProvider(
      providerId: 'legado-bad-js',
      source: badJsSource,
      httpClient: httpClient,
      jsTimeout: const Duration(milliseconds: 80),
    );

    await expectLater(
      () => provider.search('剑来'),
      throwsA(
        isA<JsExecutionFailure>().having((e) => e.isTimeout, 'isTimeout', isTrue),
      ),
    );
  });

  test('LegadoCompatProvider flags Rhino Packages.* / java.webView as UnsupportedLegadoRuleFailure', () async {
    final rhinoSource = LegadoBookSource.fromJson({
      'bookSourceName': 'Rhino Java API Source',
      'bookSourceUrl': server.baseUrl,
      'charset': 'GBK',
      'header': {'X-Client-Token': 'pureread-poc'},
      'searchUrl': '/gbk/search,{"method":"POST","body":"keyword={{key}}"}',
      'ruleSearch': {
        'bookList': 'div.book-item',
        'name': 'a.name@text<js>Packages.java.lang.System.currentTimeMillis()</js>',
        'bookUrl': 'a.name@href',
      },
    });

    final provider = LegadoCompatProvider(
      providerId: 'legado-rhino',
      source: rhinoSource,
      httpClient: httpClient,
    );

    await expectLater(
      () => provider.search('剑来'),
      throwsA(
        isA<UnsupportedLegadoRuleFailure>()
            .having((e) => e.feature, 'feature', 'rhino_java_api'),
      ),
    );
  });
}
