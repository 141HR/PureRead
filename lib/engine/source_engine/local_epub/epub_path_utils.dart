import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../domain/failures/app_failure.dart';

/// POSIX path, URL-decoding, cover extension, and fast fingerprint utilities
/// for EPUB 2/3 containers.
class EpubPathUtils {
  const EpubPathUtils._();

  static const int hashSampleBytes = 64 * 1024;

  /// Splits [href] into path and optional `#fragment` (both untouched by URL
  /// decoding until resolved).
  static ({String path, String? fragment}) splitHref(String href) {
    final trimmed = href.trim();
    final hashIdx = trimmed.indexOf('#');
    if (hashIdx < 0) {
      return (path: _stripQuery(trimmed), fragment: null);
    }
    final pathPart = _stripQuery(trimmed.substring(0, hashIdx));
    final rawFrag = trimmed.substring(hashIdx + 1).trim();
    return (
      path: pathPart,
      fragment: rawFrag.isEmpty ? null : safeUrlDecode(rawFrag),
    );
  }

  static String _stripQuery(String input) {
    final queryIdx = input.indexOf('?');
    if (queryIdx < 0) return input;
    return input.substring(0, queryIdx);
  }

  /// Normalizes a ZIP archive path to POSIX forward-slash form without leading
  /// `/` or `./`.
  static String normalizeArchivePath(String rawPath) {
    final slashPath = rawPath.trim().replaceAll('\\', '/');
    if (slashPath.isEmpty) return '';

    final strippedLeading = slashPath.replaceFirst(RegExp(r'^/+'), '');
    if (strippedLeading.isEmpty) return '';

    final normalized = p.posix.normalize(strippedLeading);
    if (normalized == '.' || normalized == '/') return '';

    // Clamp accidental leading '../' segments to archive root.
    var clean = normalized;
    while (clean.startsWith('../')) {
      clean = clean.substring(3);
    }
    if (clean.startsWith('./')) {
      clean = clean.substring(2);
    }
    return clean == '.' || clean == '..' ? '' : clean;
  }

  /// Resolves [rawHref] relative to the directory containing [baseFileArchivePath]
  /// (for example OPF, NAV, or NCX file) and returns both decoded and raw
  /// archive path candidates plus the canonical `epubHref` with `#fragment`.
  static ({
    String archivePath,
    String rawArchivePath,
    String? fragment,
    String epubHref,
  }) resolveHref(String baseFileArchivePath, String rawHref) {
    final split = splitHref(rawHref);
    final decodedPathPart = safeUrlDecode(split.path);
    final normalizedBase = normalizeArchivePath(baseFileArchivePath);
    final baseDir = normalizedBase.isEmpty
        ? ''
        : p.posix.dirname(normalizedBase);

    String resolveAgainstBase(String relativeOrRoot) {
      final cleaned = relativeOrRoot.replaceAll('\\', '/').trim();
      if (cleaned.isEmpty) {
        return normalizedBase;
      }
      if (cleaned.startsWith('/')) {
        return normalizeArchivePath(cleaned);
      }
      if (baseDir.isEmpty || baseDir == '.') {
        return normalizeArchivePath(cleaned);
      }
      return normalizeArchivePath(p.posix.join(baseDir, cleaned));
    }

    final archivePath = resolveAgainstBase(decodedPathPart);
    final rawArchivePath = resolveAgainstBase(split.path);
    final fragment = split.fragment;
    final epubHref = (fragment != null && fragment.isNotEmpty)
        ? '$archivePath#$fragment'
        : archivePath;

    return (
      archivePath: archivePath,
      rawArchivePath: rawArchivePath,
      fragment: fragment,
      epubHref: epubHref,
    );
  }

  /// Safely URL-decodes percent-encoded strings without throwing on malformed
  /// `%` escapes and preserving literal `+` characters.
  static String safeUrlDecode(String input) {
    if (!input.contains('%')) return input;
    try {
      return Uri.decodeComponent(input);
    } on ArgumentError {
      // Fallback: decode valid contiguous %XX byte sequences as UTF-8, leaving
      // invalid '%' escapes intact.
      final out = StringBuffer();
      var i = 0;
      while (i < input.length) {
        if (input.codeUnitAt(i) == 0x25 && i + 2 < input.length) {
          final byteGroup = <int>[];
          var j = i;
          while (j + 2 < input.length && input.codeUnitAt(j) == 0x25) {
            final hex = input.substring(j + 1, j + 3);
            final val = int.tryParse(hex, radix: 16);
            if (val == null) break;
            byteGroup.add(val);
            j += 3;
          }
          if (byteGroup.isNotEmpty) {
            out.write(utf8.decode(byteGroup, allowMalformed: true));
            i = j;
            continue;
          }
        }
        out.writeCharCode(input.codeUnitAt(i));
        i++;
      }
      return out.toString();
    }
  }

  /// Infers a lowercase image extension with leading dot (e.g. `.jpg`, `.png`)
  /// from [archivePath], [mediaType], and optionally magic [bytes].
  static String inferImageExtension({
    required String archivePath,
    String? mediaType,
    Uint8List? bytes,
  }) {
    final pathExt = p.posix.extension(archivePath).toLowerCase();
    if (_knownImageExtensions.contains(pathExt)) {
      return pathExt;
    }

    if (mediaType != null) {
      final mt = mediaType.split(';').first.trim().toLowerCase();
      switch (mt) {
        case 'image/jpeg':
        case 'image/jpg':
          return '.jpg';
        case 'image/png':
          return '.png';
        case 'image/webp':
          return '.webp';
        case 'image/gif':
          return '.gif';
        case 'image/bmp':
          return '.bmp';
        case 'image/svg+xml':
          return '.svg';
      }
    }

    if (bytes != null && bytes.length >= 4) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return '.jpg';
      }
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return '.png';
      }
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38) {
        return '.gif';
      }
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return '.webp';
      }
      if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
        return '.bmp';
      }
    }

    return pathExt;
  }

  static const Set<String> _knownImageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.svg',
  };

  /// Computes a fast, deterministic 128-bit content fingerprint from file size
  /// plus up to 64 KiB head + 64 KiB tail bytes.
  static String computeFastFileHashSync(String filePath) {
    final file = File(filePath);
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final fileLength = raf.lengthSync();
        final hasher = _FastDualHash128()..addUint64(fileLength);
        final headLen =
            fileLength < hashSampleBytes ? fileLength : hashSampleBytes;
        if (headLen > 0) {
          hasher.addBytes(raf.readSync(headLen));
        }
        if (fileLength > hashSampleBytes) {
          final tailStart = fileLength > hashSampleBytes * 2
              ? fileLength - hashSampleBytes
              : hashSampleBytes;
          final tailLen = fileLength - tailStart;
          if (tailLen > 0) {
            raf.setPositionSync(tailStart);
            hasher.addBytes(raf.readSync(tailLen));
          }
        }
        return '${fileLength.toRadixString(16)}_${hasher.digestHex()}';
      } finally {
        raf.closeSync();
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to hash EPUB file: ${e.message}',
        filePath: filePath,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    }
  }

  /// In-memory equivalent of [computeFastFileHashSync].
  static String computeFastBytesHash(Uint8List bytes) {
    final len = bytes.length;
    final hasher = _FastDualHash128()..addUint64(len);
    final headLen = len < hashSampleBytes ? len : hashSampleBytes;
    if (headLen > 0) {
      hasher.addBytes(Uint8List.sublistView(bytes, 0, headLen));
    }
    if (len > hashSampleBytes) {
      final tailStart = len > hashSampleBytes * 2
          ? len - hashSampleBytes
          : hashSampleBytes;
      if (tailStart < len) {
        hasher.addBytes(Uint8List.sublistView(bytes, tailStart, len));
      }
    }
    return '${len.toRadixString(16)}_${hasher.digestHex()}';
  }
}

class _FastDualHash128 {
  static const int _mask64 = -1;
  static const int _fnvPrime = 0x100000001b3;
  int _laneA = -3750763034362895579;
  int _laneB = 0x9e3779b97f4a7c15;
  int _index = 0;

  void addUint64(int value) {
    for (var shift = 56; shift >= 0; shift -= 8) {
      _addByte((value >> shift) & 0xFF);
    }
  }

  void addBytes(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      _addByte(bytes[i]);
    }
  }

  void _addByte(int b) {
    _laneA = ((_laneA ^ b) * _fnvPrime) & _mask64;
    _laneB = ((_laneB ^ (b ^ (_index & 0xFF))) * _fnvPrime) & _mask64;
    _index++;
  }

  String digestHex() {
    final a = _mix64(_laneA ^ _index);
    final b = _mix64(_laneB ^ (_index * 0x517cc1b727220a95));
    return '${_toHex64(a)}${_toHex64(b)}';
  }

  static int _mix64(int x) {
    var z = x;
    z = ((z ^ (z >>> 30)) * -4658895280553007687) & _mask64;
    z = ((z ^ (z >>> 27)) * -7723592293110705685) & _mask64;
    return z ^ (z >>> 31);
  }

  static String _toHex64(int value) {
    final hi = ((value >>> 32) & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    final lo = (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$hi$lo';
  }
}
