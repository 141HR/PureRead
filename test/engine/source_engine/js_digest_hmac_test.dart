import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/js/js_crypto_helpers.dart';
import 'package:pureread/infrastructure/js/qjs_sandbox_runtime.dart';

void main() {
  group('JsCryptoHelpers SHA-1 / SHA-256 / SHA-512 / MD5 digests', () {
    test('matches official NIST FIPS 180-4 SHA-1 vectors', () {
      expect(
        JsCryptoHelpers.digestHex('', 'SHA-1'),
        'da39a3ee5e6b4b0d3255bfef95601890afd80709',
      );
      expect(
        JsCryptoHelpers.digestHex('abc', 'sha1'),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
      expect(
        JsCryptoHelpers.digestHex(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          'SHA1',
        ),
        '84983e441c3bd26ebaae4aa1f95129e5e54670f1',
      );
      expect(
        JsCryptoHelpers.digestHex(
          'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu',
          'sha-1',
        ),
        'a49b2446a02c645bf419f995b67091253a04a259',
      );
      expect(
        JsCryptoHelpers.digestBytes(Uint8List.fromList(utf8.encode('abc')), 'SHA-1'),
        JsCryptoHelpers.hexDecodeBytes('a9993e364706816aba3e25717850c26c9cd0d89d'),
      );
    });

    test('matches official NIST FIPS 180-4 SHA-256 vectors', () {
      expect(
        JsCryptoHelpers.digestHex('', 'SHA-256'),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        JsCryptoHelpers.digestHex('abc', 'sha256'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        JsCryptoHelpers.digestHex(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          'SHA256',
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      expect(
        JsCryptoHelpers.digestHex(
          'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu',
          'sha-256',
        ),
        'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
      );
      expect(
        JsCryptoHelpers.digestBase64('abc', 'SHA-256'),
        base64Encode(
          JsCryptoHelpers.hexDecodeBytes(
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          ),
        ),
      );
    });

    test('matches official NIST FIPS 180-4 SHA-512 vectors and MD5 alias', () {
      expect(
        JsCryptoHelpers.digestHex('', 'SHA-512'),
        'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce'
        '47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e',
      );
      expect(
        JsCryptoHelpers.digestHex('abc', 'sha512'),
        'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
        '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
      );
      expect(
        JsCryptoHelpers.digestHex(
          'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu',
          'SHA512',
        ),
        '8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018'
        '501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909',
      );
      expect(
        JsCryptoHelpers.digestHex('abc', 'md5'),
        '900150983cd24fb0d6963f7d28e17f72',
      );
      expect(
        JsCryptoHelpers.hexEncodeString('PureRead净读'),
        '5075726552656164e58780e8afbb',
      );
      expect(
        JsCryptoHelpers.hexEncodeString(<int>[0x00, 0x0f, 0xa0, 0xff]),
        '000fa0ff',
      );
    });
  });

  group('JsCryptoHelpers RFC 2104 / 2202 / 4231 HMAC', () {
    test('matches RFC 2202 HMAC-MD5 & HMAC-SHA1 vectors including long keys', () {
      // RFC 2202 Test Case 1
      expect(
        JsCryptoHelpers.hmacHex(
          'Hi There',
          Uint8List.fromList(List<int>.filled(16, 0x0b)),
          'HmacMD5',
        ),
        '9294727a3638bb1c13f48ef8158bfc9d',
      );
      expect(
        JsCryptoHelpers.hmacHex(
          'Hi There',
          Uint8List.fromList(List<int>.filled(20, 0x0b)),
          'hmacsha1',
        ),
        'b617318655057264e28bc0b6fb378c8ef146be00',
      );

      // RFC 2202 Test Case 2
      expect(
        JsCryptoHelpers.hmacHex(
          'what do ya want for nothing?',
          'Jefe',
          'HMACMD5',
        ),
        '750c783e6ab0b503eaa86e310a5db738',
      );
      expect(
        JsCryptoHelpers.hmacHex(
          'what do ya want for nothing?',
          'Jefe',
          'HmacSHA1',
        ),
        'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79',
      );

      // Keys longer than 64-byte block size
      final longKey80 = Uint8List.fromList(List<int>.filled(80, 0xaa));
      const longMsg = 'Test Using Larger Than Block-Size Hash Key - Hash Key First';
      expect(
        JsCryptoHelpers.hmacHex(longMsg, longKey80, 'HmacMD5'),
        '3e676e40f5cc0bc5cc0e6f9ee697e184',
      );
      expect(
        JsCryptoHelpers.hmacHex(longMsg, longKey80, 'HmacSHA1'),
        '1b50645102da0b9ea3b04102b199ad4546ab6f15',
      );
    });

    test('matches RFC 4231 HMAC-SHA256 & HMAC-SHA512 vectors including >128-byte keys', () {
      final key20 = Uint8List.fromList(List<int>.filled(20, 0x0b));
      // RFC 4231 Test Case 1
      expect(
        JsCryptoHelpers.hmacHex('Hi There', key20, 'HmacSHA256'),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
      expect(
        JsCryptoHelpers.hmacHex('Hi There', key20, 'HmacSHA512'),
        '87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde'
        'daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854',
      );

      // RFC 4231 Test Case 2
      expect(
        JsCryptoHelpers.hmacHex(
          'what do ya want for nothing?',
          'Jefe',
          'hmacsha256',
        ),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
      expect(
        JsCryptoHelpers.hmacHex(
          'what do ya want for nothing?',
          'Jefe',
          'hmac-sha512',
        ),
        '164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea250554'
        '9758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737',
      );

      // RFC 4231 Test Case 7 (131-byte key > 128-byte SHA-512 block size, > 64-byte SHA-256 block size)
      final key131 = Uint8List.fromList(List<int>.filled(131, 0xaa));
      const tc7Data =
          'This is a test using a larger than block-size key and a larger than '
          'block-size data. The key needs to be hashed before being used by '
          'the HMAC algorithm.';
      expect(
        JsCryptoHelpers.hmacHex(tc7Data, key131, 'HmacSHA256'),
        '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2',
      );
      expect(
        JsCryptoHelpers.hmacHex(tc7Data, key131, 'HmacSHA512'),
        'e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944'
        'b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58',
      );
      expect(
        JsCryptoHelpers.hmacBase64(tc7Data, key131, 'HmacSHA256'),
        base64Encode(
          JsCryptoHelpers.hexDecodeBytes(
            '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2',
          ),
        ),
      );
      expect(
        JsCryptoHelpers.hmacBytes(
          Uint8List.fromList(utf8.encode('Hi There')),
          key20,
          'HmacSHA256',
        ),
        JsCryptoHelpers.hexDecodeBytes(
          'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
        ),
      );
    });

    test('throws explicit ArgumentError on unsupported algorithms and invalid inputs', () {
      expect(
        () => JsCryptoHelpers.digestBytes(Uint8List(0), 'SHA-384'),
        throwsArgumentError,
      );
      expect(
        () => JsCryptoHelpers.digestHex('abc', 'CRC32'),
        throwsArgumentError,
      );
      expect(
        () => JsCryptoHelpers.digestBase64('abc', ''),
        throwsArgumentError,
      );
      expect(
        () => JsCryptoHelpers.hmacBytes(Uint8List(0), Uint8List(4), 'HmacSHA3'),
        throwsArgumentError,
      );
      expect(
        () => JsCryptoHelpers.hmacHex('abc', 'key', 'SHA-256'),
        throwsArgumentError,
      );
      expect(
        () => JsCryptoHelpers.hmacBase64('abc', 'key', 'unknown'),
        throwsArgumentError,
      );
      expect(
        () => JsCryptoHelpers.hexEncodeString(12345),
        throwsArgumentError,
      );
    });
  });

  group('QjsSandboxRuntime digest, HMAC, and hexEncode host bindings', () {
    test('exposes host.digestHex, host.digestBase64, host.hmacHex, host.hmacBase64, and host.hexEncode', () async {
      final runtime = QjsSandboxRuntime(sourceId: 'qjs-digest-hmac');
      try {
        final res = await runtime.evaluate('''
          const sha1Hex = host.digestHex("abc", "sha-1");
          const sha256Hex = host.digestHex("abc", "SHA256");
          const sha512Hex = host.digestHex("abc", "SHA-512");
          const sha256B64 = host.digestBase64(new Uint8Array([97, 98, 99]), "SHA-256");
          const hmacMd5 = host.hmacHex("what do ya want for nothing?", "Jefe", "HmacMD5");
          const hmacSha1 = host.hmacHex("what do ya want for nothing?", "Jefe", "HmacSHA1");
          const hmacSha256 = host.hmacHex("what do ya want for nothing?", "Jefe", "HmacSHA256");
          const hmacSha512B64 = host.hmacBase64("what do ya want for nothing?", "Jefe", "HmacSHA512");
          const longKey = Array.from({ length: 131 }, () => 0xaa);
          const tc7Msg = "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.";
          const hmacLong = host.hmacHex(tc7Msg, longKey, "HmacSHA256");
          const hexStr = host.hexEncode("PureRead");
          const hexBytes = host.hexEncode(new Uint8Array([0xde, 0xad, 0xbe, 0xef]));

          let caughtDigestErr = "";
          try {
            host.digestHex("abc", "BLAKE2");
          } catch (e) {
            caughtDigestErr = String(e.message || e);
          }

          let caughtKeyErr = "";
          try {
            host.hmacHex("abc", null, "HmacSHA256");
          } catch (e) {
            caughtKeyErr = String(e.message || e);
          }

          JSON.stringify({
            sha1Hex,
            sha256Hex,
            sha512Hex,
            sha256B64,
            hmacMd5,
            hmacSha1,
            hmacSha256,
            hmacSha512B64,
            hmacLong,
            hexStr,
            hexBytes,
            caughtDigestErr,
            caughtKeyErr,
          });
        ''');

        final decoded = jsonDecode(res.value) as Map<String, dynamic>;
        expect(decoded['sha1Hex'], 'a9993e364706816aba3e25717850c26c9cd0d89d');
        expect(
          decoded['sha256Hex'],
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        );
        expect(
          decoded['sha512Hex'],
          'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
          '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
        );
        expect(
          decoded['sha256B64'],
          base64Encode(
            JsCryptoHelpers.hexDecodeBytes(
              'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
            ),
          ),
        );
        expect(decoded['hmacMd5'], '750c783e6ab0b503eaa86e310a5db738');
        expect(decoded['hmacSha1'], 'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79');
        expect(
          decoded['hmacSha256'],
          '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
        );
        expect(
          decoded['hmacSha512B64'],
          base64Encode(
            JsCryptoHelpers.hexDecodeBytes(
              '164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea250554'
              '9758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737',
            ),
          ),
        );
        expect(
          decoded['hmacLong'],
          '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2',
        );
        expect(decoded['hexStr'], '5075726552656164');
        expect(decoded['hexBytes'], 'deadbeef');
        expect(decoded['caughtDigestErr'], contains('Unsupported digest algorithm'));
        expect(decoded['caughtKeyErr'], contains('HMAC key'));

        // Uncaught validation errors map to JsExecutionFailure and keep runtime healthy.
        await expectLater(
          () => runtime.evaluate('host.digestHex("abc", "NOPE")'),
          throwsA(
            isA<JsExecutionFailure>().having(
              (e) => e.message,
              'message',
              contains('Unsupported digest algorithm'),
            ),
          ),
        );
        await expectLater(
          () => runtime.evaluate('host.hmacBase64("abc", "key", "BAD_HMAC")'),
          throwsA(
            isA<JsExecutionFailure>().having(
              (e) => e.message,
              'message',
              contains('Unsupported HMAC algorithm'),
            ),
          ),
        );
        final recovery = await runtime.evaluate('host.digestHex("abc", "MD5")');
        expect(recovery.value, '900150983cd24fb0d6963f7d28e17f72');
      } finally {
        await runtime.dispose();
      }
    });
  });
}
