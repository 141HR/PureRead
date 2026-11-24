import 'dart:isolate';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/reader_engine.dart';

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

String _stripTrailingLineBreaks(String s) {
  var end = s.length;
  while (end > 0) {
    final cu = s.codeUnitAt(end - 1);
    if (cu != 0x0A && cu != 0x0D) break;
    end--;
  }
  return s.substring(0, end);
}

void assertCharacterConservation(String chapterText, List<PageSlice> pages) {
  expect(pages, isNotEmpty);
  expect(pages.first.startCharOffset, equals(0));
  expect(pages.last.endCharOffset, equals(chapterText.length));

  final pageJoin = StringBuffer();
  final lineJoin = StringBuffer();

  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    expect(page.pageIndex, equals(i));
    if (i + 1 < pages.length) {
      expect(page.endCharOffset, equals(pages[i + 1].startCharOffset));
    }
    pageJoin.write(
      chapterText.substring(page.startCharOffset, page.endCharOffset),
    );

    if (page.lines.isNotEmpty) {
      expect(page.lines.first.startCharOffset, equals(page.startCharOffset));
      expect(page.lines.last.endCharOffset, equals(page.endCharOffset));
      for (var j = 0; j < page.lines.length; j++) {
        final line = page.lines[j];
        expect(
          line.text,
          equals(
            chapterText.substring(line.startCharOffset, line.endCharOffset),
          ),
        );
        if (j + 1 < page.lines.length) {
          expect(line.endCharOffset, equals(page.lines[j + 1].startCharOffset));
        }
        lineJoin.write(line.text);
      }
    }
  }

  expect(pageJoin.toString(), equals(chapterText));
  expect(lineJoin.toString(), equals(chapterText));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dart:ui TextPainter cannot run in a background Isolate', () async {
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

  test('TextPainterMetricsCache matches single-glyph widths', () {
    const config = PaginationConfig(
      columnWidth: 340,
      columnHeight: 600,
      fontSize: 18,
      letterSpacing: 0.0,
    );
    final cache = TextPainterMetricsCache(config);
    const sample = '汉字排版，。！？、》」《「（）Flutter2026';
    cache.warmUpSlice(sample, 0, sample.length);

    final style = TextStyle(
      fontSize: config.fontSize,
      fontWeight: TextPainterMetricsCache.resolveFontWeight(
        config.fontWeightValue,
      ),
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

  test('LayoutLine geometry contracts: x indent, y stacking, height, and charXOffsets', () {
    final paginator = IncrementalTextPaginator();
    const text = '第一段需要测试首行缩进以及垂直行偏移计算是否精确准确，'
        '并且检查换行后的次行零缩进。\n'
        '第二段继续验证段落间距累加。\n';
    const config = PaginationConfig(
      columnWidth: 260,
      columnHeight: 600,
      fontSize: 18,
      lineHeightMultiplier: 1.65,
      paragraphSpacing: 12,
      paragraphIndentChars: 2,
    );

    final pages = paginator.paginateChapterSync(
      chapterIndex: 0,
      sanitizedText: text,
      config: config,
    );
    assertCharacterConservation(text, pages);

    final lines = pages.single.lines;
    expect(lines.length, greaterThanOrEqualTo(3));

    final expectedIndent = config.paragraphIndentChars * config.fontSize;
    var expectedY = 0.0;
    for (final line in lines) {
      expect(line.x, equals(line.isParagraphStart ? expectedIndent : 0.0));
      expect(line.y, closeTo(expectedY, 1e-6));
      expect(line.height, greaterThan(0.0));

      final visible = _stripTrailingLineBreaks(line.text);
      if (visible.isNotEmpty) {
        expect(line.charXOffsets, isNotNull);
        expect(line.charXOffsets!.length, equals(visible.length));
        expect(line.charXOffsets!.first, equals(0.0));
        for (var i = 1; i < line.charXOffsets!.length; i++) {
          expect(
            line.charXOffsets![i],
            greaterThanOrEqualTo(line.charXOffsets![i - 1]),
          );
        }
      }

      expectedY += line.height;
      if (line.isParagraphEnd) {
        expectedY += config.paragraphSpacing;
      }
    }
  });

  test('0-violation Chinese punctuation prohibition matrix across widths and font sizes', () {
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
        assertCharacterConservation(edgeText, pages);

        for (final page in pages) {
          for (final line in page.lines) {
            final visible = _stripTrailingLineBreaks(line.text);
            if (visible.isEmpty) continue;
            final firstCp = visible.runes.first;
            expect(
              ChineseTypesetting.isLineStartProhibited(firstCp),
              isFalse,
              reason:
                  'Line started with prohibited "${String.fromCharCode(firstCp)}" '
                  'at width=$width fontSize=$fontSize line="$visible"',
            );
            if (!line.isParagraphEnd) {
              final lastCp = visible.runes.last;
              expect(
                ChineseTypesetting.isLineEndProhibited(lastCp),
                isFalse,
                reason:
                    'Non-terminal line ended with prohibited "${String.fromCharCode(lastCp)}" '
                    'at width=$width fontSize=$fontSize line="$visible"',
              );
            }
          }
        }
      }
    }

    // Pathological all-punctuation input must terminate without hanging and conserve 100% chars.
    final pathological = '${'，' * 60}\n${'《' * 60}\n';
    final pathPages = paginator.paginateChapterSync(
      chapterIndex: 0,
      sanitizedText: pathological,
      config: const PaginationConfig(columnWidth: 200, columnHeight: 300),
    );
    assertCharacterConservation(pathological, pathPages);
  });

  test('CJK-ASCII spacing adds 0.2 * fontSize gaps cleanly without mutating text', () {
    final paginator = IncrementalTextPaginator(enableJustification: false);
    const text = '使用Flutter框架2026版，在《PureRead》中运行v3引擎。';

    const spacedConfig = PaginationConfig(
      columnWidth: 900,
      columnHeight: 500,
      fontSize: 20,
      letterSpacing: 0.0,
      enableCjkSpacing: true,
    );
    final plainConfig = spacedConfig.copyWith(enableCjkSpacing: false);

    final spacedPages = paginator.paginateChapterSync(
      chapterIndex: 0,
      sanitizedText: text,
      config: spacedConfig,
    );
    final plainPages = paginator.paginateChapterSync(
      chapterIndex: 0,
      sanitizedText: text,
      config: plainConfig,
    );
    assertCharacterConservation(text, spacedPages);
    assertCharacterConservation(text, plainPages);

    final spacedLine = spacedPages.single.lines.single;
    final plainLine = plainPages.single.lines.single;
    const expectedSingleGap = 20.0 * kCjkAsciiSpacingRatio;

    // 6 CJK<->ASCII boundaries: 用->F, r->框, 架->2, 6->版, 行->v, 3->引
    // Note: 《PureRead》 has full-width punctuation around ASCII so NO extra gap there.
    expect(
      spacedLine.width - plainLine.width,
      closeTo(6 * expectedSingleGap, 0.05),
    );

    final idxF = text.indexOf('F');
    final idxP = text.indexOf('P');
    final spacedGapBeforeF =
        spacedLine.charXOffsets![idxF] - spacedLine.charXOffsets![idxF - 1];
    final plainGapBeforeF =
        plainLine.charXOffsets![idxF] - plainLine.charXOffsets![idxF - 1];
    expect(spacedGapBeforeF - plainGapBeforeF, closeTo(expectedSingleGap, 0.05));

    final spacedGapBeforeP =
        spacedLine.charXOffsets![idxP] - spacedLine.charXOffsets![idxP - 1];
    final plainGapBeforeP =
        plainLine.charXOffsets![idxP] - plainLine.charXOffsets![idxP - 1];
    expect(spacedGapBeforeP - plainGapBeforeP, closeTo(0.0, 0.05));
  });

  test('100% character conservation across single/two-column, varied sizes, CRLF & surrogates', () {
    final paginator = IncrementalTextPaginator();
    const baseCfg = PaginationConfig(columnWidth: 340, columnHeight: 580);

    // Empty chapter
    assertCharacterConservation(
      '',
      paginator.paginateChapterSync(
        chapterIndex: 0,
        sanitizedText: '',
        config: baseCfg,
      ),
    );

    // CRLF, multiple blank lines, ideographic indent & non-BMP surrogates
    const tricky =
        '\r\n　　第一段含生僻字𠮷与表情😀，换行测试。\r\n\r\n\r\n'
        '第二段继续测试，包含《引号》和数字12345。\r\n';
    final trickyPages = paginator.paginateChapterSync(
      chapterIndex: 1,
      sanitizedText: tricky,
      config: baseCfg,
    );
    assertCharacterConservation(tricky, trickyPages);

    // Ensure surrogate pair entries in charXOffsets match each other.
    final jiIdx = tricky.indexOf('𠮷');
    final firstLine = trickyPages.first.lines
        .firstWhere((l) => jiIdx >= l.startCharOffset && jiIdx < l.endCharOffset);
    final relJi = jiIdx - firstLine.startCharOffset;
    expect(
      firstLine.charXOffsets![relJi],
      equals(firstLine.charXOffsets![relJi + 1]),
    );

    // Varied widths, font sizes, and 1-col / 2-col configurations
    final chapter5k = _build5000CharChapter();
    for (final columnCount in <int>[1, 2]) {
      for (final colWidth in <double>[260, 360, 480]) {
        for (final fontSize in <double>[15, 18, 22]) {
          final cfg = PaginationConfig(
            columnWidth: colWidth,
            columnHeight: 620,
            columnCount: columnCount,
            fontSize: fontSize,
          );
          final pages = paginator.paginateChapterSync(
            chapterIndex: 42,
            sanitizedText: chapter5k,
            config: cfg,
          );
          assertCharacterConservation(chapter5k, pages);
        }
      }
    }
  });

  test('IncrementalTextPaginator implements ReaderPaginator and emits first-screen before completion', () async {
    final ReaderPaginator paginatorInterface = IncrementalTextPaginator(
      frameBudgetMicros: 4000,
    );
    final incremental = paginatorInterface as IncrementalTextPaginator;
    final chapter = '${_build5000CharChapter()}${_build5000CharChapter()}';

    const config = PaginationConfig(
      columnWidth: 360,
      columnHeight: 700,
      fontSize: 18,
    );

    // Works through pure domain ReaderPaginator contract
    final viaInterface = await paginatorInterface.paginateChapter(
      chapterIndex: 7,
      sanitizedText: chapter,
      config: config,
      priorityCharOffset: 4500,
    );
    assertCharacterConservation(chapter, viaInterface);

    // Emits immediate first-screen hook for deep priorityCharOffset (> 1200)
    FirstScreenResult? emittedFirstScreen;
    final res = await incremental.paginateChapterIncremental(
      chapterIndex: 7,
      sanitizedText: chapter,
      config: config,
      priorityCharOffset: 4500,
      onFirstScreen: (fs) {
        emittedFirstScreen = fs;
      },
    );

    expect(emittedFirstScreen, isNotNull);
    expect(emittedFirstScreen!.isApproximateWindow, isTrue);
    final anchorLocalIdx = emittedFirstScreen!.anchorPageIndex -
        emittedFirstScreen!.pages.first.pageIndex;
    expect(
      emittedFirstScreen!.pages[anchorLocalIdx].containsOffset(4500),
      isTrue,
    );
    assertCharacterConservation(chapter, res.allPages);
    expect(res.firstScreenMicros, lessThan(50000));
    expect(res.totalComputeMicros, lessThan(250000));

    // CancellationToken aborts cleanly
    final token = CancellationToken()..cancel();
    await expectLater(
      () => incremental.paginateChapterIncremental(
        chapterIndex: 7,
        sanitizedText: chapter,
        config: config,
        cancelToken: token,
      ),
      throwsA(isA<CancelledFailure>()),
    );
  });
}
