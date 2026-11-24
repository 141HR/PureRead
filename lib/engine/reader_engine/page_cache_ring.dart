import '../../domain/value_objects/page_slice.dart';
import '../../domain/value_objects/pagination_config.dart';

/// Three-chapter sliding page cache ring for `{chapterIndex - 1, chapterIndex,
/// chapterIndex + 1}`, keyed by `(bookId, chapterIndex, PaginationConfig)`.
///
/// Automatically evicts chapters outside the 3-chapter window around the
/// active reading chapter and clears cached slices whenever the active book
/// or [PaginationConfig] changes.
class PageCacheRing {
  String? _activeBookId;
  PaginationConfig? _activeConfig;
  int? _centerChapterIndex;
  final Map<int, List<PageSlice>> _pagesByChapter = <int, List<PageSlice>>{};

  String? get activeBookId => _activeBookId;
  PaginationConfig? get activeConfig => _activeConfig;
  int? get centerChapterIndex => _centerChapterIndex;
  int get length => _pagesByChapter.length;

  /// Unmodifiable snapshot of currently cached chapter indices.
  Set<int> get cachedChapterIndices =>
      Set<int>.unmodifiable(_pagesByChapter.keys);

  /// Updates the active chapter window center to [chapterIndex], clearing if
  /// [bookId] or [config] changed and evicting chapters with
  /// `(k - chapterIndex).abs() > 1`.
  void focusChapter({
    required String bookId,
    required int chapterIndex,
    required PaginationConfig config,
  }) {
    _validateChapterIndex(chapterIndex);
    _resetIfContextChanged(bookId: bookId, config: config);
    _centerChapterIndex = chapterIndex;
    _evictOutsideWindow(chapterIndex);
  }

  /// Stores paginated [pages] for `(bookId, chapterIndex, config)` and keeps at
  /// most the 3-chapter sliding window `{c - 1, c, c + 1}`.
  void put({
    required String bookId,
    required int chapterIndex,
    required PaginationConfig config,
    required List<PageSlice> pages,
    bool isCurrentChapter = false,
  }) {
    _validateChapterIndex(chapterIndex);
    _resetIfContextChanged(bookId: bookId, config: config);

    _pagesByChapter[chapterIndex] = List<PageSlice>.unmodifiable(pages);

    if (isCurrentChapter || _centerChapterIndex == null) {
      _centerChapterIndex = chapterIndex;
      _evictOutsideWindow(chapterIndex);
      return;
    }

    final currentCenter = _centerChapterIndex!;
    if ((chapterIndex - currentCenter).abs() <= 1) {
      return;
    }

    // Slide the 3-chapter window smoothly when sequential chapters are added
    // without an explicit `focusChapter` call.
    final shiftedCenter =
        chapterIndex > currentCenter ? chapterIndex - 1 : chapterIndex + 1;
    _centerChapterIndex = shiftedCenter;
    _evictOutsideWindow(shiftedCenter);
  }

  /// Retrieves cached slices for `(bookId, chapterIndex, config)`, or `null`
  /// on miss or book/config mismatch.
  List<PageSlice>? get({
    required String bookId,
    required int chapterIndex,
    required PaginationConfig config,
  }) {
    if (_activeBookId != bookId || _activeConfig != config) {
      return null;
    }
    return _pagesByChapter[chapterIndex];
  }

  /// True when `(bookId, chapterIndex, config)` is present in the cache ring.
  bool contains({
    required String bookId,
    required int chapterIndex,
    required PaginationConfig config,
  }) {
    if (_activeBookId != bookId || _activeConfig != config) {
      return false;
    }
    return _pagesByChapter.containsKey(chapterIndex);
  }

  /// Removes a single chapter from the ring (e.g. after chapter re-sanitization).
  bool invalidateChapter(int chapterIndex) {
    return _pagesByChapter.remove(chapterIndex) != null;
  }

  /// Clears all cached slices if [newConfig] differs from the active config.
  void invalidateOnConfigChange(PaginationConfig newConfig) {
    if (_activeConfig != null && _activeConfig != newConfig) {
      clear();
    }
  }

  /// Clears all cached entries and resets active context metadata.
  void clear() {
    _pagesByChapter.clear();
    _activeBookId = null;
    _activeConfig = null;
    _centerChapterIndex = null;
  }

  void _resetIfContextChanged({
    required String bookId,
    required PaginationConfig config,
  }) {
    if (_activeBookId != bookId || _activeConfig != config) {
      _pagesByChapter.clear();
      _activeBookId = bookId;
      _activeConfig = config;
      _centerChapterIndex = null;
    }
  }

  void _evictOutsideWindow(int center) {
    _pagesByChapter.removeWhere((key, _) => (key - center).abs() > 1);
  }

  void _validateChapterIndex(int chapterIndex) {
    if (chapterIndex < 0) {
      throw ArgumentError.value(
        chapterIndex,
        'chapterIndex',
        'must be non-negative',
      );
    }
  }
}
