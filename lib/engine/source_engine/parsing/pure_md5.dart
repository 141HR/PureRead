import 'dart:typed_data';

import '../../../infrastructure/js/js_crypto_helpers.dart';

/// Pure-Dart RFC 1321 MD5 message digest helper.
class PureMd5 {
  const PureMd5._();

  /// Computes the 16-byte MD5 digest of [bytes].
  static Uint8List digestBytes(List<int> bytes) =>
      JsCryptoHelpers.md5Bytes(bytes);

  /// Computes the 32-character lowercase hexadecimal MD5 digest of UTF-8
  /// encoded [input].
  static String digestHex(String input) => JsCryptoHelpers.md5Hex(input);

  /// Computes the 16-character middle slice (`[8, 24)`) of [digestHex],
  /// matching Legado's `java.md5Encode16`.
  static String digest16Hex(String input) => JsCryptoHelpers.md5Hex16(input);
}
