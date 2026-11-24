/// Bookmark and annotation entity corresponding to the `bookmarks` table.
class Bookmark {
  final String id;
  final String bookId;
  final int chapterIndex;
  final int charOffset;
  final String excerpt;
  final String note;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.charOffset,
    required this.excerpt,
    this.note = '',
    required this.createdAt,
  });

  Bookmark copyWith({
    String? id,
    String? bookId,
    int? chapterIndex,
    int? charOffset,
    String? excerpt,
    String? note,
    DateTime? createdAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      charOffset: charOffset ?? this.charOffset,
      excerpt: excerpt ?? this.excerpt,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          bookId == other.bookId &&
          chapterIndex == other.chapterIndex &&
          charOffset == other.charOffset &&
          excerpt == other.excerpt &&
          note == other.note &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        chapterIndex,
        charOffset,
        excerpt,
        note,
        createdAt,
      );
}
