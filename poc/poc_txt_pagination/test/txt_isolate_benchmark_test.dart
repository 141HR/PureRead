import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_txt_pagination/txt/synthetic_novel_generator.dart';
import 'package:poc_txt_pagination/txt/txt_chapter_scanner.dart';
import 'package:poc_txt_pagination/txt/txt_encoding.dart';

void main() {
  final tmpDir = Directory('${Directory.current.path}${Platform.pathSeparator}.tmp');
  late File utf8File;
  late File gb18030File;

  setUpAll(() async {
    await tmpDir.create(recursive: true);
    utf8File = File('${tmpDir.path}${Platform.pathSeparator}novel_utf8_30mb.txt');
    gb18030File = File('${tmpDir.path}${Platform.pathSeparator}novel_gb18030_30mb.txt');

    final utf8Gen = await SyntheticNovelGenerator.generate(
      outputPath: utf8File.path,
      encoding: TxtEncoding.utf8,
    );
    final gbGen = await SyntheticNovelGenerator.generate(
      outputPath: gb18030File.path,
      encoding: TxtEncoding.gb18030,
    );

    // ignore: avoid_print
    print(
      '[GEN] UTF-8: ${(utf8Gen.fileBytes / (1024 * 1024)).toStringAsFixed(2)} MiB, '
      '${utf8Gen.chapterCount} chapters in ${(utf8Gen.generationMicros / 1000).toStringAsFixed(1)} ms',
    );
    // ignore: avoid_print
    print(
      '[GEN] GB18030: ${(gbGen.fileBytes / (1024 * 1024)).toStringAsFixed(2)} MiB, '
      '${gbGen.chapterCount} chapters in ${(gbGen.generationMicros / 1000).toStringAsFixed(1)} ms',
    );
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('GBK codec round-trips all required Chinese punctuation cleanly', () {
    const sample = '，。！？、》」《「（）“”…— PureRead v3.13 第1024章';
    final encoded = gbk.encode(sample);
    final decoded = TxtCodecHelper.decodeBytes(
      Uint8List.fromList(encoded),
      TxtEncoding.gb18030,
    );
    expect(decoded, equals(sample));
  });

  test('30MB UTF-8 novel: Isolate streaming detect + scan < 2.0s & RAF read < 200ms', () async {
    final sw = Stopwatch()..start();
    final scan = await TxtChapterScanner.scanInBackgroundIsolate(utf8File.path);
    sw.stop();

    // ignore: avoid_print
    print(
      '[BENCH UTF-8] file=${(scan.fileBytes / (1024 * 1024)).toStringAsFixed(2)} MiB, '
      'encoding=${scan.encoding.label}, chapters=${scan.chapters.length}, '
      'detect=${(scan.detectMicros / 1000).toStringAsFixed(2)} ms, '
      'scan=${(scan.scanMicros / 1000).toStringAsFixed(2)} ms, '
      'wallWithIsolate=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)} ms, '
      'rssDelta=${(scan.peakMemoryDeltaBytes / (1024 * 1024)).toStringAsFixed(2)} MiB',
    );

    expect(scan.encoding, TxtEncoding.utf8);
    expect(scan.fileBytes, greaterThanOrEqualTo(30 * 1024 * 1024));
    expect(scan.usedFallbackSplit, isFalse);
    // 1500 chapters + 1 preface = 1501 entries, zero false positives from decoy lines
    expect(scan.chapters.length, equals(1501));
    expect(sw.elapsedMilliseconds, lessThan(2000));

    // Verify contiguous byte ranges covering entire file
    for (var i = 0; i < scan.chapters.length; i++) {
      final c = scan.chapters[i];
      expect(c.chapterIndex, equals(i));
      expect(c.byteStart, lessThan(c.byteEnd));
      if (i + 1 < scan.chapters.length) {
        expect(c.byteEnd, equals(scan.chapters[i + 1].byteStart));
      }
    }
    expect(scan.chapters.last.byteEnd, equals(scan.fileBytes));

    // Benchmark RandomAccessFile single-chapter slice read (first, middle, last)
    for (final idx in <int>[1, 750, scan.chapters.length - 1]) {
      final readSw = Stopwatch()..start();
      final chapter = await TxtChapterScanner.readChapterInBackgroundIsolate(
        utf8File.path,
        scan.chapters[idx],
        scan.encoding,
      );
      readSw.stop();

      // ignore: avoid_print
      print(
        '[RAF UTF-8] ch#$idx "${chapter.title}" bytes=${chapter.bytesRead}, '
        'read=${(chapter.readMicros / 1000).toStringAsFixed(3)} ms, '
        'decode=${(chapter.decodeMicros / 1000).toStringAsFixed(3)} ms, '
        'wall=${(readSw.elapsedMicroseconds / 1000).toStringAsFixed(3)} ms',
      );

      expect(chapter.text.startsWith(scan.chapters[idx].title), isTrue);
      expect(chapter.text.contains('，'), isTrue);
      expect(chapter.text.contains('PureRead'), isTrue);
      expect(readSw.elapsedMilliseconds, lessThan(200));
    }
  });

  test('30MB GB18030 novel: Isolate streaming detect + scan < 2.0s & RAF read < 200ms', () async {
    final sw = Stopwatch()..start();
    final scan = await TxtChapterScanner.scanInBackgroundIsolate(gb18030File.path);
    sw.stop();

    // ignore: avoid_print
    print(
      '[BENCH GB18030] file=${(scan.fileBytes / (1024 * 1024)).toStringAsFixed(2)} MiB, '
      'encoding=${scan.encoding.label}, chapters=${scan.chapters.length}, '
      'detect=${(scan.detectMicros / 1000).toStringAsFixed(2)} ms, '
      'scan=${(scan.scanMicros / 1000).toStringAsFixed(2)} ms, '
      'wallWithIsolate=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)} ms, '
      'rssDelta=${(scan.peakMemoryDeltaBytes / (1024 * 1024)).toStringAsFixed(2)} MiB',
    );

    expect(scan.encoding, TxtEncoding.gb18030);
    expect(scan.fileBytes, greaterThanOrEqualTo(30 * 1024 * 1024));
    expect(scan.usedFallbackSplit, isFalse);
    expect(scan.chapters.length, equals(1501));
    expect(sw.elapsedMilliseconds, lessThan(2000));

    // Verify RandomAccessFile single-chapter slice read with no garbled chars
    for (final idx in <int>[1, 750, scan.chapters.length - 1]) {
      final readSw = Stopwatch()..start();
      final chapter = await TxtChapterScanner.readChapterInBackgroundIsolate(
        gb18030File.path,
        scan.chapters[idx],
        scan.encoding,
      );
      readSw.stop();

      // ignore: avoid_print
      print(
        '[RAF GB18030] ch#$idx "${chapter.title}" bytes=${chapter.bytesRead}, '
        'read=${(chapter.readMicros / 1000).toStringAsFixed(3)} ms, '
        'decode=${(chapter.decodeMicros / 1000).toStringAsFixed(3)} ms, '
        'wall=${(readSw.elapsedMicroseconds / 1000).toStringAsFixed(3)} ms',
      );

      expect(chapter.text.startsWith(scan.chapters[idx].title), isTrue);
      expect(chapter.text.contains('\uFFFD'), isFalse);
      expect(chapter.text.contains('》'), isTrue);
      expect(chapter.text.contains('「'), isTrue);
      expect(readSw.elapsedMilliseconds, lessThan(200));
    }
  });

  test('UTF-8-BOM, UTF-16LE BOM, UTF-16BE BOM, chunk split & no-chapter fallback', () async {
    const sampleNovel = '第1章 起航\r\n这是第一段，包含「引号」与 PureRead 123。\r\n'
        '第2章 归途\r\n这是第二段《测试》，结束！\r\n';

    // UTF-8 BOM
    final utf8BomFile = File('${tmpDir.path}${Platform.pathSeparator}sample_utf8_bom.txt');
    await utf8BomFile.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(sampleNovel)]);
    final utf8BomScan = await TxtChapterScanner.scanInBackgroundIsolate(utf8BomFile.path);
    expect(utf8BomScan.encoding, TxtEncoding.utf8Bom);
    expect(utf8BomScan.chapters.length, 2);
    final bomCh1 = TxtChapterScanner.readChapterSliceSync(
      utf8BomFile,
      utf8BomScan.chapters[0],
      utf8BomScan.encoding,
    );
    expect(bomCh1.text.startsWith('第1章 起航'), isTrue);

    // UTF-16LE BOM
    final utf16LeFile = File('${tmpDir.path}${Platform.pathSeparator}sample_utf16le.txt');
    await utf16LeFile.writeAsBytes(
      const Utf16Encoder().encodeUtf16Le(sampleNovel, true),
    );
    final leScan = await TxtChapterScanner.scanInBackgroundIsolate(utf16LeFile.path);
    expect(leScan.encoding, TxtEncoding.utf16Le);
    expect(leScan.chapters.length, 2);
    final leCh2 = TxtChapterScanner.readChapterSliceSync(
      utf16LeFile,
      leScan.chapters[1],
      leScan.encoding,
    );
    expect(leCh2.text.startsWith('第2章 归途'), isTrue);
    expect(leCh2.text.contains('《测试》'), isTrue);

    // UTF-16BE BOM
    final utf16BeFile = File('${tmpDir.path}${Platform.pathSeparator}sample_utf16be.txt');
    await utf16BeFile.writeAsBytes(
      const Utf16Encoder().encodeUtf16Be(sampleNovel, true),
    );
    final beScan = await TxtChapterScanner.scanInBackgroundIsolate(utf16BeFile.path);
    expect(beScan.encoding, TxtEncoding.utf16Be);
    expect(beScan.chapters.length, 2);
    final beCh1 = TxtChapterScanner.readChapterSliceSync(
      utf16BeFile,
      beScan.chapters[0],
      beScan.encoding,
    );
    expect(beCh1.text.startsWith('第1章 起航'), isTrue);

    // Chunk-boundary split test (64-byte chunks) + delayed non-ASCII (> 4KB ASCII prefix)
    final delayedFile = File('${tmpDir.path}${Platform.pathSeparator}delayed_gbk.txt');
    final asciiPad = 'ASCII header line 0123456789\n' * 300;
    final gbkBody = '$asciiPad第1章 延迟中文\n正文开始，中文GBK测试！\n第2章 继续\n结尾。\n';
    await delayedFile.writeAsBytes(gbk.encode(gbkBody));
    final delayedScan = await Isolate.run(
      () => TxtChapterScanner.scanFileSync(delayedFile, chunkBytes: 64),
    );
    expect(delayedScan.encoding, TxtEncoding.gb18030);
    expect(delayedScan.chapters.length, 3); // preface ASCII + ch1 + ch2
    expect(delayedScan.chapters[1].title, '第1章 延迟中文');

    // No-chapter fallback segmentation (PRD F1.1)
    final plainFile = File('${tmpDir.path}${Platform.pathSeparator}no_chapters.txt');
    final plainText = '这是一段没有章节标题的纯文本小说内容，包含各种中文标点：，。！？、》」《「（）以及数字2026。\n' * 400;
    await plainFile.writeAsBytes(utf8.encode(plainText));
    final fallbackScan = await TxtChapterScanner.scanInBackgroundIsolate(
      plainFile.path,
      fallbackSegmentBytes: 4096,
    );
    expect(fallbackScan.usedFallbackSplit, isTrue);
    expect(fallbackScan.chapters.length, greaterThan(4));

    // Rejoining all fallback chapter slices restores the exact original text!
    final restored = StringBuffer();
    for (final ch in fallbackScan.chapters) {
      final slice = TxtChapterScanner.readChapterSliceSync(
        plainFile,
        ch,
        fallbackScan.encoding,
      );
      restored.write(slice.text);
    }
    expect(restored.toString(), equals(plainText));
  });
}
