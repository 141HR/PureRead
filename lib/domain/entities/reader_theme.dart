import '../value_objects/pagination_config.dart';

/// Reader theme and typography preset corresponding to `reader_themes`.
///
/// Colors are stored as 32-bit ARGB integers (e.g. `0xFFF5F0E6`) to keep the
/// domain layer pure Dart with zero UI framework dependencies.
class ReaderTheme {
  final String id;
  final String name;
  final bool isBuiltin;
  final bool isDark;
  final int bgColor;
  final int textColor;
  final int secondaryTextColor;
  final String? bgTexturePath;
  final String fontFamily;
  final String? fontPath;
  final double fontSize;
  final int fontWeight;
  final double lineHeight;
  final double paragraphSpacing;
  final double letterSpacing;
  final int paragraphIndentChars;
  final double marginHorizontal;
  final double marginVertical;
  final ColumnMode columnMode;
  final double maxContentWidth;
  final PageTurnMode pageTurnMode;
  final bool enablePunctuationHanging;
  final bool enableCjkSpacing;
  final DateTime updatedAt;

  const ReaderTheme({
    required this.id,
    required this.name,
    this.isBuiltin = false,
    this.isDark = false,
    required this.bgColor,
    required this.textColor,
    required this.secondaryTextColor,
    this.bgTexturePath,
    this.fontFamily = 'system',
    this.fontPath,
    this.fontSize = 18.0,
    this.fontWeight = 400,
    this.lineHeight = 1.65,
    this.paragraphSpacing = 12.0,
    this.letterSpacing = 0.2,
    this.paragraphIndentChars = 2,
    this.marginHorizontal = 20.0,
    this.marginVertical = 24.0,
    this.columnMode = ColumnMode.auto,
    this.maxContentWidth = 760.0,
    this.pageTurnMode = PageTurnMode.cover,
    this.enablePunctuationHanging = true,
    this.enableCjkSpacing = true,
    required this.updatedAt,
  });

  /// Builds a [PaginationConfig] for the resolved logical column geometry.
  PaginationConfig toPaginationConfig({
    required double columnWidth,
    required double columnHeight,
    required int columnCount,
    double columnGap = 32.0,
  }) {
    return PaginationConfig(
      columnWidth: columnWidth,
      columnHeight: columnHeight,
      columnCount: columnCount,
      columnGap: columnGap,
      fontFamily: fontFamily,
      fontFilePath: fontPath,
      fontSize: fontSize,
      fontWeightValue: fontWeight,
      lineHeightMultiplier: lineHeight,
      paragraphSpacing: paragraphSpacing,
      letterSpacing: letterSpacing,
      paragraphIndentChars: paragraphIndentChars,
      enablePunctuationHanging: enablePunctuationHanging,
      enableCjkSpacing: enableCjkSpacing,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderTheme &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          isBuiltin == other.isBuiltin &&
          isDark == other.isDark &&
          bgColor == other.bgColor &&
          textColor == other.textColor &&
          secondaryTextColor == other.secondaryTextColor &&
          bgTexturePath == other.bgTexturePath &&
          fontFamily == other.fontFamily &&
          fontPath == other.fontPath &&
          fontSize == other.fontSize &&
          fontWeight == other.fontWeight &&
          lineHeight == other.lineHeight &&
          paragraphSpacing == other.paragraphSpacing &&
          letterSpacing == other.letterSpacing &&
          paragraphIndentChars == other.paragraphIndentChars &&
          marginHorizontal == other.marginHorizontal &&
          marginVertical == other.marginVertical &&
          columnMode == other.columnMode &&
          maxContentWidth == other.maxContentWidth &&
          pageTurnMode == other.pageTurnMode &&
          enablePunctuationHanging == other.enablePunctuationHanging &&
          enableCjkSpacing == other.enableCjkSpacing &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        isBuiltin,
        isDark,
        bgColor,
        textColor,
        secondaryTextColor,
        bgTexturePath,
        fontFamily,
        fontPath,
        fontSize,
        fontWeight,
        lineHeight,
        paragraphSpacing,
        letterSpacing,
        paragraphIndentChars,
        marginHorizontal,
        marginVertical,
        columnMode,
        maxContentWidth,
        pageTurnMode,
        enablePunctuationHanging,
        enableCjkSpacing,
        updatedAt,
      ]);
}
