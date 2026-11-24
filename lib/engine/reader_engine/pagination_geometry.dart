import 'dart:math' as math;

import '../../domain/entities/reader_theme.dart';
import '../../domain/value_objects/pagination_config.dart';

/// Resolved layout geometry alongside the resulting [PaginationConfig].
class ResolvedPaginationGeometry {
  const ResolvedPaginationGeometry({
    required this.config,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.contentWidth,
    required this.contentHeight,
    required this.horizontalPadding,
    required this.topPadding,
    required this.bottomPadding,
  });

  final PaginationConfig config;
  final double viewportWidth;
  final double viewportHeight;
  final double contentWidth;
  final double contentHeight;

  /// Horizontal inset from the viewport edge to the first column's left edge.
  /// In single-column mode on wide screens, centers the `maxContentWidth` block.
  final double horizontalPadding;
  final double topPadding;
  final double bottomPadding;

  int get columnCount => config.columnCount;
  double get columnWidth => config.columnWidth;
  double get columnHeight => config.columnHeight;
  double get columnGap => config.columnGap;
}

/// Resolves viewport bounds and [ReaderTheme] settings into [PaginationConfig]
/// following architecture §4.2's single/two-column logical page equivalence.
class PaginationGeometryResolver {
  const PaginationGeometryResolver._();

  /// Minimum viewport width at which [ColumnMode.auto] enables two columns.
  static const double defaultTwoColumnBreakpoint = 840.0;

  /// Default horizontal gap between left and right columns in two-column mode.
  static const double defaultColumnGap = 32.0;

  static const double _minContentWidth = 60.0;
  static const double _minColumnWidth = 40.0;
  static const double _minColumnHeight = 60.0;

  /// Determines the effective column count (`1` or `2`) for [viewportWidth]
  /// and [columnMode].
  static int resolveColumnCount({
    required double viewportWidth,
    required ColumnMode columnMode,
    double twoColumnBreakpoint = defaultTwoColumnBreakpoint,
  }) {
    return switch (columnMode) {
      ColumnMode.single => 1,
      ColumnMode.double => 2,
      ColumnMode.auto => viewportWidth >= twoColumnBreakpoint ? 2 : 1,
    };
  }

  /// Resolves viewport dimensions and [theme] into a [PaginationConfig].
  static PaginationConfig resolve({
    required double viewportWidth,
    required double viewportHeight,
    required ReaderTheme theme,
    double headerHeight = 0.0,
    double footerHeight = 0.0,
    double columnGap = defaultColumnGap,
    double twoColumnBreakpoint = defaultTwoColumnBreakpoint,
  }) {
    return resolveLayout(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      theme: theme,
      headerHeight: headerHeight,
      footerHeight: footerHeight,
      columnGap: columnGap,
      twoColumnBreakpoint: twoColumnBreakpoint,
    ).config;
  }

  /// Resolves full column and centering geometry alongside [PaginationConfig].
  static ResolvedPaginationGeometry resolveLayout({
    required double viewportWidth,
    required double viewportHeight,
    required ReaderTheme theme,
    double headerHeight = 0.0,
    double footerHeight = 0.0,
    double columnGap = defaultColumnGap,
    double twoColumnBreakpoint = defaultTwoColumnBreakpoint,
  }) {
    final safeViewportW =
        viewportWidth.isFinite && viewportWidth > 0 ? viewportWidth : 360.0;
    final safeViewportH =
        viewportHeight.isFinite && viewportHeight > 0 ? viewportHeight : 640.0;
    final safeMarginH = theme.marginHorizontal.isFinite &&
            theme.marginHorizontal >= 0
        ? theme.marginHorizontal
        : 0.0;
    final safeMarginV =
        theme.marginVertical.isFinite && theme.marginVertical >= 0
            ? theme.marginVertical
            : 0.0;
    final safeHeaderH =
        headerHeight.isFinite && headerHeight >= 0 ? headerHeight : 0.0;
    final safeFooterH =
        footerHeight.isFinite && footerHeight >= 0 ? footerHeight : 0.0;
    final safeGap = columnGap.isFinite && columnGap >= 0 ? columnGap : 0.0;

    final availableWidth = math.max(
      _minContentWidth,
      safeViewportW - safeMarginH * 2,
    );
    final availableHeight = math.max(
      _minColumnHeight,
      safeViewportH - safeMarginV * 2 - safeHeaderH - safeFooterH,
    );

    final columnCount = resolveColumnCount(
      viewportWidth: safeViewportW,
      columnMode: theme.columnMode,
      twoColumnBreakpoint: twoColumnBreakpoint,
    );

    final double contentWidth;
    final double columnWidth;
    final double horizontalPadding;

    if (columnCount == 2) {
      contentWidth = availableWidth;
      columnWidth = math.max(
        _minColumnWidth,
        (contentWidth - safeGap) / 2,
      );
      horizontalPadding = math.max(0.0, (safeViewportW - contentWidth) / 2);
    } else {
      final maxW = theme.maxContentWidth.isFinite && theme.maxContentWidth > 0
          ? theme.maxContentWidth
          : availableWidth;
      contentWidth = math.max(
        _minContentWidth,
        math.min(availableWidth, maxW),
      );
      columnWidth = contentWidth;
      horizontalPadding = math.max(0.0, (safeViewportW - contentWidth) / 2);
    }

    final config = theme.toPaginationConfig(
      columnWidth: columnWidth,
      columnHeight: availableHeight,
      columnCount: columnCount,
      columnGap: safeGap,
    );

    return ResolvedPaginationGeometry(
      config: config,
      viewportWidth: safeViewportW,
      viewportHeight: safeViewportH,
      contentWidth: contentWidth,
      contentHeight: availableHeight,
      horizontalPadding: horizontalPadding,
      topPadding: safeMarginV + safeHeaderH,
      bottomPadding: safeMarginV + safeFooterH,
    );
  }
}
