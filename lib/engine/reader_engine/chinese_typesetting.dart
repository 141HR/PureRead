/// Ratio of `fontSize` inserted at CJK ideograph <-> ASCII alphanumeric
/// boundaries when `PaginationConfig.enableCjkSpacing` is enabled.
const double kCjkAsciiSpacingRatio = 0.2;

/// Chinese typography rules and UTF-16 safe boundary helpers:
/// - Line-start / line-end punctuation prohibition (避头尾禁则)
/// - CJK <-> ASCII alphanumeric micro-spacing classification
/// - Surrogate-pair and ASCII token integrity guards
class ChineseTypesetting {
  const ChineseTypesetting._();

  /// Ratio of `fontSize` inserted between CJK ideographs and ASCII alphanumerics.
  static const double kCjkAsciiSpacingRatio = 0.2;

  /// Punctuation prohibited from starting a line (避头标点).
  static const Set<int> lineStartProhibitedCodeUnits = <int>{
    // Full-width Chinese closing and separating punctuation
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
    0x2015, // ―
    0xFF5E, // ～
    0x00B7, // ·
    0xFF0E, // ．
    0xFF05, // ％
    0x301E, // 〞
    0x301F, // 〟
    0x2025, // ‥
    0x2032, // ′
    0x2033, // ″
    // Half-width closing and separating punctuation
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
    0x0025, // %
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
    0x301D, // 〝
    0x0028, // (
    0x005B, // [
    0x007B, // {
    0x003C, // <
  };

  static bool isLineStartProhibited(int codePoint) =>
      lineStartProhibitedCodeUnits.contains(codePoint);

  static bool isLineEndProhibited(int codePoint) =>
      lineEndProhibitedCodeUnits.contains(codePoint);

  /// True for CJK ideographs (excluding full-width punctuation, which already
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

  /// Whether [codePoint] remains glued inside an ASCII token (e.g. `v3.13`, `A-01`).
  static bool isAsciiTokenContinuation(int codePoint) {
    return isAsciiAlphaNum(codePoint) ||
        codePoint == 0x2D || // -
        codePoint == 0x5F || // _
        codePoint == 0x2E; // .
  }

  /// True if a CJK-ASCII micro-gap should appear between [leftCodePoint] and
  /// [rightCodePoint] on the same line.
  static bool needsCjkAsciiGap(int leftCodePoint, int rightCodePoint) {
    return (isCjkIdeograph(leftCodePoint) && isAsciiAlphaNum(rightCodePoint)) ||
        (isAsciiAlphaNum(leftCodePoint) && isCjkIdeograph(rightCodePoint));
  }

  /// Computes the horizontal CJK-ASCII spacing gap in logical pixels.
  static double cjkAsciiGap(double fontSize, {bool enabled = true}) {
    if (!enabled || fontSize <= 0) return 0.0;
    return fontSize * kCjkAsciiSpacingRatio;
  }

  static bool isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  static int combineSurrogates(int high, int low) =>
      0x10000 + (((high - 0xD800) << 10) | (low - 0xDC00));

  /// Reads the Unicode code point starting at UTF-16 [index] within `[0, limit)`.
  static int codePointAt(String text, int index, [int? limit]) {
    final end = limit ?? text.length;
    final cu = text.codeUnitAt(index);
    if (isHighSurrogate(cu) && index + 1 < end) {
      final low = text.codeUnitAt(index + 1);
      if (isLowSurrogate(low)) {
        return combineSurrogates(cu, low);
      }
    }
    return cu;
  }

  /// Reads the Unicode code point ending immediately before UTF-16 [index]
  /// within `[start, text.length)`.
  static int codePointBefore(String text, int index, [int start = 0]) {
    final cu = text.codeUnitAt(index - 1);
    if (isLowSurrogate(cu) && index - 2 >= start) {
      final high = text.codeUnitAt(index - 2);
      if (isHighSurrogate(high)) {
        return combineSurrogates(high, cu);
      }
    }
    return cu;
  }

  /// Advances one Unicode code point forward from [index], clamped at [limit].
  static int stepForward(String text, int index, [int? limit]) {
    final end = limit ?? text.length;
    if (index >= end) return end;
    final cu = text.codeUnitAt(index);
    if (isHighSurrogate(cu) &&
        index + 1 < end &&
        isLowSurrogate(text.codeUnitAt(index + 1))) {
      return index + 2;
    }
    return index + 1;
  }

  /// Steps one Unicode code point backward before [index], bounded by [start].
  static int stepBackward(String text, int index, [int start = 0]) {
    if (index <= start) return start;
    if (index - 2 >= start &&
        isLowSurrogate(text.codeUnitAt(index - 1)) &&
        isHighSurrogate(text.codeUnitAt(index - 2))) {
      return index - 2;
    }
    return index - 1;
  }

  /// Returns UTF-16 offsets inside `[start, end)` of the left character at each
  /// CJK<->ASCII boundary where a micro-gap applies.
  static List<int> findCjkAsciiGapOffsets(
    String text, {
    int start = 0,
    int? end,
  }) {
    final limit = end ?? text.length;
    if (start >= limit) return const <int>[];

    final gaps = <int>[];
    var pos = start;
    var prevPos = -1;
    var prevCp = -1;

    while (pos < limit) {
      final cp = codePointAt(text, pos, limit);
      final nextPos = stepForward(text, pos, limit);
      if (prevCp != -1 && needsCjkAsciiGap(prevCp, cp)) {
        gaps.add(prevPos);
      }
      prevPos = pos;
      prevCp = cp;
      pos = nextPos;
    }

    return gaps;
  }

  /// Pulls a candidate line-wrap offset backward to obey Chinese 避头尾禁则 while
  /// preserving UTF-16 surrogate pairs, whole ASCII tokens, and forward progress
  /// under pathological all-punctuation runs.
  static int resolveLineBreakOffset({
    required String text,
    required int lineStart,
    required int candidateEnd,
    required int paragraphRenderEnd,
    int maxBacktrackSteps = 32,
  }) {
    if (candidateEnd >= paragraphRenderEnd) {
      return paragraphRenderEnd;
    }
    if (candidateEnd <= lineStart) {
      return stepForward(text, lineStart, paragraphRenderEnd);
    }

    // Ensure candidateEnd never splits a UTF-16 surrogate pair.
    var safeCandidate = candidateEnd;
    if (safeCandidate > lineStart &&
        safeCandidate < paragraphRenderEnd &&
        isLowSurrogate(text.codeUnitAt(safeCandidate)) &&
        isHighSurrogate(text.codeUnitAt(safeCandidate - 1))) {
      safeCandidate--;
      if (safeCandidate <= lineStart) {
        return stepForward(text, lineStart, paragraphRenderEnd);
      }
    }

    var adjusted = safeCandidate;
    var steps = 0;

    while (adjusted > lineStart && steps < maxBacktrackSteps) {
      final nextCp = codePointAt(text, adjusted, paragraphRenderEnd);
      final prevCp = codePointBefore(text, adjusted, lineStart);

      final violatesStart = isLineStartProhibited(nextCp);
      final violatesEnd = isLineEndProhibited(prevCp);

      if (!violatesStart && !violatesEnd) {
        return adjusted;
      }

      // Step backward by 1 code point (or 1 whole ASCII word token).
      var nextBack = stepBackward(text, adjusted, lineStart);
      if (isAsciiAlphaNum(prevCp)) {
        while (nextBack > lineStart &&
            isAsciiTokenContinuation(text.codeUnitAt(nextBack - 1))) {
          nextBack--;
        }
      }

      // Guard against empty lines or pathological all-punctuation sequences.
      if (nextBack <= lineStart) {
        return safeCandidate;
      }

      adjusted = nextBack;
      steps++;
    }

    final nextCp = codePointAt(text, adjusted, paragraphRenderEnd);
    final prevCp = codePointBefore(text, adjusted, lineStart);
    if (isLineStartProhibited(nextCp) || isLineEndProhibited(prevCp)) {
      return safeCandidate;
    }
    return adjusted;
  }
}
