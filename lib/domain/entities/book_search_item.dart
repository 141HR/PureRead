import '../value_objects/provider_capabilities.dart';

/// Search result item returned by [BookProvider.search].
class BookSearchItem {
  final String sourceId;
  final ProviderType providerType;
  final String bookUrl;
  final String title;
  final String author;
  final String? coverUrl;
  final String intro;
  final String latestChapterTitle;
  final String? kind;

  const BookSearchItem({
    required this.sourceId,
    required this.providerType,
    required this.bookUrl,
    required this.title,
    this.author = '',
    this.coverUrl,
    this.intro = '',
    this.latestChapterTitle = '',
    this.kind,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookSearchItem &&
          runtimeType == other.runtimeType &&
          sourceId == other.sourceId &&
          providerType == other.providerType &&
          bookUrl == other.bookUrl &&
          title == other.title &&
          author == other.author &&
          coverUrl == other.coverUrl &&
          intro == other.intro &&
          latestChapterTitle == other.latestChapterTitle &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(
        sourceId,
        providerType,
        bookUrl,
        title,
        author,
        coverUrl,
        intro,
        latestChapterTitle,
        kind,
      );
}

/// Detailed book metadata returned by [BookProvider.getBookDetail].
class BookDetail {
  final String sourceId;
  final ProviderType providerType;
  final String bookUrl;
  final String tocUrl;
  final String title;
  final String author;
  final String? coverUrl;
  final String intro;
  final String latestChapterTitle;
  final String? kind;
  final int? wordCount;

  const BookDetail({
    required this.sourceId,
    required this.providerType,
    required this.bookUrl,
    required this.tocUrl,
    required this.title,
    this.author = '',
    this.coverUrl,
    this.intro = '',
    this.latestChapterTitle = '',
    this.kind,
    this.wordCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookDetail &&
          runtimeType == other.runtimeType &&
          sourceId == other.sourceId &&
          providerType == other.providerType &&
          bookUrl == other.bookUrl &&
          tocUrl == other.tocUrl &&
          title == other.title &&
          author == other.author &&
          coverUrl == other.coverUrl &&
          intro == other.intro &&
          latestChapterTitle == other.latestChapterTitle &&
          kind == other.kind &&
          wordCount == other.wordCount;

  @override
  int get hashCode => Object.hash(
        sourceId,
        providerType,
        bookUrl,
        tocUrl,
        title,
        author,
        coverUrl,
        intro,
        latestChapterTitle,
        kind,
        wordCount,
      );
}
