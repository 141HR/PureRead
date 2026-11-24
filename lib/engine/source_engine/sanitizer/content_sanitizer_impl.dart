import 'dart:collection';

import '../../../domain/entities/replace_rule.dart';
import '../../../domain/repositories/source_repository.dart';
import '../../../domain/services/content_sanitizer.dart';
import '../../../domain/value_objects/sanitize_context.dart';

/// Callback loading candidate [ReplaceRule]s for a given [SanitizeContext].
typedef ReplaceRuleLoader = Future<List<ReplaceRule>> Function(
  SanitizeContext context,
);

/// Production [ContentSanitizer] implementation.
///
/// Loads rules via [ruleLoader] or [sourceRepository], filters to enabled rules
/// matching [SanitizeContext] scope, executes them in `global -> source -> book`
/// priority order sorted by `sortOrder`, caches compiled [RegExp] instances in
/// an LRU cache with malformed-regex protection, and normalizes line breaks,
/// paragraph whitespace, and excessive blank lines without inserting artificial
/// indent spaces.
class ContentSanitizerImpl implements ContentSanitizer {
  ContentSanitizerImpl({
    ReplaceRuleLoader? ruleLoader,
    SourceRepository? sourceRepository,
    this.maxCachedRegexes = 256,
    this.maxConsecutiveBlankLines = 1,
  })  : assert(
          ruleLoader == null || sourceRepository == null,
          'Provide either ruleLoader or sourceRepository, not both.',
        ),
        _ruleLoader = ruleLoader ??
            (sourceRepository != null
                ? ((context) => sourceRepository.listReplaceRules(
                      enabledOnly: true,
                      sourceId: context.sourceId,
                      bookId: context.bookId,
                    ))
                : _emptyRuleLoader);

  final ReplaceRuleLoader _ruleLoader;
  final int maxCachedRegexes;
  final int maxConsecutiveBlankLines;

  final LinkedHashMap<String, _CachedRegex> _regexCache =
      LinkedHashMap<String, _CachedRegex>();

  int get regexCacheSize => _regexCache.length;

  void clearRegexCache() => _regexCache.clear();

  @override
  Future<String> sanitize(String rawContent, SanitizeContext context) async {
    if (rawContent.isEmpty) return '';

    var text = _normalizeLineEndings(rawContent);
    final candidateRules = await _ruleLoader(context);
    final orderedRules = _selectAndOrderRules(candidateRules, context);

    for (final rule in orderedRules) {
      if (rule.pattern.isEmpty) continue;
      if (rule.isRegex) {
        final regex = _getOrCompileRegex(rule.pattern);
        if (regex == null) continue;
        try {
          text = text.replaceAll(regex, rule.replacement);
        } catch (_) {
          // Skip faulty replacement evaluation safely so reading never crashes.
        }
      } else {
        text = text.replaceAll(rule.pattern, rule.replacement);
      }
    }

    return _normalizeWhitespace(
      _normalizeLineEndings(text),
      maxBlankLines: maxConsecutiveBlankLines,
    );
  }

  List<ReplaceRule> _selectAndOrderRules(
    List<ReplaceRule> rules,
    SanitizeContext context,
  ) {
    final matched = <({ReplaceRule rule, int scopeRank, int originalIndex})>[];
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      if (!rule.enabled || rule.pattern.isEmpty) continue;
      final matchesScope = switch (rule.scopeType) {
        RuleScopeType.global => true,
        RuleScopeType.source =>
          context.sourceId != null && rule.scopeTargetId == context.sourceId,
        RuleScopeType.book => rule.scopeTargetId == context.bookId,
      };
      if (!matchesScope) continue;
      matched.add((
        rule: rule,
        scopeRank: _scopePriority(rule.scopeType),
        originalIndex: i,
      ));
    }

    matched.sort((a, b) {
      final scopeCmp = a.scopeRank.compareTo(b.scopeRank);
      if (scopeCmp != 0) return scopeCmp;
      final orderCmp = a.rule.sortOrder.compareTo(b.rule.sortOrder);
      if (orderCmp != 0) return orderCmp;
      return a.originalIndex.compareTo(b.originalIndex);
    });

    return matched.map((entry) => entry.rule).toList(growable: false);
  }

  static int _scopePriority(RuleScopeType scope) => switch (scope) {
        RuleScopeType.global => 0,
        RuleScopeType.source => 1,
        RuleScopeType.book => 2,
      };

  RegExp? _getOrCompileRegex(String pattern) {
    if (maxCachedRegexes <= 0) {
      return _tryCompile(pattern);
    }

    final existing = _regexCache.remove(pattern);
    if (existing != null) {
      _regexCache[pattern] = existing;
      return existing.regex;
    }

    final compiled = _tryCompile(pattern);
    if (_regexCache.length >= maxCachedRegexes) {
      _regexCache.remove(_regexCache.keys.first);
    }
    _regexCache[pattern] = _CachedRegex(compiled);
    return compiled;
  }

  static RegExp? _tryCompile(String pattern) {
    try {
      return RegExp(pattern, multiLine: true);
    } on FormatException {
      return null;
    }
  }

  static String _normalizeLineEndings(String text) {
    if (!text.contains('\r')) return text;
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static String _normalizeWhitespace(
    String text, {
    required int maxBlankLines,
  }) {
    final rawLines = text.split('\n');
    final out = <String>[];
    var consecutiveBlanks = 0;

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (out.isEmpty) continue;
        if (consecutiveBlanks < maxBlankLines) {
          out.add('');
          consecutiveBlanks++;
        }
      } else {
        out.add(trimmed);
        consecutiveBlanks = 0;
      }
    }

    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }

    return out.join('\n');
  }

  static Future<List<ReplaceRule>> _emptyRuleLoader(
    SanitizeContext context,
  ) async =>
      const <ReplaceRule>[];
}

class _CachedRegex {
  const _CachedRegex(this.regex);

  final RegExp? regex;
}
