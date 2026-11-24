import 'dart:io';
import 'dart:typed_data';

import '../../../domain/failures/app_failure.dart';

/// Supported text encodings for local TXT novel files.
enum TxtEncoding {
  utf8('UTF-8', 0),
  utf8Bom('UTF-8-BOM', 3),
  gb18030('GB18030', 0),
  utf16Le('UTF-16LE', 2),
  utf16Be('UTF-16BE', 2);

  const TxtEncoding(this.label, this.bomLength);

  final String label;
  final int bomLength;

  /// Parses an encoding label (case-insensitive) or returns `null` if unknown.
  static TxtEncoding? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw
        .trim()
        .toUpperCase()
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '');
    switch (normalized) {
      case 'UTF8':
        return TxtEncoding.utf8;
      case 'UTF8BOM':
        return TxtEncoding.utf8Bom;
      case 'GB18030':
      case 'GBK':
      case 'GB2312':
      case 'CP936':
        return TxtEncoding.gb18030;
      case 'UTF16LE':
        return TxtEncoding.utf16Le;
      case 'UTF16BE':
        return TxtEncoding.utf16Be;
      default:
        return null;
    }
  }
}

/// Result of streaming TXT encoding detection.
class EncodingDetectionResult {
  const EncodingDetectionResult({
    required this.encoding,
    required this.bytesInspected,
    required this.elapsedMicros,
    this.bomLength = 0,
    this.isUndecodable = false,
  });

  final TxtEncoding encoding;
  final int bytesInspected;
  final int elapsedMicros;
  final int bomLength;
  final bool isUndecodable;
}

/// Streaming, chunk-boundary-safe text encoding detector.
///
/// Inspects BOM headers first, then streams chunks through stateful UTF-8 and
/// GB18030/GBK byte validators (plus BOM-less UTF-16 NUL-byte checks) without
/// loading large files into memory and without calling `Charset.detect()`.
class TxtEncodingDetector {
  const TxtEncodingDetector._();

  static const int defaultChunkSize = 64 * 1024;
  static const int defaultMaxSampleBytes = 256 * 1024;
  static const int _minNonAsciiEvidenceBytes = 2048;

  /// Detects encoding by streaming chunks from [file] via [RandomAccessFile].
  static Future<EncodingDetectionResult> detectFile(
    File file, {
    int chunkSize = defaultChunkSize,
    int maxSampleBytes = defaultMaxSampleBytes,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final length = await raf.length();
        if (length == 0) {
          sw.stop();
          return EncodingDetectionResult(
            encoding: TxtEncoding.utf8,
            bytesInspected: 0,
            elapsedMicros: sw.elapsedMicroseconds,
          );
        }

        final firstChunkSize = length < chunkSize ? length : chunkSize;
        final firstChunk = await raf.read(firstChunkSize);
        final bom = detectBom(firstChunk);
        if (bom != null) {
          sw.stop();
          return EncodingDetectionResult(
            encoding: bom,
            bytesInspected: firstChunk.length,
            elapsedMicros: sw.elapsedMicroseconds,
            bomLength: bom.bomLength,
          );
        }

        final tracker = _StreamingEncodingTracker()..feed(firstChunk);
        var totalInspected = firstChunk.length;

        while (totalInspected < length &&
            totalInspected < maxSampleBytes &&
            !tracker.hasDecisiveResult) {
          final remaining = length - totalInspected;
          final toRead = remaining < chunkSize ? remaining : chunkSize;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;
          tracker.feed(chunk);
          totalInspected += chunk.length;
        }

        sw.stop();
        final resolution = tracker.resolve();
        return EncodingDetectionResult(
          encoding: resolution.encoding,
          bytesInspected: totalInspected,
          elapsedMicros: sw.elapsedMicroseconds,
          isUndecodable: resolution.isUndecodable,
        );
      } finally {
        await raf.close();
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to inspect TXT encoding: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Synchronous variant for use inside a dedicated background Isolate.
  static EncodingDetectionResult detectFileSync(
    File file, {
    int chunkSize = defaultChunkSize,
    int maxSampleBytes = defaultMaxSampleBytes,
  }) {
    final sw = Stopwatch()..start();
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final length = raf.lengthSync();
        if (length == 0) {
          sw.stop();
          return EncodingDetectionResult(
            encoding: TxtEncoding.utf8,
            bytesInspected: 0,
            elapsedMicros: sw.elapsedMicroseconds,
          );
        }

        final firstChunkSize = length < chunkSize ? length : chunkSize;
        final firstChunk = raf.readSync(firstChunkSize);
        final bom = detectBom(firstChunk);
        if (bom != null) {
          sw.stop();
          return EncodingDetectionResult(
            encoding: bom,
            bytesInspected: firstChunk.length,
            elapsedMicros: sw.elapsedMicroseconds,
            bomLength: bom.bomLength,
          );
        }

        final tracker = _StreamingEncodingTracker()..feed(firstChunk);
        var totalInspected = firstChunk.length;

        while (totalInspected < length &&
            totalInspected < maxSampleBytes &&
            !tracker.hasDecisiveResult) {
          final remaining = length - totalInspected;
          final toRead = remaining < chunkSize ? remaining : chunkSize;
          final chunk = raf.readSync(toRead);
          if (chunk.isEmpty) break;
          tracker.feed(chunk);
          totalInspected += chunk.length;
        }

        sw.stop();
        final resolution = tracker.resolve();
        return EncodingDetectionResult(
          encoding: resolution.encoding,
          bytesInspected: totalInspected,
          elapsedMicros: sw.elapsedMicroseconds,
          isUndecodable: resolution.isUndecodable,
        );
      } finally {
        raf.closeSync();
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to inspect TXT encoding: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Detects encoding from an in-memory buffer, optionally fed in [chunkSize]
  /// slices to preserve stateful boundary validation.
  static EncodingDetectionResult detectBytes(
    Uint8List bytes, {
    int chunkSize = defaultChunkSize,
  }) {
    final sw = Stopwatch()..start();
    if (bytes.isEmpty) {
      sw.stop();
      return EncodingDetectionResult(
        encoding: TxtEncoding.utf8,
        bytesInspected: 0,
        elapsedMicros: sw.elapsedMicroseconds,
      );
    }

    final bom = detectBom(bytes);
    if (bom != null) {
      sw.stop();
      return EncodingDetectionResult(
        encoding: bom,
        bytesInspected: bytes.length < chunkSize ? bytes.length : chunkSize,
        elapsedMicros: sw.elapsedMicroseconds,
        bomLength: bom.bomLength,
      );
    }

    final tracker = _StreamingEncodingTracker();
    var offset = 0;
    while (offset < bytes.length && offset < defaultMaxSampleBytes) {
      final end = (offset + chunkSize) < bytes.length
          ? offset + chunkSize
          : bytes.length;
      tracker.feed(Uint8List.sublistView(bytes, offset, end));
      offset = end;
      if (tracker.hasDecisiveResult) break;
    }

    sw.stop();
    final resolution = tracker.resolve();
    return EncodingDetectionResult(
      encoding: resolution.encoding,
      bytesInspected: offset,
      elapsedMicros: sw.elapsedMicroseconds,
      isUndecodable: resolution.isUndecodable,
    );
  }

  /// Inspects leading bytes for a recognized BOM header.
  static TxtEncoding? detectBom(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return TxtEncoding.utf8Bom;
    }
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return TxtEncoding.utf16Le;
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return TxtEncoding.utf16Be;
      }
    }
    return null;
  }

  /// Returns the BOM byte length present at the start of [bytes] if it matches
  /// [encoding], or `0` when no matching BOM is present.
  static int inspectMatchingBomLength(Uint8List bytes, TxtEncoding encoding) {
    switch (encoding) {
      case TxtEncoding.utf8:
      case TxtEncoding.utf8Bom:
        if (bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF) {
          return 3;
        }
        return 0;
      case TxtEncoding.utf16Le:
        if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
          return 2;
        }
        return 0;
      case TxtEncoding.utf16Be:
        if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
          return 2;
        }
        return 0;
      case TxtEncoding.gb18030:
        return 0;
    }
  }
}

/// Stateful UTF-8 vs GB18030/GBK byte validator across arbitrary chunk splits.
class _StreamingEncodingTracker {
  // UTF-8 state
  int _utf8Need = 0;
  int _utf8MinCodepoint = 0;
  int _utf8Codepoint = 0;
  int _utf8Errors = 0;
  int _utf8ValidMultiByteCount = 0;
  int _utf8ThreeByteCjkCount = 0;

  // GB18030 state:
  // 0: ground, 1: saw lead (0x81..0xFE), 2: saw 4-byte digit2 (0x30..0x39),
  // 3: saw 4-byte lead3 (0x81..0xFE)
  int _gbState = 0;
  int _gbLead1 = 0;
  int _gbErrors = 0;
  int _gbValidMultiByteCount = 0;
  int _gbCommonCjkCount = 0;

  int _totalBytes = 0;
  int _nonAsciiBytes = 0;
  int _evenNullCount = 0;
  int _oddNullCount = 0;

  bool get hasDecisiveResult {
    if (_evenNullCount > 0 && _oddNullCount > 0) {
      return _totalBytes >= 64;
    }
    if ((_oddNullCount >= 64 && _evenNullCount == 0) ||
        (_evenNullCount >= 64 && _oddNullCount == 0)) {
      return true;
    }
    if (_nonAsciiBytes < TxtEncodingDetector._minNonAsciiEvidenceBytes) {
      return false;
    }
    if (_utf8Errors > 4 && _gbErrors == 0) return true;
    if (_gbErrors > 4 && _utf8Errors == 0) return true;
    return _nonAsciiBytes >= 16384;
  }

  void feed(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x00) {
        if (_totalBytes.isEven) {
          _evenNullCount++;
        } else {
          _oddNullCount++;
        }
      }
      _totalBytes++;
      if (b >= 0x80) _nonAsciiBytes++;
      _stepUtf8(b);
      _stepGb18030(b);
    }
  }

  void _stepUtf8(int b) {
    if (_utf8Need == 0) {
      if (b <= 0x7F) {
        return;
      } else if (b >= 0xC2 && b <= 0xDF) {
        _utf8Need = 1;
        _utf8Codepoint = b & 0x1F;
        _utf8MinCodepoint = 0x80;
      } else if (b >= 0xE0 && b <= 0xEF) {
        _utf8Need = 2;
        _utf8Codepoint = b & 0x0F;
        _utf8MinCodepoint = 0x800;
      } else if (b >= 0xF0 && b <= 0xF4) {
        _utf8Need = 3;
        _utf8Codepoint = b & 0x07;
        _utf8MinCodepoint = 0x10000;
      } else {
        _utf8Errors++;
      }
      return;
    }

    // Continuation byte expected (0x80..0xBF)
    if ((b & 0xC0) != 0x80) {
      _utf8Errors++;
      _utf8Need = 0;
      if (b > 0x7F) _stepUtf8(b);
      return;
    }

    _utf8Codepoint = (_utf8Codepoint << 6) | (b & 0x3F);
    _utf8Need--;
    if (_utf8Need == 0) {
      final cp = _utf8Codepoint;
      final isSurrogate = cp >= 0xD800 && cp <= 0xDFFF;
      if (cp < _utf8MinCodepoint || cp > 0x10FFFF || isSurrogate) {
        _utf8Errors++;
      } else {
        _utf8ValidMultiByteCount++;
        if (cp >= 0x3000 && cp <= 0x9FFF) {
          _utf8ThreeByteCjkCount++;
        }
      }
    }
  }

  void _stepGb18030(int b) {
    switch (_gbState) {
      case 0:
        if (b <= 0x7F) {
          return;
        } else if (b >= 0x81 && b <= 0xFE) {
          _gbState = 1;
          _gbLead1 = b;
        } else {
          _gbErrors++;
        }
      case 1:
        if ((b >= 0x40 && b <= 0x7E) || (b >= 0x80 && b <= 0xFE)) {
          _gbValidMultiByteCount++;
          if (_gbLead1 >= 0xA1 && _gbLead1 <= 0xF7 && b >= 0xA1 && b <= 0xFE) {
            _gbCommonCjkCount++;
          }
          _gbState = 0;
        } else if (b >= 0x30 && b <= 0x39) {
          _gbState = 2; // 4-byte GB18030 sequence
        } else {
          _gbErrors++;
          _gbState = 0;
        }
      case 2:
        if (b >= 0x81 && b <= 0xFE) {
          _gbState = 3;
        } else {
          _gbErrors++;
          _gbState = 0;
        }
      case 3:
        if (b >= 0x30 && b <= 0x39) {
          _gbValidMultiByteCount++;
        } else {
          _gbErrors++;
        }
        _gbState = 0;
    }
  }

  ({TxtEncoding encoding, bool isUndecodable}) resolve() {
    if (_evenNullCount > 0 || _oddNullCount > 0) {
      if (_totalBytes >= 4 && _totalBytes.isEven) {
        if (_oddNullCount >= 2 && _evenNullCount == 0) {
          return (encoding: TxtEncoding.utf16Le, isUndecodable: false);
        }
        if (_evenNullCount >= 2 && _oddNullCount == 0) {
          return (encoding: TxtEncoding.utf16Be, isUndecodable: false);
        }
      }
      return (encoding: TxtEncoding.utf8, isUndecodable: true);
    }

    if (_nonAsciiBytes == 0) {
      return (encoding: TxtEncoding.utf8, isUndecodable: false);
    }

    if (_utf8Errors == 0 && _utf8ValidMultiByteCount > 0) {
      if (_gbErrors > 0 || _utf8ThreeByteCjkCount >= _gbCommonCjkCount) {
        return (encoding: TxtEncoding.utf8, isUndecodable: false);
      }
      return (encoding: TxtEncoding.utf8, isUndecodable: false);
    }

    if (_gbErrors == 0 && _gbValidMultiByteCount > 0) {
      return (encoding: TxtEncoding.gb18030, isUndecodable: false);
    }

    // Both UTF-8 and GB18030 encountered errors.
    if (_utf8ValidMultiByteCount == 0 && _gbValidMultiByteCount == 0) {
      return (encoding: TxtEncoding.utf8, isUndecodable: true);
    }

    final utf8Unusable = _utf8Errors * 4 > _utf8ValidMultiByteCount;
    final gbUnusable = _gbErrors * 4 > _gbValidMultiByteCount;
    if (utf8Unusable && gbUnusable) {
      return (encoding: TxtEncoding.utf8, isUndecodable: true);
    }

    final chosen = _utf8Errors <= _gbErrors
        ? TxtEncoding.utf8
        : TxtEncoding.gb18030;
    return (encoding: chosen, isUndecodable: false);
  }
}
