import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

import 'txt_encoding.dart';

/// Fast byte-slice decoder supporting UTF-8, GBK/GB18030, and UTF-16LE/BE.
///
/// Builds a flat 65,536-entry GBK lookup table once per Isolate from
/// `package:charset`'s `gbk` codec to avoid per-character Map lookups,
/// supplements it with 4-byte GB18030 decoding, and explicitly uses
/// `decodeUtf16Le` / `decodeUtf16Be(..., stripBom: false)` for mid-file slices.
class TxtCodecHelper {
  const TxtCodecHelper._();

  static Uint16List? _gbkFastTable;

  static Uint16List _getGbkFastTable() {
    final existing = _gbkFastTable;
    if (existing != null) return existing;

    final table = Uint16List(65536);
    // Batch-decode all 23,940 valid 2-byte GBK slots in one gbk.decode call
    // (~2 ms instead of 23,940 separate Map lookups).
    final keys = <int>[];
    final batch = BytesBuilder(copy: false);
    for (var b1 = 0x81; b1 <= 0xFE; b1++) {
      for (var b2 = 0x40; b2 <= 0xFE; b2++) {
        if (b2 == 0x7F) continue;
        keys.add((b1 << 8) | b2);
        batch.addByte(b1);
        batch.addByte(b2);
      }
    }
    final decoded = gbk.decode(batch.takeBytes(), allowMalformed: true);
    final len = decoded.length < keys.length ? decoded.length : keys.length;
    for (var i = 0; i < len; i++) {
      final codeUnit = decoded.codeUnitAt(i);
      if (codeUnit != 0xFFFD) {
        table[keys[i]] = codeUnit;
      }
    }
    _gbkFastTable = table;
    return table;
  }

  /// Pre-warms the Isolate-local 64K GBK lookup table.
  static void warmUpGbkTable() {
    _getGbkFastTable();
  }

  /// Decodes a byte slice `[start, end)` using [encoding].
  ///
  /// When [allowMalformed] is `false`, invalid byte sequences or unpaired
  /// UTF-16 surrogates throw a [FormatException].
  static String decodeBytes(
    Uint8List bytes,
    TxtEncoding encoding, {
    int start = 0,
    int? end,
    bool allowMalformed = true,
  }) {
    final actualEnd = end ?? bytes.length;
    if (start >= actualEnd) return '';

    final slice = (start == 0 && actualEnd == bytes.length)
        ? bytes
        : Uint8List.sublistView(bytes, start, actualEnd);

    switch (encoding) {
      case TxtEncoding.utf8:
      case TxtEncoding.utf8Bom:
        return utf8.decode(slice, allowMalformed: allowMalformed);

      case TxtEncoding.gb18030:
        return _decodeGb18030Fast(
          bytes,
          start,
          actualEnd,
          allowMalformed: allowMalformed,
        );

      case TxtEncoding.utf16Le:
        if (!allowMalformed) {
          _validateUtf16Slice(slice, isLe: true);
        }
        return (utf16.decoder as Utf16Decoder)
            .decodeUtf16Le(slice, 0, slice.length, false);

      case TxtEncoding.utf16Be:
        if (!allowMalformed) {
          _validateUtf16Slice(slice, isLe: false);
        }
        return (utf16.decoder as Utf16Decoder)
            .decodeUtf16Be(slice, 0, slice.length, false);
    }
  }

  static void _validateUtf16Slice(Uint8List slice, {required bool isLe}) {
    if (slice.length.isOdd) {
      throw const FormatException('UTF-16 byte slice has odd byte length');
    }
    for (var i = 0; i < slice.length; i += 2) {
      final unit = isLe
          ? (slice[i] | (slice[i + 1] << 8))
          : ((slice[i] << 8) | slice[i + 1]);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 2 >= slice.length) {
          throw const FormatException('Trailing unpaired UTF-16 high surrogate');
        }
        final next = isLe
            ? (slice[i + 2] | (slice[i + 3] << 8))
            : ((slice[i + 2] << 8) | slice[i + 3]);
        if (next < 0xDC00 || next > 0xDFFF) {
          throw const FormatException('Unpaired UTF-16 high surrogate');
        }
        i += 2;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        throw const FormatException('Unexpected UTF-16 low surrogate');
      }
    }
  }

  /// Decodes GBK / GB18030 bytes using the flat 64K lookup table plus
  /// GB18030 4-byte supplementary plane decoding.
  static String _decodeGb18030Fast(
    Uint8List bytes,
    int start,
    int end, {
    required bool allowMalformed,
  }) {
    var allAscii = true;
    for (var i = start; i < end; i++) {
      if (bytes[i] >= 0x80) {
        allAscii = false;
        break;
      }
    }
    if (allAscii) {
      return String.fromCharCodes(bytes, start, end);
    }

    final table = _getGbkFastTable();
    final out = Uint16List(end - start);
    var outLen = 0;
    var i = start;

    while (i < end) {
      final b1 = bytes[i];
      if (b1 <= 0x7F) {
        out[outLen++] = b1;
        i++;
        continue;
      }
      if (b1 < 0x81 || b1 > 0xFE || i + 1 >= end) {
        if (!allowMalformed) {
          throw FormatException(
            'Invalid GB18030 lead or truncated byte at offset $i',
            bytes,
            i,
          );
        }
        out[outLen++] = 0xFFFD;
        i++;
        continue;
      }

      final b2 = bytes[i + 1];
      if (b2 >= 0x30 && b2 <= 0x39) {
        // 4-byte GB18030 sequence: [81..FE][30..39][81..FE][30..39]
        if (i + 3 < end) {
          final b3 = bytes[i + 2];
          final b4 = bytes[i + 3];
          if (b3 >= 0x81 && b3 <= 0xFE && b4 >= 0x30 && b4 <= 0x39) {
            final linear =
                (((b1 - 0x81) * 10 + (b2 - 0x30)) * 126 + (b3 - 0x81)) * 10 +
                    (b4 - 0x30);
            if (linear >= 189000 && linear <= 1237575) {
              // Supplementary planes U+10000..U+10FFFF
              final cp = 0x10000 + (linear - 189000);
              final high = 0xD800 + ((cp - 0x10000) >> 10);
              final low = 0xDC00 + ((cp - 0x10000) & 0x3FF);
              out[outLen++] = high;
              out[outLen++] = low;
              i += 4;
              continue;
            }
            if (linear >= 0 && linear <= 39419) {
              // Valid GB18030 4-byte BMP slot outside the 2-byte GBK subset.
              out[outLen++] = 0xFFFD;
              i += 4;
              continue;
            }
            if (!allowMalformed) {
              throw FormatException(
                'Out-of-range GB18030 4-byte sequence at offset $i',
                bytes,
                i,
              );
            }
            out[outLen++] = 0xFFFD;
            i += 4;
            continue;
          }
        }
        if (!allowMalformed) {
          throw FormatException(
            'Malformed GB18030 4-byte sequence at offset $i',
            bytes,
            i,
          );
        }
        out[outLen++] = 0xFFFD;
        i++;
        continue;
      }

      final mapped = table[(b1 << 8) | b2];
      if (mapped != 0) {
        out[outLen++] = mapped;
        i += 2;
      } else if ((b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFE)) {
        if (!allowMalformed) {
          throw FormatException(
            'Unmapped GBK byte sequence 0x${((b1 << 8) | b2).toRadixString(16)}',
            bytes,
            i,
          );
        }
        out[outLen++] = 0xFFFD;
        i += 2;
      } else {
        if (!allowMalformed) {
          throw FormatException(
            'Invalid GB18030 trail byte 0x${b2.toRadixString(16)} at offset $i',
            bytes,
            i,
          );
        }
        out[outLen++] = 0xFFFD;
        i++;
      }
    }

    return String.fromCharCodes(out, 0, outLen);
  }
}
