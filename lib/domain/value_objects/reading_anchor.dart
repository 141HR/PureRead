/// Precise reading position anchor independent of screen size or font settings.
///
/// [charOffset] refers to the character index within the chapter's sanitized
/// plain text and serves as the single source of truth across repagination.
class ReadingAnchor {
  final int chapterIndex;
  final int charOffset;
  final String chapterTitleSnapshot;

  const ReadingAnchor({
    required this.chapterIndex,
    required this.charOffset,
    required this.chapterTitleSnapshot,
  });

  ReadingAnchor copyWith({
    int? chapterIndex,
    int? charOffset,
    String? chapterTitleSnapshot,
  }) {
    return ReadingAnchor(
      chapterIndex: chapterIndex ?? this.chapterIndex,
      charOffset: charOffset ?? this.charOffset,
      chapterTitleSnapshot: chapterTitleSnapshot ?? this.chapterTitleSnapshot,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingAnchor &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          charOffset == other.charOffset &&
          chapterTitleSnapshot == other.chapterTitleSnapshot;

  @override
  int get hashCode =>
      Object.hash(chapterIndex, charOffset, chapterTitleSnapshot);

  @override
  String toString() =>
      'ReadingAnchor(chapterIndex: $chapterIndex, charOffset: $charOffset, '
      'chapterTitleSnapshot: $chapterTitleSnapshot)';
}
