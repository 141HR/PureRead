import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';
import 'package:pureread/infrastructure/storage/app_path_resolver.dart';
import 'package:pureread/infrastructure/storage/chapter_cache_store.dart';

class _TestHttpServer {
  HttpServer? _server;
  final List<DateTime> hits = <DateTime>[];

  int get port => _server!.port;
  String get baseUrl => 'http://127.0.0.1:$port';

  Future<void> start(FutureOr<void> Function(HttpRequest req) handler) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server!.listen((req) async {
      hits.add(DateTime.now());
      await handler(req);
    });
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}

void main() {
  group('SourceHttpClient', () {
    late _TestHttpServer server;
    late SourceHttpClient client;

    setUp(() async {
      server = _TestHttpServer();
      client = SourceHttpClient();
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test('enforces per-host rateLimitMs across concurrent requests without blocking other hosts', () async {
      await server.start((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..write('ok:${req.uri.path}');
        await req.response.close();
      });

      final sameHostSw = Stopwatch()..start();
      await Future.wait(<Future<HttpFetchResult>>[
        client.request('${server.baseUrl}/1', rateLimitMs: 120),
        client.request('${server.baseUrl}/2', rateLimitMs: 120),
        client.request('${server.baseUrl}/3', rateLimitMs: 120),
      ]);
      sameHostSw.stop();

      // 3 serialized dispatches with 120ms spacing require >= 220ms elapsed.
      expect(sameHostSw.elapsedMilliseconds, greaterThanOrEqualTo(200));

      // Verify a different host (`localhost`) is not throttled by 127.0.0.1.
      final diffHostSw = Stopwatch()..start();
      await Future.wait(<Future<HttpFetchResult>>[
        client.request('http://127.0.0.1:${server.port}/a', rateLimitMs: 150),
        client.request('http://localhost:${server.port}/b', rateLimitMs: 150),
      ]);
      diffHostSw.stop();
      expect(diffHostSw.elapsedMilliseconds, lessThan(250));
    });

    test('isolates CookieJar strictly per host and exposes cookie helpers', () async {
      await server.start((req) async {
        if (req.uri.path == '/set') {
          final val = req.uri.queryParameters['v'] ?? 'default';
          req.response.headers.add(
            HttpHeaders.setCookieHeader,
            'sid=$val; Path=/',
          );
          req.response.write('set:$val');
          await req.response.close();
          return;
        }
        final cookie = req.headers.value(HttpHeaders.cookieHeader) ?? '';
        req.response.write('cookie=$cookie');
        await req.response.close();
      });

      await client.request('http://127.0.0.1:${server.port}/set?v=alpha');
      await client.request('http://localhost:${server.port}/set?v=beta');

      expect(
        await client.getKey('http://127.0.0.1:${server.port}#🎃', 'sid'),
        'alpha',
      );
      expect(
        await client.getKey('http://localhost:${server.port}', 'sid'),
        'beta',
      );
      expect(
        await client.getCookie('http://127.0.0.1:${server.port}'),
        'sid=alpha',
      );

      final r1 = await client.request('http://127.0.0.1:${server.port}/echo');
      final r2 = await client.request('http://localhost:${server.port}/echo');
      expect(r1.body, 'cookie=sid=alpha');
      expect(r2.body, 'cookie=sid=beta');

      await client.removeCookie('http://127.0.0.1:${server.port}#tag');
      expect(
        await client.getCookie('http://127.0.0.1:${server.port}'),
        isEmpty,
      );
      // Removing 127.0.0.1 must not disturb localhost.
      expect(
        await client.getKey('http://localhost:${server.port}', 'sid'),
        'beta',
      );

      await client.setCookie('http://127.0.0.1:${server.port}', 'token=xyz; mode=1');
      expect(
        await client.getKey('http://127.0.0.1:${server.port}', 'token'),
        'xyz',
      );
      expect(
        await client.getKey('http://127.0.0.1:${server.port}', 'mode'),
        '1',
      );
    });

    test('supports custom headers, POST bodies, 4xx/5xx mapping, and CancellationToken', () async {
      await server.start((req) async {
        if (req.uri.path == '/post') {
          final body = await utf8.decoder.bind(req).join();
          final custom = req.headers.value('x-custom') ?? '';
          final ctype = req.headers.value(HttpHeaders.contentTypeHeader) ?? '';
          req.response.write('$custom|$ctype|$body');
          await req.response.close();
          return;
        }
        if (req.uri.path == '/slow') {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          req.response.write('done');
          await req.response.close();
          return;
        }
        if (req.uri.path == '/err404') {
          req.response.statusCode = HttpStatus.notFound;
          req.response.write('missing');
          await req.response.close();
          return;
        }
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write('boom');
        await req.response.close();
      });

      final postResp = await client.request(
        '${server.baseUrl}/post',
        method: 'POST',
        data: 'a=1&b=2',
        headers: <String, String>{'X-Custom': 'PureRead'},
      );
      expect(
        postResp.body,
        contains('PureRead|application/x-www-form-urlencoded'),
      );
      expect(postResp.body, endsWith('|a=1&b=2'));

      await expectLater(
        () => client.request('${server.baseUrl}/err404'),
        throwsA(
          isA<NetworkFailure>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );

      await expectLater(
        () => client.request('${server.baseUrl}/err500'),
        throwsA(
          isA<NetworkFailure>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );

      // Pre-cancelled token
      final preToken = CancellationToken()..cancel();
      await expectLater(
        () => client.request('${server.baseUrl}/post', cancelToken: preToken),
        throwsA(isA<CancelledFailure>()),
      );

      // In-flight cancellation
      final liveToken = CancellationToken();
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 60),
          liveToken.cancel,
        ),
      );
      await expectLater(
        () => client.request('${server.baseUrl}/slow', cancelToken: liveToken),
        throwsA(isA<CancelledFailure>()),
      );

      // Malformed non-HTTP URL maps cleanly to NetworkFailure.
      await expectLater(
        () => client.request('晴天融合VIP4.0'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('decodes charsets strictly by priority explicit -> Content-Type -> meta -> UTF-8 -> GB18030/GBK without Charset.detect', () {
      const sample = '凡人修仙传·韩立';
      final gbkBytes = Uint8List.fromList(gbk.encode(sample));
      final utf8Bytes = Uint8List.fromList(utf8.encode(sample));

      // 1. explicitCharset overrides Content-Type
      final r1 = SourceHttpClient.decodeResponseBytes(
        gbkBytes,
        explicitCharset: 'gbk',
        contentTypeHeader: 'text/html; charset=utf-8',
      );
      expect(r1.text, sample);
      expect(r1.charsetName, 'gbk');

      // 2. Content-Type overrides <meta charset>
      final htmlMetaUtf8WithGbkBody = Uint8List.fromList(<int>[
        ...ascii.encode('<html><head><meta charset="utf-8"></head><body>'),
        ...gbkBytes,
        ...ascii.encode('</body></html>'),
      ]);
      final r2 = SourceHttpClient.decodeResponseBytes(
        htmlMetaUtf8WithGbkBody,
        contentTypeHeader: 'text/html; charset=GB2312',
      );
      expect(r2.text, contains(sample));
      expect(r2.charsetName, 'gb2312');

      // 3. <meta charset> used when header omits charset
      final r3 = SourceHttpClient.decodeResponseBytes(
        Uint8List.fromList(<int>[
          ...ascii.encode(
            '<html><head><meta http-equiv="Content-Type" content="text/html; charset=gbk"></head><body>',
          ),
          ...gbkBytes,
          ...ascii.encode('</body></html>'),
        ]),
      );
      expect(r3.text, contains(sample));
      expect(r3.charsetName, 'gbk');

      // 4. UTF-8 fallback before GBK
      final r4 = SourceHttpClient.decodeResponseBytes(utf8Bytes);
      expect(r4.text, sample);
      expect(r4.charsetName, 'utf-8');

      // 5. GB18030/GBK fallback when not valid UTF-8
      final r5 = SourceHttpClient.decodeResponseBytes(gbkBytes);
      expect(r5.text, sample);
      expect(r5.charsetName, 'gb18030');

      // 6. Never calls Charset.detect() (0xFE 0xFF would confuse Charset.detect into UTF-8/UTF-16!)
      final trickyBytes = Uint8List.fromList(<int>[0xFE, 0xFF, 0x41, 0x42]);
      final r6 = SourceHttpClient.decodeResponseBytes(trickyBytes);
      expect(r6.charsetName, isNot('utf-16'));

      // 7. Unknown explicit charset throws EncodingFailure
      expect(
        () => SourceHttpClient.decodeResponseBytes(
          utf8Bytes,
          explicitCharset: 'x-bogus-999',
        ),
        throwsA(isA<EncodingFailure>()),
      );
    });
  });

  group('ChapterCacheStore', () {
    late Directory tempDir;
    late AppPathResolver resolver;
    late ChapterCacheStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pureread_ch_cache_');
      resolver = await AppPathResolver.resolve(
        executablePath: p.join(tempDir.path, 'pureread.exe'),
        isWindowsOverride: false,
        supportDirProvider: () async => Directory(p.join(tempDir.path, 'data')),
        cacheDirProvider: () async =>
            Directory(p.join(tempDir.path, 'cache_root')),
      );
      store = ChapterCacheStore(resolver);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists, reads, measures, and clears chapter cache files safely', () async {
      expect(await store.getTotalCacheBytes(), 0);
      expect(await store.readChapter('book-1', 0), isNull);
      expect(await store.hasChapter('book-1', 0), isFalse);

      final key0 = await store.writeChapter('book-1', 0, '第一章 正文内容\n第二段');
      final key1 = await store.writeChapter('book-1', 1, '第二章 正文内容');
      final key2 = await store.writeChapter('book-2', 0, '另一本书正文');

      expect(key0, 'book-1/0.txt');
      expect(key1, 'book-1/1.txt');
      expect(key2, 'book-2/0.txt');
      expect(await store.hasChapter('book-1', 0), isTrue);
      expect(await store.readChapter('book-1', 0), '第一章 正文内容\n第二段');
      expect(
        await File(
          p.join(resolver.chaptersCacheDir.path, 'book-1', '0.txt'),
        ).exists(),
        isTrue,
      );

      final totalBefore = await store.getTotalCacheBytes();
      expect(totalBefore, greaterThan(0));

      await store.deleteChapter('book-1', 0);
      expect(await store.hasChapter('book-1', 0), isFalse);
      expect(await store.hasChapter('book-1', 1), isTrue);

      await store.deleteBookCache('book-1');
      expect(await store.hasChapter('book-1', 1), isFalse);
      expect(await store.hasChapter('book-2', 0), isTrue);

      final freed = await store.clearAllCache();
      expect(freed, greaterThan(0));
      expect(await store.getTotalCacheBytes(), 0);
      expect(await store.hasChapter('book-2', 0), isFalse);

      await expectLater(
        () => store.writeChapter('book-1', -1, 'invalid'),
        throwsA(isA<FileAccessFailure>()),
      );
      await expectLater(
        () => store.writeChapter('..', 0, 'escape'),
        throwsA(isA<FileAccessFailure>()),
      );
    });
  });
}
