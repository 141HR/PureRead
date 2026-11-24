/// Chinese typesetting character classifiers:
/// - Kinsoku punctuation prohibition (避头尾禁则)
/// - CJK <-> ASCII alphanumeric micro-spacing classification
class ChineseTypesetting {
  const ChineseTypesetting._();

  /// Punctuation prohibited from starting a line (避头标点).
  static const Set<int> lineStartProhibitedCodeUnits = <int>{
    // Full-width Chinese closing/separating punctuation
    0xFF0C, // ，
    0x3002, // 。
    0xFF01, // ！
    0xFF1F, // ？
    0x3001, // 、
    0xFF1B, // ；
    0xFF1A, // ：
    0x300B, // 》
    0x300D, // 」
    0x300F, // 』
    0xFF09, // ）
    0x3011, // 】
    0x3015, // 〕
    0x3009, // 〉
    0x3017, // 〗
    0xFF5D, // ｝
    0x2019, // ’
    0x201D, // ”
    0x2026, // …
    0x2014, // —
    0xFF5E, // ～
    0x00B7, // ·
    0xFF0E, // ．
    0xFF05, // ％
    // Half-width closing/separating punctuation
    0x002C, // ,
    0x002E, // .
    0x0021, // !
    0x003F, // ?
    0x003B, // ;
    0x003A, // :
    0x0029, // )
    0x005D, // ]
    0x007D, // }
    0x003E, // >
  };

  /// Opening punctuation prohibited from ending a line alone (避尾标点).
  static const Set<int> lineEndProhibitedCodeUnits = <int>{
    0x300A, // 《
    0x300C, // 「
    0x300E, // 『
    0xFF08, // （
    0x3010, // 【
    0x3014, // 〔
    0x3008, // 〈
    0x3016, // 〖
    0xFF5B, // ｛
    0x2018, // ‘
    0x201C, // “
    0x0028, // (
    0x005B, // [
    0x007B, // {
    0x003C, // <
  };

  static bool isLineStartProhibited(int codePoint) =>
      lineStartProhibitedCodeUnits.contains(codePoint);

  static bool isLineEndProhibited(int codePoint) =>
      lineEndProhibitedCodeUnits.contains(codePoint);

  /// True for CJK ideographs (excluding fullwidth punctuation, which already
  /// carries built-in side bearings in CJK fonts).
  static bool isCjkIdeograph(int codePoint) {
    return (codePoint >= 0x4E00 && codePoint <= 0x9FFF) || // CJK Unified
        (codePoint >= 0x3400 && codePoint <= 0x4DBF) || // CJK Ext-A
        (codePoint >= 0xF900 && codePoint <= 0xFAFF) || // CJK Compat
        (codePoint >= 0x20000 && codePoint <= 0x2FA1F); // CJK Ext-B..F
  }

  static bool isAsciiAlphaNum(int codePoint) {
    return (codePoint >= 0x30 && codePoint <= 0x39) || // 0-9
        (codePoint >= 0x41 && codePoint <= 0x5A) || // A-Z
        (codePoint >= 0x61 && codePoint <= 0x7A); // a-z
  }

  /// Whether [codePoint] stays glued inside an ASCII token (e.g. `v3.13`, `A-01`).
  static bool isAsciiTokenContinuation(int codePoint) {
    return isAsciiAlphaNum(codePoint) ||
        codePoint == 0x2D || // -
        codePoint == 0x5F || // _
        codePoint == 0x2E; // .
  }

  /// True if a micro-gap should be rendered between [leftCodePoint] and
  /// [rightCodePoint] on the same line.
  static bool needsCjkAsciiGap(int leftCodePoint, int rightCodePoint) {
    return (isCjkIdeograph(leftCodePoint) && isAsciiAlphaNum(rightCodePoint)) ||
        (isAsciiAlphaNum(leftCodePoint) && isCjkIdeograph(rightCodePoint));
  }

  static bool isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  static int combineSurrogates(int high, int low) =>
      0x10000 + (((high - 0xD800) << 10) | (low - 0xDC00));
}
