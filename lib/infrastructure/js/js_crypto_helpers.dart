import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart RFC 1321 MD5 and Base64 utilities for sandboxed JS runtimes and
/// source parsing without external crypto dependencies.
class JsCryptoHelpers {
  const JsCryptoHelpers._();

  static const List<int> _shifts = <int>[
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  static const List<int> _k = <int>[
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];

  /// Computes the 16-byte RFC 1321 MD5 digest of [bytes].
  static Uint8List md5Bytes(List<int> bytes) {
    final msgLen = bytes.length;
    final bitLen = msgLen * 8;
    final rem = (msgLen + 9) % 64;
    final padLen = rem == 0 ? 0 : 64 - rem;
    final totalLen = msgLen + 9 + padLen;

    final padded = Uint8List(totalLen);
    padded.setRange(0, msgLen, bytes);
    padded[msgLen] = 0x80;

    // Append 64-bit little-endian bit length.
    for (var i = 0; i < 8; i++) {
      padded[totalLen - 8 + i] = (bitLen >>> (8 * i)) & 0xFF;
    }

    var a0 = 0x67452301;
    var b0 = 0xefcdab89;
    var c0 = 0x98badcfe;
    var d0 = 0x10325476;

    final words = Uint32List(16);
    for (var offset = 0; offset < totalLen; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        words[i] =
            padded[j] |
            (padded[j + 1] << 8) |
            (padded[j + 2] << 16) |
            (padded[j + 3] << 24);
      }

      var a = a0;
      var b = b0;
      var c = c0;
      var d = d0;

      for (var i = 0; i < 64; i++) {
        int f;
        int g;
        if (i < 16) {
          f = (b & c) | ((~b) & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | ((~d) & c);
          g = (5 * i + 1) & 15;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) & 15;
        } else {
          f = c ^ (b | (~d));
          g = (7 * i) & 15;
        }

        f &= 0xFFFFFFFF;
        final temp = (a + f + _k[i] + words[g]) & 0xFFFFFFFF;
        a = d;
        d = c;
        c = b;
        b = (b + _rotl32(temp, _shifts[i])) & 0xFFFFFFFF;
      }

      a0 = (a0 + a) & 0xFFFFFFFF;
      b0 = (b0 + b) & 0xFFFFFFFF;
      c0 = (c0 + c) & 0xFFFFFFFF;
      d0 = (d0 + d) & 0xFFFFFFFF;
    }

    final digest = Uint8List(16);
    _writeUint32Le(digest, 0, a0);
    _writeUint32Le(digest, 4, b0);
    _writeUint32Le(digest, 8, c0);
    _writeUint32Le(digest, 12, d0);
    return digest;
  }

  /// Computes the 32-character lowercase hexadecimal RFC 1321 MD5 digest of
  /// UTF-8 encoded [input].
  static String md5Hex(String input) {
    final digest = md5Bytes(utf8.encode(input));
    final buf = StringBuffer();
    for (final byte in digest) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Computes the 16-character middle slice (`[8, 24)`) of the MD5 hex digest,
  /// matching Legado's `java.md5Encode16`.
  static String md5Hex16(String input) => md5Hex(input).substring(8, 24);

  /// Encodes UTF-8 [input] to Base64.
  static String base64EncodeString(String input) =>
      base64Encode(utf8.encode(input));

  /// Decodes a Base64 string (normalizing whitespace/padding) into bytes.
  static Uint8List base64DecodeBytes(String input) {
    var normalized = input.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return Uint8List(0);
    // Support URL-safe Base64 variants transparently.
    normalized = normalized.replaceAll('-', '+').replaceAll('_', '/');
    final mod = normalized.length % 4;
    if (mod != 0) {
      normalized = normalized.padRight(normalized.length + (4 - mod), '=');
    }
    return base64Decode(normalized);
  }

  /// Decodes a Base64 string into a UTF-8 string.
  static String base64DecodeString(String input) {
    final bytes = base64DecodeBytes(input);
    if (bytes.isEmpty) return '';
    return utf8.decode(bytes, allowMalformed: true);
  }

  static int _rotl32(int value, int shift) {
    final v = value & 0xFFFFFFFF;
    return ((v << shift) | (v >>> (32 - shift))) & 0xFFFFFFFF;
  }

  static void _writeUint32Le(Uint8List out, int offset, int value) {
    out[offset] = value & 0xFF;
    out[offset + 1] = (value >>> 8) & 0xFF;
    out[offset + 2] = (value >>> 16) & 0xFF;
    out[offset + 3] = (value >>> 24) & 0xFF;
  }
}
