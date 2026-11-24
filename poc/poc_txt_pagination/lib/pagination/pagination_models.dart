import 'package:flutter/painting.dart';

/// Immutable layout configuration matching PureRead's Phase 2 contract.
class PaginationConfig {
  const PaginationConfig({
    required this.columnWidth,
    required this.columnHeight,
    this.columnCount = 1,
    this.columnGap = 32.0,
    this.fontFamily = 'sans-serif',
    this.fontSize = 18.0,
    this.fontWeightValue = 400,
    this.lineHeightMultiplier = 1.6,
    this.paragraphSpacing = 10.0,
    this.letterSpacing = 0.0,
    this.paragraphIndentChars = 2,
    this.enablePunctuationHanging = true,
    this.enableCjkSpacing = true,
    this.enableJustification = true,
  });

  /// Constructs single-column or two-column config using the logical-page
  /// reuse formula from architecture doc section 4.2:
  /// `columnWidth = (contentWidth - columnGap) / 2` in 2-column mode.
  factory PaginationConfig.fromViewport({
    required double viewportWidth,
    required double viewportHeight,
    double horizontalPadding = 24.0,
    double verticalPadding = 24.0,
    int columnCount = 1,
    double columnGap = 32.0,
    String fontFamily = 'sans-serif',
    double fontSize = 18.0,
    int fontWeightValue = 400,
    double lineHeightMultiplier = 1.6,
    double paragraphSpacing = 10.0,
    double letterSpacing = 0.0,
    int paragraphIndentChars = 2,
    bool enablePunctuationHanging = true,
    bool enableCjkSpacing = true,
    bool enableJustification = true,
  }) {
    final contentWidth = (viewportWidth - horizontalPadding * 2).clamp(60.0, double.infinity);
    final contentHeight = (viewportHeight - verticalPadding * 2).clamp(60.0, double.infinity);
    final logicalColumnWidth = columnCount == 2
        ? ((contentWidth - columnGap) / 2).clamp(40.0, double.infinity)
        : contentWidth;

    return PaginationConfig(
      columnWidth: logicalColumnWidth,
      columnHeight: contentHeight,
      columnCount: columnCount,
      columnGap: columnGap,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeightValue: fontWeightValue,
      lineHeightMultiplier: lineHeightMultiplier,
      paragraphSpacing: paragraphSpacing,
      letterSpacing: letterSpacing,
      paragraphIndentChars: paragraphIndentChars,
      enablePunctuationHanging: enablePunctuationHanging,
      enableCjkSpacing: enableCjkSpacing,
      enableJustification: enableJustification,
    );
  }

  final double columnWidth;
  final double columnHeight;
  final int columnCount;
  final double columnGap;
  final String fontFamily;
  final double fontSize;
  final int fontWeightValue;
  final double lineHeightMultiplier;
  final double paragraphSpacing;
  final double letterSpacing;
  final int paragraphIndentChars;
  final bool enablePunctuationHanging;
  final bool enableCjkSpacing;
  final bool enableJustification;

  double get cjkAsciiGap => enableCjkSpacing ? fontSize * 0.2 : 0.0;

  FontWeight get fontWeight {
    return FontWeight.values.firstWhere(
      (w) => w.value == fontWeightValue,
      orElse: () => FontWeight.w400,
    );
  }

  String get typographyKey =>
      '$fontFamily|$fontSize|$fontWeightValue|$lineHeightMultiplier|$letterSpacing';

  PaginationConfig copyWith({
    double? columnWidth,
    double? columnHeight,
    int? columnCount,
    double? columnGap,
    String? fontFamily,
    double? fontSize,
    int? fontWeightValue,
    double? lineHeightMultiplier,
    double? paragraphSpacing,
    double? letterSpacing,
    int? paragraphIndentChars,
    bool? enablePunctuationHanging,
    bool? enableCjkSpacing,
    bool? enableJustification,
  }) {
    return PaginationConfig(
      columnWidth: columnWidth ?? this.columnWidth,
      columnHeight: columnHeight ?? this.columnHeight,
      columnCount: columnCount ?? this.columnCount,
      columnGap: columnGap ?? this.columnGap,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeightValue: fontWeightValue ?? this.fontWeightValue,
      lineHeightMultiplier: lineHeightMultiplier ?? this.lineHeightMultiplier,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      paragraphIndentChars: paragraphIndentChars ?? this.paragraphIndentChars,
      enablePunctuationHanging:
          enablePunctuationHanging ?? this.enablePunctuationHanging,
      enableCjkSpacing: enableCjkSpacing ?? this.enableCjkSpacing,
      enableJustification: enableJustification ?? this.enableJustification,
    );
  }
}

/// Progress anchor inside a chapter, invariant across font/viewport changes.
class ReadingAnchor {
  const ReadingAnchor({
    required this.chapterIndex,
    required this.charOffset,
    required this.chapterTitleSnapshot,
  });

  final int chapterIndex;
  final int charOffset;
  final String chapterTitleSnapshot;
}

/// A single pre-positioned visual line ready for [CustomPainter] rendering.
class LayoutLine {
  const LayoutLine({
    required this.startCharOffset,
    required this.renderEndCharOffset,
    required this.endCharOffset,
    required this.dx,
    required this.dy,
    required this.width,
    required this.height,
    required this.baseline,
    required this.extraCharSpacing,
    required this.isParagraphStart,
    required this.isParagraphEnd,
    required this.isTitle,
    required this.cjkGapOffsets,
  });

  /// Inclusive UTF-16 offset in the chapter's sanitized text.
  final int startCharOffset;

  /// Exclusive UTF-16 offset of visible characters (excludes trailing `\r`/`\n`).
  final int renderEndCharOffset;

  /// Exclusive UTF-16 offset including trailing paragraph newline(s), ensuring
  /// strict contiguous conservation across lines and pages.
  final int endCharOffset;

  final double dx;
  final double dy;
  final double width;
  final double height;
  final double baseline;
  final double extraCharSpacing;
  final bool isParagraphStart;
  final bool isParagraphEnd;
  final bool isTitle;

  /// UTF-16 indices (relative to [sanitizedText]) of characters after which
  /// a CJK<->ASCII micro-gap is applied.
  final List<int> cjkGapOffsets;

  String renderText(String chapterText) =>
      chapterText.substring(startCharOffset, renderEndCharOffset);

  String rawSlice(String chapterText) =>
      chapterText.substring(startCharOffset, endCharOffset);
}

/// Logical page slice covering `[startCharOffset, endCharOffset)`.
class PageSlice {
  const PageSlice({
    required this.chapterIndex,
    required this.pageIndex,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.lines,
  });

  final int chapterIndex;
  final int pageIndex;
  final int startCharOffset;
  final int endCharOffset;
  final List<LayoutLine> lines;

  bool containsOffset(int charOffset) {
    if (startCharOffset == endCharOffset) return charOffset == startCharOffset;
    return charOffset >= startCharOffset && charOffset < endCharOffset;
  }

  String sliceText(String chapterText) =>
      chapterText.substring(startCharOffset, endCharOffset);
}

/// Two-column desktop spread `(P_{2k}, P_{2k+1})`.
class TwoColumnSpread {
  const TwoColumnSpread({
    required this.spreadIndex,
    required this.left,
    required this.right,
  });

  final int spreadIndex;
  final PageSlice left;
  final PageSlice? right;
}

/// Immediate first-screen payload emitted around `priorityCharOffset`.
class FirstScreenResult {
  const FirstScreenResult({
    required this.anchorPageIndex,
    required this.pages,
    required this.elapsedMicros,
  });

  final int anchorPageIndex;
  final List<PageSlice> pages;
  final int elapsedMicros;
}

/// Full result of incremental chapter pagination including performance telemetry.
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
