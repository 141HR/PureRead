import '../../domain/value_objects/page_slice.dart';
import '../../domain/value_objects/reading_anchor.dart';

/// Bidirectional mapping between character offsets ([ReadingAnchor]) and
/// paginated [PageSlice]s / two-column desktop spreads `(P_{2k}, P_{2k+1})`.
class AnchorMapper {
  const AnchorMapper._();

  /// Binary-searches the logical page index containing [charOffset].
  ///
  /// Returns `0` when [pages] is empty or [charOffset] precedes the first page,
  /// and `pages.length - 1` when [charOffset] meets or exceeds the last page end.
  static int findPageIndexByCharOffset(
    List<PageSlice> pages,
    int charOffset,
  ) {
    if (pages.isEmpty) return 0;
    if (charOffset <= pages.first.startCharOffset) return 0;
    if (charOffset >= pages.last.endCharOffset) return pages.length - 1;

    var low = 0;
    var high = pages.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final page = pages[mid];
      if (charOffset < page.startCharOffset) {
        high = mid - 1;
      } else if (charOffset >= page.endCharOffset &&
          page.startCharOffset != page.endCharOffset) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return low.clamp(0, pages.length - 1);
  }

  /// Maps [charOffset] to the display spread index in single-column (`1`) or
  /// two-column (`2`) mode.
  static int findSpreadIndexByCharOffset(
    List<PageSlice> pages,
    int charOffset, {
    int columnCount = 2,
  }) {
    final pageIndex = findPageIndexByCharOffset(pages, charOffset);
    return columnCount >= 2 ? pageIndex >> 1 : pageIndex;
  }

  /// Total number of visual spreads for [pages] under [columnCount].
  static int spreadCount(List<PageSlice> pages, int columnCount) {
    if (pages.isEmpty) return 0;
    return columnCount >= 2 ? (pages.length + 1) >> 1 : pages.length;
  }

  /// Extracts a layout-independent [ReadingAnchor] anchored to the start of
  /// [page].
  static ReadingAnchor getAnchorForPage(
    PageSlice page, {
    String chapterTitleSnapshot = '',
  }) {
    return ReadingAnchor(
      chapterIndex: page.chapterIndex,
      charOffset: page.startCharOffset,
      chapterTitleSnapshot: chapterTitleSnapshot,
    );
  }

  /// Pairs logical pages into `(P_{2k}, P_{2k+1})` in two-column mode, or
  /// `(P_k, null)` in single-column mode.
  ///
  /// When [pages] has an odd count in two-column mode and [spreadIndex] points
  /// to the final spread, `right` is `null` so the right column stays blank.
  static (PageSlice left, PageSlice? right) pairSpread(
    List<PageSlice> pages,
    int spreadIndex,
    int columnCount,
  ) {
    if (pages.isEmpty) {
      throw RangeError.index(spreadIndex, pages, 'spreadIndex');
    }
    final totalSpreads = spreadCount(pages, columnCount);
    if (spreadIndex < 0 || spreadIndex >= totalSpreads) {
      throw RangeError.range(
        spreadIndex,
        0,
        totalSpreads - 1,
        'spreadIndex',
      );
    }

    if (columnCount < 2) {
      return (pages[spreadIndex], null);
    }

    final leftIndex = spreadIndex * 2;
    final rightIndex = leftIndex + 1;
    final left = pages[leftIndex];
    final right = rightIndex < pages.length ? pages[rightIndex] : null;
    return (left, right);
  }
}
