import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'chapter_index_entry.dart';
import 'txt_encoding.dart';

/// Output of streaming TXT encoding detection and chapter indexing.
class TxtScanResult {
  const TxtScanResult({
    required this.encoding,
    required this.fileBytes,
    required this.chapters,
    required this.detectMicros,
    required this.scanMicros,
    required this.usedFallbackSplit,
    required this.peakMemoryDeltaBytes,
  });

  final TxtEncoding encoding;
  final int fileBytes;
  final List<ChapterIndexEntry> chapters;
  final int detectMicros;
  final int scanMicros;
  final bool usedFallbackSplit;
  final int peakMemoryDeltaBytes;

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

/// Streaming chapter scanner & `RandomAccessFile` chapter reader designed for
/// execution inside a background Dart [Isolate].
class TxtChapterScanner {
  TxtChapterScanner._();

  static const int defaultChunkBytes = 128 * 1024;
  static const int defaultMaxCandidateLineBytes = 384;
  static const int defaultFallbackSegmentBytes = 24 * 1024;

  static final RegExp defaultChapterRegex = RegExp(
    r'^\s*(?:第\s*[零一二三四五六七八九十百千万亿两\d]{1,9}\s*[章节回卷集部篇话]'
    r'(?:$|[\s：:、.\-—　][^\r\n]{0,50}$|[^\s，。！？、；：“”‘’《》\r\n]{1,30}$)|'
    r'(?:序\s*章|楔\s*子|引\s*子|尾\s*声|后\s*记|番\s*外)'
    r'(?:$|[\s：:、.\-—　][^\r\n]{0,50}$)|'
    r'Chapter\s+\d+(?:$|[\s：:.\-][^\r\n]{0,60}$))',
  );

  /// Runs encoding detection and streaming chapter scanning in a dedicated
  /// background [Isolate].
  static Future<TxtScanResult> scanInBackgroundIsolate(
    String filePath, {
    String? customPattern,
    int chunkBytes = defaultChunkBytes,
    int maxCandidateLineBytes = defaultMaxCandidateLineBytes,
    int fallbackSegmentBytes = defaultFallbackSegmentBytes,
  }) {
    return Isolate.run(
      () => scanFileSync(
        File(filePath),
        chapterRegex: customPattern != null ? RegExp(customPattern) : null,
        chunkBytes: chunkBytes,
        maxCandidateLineBytes: maxCandidateLineBytes,
        fallbackSegmentBytes: fallbackSegmentBytes,
      ),
    );
  }

  /// Reads and decodes a single chapter slice using [RandomAccessFile] inside
  /// a background [Isolate].
  static Future<ChapterReadResult> readChapterInBackgroundIsolate(
    String filePath,
    ChapterIndexEntry chapter,
    TxtEncoding encoding,
  ) {
    return Isolate.run(
      () => readChapterSliceSync(File(filePath), chapter, encoding),
    );
  }

  /// Streaming synchronous file scan (call inside a background Isolate).
  ///
  /// Memory usage remains bounded by ~[chunkBytes] + compact chapter metadata
  /// regardless of file size.
  static TxtScanResult scanFileSync(
    File file, {
    RegExp? chapterRegex,
    int chunkBytes = defaultChunkBytes,
    int maxCandidateLineBytes = defaultMaxCandidateLineBytes,
    int fallbackSegmentBytes = defaultFallbackSegmentBytes,
  }) {
    final rssBefore = ProcessInfo.currentRss;
    var peakRss = rssBefore;

    final detectResult = TxtEncodingDetector.detectFileSync(file);
    final encoding = detectResult.encoding;

    final scanSw = Stopwatch()..start();
    if (encoding == TxtEncoding.gb18030) {
      TxtCodecHelper.warmUpGbkTable();
    }

    final regex = chapterRegex ?? defaultChapterRegex;
    final raf = file.openSync(mode: FileMode.read);
    final rawHits = <({String title, int byteStart})>[];
    final int fileLength;

    try {
      fileLength = raf.lengthSync();
      final contentStart = encoding.bomLength < fileLength
          ? encoding.bomLength
          : fileLength;
      raf.setPositionSync(contentStart);

      if (encoding == TxtEncoding.utf16Le || encoding == TxtEncoding.utf16Be) {
        _scanUtf16Stream(
          raf: raf,
          encoding: encoding,
          contentStart: contentStart,
          fileLength: fileLength,
          chunkBytes: chunkBytes,
          maxCandidateLineBytes: maxCandidateLineBytes * 2,
          regex: regex,
          hits: rawHits,
          onSampleRss: () {
            final rss = ProcessInfo.currentRss;
            if (rss > peakRss) peakRss = rss;
          },
        );
      } else {
        _scanByteLineStream(
          raf: raf,
          encoding: encoding,
          contentStart: contentStart,
          fileLength: fileLength,
          chunkBytes: chunkBytes,
          maxCandidateLineBytes: maxCandidateLineBytes,
          regex: regex,
          hits: rawHits,
          onSampleRss: () {
            final rss = ProcessInfo.currentRss;
            if (rss > peakRss) peakRss = rss;
          },
        );
      }

      final chapters = <ChapterIndexEntry>[];
      var usedFallback = false;

      if (rawHits.isEmpty) {
        usedFallback = true;
        _buildFallbackChapters(
          raf: raf,
          encoding: encoding,
          contentStart: contentStart,
          fileLength: fileLength,
          segmentBytes: fallbackSegmentBytes,
          out: chapters,
        );
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
      final finalRss = ProcessInfo.currentRss;
      if (finalRss > peakRss) peakRss = finalRss;

      return TxtScanResult(
        encoding: encoding,
        fileBytes: fileLength,
        chapters: chapters,
        detectMicros: detectResult.elapsedMicros,
        scanMicros: scanSw.elapsedMicroseconds,
        usedFallbackSplit: usedFallback,
        peakMemoryDeltaBytes: peakRss - rssBefore,
      );
    } finally {
      raf.closeSync();
    }
  }

  /// Reads a single chapter's exact `[byteStart, byteEnd)` slice via
  /// [RandomAccessFile] and decodes it to UTF-16 Dart [String].
  static ChapterReadResult readChapterSliceSync(
    File file,
    ChapterIndexEntry chapter,
    TxtEncoding encoding,
  ) {
    final raf = file.openSync(mode: FileMode.read);
    try {
      return readChapterFromRafSync(raf, chapter, encoding);
    } finally {
      raf.closeSync();
    }
  }

  /// Reads from an already-open [RandomAccessFile] handle (useful for benchmarking
  /// pure seek+read+decode latency or reusing an open file descriptor).
  static ChapterReadResult readChapterFromRafSync(
    RandomAccessFile raf,
    ChapterIndexEntry chapter,
    TxtEncoding encoding,
  ) {
    final len = chapter.byteLength;
    if (len <= 0) {
      return ChapterReadResult(
        chapterIndex: chapter.chapterIndex,
        title: chapter.title,
        text: '',
        bytesRead: 0,
        readMicros: 0,
        decodeMicros: 0,
      );
    }

    final readSw = Stopwatch()..start();
    raf.setPositionSync(chapter.byteStart);
    final bytes = raf.readSync(len);
    readSw.stop();

    final decodeSw = Stopwatch()..start();
    final text = TxtCodecHelper.decodeBytes(bytes, encoding);
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
    required void Function() onSampleRss,
  }) {
    final buffer = Uint8List(chunkBytes);
    final lineCap = maxCandidateLineBytes + 4;
    final carry = Uint8List(lineCap);
    var carryLen = 0;
    var carryOverflowed = false;
    var lineStartByte = contentStart;
    var filePos = contentStart;
    var chunkCount = 0;

    while (filePos < fileLength) {
      final readCount = raf.readIntoSync(buffer);
      if (readCount <= 0) break;
      chunkCount++;
      if ((chunkCount & 0xF) == 0) onSampleRss();

      var segmentStart = 0;
      for (var i = 0; i < readCount; i++) {
        if (buffer[i] == 0x0A) {
          // Completed a line ending at filePos + i.
          if (!carryOverflowed) {
            final segLen = i - segmentStart;
            if (carryLen == 0) {
              // Fast path: full line lies inside buffer[segmentStart..i].
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

      // Carry over incomplete trailing line bytes.
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

    // Final line without trailing \n.
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
    required void Function() onSampleRss,
  }) {
    final evenChunkBytes = chunkBytes & ~1;
    final buffer = Uint8List(evenChunkBytes);
    final carry = Uint8List(maxCandidateLineBytes + 4);
    var carryLen = 0;
    var carryOverflowed = false;
    var lineStartByte = contentStart;
    var filePos = contentStart;
    var trailingOddByte = -1;
    var chunkCount = 0;

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

      chunkCount++;
      if ((chunkCount & 0xF) == 0) onSampleRss();

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
    final len = end - start;
    if (len <= 0) return false;
    final sampleLen = len < 4096 ? len : 4096;
    raf.setPositionSync(start);
    final bytes = raf.readSync(sampleLen);
    return TxtCodecHelper.decodeBytes(bytes, encoding).trim().isNotEmpty;
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
    final probeWindow = 512;

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

      // Snap cleanly to a newline or multi-byte character boundary near targetEnd.
      targetEnd = _snapBoundary(raf, encoding, pos, targetEnd, fileLength, probeWindow);
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

  static int _snapBoundary(
    RandomAccessFile raf,
    TxtEncoding encoding,
    int minPos,
    int targetPos,
    int fileLength,
    int probeWindow,
  ) {
    final searchStart = (targetPos - probeWindow).clamp(minPos + 1, fileLength);
    final searchEnd = (targetPos + probeWindow).clamp(searchStart, fileLength);
    final len = searchEnd - searchStart;
    if (len <= 0) return targetPos;

    raf.setPositionSync(searchStart);
    final probe = raf.readSync(len);

    if (encoding == TxtEncoding.utf16Le || encoding == TxtEncoding.utf16Be) {
      final isLe = encoding == TxtEncoding.utf16Le;
      final alignedOffset = (searchStart - encoding.bomLength).isOdd ? 1 : 0;
      for (var i = alignedOffset; i + 1 < probe.length; i += 2) {
        final isNl = isLe
            ? (probe[i] == 0x0A && probe[i + 1] == 0x00)
            : (probe[i] == 0x00 && probe[i + 1] == 0x0A);
        if (isNl) return searchStart + i + 2;
      }
      final targetEven =
          targetPos - ((targetPos - encoding.bomLength).isOdd ? 1 : 0);
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

    // GB18030/GBK: walk forward from searchStart to find exact character boundary.
    var i = 0;
    while (i < probe.length && searchStart + i < targetPos) {
      final b1 = probe[i];
      if (b1 <= 0x7F) {
        i++;
      } else if (i + 1 < probe.length && probe[i + 1] >= 0x30 && probe[i + 1] <= 0x39) {
        i += 4;
      } else {
        i += 2;
      }
    }
    return (searchStart + i).clamp(minPos + 1, fileLength);
  }
}
