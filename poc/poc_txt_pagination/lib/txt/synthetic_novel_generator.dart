import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';

import 'txt_encoding.dart';

/// Metadata about a generated synthetic novel file.
class GeneratedNovelStats {
  const GeneratedNovelStats({
    required this.filePath,
    required this.encoding,
    required this.fileBytes,
    required this.chapterCount,
    required this.generationMicros,
  });

  final String filePath;
  final TxtEncoding encoding;
  final int fileBytes;
  final int chapterCount;
  final int generationMicros;
}

/// Generates realistic ~30 MB Chinese novel TXT files (UTF-8 and GB18030/GBK)
/// with ~1,500 chapters, mixed CJK/ASCII/digits, decoy sentences, and full
/// Chinese punctuation `，。！？、》」《「（）`.
class SyntheticNovelGenerator {
  SyntheticNovelGenerator._();

  static const int defaultTargetBytes = 30 * 1024 * 1024; // 30 MiB
  static const int defaultChapterCount = 1500;

  static const List<String> _titleThemes = <String>[
    '青云初雪',
    '星海归途',
    '长夜孤灯',
    '墨染江湖',
    '代码与剑',
    '风起云涌',
    '故人重逢',
    '破晓之光',
    '北境孤城',
    '山海旧约',
  ];

  static const List<String> _paragraphPool = <String>[
    '夜色微凉，沈砚合上桌上的《山海残卷》，抬头望向窗外闪烁的霓虹灯光。'
        '终端屏幕上的 PureRead v3.13 引擎仍在静默运行，日志里不断刷新着 1024 与 4096 的字节偏移刻度。'
        '「你确定要在今晚测试这套分页算法吗？」林清音端着热茶走近，「如果出现半个汉字乱码怎么办？」\r\n',
    '他轻轻一笑，在键盘上敲下几行 Flutter 测试命令：第1步校验编码，第2步构建章节索引，第3步统计字符守恒。'
        '窗外细雨淅沥，石板路上的积水倒映着古老牌坊与现代路灯，仿佛两个时代在此交汇！'
        '无论是「行首避头」还是「行尾避尾」，排版细节都决定了长篇阅读的呼吸感。\r\n',
    '“这已经是第7次压测了，数据流依然稳如磐石。”苏牧把玩着手中的青铜令牌（编号 A-2026），'
        '仔细核对清单上的条目：墨水屏适配、双栏布局、UTF-8 与 GB18030 流式识别、以及 RandomAccessFile 随机读取。'
        '远处的钟楼敲响了午夜十二点的钟声，第一缕山风穿过回廊，吹动了案头的书页……\r\n',
    '他想起三天前在藏书阁翻阅的笔记，里面记录着上古修士对《太虚真经》和《九霄星图》的批注。'
        '第一件事便是理清经脉与灵力的流转路径；第二件事则是防范心魔反噬（成功率仅 62.5%）。'
        '“别急，先喝口水，等 Dart Isolate 把三千万字节全部扫完再说！”\r\n',
    '长街尽头传来阵阵马蹄声，镖局的旗帜在暮色中猎猎作响，车队编号分别为 Alpha-01、Beta-02、Gamma-03。'
        '掌柜拨动算盘，嘴里念念有词：「三两银子、五斤熟肉、外加两坛女儿红——总共二十八贯钱，少一文都不行！」'
        '众人哄笑一堂，客栈里的灯火越发明亮温暖。\r\n',
    '在测试脚本运行到第1024行时，监控面板上的帧耗时曲线平稳地维持在 4.2ms 左右，远低于 16.6ms 的阈值。'
        '这就是工程打磨的意义：把复杂的底层编码与断行禁则藏在幕后，留给读者的只有纸张般的宁静与顺滑！'
        '翻过这一页，新的故事才刚刚拉开帷幕。\r\n',
  ];

  /// Streams a synthetic ~30 MB novel straight to [outputPath] without holding
  /// the entire 30 MB text in memory.
  static Future<GeneratedNovelStats> generate({
    required String outputPath,
    required TxtEncoding encoding,
    int targetBytes = defaultTargetBytes,
    int chapterCount = defaultChapterCount,
  }) async {
    assert(
      encoding == TxtEncoding.utf8 ||
          encoding == TxtEncoding.utf8Bom ||
          encoding == TxtEncoding.gb18030,
      'Synthetic generator targets UTF-8 / UTF-8-BOM / GB18030 variants.',
    );

    final sw = Stopwatch()..start();
    final file = File(outputPath);
    await file.parent.create(recursive: true);

    final sink = file.openWrite();
    final chunkBuf = BytesBuilder(copy: false);
    const flushThresholdBytes = 256 * 1024;
    var writtenBytes = 0;

    void emitBytes(List<int> bytes) {
      chunkBuf.add(bytes);
      writtenBytes += bytes.length;
      if (chunkBuf.length >= flushThresholdBytes) {
        sink.add(chunkBuf.takeBytes());
      }
    }

    Uint8List encodeText(String text) {
      if (encoding == TxtEncoding.gb18030) {
        return Uint8List.fromList(gbk.encode(text));
      }
      return Uint8List.fromList(utf8.encode(text));
    }

    // Pre-encode paragraph pool once for blazing fast generation.
    final encodedParagraphs =
        _paragraphPool.map(encodeText).toList(growable: false);
    final avgParagraphBytes = encodedParagraphs.fold<int>(
          0,
          (sum, b) => sum + b.length,
        ) ~/
        encodedParagraphs.length;

    if (encoding == TxtEncoding.utf8Bom) {
      emitBytes(const <int>[0xEF, 0xBB, 0xBF]);
    }

    // Small preface before Chapter 1 to validate prologue extraction or clean start.
    emitBytes(
      encodeText(
        '《墨海星图（2026精校版）》\r\n作者：净读测试集\r\n'
        '简介：一部用于验证 PureRead（净读）30MB 流式分章与精细排版的长篇测试小说。\r\n\r\n',
      ),
    );

    final bytesPerChapterTarget =
        (targetBytes - writtenBytes) ~/ chapterCount;

    for (var i = 0; i < chapterCount; i++) {
      final title = _buildChapterTitle(i, chapterCount);
      final headerBytes = encodeText('$title\r\n');
      emitBytes(headerBytes);

      var chapterBytes = headerBytes.length;
      // Keep chapter sizes slightly varied around bytesPerChapterTarget, while
      // guaranteeing total size reaches >= targetBytes by the final chapter.
      final remainingTarget = targetBytes - writtenBytes;
      final remainingChapters = chapterCount - i;
      final adaptiveTarget = remainingTarget ~/ remainingChapters;
      final desiredChapterBytes =
          adaptiveTarget > bytesPerChapterTarget ? adaptiveTarget : bytesPerChapterTarget;

      var pIdx = i;
      while (chapterBytes + avgParagraphBytes <= desiredChapterBytes ||
          (i == chapterCount - 1 && writtenBytes < targetBytes)) {
        final pBytes = encodedParagraphs[pIdx % encodedParagraphs.length];
        emitBytes(pBytes);
        chapterBytes += pBytes.length;
        pIdx++;
      }

      emitBytes(const <int>[0x0D, 0x0A]);
    }

    if (chunkBuf.isNotEmpty) {
      sink.add(chunkBuf.takeBytes());
    }
    await sink.flush();
    await sink.close();
    sw.stop();

    return GeneratedNovelStats(
      filePath: outputPath,
      encoding: encoding,
      fileBytes: writtenBytes,
      chapterCount: chapterCount,
      generationMicros: sw.elapsedMicroseconds,
    );
  }

  static String _buildChapterTitle(int index, int totalCount) {
    final theme = _titleThemes[index % _titleThemes.length];
    if (index == 0) {
      return '序章 $theme';
    }
    if (index == totalCount - 1) {
      return '尾声 $theme（2026终章）';
    }
    if (index % 250 == 0) {
      return '第${_toChineseNumeral(index)}回 $theme';
    }
    if (index % 50 == 0) {
      return '第${_toChineseNumeral(index)}章：$theme';
    }
    return '第$index章 $theme（$index）';
  }

  static String _toChineseNumeral(int n) {
    const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    if (n <= 0) return '零';
    if (n < 10) return digits[n];
    final buf = StringBuffer();
    final thousands = n ~/ 1000;
    final hundreds = (n % 1000) ~/ 100;
    final tens = (n % 100) ~/ 10;
    final ones = n % 10;

    if (thousands > 0) {
      buf.write('${digits[thousands]}千');
    }
    if (hundreds > 0) {
      buf.write('${digits[hundreds]}百');
    } else if (thousands > 0 && (tens > 0 || ones > 0)) {
      buf.write('零');
    }
    if (tens > 0) {
      if (tens > 1 || thousands > 0 || hundreds > 0) {
        buf.write(digits[tens]);
      }
      buf.write('十');
    } else if (hundreds > 0 && ones > 0) {
      buf.write('零');
    }
    if (ones > 0) {
      buf.write(digits[ones]);
    }
    return buf.toString();
  }
}
