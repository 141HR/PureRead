import '../../domain/domain.dart';

/// Filter option for source enablement status.
enum SourceEnabledFilter { all, enabledOnly, disabledOnly }

/// Immutable state managed by [SourcesController].
class SourcesState {
  final List<BookSource> sources;
  final String selectedGroup;
  final String searchQuery;
  final SourceEnabledFilter enabledFilter;
  final Set<String> selectedIds;
  final bool isLoading;
  final bool isImporting;
  final String? statusMessage;
  final String? errorMessage;

  const SourcesState({
    this.sources = const <BookSource>[],
    this.selectedGroup = '全部',
    this.searchQuery = '',
    this.enabledFilter = SourceEnabledFilter.all,
    this.selectedIds = const <String>{},
    this.isLoading = false,
    this.isImporting = false,
    this.statusMessage,
    this.errorMessage,
  });

  static final RegExp _groupSplitRe = RegExp(r'[,，;；]+');
  static final RegExp _separatorOnlyRe = RegExp(r'^[-_=~*·•—–\s]+$');

  /// Splits composite Legado `bookSourceGroup` strings (`"---,0206⭐,最终精简版"`)
  /// into deduplicated human-readable tags, filtering pure decorative dividers.
  static List<String> parseGroupTags(String rawGroupName) {
    final seen = <String>{};
    final tags = <String>[];
    for (final rawToken in rawGroupName.split(_groupSplitRe)) {
      final token = rawToken.trim();
      if (token.isEmpty || _separatorOnlyRe.hasMatch(token)) {
        continue;
      }
      if (seen.add(token)) {
        tags.add(token);
      }
    }
    if (tags.isEmpty) {
      return const <String>['默认'];
    }
    return tags;
  }

  /// Counts of sources belonging to each parsed group tag.
  Map<String, int> get groupCounts {
    final counts = <String, int>{};
    for (final s in sources) {
      for (final tag in parseGroupTags(s.groupName)) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Distinct group labels starting with `'全部'`, sorted by source count
  /// descending (most populated groups first, `'默认'` last on ties).
  List<String> get groups {
    final counts = groupCounts;
    final sorted = counts.keys.toList()
      ..sort((a, b) {
        final countCmp = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
        if (countCmp != 0) return countCmp;
        if (a == '默认' && b != '默认') return 1;
        if (b == '默认' && a != '默认') return -1;
        return a.compareTo(b);
      });
    return <String>['全部', ...sorted];
  }

  /// Count of sources belonging to [groupName] (`'全部'` returns total).
  int countForGroup(String groupName) {
    if (groupName == '全部') return sources.length;
    return groupCounts[groupName] ?? 0;
  }

  /// Filtered and weight-sorted visible book sources.
  List<BookSource> get filteredSources {
    final q = searchQuery.trim().toLowerCase();
    final filtered = sources.where((source) {
      if (selectedGroup != '全部') {
        if (!parseGroupTags(source.groupName).contains(selectedGroup)) {
          return false;
        }
      }
      switch (enabledFilter) {
        case SourceEnabledFilter.all:
          break;
        case SourceEnabledFilter.enabledOnly:
          if (!source.enabled) return false;
        case SourceEnabledFilter.disabledOnly:
          if (source.enabled) return false;
      }
      if (q.isNotEmpty) {
        final matchesName = source.name.toLowerCase().contains(q);
        final matchesUrl = source.baseUrl.toLowerCase().contains(q);
        final matchesGroup = source.groupName.toLowerCase().contains(q);
        if (!matchesName && !matchesUrl && !matchesGroup) return false;
      }
      return true;
    }).toList(growable: false);

    filtered.sort((a, b) {
      final wCmp = b.weight.compareTo(a.weight);
      if (wCmp != 0) return wCmp;
      return a.name.compareTo(b.name);
    });
    return filtered;
  }

  SourcesState copyWith({
    List<BookSource>? sources,
    String? selectedGroup,
    String? searchQuery,
    SourceEnabledFilter? enabledFilter,
    Set<String>? selectedIds,
    bool? isLoading,
    bool? isImporting,
    String? statusMessage,
    bool clearStatus = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SourcesState(
      sources: sources ?? this.sources,
      selectedGroup: selectedGroup ?? this.selectedGroup,
      searchQuery: searchQuery ?? this.searchQuery,
      enabledFilter: enabledFilter ?? this.enabledFilter,
      selectedIds: selectedIds ?? this.selectedIds,
      isLoading: isLoading ?? this.isLoading,
      isImporting: isImporting ?? this.isImporting,
      statusMessage: clearStatus
          ? null
          : (statusMessage ?? this.statusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
