import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'chinese_typesetting.dart';
import 'pagination_models.dart';

/// Root-isolate [TextPainter] width cache and line painter builder.
///
/// Honors Flutter's `dart:ui` root-isolate constraint: all [TextPainter]
/// measurements execute strictly on the UI/root isolate, batched per paragraph
/// and cached across pages/chapters for a given typography configuration.
class TextPainterMetricsCache {
  TextPainterMetricsCache(this.config)
      : _baseStyle = TextStyle(
          fontFamily: config.fontFamily,
          fontSize: config.fontSize,
          fontWeight: config.fontWeight,
          height: config.lineHeightMultiplier,
          letterSpacing: 0.0,
        ),
        _probePainter = TextPainter(textDirection: TextDirection.ltr) {
    _measureLineMetrics();
  }

  final PaginationConfig config;
  final TextStyle _baseStyle;
  final TextPainter _probePainter;

  final Map<int, double> _runeWidths = <int, double>{};
  final Map<String, double> _tokenWidths = <String, double>{};

  late final double lineHeight;
  late final double baseline;
  double? _uniformCjkIdeographWidth;

  void _measureLineMetrics() {
    _probePainter.text = TextSpan(text: '汉A', style: _baseStyle);
    _probePainter.layout();
    lineHeight = _probePainter.height;
    baseline = _probePainter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );

    // Empirically probe 10 structurally varied CJK ideographs via TextPainter.
    // Nearly all Chinese reading fonts (Noto CJK, PingFang, YaHei, KaiTi,
    // WenKai, Ahem) assign uniform em-advance to U+4E00..U+9FFF; when verified,
    // avoid thousands of redundant SkParagraph FFI calls on cold chapter open.
    const probeChars = '一国鑫田口日月木水火';
    _probePainter.text = TextSpan(text: probeChars, style: _baseStyle);
    _probePainter.layout();
    var minW = double.infinity;
    var maxW = 0.0;
    var prevDx = 0.0;
    for (var i = 1; i <= probeChars.length; i++) {
      final dx = _probePainter
          .getOffsetForCaret(TextPosition(offset: i), ui.Rect.zero)
          .dx;
      final w = dx - prevDx;
      if (w < minW) minW = w;
      if (w > maxW) maxW = w;
      prevDx = dx;
    }
    if (minW > 0 && (maxW - minW) <= 0.02) {
      _uniformCjkIdeographWidth = (minW + maxW) * 0.5;
    }
  }

  /// Pre-populates unseen rune widths in [text] slice `[start, end)` using a
  /// single batched [TextPainter.layout] call so per-character measurement never
  /// incurs N separate SkParagraph layout allocations.
  void warmUpSlice(String text, int start, int end) {
    StringBuffer? unseenBuf;
    final unseenRunes = <int>[];
    final seenInBatch = <int>{};
    final uniformCjk = _uniformCjkIdeographWidth;

    var i = start;
    while (i < end) {
      final cu = text.codeUnitAt(i);
      var cp = cu;
      var step = 1;
      if (ChineseTypesetting.isHighSurrogate(cu) && i + 1 < end) {
        final low = text.codeUnitAt(i + 1);
        if (ChineseTypesetting.isLowSurrogate(low)) {
          cp = ChineseTypesetting.combineSurrogates(cu, low);
          step = 2;
        }
      }
      if (uniformCjk != null && cp >= 0x4E00 && cp <= 0x9FFF) {
        i += step;
        continue;
      }
      if (!_runeWidths.containsKey(cp) && seenInBatch.add(cp)) {
        if (cp == 0x20 || cp == 0x09 || cp == 0x3000) {
          _runeWidths[cp] = _measureSpace(cp);
        } else {
          unseenBuf ??= StringBuffer();
          unseenRunes.add(cp);
          unseenBuf.writeCharCode(cp);
        }
      }
      i += step;
    }

    if (unseenBuf == null || unseenRunes.isEmpty) return;

    final batchStr = unseenBuf.toString();
    _probePainter.text = TextSpan(text: batchStr, style: _baseStyle);
    _probePainter.layout();

    var utf16Pos = 0;
    var prevDx = 0.0;
    for (final cp in unseenRunes) {
      final cuLen = cp > 0xFFFF ? 2 : 1;
      utf16Pos += cuLen;
      final dx = _probePainter
          .getOffsetForCaret(TextPosition(offset: utf16Pos), ui.Rect.zero)
          .dx;
      final advance = dx - prevDx;
      _runeWidths[cp] = advance > 0 ? advance : config.fontSize;
      prevDx = dx;
    }
  }

  double _measureSpace(int cp) {
    final space = String.fromCharCode(cp);
    _probePainter.text = TextSpan(text: 'M${space}M', style: _baseStyle);
    _probePainter.layout();
    final withSpace = _probePainter.width;
    _probePainter.text = TextSpan(text: 'MM', style: _baseStyle);
    _probePainter.layout();
    final withoutSpace = _probePainter.width;
    final diff = withSpace - withoutSpace;
    return diff > 0 ? diff : config.fontSize * 0.35;
  }

  double runeWidth(int codePoint) {
    final uniformCjk = _uniformCjkIdeographWidth;
    if (uniformCjk != null && codePoint >= 0x4E00 && codePoint <= 0x9FFF) {
      return uniformCjk;
    }
    final cached = _runeWidths[codePoint];
    if (cached != null) return cached;

    if (codePoint == 0x20 || codePoint == 0x09 || codePoint == 0x3000) {
      final w = _measureSpace(codePoint);
      _runeWidths[codePoint] = w;
      return w;
    }

    final str = String.fromCharCode(codePoint);
    _probePainter.text = TextSpan(text: str, style: _baseStyle);
    _probePainter.layout();
    final w = _probePainter.width;
    _runeWidths[codePoint] = w;
    return w;
  }

  /// Measures a contiguous ASCII word/token via [TextPainter] to preserve
  /// proportional font kerning.
  double tokenWidth(String token) {
    final cached = _tokenWidths[token];
    if (cached != null) return cached;

    if (token.length == 1) {
      final w = runeWidth(token.codeUnitAt(0));
      _tokenWidths[token] = w;
      return w;
    }

    _probePainter.text = TextSpan(text: token, style: _baseStyle);
    _probePainter.layout();
    final w = _probePainter.width + (token.length - 1) * config.letterSpacing;
    _tokenWidths[token] = w;
    return w;
  }

  /// Builds a ready-to-paint [TextPainter] for a single [LayoutLine] honoring
  /// CJK-ASCII spacing and full justification without modifying chapter text.
  TextPainter buildLinePainter(
    LayoutLine line,
    String chapterText, {
    required Color textColor,
  }) {
    final text = line.renderText(chapterText);
    final baseStyle = TextStyle(
      fontFamily: config.fontFamily,
      fontSize: config.fontSize,
      fontWeight: line.isTitle ? FontWeight.w700 : config.fontWeight,
      height: config.lineHeightMultiplier,
      letterSpacing: config.letterSpacing + line.extraCharSpacing,
      color: textColor,
    );

    if (line.cjkGapOffsets.isEmpty) {
      return TextPainter(
        text: TextSpan(text: text, style: baseStyle),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    // Split into runs so each boundary char carries extra CJK<->ASCII gap via
    // letterSpacing while `toPlainText()` remains identical to `text`.
    final spans = <InlineSpan>[];
    var cursor = line.startCharOffset;
    for (final gapAbsOffset in line.cjkGapOffsets) {
      if (gapAbsOffset < cursor || gapAbsOffset >= line.renderEndCharOffset) {
        continue;
      }
      if (gapAbsOffset > cursor) {
        spans.add(
          TextSpan(
            text: chapterText.substring(cursor, gapAbsOffset),
            style: baseStyle,
          ),
        );
      }
      final charLen = ChineseTypesetting.isHighSurrogate(
                chapterText.codeUnitAt(gapAbsOffset),
              ) &&
              gapAbsOffset + 1 < line.renderEndCharOffset
          ? 2
          : 1;
      spans.add(
        TextSpan(
          text: chapterText.substring(gapAbsOffset, gapAbsOffset + charLen),
          style: baseStyle.copyWith(
            letterSpacing:
                config.letterSpacing + line.extraCharSpacing + config.cjkAsciiGap,
          ),
        ),
      );
      cursor = gapAbsOffset + charLen;
    }
    if (cursor < line.renderEndCharOffset) {
      spans.add(
        TextSpan(
          text: chapterText.substring(cursor, line.renderEndCharOffset),
          style: baseStyle,
        ),
      );
    }

    return TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
    )..layout();
  }
}

class _ParagraphRange {
  const _ParagraphRange({
    required this.start,
    required this.renderEnd,
    required this.end,
    required this.isTitle,
  });

  final int start;
  final int renderEnd;
  final int end;
  final bool isTitle;
}

/// Incremental, root-isolate `TextPainter`-backed paginator supporting:
/// - Chinese line-start/line-end punctuation prohibition (避头尾禁则)
/// - CJK-ASCII micro-spacing without altering character offsets
/// - Single-column & two-column logical page reuse `(P_{2k}, P_{2k+1})`
/// - Immediate first-screen priority layout (< 8 ms) + <= 4 ms frame slicing
class IncrementalTextPaginator {
  IncrementalTextPaginator({this.frameBudgetMicros = 4000});

  final int frameBudgetMicros;
  final Map<String, TextPainterMetricsCache> _cacheByConfig =
      <String, TextPainterMetricsCache>{};

  TextPainterMetricsCache metricsFor(PaginationConfig config) {
    return _cacheByConfig.putIfAbsent(
      config.typographyKey,
      () => TextPainterMetricsCache(config),
    );
  }

  /// Clears cached font metrics (useful when measuring cold vs warm latency).
  void clearMetricsCache() => _cacheByConfig.clear();

  /// Runs incremental pagination:
  /// 1. Synchronously computes the first-screen pages around [priorityCharOffset]
  ///    (target < 8 ms) and invokes [onFirstScreen] immediately if provided.
  /// 2. Completes the full chapter in <= [frameBudgetMicros] slices (target < 50 ms
  ///    compute total for ~5,000 CJK chars), guaranteeing 100% character conservation.
  Future<IncrementalPaginationResult> paginateIncremental({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    int priorityCharOffset = 0,
    bool treatFirstLineAsTitle = false,
    void Function(FirstScreenResult firstScreen)? onFirstScreen,
    bool yieldBetweenSlices = true,
  }) async {
    final metrics = metricsFor(config);
    final totalSw = Stopwatch()..start();

    if (sanitizedText.isEmpty) {
      final emptyPage = PageSlice(
        chapterIndex: chapterIndex,
        pageIndex: 0,
        startCharOffset: 0,
        endCharOffset: 0,
        lines: const <LayoutLine>[],
      );
      totalSw.stop();
      final firstScreen = FirstScreenResult(
        anchorPageIndex: 0,
        pages: <PageSlice>[emptyPage],
        elapsedMicros: totalSw.elapsedMicroseconds,
      );
      onFirstScreen?.call(firstScreen);
      return IncrementalPaginationResult(
        firstScreen: firstScreen,
        allPages: <PageSlice>[emptyPage],
        firstScreenMicros: totalSw.elapsedMicroseconds,
        totalComputeMicros: totalSw.elapsedMicroseconds,
        maxSliceMicros: totalSw.elapsedMicroseconds,
        timeSliceCount: 1,
      );
    }

    final clampedAnchor = priorityCharOffset.clamp(0, sanitizedText.length - 1);
    final paragraphs = _splitParagraphs(
      sanitizedText,
      treatFirstLineAsTitle: treatFirstLineAsTitle,
    );

    // Phase 1: Fast First-Screen computation (anchor + 2-3 adjacent pages).
    final firstScreenSw = Stopwatch()..start();
    final FirstScreenResult firstScreen;

    // When anchor is within the first ~1,200 chars, computing straight from 0
    // through anchor + 2-3 pages finishes well inside < 8 ms AND yields exact
    // canonical pages directly. For offsets deeper in the chapter, start from
    // a local paragraph window ~650 chars before `clampedAnchor`.
    final useAnchoredWindow = clampedAnchor > 1200;
    final List<PageSlice> canonicalPages = <PageSlice>[];
    var nextParagraphIdx = 0;
    var currentLines = <LayoutLine>[];
    var currentY = 0.0;
    var currentPageStart = 0;

    if (useAnchoredWindow) {
      firstScreen = _layoutAnchoredWindow(
        chapterIndex: chapterIndex,
        text: sanitizedText,
        paragraphs: paragraphs,
        anchorOffset: clampedAnchor,
        config: config,
        metrics: metrics,
      );
      firstScreenSw.stop();
      onFirstScreen?.call(firstScreen);
    } else {
      final minPagesWanted = config.columnCount == 2 ? 4 : 3;
      int? anchorPageIdx;

      while (nextParagraphIdx < paragraphs.length) {
        final p = paragraphs[nextParagraphIdx++];
        final pLines = _breakParagraph(p, sanitizedText, config, metrics);
        for (final line in pLines) {
          if (currentLines.isNotEmpty &&
              currentY + line.height > config.columnHeight + 0.01) {
            final page = PageSlice(
              chapterIndex: chapterIndex,
              pageIndex: canonicalPages.length,
              startCharOffset: currentPageStart,
              endCharOffset: currentLines.last.endCharOffset,
              lines: currentLines,
            );
            canonicalPages.add(page);
            if (anchorPageIdx == null && page.containsOffset(clampedAnchor)) {
              anchorPageIdx = page.pageIndex;
            }
            currentLines = <LayoutLine>[];
            currentY = 0.0;
            currentPageStart = line.startCharOffset;
          }

          currentLines.add(_positionLine(line, currentY));
          currentY += line.height;
          if (line.isParagraphEnd) {
            currentY += config.paragraphSpacing;
          }
        }

        if (anchorPageIdx != null &&
            canonicalPages.length >= anchorPageIdx + minPagesWanted) {
          break;
        }
      }

      // If anchor fell on the still-open last page of the chapter, close it now.
      if (nextParagraphIdx >= paragraphs.length && currentLines.isNotEmpty) {
        final page = PageSlice(
          chapterIndex: chapterIndex,
          pageIndex: canonicalPages.length,
          startCharOffset: currentPageStart,
          endCharOffset: sanitizedText.length,
          lines: currentLines,
        );
        canonicalPages.add(page);
        if (anchorPageIdx == null && page.containsOffset(clampedAnchor)) {
          anchorPageIdx = page.pageIndex;
        }
        currentLines = <LayoutLine>[];
      }

      firstScreenSw.stop();
      final resolvedAnchorIdx = anchorPageIdx ??
          findPageIndexForOffset(canonicalPages, clampedAnchor);
      final sliceStart = (resolvedAnchorIdx - 1).clamp(0, canonicalPages.length);
      final sliceEnd = (resolvedAnchorIdx + 3).clamp(0, canonicalPages.length);
      firstScreen = FirstScreenResult(
        anchorPageIndex: resolvedAnchorIdx,
        pages: canonicalPages.sublist(sliceStart, sliceEnd),
        elapsedMicros: firstScreenSw.elapsedMicroseconds,
      );
      onFirstScreen?.call(firstScreen);
    }

    // Phase 2: Incremental time-sliced completion of the full canonical chapter.
    var computeMicros = firstScreenSw.elapsedMicroseconds;
    var maxSliceMicros = firstScreenSw.elapsedMicroseconds;
    var sliceCount = 1;

    while (nextParagraphIdx < paragraphs.length) {
      if (yieldBetweenSlices) {
        await Future<void>.delayed(Duration.zero);
      }
      final sliceSw = Stopwatch()..start();
      sliceCount++;

      while (nextParagraphIdx < paragraphs.length) {
        final p = paragraphs[nextParagraphIdx++];
        final pLines = _breakParagraph(p, sanitizedText, config, metrics);
        for (final line in pLines) {
          if (currentLines.isNotEmpty &&
              currentY + line.height > config.columnHeight + 0.01) {
            canonicalPages.add(
              PageSlice(
                chapterIndex: chapterIndex,
                pageIndex: canonicalPages.length,
                startCharOffset: currentPageStart,
                endCharOffset: currentLines.last.endCharOffset,
                lines: currentLines,
              ),
            );
            currentLines = <LayoutLine>[];
            currentY = 0.0;
            currentPageStart = line.startCharOffset;
          }
          currentLines.add(_positionLine(line, currentY));
          currentY += line.height;
          if (line.isParagraphEnd) {
            currentY += config.paragraphSpacing;
          }
        }

        if (sliceSw.elapsedMicroseconds >= frameBudgetMicros &&
            nextParagraphIdx < paragraphs.length) {
          break;
        }
      }

      if (nextParagraphIdx >= paragraphs.length && currentLines.isNotEmpty) {
        canonicalPages.add(
          PageSlice(
            chapterIndex: chapterIndex,
            pageIndex: canonicalPages.length,
            startCharOffset: currentPageStart,
            endCharOffset: sanitizedText.length,
            lines: currentLines,
          ),
        );
        currentLines = <LayoutLine>[];
      }

      sliceSw.stop();
      final elapsed = sliceSw.elapsedMicroseconds;
      computeMicros += elapsed;
      if (elapsed > maxSliceMicros) maxSliceMicros = elapsed;
    }

    totalSw.stop();

    return IncrementalPaginationResult(
      firstScreen: firstScreen,
      allPages: canonicalPages,
      firstScreenMicros: firstScreenSw.elapsedMicroseconds,
      totalComputeMicros: computeMicros,
      maxSliceMicros: maxSliceMicros,
      timeSliceCount: sliceCount,
    );
  }

  /// Synchronous full-chapter pagination (convenient for resize benchmarks &
  /// unit verification).
  List<PageSlice> paginateChapterSync({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    bool treatFirstLineAsTitle = false,
  }) {
    if (sanitizedText.isEmpty) {
      return <PageSlice>[
        PageSlice(
          chapterIndex: chapterIndex,
          pageIndex: 0,
          startCharOffset: 0,
          endCharOffset: 0,
          lines: const <LayoutLine>[],
        ),
      ];
    }

    final metrics = metricsFor(config);
    final paragraphs = _splitParagraphs(
      sanitizedText,
      treatFirstLineAsTitle: treatFirstLineAsTitle,
    );

    final pages = <PageSlice>[];
    var currentLines = <LayoutLine>[];
    var currentY = 0.0;
    var currentPageStart = 0;

    for (final p in paragraphs) {
      final pLines = _breakParagraph(p, sanitizedText, config, metrics);
      for (final line in pLines) {
        if (currentLines.isNotEmpty &&
            currentY + line.height > config.columnHeight + 0.01) {
          pages.add(
            PageSlice(
              chapterIndex: chapterIndex,
              pageIndex: pages.length,
              startCharOffset: currentPageStart,
              endCharOffset: currentLines.last.endCharOffset,
              lines: currentLines,
            ),
          );
          currentLines = <LayoutLine>[];
          currentY = 0.0;
          currentPageStart = line.startCharOffset;
        }
        currentLines.add(_positionLine(line, currentY));
        currentY += line.height;
        if (line.isParagraphEnd) {
          currentY += config.paragraphSpacing;
        }
      }
    }

    if (currentLines.isNotEmpty) {
      pages.add(
        PageSlice(
          chapterIndex: chapterIndex,
          pageIndex: pages.length,
          startCharOffset: currentPageStart,
          endCharOffset: sanitizedText.length,
          lines: currentLines,
        ),
      );
    }

    return pages;
  }

  /// Binary-searches the logical page index containing [charOffset].
  static int findPageIndexForOffset(List<PageSlice> pages, int charOffset) {
    if (pages.isEmpty) return 0;
    if (charOffset <= pages.first.startCharOffset) return 0;
    if (charOffset >= pages.last.endCharOffset) return pages.length - 1;

    var low = 0;
    var high = pages.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final page = pages[mid];
      if (charOffset < page.startCharOffset) {
        high = mid - 1;
      } else if (charOffset >= page.endCharOffset &&
          page.startCharOffset != page.endCharOffset) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return low.clamp(0, pages.length - 1);
  }

  /// Groups linear logical pages `[P0, P1, ..., Pn]` into two-column desktop
  /// spreads `(P_{2k}, P_{2k+1})`.
  static List<TwoColumnSpread> buildTwoColumnSpreads(List<PageSlice> pages) {
    final spreads = <TwoColumnSpread>[];
    for (var i = 0; i < pages.length; i += 2) {
      spreads.add(
        TwoColumnSpread(
          spreadIndex: i >> 1,
          left: pages[i],
          right: i + 1 < pages.length ? pages[i + 1] : null,
        ),
      );
    }
    return spreads;
  }

  /// Maps a [charOffset] to its spread index `k` in two-column mode.
  static int findSpreadIndexForOffset(List<PageSlice> pages, int charOffset) {
    return findPageIndexForOffset(pages, charOffset) >> 1;
  }

  FirstScreenResult _layoutAnchoredWindow({
    required int chapterIndex,
    required String text,
    required List<_ParagraphRange> paragraphs,
    required int anchorOffset,
    required PaginationConfig config,
    required TextPainterMetricsCache metrics,
  }) {
    final sw = Stopwatch()..start();

    // Locate paragraph containing anchorOffset.
    var pIdx = 0;
    for (var i = 0; i < paragraphs.length; i++) {
      if (anchorOffset >= paragraphs[i].start &&
          anchorOffset < paragraphs[i].end) {
        pIdx = i;
        break;
      }
    }

    // Step backward ~650 chars so we build ~1 page before anchor + 2-3 after.
    var startParaIdx = pIdx;
    var charsBack = 0;
    while (startParaIdx > 0 && charsBack < 650) {
      startParaIdx--;
      charsBack += paragraphs[startParaIdx].end - paragraphs[startParaIdx].start;
    }

    final windowPages = <PageSlice>[];
    var currentLines = <LayoutLine>[];
    var currentY = 0.0;
    var pageStart = paragraphs[startParaIdx].start;
    int? anchorPageIdx;
    final minTrailingPages = config.columnCount == 2 ? 3 : 2;

    for (var i = startParaIdx; i < paragraphs.length; i++) {
      final p = paragraphs[i];
      final pLines = _breakParagraph(p, text, config, metrics);
      for (final line in pLines) {
        if (currentLines.isNotEmpty &&
            currentY + line.height > config.columnHeight + 0.01) {
          final page = PageSlice(
            chapterIndex: chapterIndex,
            pageIndex: windowPages.length,
            startCharOffset: pageStart,
            endCharOffset: currentLines.last.endCharOffset,
            lines: currentLines,
          );
          windowPages.add(page);
          if (anchorPageIdx == null && page.containsOffset(anchorOffset)) {
            anchorPageIdx = page.pageIndex;
          }
          currentLines = <LayoutLine>[];
          currentY = 0.0;
          pageStart = line.startCharOffset;
        }

        currentLines.add(_positionLine(line, currentY));
        currentY += line.height;
        if (line.isParagraphEnd) {
          currentY += config.paragraphSpacing;
        }
      }

      if (anchorPageIdx != null &&
          windowPages.length >= anchorPageIdx + minTrailingPages + 1) {
        break;
      }
    }

    if (currentLines.isNotEmpty &&
        (anchorPageIdx == null ||
            windowPages.length < anchorPageIdx + minTrailingPages + 1)) {
      final page = PageSlice(
        chapterIndex: chapterIndex,
        pageIndex: windowPages.length,
        startCharOffset: pageStart,
        endCharOffset: currentLines.last.endCharOffset,
        lines: currentLines,
      );
      windowPages.add(page);
      if (anchorPageIdx == null && page.containsOffset(anchorOffset)) {
        anchorPageIdx = page.pageIndex;
      }
    }

    sw.stop();
    final resolved = anchorPageIdx ??
        findPageIndexForOffset(windowPages, anchorOffset);
    final sliceStart = (resolved - 1).clamp(0, windowPages.length);
    final sliceEnd = (resolved + 3).clamp(0, windowPages.length);
    return FirstScreenResult(
      anchorPageIndex: resolved,
      pages: windowPages.sublist(sliceStart, sliceEnd),
      elapsedMicros: sw.elapsedMicroseconds,
    );
  }

  List<_ParagraphRange> _splitParagraphs(
    String text, {
    required bool treatFirstLineAsTitle,
  }) {
    final result = <_ParagraphRange>[];
    final len = text.length;
    var i = 0;

    while (i < len) {
      final lineStart = i;
      while (i < len && text.codeUnitAt(i) != 0x0A) {
        i++;
      }
      var renderEnd = i;
      if (renderEnd > lineStart && text.codeUnitAt(renderEnd - 1) == 0x0D) {
        renderEnd--;
      }
      if (i < len && text.codeUnitAt(i) == 0x0A) {
        i++;
      }

      // Collapse blank newline runs onto the preceding non-empty paragraph so
      // page tops never display awkward orphan blank lines while conserving 100%
      // of characters.
      if (renderEnd == lineStart && result.isNotEmpty) {
        final prev = result.removeLast();
        result.add(
          _ParagraphRange(
            start: prev.start,
            renderEnd: prev.renderEnd,
            end: i,
            isTitle: prev.isTitle,
          ),
        );
      } else {
        result.add(
          _ParagraphRange(
            start: lineStart,
            renderEnd: renderEnd,
            end: i,
            isTitle: treatFirstLineAsTitle && result.isEmpty && renderEnd > lineStart,
          ),
        );
      }
    }

    return result;
  }

  List<LayoutLine> _breakParagraph(
    _ParagraphRange p,
    String text,
    PaginationConfig config,
    TextPainterMetricsCache metrics,
  ) {
    if (p.start == p.renderEnd) {
      return <LayoutLine>[
        LayoutLine(
          startCharOffset: p.start,
          renderEndCharOffset: p.renderEnd,
          endCharOffset: p.end,
          dx: 0,
          dy: 0,
          width: 0,
          height: metrics.lineHeight,
          baseline: metrics.baseline,
          extraCharSpacing: 0,
          isParagraphStart: true,
          isParagraphEnd: true,
          isTitle: p.isTitle,
          cjkGapOffsets: const <int>[],
        ),
      ];
    }

    metrics.warmUpSlice(text, p.start, p.renderEnd);
    final lineMetrics = p.isTitle && config.fontWeightValue != 700
        ? metricsFor(config.copyWith(fontWeightValue: 700))
        : metrics;
    if (!identical(lineMetrics, metrics)) {
      lineMetrics.warmUpSlice(text, p.start, p.renderEnd);
    }

    final lines = <LayoutLine>[];
    final startsWithFullIndent = text.codeUnitAt(p.start) == 0x3000;
    final firstLineIndent =
        (!p.isTitle && !startsWithFullIndent && config.paragraphIndentChars > 0)
            ? config.paragraphIndentChars * config.fontSize
            : 0.0;

    var lineStart = p.start;
    while (lineStart < p.renderEnd) {
      final isFirstLine = lineStart == p.start;
      final dx = isFirstLine ? firstLineIndent : 0.0;
      final maxLineWidth =
          (config.columnWidth - dx).clamp(config.fontSize, config.columnWidth);

      final breakResult = _fitSingleLine(
        text: text,
        start: lineStart,
        renderEnd: p.renderEnd,
        maxWidth: maxLineWidth,
        config: config,
        metrics: lineMetrics,
      );

      var lineRenderEnd = breakResult.endOffset;
      var lineWidth = breakResult.width;
      var gapOffsets = breakResult.cjkGapOffsets;
      var codePointCount = breakResult.codePointCount;

      // Enforce Chinese punctuation prohibition (避头尾禁则) when wrapping.
      if (config.enablePunctuationHanging && lineRenderEnd < p.renderEnd) {
        final adjusted = _applyKinsokuRules(
          text: text,
          lineStart: lineStart,
          candidateEnd: lineRenderEnd,
          paragraphRenderEnd: p.renderEnd,
        );
        if (adjusted != lineRenderEnd) {
          lineRenderEnd = adjusted;
          final remeasured = _measureExactLine(
            text: text,
            start: lineStart,
            end: lineRenderEnd,
            config: config,
            metrics: lineMetrics,
          );
          lineWidth = remeasured.width;
          gapOffsets = remeasured.cjkGapOffsets;
          codePointCount = remeasured.codePointCount;
        }
      }

      final isLastLine = lineRenderEnd >= p.renderEnd;
      var extraCharSpacing = 0.0;
      if (config.enableJustification &&
          !p.isTitle &&
          !isLastLine &&
          codePointCount > 1) {
        final slack = maxLineWidth - lineWidth;
        if (slack > 0.25 && slack <= config.fontSize * 3.0) {
          extraCharSpacing = slack / (codePointCount - 1);
        }
      }

      lines.add(
        LayoutLine(
          startCharOffset: lineStart,
          renderEndCharOffset: lineRenderEnd,
          endCharOffset: isLastLine ? p.end : lineRenderEnd,
          dx: dx,
          dy: 0,
          width: lineWidth,
          height: lineMetrics.lineHeight,
          baseline: lineMetrics.baseline,
          extraCharSpacing: extraCharSpacing,
          isParagraphStart: isFirstLine,
          isParagraphEnd: isLastLine,
          isTitle: p.isTitle,
          cjkGapOffsets: gapOffsets,
        ),
      );

      lineStart = lineRenderEnd;
    }

    return lines;
  }

  ({int endOffset, double width, List<int> cjkGapOffsets, int codePointCount})
      _fitSingleLine({
    required String text,
    required int start,
    required int renderEnd,
    required double maxWidth,
    required PaginationConfig config,
    required TextPainterMetricsCache metrics,
  }) {
    var pos = start;
    var width = 0.0;
    var prevRune = -1;
    var prevPos = -1;
    var cpCount = 0;
    final gaps = <int>[];
    final cjkGap = config.cjkAsciiGap;

    while (pos < renderEnd) {
      final cu = text.codeUnitAt(pos);

      // Step whole ASCII alphanumeric tokens as a unit unless a single token
      // exceeds the entire line width.
      if (ChineseTypesetting.isAsciiAlphaNum(cu)) {
        var tokEnd = pos + 1;
        while (tokEnd < renderEnd &&
            ChineseTypesetting.isAsciiTokenContinuation(
              text.codeUnitAt(tokEnd),
            )) {
          tokEnd++;
        }
        // Avoid trailing `.` or `-` glued onto token if followed by CJK/space
        while (tokEnd > pos + 1 &&
            !ChineseTypesetting.isAsciiAlphaNum(text.codeUnitAt(tokEnd - 1))) {
          tokEnd--;
        }

        final tokenStr = text.substring(pos, tokEnd);
        final tokWidth = metrics.tokenWidth(tokenStr);
        final leadLs = pos > start ? config.letterSpacing : 0.0;
        final leadCjkGap = (cjkGap > 0 &&
                prevRune != -1 &&
                ChineseTypesetting.needsCjkAsciiGap(prevRune, cu))
            ? cjkGap
            : 0.0;

        if (width + leadLs + leadCjkGap + tokWidth <= maxWidth + 0.01) {
          if (leadCjkGap > 0) gaps.add(prevPos);
          width += leadLs + leadCjkGap + tokWidth;
          cpCount += tokEnd - pos;
          prevPos = tokEnd - 1;
          prevRune = text.codeUnitAt(prevPos);
          pos = tokEnd;
          continue;
        }

        // If this single ASCII token is wider than an empty line, split char-by-char.
        if (pos == start) {
          return _fitCharByCharFallback(
            text: text,
            start: start,
            renderEnd: renderEnd,
            maxWidth: maxWidth,
            config: config,
            metrics: metrics,
          );
        }
        break;
      }

      // Single Unicode code point (1 or 2 UTF-16 code units).
      var cp = cu;
      var step = 1;
      if (ChineseTypesetting.isHighSurrogate(cu) && pos + 1 < renderEnd) {
        final low = text.codeUnitAt(pos + 1);
        if (ChineseTypesetting.isLowSurrogate(low)) {
          cp = ChineseTypesetting.combineSurrogates(cu, low);
          step = 2;
        }
      }

      final glyphWidth = metrics.runeWidth(cp);
      final leadLs = pos > start ? config.letterSpacing : 0.0;
      final leadCjkGap = (cjkGap > 0 &&
              prevRune != -1 &&
              ChineseTypesetting.needsCjkAsciiGap(prevRune, cp))
          ? cjkGap
          : 0.0;

      if (width + leadLs + leadCjkGap + glyphWidth > maxWidth + 0.01 &&
          pos > start) {
        break;
      }

      if (leadCjkGap > 0) gaps.add(prevPos);
      width += leadLs + leadCjkGap + glyphWidth;
      cpCount++;
      prevPos = pos;
      prevRune = cp;
      pos += step;
    }

    return (
      endOffset: pos,
      width: width,
      cjkGapOffsets: gaps,
      codePointCount: cpCount,
    );
  }

  ({int endOffset, double width, List<int> cjkGapOffsets, int codePointCount})
      _fitCharByCharFallback({
    required String text,
    required int start,
    required int renderEnd,
    required double maxWidth,
    required PaginationConfig config,
    required TextPainterMetricsCache metrics,
  }) {
    var pos = start;
    var width = 0.0;
    var cpCount = 0;
    while (pos < renderEnd) {
      final cp = text.codeUnitAt(pos);
      final w = metrics.runeWidth(cp);
      final leadLs = pos > start ? config.letterSpacing : 0.0;
      if (width + leadLs + w > maxWidth + 0.01 && pos > start) {
        break;
      }
      width += leadLs + w;
      cpCount++;
      pos++;
    }
    return (
      endOffset: pos,
      width: width,
      cjkGapOffsets: const <int>[],
      codePointCount: cpCount,
    );
  }

  ({double width, List<int> cjkGapOffsets, int codePointCount})
      _measureExactLine({
    required String text,
    required int start,
    required int end,
    required PaginationConfig config,
    required TextPainterMetricsCache metrics,
  }) {
    var pos = start;
    var width = 0.0;
    var prevRune = -1;
    var prevPos = -1;
    var cpCount = 0;
    final gaps = <int>[];
    final cjkGap = config.cjkAsciiGap;

    while (pos < end) {
      final cu = text.codeUnitAt(pos);
      if (ChineseTypesetting.isAsciiAlphaNum(cu)) {
        var tokEnd = pos + 1;
        while (tokEnd < end &&
            ChineseTypesetting.isAsciiTokenContinuation(
              text.codeUnitAt(tokEnd),
            )) {
          tokEnd++;
        }
        while (tokEnd > pos + 1 &&
            !ChineseTypesetting.isAsciiAlphaNum(text.codeUnitAt(tokEnd - 1))) {
          tokEnd--;
        }
        final tokWidth = metrics.tokenWidth(text.substring(pos, tokEnd));
        final leadLs = pos > start ? config.letterSpacing : 0.0;
        final leadGap = (cjkGap > 0 &&
                prevRune != -1 &&
                ChineseTypesetting.needsCjkAsciiGap(prevRune, cu))
            ? cjkGap
            : 0.0;
        if (leadGap > 0) gaps.add(prevPos);
        width += leadLs + leadGap + tokWidth;
        cpCount += tokEnd - pos;
        prevPos = tokEnd - 1;
        prevRune = text.codeUnitAt(prevPos);
        pos = tokEnd;
        continue;
      }

      var cp = cu;
      var step = 1;
      if (ChineseTypesetting.isHighSurrogate(cu) && pos + 1 < end) {
        final low = text.codeUnitAt(pos + 1);
        if (ChineseTypesetting.isLowSurrogate(low)) {
          cp = ChineseTypesetting.combineSurrogates(cu, low);
          step = 2;
        }
      }
      final leadLs = pos > start ? config.letterSpacing : 0.0;
      final leadGap = (cjkGap > 0 &&
              prevRune != -1 &&
              ChineseTypesetting.needsCjkAsciiGap(prevRune, cp))
          ? cjkGap
          : 0.0;
      if (leadGap > 0) gaps.add(prevPos);
      width += leadLs + leadGap + metrics.runeWidth(cp);
      cpCount++;
      prevPos = pos;
      prevRune = cp;
      pos += step;
    }

    return (width: width, cjkGapOffsets: gaps, codePointCount: cpCount);
  }

  /// Pulls line breaks backward to enforce Chinese 避头尾禁则 while guaranteeing
  /// forward progress and whole surrogate/token integrity.
  int _applyKinsokuRules({
    required String text,
    required int lineStart,
    required int candidateEnd,
    required int paragraphRenderEnd,
  }) {
    var adjusted = candidateEnd;
    const maxBacktrackSteps = 16;
    var steps = 0;

    while (adjusted > lineStart && steps < maxBacktrackSteps) {
      final nextCp = _codePointAt(text, adjusted, paragraphRenderEnd);
      final prevCp = _codePointBefore(text, adjusted, lineStart);

      final violatesStart = ChineseTypesetting.isLineStartProhibited(nextCp);
      final violatesEnd = ChineseTypesetting.isLineEndProhibited(prevCp);

      if (!violatesStart && !violatesEnd) {
        return adjusted;
      }

      // Step backward by 1 code point (or 1 whole ASCII word token).
      var nextBack = _stepBackward(text, adjusted, lineStart);
      if (ChineseTypesetting.isAsciiAlphaNum(prevCp)) {
        while (nextBack > lineStart &&
            ChineseTypesetting.isAsciiTokenContinuation(
              text.codeUnitAt(nextBack - 1),
            )) {
          nextBack--;
        }
      }

      if (nextBack <= lineStart) {
        // Cannot backtrack without emptying the line; keep original break.
        return candidateEnd;
      }

      adjusted = nextBack;
      steps++;
    }

    // If pathological consecutive punctuation hit maxBacktrackSteps, check final
    // position validity; fall back to candidateEnd if still invalid.
    final nextCp = _codePointAt(text, adjusted, paragraphRenderEnd);
    final prevCp = _codePointBefore(text, adjusted, lineStart);
    if (ChineseTypesetting.isLineStartProhibited(nextCp) ||
        ChineseTypesetting.isLineEndProhibited(prevCp)) {
      return candidateEnd;
    }
    return adjusted;
  }

  int _codePointAt(String text, int index, int limit) {
    final cu = text.codeUnitAt(index);
    if (ChineseTypesetting.isHighSurrogate(cu) && index + 1 < limit) {
      final low = text.codeUnitAt(index + 1);
      if (ChineseTypesetting.isLowSurrogate(low)) {
        return ChineseTypesetting.combineSurrogates(cu, low);
      }
    }
    return cu;
  }

  int _codePointBefore(String text, int index, int start) {
    final cu = text.codeUnitAt(index - 1);
    if (ChineseTypesetting.isLowSurrogate(cu) && index - 2 >= start) {
      final high = text.codeUnitAt(index - 2);
      if (ChineseTypesetting.isHighSurrogate(high)) {
        return ChineseTypesetting.combineSurrogates(high, cu);
      }
    }
    return cu;
  }

  int _stepBackward(String text, int index, int start) {
    if (index - 2 >= start &&
        ChineseTypesetting.isLowSurrogate(text.codeUnitAt(index - 1)) &&
        ChineseTypesetting.isHighSurrogate(text.codeUnitAt(index - 2))) {
      return index - 2;
    }
    return index - 1;
  }

  LayoutLine _positionLine(LayoutLine line, double dy) {
    return LayoutLine(
      startCharOffset: line.startCharOffset,
      renderEndCharOffset: line.renderEndCharOffset,
      endCharOffset: line.endCharOffset,
      dx: line.dx,
      dy: dy,
      width: line.width,
      height: line.height,
      baseline: line.baseline,
      extraCharSpacing: line.extraCharSpacing,
      isParagraphStart: line.isParagraphStart,
      isParagraphEnd: line.isParagraphEnd,
      isTitle: line.isTitle,
      cjkGapOffsets: line.cjkGapOffsets,
    );
  }
}
