import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import 'replace_rules_state.dart';

final replaceRulesControllerProvider =
    NotifierProvider<ReplaceRulesController, ReplaceRulesState>(
      ReplaceRulesController.new,
    );

/// Manages CRUD for global/source/book content sanitization [ReplaceRule]s
/// and executes live previews through [contentSanitizerProvider].
class ReplaceRulesController extends Notifier<ReplaceRulesState> {
  bool _disposed = false;
  bool _initialized = false;
  int _previewEpoch = 0;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  ReplaceRulesState build() {
    _disposed = false;
    _initialized = false;
    _previewEpoch = 0;
    ref.onDispose(() {
      _disposed = true;
    });
    Future<void>.microtask(_initialize);
    return const ReplaceRulesState(isLoading: true);
  }

  /// Validates a rule [pattern]. Returns an error message when [isRegex] is
  /// true and [RegExp] compilation fails, or `null` when valid.
  static String? validatePattern(String pattern, {required bool isRegex}) {
    if (pattern.isEmpty) return '匹配模式不能为空';
    if (!isRegex) return null;
    try {
      RegExp(pattern, multiLine: true);
      return null;
    } on FormatException catch (e) {
      return '正则表达式语法错误：${e.message}';
    }
  }

  Future<void> _initialize() async {
    if (!_isAlive || _initialized) return;
    _initialized = true;
    await refresh();
  }

  /// Reloads replace rules along with available sources and books for scope
  /// targeting, then updates the live sanitizer preview.
  Future<void> refresh() async {
    if (!_isAlive) return;
    final sourceRepo = ref.read(sourceRepositoryProvider);
    final bookRepo = ref.read(bookRepositoryProvider);

    try {
      final rules = await sourceRepo.listReplaceRules();
      if (!_isAlive) return;
      final sources = await sourceRepo.listSources();
      if (!_isAlive) return;
      final books = await bookRepo.listBooks();
      if (!_isAlive) return;

      state = state.copyWith(
        rules: List<ReplaceRule>.unmodifiable(rules),
        availableSources: List<BookSource>.unmodifiable(sources),
        availableBooks: List<Book>.unmodifiable(books),
        isLoading: false,
      );
      await runPreview();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _formatError(error),
      );
    }
  }

  /// Filters rule list by [scope] (`null` shows all scopes).
  void setScopeFilter(RuleScopeType? scope) {
    if (!_isAlive) return;
    state = state.copyWith(
      scopeFilter: scope,
      clearScopeFilter: scope == null,
    );
  }

  /// Updates text search query across rule names, patterns, and groups.
  void setSearchQuery(String query) {
    if (!_isAlive) return;
    state = state.copyWith(searchQuery: query);
  }

  /// Creates or updates a [ReplaceRule] and refreshes live preview.
  Future<bool> saveRule({
    String? id,
    required String name,
    String groupName = '通用',
    required String pattern,
    String replacement = '',
    bool isRegex = true,
    RuleScopeType scopeType = RuleScopeType.global,
    String? scopeTargetId,
    bool enabled = true,
    int sortOrder = 0,
  }) async {
    if (!_isAlive) return false;
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      state = state.copyWith(errorMessage: '规则名称不能为空');
      return false;
    }

    final patternErr = validatePattern(pattern, isRegex: isRegex);
    if (patternErr != null) {
      state = state.copyWith(errorMessage: patternErr);
      return false;
    }

    if (scopeType != RuleScopeType.global &&
        (scopeTargetId == null || scopeTargetId.trim().isEmpty)) {
      state = state.copyWith(
        errorMessage: scopeType == RuleScopeType.source
            ? '指定书源作用域必须选择或填写书源 ID'
            : '指定书籍作用域必须选择或填写书籍 ID',
      );
      return false;
    }

    final sourceRepo = ref.read(sourceRepositoryProvider);
    final resolvedId =
        (id != null && id.trim().isNotEmpty)
            ? id.trim()
            : 'rule_${DateTime.now().microsecondsSinceEpoch}';
    final resolvedTargetId = scopeType == RuleScopeType.global
        ? null
        : scopeTargetId?.trim();

    final rule = ReplaceRule(
      id: resolvedId,
      name: cleanName,
      groupName: groupName.trim().isEmpty ? '通用' : groupName.trim(),
      pattern: pattern,
      replacement: replacement,
      isRegex: isRegex,
      scopeType: scopeType,
      scopeTargetId: resolvedTargetId,
      enabled: enabled,
      sortOrder: sortOrder,
      updatedAt: DateTime.now().toUtc(),
    );

    try {
      await sourceRepo.saveReplaceRule(rule);
      if (!_isAlive) return false;
      state = state.copyWith(
        statusMessage: '已保存规则「${rule.name}」',
        clearError: true,
      );
      await refresh();
      return true;
    } catch (error) {
      if (!_isAlive) return false;
      state = state.copyWith(errorMessage: _formatError(error));
      return false;
    }
  }

  /// Toggles whether [ruleId] is active and refreshes preview.
  Future<void> toggleRuleEnabled(String ruleId) async {
    if (!_isAlive) return;
    final idx = state.rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;
    final sourceRepo = ref.read(sourceRepositoryProvider);
    final updated = state.rules[idx].copyWith(
      enabled: !state.rules[idx].enabled,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await sourceRepo.saveReplaceRule(updated);
      if (!_isAlive) return;
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Deletes [ruleId] from [SourceRepository] and refreshes preview.
  Future<void> deleteRule(String ruleId) async {
    if (!_isAlive) return;
    final sourceRepo = ref.read(sourceRepositoryProvider);
    try {
      await sourceRepo.deleteReplaceRule(ruleId);
      if (!_isAlive) return;
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Updates live preview sample text or target `SanitizeContext` and re-runs
  /// [contentSanitizerProvider].
  Future<void> updatePreviewContext({
    String? rawText,
    String? sourceId,
    bool clearSourceId = false,
    String? bookId,
    bool clearBookId = false,
    String? chapterTitle,
  }) async {
    if (!_isAlive) return;
    state = state.copyWith(
      previewRawText: rawText ?? state.previewRawText,
      previewSourceId: sourceId,
      clearPreviewSourceId: clearSourceId,
      previewBookId: bookId,
      clearPreviewBookId: clearBookId,
      previewChapterTitle: chapterTitle ?? state.previewChapterTitle,
    );
    await runPreview();
  }

  /// Runs [contentSanitizerProvider.sanitize] on the current preview sample and
  /// target context.
  Future<void> runPreview() async {
    if (!_isAlive) return;
    final sanitizer = ref.read(contentSanitizerProvider);
    final epoch = ++_previewEpoch;

    state = state.copyWith(isPreviewing: true);
    try {
      final sanitized = await sanitizer.sanitize(
        state.previewRawText,
        SanitizeContext(
          bookId: state.previewBookId ?? '__preview_book__',
          sourceId: state.previewSourceId,
          chapterTitle: state.previewChapterTitle,
        ),
      );
      if (!_isAlive || epoch != _previewEpoch) return;
      state = state.copyWith(
        previewSanitizedText: sanitized,
        isPreviewing: false,
      );
    } catch (error) {
      if (!_isAlive || epoch != _previewEpoch) return;
      state = state.copyWith(
        isPreviewing: false,
        errorMessage: _formatError(error),
      );
    }
  }

  /// Clears transient banner messages.
  void clearBanner() {
    if (!_isAlive) return;
    state = state.copyWith(clearStatus: true, clearError: true);
  }

  String _formatError(Object error) =>
      error is AppFailure ? error.message : error.toString();
}
