import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import 'search_state.dart';

/// Maximum concurrent source searches allowed during multi-source aggregation.
final searchConcurrencyLimitProvider = Provider<int>((ref) => 4);

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

/// Orchestrates bounded concurrent multi-source search with cooperative
/// cancellation and `(title, author)` result aggregation.
class SearchController extends Notifier<SearchState> {
  bool _disposed = false;
  int _searchEpoch = 0;
  CancellationToken? _activeCancelToken;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  SearchState build() {
    _disposed = false;
    _searchEpoch = 0;
    ref.onDispose(() {
      _disposed = true;
      _activeCancelToken?.cancel();
      _activeCancelToken = null;
    });
    return const SearchState();
  }

  /// Normalizes a book title and author into a stable aggregation key.
  static String buildAggregationKey(String title, String author) {
    final normTitle = _normalizeTitle(title);
    final normAuthor = _normalizeAuthor(author);
    return '$normTitle||$normAuthor';
  }

  /// Starts a bounded-concurrency search for [rawKeyword] across all enabled
  /// [BookSource]s, cancelling any previous in-flight search first.
  Future<void> search(String rawKeyword) async {
    if (!_isAlive) return;
    final keyword = rawKeyword.trim();
    if (keyword.isEmpty) {
      cancelSearch();
      state = const SearchState();
      return;
    }

    _activeCancelToken?.cancel();
    final cancelToken = CancellationToken();
    _activeCancelToken = cancelToken;
    final epoch = ++_searchEpoch;

    final sourceRepo = ref.read(sourceRepositoryProvider);
    final providerFactory = ref.read(bookProviderFactoryProvider);
    final concurrencyLimit = math.max(
      1,
      ref.read(searchConcurrencyLimitProvider),
    );

    state = SearchState(
      query: keyword,
      isSearching: true,
    );

    List<BookSource> sources;
    try {
      final fetched = await sourceRepo.listSources(enabledOnly: true);
      if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) return;
      sources = fetched.where((s) => s.enabled).toList(growable: false)
        ..sort((a, b) {
          final weightCmp = b.weight.compareTo(a.weight);
          if (weightCmp != 0) return weightCmp;
          return a.name.compareTo(b.name);
        });
    } catch (error) {
      if (!_isAlive || epoch != _searchEpoch) return;
      state = state.copyWith(
        isSearching: false,
        errorMessage: error is AppFailure ? error.message : '加载书源失败：$error',
      );
      return;
    }

    if (sources.isEmpty) {
      state = state.copyWith(
        isSearching: false,
        totalSources: 0,
        completedSources: 0,
        errorMessage: '暂无已启用的在线书源，请先在“书源”页导入或启用书源。',
      );
      return;
    }

    state = state.copyWith(
      totalSources: sources.length,
      completedSources: 0,
    );

    final aggregatedMap = <String, _MutableAggregateBook>{};
    final sourceErrors = <String, String>{};
    var nextIdx = 0;
    var completedCount = 0;

    Future<void> worker() async {
      while (true) {
        if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) {
          return;
        }
        if (nextIdx >= sources.length) return;
        final source = sources[nextIdx++];

        try {
          final provider = await providerFactory.createProvider(source);
          if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) {
            return;
          }
          if (!provider.capabilities.supportsSearch) {
            completedCount++;
            continue;
          }
          final response = await provider.search(
            keyword,
            page: 1,
            cancelToken: cancelToken,
          );
          if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) {
            return;
          }
          _mergeItems(aggregatedMap, source, response.items);
        } on CancelledFailure {
          return;
        } catch (error) {
          if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) {
            return;
          }
          sourceErrors[source.name] = error is AppFailure
              ? error.message
              : error.toString();
        }

        completedCount++;
        if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) {
          return;
        }
        state = state.copyWith(
          completedSources: completedCount,
          results: _buildSortedResults(aggregatedMap, keyword),
          sourceErrors: Map<String, String>.unmodifiable(sourceErrors),
        );
      }
    }

    final workerCount = math.min(concurrencyLimit, sources.length);
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    if (!_isAlive || epoch != _searchEpoch) return;
    state = state.copyWith(
      isSearching: false,
      completedSources: completedCount,
      results: _buildSortedResults(aggregatedMap, keyword),
      sourceErrors: Map<String, String>.unmodifiable(sourceErrors),
    );
  }

  /// Cancels the active multi-source search while keeping results gathered so
  /// far.
  void cancelSearch() {
    if (!_isAlive) return;
    _searchEpoch++;
    _activeCancelToken?.cancel();
    _activeCancelToken = null;
    if (state.isSearching) {
      state = state.copyWith(isSearching: false);
    }
  }

  /// Highlights an aggregated result by [groupKey].
  void selectBook(String? groupKey) {
    if (!_isAlive) return;
    state = state.copyWith(
      selectedGroupKey: groupKey,
      clearSelectedBook: groupKey == null,
    );
  }

  /// Clears search results and query.
  void clearResults() {
    if (!_isAlive) return;
    cancelSearch();
    state = const SearchState();
  }

  void _mergeItems(
    Map<String, _MutableAggregateBook> map,
    BookSource source,
    List<BookSearchItem> items,
  ) {
    for (final item in items) {
      final cleanTitle = item.title.trim();
      if (cleanTitle.isEmpty) continue;
      final cleanAuthor = item.author.trim();
      final key = buildAggregationKey(cleanTitle, cleanAuthor);

      final group = map.putIfAbsent(
        key,
        () => _MutableAggregateBook(
          groupKey: key,
          title: cleanTitle,
          author: cleanAuthor,
        ),
      );

      final alreadyAdded = group.entries.any(
        (e) =>
            e.item.sourceId == item.sourceId && e.item.bookUrl == item.bookUrl,
      );
      if (alreadyAdded) continue;

      group.entries.add(
        AggregatedSearchSourceEntry(
          item: item,
          sourceName: source.name,
          sourceWeight: source.weight,
        ),
      );
      if ((group.coverUrl == null || group.coverUrl!.isEmpty) &&
          item.coverUrl != null &&
          item.coverUrl!.isNotEmpty) {
        group.coverUrl = item.coverUrl;
      }
      if (item.intro.trim().length > group.intro.length) {
        group.intro = item.intro.trim();
      }
      if (group.latestChapterTitle.isEmpty &&
          item.latestChapterTitle.trim().isNotEmpty) {
        group.latestChapterTitle = item.latestChapterTitle.trim();
      }
      if ((group.kind == null || group.kind!.isEmpty) &&
          item.kind != null &&
          item.kind!.trim().isNotEmpty) {
        group.kind = item.kind!.trim();
      }
    }
  }

  List<AggregatedSearchBook> _buildSortedResults(
    Map<String, _MutableAggregateBook> map,
    String keyword,
  ) {
    final normKeyword = _normalizeTitle(keyword);
    final list = map.values.map((entry) {
      final sortedEntries = List<AggregatedSearchSourceEntry>.of(entry.entries)
        ..sort((a, b) {
          final wCmp = b.sourceWeight.compareTo(a.sourceWeight);
          if (wCmp != 0) return wCmp;
          return a.sourceName.compareTo(b.sourceName);
        });
      return AggregatedSearchBook(
        groupKey: entry.groupKey,
        title: entry.title,
        author: entry.author,
        coverUrl: entry.coverUrl,
        intro: entry.intro,
        latestChapterTitle: entry.latestChapterTitle,
        kind: entry.kind,
        sources: List<AggregatedSearchSourceEntry>.unmodifiable(sortedEntries),
      );
    }).toList(growable: false);

    list.sort((a, b) {
      final aExact = _normalizeTitle(a.title) == normKeyword;
      final bExact = _normalizeTitle(b.title) == normKeyword;
      if (aExact != bExact) return aExact ? -1 : 1;

      final aStarts = _normalizeTitle(a.title).startsWith(normKeyword);
      final bStarts = _normalizeTitle(b.title).startsWith(normKeyword);
      if (aStarts != bStarts) return aStarts ? -1 : 1;

      final countCmp = b.sourceCount.compareTo(a.sourceCount);
      if (countCmp != 0) return countCmp;

      final weightCmp = b.bestWeight.compareTo(a.bestWeight);
      if (weightCmp != 0) return weightCmp;

      return a.title.compareTo(b.title);
    });

    return List<AggregatedSearchBook>.unmodifiable(list);
  }

  static String _normalizeTitle(String raw) {
    return raw
        .trim()
        .replaceAll('《', '')
        .replaceAll('》', '')
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
  }

  static String _normalizeAuthor(String raw) {
    var cleaned = raw.trim().replaceAll(RegExp(r'\s+'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^作者[:：]'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'著$'), '');
    return cleaned.toLowerCase();
  }
}

class _MutableAggregateBook {
  _MutableAggregateBook({
    required this.groupKey,
    required this.title,
    required this.author,
  });

  final String groupKey;
  final String title;
  final String author;
  String? coverUrl;
  String intro = '';
  String latestChapterTitle = '';
  String? kind;
  final List<AggregatedSearchSourceEntry> entries =
      <AggregatedSearchSourceEntry>[];
}
