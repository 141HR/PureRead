import 'dart:math' as math;

import '../../domain/domain.dart';

/// Minimum similarity score required for automatic chapter-title matching
/// without requiring manual fallback selection.
const double kConfidentChapterMatchThreshold = 0.72;

/// Result of matching a target chapter title against a candidate source's TOC.
class ChapterMatchResult {
  final int? matchedIndex;
  final ChapterMeta? matchedChapter;
  final double score;
  final bool isExact;
  final bool isConfident;

  const ChapterMatchResult({
    required this.matchedIndex,
    required this.matchedChapter,
    required this.score,
    required this.isExact,
    required this.isConfident,
  });
}

/// Normalizes chapter titles and computes similarity scores across sources.
abstract final class ChapterTitleMatcher {
  static final RegExp _leadingNoiseRe = RegExp(
    r'^(?:正文卷|正文|vip卷|最新章节|免费章节)\s*',
    caseSensitive: false,
  );
  static final RegExp _trailingBracketsRe = RegExp(
    r'[\(（\[【][^\)）\]】]{0,24}[\)）\]】]\s*$',
  );
  static final RegExp _chapterPrefixRe = RegExp(
    r'^(?:第\s*)?([0-9]+|[零〇一二两三四五六七八九十百千万]+)(?:\s*[章回节卷话集]|[\.、:：\-\s]+|$)',
  );
  static final RegExp _stripPunctRe = RegExp(
    r'''[\s\.\-_:,;!?/\\|~`@#$%^&*()+=\[\]{}<>'"，。！？、：；“”‘’（）【】《》—…]''',
  );

  /// Finds the best matching chapter in [candidates] for [targetTitle].
  static ChapterMatchResult findBestMatch(
    String targetTitle,
    List<ChapterMeta> candidates, {
    int? preferredIndex,
  }) {
    if (candidates.isEmpty) {
      return const ChapterMatchResult(
        matchedIndex: null,
        matchedChapter: null,
        score: 0.0,
        isExact: false,
        isConfident: false,
      );
    }

    var bestIndex = 0;
    var bestScore = -1.0;
    var bestDistance = 1 << 30;

    for (var i = 0; i < candidates.length; i++) {
      final score = scoreSimilarity(targetTitle, candidates[i].title);
      final distance = preferredIndex == null ? i : (i - preferredIndex).abs();
      if (score > bestScore + 1e-9 ||
          ((score - bestScore).abs() <= 1e-9 && distance < bestDistance)) {
        bestScore = score;
        bestIndex = i;
        bestDistance = distance;
      }
    }

    final clampedScore = bestScore.clamp(0.0, 1.0);
    return ChapterMatchResult(
      matchedIndex: bestIndex,
      matchedChapter: candidates[bestIndex],
      score: clampedScore,
      isExact: clampedScore >= 0.95,
      isConfident: clampedScore >= kConfidentChapterMatchThreshold,
    );
  }

  /// Normalizes a chapter title by converting full-width digits/letters to
  /// ASCII, converting Chinese chapter numbers, and stripping decorative noise.
  static String normalizeTitle(String rawTitle) {
    var text = _toHalfWidth(rawTitle).trim().toLowerCase();
    text = text.replaceFirst(_leadingNoiseRe, '').trim();
    text = text.replaceFirst(_trailingBracketsRe, '').trim();
    final parsed = _extractParts(text);
    final numPart = parsed.chapterNumber;
    final bodyPart = _stripPunct(parsed.body);
    if (numPart != null) {
      return '$numPart:$bodyPart';
    }
    return _stripPunct(text);
  }

  /// Computes normalized title similarity in `[0.0, 1.0]`.
  static double scoreSimilarity(String a, String b) {
    final normA = normalizeTitle(a);
    final normB = normalizeTitle(b);
    if (normA.isEmpty || normB.isEmpty) return 0.0;
    if (normA == normB) return 1.0;

    final partsA = _extractParts(_cleanBase(a));
    final partsB = _extractParts(_cleanBase(b));
    final bodyA = _stripPunct(partsA.body);
    final bodyB = _stripPunct(partsB.body);

    if (partsA.chapterNumber != null && partsB.chapterNumber != null) {
      if (partsA.chapterNumber == partsB.chapterNumber) {
        if (bodyA.isNotEmpty && bodyB.isNotEmpty) {
          if (bodyA == bodyB) return 0.98;
          if (bodyA.contains(bodyB) || bodyB.contains(bodyA)) {
            final minLen = math.min(bodyA.length, bodyB.length);
            final maxLen = math.max(bodyA.length, bodyB.length);
            return 0.86 + 0.10 * (minLen / maxLen);
          }
          return 0.65 + 0.30 * _bigramDice(bodyA, bodyB);
        }
        return 0.85;
      }

      // Different chapter numbers: still catch offset chapters when body title
      // matches cleanly (e.g. a site shifted numbering due to an extra preface).
      if (bodyA.length >= 2 && bodyB.length >= 2 && bodyA == bodyB) {
        return 0.88;
      }
      if (bodyA.isNotEmpty && bodyB.isNotEmpty) {
        return 0.35 * _bigramDice(bodyA, bodyB);
      }
      return 0.0;
    }

    final plainA = _stripPunct(_cleanBase(a));
    final plainB = _stripPunct(_cleanBase(b));
    if (plainA == plainB) return 0.96;
    if (plainA.isEmpty || plainB.isEmpty) return 0.0;
    if (plainA.contains(plainB) || plainB.contains(plainA)) {
      final ratio =
          math.min(plainA.length, plainB.length) /
          math.max(plainA.length, plainB.length);
      return 0.68 + 0.28 * ratio;
    }
    return _bigramDice(plainA, plainB);
  }

  /// Parses an Arabic or Chinese numeral string into an integer if valid.
  static int? parseChapterNumberToken(String token) {
    final clean = _toHalfWidth(token).trim();
    if (clean.isEmpty) return null;
    final arabic = int.tryParse(clean);
    if (arabic != null) return arabic;
    return _parseChineseNumeral(clean);
  }

  static String _cleanBase(String raw) {
    var text = _toHalfWidth(raw).trim().toLowerCase();
    text = text.replaceFirst(_leadingNoiseRe, '').trim();
    text = text.replaceFirst(_trailingBracketsRe, '').trim();
    return text;
  }

  static ({int? chapterNumber, String body}) _extractParts(String cleaned) {
    final match = _chapterPrefixRe.firstMatch(cleaned);
    if (match == null) {
      return (chapterNumber: null, body: cleaned);
    }
    final numToken = match.group(1) ?? '';
    final parsed = parseChapterNumberToken(numToken);
    if (parsed == null) {
      return (chapterNumber: null, body: cleaned);
    }
    final remainder = cleaned.substring(match.end).trim();
    return (chapterNumber: parsed, body: remainder);
  }

  static String _stripPunct(String input) =>
      input.replaceAll(_stripPunctRe, '');

  static String _toHalfWidth(String input) {
    final buffer = StringBuffer();
    for (final code in input.codeUnits) {
      if (code == 0x3000) {
        buffer.writeCharCode(0x20);
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        buffer.writeCharCode(code - 0xFEE0);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  static int? _parseChineseNumeral(String input) {
    const digits = <String, int>{
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    const units = <String, int>{
      '十': 10,
      '百': 100,
      '千': 1000,
    };

    var section = 0;
    var current = 0;
    var hasToken = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      final digit = digits[ch];
      if (digit != null) {
        current = digit;
        hasToken = true;
        continue;
      }
      final unit = units[ch];
      if (unit != null) {
        final factor = current == 0 && !hasToken ? 1 : (current == 0 ? 1 : current);
        section += factor * unit;
        current = 0;
        hasToken = true;
        continue;
      }
      if (ch == '万') {
        section = (section + current) * 10000;
        current = 0;
        hasToken = true;
        continue;
      }
      return null;
    }

    if (!hasToken) return null;
    return section + current;
  }

  static double _bigramDice(String a, String b) {
    if (a == b) return 1.0;
    if (a.length < 2 || b.length < 2) {
      return _charOverlap(a, b);
    }

    final bigramsA = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final gram = a.substring(i, i + 2);
      bigramsA[gram] = (bigramsA[gram] ?? 0) + 1;
    }

    var intersection = 0;
    final totalB = b.length - 1;
    for (var i = 0; i < totalB; i++) {
      final gram = b.substring(i, i + 2);
      final count = bigramsA[gram] ?? 0;
      if (count > 0) {
        intersection++;
        bigramsA[gram] = count - 1;
      }
    }

    final dice = (2.0 * intersection) / ((a.length - 1) + totalB);
    return math.max(dice, 0.5 * _charOverlap(a, b));
  }

  static double _charOverlap(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final setA = a.runes.toSet();
    final setB = b.runes.toSet();
    final common = setA.intersection(setB).length;
    return (2.0 * common) / (setA.length + setB.length);
  }
}
