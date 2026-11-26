import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';

import '../../application/reader/epub_image_cache.dart';
import '../../domain/domain.dart';
import '../../engine/reader_engine/inline_image_marker.dart';
import '../../engine/reader_engine/platform_font_resolver.dart';

/// Hit-test payload returned by [ReaderPagePainter.hitTestImage] when a pointer
/// tap intersects an inline EPUB illustration.
typedef InlineImageHit = ({InlineImageRef ref, Rect rect});

/// CustomPainter rendering one [PageSlice] (single-column) or a paired spread
/// `(P_{2k}, P_{2k+1})` (two-column), with theme background, subtle procedural
/// paper-grain texture, 2-column book-spine shadow, CJK-ASCII `0.2em`
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
    this.enablePaperGrain = true,
    this.enableSpineShadow = true,
    this.epubImageCache,
    this.book,
    this.ttsHighlightChapterIndex,
    this.ttsHighlightStartOffset,
    this.ttsHighlightEndOffset,
    this.ttsHighlightColor,
  }) : super(repaint: epubImageCache);

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
  final bool enablePaperGrain;
  final bool enableSpineShadow;
  final EpubImageCache? epubImageCache;
  final Book? book;
  final int? ttsHighlightChapterIndex;
  final int? ttsHighlightStartOffset;
  final int? ttsHighlightEndOffset;
  final Color? ttsHighlightColor;

  static final _GlyphPainterCache _glyphCache = _GlyphPainterCache();
  static final _PaperGrainBuffers _paperGrain = _PaperGrainBuffers.generate();
  static final _SpineShaderCache _spineShaderCache = _SpineShaderCache();

  static final Paint _bgPaint = Paint();
  static final Paint _warmGrainPaint = Paint()
    ..strokeWidth = 1.0
    ..strokeCap = ui.StrokeCap.round;
  static final Paint _coolGrainPaint = Paint()
    ..strokeWidth = 1.0
    ..strokeCap = ui.StrokeCap.round;
  static final Paint _fiberPaint = Paint()
    ..strokeWidth = 0.65
    ..style = PaintingStyle.stroke;
  static final Paint _spineShadowPaint = Paint();
  static final Paint _dividerPaint = Paint()..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor != null) {
      _bgPaint.color = backgroundColor!;
      canvas.drawRect(Offset.zero & size, _bgPaint);
    }

    _paintPaperGrain(canvas, size);

    final effectiveFontFamily = resolvePlatformFontFamily(config.fontFamily);
    final effectiveFontFallback = resolvePlatformFontFamilyFallback();
    final regularWeight = _resolveFontWeight(config.fontWeightValue);

    final baseStyle = TextStyle(
      fontFamily: effectiveFontFamily,
      fontFamilyFallback: effectiveFontFallback,
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
        fontFamilyFallback: effectiveFontFallback,
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
          effectiveFontFallback: effectiveFontFallback,
        );
      }

      final dividerX = leftOriginX + config.columnWidth + config.columnGap / 2;
      _paintSpineShadow(canvas, size, dividerX: dividerX);
      _dividerPaint.color = dividerColor ?? secondaryTextColor.withAlpha(46);
      canvas.drawLine(
        Offset(dividerX, topY),
        Offset(dividerX, topY + config.columnHeight),
        _dividerPaint,
      );

      if (rightPage != null) {
        _paintSlice(
          canvas,
          rightPage!,
          Offset(rightOriginX, topY),
          baseStyle: baseStyle,
          effectiveFontFamily: effectiveFontFamily,
          effectiveFontFallback: effectiveFontFallback,
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
        effectiveFontFallback: effectiveFontFallback,
      );
    }

    if (footerLeftText != null && footerLeftText!.isNotEmpty) {
      _paintChromeText(
        canvas,
        text: footerLeftText!,
        offset: Offset(16, math.max(0.0, size.height - 24)),
        maxWidth: math.max(40.0, size.width * 0.5 - 24),
        fontFamily: effectiveFontFamily,
        fontFamilyFallback: effectiveFontFallback,
      );
    }
    if (footerRightText != null && footerRightText!.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: footerRightText!,
          style: TextStyle(
            fontFamily: effectiveFontFamily,
            fontFamilyFallback: effectiveFontFallback,
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

  void _paintPaperGrain(Canvas canvas, Size size) {
    if (!enablePaperGrain ||
        backgroundColor == null ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0.0 ||
        size.height <= 0.0) {
      return;
    }

    final luminance = backgroundColor!.computeLuminance();
    if (luminance < 0.02) {
      _warmGrainPaint.color = const Color(0x05FFFFFF);
      _coolGrainPaint.color = const Color(0x03D8D0C0);
      _fiberPaint.color = const Color(0x04FFFFFF);
    } else if (luminance < 0.3) {
      _warmGrainPaint.color = const Color(0x08FFF6E5);
      _coolGrainPaint.color = const Color(0x0A000000);
      _fiberPaint.color = const Color(0x06FFFFFF);
    } else {
      _warmGrainPaint.color = const Color(0x0B8C6D46);
      _coolGrainPaint.color = const Color(0x082A3442);
      _fiberPaint.color = const Color(0x06705C42);
    }

    const tile = _PaperGrainBuffers.tileSize;
    final cols = (size.width / tile).ceil().clamp(0, 24);
    final rows = (size.height / tile).ceil().clamp(0, 24);
    if (cols == 0 || rows == 0) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    var curX = 0.0;
    var curY = 0.0;
    for (var row = 0; row < rows; row++) {
      final ty = row * tile;
      for (var col = 0; col < cols; col++) {
        final tx = col * tile;
        final dx = tx - curX;
        final dy = ty - curY;
        if (dx != 0.0 || dy != 0.0) {
          canvas.translate(dx, dy);
          curX = tx;
          curY = ty;
        }
        canvas.drawRawPoints(
          ui.PointMode.points,
          _paperGrain.warmSpecks,
          _warmGrainPaint,
        );
        canvas.drawRawPoints(
          ui.PointMode.points,
          _paperGrain.coolSpecks,
          _coolGrainPaint,
        );
        canvas.drawRawPoints(
          ui.PointMode.lines,
          _paperGrain.fiberLines,
          _fiberPaint,
        );
      }
    }
    canvas.restore();
  }

  void _paintSpineShadow(
    Canvas canvas,
    Size size, {
    required double dividerX,
  }) {
    if (!enableSpineShadow ||
        config.columnCount != 2 ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0.0 ||
        size.height <= 0.0) {
      return;
    }

    final halfWidth = math.max(18.0, config.columnGap * 0.92).clamp(16.0, 44.0);
    final isDark = (backgroundColor?.computeLuminance() ?? 1.0) < 0.3;
    final leftX = dividerX - halfWidth;
    final rightX = dividerX + halfWidth;

    _spineShadowPaint.shader = _spineShaderCache.obtain(
      leftX: leftX,
      rightX: rightX,
      isDark: isDark,
    );
    canvas.drawRect(
      Rect.fromLTWH(leftX, 0.0, halfWidth * 2.0, size.height),
      _spineShadowPaint,
    );
  }

  /// Computes the painted image bounds for an inline image [LayoutLine] inside
  /// a slice positioned at [sliceOrigin].
  static Rect computeImageRect({
    required Offset sliceOrigin,
    required LayoutLine line,
  }) {
    final vPad = line.height > 14.0 ? 6.0 : 0.0;
    final drawH = math.max(1.0, line.height - vPad * 2);
    return Rect.fromLTWH(
      sliceOrigin.dx + line.x,
      sliceOrigin.dy + line.y + vPad,
      math.max(1.0, line.width),
      drawH,
    );
  }

  /// Pure geometric hit-test locating an inline EPUB image under
  /// [localPosition] inside a canvas of [size].
  static InlineImageHit? hitTestImage({
    required Offset localPosition,
    required Size size,
    required PaginationConfig config,
    required PageSlice? leftPage,
    required PageSlice? rightPage,
    double contentTopOffset = 0.0,
  }) {
    final topY = contentTopOffset;
    if (config.columnCount == 2) {
      final spreadWidth = config.columnWidth * 2 + config.columnGap;
      final leftOriginX = math.max(0.0, (size.width - spreadWidth) / 2);
      final rightOriginX = leftOriginX + config.columnWidth + config.columnGap;
      if (leftPage != null) {
        final hit = _hitTestSlice(
          localPosition,
          leftPage,
          Offset(leftOriginX, topY),
        );
        if (hit != null) return hit;
      }
      if (rightPage != null) {
        return _hitTestSlice(
          localPosition,
          rightPage,
          Offset(rightOriginX, topY),
        );
      }
      return null;
    }

    if (leftPage == null) return null;
    final originX = math.max(0.0, (size.width - config.columnWidth) / 2);
    return _hitTestSlice(localPosition, leftPage, Offset(originX, topY));
  }

  static InlineImageHit? _hitTestSlice(
    Offset localPosition,
    PageSlice slice,
    Offset origin,
  ) {
    for (final line in slice.lines) {
      final imageRef = InlineImageMarker.tryParseLine(line.text);
      if (imageRef == null) continue;
      final rect = computeImageRect(sliceOrigin: origin, line: line);
      if (rect.contains(localPosition)) {
        return (ref: imageRef, rect: rect);
      }
    }
    return null;
  }

  void _paintSlice(
    Canvas canvas,
    PageSlice slice,
    Offset origin, {
    required TextStyle baseStyle,
    required String? effectiveFontFamily,
    required List<String>? effectiveFontFallback,
  }) {
    final hlStart = ttsHighlightStartOffset;
    final hlEnd = ttsHighlightEndOffset;
    if (ttsHighlightChapterIndex == slice.chapterIndex &&
        hlStart != null &&
        hlEnd != null &&
        hlStart < hlEnd) {
      _paintTtsHighlights(
        canvas,
        slice,
        origin,
        highlightStart: hlStart,
        highlightEnd: hlEnd,
      );
    }

    for (final line in slice.lines) {
      final imageRef = InlineImageMarker.tryParseLine(line.text);
      if (imageRef != null) {
        _paintInlineImage(
          canvas,
          origin,
          line,
          imageRef,
          effectiveFontFamily: effectiveFontFamily,
          effectiveFontFallback: effectiveFontFallback,
        );
        continue;
      }

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
          fontFamilyFallback: effectiveFontFallback,
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

  void _paintTtsHighlights(
    Canvas canvas,
    PageSlice slice,
    Offset origin, {
    required int highlightStart,
    required int highlightEnd,
  }) {
    final isDark = (backgroundColor?.computeLuminance() ?? 1.0) < 0.3;
    final color =
        ttsHighlightColor ??
        (isDark ? const Color(0x4882B1FF) : const Color(0x384A6B53));
    final highlightPaint = Paint()..color = color;

    for (final line in slice.lines) {
      if (InlineImageMarker.tryParseLine(line.text) != null) continue;
      final visibleText = trimTrailingLineBreaks(line.text);
      if (visibleText.isEmpty) continue;

      final visStart = line.startCharOffset;
      final visEnd = visStart + visibleText.length;
      final overlapStart = math.max(visStart, highlightStart);
      final overlapEnd = math.min(visEnd, highlightEnd);
      if (overlapStart >= overlapEnd) continue;

      final double leftX;
      final double rightX;
      final xOffsets = line.charXOffsets;
      if (xOffsets != null && xOffsets.isNotEmpty) {
        final localStart = overlapStart - visStart;
        final localEnd = overlapEnd - visStart;
        final startDx =
            localStart < xOffsets.length ? xOffsets[localStart] : line.width;
        final double endDx;
        if (localEnd >= visibleText.length) {
          endDx = math.max(startDx, line.width);
        } else if (localEnd < xOffsets.length) {
          var idx = localEnd;
          while (idx < xOffsets.length && xOffsets[idx] <= startDx) {
            idx++;
          }
          endDx = idx < xOffsets.length
              ? xOffsets[idx]
              : math.max(startDx, line.width);
        } else {
          endDx = math.max(startDx, line.width);
        }
        leftX = origin.dx + line.x + startDx;
        rightX = origin.dx + line.x + endDx;
      } else {
        if (line.width <= 0.0) continue;
        leftX = origin.dx + line.x;
        rightX = origin.dx + line.x + line.width;
      }

      if (rightX <= leftX) continue;
      final rect = Rect.fromLTRB(
        leftX - 2.0,
        origin.dy + line.y + 1.0,
        rightX + 2.0,
        origin.dy + line.y + math.max(2.0, line.height - 1.0),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4.0)),
        highlightPaint,
      );
    }
  }

  void _paintInlineImage(
    Canvas canvas,
    Offset origin,
    LayoutLine line,
    InlineImageRef imageRef, {
    required String? effectiveFontFamily,
    required List<String>? effectiveFontFallback,
  }) {
    final imageRect = computeImageRect(sliceOrigin: origin, line: line);
    final rrect = RRect.fromRectAndRadius(
      imageRect,
      const Radius.circular(4.0),
    );
    final borderColor = (dividerColor ?? secondaryTextColor).withAlpha(56);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = borderColor;

    final cache = epubImageCache;
    final currentBook = book;
    ui.Image? decoded;
    var failed = false;

    if (cache != null && currentBook != null) {
      decoded = cache.getCached(currentBook.id, imageRef.archivePath);
      if (decoded == null) {
        failed = cache.isFailed(currentBook.id, imageRef.archivePath);
        if (!failed && !cache.isLoading(currentBook.id, imageRef.archivePath)) {
          unawaited(cache.loadImage(currentBook, imageRef.archivePath));
        }
      }
    }

    if (decoded != null) {
      canvas.save();
      canvas.clipRRect(rrect);
      paintImage(
        canvas: canvas,
        rect: imageRect,
        image: decoded,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();
      canvas.drawRRect(rrect, borderPaint);
      return;
    }

    final bg = backgroundColor;
    final isDark = (bg?.computeLuminance() ?? 1.0) < 0.3;
    final fillColor = bg != null
        ? Color.lerp(
            bg,
            isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
            isDark ? 0.07 : 0.04,
          )!
        : const Color(0x14808080);

    final fillPaint = Paint()..color = fillColor;
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    if (imageRect.width >= 40.0 && imageRect.height >= 26.0) {
      final label = failed
          ? '图片加载失败'
          : (imageRef.alt.isNotEmpty ? imageRef.alt : '图片加载中…');
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: effectiveFontFamily,
            fontFamilyFallback: effectiveFontFallback,
            fontSize: 12,
            color: secondaryTextColor.withAlpha(failed ? 200 : 165),
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.max(16.0, imageRect.width - 16.0));
      canvas.save();
      canvas.clipRRect(rrect);
      tp.paint(
        canvas,
        Offset(
          imageRect.left + (imageRect.width - tp.width) * 0.5,
          imageRect.top + (imageRect.height - tp.height) * 0.5,
        ),
      );
      canvas.restore();
    }
  }

  void _paintWithCharOffsets(
    Canvas canvas, {
    required String visibleText,
    required List<double> xOffsets,
    required Offset origin,
    required TextStyle style,
    required String? fontFamily,
    required List<String>? fontFamilyFallback,
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
        fontFamilyFallback: fontFamilyFallback,
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
    required List<String>? fontFamilyFallback,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
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
        oldDelegate.contentTopOffset != contentTopOffset ||
        oldDelegate.enablePaperGrain != enablePaperGrain ||
        oldDelegate.enableSpineShadow != enableSpineShadow ||
        oldDelegate.epubImageCache != epubImageCache ||
        oldDelegate.book != book ||
        oldDelegate.ttsHighlightChapterIndex != ttsHighlightChapterIndex ||
        oldDelegate.ttsHighlightStartOffset != ttsHighlightStartOffset ||
        oldDelegate.ttsHighlightEndOffset != ttsHighlightEndOffset ||
        oldDelegate.ttsHighlightColor != ttsHighlightColor;
  }
}

class _PaperGrainBuffers {
  const _PaperGrainBuffers({
    required this.warmSpecks,
    required this.coolSpecks,
    required this.fiberLines,
  });

  static const double tileSize = 192.0;

  final Float32List warmSpecks;
  final Float32List coolSpecks;
  final Float32List fiberLines;

  static _PaperGrainBuffers generate() {
    var seed = 0x50757265;
    double nextUnit() {
      seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
      return seed / 4294967296.0;
    }

    const speckCount = 220;
    final warm = Float32List(speckCount * 2);
    final cool = Float32List(speckCount * 2);
    for (var i = 0; i < speckCount; i++) {
      warm[i * 2] = nextUnit() * tileSize;
      warm[i * 2 + 1] = nextUnit() * tileSize;
      cool[i * 2] = nextUnit() * tileSize;
      cool[i * 2 + 1] = nextUnit() * tileSize;
    }

    const fiberCount = 44;
    final fibers = Float32List(fiberCount * 4);
    for (var i = 0; i < fiberCount; i++) {
      final x = nextUnit() * tileSize;
      final y = nextUnit() * tileSize;
      final angle = (nextUnit() - 0.5) * math.pi;
      final len = 4.0 + nextUnit() * 6.0;
      fibers[i * 4] = x;
      fibers[i * 4 + 1] = y;
      fibers[i * 4 + 2] = x + math.cos(angle) * len;
      fibers[i * 4 + 3] = y + math.sin(angle) * len;
    }

    return _PaperGrainBuffers(
      warmSpecks: warm,
      coolSpecks: cool,
      fiberLines: fibers,
    );
  }
}

class _SpineShaderCache {
  double? _lastLeftX;
  double? _lastRightX;
  bool? _lastIsDark;
  ui.Shader? _lastShader;

  static const List<Color> _lightColors = <Color>[
    Color(0x00000000),
    Color(0x0C241B10),
    Color(0x201E160D),
    Color(0x2A1A120A),
    Color(0x161E160D),
    Color(0x06FFFFFF),
    Color(0x00000000),
  ];

  static const List<Color> _darkColors = <Color>[
    Color(0x00000000),
    Color(0x1A000000),
    Color(0x3A000000),
    Color(0x48000000),
    Color(0x22000000),
    Color(0x0BFFFFFF),
    Color(0x00000000),
  ];

  static const List<double> _stops = <double>[
    0.0,
    0.28,
    0.44,
    0.50,
    0.58,
    0.74,
    1.0,
  ];

  ui.Shader obtain({
    required double leftX,
    required double rightX,
    required bool isDark,
  }) {
    final cached = _lastShader;
    if (cached != null &&
        _lastLeftX == leftX &&
        _lastRightX == rightX &&
        _lastIsDark == isDark) {
      return cached;
    }
    final shader = ui.Gradient.linear(
      Offset(leftX, 0.0),
      Offset(rightX, 0.0),
      isDark ? _darkColors : _lightColors,
      _stops,
    );
    _lastLeftX = leftX;
    _lastRightX = rightX;
    _lastIsDark = isDark;
    _lastShader = shader;
    return shader;
  }
}

class _GlyphKey {
  const _GlyphKey({
    required this.glyph,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.fontSize,
    required this.fontWeightValue,
    required this.height,
    required this.colorArgb,
  });

  final String glyph;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
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
          listEquals(fontFamilyFallback, other.fontFamilyFallback) &&
          fontSize == other.fontSize &&
          fontWeightValue == other.fontWeightValue &&
          height == other.height &&
          colorArgb == other.colorArgb;

  @override
  int get hashCode => Object.hash(
    glyph,
    fontFamily,
    Object.hashAll(fontFamilyFallback ?? const <String>[]),
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
    required List<String>? fontFamilyFallback,
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
    required Color color,
  }) {
    final key = _GlyphKey(
      glyph: glyph,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
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
          fontFamilyFallback: fontFamilyFallback,
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
