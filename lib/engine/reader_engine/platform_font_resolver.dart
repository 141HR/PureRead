import 'package:flutter/foundation.dart';

/// Primary CJK UI and reading fallback font family on Windows.
const String kWindowsPrimaryCjkFontFamily = 'Microsoft YaHei UI';

/// Ordered Windows CJK font fallback chain preventing mixed-weight fallback to
/// Japanese UI fonts such as Yu Gothic UI.
const List<String> kWindowsCjkFontFamilyFallback = <String>[
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'DengXian',
  'SimHei',
];

/// Resolves the effective `fontFamily` for text rendering on [targetPlatform]
/// (defaulting to [defaultTargetPlatform]).
///
/// Explicit non-system font names in [requestedFontFamily] are preserved as-is;
/// `'system'`, empty, or `null` requests resolve to
/// [kWindowsPrimaryCjkFontFamily] on Windows and `null` on other platforms.
String? resolvePlatformFontFamily(
  String? requestedFontFamily, {
  TargetPlatform? targetPlatform,
}) {
  if (requestedFontFamily != null &&
      requestedFontFamily.isNotEmpty &&
      requestedFontFamily != 'system') {
    return requestedFontFamily;
  }
  final platform = targetPlatform ?? defaultTargetPlatform;
  return platform == TargetPlatform.windows
      ? kWindowsPrimaryCjkFontFamily
      : null;
}

/// Resolves the platform-specific `fontFamilyFallback` list for [targetPlatform]
/// (defaulting to [defaultTargetPlatform]).
List<String>? resolvePlatformFontFamilyFallback({
  TargetPlatform? targetPlatform,
}) {
  final platform = targetPlatform ?? defaultTargetPlatform;
  return platform == TargetPlatform.windows
      ? kWindowsCjkFontFamilyFallback
      : null;
}
