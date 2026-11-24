import 'package:flutter/material.dart';

import 'incremental_paginator.dart';
import 'pagination_models.dart';

/// CustomPainter rendering either a single [PageSlice] or a two-column desktop
/// spread `(P_{2k}, P_{2k+1})`.
class ReaderPagePainter extends CustomPainter {
  ReaderPagePainter({
    required this.chapterText,
    required this.config,
    required this.metricsCache,
    required this.leftPage,
    this.rightPage,
    this.horizontalPadding = 24.0,
    this.verticalPadding = 24.0,
    this.textColor = const Color(0xFF2B2B2B),
    this.dividerColor = const Color(0x22000000),
  });

  final String chapterText;
  final PaginationConfig config;
  final TextPainterMetricsCache metricsCache;
  final PageSlice leftPage;
  final PageSlice? rightPage;
  final double horizontalPadding;
  final double verticalPadding;
  final Color textColor;
  final Color dividerColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintColumn(canvas, leftPage, Offset(horizontalPadding, verticalPadding));

    if (config.columnCount == 2) {
      final dividerX = horizontalPadding + config.columnWidth + config.columnGap / 2;
      final dividerPaint = Paint()
        ..color = dividerColor
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(dividerX, verticalPadding),
        Offset(dividerX, verticalPadding + config.columnHeight),
        dividerPaint,
      );

      if (rightPage != null) {
        _paintColumn(
          canvas,
          rightPage!,
          Offset(
            horizontalPadding + config.columnWidth + config.columnGap,
            verticalPadding,
          ),
        );
      }
    }
  }

  void _paintColumn(Canvas canvas, PageSlice page, Offset origin) {
    for (final line in page.lines) {
      if (line.startCharOffset == line.renderEndCharOffset) continue;
      final painter = metricsCache.buildLinePainter(
        line,
        chapterText,
        textColor: textColor,
      );
      painter.paint(canvas, Offset(origin.dx + line.dx, origin.dy + line.dy));
    }
  }

  @override
  bool shouldRepaint(covariant ReaderPagePainter oldDelegate) {
    return oldDelegate.leftPage != leftPage ||
        oldDelegate.rightPage != rightPage ||
        oldDelegate.chapterText != chapterText ||
        oldDelegate.config.typographyKey != config.typographyKey ||
        oldDelegate.textColor != textColor;
  }
}
