import 'dart:isolate';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_txt_pagination/pagination/chinese_typesetting.dart';
import 'package:poc_txt_pagination/pagination/incremental_paginator.dart';
import 'package:poc_txt_pagination/pagination/pagination_models.dart';

String _build5000CharChapter() {
  const paragraphs = <String>[
    '夜色微凉，沈砚合上桌上的《山海残卷》，抬头望向窗外闪烁的霓虹灯光。'
        '终端屏幕上的 PureRead v3.13 引擎仍在静默运行，日志里不断刷新着 1024 与 4096 的字节偏移刻度。'
        '「你确定要在今晚测试这套分页算法吗？」林清音端着热茶走近，「如果出现半个汉字乱码怎么办？」\n',
    '他轻轻一笑，在键盘上敲下几行 Flutter 测试命令：第1步校验编码，第2步构建章节索引，第3步统计字符守恒。'
        '窗外细雨淅沥，石板路上的积水倒映着古老牌坊与现代路灯，仿佛两个时代在此交汇！'
        '无论是「行首避头」还是「行尾避尾」，排版细节都决定了长篇阅读的呼吸感。\n',
    '“这已经是第7次压测了，数据流依然稳如磐石。”苏牧把玩着手中的青铜令牌（编号 A-2026），'
        '仔细核对清单上的条目：墨水屏适配、双栏布局、UTF-8 与 GB18030 流式识别、以及 RandomAccessFile 随机读取。'
        '远处的钟楼敲响了午夜十二点的钟声，第一缕山风穿过回廊，吹动了案头的书页……\n',
    '长街尽头传来阵阵马蹄声，镖局的旗帜在暮色中猎猎作响，车队编号分别为 Alpha-01、Beta-02、Gamma-03。'
        '掌柜拨动算盘，嘴里念念有词：「三两银子、五斤熟肉、外加两坛女儿红——总共二十八贯钱，少一文都不行！」'
        '众人哄笑一堂，客栈里的灯火越发明亮温暖。\n',
  ];

  final buf = StringBuffer('第42章 墨海星图（PureRead 2026）\n');
  var idx = 0;
  while (buf.length < 5000) {
    buf.write(paragraphs[idx % paragraphs.length]);
    idx++;
  }
  return buf.toString();
}

void _assertCharacterConservation(String chapterText, List<PageSlice> pages) {
  expect(pages, isNotEmpty);
  expect(pages.first.startCharOffset, equals(0));
  expect(pages.last.endCharOffset, equals(chapterText.length));

  final pageJoin = StringBuffer();
  final lineJoin = StringBuffer();
  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    expect(p.pageIndex, equals(i));
    if (i + 1 < pages.length) {
      expect(p.endCharOffset, equals(pages[i + 1].startCharOffset));
    }
    pageJoin.write(p.sliceText(chapterText));

    if (p.lines.isNotEmpty) {
      expect(p.lines.first.startCharOffset, equals(p.startCharOffset));
      expect(p.lines.last.endCharOffset, equals(p.endCharOffset));
      for (var j = 0; j < p.lines.length; j++) {
        final l = p.lines[j];
        if (j + 1 < p.lines.length) {
          expect(l.endCharOffset, equals(p.lines[j + 1].startCharOffset));
        }
        lineJoin.write(l.rawSlice(chapterText));
      }
    }
  }

  expect(pageJoin.toString(), equals(chapterText));
  expect(lineJoin.toString(), equals(chapterText));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dart:ui / TextPainter cannot execute inside background Isolate', () async {
    final threw = await Isolate.run(() {
      try {
        final tp = TextPainter(
          text: const TextSpan(text: '测试', style: TextStyle(fontSize: 16)),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        return false;
      } catch (_) {
        return true;
      }
    });
    expect(threw, isTrue);
  });

  test('Batched TextPainter glyph cache matches single-glyph TextPainter widths', () {
    const config = PaginationConfig(
      columnWidth: 340,
      columnHeight: 600,
      fontSize: 18,
    );
    final cache = TextPainterMetricsCache(config);
    const sample = '汉字排版，。！？、》」《「（）Flutter2026';
    cache.warmUpSlice(sample, 0, sample.length);

    final style = TextStyle(
      fontFamily: config.fontFamily,
      fontSize: config.fontSize,
      fontWeight: config.fontWeight,
      height: config.lineHeightMultiplier,
      letterSpacing: 0.0,
    );
    for (final rune in sample.runes) {
      final tp = TextPainter(
        text: TextSpan(text: String.fromCharCode(rune), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(cache.runeWidth(rune), closeTo(tp.width, 0.05));
    }
  });

  test('Chinese punctuation prohibition (避头尾禁则) holds across varied widths & edge cases', () {
    final paginator = IncrementalTextPaginator();
    const edgeText =
        '这是一个专门测试中文标点避头尾禁则的段落，包含逗号，句号。感叹号！问号？顿号、'
        '以及书名号《山海经》，直角引号「测试文本」，圆括号（附注内容），'
        '还有连续标点组合「《测试》」！请问真的能完全避免吗？当然可以。\n'
        '再来一段混合了各种结束标点的内容》」），。！？、然后接续《「（这些左标点绝对不能孤立留在行尾。\n';

    for (final width in <double>[220, 260, 300, 342, 380]) {
      for (final fontSize in <double>[16, 18, 20, 22]) {
        if (width / fontSize < 10.5) continue;
        final config = PaginationConfig(
          columnWidth: width,
          columnHeight: 700,
          fontSize: fontSize,
        );
        final pages = paginator.paginateChapterSync(
          chapterIndex: 0,
          sanitizedText: edgeText,
          config: config,
        );
        _assertCharacterConservation(edgeText, pages);

        for (final page in pages) {
          for (final line in page.lines) {
            final lineStr = line.renderText(edgeText);
            if (lineStr.isEmpty) continue;
            final firstCp = lineStr.runes.first;
            expect(
              ChineseTypesetting.isLineStartProhibited(firstCp),
              isFalse,
              reason:
                  'Line started with prohibited punctuation "${String.fromCharCode(firstCp)}" '
                  'at width=$width fontSize=$fontSize line="$lineStr"',
            );
            if (!line.isParagraphEnd) {
              final lastCp = lineStr.runes.last;
              expect(
                ChineseTypesetting.isLineEndProhibited(lastCp),
                isFalse,
                reason:
                    'Non-terminal line ended with prohibited punctuation "${String.fromCharCode(lastCp)}" '
                    'at width=$width fontSize=$fontSize line="$lineStr"',
              );
            }
          }
        }
      }
    }

    // Pathological all-punctuation input must terminate cleanly and conserve 100% chars.
    final pathological = '${'，' * 60}\n${'《' * 60}\n';
    final pathPages = paginator.paginateChapterSync(
      chapterIndex: 0,
      sanitizedText: pathological,
      config: const PaginationConfig(columnWidth: 200, columnHeight: 300),
    );
    _assertCharacterConservation(pathological, pathPages);
  });

  test('CJK-ASCII micro-spacing adds gaps cleanly without mutating text offsets', () {
    final paginator = IncrementalTextPaginator();
    const text = '使用Flutter框架2026版，在《PureRead》中运行v3引擎。';
    const config = PaginationConfig(
      columnWidth: 900,
      columnHeight: 500,
      fontSize: 18,
      enableCjkSpacing: true,
    );

    final pages = paginator.paginateChapterSync(
      chapterIndex: 0,
      sanitizedText: text,
      config: config,
    );
    _assertCharacterConservation(text, pages);

    final line = pages.single.lines.single;
    // Transitions: 用->F, r->框, 架->2, 6->版, 行->v, 3->引 (excludes 《/》 punctuation!)
    final gapChars = line.cjkGapOffsets.map((i) => text[i]).toList();
    expect(gapChars, equals(<String>['用', 'r', '架', '6', '行', '3']));

    final metrics = paginator.metricsFor(config);
    final painter = metrics.buildLinePainter(
      line,
      text,
      textColor: const Color(0xFF000000),
    );
    expect(painter.text!.toPlainText(), equals(line.renderText(text)));
  });

  test('100% character conservation on empty, CRLF, blank-lines, surrogate pairs & 5k chapter', () {
    final paginator = IncrementalTextPaginator();
    const config = PaginationConfig(columnWidth: 340, columnHeight: 580);

    // Empty text
    final emptyPages = paginator.paginateChapterSync(
      chapterIndex: 0,
      sanitizedText: '',
      config: config,
    );
    _assertCharacterConservation('', emptyPages);

    // CRLF, multiple blank lines, leading ideographic indent, and non-BMP surrogates
    const tricky =
        '\r\n　　第一段含生僻字𠮷与表情😀，换行测试。\r\n\r\n\r\n'
        '第二段继续测试，包含《引号》和数字12345。\r\n';
    final trickyPages = paginator.paginateChapterSync(
      chapterIndex: 1,
      sanitizedText: tricky,
      config: config,
    );
    _assertCharacterConservation(tricky, trickyPages);

    // Realistic ~5,000 CJK char chapter
    final chapter5k = _build5000CharChapter();
    final pages5k = paginator.paginateChapterSync(
      chapterIndex: 42,
      sanitizedText: chapter5k,
      config: config,
      treatFirstLineAsTitle: true,
    );
    _assertCharacterConservation(chapter5k, pages5k);
  });

  test('Single-column & two-column logical page reuse (P_{2k}, P_{2k+1}) and charOffset round-trip', () {
    final paginator = IncrementalTextPaginator();
    final chapter = _build5000CharChapter();

    final mobileCfg = PaginationConfig.fromViewport(
      viewportWidth: 390,
      viewportHeight: 760,
      columnCount: 1,
      fontSize: 18,
    );
    final desktop2ColCfg = PaginationConfig.fromViewport(
      viewportWidth: 1100,
      viewportHeight: 760,
      columnCount: 2,
      columnGap: 48,
      fontSize: 22,
    );
    final narrowCfg = PaginationConfig.fromViewport(
      viewportWidth: 320,
      viewportHeight: 620,
      columnCount: 1,
      fontSize: 15,
    );

    final mobilePages = paginator.paginateChapterSync(
      chapterIndex: 42,
      sanitizedText: chapter,
      config: mobileCfg,
      treatFirstLineAsTitle: true,
    );
    final desktopPages = paginator.paginateChapterSync(
      chapterIndex: 42,
      sanitizedText: chapter,
      config: desktop2ColCfg,
      treatFirstLineAsTitle: true,
    );
    final narrowPages = paginator.paginateChapterSync(
      chapterIndex: 42,
      sanitizedText: chapter,
      config: narrowCfg,
      treatFirstLineAsTitle: true,
    );

    _assertCharacterConservation(chapter, mobilePages);
    _assertCharacterConservation(chapter, desktopPages);
    _assertCharacterConservation(chapter, narrowPages);

    // Two-column spread pairing `(P_{2k}, P_{2k+1})`
    final spreads = IncrementalTextPaginator.buildTwoColumnSpreads(desktopPages);
    expect(spreads.length, equals((desktopPages.length + 1) ~/ 2));
    for (var k = 0; k < spreads.length; k++) {
      expect(spreads[k].spreadIndex, equals(k));
      expect(spreads[k].left, same(desktopPages[2 * k]));
      if (2 * k + 1 < desktopPages.length) {
        expect(spreads[k].right, same(desktopPages[2 * k + 1]));
        expect(
          spreads[k].left.endCharOffset,
          equals(spreads[k].right!.startCharOffset),
        );
      } else {
        expect(spreads[k].right, isNull);
      }
    }

    // Round-trip anchor accuracy across font size and viewport width resizes
    for (final testPageIdx in <int>[0, 1, mobilePages.length ~/ 2, mobilePages.length - 1]) {
      final anchorOffset = mobilePages[testPageIdx].startCharOffset;

      // Resize A (mobile) -> B (desktop 2-col 22pt)
      final desktopPageIdx =
          IncrementalTextPaginator.findPageIndexForOffset(desktopPages, anchorOffset);
      final desktopSpreadIdx =
          IncrementalTextPaginator.findSpreadIndexForOffset(desktopPages, anchorOffset);
      expect(desktopPages[desktopPageIdx].containsOffset(anchorOffset), isTrue);
      final spread = spreads[desktopSpreadIdx];
      final spreadEnd = spread.right?.endCharOffset ?? spread.left.endCharOffset;
      expect(anchorOffset >= spread.left.startCharOffset, isTrue);
      expect(anchorOffset < spreadEnd, isTrue);

      // Resize B -> C (narrow 1-col 15pt)
      final narrowPageIdx =
          IncrementalTextPaginator.findPageIndexForOffset(narrowPages, anchorOffset);
      expect(narrowPages[narrowPageIdx].containsOffset(anchorOffset), isTrue);

      // Resize C -> A (back to mobile 1-col 18pt) -> exact original page & offset!
      final restoredPages = paginator.paginateChapterSync(
        chapterIndex: 42,
        sanitizedText: chapter,
        config: mobileCfg,
        treatFirstLineAsTitle: true,
      );
      final restoredIdx =
          IncrementalTextPaginator.findPageIndexForOffset(restoredPages, anchorOffset);
      expect(restoredIdx, equals(testPageIdx));
      expect(
        restoredPages[restoredIdx].startCharOffset,
        equals(mobilePages[testPageIdx].startCharOffset),
      );
      expect(
        chapter[restoredPages[restoredIdx].startCharOffset],
        equals(chapter[anchorOffset]),
      );
    }
  });

  test('Latency benchmark: first-screen < 8ms and full 5,000-char chapter < 50ms', () async {
    final chapter = _build5000CharChapter();
    final paginator = IncrementalTextPaginator(frameBudgetMicros: 4000);
    final config = PaginationConfig.fromViewport(
      viewportWidth: 400,
      viewportHeight: 760,
      columnCount: 1,
      fontSize: 18,
    );

    // 1. Cold cache (first open of session, anchor = 0)
    paginator.clearMetricsCache();
    final coldRes = await paginator.paginateIncremental(
      chapterIndex: 42,
      sanitizedText: chapter,
      config: config,
      priorityCharOffset: 0,
      treatFirstLineAsTitle: true,
    );
    _assertCharacterConservation(chapter, coldRes.allPages);

    // ignore: avoid_print
    print(
      '[PAGINATE COLD ch=5020chars offset=0] '
      'pages=${coldRes.allPages.length}, '
      'firstScreen=${(coldRes.firstScreenMicros / 1000).toStringAsFixed(2)} ms '
      '(${coldRes.firstScreen.pages.length} pages), '
      'totalCompute=${(coldRes.totalComputeMicros / 1000).toStringAsFixed(2)} ms, '
      'slices=${coldRes.timeSliceCount}, '
      'maxSlice=${(coldRes.maxSliceMicros / 1000).toStringAsFixed(2)} ms',
    );

    expect(coldRes.firstScreenMicros, lessThan(8000));
    expect(coldRes.totalComputeMicros, lessThan(50000));

    // 2. Warm cache at anchor=0, anchor=1800, anchor=4200 (anchored window)
    for (final offset in <int>[0, 1800, 4200]) {
      final res = await paginator.paginateIncremental(
        chapterIndex: 42,
        sanitizedText: chapter,
        config: config,
        priorityCharOffset: offset,
        treatFirstLineAsTitle: true,
      );
      _assertCharacterConservation(chapter, res.allPages);
      expect(
        res.firstScreen.pages[
            res.firstScreen.anchorPageIndex -
                res.firstScreen.pages.first.pageIndex]
            .containsOffset(offset),
        isTrue,
      );

      // ignore: avoid_print
      print(
        '[PAGINATE WARM ch=${chapter.length}chars offset=$offset] '
        'pages=${res.allPages.length}, '
        'firstScreen=${(res.firstScreenMicros / 1000).toStringAsFixed(2)} ms '
        '(${res.firstScreen.pages.length} pages), '
        'totalCompute=${(res.totalComputeMicros / 1000).toStringAsFixed(2)} ms, '
        'slices=${res.timeSliceCount}, '
        'maxSlice=${(res.maxSliceMicros / 1000).toStringAsFixed(2)} ms',
      );

      expect(res.firstScreenMicros, lessThan(8000));
      expect(res.totalComputeMicros, lessThan(50000));
    }

    // 3. Cold resize (font size 18 -> 22 & 2-col desktop 1100x760)
    final desktop2Col = PaginationConfig.fromViewport(
      viewportWidth: 1100,
      viewportHeight: 760,
      columnCount: 2,
      columnGap: 48,
      fontSize: 22,
    );
    final resizeRes = await paginator.paginateIncremental(
      chapterIndex: 42,
      sanitizedText: chapter,
      config: desktop2Col,
      priorityCharOffset: 1800,
      treatFirstLineAsTitle: true,
    );
    _assertCharacterConservation(chapter, resizeRes.allPages);

    // ignore: avoid_print
    print(
      '[PAGINATE RESIZE 2-COL 22pt] '
      'pages=${resizeRes.allPages.length}, '
      'firstScreen=${(resizeRes.firstScreenMicros / 1000).toStringAsFixed(2)} ms, '
      'totalCompute=${(resizeRes.totalComputeMicros / 1000).toStringAsFixed(2)} ms, '
      'slices=${resizeRes.timeSliceCount}, '
      'maxSlice=${(resizeRes.maxSliceMicros / 1000).toStringAsFixed(2)} ms',
    );

    expect(resizeRes.firstScreenMicros, lessThan(8000));
    expect(resizeRes.totalComputeMicros, lessThan(50000));

    // 4. Stress test: ~15,000-char giant chapter with deep priorityCharOffset
    final hugeChapter = '${_build5000CharChapter()}${_build5000CharChapter()}${_build5000CharChapter()}';
    final hugeRes = await paginator.paginateIncremental(
      chapterIndex: 99,
      sanitizedText: hugeChapter,
      config: config,
      priorityCharOffset: 11200,
      treatFirstLineAsTitle: true,
    );
    _assertCharacterConservation(hugeChapter, hugeRes.allPages);

    // ignore: avoid_print
    print(
      '[PAGINATE HUGE ch=${hugeChapter.length}chars offset=11200] '
      'pages=${hugeRes.allPages.length}, '
      'firstScreen=${(hugeRes.firstScreenMicros / 1000).toStringAsFixed(2)} ms '
      '(${hugeRes.firstScreen.pages.length} pages), '
      'totalCompute=${(hugeRes.totalComputeMicros / 1000).toStringAsFixed(2)} ms, '
      'slices=${hugeRes.timeSliceCount}, '
      'maxSlice=${(hugeRes.maxSliceMicros / 1000).toStringAsFixed(2)} ms',
    );
    expect(hugeRes.firstScreenMicros, lessThan(8000));

    // 5. High-vocabulary-diversity 5,000-char chapter (~1,200 distinct Hanzi)
    final diverseBuf = StringBuffer('第88章 千字文压测\n');
    var code = 0x4E00;
    while (diverseBuf.length < 5000) {
      for (var s = 0; s < 35 && diverseBuf.length < 4998; s++) {
        diverseBuf.writeCharCode(code);
        code++;
        if (code >= 0x4E00 + 1200) code = 0x4E00;
      }
      diverseBuf.write('，测试PureRead2026。\n');
    }
    final diverseChapter = diverseBuf.toString();
    paginator.clearMetricsCache();
    final diverseCold = await paginator.paginateIncremental(
      chapterIndex: 88,
      sanitizedText: diverseChapter,
      config: config,
      priorityCharOffset: 0,
      treatFirstLineAsTitle: true,
    );
    _assertCharacterConservation(diverseChapter, diverseCold.allPages);

    // ignore: avoid_print
    print(
      '[PAGINATE DIVERSE-COLD ch=${diverseChapter.length}chars ~1200uniq] '
      'pages=${diverseCold.allPages.length}, '
      'firstScreen=${(diverseCold.firstScreenMicros / 1000).toStringAsFixed(2)} ms, '
      'totalCompute=${(diverseCold.totalComputeMicros / 1000).toStringAsFixed(2)} ms, '
      'slices=${diverseCold.timeSliceCount}, '
      'maxSlice=${(diverseCold.maxSliceMicros / 1000).toStringAsFixed(2)} ms',
    );
    expect(diverseCold.firstScreenMicros, lessThan(8000));
    expect(diverseCold.totalComputeMicros, lessThan(50000));
  });
}
