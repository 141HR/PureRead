import 'dart:math' as math;

/// A single speakable sentence/clause slice referencing exact UTF-16 offsets in
/// the source chapter text.
class TtsUtterance {
  final int index;
  final int startCharOffset;
  final int endCharOffset;
  final String text;

  const TtsUtterance({
    required this.index,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.text,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsUtterance &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          startCharOffset == other.startCharOffset &&
          endCharOffset == other.endCharOffset &&
          text == other.text;

  @override
  int get hashCode =>
      Object.hash(index, startCharOffset, endCharOffset, text);

  @override
  String toString() =>
      'TtsUtterance(index: $index, [$startCharOffset, $endCharOffset), text: $text)';
}

/// Splits chapter text into speakable [TtsUtterance]s with exact UTF-16
/// `startCharOffset` / `endCharOffset` indices into the original chapter text.
///
/// - Skips EPUB inline image marker lines (`\uFFFCprimg:...\uFFFC` per Wire
///   Contract A) so image descriptors/paths are never spoken.
/// - Splits on newlines and Chinese/English sentence-end punctuation
///   (`。！？!?…；;` and sentence-ending `.`).
/// - Applies secondary splitting on comma/pause punctuation or whitespace when a
///   sentence exceeds [defaultMaxChunkLength] (`120` UTF-16 code units).
/// - Skips blank and punctuation-only chunks.
abstract final class TtsSentenceSplitter {
  static const int defaultMaxChunkLength = 120;
  static const String imageMarkerPrefix = '\uFFFCprimg:';
  static const String imageMarkerSuffix = '\uFFFC';

  static final RegExp _speakableContentPattern = RegExp(
    r'[\p{L}\p{N}]',
    unicode: true,
  );

  /// Returns `true` if [rawLine] trimmed matches the Contract A EPUB inline
  /// image marker line format (`\uFFFCprimg:...\uFFFC`).
  static bool isImageMarkerLine(String rawLine) {
    final trimmed = rawLine.trim();
    return trimmed.startsWith(imageMarkerPrefix) &&
        trimmed.endsWith(imageMarkerSuffix);
  }

  /// Splits [chapterText] into ordered [TtsUtterance] slices.
  static List<TtsUtterance> split(
    String chapterText, {
    int maxChunkLength = defaultMaxChunkLength,
  }) {
    if (chapterText.isEmpty || maxChunkLength <= 0) {
      return const <TtsUtterance>[];
    }

    final utterances = <TtsUtterance>[];
    var pos = 0;

    while (pos < chapterText.length) {
      final lineStart = pos;
      while (pos < chapterText.length &&
          chapterText.codeUnitAt(pos) != 0x0A &&
          chapterText.codeUnitAt(pos) != 0x0D) {
        pos++;
      }
      final lineContentEnd = pos;
      if (pos < chapterText.length) {
        if (chapterText.codeUnitAt(pos) == 0x0D &&
            pos + 1 < chapterText.length &&
            chapterText.codeUnitAt(pos + 1) == 0x0A) {
          pos += 2;
        } else {
          pos += 1;
        }
      }

      if (lineContentEnd <= lineStart) continue;
      final rawLine = chapterText.substring(lineStart, lineContentEnd);
      if (rawLine.trim().isEmpty || isImageMarkerLine(rawLine)) {
        continue;
      }

      _splitLine(
        chapterText: chapterText,
        lineStart: lineStart,
        lineEnd: lineContentEnd,
        maxChunkLength: maxChunkLength,
        out: utterances,
      );
    }

    return List<TtsUtterance>.unmodifiable(utterances);
  }

  /// Finds the utterance index best matching [charOffset] when starting
  /// playback from a visible page offset.
  static int findUtteranceIndexForOffset(
    List<TtsUtterance> utterances,
    int charOffset,
  ) {
    if (utterances.isEmpty) return 0;
    for (var i = 0; i < utterances.length; i++) {
      if (utterances[i].endCharOffset > charOffset) {
        return i;
      }
    }
    return utterances.length - 1;
  }

  static void _splitLine({
    required String chapterText,
    required int lineStart,
    required int lineEnd,
    required int maxChunkLength,
    required List<TtsUtterance> out,
  }) {
    var segStart = lineStart;
    var i = lineStart;

    while (i < lineEnd) {
      final cu = chapterText.codeUnitAt(i);
      if (_isPrimaryBreakBoundary(chapterText, i, lineStart, lineEnd, cu)) {
        var breakEnd = i + 1;
        while (breakEnd < lineEnd &&
            _isPrimaryTerminatorOrDotRun(
              chapterText.codeUnitAt(breakEnd),
              allowDot: cu == 0x002E,
            )) {
          breakEnd++;
        }
        while (breakEnd < lineEnd &&
            _isClosingQuoteOrBracket(chapterText.codeUnitAt(breakEnd))) {
          breakEnd++;
        }
        _emitChunk(
          chapterText: chapterText,
          rawStart: segStart,
          rawEnd: breakEnd,
          maxChunkLength: maxChunkLength,
          out: out,
        );
        segStart = breakEnd;
        i = breakEnd;
      } else {
        i++;
      }
    }

    if (segStart < lineEnd) {
      _emitChunk(
        chapterText: chapterText,
        rawStart: segStart,
        rawEnd: lineEnd,
        maxChunkLength: maxChunkLength,
        out: out,
      );
    }
  }

  static void _emitChunk({
    required String chapterText,
    required int rawStart,
    required int rawEnd,
    required int maxChunkLength,
    required List<TtsUtterance> out,
  }) {
    final trimmed = _trimRange(chapterText, rawStart, rawEnd);
    if (trimmed == null) return;
    final (start, end) = trimmed;

    if (end - start <= maxChunkLength) {
      _appendIfSpeakable(chapterText, start, end, out);
      return;
    }

    var cursor = start;
    while (cursor < end) {
      while (cursor < end && _isWhitespace(chapterText.codeUnitAt(cursor))) {
        cursor++;
      }
      if (cursor >= end) break;

      if (end - cursor <= maxChunkLength) {
        final tail = _trimRange(chapterText, cursor, end);
        if (tail != null) {
          _appendIfSpeakable(chapterText, tail.$1, tail.$2, out);
        }
        break;
      }

      var limit = math.min<int>(end, cursor + maxChunkLength);
      if (limit < end &&
          _isLowSurrogate(chapterText.codeUnitAt(limit)) &&
          limit - 1 > cursor) {
        limit--;
      }

      final splitPos = _findSecondarySplitPos(chapterText, cursor, limit);
      final piece = _trimRange(chapterText, cursor, splitPos);
      if (piece != null) {
        _appendIfSpeakable(chapterText, piece.$1, piece.$2, out);
      }
      cursor = splitPos;
    }
  }

  static int _findSecondarySplitPos(
    String text,
    int cursor,
    int limit,
  ) {
    // Prefer splitting after a comma/pause punctuation at least a few chars in.
    final minPreferred = math.min<int>(limit, cursor + 16);
    for (var i = limit - 1; i >= minPreferred; i--) {
      if (_isSecondaryPausePunctuation(text.codeUnitAt(i))) {
        return i + 1;
      }
    }
    for (var i = math.min<int>(limit - 1, minPreferred - 1); i > cursor; i--) {
      if (_isSecondaryPausePunctuation(text.codeUnitAt(i))) {
        return i + 1;
      }
    }

    // Fallback to whitespace inside [cursor, limit).
    for (var i = limit - 1; i > cursor; i--) {
      if (_isWhitespace(text.codeUnitAt(i))) {
        return i;
      }
    }

    // Hard split within surrogate-safe limit.
    return limit;
  }

  static void _appendIfSpeakable(
    String chapterText,
    int start,
    int end,
    List<TtsUtterance> out,
  ) {
    if (start >= end) return;
    final slice = chapterText.substring(start, end);
    if (!_speakableContentPattern.hasMatch(slice)) return;
    out.add(
      TtsUtterance(
        index: out.length,
        startCharOffset: start,
        endCharOffset: end,
        text: slice,
      ),
    );
  }

  static (int, int)? _trimRange(String text, int rawStart, int rawEnd) {
    var start = rawStart;
    var end = rawEnd;
    while (start < end && _isWhitespace(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isWhitespace(text.codeUnitAt(end - 1))) {
      end--;
    }
    if (start >= end) return null;
    return (start, end);
  }

  static bool _isPrimaryBreakBoundary(
    String text,
    int index,
    int lineStart,
    int lineEnd,
    int cu,
  ) {
    if (_isPrimaryTerminator(cu)) return true;
    if (cu != 0x002E) return false; // '.'

    // Do not break decimal numbers or versions such as 3.14 or v0.5.0.
    if (index > lineStart &&
        index + 1 < lineEnd &&
        _isAsciiDigit(text.codeUnitAt(index - 1)) &&
        _isAsciiDigit(text.codeUnitAt(index + 1))) {
      return false;
    }

    // Look past any consecutive dots ('...' ellipsis) and closing quotes.
    var probe = index + 1;
    while (probe < lineEnd && text.codeUnitAt(probe) == 0x002E) {
      probe++;
    }
    while (probe < lineEnd && _isClosingQuoteOrBracket(text.codeUnitAt(probe))) {
      probe++;
    }
    if (probe >= lineEnd) return true;
    final next = text.codeUnitAt(probe);
    return _isWhitespace(next) || _isPrimaryTerminator(next);
  }

  static bool _isPrimaryTerminator(int cu) {
    return cu == 0x3002 || // 。
        cu == 0xFF01 || // ！
        cu == 0xFF1F || // ？
        cu == 0x0021 || // !
        cu == 0x003F || // ?
        cu == 0x2026 || // …
        cu == 0xFF1B || // ；
        cu == 0x003B; // ;
  }

  static bool _isPrimaryTerminatorOrDotRun(int cu, {required bool allowDot}) {
    if (_isPrimaryTerminator(cu)) return true;
    return allowDot && cu == 0x002E;
  }

  static bool _isSecondaryPausePunctuation(int cu) {
    return cu == 0xFF0C || // ，
        cu == 0x002C || // ,
        cu == 0x3001 || // 、
        cu == 0xFF1A || // ：
        cu == 0x003A || // :
        cu == 0x2014 || // —
        cu == 0x2013; // –
  }

  static bool _isClosingQuoteOrBracket(int cu) {
    return cu == 0x201D || // ”
        cu == 0x2019 || // ’
        cu == 0x0022 || // "
        cu == 0x0027 || // '
        cu == 0x300D || // 」
        cu == 0x300F || // 』
        cu == 0xFF09 || // ）
        cu == 0x0029 || // )
        cu == 0x3011 || // 】
        cu == 0x005D || // ]
        cu == 0x300B || // 》
        cu == 0x3009 || // 〉
        cu == 0x3015 || // 〕
        cu == 0x007D; // }
  }

  static bool _isWhitespace(int cu) {
    return cu <= 0x20 ||
        cu == 0x00A0 ||
        cu == 0x1680 ||
        (cu >= 0x2000 && cu <= 0x200A) ||
        cu == 0x2028 ||
        cu == 0x2029 ||
        cu == 0x202F ||
        cu == 0x205F ||
        cu == 0x3000 ||
        cu == 0xFEFF;
  }

  static bool _isAsciiDigit(int cu) => cu >= 0x30 && cu <= 0x39;

  static bool _isLowSurrogate(int cu) => cu >= 0xDC00 && cu <= 0xDFFF;
}
