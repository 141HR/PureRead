/// Layout column strategy for adaptive single/dual-column reading.
enum ColumnMode { auto, single, double }

/// Page transition animation strategy.
enum PageTurnMode { none, slide, cover, scroll, simulation }

/// Immutable typography and geometry configuration consumed by [ReaderPaginator].
class PaginationConfig {
  /// Single logical column width. In two-column mode, equals
  /// `(viewportWidth - columnGap) / 2`.
  final double columnWidth;
  final double columnHeight;

  /// Number of logical columns rendered side by side (1 or 2).
  final int columnCount;
  final double columnGap;

  final String fontFamily;
  final String? fontFilePath;
  final double fontSize;
  final int fontWeightValue;
  final double lineHeightMultiplier;
  final double paragraphSpacing;
  final double letterSpacing;
  final int paragraphIndentChars;
  final bool enablePunctuationHanging;
  final bool enableCjkSpacing;

  const PaginationConfig({
    required this.columnWidth,
    required this.columnHeight,
    this.columnCount = 1,
    this.columnGap = 32.0,
    this.fontFamily = 'system',
    this.fontFilePath,
    this.fontSize = 18.0,
    this.fontWeightValue = 400,
    this.lineHeightMultiplier = 1.65,
    this.paragraphSpacing = 12.0,
    this.letterSpacing = 0.2,
    this.paragraphIndentChars = 2,
    this.enablePunctuationHanging = true,
    this.enableCjkSpacing = true,
  });

  PaginationConfig copyWith({
    double? columnWidth,
    double? columnHeight,
    int? columnCount,
    double? columnGap,
    String? fontFamily,
    String? fontFilePath,
    bool clearFontFilePath = false,
    double? fontSize,
    int? fontWeightValue,
    double? lineHeightMultiplier,
    double? paragraphSpacing,
    double? letterSpacing,
    int? paragraphIndentChars,
    bool? enablePunctuationHanging,
    bool? enableCjkSpacing,
  }) {
    return PaginationConfig(
      columnWidth: columnWidth ?? this.columnWidth,
      columnHeight: columnHeight ?? this.columnHeight,
      columnCount: columnCount ?? this.columnCount,
      columnGap: columnGap ?? this.columnGap,
      fontFamily: fontFamily ?? this.fontFamily,
      fontFilePath:
          clearFontFilePath ? null : (fontFilePath ?? this.fontFilePath),
      fontSize: fontSize ?? this.fontSize,
      fontWeightValue: fontWeightValue ?? this.fontWeightValue,
      lineHeightMultiplier: lineHeightMultiplier ?? this.lineHeightMultiplier,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      paragraphIndentChars: paragraphIndentChars ?? this.paragraphIndentChars,
      enablePunctuationHanging:
          enablePunctuationHanging ?? this.enablePunctuationHanging,
      enableCjkSpacing: enableCjkSpacing ?? this.enableCjkSpacing,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaginationConfig &&
          runtimeType == other.runtimeType &&
          columnWidth == other.columnWidth &&
          columnHeight == other.columnHeight &&
          columnCount == other.columnCount &&
          columnGap == other.columnGap &&
          fontFamily == other.fontFamily &&
          fontFilePath == other.fontFilePath &&
          fontSize == other.fontSize &&
          fontWeightValue == other.fontWeightValue &&
          lineHeightMultiplier == other.lineHeightMultiplier &&
          paragraphSpacing == other.paragraphSpacing &&
          letterSpacing == other.letterSpacing &&
          paragraphIndentChars == other.paragraphIndentChars &&
          enablePunctuationHanging == other.enablePunctuationHanging &&
          enableCjkSpacing == other.enableCjkSpacing;

  @override
  int get hashCode => Object.hash(
        columnWidth,
        columnHeight,
        columnCount,
        columnGap,
        fontFamily,
        fontFilePath,
        fontSize,
        fontWeightValue,
        lineHeightMultiplier,
        paragraphSpacing,
        letterSpacing,
        paragraphIndentChars,
        enablePunctuationHanging,
        enableCjkSpacing,
      );
}
