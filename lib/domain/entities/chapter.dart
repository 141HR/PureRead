/// Unified chapter metadata entity corresponding to the `chapters` table.
class ChapterMeta {
  final int? id;
  final String bookId;
  final int chapterIndex;
  final String title;
  final String? url;
  final int? byteStart;
  final int? byteEnd;
  final String? epubHref;
  final bool isCached;
  final String? cacheKey;
  final int wordCount;
  final DateTime updatedAt;

  const ChapterMeta({
    this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.title,
    this.url,
    this.byteStart,
    this.byteEnd,
    this.epubHref,
    this.isCached = false,
    this.cacheKey,
    this.wordCount = 0,
    required this.updatedAt,
  });

  ChapterMeta copyWith({
    int? id,
    String? bookId,
    int? chapterIndex,
    String? title,
    String? url,
    int? byteStart,
    int? byteEnd,
    String? epubHref,
    bool? isCached,
    String? cacheKey,
    int? wordCount,
    DateTime? updatedAt,
  }) {
    return ChapterMeta(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      title: title ?? this.title,
      url: url ?? this.url,
      byteStart: byteStart ?? this.byteStart,
      byteEnd: byteEnd ?? this.byteEnd,
      epubHref: epubHref ?? this.epubHref,
      isCached: isCached ?? this.isCached,
      cacheKey: cacheKey ?? this.cacheKey,
      wordCount: wordCount ?? this.wordCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterMeta &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          bookId == other.bookId &&
          chapterIndex == other.chapterIndex &&
          title == other.title &&
          url == other.url &&
          byteStart == other.byteStart &&
          byteEnd == other.byteEnd &&
          epubHref == other.epubHref &&
          isCached == other.isCached &&
          cacheKey == other.cacheKey &&
          wordCount == other.wordCount &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        chapterIndex,
        title,
        url,
        byteStart,
        byteEnd,
        epubHref,
        isCached,
        cacheKey,
        wordCount,
        updatedAt,
      );
}

/// Raw unsanitized chapter text returned by [BookProvider.getChapterContent].
class ChapterContent {
  final int chapterIndex;
  final String title;
  final String rawText;
  final String? sourceUrl;
  final DateTime fetchedAt;

  const ChapterContent({
    required this.chapterIndex,
    required this.title,
    required this.rawText,
    this.sourceUrl,
    required this.fetchedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterContent &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          title == other.title &&
          rawText == other.rawText &&
          sourceUrl == other.sourceUrl &&
          fetchedAt == other.fetchedAt;

  @override
  int get hashCode =>
      Object.hash(chapterIndex, title, rawText, sourceUrl, fetchedAt);
}
