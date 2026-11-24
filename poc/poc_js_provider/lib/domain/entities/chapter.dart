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
}

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
}
