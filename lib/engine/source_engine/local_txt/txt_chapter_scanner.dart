import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../domain/failures/app_failure.dart';
import 'txt_codec.dart';
import 'txt_encoding.dart';

/// Byte-offset metadata for a single chapter inside a local TXT file.
class ChapterIndexEntry {
  const ChapterIndexEntry({
    required this.chapterIndex,
    required this.title,
    required this.byteStart,
    required this.byteEnd,
  });

  final int chapterIndex;
  final String title;
  final int byteStart;
  final int byteEnd;

  int get byteLength => byteEnd - byteStart;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterIndexEntry &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          title == other.title &&
          byteStart == other.byteStart &&
          byteEnd == other.byteEnd;

  @override
  int get hashCode => Object.hash(chapterIndex, title, byteStart, byteEnd);

  @override
  String toString() =>
      'ChapterIndexEntry(#$chapterIndex "$title" [$byteStart, $byteEnd))';
}

/// Output of streaming TXT encoding detection and chapter indexing.
class TxtScanResult {
  const TxtScanResult({
    required this.encoding,
    required this.bomLength,
    required this.fileBytes,
    required this.fileHash,
    required this.chapters,
    required this.detectMicros,
    required this.scanMicros,
    required this.usedFallbackSplit,
  });

  final TxtEncoding encoding;
  final int bomLength;
  final int fileBytes;
  final String fileHash;
  final List<ChapterIndexEntry> chapters;
  final int detectMicros;
  final int scanMicros;
  final bool usedFallbackSplit;

  int get totalMicros => detectMicros + scanMicros;
}

/// Output of reading and decoding a single chapter byte slice via
/// [RandomAccessFile].
class ChapterReadResult {
  const ChapterReadResult({
    required this.chapterIndex,
    required this.title,
    required this.text,
    required this.bytesRead,
    required this.readMicros,
    required this.decodeMicros,
  });

  final int chapterIndex;
  final String title;
  final String text;
  final int bytesRead;
  final int readMicros;
  final int decodeMicros;

  int get totalMicros => readMicros + decodeMicros;
}

/// Streaming chapter scanner, fast file-fingerprint calculator, and
/// `RandomAccessFile` chapter reader designed for background Isolates.
class TxtChapterScanner {
  const TxtChapterScanner._();

  static const int defaultChunkBytes = 128 * 1024;
  static const int defaultMaxCandidateLineBytes = 384;
  static const int defaultFallbackSegmentBytes = 24 * 1024;
  static const int hashSampleBytes = 64 * 1024;

  static final RegExp defaultChapterRegex = RegExp(
    r'^\s*(?:第\s*[零一二三四五六七八九十百千万亿两\d]{1,9}\s*[章节回卷集部篇话]'
    r'(?:$|[\s：:、.\-—　][^\r\n]{0,50}$|[^\s，。！？、；：“”‘’《》\r\n]{1,30}$)|'
    r'(?:序\s*章|楔\s*子|引\s*子|尾\s*声|后\s*记|番\s*外)'
    r'(?:$|[\s：:、.\-—　][^\r\n]{0,50}$)|'
    r'Chapter\s+\d+(?:$|[\s：:.\-][^\r\n]{0,60}$))',
    caseSensitive: false,
  );

  /// Computes a pure-Dart fast file fingerprint combining the file size and
  /// up to 64 KiB head + 64 KiB tail samples.
  static Future<String> computeFastFileHash(String path) async {
    final file = File(path);
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final fileLength = await raf.length();
        final hasher = _FastDualHash128()..addUint64(fileLength);
        final headLen =
            fileLength < hashSampleBytes ? fileLength : hashSampleBytes;
        if (headLen > 0) {
          hasher.addBytes(await raf.read(headLen));
        }
        if (fileLength > hashSampleBytes) {
          final tailStart = fileLength > hashSampleBytes * 2
              ? fileLength - hashSampleBytes
              : hashSampleBytes;
          final tailLen = fileLength - tailStart;
          if (tailLen > 0) {
            await raf.setPosition(tailStart);
            hasher.addBytes(await raf.read(tailLen));
          }
        }
        return '${fileLength.toRadixString(16)}_${hasher.digestHex()}';
      } finally {
        await raf.close();
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to hash TXT file: ${e.message}',
        filePath: path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Synchronous variant of [computeFastFileHash] for background Isolates.
  static String computeFastFileHashSync(String path) {
    final file = File(path);
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final fileLength = raf.lengthSync();
        return _computeFastHashFromRafSync(raf, fileLength);
      } finally {
        raf.closeSync();
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to hash TXT file: ${e.message}',
        filePath: path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  static String _computeFastHashFromRafSync(
    RandomAccessFile raf,
    int fileLength,
  ) {
    final hasher = _FastDualHash128()..addUint64(fileLength);
    final headLen = fileLength < hashSampleBytes ? fileLength : hashSampleBytes;
    if (headLen > 0) {
      raf.setPositionSync(0);
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
  }

  /// Runs encoding detection and streaming chapter scanning in a one-off
  /// background [Isolate]. Prefer [TxtIsolateWorker] for repeated operations.
  static Future<TxtScanResult> scanInBackgroundIsolate(
    String filePath, {
    TxtEncoding? forcedEncoding,
    String? customPattern,
    int chunkBytes = defaultChunkBytes,
    int maxCandidateLineBytes = defaultMaxCandidateLineBytes,
    int fallbackSegmentBytes = defaultFallbackSegmentBytes,
  }) {
    return Isolate.run(
      () => scanFileSync(
        File(filePath),
        forcedEncoding: forcedEncoding,
        chapterRegex: customPattern != null ? RegExp(customPattern) : null,
        chunkBytes: chunkBytes,
        maxCandidateLineBytes: maxCandidateLineBytes,
        fallbackSegmentBytes: fallbackSegmentBytes,
      ),
    );
  }

  /// Streaming synchronous file scan (call inside a background Isolate).
  static TxtScanResult scanFileSync(
    File file, {
    TxtEncoding? forcedEncoding,
    RegExp? chapterRegex,
    int chunkBytes = defaultChunkBytes,
    int maxCandidateLineBytes = defaultMaxCandidateLineBytes,
    int fallbackSegmentBytes = defaultFallbackSegmentBytes,
  }) {
    final TxtEncoding encoding;
    final int bomLength;
    final int detectMicros;

    if (forcedEncoding == null) {
      final detectResult = TxtEncodingDetector.detectFileSync(file);
      if (detectResult.isUndecodable) {
        throw EncodingFailure(
          message: 'Unable to detect a supported TXT encoding',
          filePath: file.path,
          detectedEncoding: detectResult.encoding.label,
        );
      }
      encoding = detectResult.encoding;
      bomLength = detectResult.bomLength;
      detectMicros = detectResult.elapsedMicros;
    } else {
      encoding = forcedEncoding;
      final sw = Stopwatch()..start();
      bomLength = _inspectBomSync(file, forcedEncoding);
      sw.stop();
      detectMicros = sw.elapsedMicroseconds;
    }

    final scanSw = Stopwatch()..start();
    if (encoding == TxtEncoding.gb18030) {
      TxtCodecHelper.warmUpGbkTable();
    }

    final regex = chapterRegex ?? defaultChapterRegex;
    final safeChunkBytes = chunkBytes < 2 ? 2 : chunkBytes;
    final rawHits = <({String title, int byteStart})>[];

    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final fileLength = raf.lengthSync();
        final fileHash = _computeFastHashFromRafSync(raf, fileLength);
        final contentStart = bomLength < fileLength ? bomLength : fileLength;
        raf.setPositionSync(contentStart);

        if (encoding == TxtEncoding.utf16Le ||
            encoding == TxtEncoding.utf16Be) {
          _scanUtf16Stream(
            raf: raf,
            encoding: encoding,
            contentStart: contentStart,
            fileLength: fileLength,
            chunkBytes: safeChunkBytes,
            maxCandidateLineBytes: maxCandidateLineBytes * 2,
            regex: regex,
            hits: rawHits,
          );
        } else {
          _scanByteLineStream(
            raf: raf,
            encoding: encoding,
            contentStart: contentStart,
            fileLength: fileLength,
            chunkBytes: safeChunkBytes,
            maxCandidateLineBytes: maxCandidateLineBytes,
            regex: regex,
            hits: rawHits,
          );
        }

        final chapters = <ChapterIndexEntry>[];
        var usedFallback = false;

        if (rawHits.isEmpty) {
          if (contentStart < fileLength) {
            usedFallback = true;
            _buildFallbackChapters(
              raf: raf,
              encoding: encoding,
              contentStart: contentStart,
              fileLength: fileLength,
              segmentBytes: fallbackSegmentBytes,
              out: chapters,
            );
          }
        } else {
          if (rawHits.first.byteStart > contentStart &&
              _hasNonWhitespaceBytes(
                raf,
                encoding,
                contentStart,
                rawHits.first.byteStart,
              )) {
            chapters.add(
              ChapterIndexEntry(
                chapterIndex: 0,
                title: '序言',
                byteStart: contentStart,
                byteEnd: rawHits.first.byteStart,
              ),
            );
          }

          final offset = chapters.length;
          for (var i = 0; i < rawHits.length; i++) {
            final start = rawHits[i].byteStart;
            final end =
                i + 1 < rawHits.length ? rawHits[i + 1].byteStart : fileLength;
            chapters.add(
              ChapterIndexEntry(
                chapterIndex: offset + i,
                title: rawHits[i].title,
                byteStart: start,
                byteEnd: end,
              ),
            );
          }
        }

        scanSw.stop();
        return TxtScanResult(
          encoding: encoding,
          bomLength: bomLength,
          fileBytes: fileLength,
          fileHash: fileHash,
          chapters: chapters,
          detectMicros: detectMicros,
          scanMicros: scanSw.elapsedMicroseconds,
          usedFallbackSplit: usedFallback,
        );
      } finally {
        raf.closeSync();
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to scan TXT file: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  static int _inspectBomSync(File file, TxtEncoding encoding) {
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final len = raf.lengthSync();
        if (len == 0) return 0;
        final sample = raf.readSync(len < 3 ? len : 3);
        return TxtEncodingDetector.inspectMatchingBomLength(sample, encoding);
      } finally {
        raf.closeSync();
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to read TXT header: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Reads a single chapter's exact `[byteStart, byteEnd)` slice via
  /// [RandomAccessFile] and decodes it to a Dart [String].
  static ChapterReadResult readChapterSliceSync(
    File file,
    ChapterIndexEntry chapter,
    TxtEncoding encoding, {
    bool allowMalformed = true,
  }) {
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        return readChapterFromRafSync(
          raf,
          chapter,
          encoding,
          filePath: file.path,
          allowMalformed: allowMalformed,
        );
      } finally {
        raf.closeSync();
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to read TXT chapter slice: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Reads from an already-open [RandomAccessFile] handle.
  static ChapterReadResult readChapterFromRafSync(
    RandomAccessFile raf,
    ChapterIndexEntry chapter,
    TxtEncoding encoding, {
    String? filePath,
    bool allowMalformed = true,
  }) {
    final len = chapter.byteLength;
    if (chapter.byteStart < 0 || len < 0) {
      throw FileAccessFailure(
        message:
            'Invalid chapter byte range [${chapter.byteStart}, ${chapter.byteEnd})',
        filePath: filePath,
      );
    }
    if (len == 0) {
      return ChapterReadResult(
        chapterIndex: chapter.chapterIndex,
        title: chapter.title,
        text: '',
        bytesRead: 0,
        readMicros: 0,
        decodeMicros: 0,
      );
    }

    final fileLength = raf.lengthSync();
    if (chapter.byteEnd > fileLength) {
      throw FileAccessFailure(
        message:
            'Chapter slice [${chapter.byteStart}, ${chapter.byteEnd}) exceeds file length $fileLength',
        filePath: filePath,
      );
    }

    final readSw = Stopwatch()..start();
    raf.setPositionSync(chapter.byteStart);
    final bytes = raf.readSync(len);
    readSw.stop();

    if (bytes.length < len) {
      throw FileAccessFailure(
        message: 'Short read on chapter slice: expected $len, got ${bytes.length}',
        filePath: filePath,
      );
    }

    final decodeSw = Stopwatch()..start();
    final String text;
    try {
      text = TxtCodecHelper.decodeBytes(
        bytes,
        encoding,
        allowMalformed: allowMalformed,
      );
    } on FormatException catch (e, st) {
      throw EncodingFailure(
        message: 'Failed to decode chapter "${chapter.title}" as ${encoding.label}: ${e.message}',
        filePath: filePath,
        detectedEncoding: encoding.label,
        cause: e,
        stackTrace: st,
      );
    }
    decodeSw.stop();

    return ChapterReadResult(
      chapterIndex: chapter.chapterIndex,
      title: chapter.title,
      text: text,
      bytesRead: bytes.length,
      readMicros: readSw.elapsedMicroseconds,
      decodeMicros: decodeSw.elapsedMicroseconds,
    );
  }

  static void _scanByteLineStream({
    required RandomAccessFile raf,
    required TxtEncoding encoding,
    required int contentStart,
    required int fileLength,
    required int chunkBytes,
    required int maxCandidateLineBytes,
    required RegExp regex,
    required List<({String title, int byteStart})> hits,
  }) {
    final buffer = Uint8List(chunkBytes);
    final lineCap = maxCandidateLineBytes + 4;
    final carry = Uint8List(lineCap);
    var carryLen = 0;
    var carryOverflowed = false;
    var lineStartByte = contentStart;
    var filePos = contentStart;

    while (filePos < fileLength) {
      final readCount = raf.readIntoSync(buffer);
      if (readCount <= 0) break;

      var segmentStart = 0;
      for (var i = 0; i < readCount; i++) {
        if (buffer[i] == 0x0A) {
          if (!carryOverflowed) {
            final segLen = i - segmentStart;
            if (carryLen == 0) {
              var trimmedEnd = i;
              if (trimmedEnd > segmentStart && buffer[trimmedEnd - 1] == 0x0D) {
                trimmedEnd--;
              }
              final effectiveLen = trimmedEnd - segmentStart;
              if (effectiveLen > 0 && effectiveLen <= maxCandidateLineBytes) {
                final line = TxtCodecHelper.decodeBytes(
                  buffer,
                  encoding,
                  start: segmentStart,
                  end: trimmedEnd,
                );
                if (regex.hasMatch(line)) {
                  hits.add((title: line.trim(), byteStart: lineStartByte));
                }
              }
            } else if (carryLen + segLen <= maxCandidateLineBytes + 1) {
              carry.setRange(carryLen, carryLen + segLen, buffer, segmentStart);
              var trimmedEnd = carryLen + segLen;
              if (trimmedEnd > 0 && carry[trimmedEnd - 1] == 0x0D) {
                trimmedEnd--;
              }
              if (trimmedEnd > 0 && trimmedEnd <= maxCandidateLineBytes) {
                final line = TxtCodecHelper.decodeBytes(
                  carry,
                  encoding,
                  start: 0,
                  end: trimmedEnd,
                );
                if (regex.hasMatch(line)) {
                  hits.add((title: line.trim(), byteStart: lineStartByte));
                }
              }
            }
          }
          carryLen = 0;
          carryOverflowed = false;
          segmentStart = i + 1;
          lineStartByte = filePos + segmentStart;
        }
      }

      final tailLen = readCount - segmentStart;
      if (tailLen > 0 && !carryOverflowed) {
        if (carryLen + tailLen <= maxCandidateLineBytes + 1) {
          carry.setRange(carryLen, carryLen + tailLen, buffer, segmentStart);
          carryLen += tailLen;
        } else {
          carryLen = 0;
          carryOverflowed = true;
        }
      }

      filePos += readCount;
    }

    if (!carryOverflowed && carryLen > 0) {
      var trimmedEnd = carryLen;
      if (trimmedEnd > 0 && carry[trimmedEnd - 1] == 0x0D) {
        trimmedEnd--;
      }
      if (trimmedEnd > 0 && trimmedEnd <= maxCandidateLineBytes) {
        final line = TxtCodecHelper.decodeBytes(
          carry,
          encoding,
          start: 0,
          end: trimmedEnd,
        );
        if (regex.hasMatch(line)) {
          hits.add((title: line.trim(), byteStart: lineStartByte));
        }
      }
    }
  }

  static void _scanUtf16Stream({
    required RandomAccessFile raf,
    required TxtEncoding encoding,
    required int contentStart,
    required int fileLength,
    required int chunkBytes,
    required int maxCandidateLineBytes,
    required RegExp regex,
    required List<({String title, int byteStart})> hits,
  }) {
    final rawEven = chunkBytes & ~1;
    final evenChunkBytes = rawEven < 2 ? 2 : rawEven;
    final buffer = Uint8List(evenChunkBytes);
    final carry = Uint8List(maxCandidateLineBytes + 4);
    var carryLen = 0;
    var carryOverflowed = false;
    var lineStartByte = contentStart;
    var filePos = contentStart;
    var trailingOddByte = -1;

    final isLe = encoding == TxtEncoding.utf16Le;

    bool isNewlinePair(int b0, int b1) =>
        isLe ? (b0 == 0x0A && b1 == 0x00) : (b0 == 0x00 && b1 == 0x0A);

    bool isCrPair(int b0, int b1) =>
        isLe ? (b0 == 0x0D && b1 == 0x00) : (b0 == 0x00 && b1 == 0x0D);

    while (filePos < fileLength) {
      var readCount = raf.readIntoSync(buffer, trailingOddByte >= 0 ? 1 : 0);
      if (readCount <= 0) break;
      if (trailingOddByte >= 0) {
        buffer[0] = trailingOddByte;
        readCount += 1;
        trailingOddByte = -1;
      }
      final alignedLen = readCount & ~1;
      if (alignedLen < readCount) {
        trailingOddByte = buffer[alignedLen];
      }

      var segmentStart = 0;
      for (var i = 0; i < alignedLen; i += 2) {
        if (isNewlinePair(buffer[i], buffer[i + 1])) {
          if (!carryOverflowed) {
            final segLen = i - segmentStart;
            if (carryLen == 0) {
              var trimmedEnd = i;
              if (trimmedEnd - segmentStart >= 2 &&
                  isCrPair(buffer[trimmedEnd - 2], buffer[trimmedEnd - 1])) {
                trimmedEnd -= 2;
              }
              final effectiveLen = trimmedEnd - segmentStart;
              if (effectiveLen > 0 && effectiveLen <= maxCandidateLineBytes) {
                final line = TxtCodecHelper.decodeBytes(
                  buffer,
                  encoding,
                  start: segmentStart,
                  end: trimmedEnd,
                );
                if (regex.hasMatch(line)) {
                  hits.add((title: line.trim(), byteStart: lineStartByte));
                }
              }
            } else if (carryLen + segLen <= maxCandidateLineBytes + 2) {
              carry.setRange(carryLen, carryLen + segLen, buffer, segmentStart);
              var trimmedEnd = carryLen + segLen;
              if (trimmedEnd >= 2 &&
                  isCrPair(carry[trimmedEnd - 2], carry[trimmedEnd - 1])) {
                trimmedEnd -= 2;
              }
              if (trimmedEnd > 0 && trimmedEnd <= maxCandidateLineBytes) {
                final line = TxtCodecHelper.decodeBytes(
                  carry,
                  encoding,
                  start: 0,
                  end: trimmedEnd,
                );
                if (regex.hasMatch(line)) {
                  hits.add((title: line.trim(), byteStart: lineStartByte));
                }
              }
            }
          }
          carryLen = 0;
          carryOverflowed = false;
          segmentStart = i + 2;
          lineStartByte = filePos + segmentStart;
        }
      }

      final tailLen = alignedLen - segmentStart;
      if (tailLen > 0 && !carryOverflowed) {
        if (carryLen + tailLen <= maxCandidateLineBytes + 2) {
          carry.setRange(carryLen, carryLen + tailLen, buffer, segmentStart);
          carryLen += tailLen;
        } else {
          carryLen = 0;
          carryOverflowed = true;
        }
      }

      filePos += alignedLen;
    }

    if (!carryOverflowed && carryLen >= 2) {
      var trimmedEnd = carryLen;
      if (trimmedEnd >= 2 &&
          isCrPair(carry[trimmedEnd - 2], carry[trimmedEnd - 1])) {
        trimmedEnd -= 2;
      }
      if (trimmedEnd > 0 && trimmedEnd <= maxCandidateLineBytes) {
        final line = TxtCodecHelper.decodeBytes(
          carry,
          encoding,
          start: 0,
          end: trimmedEnd,
        );
        if (regex.hasMatch(line)) {
          hits.add((title: line.trim(), byteStart: lineStartByte));
        }
      }
    }
  }

  static bool _hasNonWhitespaceBytes(
    RandomAccessFile raf,
    TxtEncoding encoding,
    int start,
    int end,
  ) {
    if (end <= start) return false;
    const chunkSize = 4096;
    var pos = start;
    while (pos < end) {
      final remaining = end - pos;
      var readLen = remaining < chunkSize ? remaining : chunkSize;
      if (encoding == TxtEncoding.utf16Le || encoding == TxtEncoding.utf16Be) {
        readLen = readLen & ~1;
        if (readLen == 0) break;
      }
      raf.setPositionSync(pos);
      final bytes = raf.readSync(readLen);
      if (bytes.isEmpty) break;
      if (TxtCodecHelper.decodeBytes(bytes, encoding).trim().isNotEmpty) {
        return true;
      }
      pos += bytes.length;
    }
    return false;
  }

  static void _buildFallbackChapters({
    required RandomAccessFile raf,
    required TxtEncoding encoding,
    required int contentStart,
    required int fileLength,
    required int segmentBytes,
    required List<ChapterIndexEntry> out,
  }) {
    if (contentStart >= fileLength) return;

    var pos = contentStart;
    var idx = 0;
    const probeWindow = 512;

    while (pos < fileLength) {
      var targetEnd = pos + segmentBytes;
      if (targetEnd >= fileLength) {
        out.add(
          ChapterIndexEntry(
            chapterIndex: idx,
            title: '第${idx + 1}节',
            byteStart: pos,
            byteEnd: fileLength,
          ),
        );
        break;
      }

      targetEnd = _snapBoundary(
        raf: raf,
        encoding: encoding,
        contentStart: contentStart,
        minPos: pos,
        targetPos: targetEnd,
        fileLength: fileLength,
        probeWindow: probeWindow,
      );
      if (targetEnd <= pos) {
        targetEnd = (pos + segmentBytes).clamp(pos + 2, fileLength);
      }
      out.add(
        ChapterIndexEntry(
          chapterIndex: idx,
          title: '第${idx + 1}节',
          byteStart: pos,
          byteEnd: targetEnd,
        ),
      );
      pos = targetEnd;
      idx++;
    }
  }

  static int _snapBoundary({
    required RandomAccessFile raf,
    required TxtEncoding encoding,
    required int contentStart,
    required int minPos,
    required int targetPos,
    required int fileLength,
    required int probeWindow,
  }) {
    final searchStart = (targetPos - probeWindow).clamp(minPos + 1, fileLength);
    final searchEnd = (targetPos + probeWindow).clamp(searchStart, fileLength);
    final len = searchEnd - searchStart;
    if (len <= 0) return targetPos;

    raf.setPositionSync(searchStart);
    final probe = raf.readSync(len);

    if (encoding == TxtEncoding.utf16Le || encoding == TxtEncoding.utf16Be) {
      final isLe = encoding == TxtEncoding.utf16Le;
      final alignedOffset = (searchStart - contentStart).isOdd ? 1 : 0;
      for (var i = alignedOffset; i + 1 < probe.length; i += 2) {
        final isNl = isLe
            ? (probe[i] == 0x0A && probe[i + 1] == 0x00)
            : (probe[i] == 0x00 && probe[i + 1] == 0x0A);
        if (isNl) return searchStart + i + 2;
      }
      var targetEven =
          targetPos - ((targetPos - contentStart).isOdd ? 1 : 0);
      targetEven = targetEven.clamp(minPos + 2, fileLength);
      // Avoid cutting a UTF-16 surrogate pair across chapter boundaries.
      final idxInProbe = targetEven - searchStart;
      if (idxInProbe >= 0 && idxInProbe + 1 < probe.length) {
        final codeUnit = isLe
            ? (probe[idxInProbe] | (probe[idxInProbe + 1] << 8))
            : ((probe[idxInProbe] << 8) | probe[idxInProbe + 1]);
        if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
          targetEven = targetEven + 2 <= fileLength
              ? targetEven + 2
              : targetEven - 2;
        }
      }
      return targetEven.clamp(minPos + 2, fileLength);
    }

    // Prefer snapping right after a newline.
    for (var i = 0; i < probe.length; i++) {
      if (probe[i] == 0x0A) {
        return searchStart + i + 1;
      }
    }

    if (encoding == TxtEncoding.utf8 || encoding == TxtEncoding.utf8Bom) {
      var idx = targetPos - searchStart;
      while (idx < probe.length && (probe[idx] & 0xC0) == 0x80) {
        idx++;
      }
      return (searchStart + idx).clamp(minPos + 1, fileLength);
    }

    // GB18030/GBK: find a guaranteed 1-byte ASCII resync point (< 0x30) in probe
    // before targetPos; otherwise walk safely from minPos (known char boundary).
    var resyncPos = minPos;
    final targetIdxInProbe = (targetPos - searchStart).clamp(0, probe.length);
    for (var j = targetIdxInProbe - 1; j >= 0; j--) {
      if (probe[j] < 0x30) {
        resyncPos = searchStart + j + 1;
        break;
      }
    }

    return _walkGb18030Boundary(
      raf: raf,
      startBoundary: resyncPos,
      targetPos: targetPos,
      fileLength: fileLength,
    ).clamp(minPos + 1, fileLength);
  }

  static int _walkGb18030Boundary({
    required RandomAccessFile raf,
    required int startBoundary,
    required int targetPos,
    required int fileLength,
  }) {
    if (startBoundary >= targetPos) return startBoundary;
    final maxRead = (targetPos + 8).clamp(startBoundary, fileLength) - startBoundary;
    raf.setPositionSync(startBoundary);
    final bytes = raf.readSync(maxRead);
    var i = 0;
    while (i < bytes.length && startBoundary + i < targetPos) {
      final b1 = bytes[i];
      if (b1 <= 0x7F) {
        i++;
      } else if (i + 1 < bytes.length &&
          bytes[i + 1] >= 0x30 &&
          bytes[i + 1] <= 0x39) {
        i += 4;
      } else {
        i += 2;
      }
    }
    return startBoundary + i;
  }
}

/// Pure-Dart 128-bit dual-lane FNV-1a + SplitMix64 fast content fingerprint.
class _FastDualHash128 {
  static const int _mask64 = -1; // 64-bit two's complement on Dart VM
  static const int _fnvPrime = 0x100000001b3;
  int _laneA = -3750763034362895579; // 0xcbf29ce484222325
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
