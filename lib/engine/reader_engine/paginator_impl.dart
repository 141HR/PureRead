import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../domain/services/reader_paginator.dart';
import '../../domain/value_objects/cancellation_token.dart';
import '../../domain/value_objects/page_slice.dart';
import '../../domain/value_objects/pagination_config.dart';
import 'anchor_mapper.dart';
import 'chinese_typesetting.dart';
import 'inline_image_marker.dart';
import 'platform_font_resolver.dart';

/// Immediate first-screen payload emitted around `priorityCharOffset` before
/// full-chapter incremental pagination completes.
class FirstScreenResult {
  const FirstScreenResult({
    required this.anchorPageIndex,
    required this.pages,
    required this.elapsedMicros,
    required this.isApproximateWindow,
  });

  final int anchorPageIndex;
  final List<PageSlice> pages;
  final int elapsedMicros;

  /// True when [pages] came from a local anchored slice (deep offset > 1,200)
  /// whose `pageIndex` values are relative to that local window rather than the
  /// chapter start.
  final bool isApproximateWindow;
}

/// Complete telemetry and slices returned by
/// [IncrementalTextPaginator.paginateChapterIncremental].
class IncrementalPaginationResult {
  const IncrementalPaginationResult({
    required this.firstScreen,
    required this.allPages,
    required this.firstScreenMicros,
    required this.totalComputeMicros,
    required this.maxSliceMicros,
    required this.timeSliceCount,
  });

  final FirstScreenResult firstScreen;
  final List<PageSlice> allPages;
  final int firstScreenMicros;
  final int totalComputeMicros;
  final int maxSliceMicros;
  final int timeSliceCount;
}

/// Root-isolate [TextPainter] glyph and ASCII token width cache for a single
/// typography profile.
///
/// Honors Flutter's `dart:ui` root-isolate constraint: all [TextPainter]
/// measurements execute on the root/UI isolate and are cached across lines,
/// pages, and chapters for a given font configuration.
class TextPainterMetricsCache {
  TextPainterMetricsCache(this.config)
      : _baseStyle = TextStyle(
          fontFamily: resolvePlatformFontFamily(config.fontFamily),
          fontFamilyFallback: resolvePlatformFontFamilyFallback(),
          fontSize: config.fontSize,
          fontWeight: resolveFontWeight(config.fontWeightValue),
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
  final Map<String, List<double>> _tokenAdvances = <String, List<double>>{};
  final Map<String, double> _tokenWidths = <String, double>{};

  late final double lineHeight;
  late final double baseline;
  double? _uniformCjkIdeographWidth;

  /// Whether the active font assigns uniform advance width across the 10-char
  /// representative CJK probe (`一国鑫田口日月木水火`).
  bool get hasUniformCjkWidth => _uniformCjkIdeographWidth != null;

  /// Cache key identifying the font/metric properties that affect glyph sizes.
  static String typographyKeyFor(PaginationConfig config) =>
      '${config.fontFamily}|${config.fontFilePath ?? ''}|${config.fontSize}|'
      '${config.fontWeightValue}|${config.lineHeightMultiplier}|'
      '${config.letterSpacing}';

  static FontWeight resolveFontWeight(int fontWeightValue) {
    return switch (fontWeightValue) {
      <= 150 => FontWeight.w100,
      <= 250 => FontWeight.w200,
      <= 350 => FontWeight.w300,
      <= 450 => FontWeight.w400,
      <= 550 => FontWeight.w500,
      <= 650 => FontWeight.w600,
      <= 750 => FontWeight.w700,
      <= 850 => FontWeight.w800,
      _ => FontWeight.w900,
    };
  }

  void _measureLineMetrics() {
    _probePainter.text = TextSpan(text: '汉A', style: _baseStyle);
    _probePainter.layout();
    final measuredHeight = _probePainter.height;
    lineHeight = measuredHeight > 0
        ? measuredHeight
        : config.fontSize * config.lineHeightMultiplier;
    baseline = _probePainter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );

    // Empirically probe 10 structurally varied CJK ideographs via TextPainter.
    // Uniform-advance fonts avoid thousands of redundant SkParagraph FFI calls,
    // while variable-width fonts automatically fall back to batched warmUp.
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

  /// Pre-populates unseen glyph widths inside `[start, end)` using a single
  /// batched [TextPainter.layout] call per paragraph.
  void warmUpSlice(String text, int start, int end) {
    StringBuffer? unseenBuf;
    final unseenRunes = <int>[];
    final seenInBatch = <int>{};
    final uniformCjk = _uniformCjkIdeographWidth;

    var i = start;
    while (i < end) {
      final cp = ChineseTypesetting.codePointAt(text, i, end);
      final nextI = ChineseTypesetting.stepForward(text, i, end);
      if (uniformCjk != null && cp >= 0x4E00 && cp <= 0x9FFF) {
        i = nextI;
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
      i = nextI;
    }

    if (unseenBuf == null || unseenRunes.isEmpty) return;

    _probePainter.text = TextSpan(text: unseenBuf.toString(), style: _baseStyle);
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
      if (advance > 0) {
        _runeWidths[cp] = advance;
      } else {
        _runeWidths[cp] = _measureSingleRuneFallback(cp);
      }
      prevDx = dx;
    }
  }

  double _measureSingleRuneFallback(int codePoint) {
    _probePainter.text = TextSpan(
      text: String.fromCharCode(codePoint),
      style: _baseStyle,
    );
    _probePainter.layout();
    final w = _probePainter.width;
    return w > 0 ? w : config.fontSize;
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

    final w = _measureSingleRuneFallback(codePoint);
    _runeWidths[codePoint] = w;
    return w;
  }

  /// Measures and caches individual character advances inside a contiguous
  /// ASCII token so proportional font kerning is preserved in `charXOffsets`.
  List<double> tokenAdvances(String token) {
    final cached = _tokenAdvances[token];
    if (cached != null) return cached;

    if (token.length == 1) {
      final single = List<double>.unmodifiable(<double>[
        runeWidth(token.codeUnitAt(0)),
      ]);
      _tokenAdvances[token] = single;
      _tokenWidths[token] = single[0];
      return single;
    }

    _probePainter.text = TextSpan(text: token, style: _baseStyle);
    _probePainter.layout();
    final baseWidth = _probePainter.width;
    final advances = List<double>.filled(token.length, 0.0);
    var prevDx = 0.0;
    for (var i = 0; i < token.length; i++) {
      final rawDx = i + 1 == token.length
          ? baseWidth
          : _probePainter
              .getOffsetForCaret(TextPosition(offset: i + 1), ui.Rect.zero)
              .dx;
      final clampedDx = rawDx < prevDx ? prevDx : rawDx;
      advances[i] = clampedDx - prevDx;
      prevDx = clampedDx;
    }
    final immutable = List<double>.unmodifiable(advances);
    _tokenAdvances[token] = immutable;
    _tokenWidths[token] =
        baseWidth + (token.length - 1) * config.letterSpacing;
    return immutable;
  }

  double tokenWidth(String token) {
    final cached = _tokenWidths[token];
    if (cached != null) return cached;
    tokenAdvances(token);
    return _tokenWidths[token]!;
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

class _ScannedLine {
  const _ScannedLine({
    required this.endOffset,
    required this.width,
    required this.advances,
    required this.utf16Lens,
    required this.gapBefore,
  });

  final int endOffset;
  final double width;
  final List<double> advances;
  final List<int> utf16Lens;
  final List<bool> gapBefore;

  int get codePointCount => advances.length;
}

class _PagePacker {
  _PagePacker({
    required this.chapterIndex,
    required this.config,
    required int initialPageStart,
    this.anchorOffset,
  }) : _currentPageStart = initialPageStart;

  final int chapterIndex;
  final PaginationConfig config;
  final int? anchorOffset;

  final List<PageSlice> pages = <PageSlice>[];
  List<LayoutLine> _currentLines = <LayoutLine>[];
  double _currentY = 0.0;
  int _currentPageStart;
  int? anchorPageIndex;

  void addLines(List<LayoutLine> lines) {
    for (final line in lines) {
      if (_currentLines.isNotEmpty &&
          _currentY + line.height > config.columnHeight + 0.01) {
        _flushPage(_currentLines.last.endCharOffset);
        _currentPageStart = line.startCharOffset;
      }
      _currentLines.add(
        LayoutLine(
          text: line.text,
          startCharOffset: line.startCharOffset,
          endCharOffset: line.endCharOffset,
          x: line.x,
          y: _currentY,
          width: line.width,
          height: line.height,
          isParagraphStart: line.isParagraphStart,
          isParagraphEnd: line.isParagraphEnd,
          isChapterTitle: line.isChapterTitle,
          charXOffsets: line.charXOffsets,
        ),
      );
      _currentY += line.height;
      if (line.isParagraphEnd) {
        _currentY += config.paragraphSpacing;
      }
    }
  }

  void flushRemainder([int? forcedEndOffset]) {
    if (_currentLines.isEmpty) return;
    _flushPage(forcedEndOffset ?? _currentLines.last.endCharOffset);
  }

  void _flushPage(int endCharOffset) {
    final page = PageSlice(
      chapterIndex: chapterIndex,
      pageIndex: pages.length,
      startCharOffset: _currentPageStart,
      endCharOffset: endCharOffset,
      lines: List<LayoutLine>.unmodifiable(_currentLines),
    );
    pages.add(page);
    if (anchorOffset != null &&
        anchorPageIndex == null &&
        page.containsOffset(anchorOffset!)) {
      anchorPageIndex = page.pageIndex;
    }
    _currentLines = <LayoutLine>[];
    _currentY = 0.0;
  }
}

/// Root-isolate `TextPainter`-backed incremental chapter paginator implementing
/// [ReaderPaginator].
///
/// Features:
/// - Uniform CJK advance probe with batched fallback for variable-width fonts
/// - Immediate priority local window around `priorityCharOffset` (`< 8ms`)
/// - `<= 4ms` frame-budgeted incremental slicing to complete full chapters
/// - 避头尾禁则, CJK-ASCII micro-spacing, first-line indent (`LayoutLine.x`),
///   justification via `LayoutLine.charXOffsets`, and 100% char conservation.
class IncrementalTextPaginator implements ReaderPaginator {
  IncrementalTextPaginator({
    this.frameBudgetMicros = 4000,
    this.treatFirstLineAsTitle = false,
    this.enableJustification = true,
    this.maxCachedTypographyProfiles = 16,
  });

  final int frameBudgetMicros;
  final bool treatFirstLineAsTitle;
  final bool enableJustification;
  final int maxCachedTypographyProfiles;

  final Map<String, TextPainterMetricsCache> _cacheByConfig =
      <String, TextPainterMetricsCache>{};

  /// Returns or initializes the [TextPainterMetricsCache] for [config].
  TextPainterMetricsCache metricsFor(PaginationConfig config) {
    final key = TextPainterMetricsCache.typographyKeyFor(config);
    final existing = _cacheByConfig[key];
    if (existing != null) {
      return existing;
    }
    if (_cacheByConfig.length >= maxCachedTypographyProfiles &&
        _cacheByConfig.isNotEmpty) {
      _cacheByConfig.remove(_cacheByConfig.keys.first);
    }
    final created = TextPainterMetricsCache(config);
    _cacheByConfig[key] = created;
    return created;
  }

  /// Clears cached font metrics (useful for benchmarking cold vs warm runs).
  void clearMetricsCache() => _cacheByConfig.clear();

  @override
  Future<List<PageSlice>> paginateChapter({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    int? priorityCharOffset,
  }) async {
    final result = await paginateChapterIncremental(
      chapterIndex: chapterIndex,
      sanitizedText: sanitizedText,
      config: config,
      priorityCharOffset: priorityCharOffset,
    );
    return result.allPages;
  }

  /// Runs incremental pagination and emits [onFirstScreen] immediately once the
  /// pages surrounding [priorityCharOffset] are ready, before time-sliced
  /// completion of the full chapter.
  Future<IncrementalPaginationResult> paginateChapterIncremental({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    int? priorityCharOffset,
    bool? treatFirstLineAsTitle,
    void Function(FirstScreenResult firstScreen)? onFirstScreen,
    bool yieldBetweenSlices = true,
    CancellationToken? cancelToken,
    Future<void> Function()? yieldFrame,
  }) async {
    cancelToken?.throwIfCancelled();

    final useTitle = treatFirstLineAsTitle ?? this.treatFirstLineAsTitle;
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
        isApproximateWindow: false,
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

    final clampedAnchor =
        (priorityCharOffset ?? 0).clamp(0, sanitizedText.length - 1);
    final paragraphs = _splitParagraphs(
      sanitizedText,
      treatFirstLineAsTitle: useTitle,
    );

    final firstScreenSw = Stopwatch()..start();
    final FirstScreenResult firstScreen;

    final useAnchoredWindow = clampedAnchor > 1200;
    final packer = _PagePacker(
      chapterIndex: chapterIndex,
      config: config,
      initialPageStart: 0,
      anchorOffset: clampedAnchor,
    );
    var nextParagraphIdx = 0;

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
      final minPagesWanted = config.columnCount >= 2 ? 4 : 3;

      while (nextParagraphIdx < paragraphs.length) {
        final p = paragraphs[nextParagraphIdx++];
        packer.addLines(_breakParagraph(p, sanitizedText, config, metrics));

        if (packer.anchorPageIndex != null &&
            packer.pages.length >= packer.anchorPageIndex! + minPagesWanted) {
          break;
        }
      }

      if (nextParagraphIdx >= paragraphs.length) {
        packer.flushRemainder(sanitizedText.length);
      }

      firstScreenSw.stop();
      final resolvedAnchorIdx = packer.anchorPageIndex ??
          AnchorMapper.findPageIndexByCharOffset(packer.pages, clampedAnchor);
      final sliceStart = (resolvedAnchorIdx - 1).clamp(0, packer.pages.length);
      final sliceEnd = (resolvedAnchorIdx + 3).clamp(0, packer.pages.length);
      firstScreen = FirstScreenResult(
        anchorPageIndex: resolvedAnchorIdx,
        pages: List<PageSlice>.unmodifiable(
          packer.pages.sublist(sliceStart, sliceEnd),
        ),
        elapsedMicros: firstScreenSw.elapsedMicroseconds,
        isApproximateWindow: false,
      );
      onFirstScreen?.call(firstScreen);
    }

    var computeMicros = firstScreenSw.elapsedMicroseconds;
    var maxSliceMicros = firstScreenSw.elapsedMicroseconds;
    var sliceCount = 1;

    while (nextParagraphIdx < paragraphs.length) {
      if (yieldBetweenSlices) {
        await (yieldFrame != null
            ? yieldFrame()
            : Future<void>.delayed(Duration.zero));
        cancelToken?.throwIfCancelled();
      }
      final sliceSw = Stopwatch()..start();
      sliceCount++;

      while (nextParagraphIdx < paragraphs.length) {
        final p = paragraphs[nextParagraphIdx++];
        packer.addLines(_breakParagraph(p, sanitizedText, config, metrics));

        if (sliceSw.elapsedMicroseconds >= frameBudgetMicros &&
            nextParagraphIdx < paragraphs.length) {
          break;
        }
      }

      if (nextParagraphIdx >= paragraphs.length) {
        packer.flushRemainder(sanitizedText.length);
      }

      sliceSw.stop();
      final elapsed = sliceSw.elapsedMicroseconds;
      computeMicros += elapsed;
      if (elapsed > maxSliceMicros) maxSliceMicros = elapsed;
    }

    totalSw.stop();

    return IncrementalPaginationResult(
      firstScreen: firstScreen,
      allPages: List<PageSlice>.unmodifiable(packer.pages),
      firstScreenMicros: firstScreenSw.elapsedMicroseconds,
      totalComputeMicros: computeMicros,
      maxSliceMicros: maxSliceMicros,
      timeSliceCount: sliceCount,
    );
  }

  /// Synchronous full-chapter pagination for deterministic tests and fast
  /// in-memory callers.
  List<PageSlice> paginateChapterSync({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    bool? treatFirstLineAsTitle,
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

    final useTitle = treatFirstLineAsTitle ?? this.treatFirstLineAsTitle;
    final metrics = metricsFor(config);
    final paragraphs = _splitParagraphs(
      sanitizedText,
      treatFirstLineAsTitle: useTitle,
    );

    final packer = _PagePacker(
      chapterIndex: chapterIndex,
      config: config,
      initialPageStart: 0,
    );

    for (final p in paragraphs) {
      packer.addLines(_breakParagraph(p, sanitizedText, config, metrics));
    }
    packer.flushRemainder(sanitizedText.length);

    return List<PageSlice>.unmodifiable(packer.pages);
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

    var pIdx = 0;
    for (var i = 0; i < paragraphs.length; i++) {
      if (anchorOffset >= paragraphs[i].start &&
          anchorOffset < paragraphs[i].end) {
        pIdx = i;
        break;
      }
    }

    var startParaIdx = pIdx;
    var charsBack = 0;
    while (startParaIdx > 0 && charsBack < 650) {
      startParaIdx--;
      charsBack += paragraphs[startParaIdx].end - paragraphs[startParaIdx].start;
    }

    final packer = _PagePacker(
      chapterIndex: chapterIndex,
      config: config,
      initialPageStart: paragraphs[startParaIdx].start,
      anchorOffset: anchorOffset,
    );
    final minTrailingPages = config.columnCount >= 2 ? 3 : 2;

    for (var i = startParaIdx; i < paragraphs.length; i++) {
      packer.addLines(_breakParagraph(paragraphs[i], text, config, metrics));

      if (packer.anchorPageIndex != null &&
          packer.pages.length >=
              packer.anchorPageIndex! + minTrailingPages + 1) {
        break;
      }
    }

    if (packer.anchorPageIndex == null ||
        packer.pages.length < packer.anchorPageIndex! + minTrailingPages + 1) {
      packer.flushRemainder();
    }

    sw.stop();
    final resolved = packer.anchorPageIndex ??
        AnchorMapper.findPageIndexByCharOffset(packer.pages, anchorOffset);
    final sliceStart = (resolved - 1).clamp(0, packer.pages.length);
    final sliceEnd = (resolved + 3).clamp(0, packer.pages.length);
    return FirstScreenResult(
      anchorPageIndex: resolved,
      pages: List<PageSlice>.unmodifiable(
        packer.pages.sublist(sliceStart, sliceEnd),
      ),
      elapsedMicros: sw.elapsedMicroseconds,
      isApproximateWindow: true,
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

      // Collapse blank newline runs onto the preceding paragraph so pages never
      // start with orphan blank lines while conserving 100% of characters.
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
            isTitle:
                treatFirstLineAsTitle && result.isEmpty && renderEnd > lineStart,
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
          text: text.substring(p.start, p.end),
          startCharOffset: p.start,
          endCharOffset: p.end,
          x: 0.0,
          y: 0.0,
          width: 0.0,
          height: metrics.lineHeight,
          isParagraphStart: true,
          isParagraphEnd: true,
          isChapterTitle: p.isTitle,
          charXOffsets: null,
        ),
      ];
    }

    final imageRef = InlineImageMarker.tryParseLine(
      text.substring(p.start, p.renderEnd),
    );
    if (imageRef != null) {
      return _buildInlineImageLines(p, text, imageRef, config);
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
    final firstLineIndent = (!p.isTitle &&
            !startsWithFullIndent &&
            config.paragraphIndentChars > 0)
        ? config.paragraphIndentChars * config.fontSize
        : 0.0;

    final cjkGap = ChineseTypesetting.cjkAsciiGap(
      config.fontSize,
      enabled: config.enableCjkSpacing,
    );

    var lineStart = p.start;
    while (lineStart < p.renderEnd) {
      final isFirstLine = lineStart == p.start;
      final x = isFirstLine ? firstLineIndent : 0.0;
      final minAllowedWidth = math.min(config.fontSize, config.columnWidth);
      final maxLineWidth = math.max(minAllowedWidth, config.columnWidth - x);

      var scan = _scanLine(
        text: text,
        start: lineStart,
        limit: p.renderEnd,
        maxWidth: maxLineWidth,
        cjkGap: cjkGap,
        config: config,
        metrics: lineMetrics,
      );

      if (config.enablePunctuationHanging && scan.endOffset < p.renderEnd) {
        final adjusted = ChineseTypesetting.resolveLineBreakOffset(
          text: text,
          lineStart: lineStart,
          candidateEnd: scan.endOffset,
          paragraphRenderEnd: p.renderEnd,
        );
        if (adjusted != scan.endOffset) {
          scan = _scanLine(
            text: text,
            start: lineStart,
            limit: adjusted,
            maxWidth: null,
            cjkGap: cjkGap,
            config: config,
            metrics: lineMetrics,
          );
        }
      }

      final lineRenderEnd = scan.endOffset;
      final isLastLine = lineRenderEnd >= p.renderEnd;
      final lineEnd = isLastLine ? p.end : lineRenderEnd;

      var extraCharSpacing = 0.0;
      if (enableJustification &&
          !p.isTitle &&
          !isLastLine &&
          scan.codePointCount > 1) {
        final slack = maxLineWidth - scan.width;
        if (slack > 0.25 && slack <= config.fontSize * 3.0) {
          extraCharSpacing = slack / (scan.codePointCount - 1);
        }
      }

      final (:charXOffsets, :renderedWidth) = _buildCharXOffsets(
        renderLength: lineRenderEnd - lineStart,
        scan: scan,
        cjkGap: cjkGap,
        letterSpacing: config.letterSpacing,
        extraCharSpacing: extraCharSpacing,
      );

      lines.add(
        LayoutLine(
          text: text.substring(lineStart, lineEnd),
          startCharOffset: lineStart,
          endCharOffset: lineEnd,
          x: x,
          y: 0.0,
          width: renderedWidth,
          height: lineMetrics.lineHeight,
          isParagraphStart: isFirstLine,
          isParagraphEnd: isLastLine,
          isChapterTitle: p.isTitle,
          charXOffsets: charXOffsets,
        ),
      );

      lineStart = lineRenderEnd;
    }

    return lines;
  }

  List<LayoutLine> _buildInlineImageLines(
    _ParagraphRange p,
    String text,
    InlineImageRef imageRef,
    PaginationConfig config,
  ) {
    const verticalPadding = 12.0;
    final colW = math.max(1.0, config.columnWidth);
    final colH = math.max(1.0, config.columnHeight);
    final maxDrawH = math.max(1.0, colH - verticalPadding);

    final double drawW;
    final double drawH;
    final isSmallIcon =
        imageRef.width > 0 &&
        imageRef.height > 0 &&
        imageRef.width <= 160 &&
        imageRef.height <= 120;

    if (isSmallIcon) {
      final naturalW = imageRef.width.toDouble();
      final naturalH = imageRef.height.toDouble();
      final scale = math.min(
        1.0,
        math.min(colW / naturalW, maxDrawH / naturalH),
      );
      drawW = naturalW * scale;
      drawH = naturalH * scale;
    } else {
      final aspect = (imageRef.width > 0 && imageRef.height > 0)
          ? imageRef.width / imageRef.height
          : 4.0 / 3.0;
      final maxIllustrationH = math.min(colH * 0.86, maxDrawH);
      var w = colW;
      var h = w / aspect;
      if (h > maxIllustrationH) {
        h = maxIllustrationH;
        w = h * aspect;
      }
      drawW = w;
      drawH = h;
    }

    final x = math.max(0.0, (colW - drawW) * 0.5);
    final lineHeight = math.min(colH, drawH + verticalPadding);

    return <LayoutLine>[
      LayoutLine(
        text: text.substring(p.start, p.end),
        startCharOffset: p.start,
        endCharOffset: p.end,
        x: x,
        y: 0.0,
        width: drawW,
        height: lineHeight,
        isParagraphStart: true,
        isParagraphEnd: true,
        isChapterTitle: false,
        charXOffsets: null,
      ),
    ];
  }

  _ScannedLine _scanLine({
    required String text,
    required int start,
    required int limit,
    required double? maxWidth,
    required double cjkGap,
    required PaginationConfig config,
    required TextPainterMetricsCache metrics,
    bool groupAsciiTokens = true,
  }) {
    var pos = start;
    var width = 0.0;
    var prevRune = -1;
    final advances = <double>[];
    final utf16Lens = <int>[];
    final gapBefore = <bool>[];

    while (pos < limit) {
      final cu = text.codeUnitAt(pos);

      if (groupAsciiTokens && ChineseTypesetting.isAsciiAlphaNum(cu)) {
        var tokEnd = pos + 1;
        while (tokEnd < limit &&
            ChineseTypesetting.isAsciiTokenContinuation(
              text.codeUnitAt(tokEnd),
            )) {
          tokEnd++;
        }
        while (tokEnd > pos + 1 &&
            !ChineseTypesetting.isAsciiAlphaNum(text.codeUnitAt(tokEnd - 1))) {
          tokEnd--;
        }

        final tokenStr = text.substring(pos, tokEnd);
        final tokWidth = metrics.tokenWidth(tokenStr);
        final leadLs = pos > start ? config.letterSpacing : 0.0;
        final needsGap = cjkGap > 0 &&
            prevRune != -1 &&
            ChineseTypesetting.needsCjkAsciiGap(prevRune, cu);
        final leadCjkGap = needsGap ? cjkGap : 0.0;

        if (maxWidth == null ||
            width + leadLs + leadCjkGap + tokWidth <= maxWidth + 0.01) {
          final tokAdvances = metrics.tokenAdvances(tokenStr);
          for (var j = 0; j < tokAdvances.length; j++) {
            advances.add(tokAdvances[j]);
            utf16Lens.add(1);
            gapBefore.add(j == 0 && needsGap);
          }
          width += leadLs + leadCjkGap + tokWidth;
          prevRune = text.codeUnitAt(tokEnd - 1);
          pos = tokEnd;
          continue;
        }

        // Single ASCII token wider than an empty line: split char-by-char.
        if (pos == start) {
          return _scanLine(
            text: text,
            start: start,
            limit: limit,
            maxWidth: maxWidth,
            cjkGap: cjkGap,
            config: config,
            metrics: metrics,
            groupAsciiTokens: false,
          );
        }
        break;
      }

      final cp = ChineseTypesetting.codePointAt(text, pos, limit);
      final nextPos = ChineseTypesetting.stepForward(text, pos, limit);
      final step = nextPos - pos;
      final glyphWidth = metrics.runeWidth(cp);
      final leadLs = pos > start ? config.letterSpacing : 0.0;
      final needsGap = cjkGap > 0 &&
          prevRune != -1 &&
          ChineseTypesetting.needsCjkAsciiGap(prevRune, cp);
      final leadCjkGap = needsGap ? cjkGap : 0.0;

      if (maxWidth != null &&
          width + leadLs + leadCjkGap + glyphWidth > maxWidth + 0.01 &&
          pos > start) {
        break;
      }

      advances.add(glyphWidth);
      utf16Lens.add(step);
      gapBefore.add(needsGap);
      width += leadLs + leadCjkGap + glyphWidth;
      prevRune = cp;
      pos = nextPos;
    }

    return _ScannedLine(
      endOffset: pos,
      width: width,
      advances: advances,
      utf16Lens: utf16Lens,
      gapBefore: gapBefore,
    );
  }

  ({List<double>? charXOffsets, double renderedWidth}) _buildCharXOffsets({
    required int renderLength,
    required _ScannedLine scan,
    required double cjkGap,
    required double letterSpacing,
    required double extraCharSpacing,
  }) {
    if (renderLength <= 0 || scan.codePointCount == 0) {
      return (charXOffsets: null, renderedWidth: 0.0);
    }

    final offsets = List<double>.filled(renderLength, 0.0);
    var cursorX = 0.0;
    var outIdx = 0;

    for (var k = 0; k < scan.codePointCount; k++) {
      if (k > 0) {
        cursorX += letterSpacing +
            extraCharSpacing +
            (scan.gapBefore[k] ? cjkGap : 0.0);
      }
      final step = scan.utf16Lens[k];
      offsets[outIdx] = cursorX;
      if (step == 2) {
        offsets[outIdx + 1] = cursorX;
      }
      outIdx += step;
      cursorX += scan.advances[k];
    }

    return (
      charXOffsets: List<double>.unmodifiable(offsets),
      renderedWidth: cursorX,
    );
  }
}
