import '../../domain/domain.dart';

/// Convenience `copyWith` extension on [ReaderTheme] without altering the
/// frozen pure-Dart `lib/domain/` entity.
extension ReaderThemeCopyX on ReaderTheme {
  ReaderTheme copyWith({
    String? id,
    String? name,
    bool? isBuiltin,
    bool? isDark,
    int? bgColor,
    int? textColor,
    int? secondaryTextColor,
    String? bgTexturePath,
    bool clearBgTexturePath = false,
    String? fontFamily,
    String? fontPath,
    bool clearFontPath = false,
    double? fontSize,
    int? fontWeight,
    double? lineHeight,
    double? paragraphSpacing,
    double? letterSpacing,
    int? paragraphIndentChars,
    double? marginHorizontal,
    double? marginVertical,
    ColumnMode? columnMode,
    double? maxContentWidth,
    PageTurnMode? pageTurnMode,
    bool? enablePunctuationHanging,
    bool? enableCjkSpacing,
    DateTime? updatedAt,
  }) {
    return ReaderTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      isDark: isDark ?? this.isDark,
      bgColor: bgColor ?? this.bgColor,
      textColor: textColor ?? this.textColor,
      secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
      bgTexturePath:
          clearBgTexturePath ? null : (bgTexturePath ?? this.bgTexturePath),
      fontFamily: fontFamily ?? this.fontFamily,
      fontPath: clearFontPath ? null : (fontPath ?? this.fontPath),
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      paragraphIndentChars: paragraphIndentChars ?? this.paragraphIndentChars,
      marginHorizontal: marginHorizontal ?? this.marginHorizontal,
      marginVertical: marginVertical ?? this.marginVertical,
      columnMode: columnMode ?? this.columnMode,
      maxContentWidth: maxContentWidth ?? this.maxContentWidth,
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      enablePunctuationHanging:
          enablePunctuationHanging ?? this.enablePunctuationHanging,
      enableCjkSpacing: enableCjkSpacing ?? this.enableCjkSpacing,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Default built-in reader themes used as initial/fallback presets when no
/// persistent database themes are seeded yet.
List<ReaderTheme> buildDefaultReaderThemes({DateTime? timestamp}) {
  final now = timestamp ?? DateTime.utc(2026, 1, 1);
  return <ReaderTheme>[
    ReaderTheme(
      id: 'eye_care_ivory',
      name: '米白护眼',
      isBuiltin: true,
      isDark: false,
      bgColor: 0xFFF7F4EC,
      textColor: 0xFF2C2A26,
      secondaryTextColor: 0xFF78736A,
      updatedAt: now,
    ),
    ReaderTheme(
      id: 'parchment_warm',
      name: '羊皮纸感',
      isBuiltin: true,
      isDark: false,
      bgColor: 0xFFF2E6CE,
      textColor: 0xFF3A2F23,
      secondaryTextColor: 0xFF7D6E5C,
      updatedAt: now,
    ),
    ReaderTheme(
      id: 'slate_night',
      name: '静谧暗灰',
      isBuiltin: true,
      isDark: true,
      bgColor: 0xFF1E2022,
      textColor: 0xFFCFCFCF,
      secondaryTextColor: 0xFF8C9299,
      updatedAt: now,
    ),
    ReaderTheme(
      id: 'oled_pure_black',
      name: 'OLED 纯黑',
      isBuiltin: true,
      isDark: true,
      bgColor: 0xFF000000,
      textColor: 0xFFB8B8B8,
      secondaryTextColor: 0xFF6E6E6E,
      updatedAt: now,
    ),
  ];
}
