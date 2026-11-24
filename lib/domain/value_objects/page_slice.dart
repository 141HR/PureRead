/// Pure-Dart pre-laid-out line representation consumed by CustomPainter.
class LayoutLine {
  final String text;
  final int startCharOffset;
  final int endCharOffset;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool isParagraphStart;
  final bool isParagraphEnd;
  final bool isChapterTitle;

  /// Optional per-character horizontal offsets for justified or CJK-ASCII spacing.
  final List<double>? charXOffsets;

  const LayoutLine({
    required this.text,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.isParagraphStart = false,
    this.isParagraphEnd = false,
    this.isChapterTitle = false,
    this.charXOffsets,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutLine &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          startCharOffset == other.startCharOffset &&
          endCharOffset == other.endCharOffset &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          isParagraphStart == other.isParagraphStart &&
          isParagraphEnd == other.isParagraphEnd &&
          isChapterTitle == other.isChapterTitle &&
          _listEquals(charXOffsets, other.charXOffsets);

  @override
  int get hashCode => Object.hash(
        text,
        startCharOffset,
        endCharOffset,
        x,
        y,
        width,
        height,
        isParagraphStart,
        isParagraphEnd,
        isChapterTitle,
        charXOffsets == null ? null : Object.hashAll(charXOffsets!),
      );
}

/// One logical page slice produced by [ReaderPaginator].
///
/// Adjacent slices within a chapter must satisfy
/// `prev.endCharOffset == next.startCharOffset` (half-open range
/// `[startCharOffset, endCharOffset)`) to guarantee zero dropped or duplicated
/// characters.
class PageSlice {
  final int chapterIndex;
  final int pageIndex;
  final int startCharOffset;
  final int endCharOffset;
  final List<LayoutLine> lines;

  const PageSlice({
    required this.chapterIndex,
    required this.pageIndex,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.lines,
  });

  int get length => endCharOffset - startCharOffset;

  bool containsOffset(int charOffset) =>
      charOffset >= startCharOffset && charOffset < endCharOffset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageSlice &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          pageIndex == other.pageIndex &&
          startCharOffset == other.startCharOffset &&
          endCharOffset == other.endCharOffset &&
          _listEquals(lines, other.lines);

  @override
  int get hashCode => Object.hash(
        chapterIndex,
        pageIndex,
        startCharOffset,
        endCharOffset,
        Object.hashAll(lines),
      );

  @override
  String toString() =>
      'PageSlice(chapterIndex: $chapterIndex, pageIndex: $pageIndex, '
      'range: [$startCharOffset, $endCharOffset), lines: ${lines.length})';
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
