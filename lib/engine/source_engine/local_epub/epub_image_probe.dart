import 'dart:typed_data';

/// Pure-Dart header dimension parser for common raster image formats embedded
/// inside EPUB archives.
class EpubImageProbe {
  const EpubImageProbe._();

  /// Probes pixel dimensions from raw image header [bytes].
  ///
  /// Supports PNG (IHDR), JPEG (SOF0..SOF15), GIF (6-byte header + LSD),
  /// WebP (`VP8 `, `VP8L`, `VP8X`), and BMP. Returns `null` when the buffer
  /// is too short, unsupported, or malformed.
  static ({int width, int height})? probeDimensions(Uint8List bytes) {
    if (bytes.length < 10) return null;

    if (_isPng(bytes)) {
      return _probePng(bytes);
    }
    if (_isGif(bytes)) {
      return _probeGif(bytes);
    }
    if (_isJpeg(bytes)) {
      return _probeJpeg(bytes);
    }
    if (_isWebp(bytes)) {
      return _probeWebp(bytes);
    }
    if (_isBmp(bytes)) {
      return _probeBmp(bytes);
    }
    return null;
  }

  static bool _isPng(Uint8List bytes) =>
      bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;

  static ({int width, int height})? _probePng(Uint8List bytes) {
    // IHDR must be the first chunk immediately following the 8-byte signature.
    if (bytes[12] != 0x49 || // I
        bytes[13] != 0x48 || // H
        bytes[14] != 0x44 || // D
        bytes[15] != 0x52) {
      // R
      return null;
    }
    final chunkLen = _readUint32Be(bytes, 8);
    if (chunkLen < 13) return null;
    final width = _readUint32Be(bytes, 16);
    final height = _readUint32Be(bytes, 20);
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }

  static bool _isGif(Uint8List bytes) =>
      bytes.length >= 10 &&
      bytes[0] == 0x47 && // G
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x38 && // 8
      (bytes[4] == 0x37 || bytes[4] == 0x39) && // 7 or 9
      bytes[5] == 0x61; // a

  static ({int width, int height})? _probeGif(Uint8List bytes) {
    final width = _readUint16Le(bytes, 6);
    final height = _readUint16Le(bytes, 8);
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }

  static bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  static ({int width, int height})? _probeJpeg(Uint8List bytes) {
    var offset = 2;
    while (offset < bytes.length) {
      if (bytes[offset] != 0xFF) {
        return null;
      }
      while (offset < bytes.length && bytes[offset] == 0xFF) {
        offset++;
      }
      if (offset >= bytes.length) return null;

      final marker = bytes[offset++];
      // EOI (0xD9) or SOS (0xDA) ends marker header scanning.
      if (marker == 0xD9 || marker == 0xDA) {
        return null;
      }
      // Standalone markers without length payload (TEM / RST0..7 / SOI / stuffed 0).
      if (marker == 0x00 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD8)) {
        continue;
      }

      if (offset + 2 > bytes.length) return null;
      final segmentLen = (bytes[offset] << 8) | bytes[offset + 1];
      if (segmentLen < 2) return null;

      if (_isJpegSofMarker(marker)) {
        if (segmentLen < 7 || offset + 7 > bytes.length) {
          return null;
        }
        final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
        final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
        if (width <= 0 || height <= 0) return null;
        return (width: width, height: height);
      }

      final nextOffset = offset + segmentLen;
      if (nextOffset <= offset || nextOffset > bytes.length) {
        return null;
      }
      offset = nextOffset;
    }
    return null;
  }

  static bool _isJpegSofMarker(int marker) {
    switch (marker) {
      case 0xC0: // SOF0
      case 0xC1: // SOF1
      case 0xC2: // SOF2
      case 0xC3: // SOF3
      case 0xC5: // SOF5
      case 0xC6: // SOF6
      case 0xC7: // SOF7
      case 0xC9: // SOF9
      case 0xCA: // SOF10
      case 0xCB: // SOF11
      case 0xCD: // SOF13
      case 0xCE: // SOF14
      case 0xCF: // SOF15
        return true;
      default:
        return false;
    }
  }

  static bool _isWebp(Uint8List bytes) =>
      bytes.length >= 20 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x45 && // E
      bytes[10] == 0x42 && // B
      bytes[11] == 0x50; // P

  static ({int width, int height})? _probeWebp(Uint8List bytes) {
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final b0 = bytes[offset];
      final b1 = bytes[offset + 1];
      final b2 = bytes[offset + 2];
      final b3 = bytes[offset + 3];
      final chunkSize = _readUint32Le(bytes, offset + 4);
      final dataOffset = offset + 8;

      // 'VP8 ' (lossy bitstream)
      if (b0 == 0x56 && b1 == 0x50 && b2 == 0x38 && b3 == 0x20) {
        if (dataOffset + 10 > bytes.length) return null;
        // Keyframe bit 0 must be 0, and sync code 0x9D 0x01 0x2A must match.
        if ((bytes[dataOffset] & 0x01) != 0) return null;
        if (bytes[dataOffset + 3] != 0x9D ||
            bytes[dataOffset + 4] != 0x01 ||
            bytes[dataOffset + 5] != 0x2A) {
          return null;
        }
        final width = _readUint16Le(bytes, dataOffset + 6) & 0x3FFF;
        final height = _readUint16Le(bytes, dataOffset + 8) & 0x3FFF;
        if (width <= 0 || height <= 0) return null;
        return (width: width, height: height);
      }

      // 'VP8L' (lossless bitstream)
      if (b0 == 0x56 && b1 == 0x50 && b2 == 0x38 && b3 == 0x4C) {
        if (dataOffset + 5 > bytes.length) return null;
        if (bytes[dataOffset] != 0x2F) return null;
        final bits = _readUint32Le(bytes, dataOffset + 1);
        final width = (bits & 0x3FFF) + 1;
        final height = ((bits >> 14) & 0x3FFF) + 1;
        if (width <= 0 || height <= 0) return null;
        return (width: width, height: height);
      }

      // 'VP8X' (extended WebP canvas header)
      if (b0 == 0x56 && b1 == 0x50 && b2 == 0x38 && b3 == 0x58) {
        if (dataOffset + 10 > bytes.length) return null;
        final width = 1 + _readUint24Le(bytes, dataOffset + 4);
        final height = 1 + _readUint24Le(bytes, dataOffset + 7);
        if (width <= 0 || height <= 0) return null;
        return (width: width, height: height);
      }

      final paddedSize = chunkSize + (chunkSize & 1);
      final nextOffset = dataOffset + paddedSize;
      if (nextOffset <= offset || nextOffset > bytes.length) {
        return null;
      }
      offset = nextOffset;
    }
    return null;
  }

  static bool _isBmp(Uint8List bytes) =>
      bytes.length >= 22 && bytes[0] == 0x42 && bytes[1] == 0x4D;

  static ({int width, int height})? _probeBmp(Uint8List bytes) {
    final dibSize = _readUint32Le(bytes, 14);
    if (dibSize == 12) {
      final width = _readUint16Le(bytes, 18);
      final height = _readUint16Le(bytes, 20);
      if (width <= 0 || height <= 0) return null;
      return (width: width, height: height);
    }
    if (dibSize < 16 || bytes.length < 26) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getInt32(18, Endian.little);
    final rawHeight = data.getInt32(22, Endian.little);
    final height = rawHeight.abs();
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }

  static int _readUint16Le(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _readUint24Le(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);

  static int _readUint32Le(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static int _readUint32Be(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
