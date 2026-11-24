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

  /// Sorted distinct group labels starting with `'全部'`.
  List<String> get groups {
    final set = <String>{};
    for (final s in sources) {
      final group = s.groupName.trim().isEmpty ? '默认' : s.groupName.trim();
      set.add(group);
    }
    final sorted = set.toList()..sort();
    return <String>['全部', ...sorted];
  }

  /// Count of sources belonging to [groupName] (`'全部'` returns total).
  int countForGroup(String groupName) {
    if (groupName == '全部') return sources.length;
    return sources.where((s) {
      final g = s.groupName.trim().isEmpty ? '默认' : s.groupName.trim();
      return g == groupName;
    }).length;
  }

  /// Filtered and weight-sorted visible book sources.
  List<BookSource> get filteredSources {
    final q = searchQuery.trim().toLowerCase();
    final filtered = sources.where((source) {
      if (selectedGroup != '全部') {
        final g = source.groupName.trim().isEmpty
            ? '默认'
            : source.groupName.trim();
        if (g != selectedGroup) return false;
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
