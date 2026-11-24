import '../../domain/domain.dart';

const String kDefaultSanitizePreviewSample = '''第一章 初入山门

    【新笔趣阁 www.xbiquge.example】    


    韩立看着手中的小绿瓶，心中默念：请记住本站域名 xbiquge.example，求月票求推荐！

    正文开始，风声鹤唳。



    （本章完，未完待续...）''';

/// Immutable state managed by [ReplaceRulesController].
class ReplaceRulesState {
  final List<ReplaceRule> rules;
  final List<BookSource> availableSources;
  final List<Book> availableBooks;
  final RuleScopeType? scopeFilter;
  final String searchQuery;
  final String previewRawText;
  final String previewSanitizedText;
  final String? previewSourceId;
  final String? previewBookId;
  final String previewChapterTitle;
  final bool isLoading;
  final bool isPreviewing;
  final String? statusMessage;
  final String? errorMessage;

  const ReplaceRulesState({
    this.rules = const <ReplaceRule>[],
    this.availableSources = const <BookSource>[],
    this.availableBooks = const <Book>[],
    this.scopeFilter,
    this.searchQuery = '',
    this.previewRawText = kDefaultSanitizePreviewSample,
    this.previewSanitizedText = '',
    this.previewSourceId,
    this.previewBookId,
    this.previewChapterTitle = '第1章 预览',
    this.isLoading = false,
    this.isPreviewing = false,
    this.statusMessage,
    this.errorMessage,
  });

  List<ReplaceRule> get filteredRules {
    final q = searchQuery.trim().toLowerCase();
    return rules
        .where((rule) {
          if (scopeFilter != null && rule.scopeType != scopeFilter) {
            return false;
          }
          if (q.isNotEmpty) {
            final matchName = rule.name.toLowerCase().contains(q);
            final matchPattern = rule.pattern.toLowerCase().contains(q);
            final matchGroup = rule.groupName.toLowerCase().contains(q);
            if (!matchName && !matchPattern && !matchGroup) return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  ReplaceRulesState copyWith({
    List<ReplaceRule>? rules,
    List<BookSource>? availableSources,
    List<Book>? availableBooks,
    RuleScopeType? scopeFilter,
    bool clearScopeFilter = false,
    String? searchQuery,
    String? previewRawText,
    String? previewSanitizedText,
    String? previewSourceId,
    bool clearPreviewSourceId = false,
    String? previewBookId,
    bool clearPreviewBookId = false,
    String? previewChapterTitle,
    bool? isLoading,
    bool? isPreviewing,
    String? statusMessage,
    bool clearStatus = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReplaceRulesState(
      rules: rules ?? this.rules,
      availableSources: availableSources ?? this.availableSources,
      availableBooks: availableBooks ?? this.availableBooks,
      scopeFilter: clearScopeFilter ? null : (scopeFilter ?? this.scopeFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      previewRawText: previewRawText ?? this.previewRawText,
      previewSanitizedText: previewSanitizedText ?? this.previewSanitizedText,
      previewSourceId: clearPreviewSourceId
          ? null
          : (previewSourceId ?? this.previewSourceId),
      previewBookId: clearPreviewBookId
          ? null
          : (previewBookId ?? this.previewBookId),
      previewChapterTitle: previewChapterTitle ?? this.previewChapterTitle,
      isLoading: isLoading ?? this.isLoading,
      isPreviewing: isPreviewing ?? this.isPreviewing,
      statusMessage: clearStatus
          ? null
          : (statusMessage ?? this.statusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
