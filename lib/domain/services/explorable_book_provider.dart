import '../entities/book_search_item.dart';
import '../entities/explore_category.dart';
import '../value_objects/cancellation_token.dart';
import '../value_objects/source_debug_trace.dart';
import 'book_provider.dart';

/// Capability interface for [BookProvider] implementations that support
/// browsing online discovery feeds and rankings (发现 / 排行榜).
abstract interface class ExplorableBookProvider implements BookProvider {
  /// Returns the parsed discovery categories / group headers for this source.
  Future<({List<ExploreCategory> categories, SourceDebugTrace trace})>
  getExploreCategories({CancellationToken? cancelToken});

  /// Fetches one page of books under [category].
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> explore(
    ExploreCategory category, {
    int page = 1,
    CancellationToken? cancelToken,
  });
}
