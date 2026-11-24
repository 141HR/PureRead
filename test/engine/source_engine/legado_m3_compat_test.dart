import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_compat.dart';
import 'package:pureread/engine/source_engine/parsing/legado_selector_engine.dart';
import 'package:pureread/infrastructure/js/js_crypto_helpers.dart';
import 'package:pureread/infrastructure/js/qjs_sandbox_runtime.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

class _M3MockCryptoRegexServer {
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
    if (path == '/search') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<!DOCTYPE html>
<html><body>
  <DIV class="RESULT-ITEM" data-id="101">
    <A href="/book/101-raw">剑道长生【精校】</A>
    <span class="author">作者：青衫客</span>
    <img src="/cover/101.jpg"/>
  </DIV>
  <DIV class="RESULT-ITEM" data-id="102">
    <A href="/book/102-raw">星海问道</A>
    <span class="author">作者：南宫羽</span>
    <img data-src="/cover/102.jpg"/>
  </DIV>
</body></html>
''');
      await req.response.close();
      return;
    }

    if (path == '/book/101') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<html><body>
  <h1>剑道长生</h1>
  <div class="writer">青衫客</div>
  <a id="toc" href="/toc/101">目录</a>
</body></html>
''');
      await req.response.close();
      return;
    }

    if (path == '/toc/101') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<html><body>
  <div class="volume">
    <a data-cid="c1" class="vip-tag name" href="/chapter/1?from=toc">🔒 第一章 初入剑宗</a>
    <a data-cid="c2" class="name" href="/chapter/2?from=toc">第二章 剑气如霜</a>
  </div>
</body></html>
''');
      await req.response.close();
      return;
    }

    if (path == '/chapter/c1') {
      const key = 'f041c49714d39908';
      const iv = '0123456789abcdef';
      final encrypted = JsCryptoHelpers.aesEncryptBase64(
        '青峰之上，剑鸣不止！\n第一段正文结束。',
        key,
        transformation: 'AES/CBC/PKCS5Padding',
        iv: iv,
      );
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(<String, Object?>{'data': encrypted}));
      await req.response.close();
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }
}

void main() {
  group('JsCryptoHelpers symmetric AES & DES', () {
    test('matches NIST FIPS-197 AES-128/192/256 ECB & SP 800-38A CBC vectors', () {
      final pt = JsCryptoHelpers.hexDecodeBytes(
        '00112233445566778899aabbccddeeff',
      );

      // FIPS-197 Appendix C.1 (AES-128)
      final k128 = JsCryptoHelpers.hexDecodeBytes(
        '000102030405060708090a0b0c0d0e0f',
      );
      final c128 = JsCryptoHelpers.encryptSymmetric(
        data: pt,
        key: k128,
        transformation: 'AES/ECB/NoPadding',
      );
      expect(
        JsCryptoHelpers.hexEncode(c128),
        '69c4e0d86a7b0430d8cdb78070b4c55a',
      );
      expect(
        JsCryptoHelpers.decryptSymmetric(
          data: c128,
          key: k128,
          transformation: 'AES/ECB/NoPadding',
        ),
        pt,
      );

      // FIPS-197 Appendix C.2 (AES-192)
      final k192 = JsCryptoHelpers.hexDecodeBytes(
        '000102030405060708090a0b0c0d0e0f1011121314151617',
      );
      final c192 = JsCryptoHelpers.encryptSymmetric(
        data: pt,
        key: k192,
        transformation: 'AES/ECB/NoPadding',
      );
      expect(
        JsCryptoHelpers.hexEncode(c192),
        'dda97ca4864cdfe06eaf70a0ec0d7191',
      );
      expect(
        JsCryptoHelpers.decryptSymmetric(
          data: c192,
          key: k192,
          transformation: 'AES/ECB/NoPadding',
        ),
        pt,
      );

      // FIPS-197 Appendix C.3 (AES-256)
      final k256 = JsCryptoHelpers.hexDecodeBytes(
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
      );
      final c256 = JsCryptoHelpers.encryptSymmetric(
        data: pt,
        key: k256,
        transformation: 'AES/ECB/NoPadding',
      );
      expect(
        JsCryptoHelpers.hexEncode(c256),
        '8ea2b7ca516745bfeafc49904b496089',
      );
      expect(
        JsCryptoHelpers.decryptSymmetric(
          data: c256,
          key: k256,
          transformation: 'AES/ECB/NoPadding',
        ),
        pt,
      );

      // NIST SP 800-38A F.2.1 (CBC-AES128)
      final cbcKey = JsCryptoHelpers.hexDecodeBytes(
        '2b7e151628aed2a6abf7158809cf4f3c',
      );
      final cbcIv = JsCryptoHelpers.hexDecodeBytes(
        '000102030405060708090a0b0c0d0e0f',
      );
      final cbcPt = JsCryptoHelpers.hexDecodeBytes(
        '6bc1bee22e409f96e93d7e117393172a'
        'ae2d8a571e03ac9c9eb76fac45af8e51',
      );
      final cbcCipher = JsCryptoHelpers.encryptSymmetric(
        data: cbcPt,
        key: cbcKey,
        iv: cbcIv,
        transformation: 'AES/CBC/NoPadding',
      );
      expect(
        JsCryptoHelpers.hexEncode(cbcCipher),
        '7649abac8119b246cee98e9b12e9197d'
        '5086cb9b507219ee95db113a917678b2',
      );
      expect(
        JsCryptoHelpers.decryptSymmetric(
          data: cbcCipher,
          key: cbcKey,
          iv: cbcIv,
          transformation: 'AES/CBC/NoPadding',
        ),
        cbcPt,
      );
    });

    test('matches FIPS-46 DES vector and supports ECB/CBC + all paddings + IV normalization', () {
      // FIPS-46 / FIPS-81 standard DES vector
      final desKey = JsCryptoHelpers.hexDecodeBytes('133457799bbcdff1');
      final desPt = JsCryptoHelpers.hexDecodeBytes('0123456789abcdef');
      final desCipher = JsCryptoHelpers.encryptSymmetric(
        data: desPt,
        key: desKey,
        transformation: 'DES/ECB/NoPadding',
      );
      expect(JsCryptoHelpers.hexEncode(desCipher), '85e813540f0ab405');
      expect(
        JsCryptoHelpers.decryptSymmetric(
          data: desCipher,
          key: desKey,
          transformation: 'DES/ECB/NoPadding',
        ),
        desPt,
      );

      // DES CBC round-trip with UTF-8 string + PKCS5/PKCS7/ZeroPadding
      final key8 = utf8.encode('snY%169j');
      final iv8 = utf8.encode('1ae2c94b');
      final payload = utf8.encode('净读 PureRead DES-CBC 测试文本 123456');
      for (final transformation in <String>[
        'DES/ECB/PKCS5Padding',
        'DES/CBC/PKCS5Padding',
        'DES/CBC/PKCS7Padding',
        'DES/CBC/ZeroPadding',
      ]) {
        final enc = JsCryptoHelpers.encryptSymmetric(
          data: payload,
          key: key8,
          iv: iv8,
          transformation: transformation,
        );
        final dec = JsCryptoHelpers.decryptSymmetric(
          data: enc,
          key: key8,
          iv: iv8,
          transformation: transformation,
        );
        expect(dec, payload, reason: transformation);
      }

      // AES convenience Base64 & Hex round-trips across 16/24/32-byte keys & paddings
      for (final key in <String>[
        '0123456789abcdef',
        '0123456789abcdefghijklmn',
        '0123456789abcdef0123456789abcdef',
      ]) {
        for (final pad in <String>[
          'PKCS5Padding',
          'PKCS7Padding',
          'ZeroPadding',
        ]) {
          final tr = 'AES/CBC/$pad';
          final b64 = JsCryptoHelpers.aesEncryptBase64(
            '净读 AES Multi-Block 中文内容 0123456789ABCDEF!',
            key,
            transformation: tr,
            iv: 'iv-16-bytes-here',
          );
          expect(
            JsCryptoHelpers.aesDecryptBase64(
              b64,
              key,
              transformation: tr,
              iv: 'iv-16-bytes-here',
            ),
            '净读 AES Multi-Block 中文内容 0123456789ABCDEF!',
          );

          final hex = JsCryptoHelpers.aesEncryptHex(
            'exact-block-16!!',
            key,
            transformation: tr,
            iv: 'iv-16-bytes-here',
          );
          expect(
            JsCryptoHelpers.aesDecryptHex(
              hex,
              key,
              transformation: tr,
              iv: 'iv-16-bytes-here',
            ),
            'exact-block-16!!',
          );
        }
      }

      // CBC zero-IV fallback & IV truncation/padding normalization
      final encNullIv = JsCryptoHelpers.aesEncryptBase64(
        'zero-iv-check',
        '0123456789abcdef',
        transformation: 'AES/CBC/PKCS5Padding',
      );
      final encExplicitZeroIv = JsCryptoHelpers.encryptSymmetric(
        data: utf8.encode('zero-iv-check'),
        key: utf8.encode('0123456789abcdef'),
        transformation: 'AES/CBC/PKCS5Padding',
        iv: Uint8List(16),
      );
      expect(encNullIv, base64Encode(encExplicitZeroIv));

      final encShortIv = JsCryptoHelpers.aesEncryptBase64(
        'short-iv',
        '0123456789abcdef',
        transformation: 'AES/CBC/PKCS5Padding',
        iv: 'abc',
      );
      expect(
        JsCryptoHelpers.aesDecryptBase64(
          encShortIv,
          '0123456789abcdef',
          transformation: 'AES/CBC/PKCS5Padding',
          iv: 'abc\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00',
        ),
        'short-iv',
      );

      final encLongIv = JsCryptoHelpers.aesEncryptBase64(
        'long-iv',
        '0123456789abcdef',
        transformation: 'AES/CBC/PKCS5Padding',
        iv: '0123456789abcdefEXTRA',
      );
      expect(
        JsCryptoHelpers.aesDecryptBase64(
          encLongIv,
          '0123456789abcdef',
          transformation: 'AES/CBC/PKCS5Padding',
          iv: '0123456789abcdef',
        ),
        'long-iv',
      );
    });

    test('throws explicit errors on invalid parameters without crashing', () {
      expect(
        () => JsCryptoHelpers.encryptSymmetric(
          data: utf8.encode('hi'),
          key: utf8.encode('too-short'),
          transformation: 'AES/ECB/PKCS5Padding',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('16, 24, or 32'),
          ),
        ),
      );

      expect(
        () => JsCryptoHelpers.encryptSymmetric(
          data: utf8.encode('hi'),
          key: utf8.encode('7bytes!'),
          transformation: 'DES/ECB/PKCS5Padding',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('8 bytes'),
          ),
        ),
      );

      expect(
        () => JsCryptoHelpers.encryptSymmetric(
          data: utf8.encode('hi'),
          key: utf8.encode('0123456789abcdef'),
          transformation: 'RC4/ECB/PKCS5Padding',
        ),
        throwsArgumentError,
      );

      expect(
        () => JsCryptoHelpers.encryptSymmetric(
          data: utf8.encode('hi'),
          key: utf8.encode('0123456789abcdef'),
          transformation: 'AES/CTR/PKCS5Padding',
        ),
        throwsArgumentError,
      );

      expect(
        () => JsCryptoHelpers.encryptSymmetric(
          data: utf8.encode('not-aligned'),
          key: utf8.encode('0123456789abcdef'),
          transformation: 'AES/ECB/NoPadding',
        ),
        throwsArgumentError,
      );

      expect(
        () => JsCryptoHelpers.decryptSymmetric(
          data: Uint8List(16),
          key: utf8.encode('0123456789abcdef'),
          transformation: 'AES/ECB/PKCS5Padding',
        ),
        throwsFormatException,
      );

      expect(
        () => JsCryptoHelpers.aesDecryptHex(
          'xyz-not-hex',
          '0123456789abcdef',
          transformation: 'AES/ECB/PKCS5Padding',
        ),
        throwsFormatException,
      );
    });
  });

  group('QuickJS host & Legado java.* symmetric crypto bridges', () {
    test('exposes host.aesEncodeBase64, host.aesDecodeBase64, and host.symmetricCrypto safely', () async {
      final runtime = QjsSandboxRuntime(sourceId: 'qjs-crypto');
      try {
        final res = await runtime.evaluate('''
          const key = "f041c49714d39908";
          const iv = "0123456789abcdef";
          const b64 = host.aesEncodeBase64("PureRead-Host", key, "AES/CBC/PKCS5Padding", iv);
          const dec = host.aesDecodeBase64(b64, key, "AES/CBC/PKCS5Padding", iv);
          const desHex = host.symmetricCrypto("encryptHex", "DES/ECB/PKCS5Padding", "snY%169j", null, "DES-Host");
          const desDec = host.symmetricCrypto("decryptHexStr", "DES/ECB/PKCS5Padding", "snY%169j", null, desHex);
          let errMsg = "";
          try {
            host.aesEncodeBase64("x", "bad-key", "AES/ECB/PKCS5Padding");
          } catch (e) {
            errMsg = String(e.message || e);
          }
          JSON.stringify({ b64, dec, desHex, desDec, errMsg });
        ''');

        final decoded = jsonDecode(res.value) as Map<String, dynamic>;
        expect(decoded['dec'], 'PureRead-Host');
        expect(decoded['desDec'], 'DES-Host');
        expect(decoded['errMsg'], contains('Invalid AES key length'));

        await expectLater(
          () => runtime.evaluate(
            'host.symmetricCrypto("decryptBase64Str", "AES/CBC/PKCS5Padding", "bad", "", "AAAA")',
          ),
          throwsA(
            isA<JsExecutionFailure>().having(
              (e) => e.message,
              'message',
              contains('Invalid AES key length'),
            ),
          ),
        );
      } finally {
        await runtime.dispose();
      }
    });

    test('supports java.aes* and java.createSymmetricCrypto for AES/DES with String & Array<int> keys/IVs', () async {
      const evaluator = LegadoRuleEvaluator(sourceId: 'legado-crypto-js');
      final out = await evaluator.evaluateString(
        '',
        '''
        <js>
        const aesKey = "f041c49714d39908";
        const aesIv = "0123456789abcdef";
        const b64 = java.aesBase64Encode("净读AES测试", aesKey, "AES/CBC/PKCS5Padding", aesIv);
        const b64Alias = java.aesEncodeToString("净读AES测试", aesKey, "AES/CBC/PKCS5Padding", aesIv);
        const plain1 = java.aesBase64DecodeToString(b64, aesKey, "AES/CBC/PKCS5Padding", aesIv);
        const plain2 = java.aesDecodeToString(b64Alias, aesKey, "AES/CBC/PKCS5Padding", aesIv);

        const aesCrypto = java.createSymmetricCrypto("AES/CBC/PKCS5Padding", aesKey, aesIv);
        const cB64 = aesCrypto.encryptBase64("Hello Crypto");
        const cHex = aesCrypto.encryptHex("Hello Crypto");
        const rawBytes = aesCrypto.decrypt(cB64);
        const dStr = aesCrypto.decryptStr(cHex);
        const dB64 = aesCrypto.decryptBase64Str(cB64);
        const dHex = aesCrypto.decryptHexStr(cHex);
        const dFromBytes = java.aesDecodeToString(java.base64DecodeToByteArray(cB64), aesKey, "AES/CBC/PKCS5Padding", aesIv);

        const desCrypto = java.createSymmetricCrypto("DES/ECB/PKCS5Padding", "snY%169j");
        const desB64 = desCrypto.encryptBase64("DES-ECB-OK");
        const desPlain = desCrypto.decryptBase64Str(desB64);

        const keyArr = java.strToBytes("0123456789abcdef");
        const signedIv = [-1, 0, 127, -128, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
        const arrCrypto = java.createSymmetricCrypto("AES/CBC/PKCS7Padding", keyArr, new Uint8Array(signedIv));
        const arrEnc = arrCrypto.encryptBase64("ArrayKeyIV");
        const arrDec = java.createSymmetricCrypto("AES/CBC/PKCS7Padding", keyArr, signedIv).decryptStr(arrEnc);

        JSON.stringify({
          sameEnc: b64 === b64Alias,
          plain1,
          plain2,
          dStr,
          dB64,
          dHex,
          dFromBytes,
          rawBytesLen: rawBytes.length,
          desPlain,
          arrDec,
        });
        </js>
        ''',
        baseUrl: 'https://example.com',
      );

      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['sameEnc'], isTrue);
      expect(decoded['plain1'], '净读AES测试');
      expect(decoded['plain2'], '净读AES测试');
      expect(decoded['dStr'], 'Hello Crypto');
      expect(decoded['dB64'], 'Hello Crypto');
      expect(decoded['dHex'], 'Hello Crypto');
      expect(decoded['dFromBytes'], 'Hello Crypto');
      expect(decoded['rawBytesLen'], 12);
      expect(decoded['desPlain'], 'DES-ECB-OK');
      expect(decoded['arrDec'], 'ArrayKeyIV');
    });
  });

  group('Legado :regex / @regex: all-in-one list rules', () {
    test('translates inline flags, preserves :: CSS, and handles && narrowing chains', () {
      const html = '''
      <div class="ignored">skip</div>
      <div class="SECTION">
        <a href="/ch/1">First</a>
        <A href="/ch/2">Second
Line</A>
      </div>
      ''';

      expect(LegadoSelectorEngine.isRegexListRule(':abc'), isTrue);
      expect(LegadoSelectorEngine.isRegexListRule('@Regex:abc'), isTrue);
      expect(LegadoSelectorEngine.isRegexListRule('::before'), isFalse);

      // Multiline + case-insensitive with `&&` narrowing chain
      final items = LegadoSelectorEngine.selectElements(
        html,
        r':(?is)<div class="section">.*?</div>&&<a href="([^"]+)">(.*?)</a>',
      );
      expect(items, hasLength(2));
      expect(LegadoSelectorEngine.selectOne(items[0], r'$1'), '/ch/1');
      expect(LegadoSelectorEngine.selectOne(items[0], r'$2'), 'First');
      expect(LegadoSelectorEngine.selectOne(items[1], r'$1'), '/ch/2');
      expect(LegadoSelectorEngine.selectOne(items[1], r'$2'), 'Second\nLine');

      // (?m) multiline anchors via @regex:
      const lines = '101 | Alpha\n102 | Beta';
      final lineItems = LegadoSelectorEngine.selectElements(
        lines,
        r'@regex:(?m)^(\d+)\s*\|\s*(.+)$',
      );
      expect(lineItems, hasLength(2));
      expect(LegadoSelectorEngine.selectOne(lineItems[1], r'$1:$2'), '102:Beta');
    });

    test('propagates capture groups across ##regex##, @js:, {{...}}, and CSS/XPath/JSONPath unchanged', () async {
      const evaluator = LegadoRuleEvaluator(sourceId: 'regex-eval');

      const tocHtml = '''
      <a href="/c/10" class="isvip name">第十二章 破境【VIP】</a>
      <a href="/c/11" class="name">第十三章 归来</a>
      ''';

      final blocks = await evaluator.evaluateListBlocks(
        tocHtml,
        r':(?s)/c/(\d+)" class="(isvip )?[^"]*name">([^<]*)',
        baseUrl: 'https://example.com',
      );
      expect(blocks.items, hasLength(2));

      // Capture substitution + ##replace## + @js: + {{...}}
      final ch0Name = await evaluator.evaluateString(
        blocks.items[0],
        r'$2$3##【VIP】##<js>java.toNumChapter(result)</js>',
        baseUrl: 'https://example.com',
      );
      final ch0Url = await evaluator.evaluateString(
        blocks.items[0],
        r'https://example.com/api/{{$1}}?sig={{java.md5Encode($1)}}',
        baseUrl: 'https://example.com',
      );
      final ch1Name = await evaluator.evaluateString(
        blocks.items[1],
        r'$2$3@js:java.toNumChapter(result)',
        baseUrl: 'https://example.com',
      );
      final ch1JsDirect = await evaluator.evaluateString(
        blocks.items[1],
        r'@js:$1 + ":" + $3',
        baseUrl: 'https://example.com',
      );

      expect(ch0Name, 'isvip 第12章 破境');
      expect(
        ch0Url,
        'https://example.com/api/10?sig=d3d9446802a44259755d38e6d163e820',
      );
      expect(ch1Name, '第13章 归来');
      expect(ch1JsDirect, '11:第十三章 归来');

      // Normal CSS, XPath, and JSONPath rules remain unaffected
      expect(
        await evaluator.evaluateString(
          '<div class="b"><span>Book</span></div>',
          'class.b@tag.span@text',
          baseUrl: 'https://example.com',
        ),
        'Book',
      );
      expect(
        await evaluator.evaluateString(
          '<div><a href="/x">Link</a></div>',
          '@XPath://a/@href',
          baseUrl: 'https://example.com',
        ),
        '/x',
      );
      expect(
        await evaluator.evaluateString(
          '{"book":{"name":"凡人修仙传"}}',
          r'$.book.name',
          baseUrl: 'https://example.com',
        ),
        '凡人修仙传',
      );
    });

    test('runs end-to-end LegadoCompatProvider with :regex search, -@regex: TOC, and AES chapter decryption', () async {
      final server = _M3MockCryptoRegexServer();
      await server.start();
      final httpClient = SourceHttpClient();

      try {
        final source = LegadoBookSource.fromJson(<String, Object?>{
          'bookSourceName': 'M3 Regex+AES 书源',
          'bookSourceUrl': server.baseUrl,
          'bookSourceType': 0,
          'searchUrl': '/search?q={{key}}',
          'ruleSearch': <String, Object?>{
            'bookList':
                r':(?is)<div class="result-item" data-id="(\d+)">\s*<a href="([^"]+)">(.*?)</a>\s*<span class="author">(.*?)</span>\s*<img (?:src|data-src)="([^"]+)"',
            'name': r'$3##【精校】##',
            'author': r'$4##^作者：##',
            'bookUrl': r'/book/$1',
            'coverUrl': r'$5',
          },
          'ruleBookInfo': <String, Object?>{
            'name': 'h1@text',
            'author': '.writer@text',
            'tocUrl': '#toc@href',
          },
          'ruleToc': <String, Object?>{
            'chapterList':
                r'-@regex:(?is)<a data-cid="([^"]+)" class="(vip-tag )?name"[^>]*>(.*?)</a>',
            'chapterName': r'$2$3##vip-tag ##[VIP] ##<js>java.toNumChapter(result)</js>',
            'chapterUrl': r'/chapter/$1',
          },
          'ruleContent': <String, Object?>{
            'content': '''
<js>
const body = JSON.parse(result);
java.createSymmetricCrypto("AES/CBC/PKCS5Padding", "f041c49714d39908", "0123456789abcdef").decryptStr(body.data);
</js>
''',
          },
        });

        final provider = LegadoCompatProvider(
          providerId: 'm3-e2e',
          source: source,
          httpClient: httpClient,
          rateLimitMsOverride: 0,
        );

        final searchRes = await provider.search('剑道');
        expect(searchRes.items, hasLength(2));
        expect(searchRes.items[0].title, '剑道长生');
        expect(searchRes.items[0].author, '青衫客');
        expect(searchRes.items[0].bookUrl, '${server.baseUrl}/book/101');
        expect(searchRes.items[0].coverUrl, '${server.baseUrl}/cover/101.jpg');
        expect(searchRes.items[1].title, '星海问道');
        expect(searchRes.items[1].coverUrl, '${server.baseUrl}/cover/102.jpg');

        final detailRes = await provider.getBookDetail(
          searchRes.items[0].bookUrl,
        );
        expect(detailRes.detail.title, '剑道长生');
        expect(detailRes.detail.tocUrl, '${server.baseUrl}/toc/101');

        final tocRes = await provider.getToc(detailRes.detail.tocUrl);
        expect(tocRes.chapters, hasLength(2));
        // Reversed by `-@regex:`
        expect(tocRes.chapters[0].title, '第2章 剑气如霜');
        expect(tocRes.chapters[0].url, '${server.baseUrl}/chapter/c2');
        expect(tocRes.chapters[1].title, '[VIP] 🔒 第1章 初入剑宗');
        expect(tocRes.chapters[1].url, '${server.baseUrl}/chapter/c1');

        final contentRes = await provider.getChapterContent(tocRes.chapters[1]);
        expect(contentRes.content.rawText, '青峰之上，剑鸣不止！\n第一段正文结束。');
      } finally {
        httpClient.close();
        await server.close();
      }
    });
  });
}
