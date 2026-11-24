import '../entities/book_search_item.dart';
import '../entities/chapter.dart';
import '../value_objects/cancellation_token.dart';
import '../value_objects/provider_capabilities.dart';
import '../value_objects/source_debug_trace.dart';

abstract interface class BookProvider {
  String get providerId;
  ProviderType get type;
  ProviderCapabilities get capabilities;

  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  });

  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  });

  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  });

  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  });
}
