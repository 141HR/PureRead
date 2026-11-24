/// Context metadata supplied to [ContentSanitizer.sanitize].
class SanitizeContext {
  final String bookId;
  final String? sourceId;
  final String chapterTitle;

  const SanitizeContext({
    required this.bookId,
    this.sourceId,
    required this.chapterTitle,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SanitizeContext &&
          runtimeType == other.runtimeType &&
          bookId == other.bookId &&
          sourceId == other.sourceId &&
          chapterTitle == other.chapterTitle;

  @override
  int get hashCode => Object.hash(bookId, sourceId, chapterTitle);
}
