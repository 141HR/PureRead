import 'dart:convert';
import 'dart:math';

import 'package:html/parser.dart' as html_parser;

import '../../../domain/domain.dart';
import '../../../infrastructure/js/js_crypto_helpers.dart';
import '../../../infrastructure/js/qjs_sandbox_runtime.dart';
import '../../../infrastructure/network/source_http_client.dart';
import '../parsing/legado_jsoup_bridge.dart';
import '../parsing/legado_selector_engine.dart';
import 'legado_source.dart';

/// Parsed HTTP request specification derived from a Legado URL expression.
class LegadoRequestSpec {
  final String url;
  final String method;
  final String? body;
  final Map<String, String> headers;
  final String? charset;
  final bool webView;

  const LegadoRequestSpec({
    required this.url,
    this.method = 'GET',
    this.body,
    this.headers = const <String, String>{},
    this.charset,
    this.webView = false,
  });
}

/// Cached entry stored by Legado `cache.put(key, value, saveSeconds?)`.
class LegadoCacheEntry {
  final String value;
  final int? expiresAtMs;

  const LegadoCacheEntry(this.value, this.expiresAtMs);

  bool isExpired(int nowMs) {
    final exp = expiresAtMs;
    return exp != null && nowMs > exp;
  }
}

/// Mutable per-operation / per-provider state shared across Legado rule and JS
/// evaluations (`java.put`/`java.get`, `book.putVariable`/`book.getVariable`,
/// `cache.get`/`cache.put`, `source.getVariable`/`setVariable`, cookie
/// mutations, and debug logs).
class LegadoEvalSession {
  final Map<String, String> javaVars;
  final Map<String, String> bookVars;
  final Map<String, LegadoCacheEntry> cacheEntries;
  final Map<String, String> cookieSnapshotByHost = <String, String>{};
  final List<({String type, String url, String value})> _pendingCookieOps =
      <({String type, String url, String value})>[];
  final List<String> logs = <String>[];

  String sourceVariable;
  String bookName;
  String bookUrl;
  String tocUrl;
  String bookVariable;
  String bookCustomVariable;
  String chapterTitle;
  String chapterUrl;
  int chapterIndex;

  LegadoEvalSession({
    this.sourceVariable = '',
    this.bookName = '',
    this.bookUrl = '',
    this.tocUrl = '',
    this.bookVariable = '',
    this.bookCustomVariable = '',
    this.chapterTitle = '',
    this.chapterUrl = '',
    this.chapterIndex = 0,
    Map<String, String>? javaVars,
    Map<String, String>? bookVars,
    Map<String, LegadoCacheEntry>? cacheEntries,
  }) : javaVars = javaVars ?? <String, String>{},
       bookVars = bookVars ?? <String, String>{},
       cacheEntries = cacheEntries ?? <String, LegadoCacheEntry>{};

  Future<void> preloadCookies(
    SourceHttpClient httpClient,
    List<String> urls,
  ) async {
    for (final raw in urls) {
      final uri = SourceHttpClient.tryNormalizeHttpUri(raw);
      if (uri == null) continue;
      final hostKey = HostIsolatedCookieJar.hostKeyForUri(uri);
      if (cookieSnapshotByHost.containsKey(hostKey)) continue;
      cookieSnapshotByHost[hostKey] = await httpClient.getCookie(uri.toString());
    }
  }

  String getCookieSync(String urlOrDomain) {
    final uri = SourceHttpClient.tryNormalizeHttpUri(urlOrDomain);
    if (uri == null) return '';
    return cookieSnapshotByHost[HostIsolatedCookieJar.hostKeyForUri(uri)] ?? '';
  }

  String getCookieKeySync(String urlOrDomain, String key) {
    final raw = getCookieSync(urlOrDomain);
    if (raw.isEmpty || key.isEmpty) return '';
    for (final part in raw.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final k = part.substring(0, idx).trim();
      if (k == key) {
        return part.substring(idx + 1).trim();
      }
    }
    return '';
  }

  void setCookieSync(String urlOrDomain, String cookieValue) {
    final uri = SourceHttpClient.tryNormalizeHttpUri(urlOrDomain);
    if (uri == null) return;
    final hostKey = HostIsolatedCookieJar.hostKeyForUri(uri);
    final existing = cookieSnapshotByHost[hostKey] ?? '';
    cookieSnapshotByHost[hostKey] = existing.isEmpty
        ? cookieValue
        : '$existing; $cookieValue';
    _pendingCookieOps.add((
      type: 'set',
      url: uri.toString(),
      value: cookieValue,
    ));
  }

  void removeCookieSync(String urlOrDomain) {
    final uri = SourceHttpClient.tryNormalizeHttpUri(urlOrDomain);
    if (uri == null) return;
    final hostKey = HostIsolatedCookieJar.hostKeyForUri(uri);
    cookieSnapshotByHost[hostKey] = '';
    _pendingCookieOps.add((type: 'remove', url: uri.toString(), value: ''));
  }

  Future<void> flushCookies(SourceHttpClient httpClient) async {
    if (_pendingCookieOps.isEmpty) return;
    final ops = List.of(_pendingCookieOps);
    _pendingCookieOps.clear();
    for (final op in ops) {
      if (op.type == 'remove') {
        await httpClient.removeCookie(op.url);
      } else if (op.type == 'set') {
        await httpClient.setCookie(op.url, op.value);
      }
    }
  }
}

sealed class _RuleStage {
  const _RuleStage();
}

final class _SelectorStage extends _RuleStage {
  final String rule;
  const _SelectorStage(this.rule);
}

final class _JsStage extends _RuleStage {
  final String code;
  const _JsStage(this.code);
}

/// Evaluates Legado v3 URL expressions, selectors, regex replacements, mustache
/// templates, and embedded `<js>` / `@js:` scripts inside [QjsSandboxRuntime].
class LegadoRuleEvaluator {
  final String sourceId;
  final LegadoBookSource? source;
  final SourceHttpClient? httpClient;
  final Duration jsTimeout;
  final int memoryLimitBytes;

  const LegadoRuleEvaluator({
    required this.sourceId,
    this.source,
    this.httpClient,
    this.jsTimeout = const Duration(seconds: 5),
    this.memoryLimitBytes = QjsSandboxRuntime.defaultMemoryLimitBytes,
  });

  /// Synchronous static URL parser (supports `{{key}}`, `{{page}}`, `<a,b>`,
  /// lenient JS-object options, charset-aware query/form encoding, and `#fragment`
  /// baseUrl normalization).
  static LegadoRequestSpec parseUrlSpec(
    String rawSpec, {
    required String baseUrl,
    Map<String, String> defaultHeaders = const <String, String>{},
    String? defaultCharset,
    String? keyword,
    int? page,
  }) {
    final normalizedBase =
        SourceHttpClient.tryNormalizeHttpUri(baseUrl)?.toString() ?? baseUrl;

    var interpolated = rawSpec.trim();
    if (page != null) {
      interpolated = LegadoSelectorEngine.resolvePageConditionals(
        interpolated,
        page,
      );
    }

    var urlPart = interpolated;
    Map<String, dynamic>? optionJson;

    final split = _splitUrlAndOptions(interpolated);
    if (split != null) {
      urlPart = split.urlPart;
      optionJson = LegadoBookSource.tryParseLenientJsonMap(split.optionsPart);
    }

    final mergedHeaders = <String, String>{...defaultHeaders};
    if (optionJson != null && optionJson['headers'] is Map) {
      final optHeaders = optionJson['headers'] as Map;
      for (final entry in optHeaders.entries) {
        mergedHeaders[entry.key.toString()] = entry.value.toString();
      }
    }

    final rawMethod =
        optionJson?['method']?.toString().trim().toUpperCase() ?? 'GET';
    final method = rawMethod.isEmpty ? 'GET' : rawMethod;
    final rawCharset = optionJson?['charset']?.toString().trim();
    final charset = (rawCharset != null && rawCharset.isNotEmpty)
        ? rawCharset
        : defaultCharset;
    final webView = optionJson?['webView'] == true;

    urlPart = _interpolateUrlString(
      urlPart,
      keyword: keyword,
      page: page,
      charset: charset,
      isJsonContext: false,
    ).trim();

    String? body = optionJson?['body']?.toString();
    if (body != null) {
      final contentType = mergedHeaders.entries
          .where((e) => e.key.toLowerCase() == 'content-type')
          .map((e) => e.value.toLowerCase())
          .firstOrNull;
      final isJsonBody =
          body.trimLeft().startsWith('{') ||
          body.trimLeft().startsWith('[') ||
          (contentType?.contains('json') ?? false);
      body = _interpolateUrlString(
        body,
        keyword: keyword,
        page: page,
        charset: charset,
        isJsonContext: isJsonBody,
      );
    }

    final resolvedUrl = SourceHttpClient.resolveUrl(urlPart, normalizedBase);

    return LegadoRequestSpec(
      url: resolvedUrl,
      method: method,
      body: body,
      headers: mergedHeaders,
      charset: charset,
      webView: webView,
    );
  }

  /// Dynamic URL parser supporting embedded `<js>`/`@js:` scripts and `{{...}}`
  /// JS/cookie/source expressions before parsing URL + options.
  Future<LegadoRequestSpec> parseUrlSpecAsync(
    String rawSpec, {
    required String baseUrl,
    Map<String, String> defaultHeaders = const <String, String>{},
    String? defaultCharset,
    String? keyword,
    int? page,
    LegadoEvalSession? session,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final trimmed = rawSpec.trim();
    _guardUnsupportedFeatures(trimmed);

    final activeSession = session ?? LegadoEvalSession();
    if (httpClient != null) {
      await activeSession.preloadCookies(httpClient!, <String>[
        baseUrl,
        source?.bookSourceUrl ?? '',
        source?.normalizedBaseUrl ?? '',
      ]);
    }

    var working = trimmed;
    final stages = _parseStages(working);
    final hasJsStage = stages.any((s) => s is _JsStage);

    if (hasJsStage) {
      var current = '';
      for (final stage in stages) {
        switch (stage) {
          case _SelectorStage(:final rule):
            current = await _resolveMustacheInRule(
              rule,
              input: current,
              baseUrl: baseUrl,
              keyword: keyword,
              page: page,
              session: activeSession,
              cancelToken: cancelToken,
            );
          case _JsStage(:final code):
            var jsInput = code;
            if (jsInput.contains('{{') && jsInput.contains('}}')) {
              jsInput = await _resolveMustacheExpressionsOnly(
                jsInput,
                input: current,
                baseUrl: baseUrl,
                keyword: keyword,
                page: page,
                session: activeSession,
                preserveKeyPage: true,
                isJsCode: true,
                cancelToken: cancelToken,
              );
            }
            jsInput = _interpolateKeyPageLiterals(
              jsInput,
              keyword: keyword,
              page: page,
              isJsCode: true,
            );
            current = await _runJsSnippet(
              jsInput,
              result: current,
              baseUrl: baseUrl,
              keyword: keyword,
              page: page,
              session: activeSession,
              cancelToken: cancelToken,
            );
        }
      }
      working = current;
    } else if (working.contains('{{') && working.contains('}}')) {
      working = await _resolveMustacheForUrl(
        working,
        baseUrl: baseUrl,
        keyword: keyword,
        page: page,
        session: activeSession,
        cancelToken: cancelToken,
      );
    }

    if (httpClient != null) {
      await activeSession.flushCookies(httpClient!);
    }

    return parseUrlSpec(
      working,
      baseUrl: baseUrl,
      defaultHeaders: defaultHeaders,
      defaultCharset: defaultCharset,
      keyword: keyword,
      page: page,
    );
  }

  /// Resolves static or `<js>`/`@js:` dynamic `header` configuration into HTTP
  /// headers.
  Future<Map<String, String>> evaluateHeaders({
    required String baseUrl,
    LegadoEvalSession? session,
    CancellationToken? cancelToken,
  }) async {
    final src = source;
    if (src == null) return const <String, String>{};
    final rawHeader = src.rawHeader;
    if (rawHeader == null || rawHeader.trim().isEmpty) {
      return src.headers;
    }
    if (!rawHeader.contains('<js>') &&
        !rawHeader.toLowerCase().startsWith('@js:')) {
      return src.headers;
    }
    final activeSession = session ?? LegadoEvalSession();
    final evaluated = await evaluateString(
      '',
      rawHeader,
      baseUrl: baseUrl,
      session: activeSession,
      cancelToken: cancelToken,
    );
    return LegadoBookSource.parseStaticHeaderField(evaluated);
  }

  /// Evaluates a Legado field rule supporting chained selectors, combinators,
  /// XPath, JSONPath, regex `##`, `@put:`/`@get:`, `{{...}}`, and `<js>`/`@js:`.
  Future<List<String>> evaluateList(
    String input,
    String rule, {
    required String baseUrl,
    String? keyword,
    int? page,
    LegadoEvalSession? session,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    var workingRule = rule.trim();
    if (workingRule.isEmpty) return const <String>[];

    _guardUnsupportedFeatures(workingRule);

    final activeSession = session ?? LegadoEvalSession();
    if (httpClient != null) {
      await activeSession.preloadCookies(httpClient!, <String>[
        baseUrl,
        source?.bookSourceUrl ?? '',
        source?.normalizedBaseUrl ?? '',
      ]);
    }

    workingRule = await _processPutAndGet(
      workingRule,
      input: input,
      baseUrl: baseUrl,
      session: activeSession,
      cancelToken: cancelToken,
    );

    final stages = _parseStages(workingRule);
    var values = <String>[input];

    for (var i = 0; i < stages.length; i++) {
      cancelToken?.throwIfCancelled();
      final stage = stages[i];
      final isLastStage = i == stages.length - 1;

      switch (stage) {
        case _SelectorStage(:final rule):
          final nextValues = <String>[];
          for (final currentInput in values) {
            nextValues.addAll(
              await _evaluateSelectorStageList(
                currentInput,
                rule,
                baseUrl: baseUrl,
                keyword: keyword,
                page: page,
                session: activeSession,
                cancelToken: cancelToken,
              ),
            );
          }
          values = nextValues;

        case _JsStage(:final code):
          final nextValues = <String>[];
          final inputs = values.isEmpty ? const <String>[''] : values;
          for (final currentInput in inputs) {
            final resolvedCode =
                (code.contains('{{') && code.contains('}}'))
                    ? await _resolveMustacheExpressionsOnly(
                        code,
                        input: currentInput,
                        baseUrl: baseUrl,
                        keyword: keyword,
                        page: page,
                        session: activeSession,
                        isJsCode: true,
                        cancelToken: cancelToken,
                      )
                    : code;
            final jsOut = await _runJsSnippet(
              resolvedCode,
              result: currentInput,
              src: input,
              baseUrl: baseUrl,
              keyword: keyword,
              page: page,
              session: activeSession,
              cancelToken: cancelToken,
            );
            if (jsOut.isEmpty) continue;
            final trimmedOut = jsOut.trim();
            if (isLastStage &&
                trimmedOut.startsWith('[') &&
                trimmedOut.endsWith(']')) {
              final unpacked = _tryDecodeJsonStringList(trimmedOut);
              if (unpacked != null) {
                nextValues.addAll(unpacked);
                continue;
              }
            }
            nextValues.add(jsOut);
          }
          values = nextValues;
      }
      if (values.isEmpty && stage is _SelectorStage) {
        break;
      }
    }

    if (httpClient != null) {
      await activeSession.flushCookies(httpClient!);
    }

    return values;
  }

  /// Evaluates [rule] and returns a single string (joining `&&` branches with
  /// [joinSeparator] when applicable).
  Future<String> evaluateString(
    String input,
    String rule, {
    required String baseUrl,
    String? keyword,
    int? page,
    LegadoEvalSession? session,
    String joinSeparator = '\n',
    CancellationToken? cancelToken,
  }) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return '';

    final stages = _parseStages(trimmed);
    if (stages.length == 1 && stages.first is _SelectorStage) {
      _guardUnsupportedFeatures(trimmed);
      final activeSession = session ?? LegadoEvalSession();
      final bareGet = _tryResolveBareGetRule(trimmed, activeSession);
      if (bareGet != null) {
        return bareGet;
      }
      final cleaned = await _processPutAndGet(
        trimmed,
        input: input,
        baseUrl: baseUrl,
        session: activeSession,
        cancelToken: cancelToken,
      );
      final regexGroups = LegadoSelectorEngine.decodeRegexMatch(input);
      final String resultStr;
      if (regexGroups != null) {
        resultStr = await _evaluateRegexMatchedOne(
          regexGroups,
          input,
          cleaned,
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: activeSession,
          joinSeparator: joinSeparator,
          cancelToken: cancelToken,
        );
      } else {
        final isTemplate = _isMustacheTemplateRule(cleaned);
        final resolved = await _resolveMustacheInRule(
          cleaned,
          input: input,
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: activeSession,
          cancelToken: cancelToken,
        );
        if (isTemplate) {
          final (:selectorPart, :regexSpec) =
              LegadoSelectorEngine.splitTrailingRegex(resolved);
          resultStr = regexSpec.isEmpty
              ? selectorPart
              : LegadoSelectorEngine.applyRegexSpec(selectorPart, regexSpec);
        } else {
          final normalized = _normalizeRuleForInput(input, resolved);
          resultStr = LegadoSelectorEngine.selectOne(
            input,
            normalized,
            joinSeparator: joinSeparator,
          );
        }
      }
      if (httpClient != null) {
        await activeSession.flushCookies(httpClient!);
      }
      return resultStr;
    }

    final list = await evaluateList(
      input,
      rule,
      baseUrl: baseUrl,
      keyword: keyword,
      page: page,
      session: session,
      cancelToken: cancelToken,
    );
    return list.isEmpty ? '' : list.first;
  }

  /// Evaluates a list rule (`bookList`, `chapterList`) supporting Legado chained
  /// CSS, XPath, JSONPath, combinators, and `<js>`/`@js:` stages returning JSON
  /// arrays or HTML blocks.
  Future<({List<String> items, bool reversed})> evaluateListBlocks(
    String input,
    String rawListRule, {
    required String baseUrl,
    LegadoEvalSession? session,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    var working = rawListRule.trim();
    if (working.isEmpty) {
      return (items: const <String>[], reversed: false);
    }

    var reversed = false;
    if (working.startsWith('-')) {
      reversed = true;
      working = working.substring(1).trim();
    }

    _guardUnsupportedFeatures(working);

    final activeSession = session ?? LegadoEvalSession();
    working = await _processPutAndGet(
      working,
      input: input,
      baseUrl: baseUrl,
      session: activeSession,
      cancelToken: cancelToken,
    );

    final stages = _parseStages(working);
    var blocks = <String>[input];

    for (var i = 0; i < stages.length; i++) {
      cancelToken?.throwIfCancelled();
      final stage = stages[i];

      switch (stage) {
        case _SelectorStage(:final rule):
          final next = <String>[];
          for (final current in blocks) {
            final resolved = await _resolveMustacheInRule(
              rule,
              input: current,
              baseUrl: baseUrl,
              session: activeSession,
              cancelToken: cancelToken,
            );
            final normalized = _normalizeRuleForInput(current, resolved);
            next.addAll(
              LegadoSelectorEngine.selectElements(current, normalized),
            );
          }
          blocks = next;

        case _JsStage(:final code):
          final next = <String>[];
          if (i > 0 &&
              blocks.isNotEmpty &&
              !LegadoSelectorEngine.isRegexMatchEnvelope(blocks.first) &&
              !_isJsonInput(blocks.first)) {
            final resolvedCode =
                (code.contains('{{') && code.contains('}}'))
                    ? await _resolveMustacheExpressionsOnly(
                        code,
                        input: input,
                        baseUrl: baseUrl,
                        session: activeSession,
                        isJsCode: true,
                        cancelToken: cancelToken,
                      )
                    : code;
            final jsOut = await _runJsSnippet(
              resolvedCode,
              result: input,
              src: input,
              elementBlocks: blocks,
              baseUrl: baseUrl,
              session: activeSession,
              cancelToken: cancelToken,
            );
            if (jsOut.isNotEmpty) {
              final trimmedOut = jsOut.trim();
              final hasFollowingJsonSelector = i + 1 < stages.length &&
                  stages[i + 1] is _SelectorStage &&
                  (_looksLikeJsonRule((stages[i + 1] as _SelectorStage).rule));
              if (!hasFollowingJsonSelector &&
                  trimmedOut.startsWith('[') &&
                  trimmedOut.endsWith(']')) {
                final unpacked = _tryDecodeJsonRawItems(trimmedOut);
                if (unpacked != null) {
                  next.addAll(unpacked);
                } else {
                  next.add(jsOut);
                }
              } else {
                next.add(jsOut);
              }
            }
          } else {
            final inputs = blocks.isEmpty ? const <String>[''] : blocks;
            for (final current in inputs) {
              final resolvedCode =
                  (code.contains('{{') && code.contains('}}'))
                      ? await _resolveMustacheExpressionsOnly(
                          code,
                          input: current,
                          baseUrl: baseUrl,
                          session: activeSession,
                          isJsCode: true,
                          cancelToken: cancelToken,
                        )
                      : code;
              final jsOut = await _runJsSnippet(
                resolvedCode,
                result: current,
                src: input,
                baseUrl: baseUrl,
                session: activeSession,
                cancelToken: cancelToken,
              );
              if (jsOut.isEmpty) continue;
              final trimmedOut = jsOut.trim();
              final hasFollowingJsonSelector = i + 1 < stages.length &&
                  stages[i + 1] is _SelectorStage &&
                  (_looksLikeJsonRule((stages[i + 1] as _SelectorStage).rule));
              if (!hasFollowingJsonSelector &&
                  trimmedOut.startsWith('[') &&
                  trimmedOut.endsWith(']')) {
                final unpacked = _tryDecodeJsonRawItems(trimmedOut);
                if (unpacked != null) {
                  next.addAll(unpacked);
                  continue;
                }
              }
              next.add(jsOut);
            }
          }
          blocks = next;
      }

      if (blocks.isEmpty && stage is _SelectorStage) {
        break;
      }
    }

    if (httpClient != null) {
      await activeSession.flushCookies(httpClient!);
    }

    return (items: blocks, reversed: reversed);
  }

  static String? _tryResolveBareGetRule(
    String rule,
    LegadoEvalSession session,
  ) {
    final trimmed = rule.trim();
    final match = RegExp(
      r'^@get\s*:\s*\{([^}]+)\}(?:##([\s\S]*))?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) return null;
    final key = _stripQuotes(match.group(1) ?? '');
    final value = session.javaVars[key] ?? '';
    final regexSpec = match.group(2);
    if (regexSpec != null && regexSpec.isNotEmpty) {
      return LegadoSelectorEngine.applyRegexSpec(value, regexSpec);
    }
    return value;
  }

  Future<String> _processPutAndGet(
    String rule, {
    required String input,
    required String baseUrl,
    required LegadoEvalSession session,
    CancellationToken? cancelToken,
  }) async {
    var out = rule;

    if (out.contains('@put:')) {
      final putMatches = RegExp(
        r'@put\s*:\s*\{([^}]*)\}',
        caseSensitive: false,
      ).allMatches(out).toList();
      for (final m in putMatches) {
        final body = m.group(1) ?? '';
        final pairs = _parsePutPairs(body);
        for (final entry in pairs.entries) {
          final val = await evaluateString(
            input,
            entry.value,
            baseUrl: baseUrl,
            session: session,
            cancelToken: cancelToken,
          );
          session.javaVars[entry.key] = val;
        }
      }
      out = out.replaceAll(
        RegExp(r'@put\s*:\s*\{[^}]*\}', caseSensitive: false),
        '',
      );
    }

    if (out.contains('@get:')) {
      out = out.replaceAllMapped(
        RegExp(r'@get\s*:\s*\{([^}]+)\}', caseSensitive: false),
        (m) {
          final key = _stripQuotes(m.group(1) ?? '');
          return session.javaVars[key] ?? '';
        },
      );
    }

    return out.trim();
  }

  Future<List<String>> _evaluateSelectorStageList(
    String currentInput,
    String rule, {
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    CancellationToken? cancelToken,
  }) async {
    final bareGet = _tryResolveBareGetRule(rule, session);
    if (bareGet != null) {
      return bareGet.isEmpty ? const <String>[] : <String>[bareGet];
    }
    final regexGroups = LegadoSelectorEngine.decodeRegexMatch(currentInput);
    if (regexGroups != null) {
      return _evaluateRegexMatchedList(
        regexGroups,
        currentInput,
        rule,
        baseUrl: baseUrl,
        keyword: keyword,
        page: page,
        session: session,
        cancelToken: cancelToken,
      );
    }
    final isTemplate = _isMustacheTemplateRule(rule);
    final resolvedRule = await _resolveMustacheInRule(
      rule,
      input: currentInput,
      baseUrl: baseUrl,
      keyword: keyword,
      page: page,
      session: session,
      cancelToken: cancelToken,
    );
    if (isTemplate) {
      final (:selectorPart, :regexSpec) =
          LegadoSelectorEngine.splitTrailingRegex(resolvedRule);
      final value = regexSpec.isEmpty
          ? selectorPart
          : LegadoSelectorEngine.applyRegexSpec(selectorPart, regexSpec);
      return value.isEmpty ? const <String>[] : <String>[value];
    }
    final normalized = _normalizeRuleForInput(currentInput, resolvedRule);
    return LegadoSelectorEngine.selectValues(currentInput, normalized);
  }

  Future<String> _evaluateRegexMatchedOne(
    List<String> regexGroups,
    String envelopeInput,
    String rule, {
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    required String joinSeparator,
    CancellationToken? cancelToken,
  }) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return '';

    final orParts = LegadoSelectorEngine.splitTopLevel(trimmed, '||');
    if (orParts.length > 1) {
      for (final branch in orParts) {
        final val = await _evaluateRegexMatchedOne(
          regexGroups,
          envelopeInput,
          branch,
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: session,
          joinSeparator: joinSeparator,
          cancelToken: cancelToken,
        );
        if (val.isNotEmpty) return val;
      }
      return '';
    }

    final andParts = LegadoSelectorEngine.splitTopLevel(trimmed, '&&');
    if (andParts.length > 1) {
      final combined = <String>[];
      for (final branch in andParts) {
        final vals = await _evaluateRegexMatchedList(
          regexGroups,
          envelopeInput,
          branch,
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: session,
          cancelToken: cancelToken,
        );
        combined.addAll(vals.where((v) => v.isNotEmpty));
      }
      return combined.join(joinSeparator);
    }

    final vals = await _evaluateRegexMatchedList(
      regexGroups,
      envelopeInput,
      trimmed,
      baseUrl: baseUrl,
      keyword: keyword,
      page: page,
      session: session,
      cancelToken: cancelToken,
    );
    return vals.isEmpty ? '' : vals.first;
  }

  Future<List<String>> _evaluateRegexMatchedList(
    List<String> regexGroups,
    String envelopeInput,
    String rule, {
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    CancellationToken? cancelToken,
  }) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const <String>[];

    final orParts = LegadoSelectorEngine.splitTopLevel(trimmed, '||');
    if (orParts.length > 1) {
      for (final part in orParts) {
        final res = await _evaluateRegexMatchedList(
          regexGroups,
          envelopeInput,
          part,
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: session,
          cancelToken: cancelToken,
        );
        if (res.isNotEmpty) return res;
      }
      return const <String>[];
    }

    final andParts = LegadoSelectorEngine.splitTopLevel(trimmed, '&&');
    if (andParts.length > 1) {
      final combined = <String>[];
      for (final part in andParts) {
        combined.addAll(
          await _evaluateRegexMatchedList(
            regexGroups,
            envelopeInput,
            part,
            baseUrl: baseUrl,
            keyword: keyword,
            page: page,
            session: session,
            cancelToken: cancelToken,
          ),
        );
      }
      return combined;
    }

    final zipParts = LegadoSelectorEngine.splitTopLevel(trimmed, '%%');
    if (zipParts.length > 1) {
      final lists = <List<String>>[];
      var maxLen = 0;
      for (final part in zipParts) {
        final res = await _evaluateRegexMatchedList(
          regexGroups,
          envelopeInput,
          part,
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: session,
          cancelToken: cancelToken,
        );
        if (res.isNotEmpty) {
          lists.add(res);
          if (res.length > maxLen) maxLen = res.length;
        }
      }
      if (lists.isEmpty) return const <String>[];
      final zipped = <String>[];
      for (var i = 0; i < maxLen; i++) {
        for (final list in lists) {
          if (i < list.length) zipped.add(list[i]);
        }
      }
      return zipped;
    }

    return _evaluateRegexMatchedLeaf(
      regexGroups,
      envelopeInput,
      trimmed,
      baseUrl: baseUrl,
      keyword: keyword,
      page: page,
      session: session,
      cancelToken: cancelToken,
    );
  }

  Future<List<String>> _evaluateRegexMatchedLeaf(
    List<String> regexGroups,
    String envelopeInput,
    String branch, {
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    CancellationToken? cancelToken,
  }) async {
    final bareGet = _tryResolveBareGetRule(branch, session);
    if (bareGet != null) {
      return bareGet.isEmpty ? const <String>[] : <String>[bareGet];
    }

    final (:selectorPart, :regexSpec) =
        LegadoSelectorEngine.splitTrailingRegex(branch);
    final hasCaptureRef =
        LegadoSelectorEngine.containsCaptureGroupRef(selectorPart);

    if (hasCaptureRef || _isPureSingleMustache(selectorPart)) {
      var value = await _resolveMustacheInRule(
        selectorPart,
        input: envelopeInput,
        baseUrl: baseUrl,
        keyword: keyword,
        page: page,
        session: session,
        regexGroups: regexGroups,
        expandCaptures: true,
        cancelToken: cancelToken,
      );
      if (regexSpec.isNotEmpty) {
        final resolvedRegexSpec = await _resolveMustacheInRule(
          regexSpec,
          input: envelopeInput,
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: session,
          regexGroups: regexGroups,
          cancelToken: cancelToken,
        );
        value = LegadoSelectorEngine.applyRegexSpec(value, resolvedRegexSpec);
      }
      return value.isEmpty ? const <String>[] : <String>[value];
    }

    final resolvedBranch = await _resolveMustacheInRule(
      branch,
      input: envelopeInput,
      baseUrl: baseUrl,
      keyword: keyword,
      page: page,
      session: session,
      regexGroups: regexGroups,
      cancelToken: cancelToken,
    );
    return LegadoSelectorEngine.selectValues(envelopeInput, resolvedBranch);
  }

  static bool _isPureSingleMustache(String selectorPart) {
    final trimmed = selectorPart.trim();
    if (!trimmed.startsWith('{{') || !trimmed.endsWith('}}')) return false;
    final matches = _findMustacheExpressions(trimmed);
    return matches.length == 1 &&
        matches.first.start == 0 &&
        matches.first.end == trimmed.length;
  }

  Future<String> _resolveMustacheInRule(
    String rule, {
    required String input,
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    List<String>? regexGroups,
    bool expandCaptures = false,
    CancellationToken? cancelToken,
  }) async {
    String expandLiteral(String text) => expandCaptures && regexGroups != null
        ? LegadoSelectorEngine.expandCaptureGroups(text, regexGroups)
        : text;

    var out = rule;
    if (!expandCaptures &&
        page != null &&
        out.contains('<') &&
        out.contains(',')) {
      out = LegadoSelectorEngine.interpolateTemplate(out, page: page);
    }
    if (out.contains('{{') && out.contains('}}')) {
      out = await _resolveMustacheExpressionsOnly(
        out,
        input: input,
        baseUrl: baseUrl,
        keyword: keyword,
        page: page,
        session: session,
        regexGroups: regexGroups,
        expandCaptures: expandCaptures,
        cancelToken: cancelToken,
      );
    } else {
      out = expandLiteral(out);
    }
    if (!expandCaptures && (out.contains(r'{$.') || out.contains('{@@'))) {
      final rawContext = (regexGroups != null && regexGroups.isNotEmpty)
          ? regexGroups[0]
          : input;
      out = LegadoSelectorEngine.interpolateTemplate(
        out,
        contextInput: rawContext,
      );
    }
    return out;
  }

  Future<String> _resolveMustacheExpressionsOnly(
    String out, {
    required String input,
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    List<String>? regexGroups,
    bool expandCaptures = false,
    bool preserveKeyPage = false,
    bool isJsCode = false,
    CancellationToken? cancelToken,
  }) async {
    String expandLiteral(String text) => expandCaptures && regexGroups != null
        ? LegadoSelectorEngine.expandCaptureGroups(text, regexGroups)
        : text;

    final matches = _findMustacheExpressions(out, isJsCode: isJsCode);
    if (matches.isEmpty) {
      return expandLiteral(out);
    }
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      buf.write(expandLiteral(out.substring(cursor, m.start)));
      final expr = m.expr.trim();
      if (preserveKeyPage && (expr == 'key' || expr == 'page')) {
        buf.write(out.substring(m.start, m.end));
      } else {
        final replacement = await _evaluateMustacheExpression(
          expr,
          input: input,
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: session,
          regexGroups: regexGroups,
          cancelToken: cancelToken,
        );
        buf.write(replacement);
      }
      cursor = m.end;
    }
    buf.write(expandLiteral(out.substring(cursor)));
    return buf.toString();
  }

  Future<String> _resolveMustacheForUrl(
    String urlSpec, {
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    CancellationToken? cancelToken,
  }) async {
    final matches = _findMustacheExpressions(urlSpec);
    if (matches.isEmpty) return urlSpec;
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      buf.write(urlSpec.substring(cursor, m.start));
      final expr = m.expr.trim();
      if (expr == 'key' || expr == 'page') {
        // Keep `{{key}}` and `{{page}}` intact so `parseUrlSpec` encodes them
        // according to charset and JSON/form context.
        buf.write(urlSpec.substring(m.start, m.end));
      } else {
        final val = await _evaluateMustacheExpression(
          expr,
          input: '',
          baseUrl: baseUrl,
          keyword: keyword,
          page: page,
          session: session,
          cancelToken: cancelToken,
        );
        buf.write(val);
      }
      cursor = m.end;
    }
    buf.write(urlSpec.substring(cursor));
    return buf.toString();
  }

  Future<String> _evaluateMustacheExpression(
    String expr, {
    required String input,
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    List<String>? regexGroups,
    CancellationToken? cancelToken,
  }) async {
    final effectiveInput = (regexGroups != null && regexGroups.isNotEmpty)
        ? regexGroups[0]
        : (LegadoSelectorEngine.decodeRegexMatch(input)?[0] ?? input);
    final groups = regexGroups ?? LegadoSelectorEngine.decodeRegexMatch(input);

    if (expr == 'key') return keyword ?? '';
    if (expr == 'page') return (page ?? 1).toString();
    if (expr == 'baseUrl') return baseUrl;
    if (expr == 'result') return effectiveInput;
    if (expr == 'chapter.title') return session.chapterTitle;
    if (expr == 'book.name') return session.bookName;

    if (groups != null) {
      final captureMatch = RegExp(r'^\$\{?(\d+)\}?$').firstMatch(expr);
      if (captureMatch != null) {
        final idx = int.tryParse(captureMatch.group(1)!);
        if (idx != null && idx >= 0 && idx < groups.length) {
          return groups[idx];
        }
        return '';
      }
    }

    if (expr.startsWith(r'$.') ||
        expr.startsWith(r'$[') ||
        expr.toLowerCase().startsWith('@json:')) {
      final clean = expr.toLowerCase().startsWith('@json:')
          ? expr.substring(6).trim()
          : expr;
      return LegadoSelectorEngine.selectOne(effectiveInput, clean);
    }
    if (expr.startsWith('@@')) {
      return LegadoSelectorEngine.selectOne(
        effectiveInput,
        expr.substring(2).trim(),
      );
    }
    if (expr.toLowerCase().startsWith('@xpath:')) {
      return LegadoSelectorEngine.selectOne(effectiveInput, expr);
    }

    final jsExpr = expr.toLowerCase().startsWith('@js:')
        ? expr.substring(4).trim()
        : expr;
    return _runJsSnippet(
      jsExpr,
      result: input,
      src: effectiveInput,
      baseUrl: baseUrl,
      keyword: keyword,
      page: page,
      session: session,
      regexGroups: groups,
      cancelToken: cancelToken,
    );
  }

  Future<String> _runJsSnippet(
    String jsCode, {
    required String result,
    String? src,
    List<String>? elementBlocks,
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    List<String>? regexGroups,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    _guardUnsupportedFeatures(jsCode);

    final bookSource = source;
    final rawSourceKey = bookSource?.bookSourceUrl ?? baseUrl;
    var activeBaseUrl =
        SourceHttpClient.tryNormalizeHttpUri(baseUrl)?.toString() ?? baseUrl;
    final resolvedGroups =
        regexGroups ?? LegadoSelectorEngine.decodeRegexMatch(result);
    final effectiveResult = (resolvedGroups != null && resolvedGroups.isNotEmpty)
        ? resolvedGroups[0]
        : result;
    final effectiveSrc = src ?? effectiveResult;
    var currentContent = effectiveResult;

    final jsoupBridge = LegadoJsoupBridge();
    final syncHost = <String, HostSyncCallback>{
      ...jsoupBridge.buildSyncHostFunctions(),
      'javaPut': (args) {
        final k = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final v = args.length > 1 ? (args[1]?.toString() ?? '') : '';
        session.javaVars[k] = v;
        return v;
      },
      'javaGetVar': (args) {
        final k = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        return session.javaVars[k] ?? '';
      },
      'javaToast': (args) {
        final msg = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        session.logs.add('[toast] $msg');
        return null;
      },
      'javaSetContent': (args) {
        currentContent = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        if (args.length > 1 && args[1] != null) {
          final nextBase = args[1].toString().trim();
          if (nextBase.isNotEmpty) {
            activeBaseUrl =
                SourceHttpClient.tryNormalizeHttpUri(nextBase)?.toString() ??
                nextBase;
          }
        }
        return null;
      },
      'javaGetString': (args) {
        final rule = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final targetArg = args.length > 1 ? args[1] : null;
        if (targetArg is List) {
          for (final item in targetArg) {
            final itemStr = _coerceJsTargetToString(item);
            final val = LegadoSelectorEngine.selectOne(
              itemStr,
              _normalizeRuleForInput(itemStr, rule),
            );
            if (val.isNotEmpty) return val;
          }
          return '';
        }
        final target = targetArg != null
            ? _coerceJsTargetToString(targetArg)
            : currentContent;
        return LegadoSelectorEngine.selectOne(
          target,
          _normalizeRuleForInput(target, rule),
        );
      },
      'javaGetStringList': (args) {
        final rule = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final targetArg = args.length > 1 ? args[1] : null;
        if (targetArg is List) {
          final out = <String>[];
          for (final item in targetArg) {
            final itemStr = _coerceJsTargetToString(item);
            out.addAll(
              LegadoSelectorEngine.selectValues(
                itemStr,
                _normalizeRuleForInput(itemStr, rule),
              ),
            );
          }
          return out;
        }
        final target = targetArg != null
            ? _coerceJsTargetToString(targetArg)
            : currentContent;
        return LegadoSelectorEngine.selectValues(
          target,
          _normalizeRuleForInput(target, rule),
        );
      },
      'javaGetElements': (args) {
        final rule = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final targetArg = args.length > 1 ? args[1] : null;
        if (targetArg is List) {
          final out = <String>[];
          for (final item in targetArg) {
            final itemStr = _coerceJsTargetToString(item);
            out.addAll(
              LegadoSelectorEngine.selectElements(
                itemStr,
                _normalizeRuleForInput(itemStr, rule),
              ),
            );
          }
          return out;
        }
        final target = targetArg != null
            ? _coerceJsTargetToString(targetArg)
            : currentContent;
        return LegadoSelectorEngine.selectElements(
          target,
          _normalizeRuleForInput(target, rule),
        );
      },
      'javaGetElement': (args) {
        final rule = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final targetArg = args.length > 1 ? args[1] : null;
        final target = targetArg != null
            ? _coerceJsTargetToString(targetArg)
            : currentContent;
        final list = LegadoSelectorEngine.selectElements(
          target,
          _normalizeRuleForInput(target, rule),
        );
        return list.isEmpty ? '' : list.first;
      },
      'javaDigestBytes': (args) {
        final dataArg = args.isNotEmpty ? args[0] : null;
        final alg = args.length > 1 ? (args[1]?.toString() ?? '') : '';
        return JsCryptoHelpers.digestBytes(
          JsCryptoHelpers.coerceBytes(dataArg, name: 'data'),
          alg,
        );
      },
      'javaHmacBytes': (args) {
        final dataArg = args.isNotEmpty ? args[0] : null;
        final keyArg = args.length > 1 ? args[1] : null;
        final alg = args.length > 2 ? (args[2]?.toString() ?? '') : '';
        return JsCryptoHelpers.hmacBytes(
          JsCryptoHelpers.coerceBytes(dataArg, name: 'data'),
          JsCryptoHelpers.coerceBytes(keyArg, name: 'key'),
          alg,
        );
      },
      'javaRandomUUID': (_) => _generateUuidV4(),
      'javaToURL': (args) {
        final rawUrl = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final rawBase = args.length > 1 ? args[1]?.toString() : null;
        final resolved = SourceHttpClient.resolveUrl(
          rawUrl,
          (rawBase != null && rawBase.trim().isNotEmpty)
              ? rawBase
              : activeBaseUrl,
        );
        final uri = Uri.tryParse(resolved);
        if (uri == null) {
          return <String, Object?>{
            'host': '',
            'protocol': '',
            'path': '',
            'file': '',
            'query': '',
            'port': -1,
            'authority': '',
            'href': resolved,
          };
        }
        return <String, Object?>{
          'host': uri.host,
          'protocol': uri.scheme,
          'path': uri.path,
          'file': uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path,
          'query': uri.query,
          'port': uri.hasPort ? uri.port : -1,
          'authority': uri.authority,
          'href': uri.toString(),
        };
      },
      'javaHtmlFormat': (args) {
        final rawHtml = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        return formatHtmlText(rawHtml);
      },
      'javaHexDecodeToString': (args) {
        final hex = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        return _hexDecodeToUtf8(hex);
      },
      'javaEncodeURI': (args) {
        final str = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final enc = args.length > 1 ? args[1]?.toString() : null;
        return SourceHttpClient.encodeQueryComponentForCharset(
          str,
          charset: enc,
        );
      },
      'javaDecodeURI': (args) {
        final str = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        try {
          return Uri.decodeComponent(str);
        } catch (_) {
          return str;
        }
      },
      'javaTimeFormat': (args) {
        final ms = _coerceTimestampMs(args.isNotEmpty ? args[0] : null);
        return _formatTimestamp(ms, utc: false);
      },
      'javaTimeFormatUTC': (args) {
        final ms = _coerceTimestampMs(args.isNotEmpty ? args[0] : null);
        var pattern = 'yyyy-MM-dd HH:mm:ss';
        var offsetRaw = 0;
        if (args.length == 2) {
          final second = args[1];
          final parsedNum = _tryParseInt(second);
          if (parsedNum != null &&
              (second is num ||
                  RegExp(r'^[+-]?\d+$').hasMatch(second.toString().trim()))) {
            offsetRaw = parsedNum;
          } else if (second != null && second.toString().trim().isNotEmpty) {
            pattern = second.toString();
          }
        } else if (args.length >= 3) {
          final second = args[1];
          if (second != null && second.toString().trim().isNotEmpty) {
            pattern = second.toString();
          }
          offsetRaw = _tryParseInt(args[2]) ?? 0;
        }
        final offsetMs = offsetRaw.abs() <= 24
            ? offsetRaw * 3600 * 1000
            : offsetRaw;
        return _formatTimestampWithPattern(
          ms + offsetMs,
          pattern: pattern,
          utc: true,
        );
      },
      'javaToNumChapter': (args) {
        final s = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        return toNumChapter(s);
      },
      'cookieGetCookie': (args) {
        final u = args.isNotEmpty ? (args[0]?.toString() ?? '') : rawSourceKey;
        return session.getCookieSync(u);
      },
      'cookieGetKey': (args) {
        final u = args.isNotEmpty ? (args[0]?.toString() ?? '') : rawSourceKey;
        final k = args.length > 1 ? (args[1]?.toString() ?? '') : '';
        return session.getCookieKeySync(u, k);
      },
      'cookieSetCookie': (args) {
        final u = args.isNotEmpty ? (args[0]?.toString() ?? '') : rawSourceKey;
        final v = args.length > 1 ? (args[1]?.toString() ?? '') : '';
        session.setCookieSync(u, v);
        return null;
      },
      'cookieRemoveCookie': (args) {
        final u = args.isNotEmpty ? (args[0]?.toString() ?? '') : rawSourceKey;
        session.removeCookieSync(u);
        return null;
      },
      'sourceGetVariable': (_) => session.sourceVariable,
      'sourceSetVariable': (args) {
        session.sourceVariable = args.isNotEmpty
            ? (args[0]?.toString() ?? '')
            : '';
        return null;
      },
      'bookGetVar': (args) {
        final k = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        return session.bookVars[k] ?? '';
      },
      'bookPutVar': (args) {
        final k = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final v = args.length > 1 ? (args[1]?.toString() ?? '') : '';
        session.bookVars[k] = v;
        return v;
      },
      'bookGetVariableStr': (_) {
        if (session.bookVariable.isNotEmpty) return session.bookVariable;
        if (session.bookVars.isNotEmpty) return jsonEncode(session.bookVars);
        return '';
      },
      'bookSetVariableStr': (args) {
        final v = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        session.bookVariable = v;
        if (v.trimLeft().startsWith('{')) {
          try {
            final decoded = jsonDecode(v);
            if (decoded is Map) {
              session.bookVars.clear();
              for (final e in decoded.entries) {
                session.bookVars[e.key.toString()] =
                    e.value?.toString() ?? '';
              }
            }
          } catch (_) {}
        }
        return null;
      },
      'bookGetCustomVariable': (_) {
        if (session.bookCustomVariable.isNotEmpty) {
          return session.bookCustomVariable;
        }
        return session.bookVars['custom'] ?? '';
      },
      'bookPutCustomVariable': (args) {
        final v = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        session.bookCustomVariable = v;
        return v;
      },
      'cacheGet': (args) {
        final k = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final entry = session.cacheEntries[k];
        if (entry == null) return null;
        if (entry.isExpired(DateTime.now().millisecondsSinceEpoch)) {
          session.cacheEntries.remove(k);
          return null;
        }
        return entry.value;
      },
      'cachePut': (args) {
        final k = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final v = args.length > 1 ? (args[1]?.toString() ?? '') : '';
        final saveSeconds = args.length > 2 ? _tryParseInt(args[2]) : null;
        final expiresAtMs = (saveSeconds != null && saveSeconds > 0)
            ? DateTime.now().millisecondsSinceEpoch + saveSeconds * 1000
            : null;
        session.cacheEntries[k] = LegadoCacheEntry(v, expiresAtMs);
        return null;
      },
      'cacheDelete': (args) {
        final k = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        session.cacheEntries.remove(k);
        return null;
      },
    };

    final asyncHost = <String, HostAsyncCallback>{
      'legadoAjax': (args) async {
        final client = httpClient;
        if (client == null) return '';
        final rawUrl = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final req = parseUrlSpec(
          rawUrl,
          baseUrl: activeBaseUrl,
          defaultHeaders: bookSource?.headers ?? const <String, String>{},
          defaultCharset: bookSource?.charset,
        );
        if (req.webView) {
          throw UnsupportedLegadoRuleFailure(
            message: 'Legado java.ajax target requires webView: true',
            feature: 'webView',
            sourceId: sourceId,
          );
        }
        final resp = await client.request(
          req.url,
          method: req.method,
          data: req.body,
          headers: req.headers,
          charsetOverride: req.charset,
          rateLimitMs: bookSource?.rateLimitMs ?? 0,
          cancelToken: cancelToken,
        );
        return resp.body;
      },
      'legadoAjaxAll': (args) async {
        final client = httpClient;
        final rawList = args.isNotEmpty && args[0] is List
            ? args[0] as List
            : const <Object?>[];
        if (rawList.isEmpty) return const <Map<String, Object?>>[];
        if (client == null) {
          return List<Map<String, Object?>>.generate(
            rawList.length,
            (_) => <String, Object?>{
              'body': '',
              'status': 0,
              'url': '',
              'headers': <String, String>{},
            },
          );
        }
        final results = List<Map<String, Object?>?>.filled(
          rawList.length,
          null,
        );
        var nextIdx = 0;
        const maxConcurrency = 4;
        final workerCount = rawList.length < maxConcurrency
            ? rawList.length
            : maxConcurrency;

        Future<void> runWorker() async {
          while (true) {
            cancelToken?.throwIfCancelled();
            final idx = nextIdx++;
            if (idx >= rawList.length) return;
            final rawUrl = rawList[idx]?.toString() ?? '';
            final req = parseUrlSpec(
              rawUrl,
              baseUrl: activeBaseUrl,
              defaultHeaders: bookSource?.headers ?? const <String, String>{},
              defaultCharset: bookSource?.charset,
            );
            if (req.webView) {
              throw UnsupportedLegadoRuleFailure(
                message: 'Legado java.ajaxAll target requires webView: true',
                feature: 'webView',
                sourceId: sourceId,
              );
            }
            final resp = await client.request(
              req.url,
              method: req.method,
              data: req.body,
              headers: req.headers,
              charsetOverride: req.charset,
              rateLimitMs: bookSource?.rateLimitMs ?? 0,
              cancelToken: cancelToken,
            );
            results[idx] = _buildJsHttpResponseMap(resp, requestedUrl: req.url);
          }
        }

        await Future.wait(
          List<Future<void>>.generate(workerCount, (_) => runWorker()),
        );
        return results
            .whereType<Map<String, Object?>>()
            .toList(growable: false);
      },
      'legadoHttpGet': (args) async {
        final client = httpClient;
        if (client == null) {
          return <String, Object?>{
            'body': '',
            'status': 0,
            'url': '',
            'headers': <String, String>{},
          };
        }
        final rawUrl = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final rawHeaders = args.length > 1 ? args[1] : null;
        final hdrs = <String, String>{...?bookSource?.headers};
        if (rawHeaders is Map) {
          for (final e in rawHeaders.entries) {
            hdrs[e.key.toString()] = e.value.toString();
          }
        }
        final resolved = SourceHttpClient.resolveUrl(rawUrl, activeBaseUrl);
        final resp = await client.request(
          resolved,
          method: 'GET',
          headers: hdrs,
          charsetOverride: bookSource?.charset,
          rateLimitMs: bookSource?.rateLimitMs ?? 0,
          cancelToken: cancelToken,
        );
        return _buildJsHttpResponseMap(resp, requestedUrl: resolved);
      },
      'legadoHttpPost': (args) async {
        final client = httpClient;
        if (client == null) {
          return <String, Object?>{
            'body': '',
            'status': 0,
            'url': '',
            'headers': <String, String>{},
          };
        }
        final rawUrl = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final body = args.length > 1 ? args[1]?.toString() : null;
        final rawHeaders = args.length > 2 ? args[2] : null;
        final hdrs = <String, String>{...?bookSource?.headers};
        if (rawHeaders is Map) {
          for (final e in rawHeaders.entries) {
            hdrs[e.key.toString()] = e.value.toString();
          }
        }
        final resolved = SourceHttpClient.resolveUrl(rawUrl, activeBaseUrl);
        final resp = await client.request(
          resolved,
          method: 'POST',
          data: body,
          headers: hdrs,
          charsetOverride: bookSource?.charset,
          rateLimitMs: bookSource?.rateLimitMs ?? 0,
          cancelToken: cancelToken,
        );
        return _buildJsHttpResponseMap(resp, requestedUrl: resolved);
      },
    };

    final runtime = QjsSandboxRuntime(
      sourceId: sourceId,
      memoryLimitBytes: memoryLimitBytes,
      syncHostFunctions: syncHost,
      asyncHostFunctions: asyncHost,
    );

    final prepared = _prepareLegadoJsBody(jsCode);
    final jsLibPrefix =
        bookSource?.jsLib != null && bookSource!.jsLib!.trim().isNotEmpty
        ? '${bookSource.jsLib!}\n'
        : '';

    final wrapped = '''
function __normCryptoArg(v) {
  if (v == null) return null;
  if (Array.isArray(v)) return v;
  if (typeof ArrayBuffer !== "undefined" && ArrayBuffer.isView(v)) {
    return Array.from(v);
  }
  return String(v);
}
function __coerceTarget(t) {
  if (t == null) return null;
  if (typeof t === "string") return t;
  if (typeof t.outerHtml === "function") return t.outerHtml();
  if (Array.isArray(t)) {
    const out = [];
    for (let i = 0; i < t.length; i++) {
      const item = t[i];
      out.push(item && typeof item.outerHtml === "function" ? item.outerHtml() : String(item));
    }
    return out;
  }
  return String(t);
}
function __wrapResp(r) {
  const hdrs = (r && r.headers) ? r.headers : {};
  return {
    body: () => (r && r.body) ? String(r.body) : "",
    url: () => (r && r.url) ? String(r.url) : "",
    statusCode: () => (r && r.status) ? r.status : 0,
    header: (k) => {
      const lk = String(k).toLowerCase();
      return hdrs[lk] || hdrs[k] || "";
    },
    headers: (k) => {
      if (!k) return hdrs;
      const lk = String(k).toLowerCase();
      const v = hdrs[lk] || hdrs[k];
      return v ? [v] : [];
    },
    raw: () => ({ request: () => ({ url: () => (r && r.url) ? String(r.url) : "" }) })
  };
}
${LegadoJsoupBridge.jsPrelude}
Object.defineProperty(org.jsoup.nodes.Element.prototype, "toJSON", {
  value: function(key) {
    if (key === "") return { __pureReadOuterHtml: this.outerHtml() };
    return this.outerHtml();
  },
  enumerable: false,
  configurable: true,
  writable: true
});
Jsoup.connect = function(u) {
  const _url = String(u);
  const _hdrs = {};
  let _body = null;
  const conn = {
    userAgent: (ua) => { _hdrs["User-Agent"] = String(ua); return conn; },
    referrer: (r) => { _hdrs["Referer"] = String(r); return conn; },
    header: (k, v) => { _hdrs[String(k)] = String(v); return conn; },
    headers: (m) => { if (m && typeof m === "object") Object.assign(_hdrs, m); return conn; },
    timeout: () => conn,
    ignoreContentType: () => conn,
    ignoreHttpErrors: () => conn,
    followRedirects: () => conn,
    data: (k, v) => {
      if (typeof k === "object") { _body = k; }
      else { _body = (_body ? _body + "&" : "") + encodeURIComponent(k) + "=" + encodeURIComponent(v || ""); }
      return conn;
    },
    get: () => Jsoup.parse("", _url),
    post: () => Jsoup.parse("", _url),
    __asyncGet: async () => {
      const r = await host.legadoHttpGet(_url, _hdrs);
      return Jsoup.parse(r && r.body ? String(r.body) : "", (r && r.url) ? String(r.url) : _url);
    },
    __asyncPost: async () => {
      const r = await host.legadoHttpPost(_url, _body == null ? "" : (typeof _body === "string" ? _body : JSON.stringify(_body)), _hdrs);
      return Jsoup.parse(r && r.body ? String(r.body) : "", (r && r.url) ? String(r.url) : _url);
    }
  };
  return conn;
};
if (typeof __legadoResultBlocks !== "undefined" && Array.isArray(__legadoResultBlocks)) {
  const __els = new org.jsoup.select.Elements();
  for (let __i = 0; __i < __legadoResultBlocks.length; __i++) {
    const __raw = String(__legadoResultBlocks[__i]);
    if (/^\\s*<(tr|td|th|tbody|thead|tfoot)\\b/i.test(__raw)) {
      const __tdoc = org.jsoup.Jsoup.parse("<table>" + __raw + "</table>", baseUrl);
      const __picked = __tdoc.selectFirst("tr,td,th,tbody,thead,tfoot");
      if (__picked) { __els.push(__picked); continue; }
    }
    const __doc = org.jsoup.Jsoup.parse(__raw, baseUrl);
    const __body = __doc.selectFirst("body");
    const __kids = __body ? __body.children() : __doc.children();
    if (__kids && __kids.length > 0) {
      for (let __j = 0; __j < __kids.length; __j++) {
        __els.push(__kids[__j]);
      }
    } else {
      __els.push(__doc);
    }
  }
  result = __els;
}
var java = {
  put: (k, v) => host.javaPut(String(k), v == null ? "" : String(v)),
  get: (k) => host.javaGetVar(String(k)),
  __asyncAjax: async (u) => await host.legadoAjax(String(u)),
  __asyncAjaxAll: async (urls) => (await host.legadoAjaxAll(Array.isArray(urls) ? urls.map(u => String(u)) : [])).map(__wrapResp),
  __asyncHttpGet: async (u, h) => __wrapResp(await host.legadoHttpGet(String(u), h || null)),
  __asyncHttpPost: async (u, b, h) => __wrapResp(await host.legadoHttpPost(String(u), b == null ? "" : String(b), h || null)),
  __asyncConnect: async (u, h) => __wrapResp(await host.legadoHttpGet(String(u), h || null)),
  ajax: (u) => "",
  ajaxAll: (urls) => [],
  connect: (u, h) => __wrapResp({}),
  post: (u, b, h) => __wrapResp({}),
  setContent: (c, u) => { host.javaSetContent(c == null ? "" : String(c), u == null ? null : String(u)); },
  getString: (r, t) => host.javaGetString(String(r), __coerceTarget(t)),
  getStringList: (r, t) => host.javaGetStringList(String(r), __coerceTarget(t)),
  getElements: (r, t) => host.javaGetElements(String(r), __coerceTarget(t)),
  getElement: (r, t) => host.javaGetElement(String(r), __coerceTarget(t)),
  md5Encode: (s) => host.md5(s == null ? "" : String(s)),
  md5Encode16: (s) => host.md5Encode16(s == null ? "" : String(s)),
  base64Encode: (s) => host.base64Encode(s == null ? "" : String(s)),
  base64Decode: (s) => host.base64Decode(s == null ? "" : String(s)),
  digestHex: (d, alg) => host.digestHex(__normCryptoArg(d), alg == null ? "SHA-256" : String(alg)),
  digestBase64: (d, alg) => host.digestBase64(__normCryptoArg(d), alg == null ? "SHA-256" : String(alg)),
  sha256Encode: (s) => host.digestHex(s == null ? "" : String(s), "SHA-256"),
  sha1Encode: (s) => host.digestHex(s == null ? "" : String(s), "SHA-1"),
  sha512Encode: (s) => host.digestHex(s == null ? "" : String(s), "SHA-512"),
  hexEncodeToString: (s) => host.hexEncode(__normCryptoArg(s)),
  HMacHex: (d, alg, key) => host.hmacHex(__normCryptoArg(d), __normCryptoArg(key), String(alg)),
  HMacBase64: (d, alg, key) => host.hmacBase64(__normCryptoArg(d), __normCryptoArg(key), String(alg)),
  hmacHex: (d, alg, key) => host.hmacHex(__normCryptoArg(d), __normCryptoArg(key), String(alg)),
  hmacBase64: (d, alg, key) => host.hmacBase64(__normCryptoArg(d), __normCryptoArg(key), String(alg)),
  createDigest: (alg) => {
    const _alg = alg == null ? "SHA-256" : String(alg);
    return {
      digestHex: (d) => host.digestHex(__normCryptoArg(d), _alg),
      digestBase64: (d) => host.digestBase64(__normCryptoArg(d), _alg),
      digest: (d) => host.javaDigestBytes(__normCryptoArg(d), _alg),
    };
  },
  createHMac: (alg, key) => {
    const _alg = alg == null ? "HmacSHA256" : String(alg);
    const _k = __normCryptoArg(key);
    return {
      digestHex: (d) => host.hmacHex(__normCryptoArg(d), _k, _alg),
      digestBase64: (d) => host.hmacBase64(__normCryptoArg(d), _k, _alg),
      digest: (d) => host.javaHmacBytes(__normCryptoArg(d), _k, _alg),
    };
  },
  randomUUID: () => host.javaRandomUUID(),
  refreshTocUrl: () => {},
  toURL: (u, b) => {
    const parsed = host.javaToURL(u == null ? "" : String(u), b == null ? null : String(b));
    parsed.toString = () => parsed.href;
    return parsed;
  },
  htmlFormat: (h) => host.javaHtmlFormat(h == null ? "" : String(h)),
  strToBytes: (s) => host.strToBytes(s == null ? "" : String(s)),
  base64DecodeToByteArray: (s) => host.base64DecodeBytes(s == null ? "" : String(s)),
  hexDecodeToByteArray: (s) => host.hexDecodeBytes(s == null ? "" : String(s)),
  aesBase64DecodeToString: (str, key, transformation, iv) => host.aesDecodeBase64(str == null ? "" : String(str), __normCryptoArg(key), transformation == null ? null : String(transformation), __normCryptoArg(iv)),
  aesDecodeToString: (data, key, transformation, iv) => host.symmetricCrypto("decryptStr", transformation == null ? null : String(transformation), __normCryptoArg(key), __normCryptoArg(iv), __normCryptoArg(data)),
  aesBase64Encode: (str, key, transformation, iv) => host.aesEncodeBase64(__normCryptoArg(str), __normCryptoArg(key), transformation == null ? null : String(transformation), __normCryptoArg(iv)),
  aesEncodeToString: (str, key, transformation, iv) => host.aesEncodeBase64(__normCryptoArg(str), __normCryptoArg(key), transformation == null ? null : String(transformation), __normCryptoArg(iv)),
  aesEncodeToBase64String: (str, key, transformation, iv) => host.aesEncodeBase64(__normCryptoArg(str), __normCryptoArg(key), transformation == null ? null : String(transformation), __normCryptoArg(iv)),
  desEncodeToBase64String: (str, key, transformation, iv) => host.symmetricCrypto("encryptBase64", (transformation == null || String(transformation).trim() === "") ? ((iv != null && String(iv).length > 0) ? "DES/CBC/PKCS5Padding" : "DES/ECB/PKCS5Padding") : String(transformation), __normCryptoArg(key), __normCryptoArg(iv), __normCryptoArg(str)),
  desBase64DecodeToString: (str, key, transformation, iv) => host.symmetricCrypto("decryptBase64Str", (transformation == null || String(transformation).trim() === "") ? ((iv != null && String(iv).length > 0) ? "DES/CBC/PKCS5Padding" : "DES/ECB/PKCS5Padding") : String(transformation), __normCryptoArg(key), __normCryptoArg(iv), str == null ? "" : String(str)),
  createSymmetricCrypto: (transformation, key, iv) => {
    const _t = transformation == null ? "AES/ECB/PKCS5Padding" : String(transformation);
    const _k = __normCryptoArg(key);
    const _iv = __normCryptoArg(iv);
    host.symmetricCrypto("validate", _t, _k, _iv, null);
    return {
      decryptStr: (data) => host.symmetricCrypto("decryptStr", _t, _k, _iv, __normCryptoArg(data)),
      decrypt: (data) => host.symmetricCrypto("decrypt", _t, _k, _iv, __normCryptoArg(data)),
      decryptBase64Str: (data) => host.symmetricCrypto("decryptBase64Str", _t, _k, _iv, data == null ? "" : String(data)),
      decryptHexStr: (data) => host.symmetricCrypto("decryptHexStr", _t, _k, _iv, data == null ? "" : String(data)),
      decryptBase64: (data) => host.symmetricCrypto("decryptBase64", _t, _k, _iv, data == null ? "" : String(data)),
      decryptHex: (data) => host.symmetricCrypto("decryptHex", _t, _k, _iv, data == null ? "" : String(data)),
      encryptBase64: (str) => host.symmetricCrypto("encryptBase64", _t, _k, _iv, __normCryptoArg(str)),
      encryptHex: (str) => host.symmetricCrypto("encryptHex", _t, _k, _iv, __normCryptoArg(str)),
      encrypt: (str) => host.symmetricCrypto("encrypt", _t, _k, _iv, __normCryptoArg(str)),
    };
  },
  hexDecodeToString: (s) => host.javaHexDecodeToString(s == null ? "" : String(s)),
  encodeURI: (s, enc) => host.javaEncodeURI(s == null ? "" : String(s), enc == null ? null : String(enc)),
  decodeURI: (s) => host.javaDecodeURI(s == null ? "" : String(s)),
  timeFormat: (ts) => host.javaTimeFormat((ts instanceof Date) ? ts.getTime() : (ts || 0)),
  timeFormatUTC: function(ts, fmtOrOff, off) {
    const _ts = (ts instanceof Date) ? ts.getTime() : (ts || 0);
    if (off === undefined) {
      return host.javaTimeFormatUTC(_ts, fmtOrOff == null ? 0 : fmtOrOff);
    }
    return host.javaTimeFormatUTC(_ts, fmtOrOff == null ? "yyyy-MM-dd HH:mm:ss" : String(fmtOrOff), off == null ? 0 : off);
  },
  toNumChapter: (s) => host.javaToNumChapter(s == null ? "" : String(s)),
  t2s: (s) => s == null ? "" : String(s),
  s2t: (s) => s == null ? "" : String(s),
  getWebViewUA: () => ${jsonEncode(SourceHttpClient.defaultUserAgent)},
  log: (msg) => { host.log(msg == null ? "" : String(msg)); },
  toast: (msg) => { host.javaToast(msg == null ? "" : String(msg)); },
  longToast: (msg) => { host.javaToast(msg == null ? "" : String(msg)); },
  getCookie: (u, k) => k ? host.cookieGetKey(String(u), String(k)) : host.cookieGetCookie(String(u))
};
var cookie = {
  getCookie: (u) => host.cookieGetCookie(String(u)),
  getKey: (u, k) => host.cookieGetKey(String(u), String(k)),
  setCookie: (u, v) => { host.cookieSetCookie(String(u), String(v)); },
  removeCookie: (u) => { host.cookieRemoveCookie(String(u)); }
};
var book = {
  name: ${jsonEncode(session.bookName)},
  bookUrl: ${jsonEncode(session.bookUrl)},
  tocUrl: ${jsonEncode(session.tocUrl)},
  get variable() { return host.bookGetVariableStr(); },
  set variable(v) { host.bookSetVariableStr(v == null ? "" : String(v)); },
  getVariable: (k) => host.bookGetVar(k == null ? "" : String(k)),
  putVariable: (k, v) => host.bookPutVar(k == null ? "" : String(k), v == null ? "" : String(v)),
  getCustomVariable: () => host.bookGetCustomVariable(),
  putCustomVariable: (v) => host.bookPutCustomVariable(v == null ? "" : String(v)),
  setReverseToc: () => {}
};
var cache = {
  get: (k) => host.cacheGet(k == null ? "" : String(k)),
  put: (k, v, saveSeconds) => { host.cachePut(k == null ? "" : String(k), v == null ? "" : String(v), saveSeconds == null ? null : Number(saveSeconds)); },
  delete: (k) => { host.cacheDelete(k == null ? "" : String(k)); },
  getFromMemory: (k) => host.cacheGet(k == null ? "" : String(k)),
  putMemory: (k, v) => { host.cachePut(k == null ? "" : String(k), v == null ? "" : String(v), null); },
  deleteMemory: (k) => { host.cacheDelete(k == null ? "" : String(k)); }
};
var source = {
  key: ${jsonEncode(rawSourceKey)},
  bookSourceUrl: ${jsonEncode(rawSourceKey)},
  bookSourceName: ${jsonEncode(bookSource?.bookSourceName ?? '')},
  bookSourceComment: ${jsonEncode(bookSource?.bookSourceComment ?? '')},
  header: ${jsonEncode(bookSource?.rawHeader ?? '')},
  loginUrl: ${jsonEncode(bookSource?.loginUrl ?? '')},
  getKey: () => ${jsonEncode(rawSourceKey)},
  getVariable: () => host.sourceGetVariable(),
  setVariable: (v) => { host.sourceSetVariable(v == null ? "" : String(v)); },
  put: (k, v) => host.javaPut(String(k), v == null ? "" : String(v)),
  get: (k) => host.javaGetVar(String(k)),
  getHeaderMap: () => (${jsonEncode(bookSource?.headers ?? const <String, String>{})}),
  getLoginInfo: () => "",
  getLoginInfoMap: () => ({}),
  getLoginHeader: () => "",
  getLoginHeaderMap: () => ({})
};
$jsLibPrefix$prepared
''';

    final bindings = <String, Object?>{
      'result': effectiveResult,
      'src': effectiveSrc,
      'baseUrl': activeBaseUrl,
      'key': keyword ?? '',
      'page': page ?? 1,
      'title': session.chapterTitle,
      'chapter': <String, Object?>{
        'title': session.chapterTitle,
        'url': session.chapterUrl,
        'index': session.chapterIndex,
      },
    };
    if (elementBlocks != null) {
      bindings['__legadoResultBlocks'] = elementBlocks;
    }
    if (resolvedGroups != null) {
      for (var idx = 0; idx < resolvedGroups.length; idx++) {
        bindings['\$$idx'] = resolvedGroups[idx];
      }
    }

    try {
      final res = await runtime.evaluate(
        wrapped,
        bindings: bindings,
        timeout: jsTimeout,
        cancelToken: cancelToken,
      );
      session.logs.addAll(res.logs);
      final rawOut = res.value.trim();
      if (rawOut.startsWith('{"__pureReadOuterHtml":')) {
        try {
          final decoded = jsonDecode(rawOut);
          if (decoded is Map && decoded.containsKey('__pureReadOuterHtml')) {
            return (decoded['__pureReadOuterHtml']?.toString() ?? '').trim();
          }
        } catch (_) {}
      }
      return rawOut;
    } finally {
      jsoupBridge.dispose();
      await runtime.dispose();
    }
  }

  /// Rewrites synchronous-looking `java.ajax(...)`, `java.ajaxAll(...)`,
  /// `java.post(...)`, `java.connect(...)`, 2-arg `java.get(url, headers)`,
  /// and `Jsoup.connect(...)` `.get()`/`.post()` chains into `await` calls
  /// inside an async IIFE when present, leaving pure sync scripts untouched
  /// so QuickJS natively returns the final expression completion value.
  static String _prepareLegadoJsBody(String jsCode) {
    final hasAsyncCall =
        jsCode.contains('java.ajax(') ||
        jsCode.contains('java.ajaxAll(') ||
        jsCode.contains('java.connect(') ||
        jsCode.contains('java.post(') ||
        jsCode.contains('Jsoup.connect(') ||
        RegExp(r'java\.get\s*\([^,)]+,').hasMatch(jsCode);
    if (!hasAsyncCall) {
      return jsCode;
    }
    final rewritten = _rewriteAsyncHttpCalls(jsCode);
    final withReturn = _ensureTrailingReturn(rewritten);
    return '(async () => {\n$withReturn\n})()';
  }

  static String _rewriteAsyncHttpCalls(String code) {
    final out = StringBuffer();
    var i = 0;
    var inSingle = false;
    var inDouble = false;
    var inTemplate = false;

    while (i < code.length) {
      final ch = code[i];
      if (!inSingle && !inDouble && !inTemplate) {
        if (ch == '/' && i + 1 < code.length) {
          if (code[i + 1] == '/') {
            final nl = code.indexOf('\n', i);
            if (nl == -1) {
              out.write(code.substring(i));
              break;
            }
            out.write(code.substring(i, nl + 1));
            i = nl + 1;
            continue;
          }
          if (code[i + 1] == '*') {
            final end = code.indexOf('*/', i + 2);
            if (end == -1) {
              out.write(code.substring(i));
              break;
            }
            out.write(code.substring(i, end + 2));
            i = end + 2;
            continue;
          }
          final regexEnd = _findJsRegexLiteralEnd(code, i, code.length);
          if (regexEnd != -1) {
            out.write(code.substring(i, regexEnd));
            i = regexEnd;
            continue;
          }
        }

        if (ch == "'") {
          inSingle = true;
          out.write(ch);
          i++;
          continue;
        }
        if (ch == '"') {
          inDouble = true;
          out.write(ch);
          i++;
          continue;
        }
        if (ch == '`') {
          inTemplate = true;
          out.write(ch);
          i++;
          continue;
        }

        if (code.startsWith('Packages.org.jsoup.Jsoup.connect(', i) ||
            code.startsWith('org.jsoup.Jsoup.connect(', i) ||
            code.startsWith('Jsoup.connect(', i)) {
          final rewrittenConnect = _tryRewriteJsoupConnectChain(code, i);
          if (rewrittenConnect != null) {
            out.write(rewrittenConnect.replacement);
            i = rewrittenConnect.nextIndex;
            continue;
          }
        }

        String? target;
        String? replacementPrefix;
        if (code.startsWith('java.ajaxAll(', i)) {
          target = 'java.ajaxAll(';
          replacementPrefix = '(await java.__asyncAjaxAll(';
        } else if (code.startsWith('java.ajax(', i)) {
          target = 'java.ajax(';
          replacementPrefix = '(await java.__asyncAjax(';
        } else if (code.startsWith('java.connect(', i)) {
          target = 'java.connect(';
          replacementPrefix = '(await java.__asyncConnect(';
        } else if (code.startsWith('java.post(', i)) {
          target = 'java.post(';
          replacementPrefix = '(await java.__asyncHttpPost(';
        } else if (code.startsWith('java.get(', i)) {
          final argsEnd = _findMatchingParen(code, i + 'java.get('.length - 1);
          if (argsEnd != -1) {
            final inner = code.substring(i + 'java.get('.length, argsEnd);
            if (_hasTopLevelComma(inner)) {
              target = 'java.get(';
              replacementPrefix = '(await java.__asyncHttpGet(';
            }
          }
        }

        if (target != null && replacementPrefix != null) {
          final openIdx = i + target.length - 1;
          final closeIdx = _findMatchingParen(code, openIdx);
          if (closeIdx != -1) {
            final inner = _rewriteAsyncHttpCalls(
              code.substring(openIdx + 1, closeIdx),
            );
            out.write('$replacementPrefix$inner))');
            i = closeIdx + 1;
            continue;
          }
        }
      } else {
        if (ch == r'\' && i + 1 < code.length) {
          out.write(code.substring(i, i + 2));
          i += 2;
          continue;
        }
        if (inSingle && ch == "'") inSingle = false;
        if (inDouble && ch == '"') inDouble = false;
        if (inTemplate && ch == '`') inTemplate = false;
      }

      out.write(ch);
      i++;
    }
    return out.toString();
  }

  static String _ensureTrailingReturn(String code) {
    final trimmed = code.trimRight();
    if (trimmed.isEmpty) return trimmed;

    // Find the last top-level semicolon that has non-empty code after it
    // (excluding any single trailing semicolon at the very end).
    final lastSemi = _findLastStatementSplitSemicolon(trimmed);
    final prefix = lastSemi == -1 ? '' : trimmed.substring(0, lastSemi + 1);
    final tail = lastSemi == -1 ? trimmed : trimmed.substring(lastSemi + 1);
    final tailTrimmed = tail.trim();
    if (tailTrimmed.isEmpty) return trimmed;

    final firstLine = tailTrimmed
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && !l.startsWith('//'), orElse: () => '');
    if (firstLine.isEmpty ||
        firstLine.startsWith('return ') ||
        firstLine.startsWith('throw ') ||
        firstLine.startsWith('var ') ||
        firstLine.startsWith('let ') ||
        firstLine.startsWith('const ') ||
        RegExp(r'^(?:if|for|while|do|switch|try)\b').hasMatch(firstLine) ||
        firstLine.startsWith('function ') ||
        firstLine.startsWith('{') ||
        tailTrimmed.endsWith('}')) {
      return trimmed;
    }

    final cleanTail = tailTrimmed.endsWith(';')
        ? tailTrimmed.substring(0, tailTrimmed.length - 1).trimRight()
        : tailTrimmed;
    if (cleanTail.isEmpty) return trimmed;

    final leadingSpace = tail.substring(0, tail.length - tail.trimLeft().length);
    return '$prefix${leadingSpace}return ($cleanTail);';
  }

  static int _findLastStatementSplitSemicolon(String code) {
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    var inTemplate = false;
    var lastSplit = -1;

    // Ignore trailing whitespace and a single trailing semicolon at the end.
    var effectiveEnd = code.trimRight().length;
    if (effectiveEnd > 0 && code[effectiveEnd - 1] == ';') {
      effectiveEnd--;
    }

    for (var i = 0; i < effectiveEnd; i++) {
      final ch = code[i];
      if (!inSingle && !inDouble && !inTemplate) {
        if (ch == '/' && i + 1 < effectiveEnd) {
          if (code[i + 1] == '/') {
            final nl = code.indexOf('\n', i);
            if (nl == -1 || nl >= effectiveEnd) break;
            i = nl;
            continue;
          }
          if (code[i + 1] == '*') {
            final end = code.indexOf('*/', i + 2);
            if (end == -1 || end + 1 >= effectiveEnd) break;
            i = end + 1;
            continue;
          }
          final regexEnd = _findJsRegexLiteralEnd(code, i, effectiveEnd);
          if (regexEnd != -1) {
            i = regexEnd - 1;
            continue;
          }
        }
        if (ch == "'") {
          inSingle = true;
        } else if (ch == '"') {
          inDouble = true;
        } else if (ch == '`') {
          inTemplate = true;
        } else if (ch == '(' || ch == '[' || ch == '{') {
          depth++;
        } else if (ch == ')' || ch == ']' || ch == '}') {
          if (depth > 0) depth--;
        } else if (ch == ';' && depth == 0) {
          if (code.substring(i + 1, effectiveEnd).trim().isNotEmpty) {
            lastSplit = i;
          }
        }
      } else {
        if (ch == r'\' && i + 1 < effectiveEnd) {
          i++;
          continue;
        }
        if (inSingle && ch == "'") inSingle = false;
        if (inDouble && ch == '"') inDouble = false;
        if (inTemplate && ch == '`') inTemplate = false;
      }
    }
    return lastSplit;
  }

  static int _findMatchingParen(String code, int openIdx) {
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    var inTemplate = false;
    for (var i = openIdx; i < code.length; i++) {
      final ch = code[i];
      if (!inSingle && !inDouble && !inTemplate) {
        if (ch == '/' && i + 1 < code.length) {
          if (code[i + 1] == '/') {
            final nl = code.indexOf('\n', i);
            if (nl == -1) break;
            i = nl;
            continue;
          }
          if (code[i + 1] == '*') {
            final end = code.indexOf('*/', i + 2);
            if (end == -1) break;
            i = end + 1;
            continue;
          }
          final regexEnd = _findJsRegexLiteralEnd(code, i, code.length);
          if (regexEnd != -1) {
            i = regexEnd - 1;
            continue;
          }
        }
        if (ch == "'") {
          inSingle = true;
        } else if (ch == '"') {
          inDouble = true;
        } else if (ch == '`') {
          inTemplate = true;
        } else if (ch == '(') {
          depth++;
        } else if (ch == ')') {
          depth--;
          if (depth == 0) return i;
        }
      } else {
        if (ch == r'\') {
          i++;
          continue;
        }
        if (inSingle && ch == "'") inSingle = false;
        if (inDouble && ch == '"') inDouble = false;
        if (inTemplate && ch == '`') inTemplate = false;
      }
    }
    return -1;
  }

  static bool _hasTopLevelComma(String argsText) {
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    var inTemplate = false;
    for (var i = 0; i < argsText.length; i++) {
      final ch = argsText[i];
      if (!inSingle && !inDouble && !inTemplate) {
        if (ch == '/' && i + 1 < argsText.length) {
          if (argsText[i + 1] == '/') {
            final nl = argsText.indexOf('\n', i);
            if (nl == -1) break;
            i = nl;
            continue;
          }
          if (argsText[i + 1] == '*') {
            final end = argsText.indexOf('*/', i + 2);
            if (end == -1) break;
            i = end + 1;
            continue;
          }
          final regexEnd = _findJsRegexLiteralEnd(argsText, i, argsText.length);
          if (regexEnd != -1) {
            i = regexEnd - 1;
            continue;
          }
        }
        if (ch == "'") {
          inSingle = true;
        } else if (ch == '"') {
          inDouble = true;
        } else if (ch == '`') {
          inTemplate = true;
        } else if (ch == '(' || ch == '[' || ch == '{') {
          depth++;
        } else if (ch == ')' || ch == ']' || ch == '}') {
          if (depth > 0) depth--;
        } else if (ch == ',' && depth == 0) {
          return true;
        }
      } else {
        if (ch == r'\') {
          i++;
          continue;
        }
        if (inSingle && ch == "'") inSingle = false;
        if (inDouble && ch == '"') inDouble = false;
        if (inTemplate && ch == '`') inTemplate = false;
      }
    }
    return false;
  }

  static const Set<String> _regexPrefixKeywords = <String>{
    'return',
    'throw',
    'case',
    'delete',
    'void',
    'typeof',
    'in',
    'instanceof',
    'new',
    'else',
    'do',
    'await',
    'yield',
  };

  static bool _canStartJsRegexLiteral(String code, int slashIdx) {
    var k = slashIdx - 1;
    while (k >= 0 && _isWhitespaceChar(code.codeUnitAt(k))) {
      k--;
    }
    if (k < 0) return true;
    final prev = code.codeUnitAt(k);
    if (prev == 0x29 /* ) */ ||
        prev == 0x5D /* ] */ ||
        prev == 0x27 /* ' */ ||
        prev == 0x22 /* " */ ||
        prev == 0x60 /* ` */) {
      return false;
    }
    if ((prev == 0x2B /* + */ || prev == 0x2D /* - */) &&
        k > 0 &&
        code.codeUnitAt(k - 1) == prev) {
      return false;
    }
    if (_isJsIdentPart(prev)) {
      var start = k;
      while (start > 0 && _isJsIdentPart(code.codeUnitAt(start - 1))) {
        start--;
      }
      final token = code.substring(start, k + 1);
      return _regexPrefixKeywords.contains(token);
    }
    return true;
  }

  static int _findJsRegexLiteralEnd(String code, int slashIdx, int limit) {
    if (slashIdx + 1 >= limit || code[slashIdx] != '/') return -1;
    final next = code[slashIdx + 1];
    if (next == '/' || next == '*') return -1;
    if (!_canStartJsRegexLiteral(code, slashIdx)) return -1;

    var inCharClass = false;
    for (var j = slashIdx + 1; j < limit; j++) {
      final c = code[j];
      if (c == '\n' || c == '\r') return -1;
      if (c == r'\') {
        if (j + 1 >= limit) return -1;
        final escaped = code[j + 1];
        if (escaped == '\n' || escaped == '\r') return -1;
        j++;
        continue;
      }
      if (c == '[' && !inCharClass) {
        inCharClass = true;
      } else if (c == ']' && inCharClass) {
        inCharClass = false;
      } else if (c == '/' && !inCharClass) {
        var end = j + 1;
        while (end < limit && _isAsciiAlpha(code.codeUnitAt(end))) {
          end++;
        }
        return end;
      }
    }
    return -1;
  }

  static bool _isAsciiAlpha(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

  static List<_RuleStage> _parseStages(String rule) {
    final stages = <_RuleStage>[];
    var working = rule;

    // Extract trailing `@js:...` if not inside `<js>...</js>`.
    String? trailingAtJs;
    final atJsIdx = _findAtJsIndexOutsideTags(working);
    if (atJsIdx != -1) {
      trailingAtJs = working.substring(atJsIdx + 4).trim();
      working = working.substring(0, atJsIdx).trim();
    }

    final tagRegex = RegExp(r'<js>([\s\S]*?)</js>', caseSensitive: false);
    var cursor = 0;
    for (final m in tagRegex.allMatches(working)) {
      final before = working.substring(cursor, m.start).trim();
      if (before.isNotEmpty) {
        stages.add(_SelectorStage(before));
      }
      final jsBody = (m.group(1) ?? '').trim();
      if (jsBody.isNotEmpty) {
        stages.add(_JsStage(jsBody));
      }
      cursor = m.end;
    }

    final remaining = working.substring(cursor).trim();
    if (remaining.isNotEmpty) {
      stages.add(_SelectorStage(remaining));
    }

    if (trailingAtJs != null && trailingAtJs.isNotEmpty) {
      stages.add(_JsStage(trailingAtJs));
    }
    return stages;
  }

  static int _findAtJsIndexOutsideTags(String rule) {
    var cursor = 0;
    final tagRegex = RegExp(r'<js>[\s\S]*?</js>', caseSensitive: false);
    final blockedRanges = tagRegex
        .allMatches(rule)
        .map((m) => (m.start, m.end))
        .toList(growable: false);

    while (cursor < rule.length) {
      final idx = rule.indexOf('@js:', cursor);
      if (idx == -1) return -1;
      final insideTag = blockedRanges.any((r) => idx >= r.$1 && idx < r.$2);
      if (!insideTag) return idx;
      cursor = idx + 4;
    }
    return -1;
  }

  /// Checks all provided rule strings upfront and throws
  /// [UnsupportedLegadoRuleFailure] if any require interactive WebView or
  /// Rhino Java APIs.
  void guardUnsupportedRules(Iterable<String?> rules) {
    for (final rule in rules) {
      if (rule != null && rule.trim().isNotEmpty) {
        _guardUnsupportedFeatures(rule);
      }
    }
  }

  void _guardUnsupportedFeatures(String rule) {
    if (rule.contains('startBrowserAwait') ||
        RegExp(r'\bjava\.webView\b(?!UA)').hasMatch(rule)) {
      throw UnsupportedLegadoRuleFailure(
        message: 'Legado rule requires interactive WebView ($rule)',
        feature: 'webView',
        sourceId: sourceId,
      );
    }
    if (LegadoSourceParser.hasUnsupportedRhinoApi(rule)) {
      throw UnsupportedLegadoRuleFailure(
        message: 'Legado rule uses unsupported Rhino Java API: $rule',
        feature: 'rhino_java_api',
        sourceId: sourceId,
      );
    }
  }

  static String resolveUrlSpec(String rawSpec, String baseUrl) {
    final trimmed = rawSpec.trim();
    if (trimmed.isEmpty) return '';
    final split = _splitUrlAndOptions(trimmed);
    if (split == null) {
      return SourceHttpClient.resolveUrl(trimmed, baseUrl);
    }
    final resolvedUrl = SourceHttpClient.resolveUrl(split.urlPart, baseUrl);
    return '$resolvedUrl,${split.optionsPart}';
  }

  static ({String urlPart, String optionsPart})? _splitUrlAndOptions(
    String raw,
  ) {
    final trimmed = raw.trim();
    if (!trimmed.endsWith('}')) return null;

    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    for (var i = trimmed.length - 1; i >= 0; i--) {
      final ch = trimmed[i];
      final escaped = i > 0 && trimmed[i - 1] == r'\';
      if (!escaped) {
        if (ch == "'" && !inDouble) {
          inSingle = !inSingle;
        } else if (ch == '"' && !inSingle) {
          inDouble = !inDouble;
        } else if (!inSingle && !inDouble) {
          if (ch == '}') {
            depth++;
          } else if (ch == '{') {
            depth--;
            if (depth == 0) {
              var before = i - 1;
              while (before >= 0 &&
                  (trimmed[before] == ' ' ||
                      trimmed[before] == '\t' ||
                      trimmed[before] == '\n' ||
                      trimmed[before] == '\r')) {
                before--;
              }
              if (before >= 0 && trimmed[before] == ',') {
                return (
                  urlPart: trimmed.substring(0, before).trim(),
                  optionsPart: trimmed.substring(i).trim(),
                );
              }
              return null;
            }
          }
        }
      }
    }
    return null;
  }

  static String _interpolateUrlString(
    String raw, {
    String? keyword,
    int? page,
    String? charset,
    required bool isJsonContext,
  }) {
    var out = raw;
    if (keyword != null) {
      final encodedKey = isJsonContext
          ? keyword
          : SourceHttpClient.encodeQueryComponentForCharset(
              keyword,
              charset: charset,
            );
      out = out.replaceAll('{{key}}', encodedKey);
    }
    if (page != null) {
      out = out.replaceAll('{{page}}', page.toString());
    }
    return out;
  }

  static String _interpolateKeyPageLiterals(
    String code, {
    String? keyword,
    int? page,
    required bool isJsCode,
  }) {
    if ((keyword == null && page == null) ||
        !code.contains('{{') ||
        !code.contains('}}')) {
      return code;
    }
    final matches = _findMustacheExpressions(code, isJsCode: isJsCode);
    if (matches.isEmpty) return code;

    final buf = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      buf.write(code.substring(cursor, m.start));
      final expr = m.expr.trim();
      if (expr == 'key' && keyword != null) {
        buf.write(keyword);
      } else if (expr == 'page' && page != null) {
        buf.write(page.toString());
      } else {
        buf.write(code.substring(m.start, m.end));
      }
      cursor = m.end;
    }
    buf.write(code.substring(cursor));
    return buf.toString();
  }

  static List<({int start, int end, String expr})> _findMustacheExpressions(
    String input, {
    bool isJsCode = false,
  }) {
    if (!isJsCode) {
      final results = <({int start, int end, String expr})>[];
      var cursor = 0;
      while (cursor < input.length) {
        final open = input.indexOf('{{', cursor);
        if (open == -1) break;
        final close = _findMustacheClose(input, open + 2);
        if (close == -1) break;
        results.add((
          start: open,
          end: close + 2,
          expr: input.substring(open + 2, close),
        ));
        cursor = close + 2;
      }
      return results;
    }

    final results = <({int start, int end, String expr})>[];
    var inSingle = false;
    var inDouble = false;
    var inTemplate = false;
    final templateBraceStack = <int>[];

    var i = 0;
    while (i < input.length) {
      final ch = input.codeUnitAt(i);

      if (inSingle || inDouble || inTemplate) {
        if (ch == 0x5C /* \ */) {
          i += i + 1 < input.length ? 2 : 1;
          continue;
        }
        if (ch == 0x7B /* { */ &&
            i + 1 < input.length &&
            input.codeUnitAt(i + 1) == 0x7B) {
          final close = _findMustacheClose(input, i + 2);
          if (close != -1) {
            results.add((
              start: i,
              end: close + 2,
              expr: input.substring(i + 2, close),
            ));
            i = close + 2;
            continue;
          }
          i += 2;
          continue;
        }
        if (inTemplate &&
            ch == 0x24 /* $ */ &&
            i + 1 < input.length &&
            input.codeUnitAt(i + 1) == 0x7B /* { */) {
          templateBraceStack.add(1);
          inTemplate = false;
          i += 2;
          continue;
        }
        if (inSingle && ch == 0x27 /* ' */) {
          inSingle = false;
        } else if (inDouble && ch == 0x22 /* " */) {
          inDouble = false;
        } else if (inTemplate && ch == 0x60 /* ` */) {
          inTemplate = false;
        }
        i++;
        continue;
      }

      if (ch == 0x2F /* / */ && i + 1 < input.length) {
        final next = input.codeUnitAt(i + 1);
        if (next == 0x2F /* / */) {
          var end = i + 2;
          while (end < input.length &&
              input.codeUnitAt(end) != 0x0A &&
              input.codeUnitAt(end) != 0x0D) {
            end++;
          }
          i = end;
          continue;
        }
        if (next == 0x2A /* * */) {
          final end = input.indexOf('*/', i + 2);
          if (end == -1) break;
          i = end + 2;
          continue;
        }
        final regexEnd = _findJsRegexLiteralEnd(input, i, input.length);
        if (regexEnd != -1) {
          i = regexEnd;
          continue;
        }
      }

      if (ch == 0x27 /* ' */) {
        inSingle = true;
        i++;
        continue;
      }
      if (ch == 0x22 /* " */) {
        inDouble = true;
        i++;
        continue;
      }
      if (ch == 0x60 /* ` */) {
        inTemplate = true;
        i++;
        continue;
      }

      if (ch == 0x7B /* { */ &&
          i + 1 < input.length &&
          input.codeUnitAt(i + 1) == 0x7B) {
        final close = _findMustacheClose(input, i + 2);
        if (close != -1) {
          results.add((
            start: i,
            end: close + 2,
            expr: input.substring(i + 2, close),
          ));
          i = close + 2;
          continue;
        }
        i += 2;
        continue;
      }

      if (templateBraceStack.isNotEmpty) {
        if (ch == 0x7B /* { */) {
          templateBraceStack[templateBraceStack.length - 1]++;
        } else if (ch == 0x7D /* } */) {
          final remaining = templateBraceStack.last - 1;
          if (remaining == 0) {
            templateBraceStack.removeLast();
            inTemplate = true;
          } else {
            templateBraceStack[templateBraceStack.length - 1] = remaining;
          }
        }
      }

      i++;
    }
    return results;
  }

  static int _findMustacheClose(String input, int contentStart) {
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    var inTemplate = false;
    for (var i = contentStart; i < input.length - 1; i++) {
      final ch = input.codeUnitAt(i);
      if (ch == 0x5C /* \ */) {
        i++;
        continue;
      }
      if (ch == 0x27 && !inDouble && !inTemplate) {
        inSingle = !inSingle;
      } else if (ch == 0x22 && !inSingle && !inTemplate) {
        inDouble = !inDouble;
      } else if (ch == 0x60 && !inSingle && !inDouble) {
        inTemplate = !inTemplate;
      } else if (!inSingle && !inDouble && !inTemplate) {
        if (ch == 0x7B) {
          depth++;
        } else if (ch == 0x7D) {
          if (depth == 0 && input.codeUnitAt(i + 1) == 0x7D) {
            return i;
          }
          if (depth > 0) depth--;
        }
      }
    }
    return -1;
  }

  static Map<String, String> _parsePutPairs(String body) {
    final map = <String, String>{};
    final decoded = LegadoBookSource.tryParseLenientJsonMap('{$body}');
    if (decoded != null) {
      for (final e in decoded.entries) {
        map[e.key] = e.value?.toString() ?? '';
      }
      return map;
    }
    for (final pair in body.split(',')) {
      final idx = pair.indexOf(':');
      if (idx <= 0) continue;
      final k = _stripQuotes(pair.substring(0, idx));
      final v = _stripQuotes(pair.substring(idx + 1));
      if (k.isNotEmpty) map[k] = v;
    }
    return map;
  }

  static List<String>? _tryDecodeJsonStringList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return null;
  }

  static List<String>? _tryDecodeJsonRawItems(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .where((e) => e != null)
            .map((e) => e is String ? e : jsonEncode(e))
            .toList(growable: false);
      }
    } catch (_) {}
    return null;
  }

  static bool _looksLikeJsonRule(String rule) {
    final trimmed = rule.trim();
    return trimmed.startsWith(r'$.') ||
        trimmed.startsWith(r'$[') ||
        trimmed.toLowerCase().startsWith('@json:');
  }

  static String _stripQuotes(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length >= 2) {
      final first = trimmed[0];
      final last = trimmed[trimmed.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  static String _hexDecodeToUtf8(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty || cleaned.length.isOdd) return '';
    final bytes = <int>[];
    for (var i = 0; i < cleaned.length; i += 2) {
      final byte = int.tryParse(cleaned.substring(i, i + 2), radix: 16);
      if (byte == null) return '';
      bytes.add(byte);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _formatTimestamp(int ms, {required bool utc}) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: utc);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  /// Converts Chinese numerals inside chapter titles (e.g. `第十二章`) into
  /// Arabic numerals (`第12章`), matching Legado's `java.toNumChapter`.
  static String toNumChapter(String input) {
    return input.replaceAllMapped(
      RegExp(r'第([零一二两三四五六七八九十百千万〇]+)(章|节|回|卷|话|部)'),
      (m) {
        final numVal = _chineseToInt(m.group(1)!);
        if (numVal == null) return m.group(0)!;
        return '第$numVal${m.group(2)!}';
      },
    );
  }

  static int? _chineseToInt(String cn) {
    const digits = <String, int>{
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    const units = <String, int>{'十': 10, '百': 100, '千': 1000, '万': 10000};

    var total = 0;
    var section = 0;
    var number = 0;
    for (var i = 0; i < cn.length; i++) {
      final ch = cn[i];
      if (digits.containsKey(ch)) {
        number = digits[ch]!;
      } else if (units.containsKey(ch)) {
        final unit = units[ch]!;
        if (unit == 10000) {
          section = (section + number) * unit;
          total += section;
          section = 0;
          number = 0;
        } else {
          if (number == 0 && unit == 10 && section == 0 && i == 0) {
            number = 1;
          }
          section += number * unit;
          number = 0;
        }
      } else {
        return null;
      }
    }
    return total + section + number;
  }

  static final RegExp _bareJsonPathPattern = RegExp(
    r'^[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_*]+|\[\*\]|\[\d+\])*$',
  );
  static final Random _secureRandom = Random.secure();

  static bool _isMustacheTemplateRule(String rule) {
    final trimmed = rule.trim();
    if (!trimmed.contains('{{') &&
        !trimmed.contains(r'{$.') &&
        !trimmed.contains('{@@')) {
      return false;
    }
    final (:selectorPart, regexSpec: _) =
        LegadoSelectorEngine.splitTrailingRegex(trimmed);
    final matches = _findMustacheExpressions(selectorPart);
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      buf.write(selectorPart.substring(cursor, m.start));
      cursor = m.end;
    }
    buf.write(selectorPart.substring(cursor));
    final stripped = buf
        .toString()
        .replaceAll(RegExp(r'\{(?:\$\.[^}]+|@@[^}]+)\}'), '')
        .trim();
    if (stripped.isEmpty) return true;
    if (stripped.contains('@') ||
        stripped.startsWith('//') ||
        stripped.startsWith('./') ||
        stripped.startsWith(r'$.') ||
        stripped.startsWith(r'$[') ||
        stripped.startsWith('class.') ||
        stripped.startsWith('id.') ||
        stripped.startsWith('tag.') ||
        stripped.startsWith('text.') ||
        stripped.startsWith('children') ||
        stripped.startsWith('#') ||
        stripped.startsWith('.')) {
      return false;
    }
    return true;
  }

  static bool _isJsonInput(String input) {
    final trimmed = input.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return false;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map || decoded is List;
    } catch (_) {
      return false;
    }
  }

  static String _normalizeRuleForInput(String input, String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty || !_isJsonInput(input)) return rule;
    return _normalizeJsonCombinatorRule(trimmed);
  }

  static String _normalizeJsonCombinatorRule(String rule) {
    final orParts = LegadoSelectorEngine.splitTopLevel(rule, '||');
    if (orParts.length > 1) {
      return orParts.map(_normalizeJsonCombinatorRule).join('||');
    }
    final andParts = LegadoSelectorEngine.splitTopLevel(rule, '&&');
    if (andParts.length > 1) {
      return andParts.map(_normalizeJsonCombinatorRule).join('&&');
    }
    final zipParts = LegadoSelectorEngine.splitTopLevel(rule, '%%');
    if (zipParts.length > 1) {
      return zipParts.map(_normalizeJsonCombinatorRule).join('%%');
    }

    final (:selectorPart, :regexSpec) = LegadoSelectorEngine.splitTrailingRegex(
      rule,
    );
    final sel = selectorPart.trim();
    if (sel.isEmpty ||
        sel.startsWith('class.') ||
        sel.startsWith('id.') ||
        sel.startsWith('tag.') ||
        sel.startsWith('text.') ||
        sel == 'children' ||
        !_bareJsonPathPattern.hasMatch(sel)) {
      return rule;
    }
    final normalizedSel = '\$.$sel';
    return regexSpec.isEmpty ? normalizedSel : '$normalizedSel##$regexSpec';
  }

  static String _coerceJsTargetToString(Object? target) {
    if (target == null) return '';
    if (target is String) return target;
    if (target is List) {
      return target.map(_coerceJsTargetToString).join('\n');
    }
    if (target is Map) return jsonEncode(target);
    return target.toString();
  }

  static Map<String, Object?> _buildJsHttpResponseMap(
    HttpFetchResult resp, {
    required String requestedUrl,
  }) {
    var finalUrl = resp.finalUrl;
    final parsedFinal = Uri.tryParse(finalUrl);
    if (parsedFinal != null && parsedFinal.path.isEmpty) {
      finalUrl = parsedFinal.replace(path: '/').toString();
    }
    final hdrs = <String, String>{...resp.headers};
    if (!hdrs.containsKey('location')) {
      if (resp.redirectLocation != null && resp.redirectLocation!.isNotEmpty) {
        hdrs['location'] = resp.redirectLocation!;
      } else if (finalUrl.isNotEmpty &&
          Uri.tryParse(finalUrl) != Uri.tryParse(requestedUrl)) {
        hdrs['location'] = finalUrl;
      }
    }
    return <String, Object?>{
      'body': resp.body,
      'status': resp.statusCode,
      'url': finalUrl,
      'headers': hdrs,
    };
  }

  static ({String replacement, int nextIndex})? _tryRewriteJsoupConnectChain(
    String code,
    int start,
  ) {
    final openIdx = code.indexOf('(', start);
    if (openIdx == -1) return null;
    final closeIdx = _findMatchingParen(code, openIdx);
    if (closeIdx == -1) return null;

    final prefix = code.substring(start, openIdx + 1);
    final connectArg = _rewriteAsyncHttpCalls(
      code.substring(openIdx + 1, closeIdx),
    );
    final chainBuf = StringBuffer()..write('$prefix$connectArg)');
    var cursor = closeIdx + 1;

    while (cursor < code.length) {
      var ws = cursor;
      while (ws < code.length && _isWhitespaceChar(code.codeUnitAt(ws))) {
        ws++;
      }
      if (ws >= code.length || code.codeUnitAt(ws) != 0x2E) break;
      final dotPos = ws;
      var identStart = dotPos + 1;
      while (identStart < code.length &&
          _isWhitespaceChar(code.codeUnitAt(identStart))) {
        identStart++;
      }
      var identEnd = identStart;
      while (identEnd < code.length &&
          _isJsIdentPart(code.codeUnitAt(identEnd))) {
        identEnd++;
      }
      if (identEnd == identStart) break;
      final ident = code.substring(identStart, identEnd);
      var parenStart = identEnd;
      while (parenStart < code.length &&
          _isWhitespaceChar(code.codeUnitAt(parenStart))) {
        parenStart++;
      }
      if (parenStart >= code.length || code.codeUnitAt(parenStart) != 0x28) {
        break;
      }
      final parenEnd = _findMatchingParen(code, parenStart);
      if (parenEnd == -1) break;

      final callArgs = code.substring(parenStart + 1, parenEnd);
      if ((ident == 'get' || ident == 'post') && callArgs.trim().isEmpty) {
        final methodSuffix = ident == 'get' ? '__asyncGet()' : '__asyncPost()';
        return (
          replacement: '(await $chainBuf.$methodSuffix)',
          nextIndex: parenEnd + 1,
        );
      }
      chainBuf.write(code.substring(cursor, parenStart + 1));
      chainBuf.write(_rewriteAsyncHttpCalls(callArgs));
      chainBuf.write(')');
      cursor = parenEnd + 1;
    }

    return null;
  }

  static bool _isWhitespaceChar(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;

  static bool _isJsIdentPart(int code) =>
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x30 && code <= 0x39) ||
      code == 0x5F ||
      code == 0x24;

  static int _coerceTimestampMs(Object? raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.isFinite ? raw.toInt() : 0;
    final text = raw.toString().trim();
    if (text.isEmpty) return 0;
    final asNum = num.tryParse(text);
    if (asNum != null && asNum.isFinite) return asNum.toInt();
    return DateTime.tryParse(text)?.millisecondsSinceEpoch ?? 0;
  }

  static int? _tryParseInt(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.isFinite ? raw.toInt() : null;
    return num.tryParse(raw.toString().trim())?.toInt();
  }

  static String _formatTimestampWithPattern(
    int ms, {
    required String pattern,
    required bool utc,
  }) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: utc);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return pattern
        .replaceAll('yyyy', y)
        .replaceAll('MM', m)
        .replaceAll('dd', d)
        .replaceAll('HH', hh)
        .replaceAll('mm', mm)
        .replaceAll('ss', ss);
  }

  static String _generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = JsCryptoHelpers.hexEncode(bytes);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  /// Strips HTML tags and normalizes block newlines and entities into readable
  /// plain text (`java.htmlFormat`).
  static String formatHtmlText(String rawHtml) {
    if (rawHtml.trim().isEmpty) return '';
    final normalized = rawHtml
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</?(?:p|div|li|tr|h[1-6]|blockquote)\b[^>]*>', caseSensitive: false),
          '\n',
        );
    final frag = html_parser.parseFragment(normalized);
    final text = (frag.text ?? '')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = text
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    return lines.join('\n');
  }
}
