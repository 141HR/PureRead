import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../domain/domain.dart';

/// CustomPainter rendering one [PageSlice] (single-column) or a paired spread
/// `(P_{2k}, P_{2k+1})` (two-column), with theme background, CJK-ASCII `0.2em`
/// micro-spacing (or exact [LayoutLine.charXOffsets]), and optional canvas
/// header/footer lines.
class ReaderPagePainter extends CustomPainter {
  ReaderPagePainter({
    required this.config,
    required this.leftPage,
    this.rightPage,
    this.backgroundColor,
    required this.textColor,
    required this.secondaryTextColor,
    this.dividerColor,
    this.headerText,
    this.footerLeftText,
    this.footerRightText,
    this.contentTopOffset = 0.0,
  });

  final PaginationConfig config;
  final PageSlice? leftPage;
  final PageSlice? rightPage;
  final Color? backgroundColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color? dividerColor;
  final String? headerText;
  final String? footerLeftText;
  final String? footerRightText;
  final double contentTopOffset;

  static final _GlyphPainterCache _glyphCache = _GlyphPainterCache();

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = backgroundColor!,
      );
    }

    final effectiveFontFamily =
        (config.fontFamily == 'system' || config.fontFamily.isEmpty)
        ? null
        : config.fontFamily;
    final regularWeight = _resolveFontWeight(config.fontWeightValue);

    final baseStyle = TextStyle(
      fontFamily: effectiveFontFamily,
      fontSize: config.fontSize,
      fontWeight: regularWeight,
      height: config.lineHeightMultiplier,
      letterSpacing: config.letterSpacing,
      color: textColor,
    );

    if (headerText != null && headerText!.isNotEmpty) {
      _paintChromeText(
        canvas,
        text: headerText!,
        offset: const Offset(16, 8),
        maxWidth: math.max(40.0, size.width - 32),
        fontFamily: effectiveFontFamily,
      );
    }

    final topY = contentTopOffset;

    if (config.columnCount == 2) {
      final spreadWidth = config.columnWidth * 2 + config.columnGap;
      final leftOriginX = math.max(0.0, (size.width - spreadWidth) / 2);
      final rightOriginX = leftOriginX + config.columnWidth + config.columnGap;

      if (leftPage != null) {
        _paintSlice(
          canvas,
          leftPage!,
          Offset(leftOriginX, topY),
          baseStyle: baseStyle,
          effectiveFontFamily: effectiveFontFamily,
        );
      }

      final dividerX = leftOriginX + config.columnWidth + config.columnGap / 2;
      final linePaint = Paint()
        ..color = dividerColor ?? secondaryTextColor.withAlpha(46)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(dividerX, topY),
        Offset(dividerX, topY + config.columnHeight),
        linePaint,
      );

      if (rightPage != null) {
        _paintSlice(
          canvas,
          rightPage!,
          Offset(rightOriginX, topY),
          baseStyle: baseStyle,
          effectiveFontFamily: effectiveFontFamily,
        );
      }
    } else if (leftPage != null) {
      final originX = math.max(0.0, (size.width - config.columnWidth) / 2);
      _paintSlice(
        canvas,
        leftPage!,
        Offset(originX, topY),
        baseStyle: baseStyle,
        effectiveFontFamily: effectiveFontFamily,
      );
    }

    if (footerLeftText != null && footerLeftText!.isNotEmpty) {
      _paintChromeText(
        canvas,
        text: footerLeftText!,
        offset: Offset(16, math.max(0.0, size.height - 24)),
        maxWidth: math.max(40.0, size.width * 0.5 - 24),
        fontFamily: effectiveFontFamily,
      );
    }
    if (footerRightText != null && footerRightText!.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: footerRightText!,
          style: TextStyle(
            fontFamily: effectiveFontFamily,
            fontSize: 12,
            color: secondaryTextColor,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: math.max(40.0, size.width * 0.5 - 24));
      tp.paint(
        canvas,
        Offset(
          math.max(16.0, size.width - 16 - tp.width),
          math.max(0.0, size.height - 24),
        ),
      );
    }
  }

  void _paintSlice(
    Canvas canvas,
    PageSlice slice,
    Offset origin, {
    required TextStyle baseStyle,
    required String? effectiveFontFamily,
  }) {
    for (final line in slice.lines) {
      final visibleText = trimTrailingLineBreaks(line.text);
      if (visibleText.isEmpty) continue;

      final lineStyle = line.isChapterTitle
          ? baseStyle.copyWith(fontWeight: FontWeight.w700)
          : baseStyle;

      final xOffsets = line.charXOffsets;
      if (xOffsets != null && xOffsets.isNotEmpty) {
        _paintWithCharOffsets(
          canvas,
          visibleText: visibleText,
          xOffsets: xOffsets,
          origin: Offset(origin.dx + line.x, origin.dy + line.y),
          style: lineStyle,
          fontFamily: effectiveFontFamily,
        );
        continue;
      }

      final span = _buildCjkSpacedSpan(
        visibleText: visibleText,
        style: lineStyle,
      );
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(origin.dx + line.x, origin.dy + line.y));
    }
  }

  void _paintWithCharOffsets(
    Canvas canvas, {
    required String visibleText,
    required List<double> xOffsets,
    required Offset origin,
    required TextStyle style,
    required String? fontFamily,
  }) {
    var i = 0;
    final len = visibleText.length;
    while (i < len) {
      if (i >= xOffsets.length) {
        // Defensively render any trailing suffix if xOffsets was shorter.
        final rest = visibleText.substring(i);
        final tp = TextPainter(
          text: TextSpan(text: rest, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final lastX = xOffsets.isNotEmpty ? xOffsets.last : 0.0;
        tp.paint(canvas, Offset(origin.dx + lastX, origin.dy));
        break;
      }

      final cu = visibleText.codeUnitAt(i);
      final step =
          (_isHighSurrogate(cu) &&
              i + 1 < len &&
              _isLowSurrogate(visibleText.codeUnitAt(i + 1)))
          ? 2
          : 1;
      final glyph = visibleText.substring(i, i + step);
      final xOffset = xOffsets[i];
      final glyphPainter = _glyphCache.obtain(
        glyph: glyph,
        fontFamily: fontFamily,
        fontSize: style.fontSize ?? config.fontSize,
        fontWeight: style.fontWeight ?? FontWeight.w400,
        height: style.height ?? config.lineHeightMultiplier,
        color: style.color ?? textColor,
      );
      glyphPainter.paint(canvas, Offset(origin.dx + xOffset, origin.dy));
      i += step;
    }
  }

  InlineSpan _buildCjkSpacedSpan({
    required String visibleText,
    required TextStyle style,
  }) {
    if (!config.enableCjkSpacing || visibleText.length <= 1) {
      return TextSpan(text: visibleText, style: style);
    }

    final cjkGap = config.fontSize * 0.2;
    final spans = <InlineSpan>[];
    var runStart = 0;
    var pos = 0;
    var prevCp = -1;
    var prevPos = -1;
    var prevStep = 1;

    while (pos < visibleText.length) {
      final cu = visibleText.codeUnitAt(pos);
      var cp = cu;
      var step = 1;
      if (_isHighSurrogate(cu) && pos + 1 < visibleText.length) {
        final low = visibleText.codeUnitAt(pos + 1);
        if (_isLowSurrogate(low)) {
          cp = 0x10000 + (((cu - 0xD800) << 10) | (low - 0xDC00));
          step = 2;
        }
      }

      if (prevCp != -1 && _needsCjkAsciiGap(prevCp, cp)) {
        if (prevPos > runStart) {
          spans.add(
            TextSpan(
              text: visibleText.substring(runStart, prevPos),
              style: style,
            ),
          );
        }
        spans.add(
          TextSpan(
            text: visibleText.substring(prevPos, prevPos + prevStep),
            style: style.copyWith(
              letterSpacing: (style.letterSpacing ?? 0.0) + cjkGap,
            ),
          ),
        );
        runStart = pos;
      }

      prevCp = cp;
      prevPos = pos;
      prevStep = step;
      pos += step;
    }

    if (spans.isEmpty) {
      return TextSpan(text: visibleText, style: style);
    }
    if (runStart < visibleText.length) {
      spans.add(
        TextSpan(text: visibleText.substring(runStart), style: style),
      );
    }
    return TextSpan(children: spans);
  }

  void _paintChromeText(
    Canvas canvas, {
    required String text,
    required Offset offset,
    required double maxWidth,
    required String? fontFamily,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          color: secondaryTextColor,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  /// Trims trailing `\r` and `\n` characters preserved in [LayoutLine.text]
  /// for character-offset conservation.
  static String trimTrailingLineBreaks(String text) {
    var end = text.length;
    while (end > 0) {
      final cu = text.codeUnitAt(end - 1);
      if (cu == 0x0A || cu == 0x0D) {
        end--;
      } else {
        break;
      }
    }
    return end == text.length ? text : text.substring(0, end);
  }

  static FontWeight _resolveFontWeight(int weightValue) {
    return FontWeight.values.firstWhere(
      (w) => w.value == weightValue,
      orElse: () => FontWeight.w400,
    );
  }

  static bool _isHighSurrogate(int cu) => cu >= 0xD800 && cu <= 0xDBFF;

  static bool _isLowSurrogate(int cu) => cu >= 0xDC00 && cu <= 0xDFFF;

  static bool _isCjkIdeograph(int cp) {
    return (cp >= 0x4E00 && cp <= 0x9FFF) ||
        (cp >= 0x3400 && cp <= 0x4DBF) ||
        (cp >= 0xF900 && cp <= 0xFAFF) ||
        (cp >= 0x20000 && cp <= 0x2FA1F);
  }

  static bool _isAsciiAlphaNum(int cp) {
    return (cp >= 0x30 && cp <= 0x39) ||
        (cp >= 0x41 && cp <= 0x5A) ||
        (cp >= 0x61 && cp <= 0x7A);
  }

  static bool _needsCjkAsciiGap(int leftCp, int rightCp) {
    return (_isCjkIdeograph(leftCp) && _isAsciiAlphaNum(rightCp)) ||
        (_isAsciiAlphaNum(leftCp) && _isCjkIdeograph(rightCp));
  }

  @override
  bool shouldRepaint(covariant ReaderPagePainter oldDelegate) {
    return oldDelegate.leftPage != leftPage ||
        oldDelegate.rightPage != rightPage ||
        oldDelegate.config != config ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.secondaryTextColor != secondaryTextColor ||
        oldDelegate.dividerColor != dividerColor ||
        oldDelegate.headerText != headerText ||
        oldDelegate.footerLeftText != footerLeftText ||
        oldDelegate.footerRightText != footerRightText ||
        oldDelegate.contentTopOffset != contentTopOffset;
  }
}

class _GlyphKey {
  const _GlyphKey({
    required this.glyph,
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeightValue,
    required this.height,
    required this.colorArgb,
  });

  final String glyph;
  final String? fontFamily;
  final double fontSize;
  final int fontWeightValue;
  final double height;
  final int colorArgb;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _GlyphKey &&
          runtimeType == other.runtimeType &&
          glyph == other.glyph &&
          fontFamily == other.fontFamily &&
          fontSize == other.fontSize &&
          fontWeightValue == other.fontWeightValue &&
          height == other.height &&
          colorArgb == other.colorArgb;

  @override
  int get hashCode => Object.hash(
    glyph,
    fontFamily,
    fontSize,
    fontWeightValue,
    height,
    colorArgb,
  );
}

class _GlyphPainterCache {
  static const int _maxEntries = 1024;
  final LinkedHashMap<_GlyphKey, TextPainter> _entries =
      LinkedHashMap<_GlyphKey, TextPainter>();

  TextPainter obtain({
    required String glyph,
    required String? fontFamily,
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
    required Color color,
  }) {
    final key = _GlyphKey(
      glyph: glyph,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeightValue: fontWeight.value,
      height: height,
      colorArgb: color.toARGB32(),
    );
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: height,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (_entries.length >= _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = painter;
    return painter;
  }
}
