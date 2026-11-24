import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/failures/app_failure.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('pureread_scan_test_');
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('TxtChapterScanner', () {
    const sampleNovel =
        '《测试书名》\r\n作者：测试\r\n'
        '第1章 初入江湖\r\n这是第7次测试，第1步校验编码，第一件事记录细节。\r\n'
        '第2章 风起云涌\r\n第二段《山海》，包含「引号」与 PureRead 2026！\r\n'
        '尾声 山海旧约\r\n全书完。';

    test('scans UTF-8, UTF-8-BOM, GB18030, UTF-16LE, UTF-16BE with tiny 64B chunks', () async {
      final variants = <({
        String name,
        TxtEncoding expected,
        List<int> bytes,
      })>[
        (
          name: 'utf8.txt',
          expected: TxtEncoding.utf8,
          bytes: utf8.encode(sampleNovel),
        ),
        (
          name: 'utf8_bom.txt',
          expected: TxtEncoding.utf8Bom,
          bytes: <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(sampleNovel)],
        ),
        (
          name: 'gb18030.txt',
          expected: TxtEncoding.gb18030,
          bytes: gbk.encode(sampleNovel),
        ),
        (
          name: 'utf16le.txt',
          expected: TxtEncoding.utf16Le,
          bytes: const Utf16Encoder().encodeUtf16Le(sampleNovel, true),
        ),
        (
          name: 'utf16be.txt',
          expected: TxtEncoding.utf16Be,
          bytes: const Utf16Encoder().encodeUtf16Be(sampleNovel, true),
        ),
      ];

      for (final v in variants) {
        final file = File('${tmpDir.path}${Platform.pathSeparator}${v.name}');
        await file.writeAsBytes(v.bytes);

        final scan = TxtChapterScanner.scanFileSync(file, chunkBytes: 64);
        expect(scan.encoding, v.expected, reason: v.name);
        expect(scan.usedFallbackSplit, isFalse, reason: v.name);
        expect(
          scan.chapters.map((c) => c.title).toList(),
          equals(<String>['序言', '第1章 初入江湖', '第2章 风起云涌', '尾声 山海旧约']),
          reason: v.name,
        );

        // Contiguous byte coverage starting right after BOM
        expect(scan.chapters.first.byteStart, scan.bomLength, reason: v.name);
        expect(scan.chapters.last.byteEnd, v.bytes.length, reason: v.name);
        for (var i = 0; i + 1 < scan.chapters.length; i++) {
          expect(scan.chapters[i].byteEnd, scan.chapters[i + 1].byteStart);
        }

        // Mid-file slice reads reconstruct exact body without BOM or FFFD
        final ch2 = TxtChapterScanner.readChapterSliceSync(
          file,
          scan.chapters[2],
          scan.encoding,
          allowMalformed: false,
        );
        expect(ch2.text.startsWith('第2章 风起云涌'), isTrue, reason: v.name);
        expect(ch2.text.contains('「引号」与 PureRead 2026！'), isTrue, reason: v.name);
        expect(ch2.text.contains('\uFEFF'), isFalse, reason: v.name);
        expect(ch2.text.contains('\uFFFD'), isFalse, reason: v.name);

        // Full reassembly equals exact original sampleNovel
        final reassembled = StringBuffer();
        for (final ch in scan.chapters) {
          reassembled.write(
            TxtChapterScanner.readChapterSliceSync(
              file,
              ch,
              scan.encoding,
              allowMalformed: false,
            ).text,
          );
        }
        expect(reassembled.toString(), equals(sampleNovel), reason: v.name);
      }
    });

    test('skips whitespace-only prefix instead of creating empty preface', () async {
      final file = File('${tmpDir.path}${Platform.pathSeparator}ws_prefix.txt');
      await file.writeAsString('\r\n   \t\r\n第1章 正文\r\n内容。\r\n');
      final scan = TxtChapterScanner.scanFileSync(file);
      expect(scan.chapters.length, 1);
      expect(scan.chapters.first.title, '第1章 正文');
    });

    test('handles empty file gracefully with 0 chapters', () async {
      final file = File('${tmpDir.path}${Platform.pathSeparator}empty.txt');
      await file.writeAsBytes(const <int>[]);
      final scan = TxtChapterScanner.scanFileSync(file);
      expect(scan.chapters, isEmpty);
      expect(scan.usedFallbackSplit, isFalse);
    });

    test('fallback splits chapter-less UTF-8, dense GBK, and UTF-16LE with surrogates losslessly', () async {
      // UTF-8 without chapters
      final utf8Plain = File('${tmpDir.path}${Platform.pathSeparator}plain_utf8.txt');
      final utf8Text = '没有章回标题的纯文本小说，包含标点：，。！？。\n' * 180;
      await utf8Plain.writeAsBytes(utf8.encode(utf8Text));
      final utf8Scan = TxtChapterScanner.scanFileSync(
        utf8Plain,
        fallbackSegmentBytes: 1024,
      );
      expect(utf8Scan.usedFallbackSplit, isTrue);
      expect(utf8Scan.chapters.length, greaterThan(4));
      final utf8Restored = utf8Scan.chapters
          .map((c) => TxtChapterScanner.readChapterSliceSync(
                utf8Plain,
                c,
                utf8Scan.encoding,
                allowMalformed: false,
              ).text)
          .join();
      expect(utf8Restored, equals(utf8Text));

      // Dense GBK with ZERO ASCII/newlines near boundary (tests exact resync walk)
      final denseGbk = File('${tmpDir.path}${Platform.pathSeparator}plain_dense_gbk.txt');
      final denseText = '纯汉字无空格无换行测试文本' * 400;
      await denseGbk.writeAsBytes(gbk.encode(denseText));
      final gbkScan = TxtChapterScanner.scanFileSync(
        denseGbk,
        fallbackSegmentBytes: 999, // odd byte target inside 2-byte GBK
      );
      expect(gbkScan.usedFallbackSplit, isTrue);
      expect(gbkScan.chapters.length, greaterThan(4));
      final gbkRestored = gbkScan.chapters
          .map((c) => TxtChapterScanner.readChapterSliceSync(
                denseGbk,
                c,
                gbkScan.encoding,
                allowMalformed: false,
              ).text)
          .join();
      expect(gbkRestored, equals(denseText));

      // Dense UTF-16LE with surrogate pairs (no newlines near boundary)
      final utf16Surr = File('${tmpDir.path}${Platform.pathSeparator}plain_utf16_surr.txt');
      final surrText = '测\u{1F600}试\u{20000}' * 500;
      await utf16Surr.writeAsBytes(
        _encodeUtf16LeWithBom(surrText),
      );
      final surrScan = TxtChapterScanner.scanFileSync(
        utf16Surr,
        fallbackSegmentBytes: 1025,
      );
      expect(surrScan.usedFallbackSplit, isTrue);
      final surrRestored = surrScan.chapters
          .map((c) => TxtChapterScanner.readChapterSliceSync(
                utf16Surr,
                c,
                surrScan.encoding,
                allowMalformed: false,
              ).text)
          .join();
      expect(surrRestored, equals(surrText));
    });

    test('computeFastFileHash hashes size + head/tail 64 KiB and throws FileAccessFailure when missing', () async {
      final f1 = File('${tmpDir.path}${Platform.pathSeparator}hash_a.bin');
      final f2 = File('${tmpDir.path}${Platform.pathSeparator}hash_b.bin');
      final f3 = File('${tmpDir.path}${Platform.pathSeparator}hash_c.bin');

      const size = 200 * 1024;
      final base = Uint8List(size);
      for (var i = 0; i < size; i++) {
        base[i] = i & 0xFF;
      }
      await f1.writeAsBytes(base);

      final headChanged = Uint8List.fromList(base)..[10] ^= 0x01;
      await f2.writeAsBytes(headChanged);

      final tailChanged = Uint8List.fromList(base)..[size - 10] ^= 0x01;
      await f3.writeAsBytes(tailChanged);

      final f4 = File('${tmpDir.path}${Platform.pathSeparator}hash_d.bin');
      await f4.writeAsBytes(Uint8List(size + 1));

      final h1 = await TxtChapterScanner.computeFastFileHash(f1.path);
      final h1Sync = TxtChapterScanner.computeFastFileHashSync(f1.path);
      final h2 = await TxtChapterScanner.computeFastFileHash(f2.path);
      final h3 = await TxtChapterScanner.computeFastFileHash(f3.path);
      final h4 = await TxtChapterScanner.computeFastFileHash(f4.path);

      expect(h1, equals(h1Sync));
      expect(h1, isNot(equals(h2)));
      expect(h1, isNot(equals(h3)));
      expect(h2, isNot(equals(h3)));
      expect(h1, isNot(equals(h4)));

      final bgScan = await TxtChapterScanner.scanInBackgroundIsolate(
        '${tmpDir.path}${Platform.pathSeparator}utf8.txt',
      );
      expect(bgScan.encoding, TxtEncoding.utf8);
      expect(bgScan.chapters.length, 4);

      await expectLater(
        () => TxtChapterScanner.computeFastFileHash('${tmpDir.path}${Platform.pathSeparator}missing.txt'),
        throwsA(isA<FileAccessFailure>()),
      );
    });
  });
}

Uint8List _encodeUtf16LeWithBom(String text) {
  final units = text.codeUnits;
  final out = Uint8List(units.length * 2 + 2);
  out[0] = 0xFF;
  out[1] = 0xFE;
  var offset = 2;
  for (final u in units) {
    out[offset++] = u & 0xFF;
    out[offset++] = (u >> 8) & 0xFF;
  }
  return out;
}
