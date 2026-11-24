import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('pureread_enc_test_');
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('TxtEncoding & TxtEncodingDetector', () {
    test('tryParse normalizes common encoding aliases and rejects unknown', () {
      expect(TxtEncoding.tryParse('utf-8'), TxtEncoding.utf8);
      expect(TxtEncoding.tryParse('UTF8'), TxtEncoding.utf8);
      expect(TxtEncoding.tryParse('utf-8-bom'), TxtEncoding.utf8Bom);
      expect(TxtEncoding.tryParse('gb18030'), TxtEncoding.gb18030);
      expect(TxtEncoding.tryParse('GBK'), TxtEncoding.gb18030);
      expect(TxtEncoding.tryParse('gb2312'), TxtEncoding.gb18030);
      expect(TxtEncoding.tryParse('utf-16le'), TxtEncoding.utf16Le);
      expect(TxtEncoding.tryParse('UTF16_LE'), TxtEncoding.utf16Le);
      expect(TxtEncoding.tryParse('UTF-16 LE'), TxtEncoding.utf16Le);
      expect(TxtEncoding.tryParse('utf-16be'), TxtEncoding.utf16Be);
      expect(TxtEncoding.tryParse('UTF16_BE'), TxtEncoding.utf16Be);
      expect(TxtEncoding.tryParse('shift_jis'), isNull);
      expect(TxtEncoding.tryParse(null), isNull);
    });

    test('detects UTF-8-BOM, UTF-16LE BOM, and UTF-16BE BOM reliably', () async {
      final utf8BomFile = File('${tmpDir.path}${Platform.pathSeparator}bom_utf8.txt');
      await utf8BomFile.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('第一章\n正文')]);
      final utf8BomRes = await TxtEncodingDetector.detectFile(utf8BomFile);
      expect(utf8BomRes.encoding, TxtEncoding.utf8Bom);
      expect(utf8BomRes.bomLength, 3);
      expect(utf8BomRes.isUndecodable, isFalse);

      final leFile = File('${tmpDir.path}${Platform.pathSeparator}bom_le.txt');
      await leFile.writeAsBytes(const Utf16Encoder().encodeUtf16Le('第一章\n正文', true));
      final leRes = await TxtEncodingDetector.detectFile(leFile);
      expect(leRes.encoding, TxtEncoding.utf16Le);
      expect(leRes.bomLength, 2);

      final beFile = File('${tmpDir.path}${Platform.pathSeparator}bom_be.txt');
      await beFile.writeAsBytes(const Utf16Encoder().encodeUtf16Be('第一章\n正文', true));
      final beRes = await TxtEncodingDetector.detectFile(beFile);
      expect(beRes.encoding, TxtEncoding.utf16Be);
      expect(beRes.bomLength, 2);
    });

    test('stateful cross-chunk detection handles 7-byte splits and delayed GBK', () async {
      final utf8Text = '第1章 青云初雪\n${'中文标点测试，。！？、》」《「（）\n' * 60}';
      final utf8Bytes = Uint8List.fromList(utf8.encode(utf8Text));
      final utf8Res = TxtEncodingDetector.detectBytes(utf8Bytes, chunkSize: 7);
      expect(utf8Res.encoding, TxtEncoding.utf8);
      expect(utf8Res.isUndecodable, isFalse);

      final delayedGbk = File('${tmpDir.path}${Platform.pathSeparator}delayed_gbk.txt');
      final asciiPad = 'ASCII header 0123456789\n' * 300;
      final gbkText = '$asciiPad第1章 延迟中文\n这里全是 GBK 编码汉字，。！？\n';
      await delayedGbk.writeAsBytes(gbk.encode(gbkText));
      final gbkRes = await TxtEncodingDetector.detectFile(
        delayedGbk,
        chunkSize: 7,
      );
      expect(gbkRes.encoding, TxtEncoding.gb18030);
      expect(gbkRes.isUndecodable, isFalse);
    });

    test('detects BOM-less UTF-16LE/BE and flags binary garbage as undecodable', () {
      final leNoBom = const Utf16Encoder().encodeUtf16Le('Chapter 1\nHello World\n', false);
      final leRes = TxtEncodingDetector.detectBytes(leNoBom);
      expect(leRes.encoding, TxtEncoding.utf16Le);
      expect(leRes.bomLength, 0);
      expect(leRes.isUndecodable, isFalse);

      final beNoBom = const Utf16Encoder().encodeUtf16Be('Chapter 1\nHello World\n', false);
      final beRes = TxtEncodingDetector.detectBytes(beNoBom);
      expect(beRes.encoding, TxtEncoding.utf16Be);
      expect(beRes.bomLength, 0);
      expect(beRes.isUndecodable, isFalse);

      final binary = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0xFF, 0x80, 0xFF, 0x00,
      ]);
      final binRes = TxtEncodingDetector.detectBytes(binary);
      expect(binRes.isUndecodable, isTrue);
    });
  });

  group('TxtCodecHelper', () {
    test('64K GBK table round-trips CJK, punctuation, and ASCII cleanly', () {
      TxtCodecHelper.warmUpGbkTable();
      const sample = '，。！？、》」《「（）“”…— PureRead v3.13 第1024章';
      final encoded = Uint8List.fromList(gbk.encode(sample));
      final decoded = TxtCodecHelper.decodeBytes(encoded, TxtEncoding.gb18030);
      expect(decoded, equals(sample));
    });

    test('decodes 4-byte GB18030 supplementary plane characters accurately', () {
      // U+20000 ('𠀀') -> linear = 189000 + (0x20000 - 0x10000) = 254536
      // -> b1=0x95, b2=0x32, b3=0x82, b4=0x36
      // U+1F600 ('😀') -> linear = 189000 + 62976 = 251976
      // -> b1=0x94, b2=0x39, b3=0xFC, b4=0x36
      final bytes = Uint8List.fromList(<int>[
        ...gbk.encode('前'),
        0x95, 0x32, 0x82, 0x36,
        0x94, 0x39, 0xFC, 0x36,
        ...gbk.encode('后'),
      ]);
      final decoded = TxtCodecHelper.decodeBytes(
        bytes,
        TxtEncoding.gb18030,
        allowMalformed: false,
      );
      expect(decoded, equals('前\u{20000}\u{1F600}后'));
    });

    test('explicit decodeUtf16Le/Be preserves mid-file slices, surrogate pairs, and 0xFEFF without BOM strip', () {
      const midSliceText = '\uFEFF第2章 归途\n正文《测试》PureRead \u{1F600}\u{20000}';
      final leSlice = _encodeUtf16(midSliceText, isLe: true, withBom: false);
      final beSlice = _encodeUtf16(midSliceText, isLe: false, withBom: false);

      expect(
        TxtCodecHelper.decodeBytes(leSlice, TxtEncoding.utf16Le, allowMalformed: false),
        equals(midSliceText),
      );
      expect(
        TxtCodecHelper.decodeBytes(beSlice, TxtEncoding.utf16Be, allowMalformed: false),
        equals(midSliceText),
      );
    });

    test('strict mode throws FormatException on invalid sequences', () {
      // Invalid UTF-8
      expect(
        () => TxtCodecHelper.decodeBytes(
          Uint8List.fromList(<int>[0xFF, 0xFE, 0x80]),
          TxtEncoding.utf8,
          allowMalformed: false,
        ),
        throwsFormatException,
      );

      // Truncated GBK
      expect(
        () => TxtCodecHelper.decodeBytes(
          Uint8List.fromList(<int>[0xB0]),
          TxtEncoding.gb18030,
          allowMalformed: false,
        ),
        throwsFormatException,
      );

      // Odd-byte UTF-16LE
      expect(
        () => TxtCodecHelper.decodeBytes(
          Uint8List.fromList(<int>[0x31, 0x00, 0x32]),
          TxtEncoding.utf16Le,
          allowMalformed: false,
        ),
        throwsFormatException,
      );

      // Unpaired UTF-16LE high surrogate
      expect(
        () => TxtCodecHelper.decodeBytes(
          Uint8List.fromList(<int>[0x00, 0xD8, 0x31, 0x00]),
          TxtEncoding.utf16Le,
          allowMalformed: false,
        ),
        throwsFormatException,
      );
    });
  });
}

Uint8List _encodeUtf16(
  String text, {
  required bool isLe,
  required bool withBom,
}) {
  final units = text.codeUnits;
  final out = Uint8List(units.length * 2 + (withBom ? 2 : 0));
  var offset = 0;
  if (withBom) {
    out[offset++] = isLe ? 0xFF : 0xFE;
    out[offset++] = isLe ? 0xFE : 0xFF;
  }
  for (final u in units) {
    if (isLe) {
      out[offset++] = u & 0xFF;
      out[offset++] = (u >> 8) & 0xFF;
    } else {
      out[offset++] = (u >> 8) & 0xFF;
      out[offset++] = u & 0xFF;
    }
  }
  return out;
}
