/// Byte-offset metadata for a single chapter inside a local TXT file.
class ChapterIndexEntry {
  const ChapterIndexEntry({
    required this.chapterIndex,
    required this.title,
    required this.byteStart,
    required this.byteEnd,
  });

  final int chapterIndex;
  final String title;
  final int byteStart;
  final int byteEnd;

  int get byteLength => byteEnd - byteStart;

  @override
  String toString() =>
      'ChapterIndexEntry(#$chapterIndex "$title" [$byteStart, $byteEnd))';
}
