import '../value_objects/provider_capabilities.dart';

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
}

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
}
