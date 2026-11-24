import '../value_objects/page_slice.dart';
import '../value_objects/pagination_config.dart';

/// Chapter pagination contract.
///
/// Implementations prioritize pages around [priorityCharOffset] for fast
/// initial rendering and incrementally complete remaining slices for the
/// chapter while preserving exact character conservation across slices.
abstract interface class ReaderPaginator {
  Future<List<PageSlice>> paginateChapter({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    int? priorityCharOffset,
  });
}
