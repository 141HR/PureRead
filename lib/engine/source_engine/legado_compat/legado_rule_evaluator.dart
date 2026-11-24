import 'dart:convert';

import '../../../domain/domain.dart';
import '../../../infrastructure/js/qjs_sandbox_runtime.dart';
import '../../../infrastructure/network/source_http_client.dart';
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

/// Mutable per-operation / per-provider state shared across Legado rule and JS
/// evaluations (`java.put`/`java.get`, `source.getVariable`/`setVariable`,
/// cookie mutations, and debug logs).
class LegadoEvalSession {
  final Map<String, String> javaVars = <String, String>{};
  final Map<String, String> cookieSnapshotByHost = <String, String>{};
  final List<({String type, String url, String value})> _pendingCookieOps =
      <({String type, String url, String value})>[];
  final List<String> logs = <String>[];

  String sourceVariable;
  String bookName;
  String bookUrl;
  String tocUrl;
  String chapterTitle;
  String chapterUrl;
  int chapterIndex;

  LegadoEvalSession({
    this.sourceVariable = '',
    this.bookName = '',
    this.bookUrl = '',
    this.tocUrl = '',
    this.chapterTitle = '',
    this.chapterUrl = '',
    this.chapterIndex = 0,
  });

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
            final jsInput = _interpolateKeyPageLiterals(
              code,
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
            final bareGet = _tryResolveBareGetRule(rule, activeSession);
            if (bareGet != null) {
              if (bareGet.isNotEmpty) nextValues.add(bareGet);
              continue;
            }
            final resolvedRule = await _resolveMustacheInRule(
              rule,
              input: currentInput,
              baseUrl: baseUrl,
              keyword: keyword,
              page: page,
              session: activeSession,
              cancelToken: cancelToken,
            );
            nextValues.addAll(
              LegadoSelectorEngine.selectValues(currentInput, resolvedRule),
            );
          }
          values = nextValues;

        case _JsStage(:final code):
          final nextValues = <String>[];
          final inputs = values.isEmpty ? const <String>[''] : values;
          for (final currentInput in inputs) {
            final jsOut = await _runJsSnippet(
              code,
              result: currentInput,
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
      final resolved = await _resolveMustacheInRule(
        cleaned,
        input: input,
        baseUrl: baseUrl,
        keyword: keyword,
        page: page,
        session: activeSession,
        cancelToken: cancelToken,
      );
      if (httpClient != null) {
        await activeSession.flushCookies(httpClient!);
      }
      return LegadoSelectorEngine.selectOne(
        input,
        resolved,
        joinSeparator: joinSeparator,
      );
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
            next.addAll(LegadoSelectorEngine.selectElements(current, resolved));
          }
          blocks = next;

        case _JsStage(:final code):
          final next = <String>[];
          final inputs = blocks.isEmpty ? const <String>[''] : blocks;
          for (final current in inputs) {
            final jsOut = await _runJsSnippet(
              code,
              result: current,
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

  Future<String> _resolveMustacheInRule(
    String rule, {
    required String input,
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    CancellationToken? cancelToken,
  }) async {
    var out = rule;
    if (page != null && out.contains('<') && out.contains(',')) {
      out = LegadoSelectorEngine.interpolateTemplate(out, page: page);
    }
    if (out.contains('{{') && out.contains('}}')) {
      final matches = _findMustacheExpressions(out);
      if (matches.isNotEmpty) {
        final buf = StringBuffer();
        var cursor = 0;
        for (final m in matches) {
          buf.write(out.substring(cursor, m.start));
          final expr = m.expr.trim();
          final replacement = await _evaluateMustacheExpression(
            expr,
            input: input,
            baseUrl: baseUrl,
            keyword: keyword,
            page: page,
            session: session,
            cancelToken: cancelToken,
          );
          buf.write(replacement);
          cursor = m.end;
        }
        buf.write(out.substring(cursor));
        out = buf.toString();
      }
    }
    if (out.contains(r'{$.') || out.contains('{@@')) {
      out = LegadoSelectorEngine.interpolateTemplate(
        out,
        contextInput: input,
      );
    }
    return out;
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
    CancellationToken? cancelToken,
  }) async {
    if (expr == 'key') return keyword ?? '';
    if (expr == 'page') return (page ?? 1).toString();
    if (expr == 'baseUrl') return baseUrl;
    if (expr == 'result') return input;
    if (expr == 'chapter.title') return session.chapterTitle;
    if (expr == 'book.name') return session.bookName;

    if (expr.startsWith(r'$.') ||
        expr.startsWith(r'$[') ||
        expr.toLowerCase().startsWith('@json:')) {
      final clean = expr.toLowerCase().startsWith('@json:')
          ? expr.substring(6).trim()
          : expr;
      return LegadoSelectorEngine.selectOne(input, clean);
    }
    if (expr.startsWith('@@')) {
      return LegadoSelectorEngine.selectOne(input, expr.substring(2).trim());
    }
    if (expr.toLowerCase().startsWith('@xpath:')) {
      return LegadoSelectorEngine.selectOne(input, expr);
    }

    final jsExpr = expr.toLowerCase().startsWith('@js:')
        ? expr.substring(4).trim()
        : expr;
    return _runJsSnippet(
      jsExpr,
      result: input,
      baseUrl: baseUrl,
      keyword: keyword,
      page: page,
      session: session,
      cancelToken: cancelToken,
    );
  }

  Future<String> _runJsSnippet(
    String jsCode, {
    required String result,
    required String baseUrl,
    String? keyword,
    int? page,
    required LegadoEvalSession session,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    _guardUnsupportedFeatures(jsCode);

    final src = source;
    final rawSourceKey = src?.bookSourceUrl ?? baseUrl;
    final activeBaseUrl =
        SourceHttpClient.tryNormalizeHttpUri(baseUrl)?.toString() ?? baseUrl;
    var currentContent = result;

    final syncHost = <String, HostSyncCallback>{
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
        return null;
      },
      'javaGetString': (args) {
        final rule = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        return LegadoSelectorEngine.selectOne(currentContent, rule);
      },
      'javaGetStringList': (args) {
        final rule = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        return LegadoSelectorEngine.selectValues(currentContent, rule);
      },
      'javaGetElements': (args) {
        final rule = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        return LegadoSelectorEngine.selectElements(currentContent, rule);
      },
      'javaGetElement': (args) {
        final rule = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final list = LegadoSelectorEngine.selectElements(currentContent, rule);
        return list.isEmpty ? '' : list.first;
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
        final rawTs = args.isNotEmpty ? args[0] : null;
        final ms = rawTs is num
            ? rawTs.toInt()
            : int.tryParse(rawTs?.toString() ?? '') ?? 0;
        return _formatTimestamp(ms, utc: false);
      },
      'javaTimeFormatUTC': (args) {
        final rawTs = args.isNotEmpty ? args[0] : null;
        final ms = rawTs is num
            ? rawTs.toInt()
            : int.tryParse(rawTs?.toString() ?? '') ?? 0;
        final offset = args.length > 1 && args[1] is num
            ? (args[1] as num).toInt()
            : 0;
        return _formatTimestamp(ms + offset * 3600 * 1000, utc: true);
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
    };

    final asyncHost = <String, HostAsyncCallback>{
      'legadoAjax': (args) async {
        final client = httpClient;
        if (client == null) return '';
        final rawUrl = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final req = parseUrlSpec(
          rawUrl,
          baseUrl: activeBaseUrl,
          defaultHeaders: src?.headers ?? const <String, String>{},
          defaultCharset: src?.charset,
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
          rateLimitMs: src?.rateLimitMs ?? 0,
          cancelToken: cancelToken,
        );
        return resp.body;
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
        final hdrs = <String, String>{...?src?.headers};
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
          charsetOverride: src?.charset,
          rateLimitMs: src?.rateLimitMs ?? 0,
          cancelToken: cancelToken,
        );
        return <String, Object?>{
          'body': resp.body,
          'status': resp.statusCode,
          'url': resp.finalUrl,
          'headers': resp.headers,
        };
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
        final hdrs = <String, String>{...?src?.headers};
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
          charsetOverride: src?.charset,
          rateLimitMs: src?.rateLimitMs ?? 0,
          cancelToken: cancelToken,
        );
        return <String, Object?>{
          'body': resp.body,
          'status': resp.statusCode,
          'url': resp.finalUrl,
          'headers': resp.headers,
        };
      },
    };

    final runtime = QjsSandboxRuntime(
      sourceId: sourceId,
      memoryLimitBytes: memoryLimitBytes,
      syncHostFunctions: syncHost,
      asyncHostFunctions: asyncHost,
    );

    final prepared = _prepareLegadoJsBody(jsCode);
    final jsLibPrefix = src?.jsLib != null && src!.jsLib!.trim().isNotEmpty
        ? '${src.jsLib!}\n'
        : '';

    final wrapped = '''
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
const java = {
  put: (k, v) => host.javaPut(String(k), v == null ? "" : String(v)),
  get: (k) => host.javaGetVar(String(k)),
  __asyncAjax: async (u) => await host.legadoAjax(String(u)),
  __asyncHttpGet: async (u, h) => __wrapResp(await host.legadoHttpGet(String(u), h || null)),
  __asyncHttpPost: async (u, b, h) => __wrapResp(await host.legadoHttpPost(String(u), b == null ? "" : String(b), h || null)),
  __asyncConnect: async (u) => __wrapResp(await host.legadoHttpGet(String(u), null)),
  ajax: (u) => "",
  connect: (u) => __wrapResp({}),
  post: (u, b, h) => __wrapResp({}),
  setContent: (c) => { host.javaSetContent(c == null ? "" : String(c)); },
  getString: (r) => host.javaGetString(String(r)),
  getStringList: (r) => host.javaGetStringList(String(r)),
  getElements: (r) => host.javaGetElements(String(r)),
  getElement: (r) => host.javaGetElement(String(r)),
  md5Encode: (s) => host.md5(s == null ? "" : String(s)),
  md5Encode16: (s) => host.md5Encode16(s == null ? "" : String(s)),
  base64Encode: (s) => host.base64Encode(s == null ? "" : String(s)),
  base64Decode: (s) => host.base64Decode(s == null ? "" : String(s)),
  hexDecodeToString: (s) => host.javaHexDecodeToString(s == null ? "" : String(s)),
  encodeURI: (s, enc) => host.javaEncodeURI(s == null ? "" : String(s), enc == null ? null : String(enc)),
  decodeURI: (s) => host.javaDecodeURI(s == null ? "" : String(s)),
  timeFormat: (ts) => host.javaTimeFormat(ts || 0),
  timeFormatUTC: (ts, off) => host.javaTimeFormatUTC(ts || 0, off || 0),
  toNumChapter: (s) => host.javaToNumChapter(s == null ? "" : String(s)),
  t2s: (s) => s == null ? "" : String(s),
  s2t: (s) => s == null ? "" : String(s),
  getWebViewUA: () => ${jsonEncode(SourceHttpClient.defaultUserAgent)},
  log: (msg) => { host.log(msg == null ? "" : String(msg)); },
  toast: (msg) => { host.javaToast(msg == null ? "" : String(msg)); },
  longToast: (msg) => { host.javaToast(msg == null ? "" : String(msg)); },
  getCookie: (u, k) => k ? host.cookieGetKey(String(u), String(k)) : host.cookieGetCookie(String(u))
};
const cookie = {
  getCookie: (u) => host.cookieGetCookie(String(u)),
  getKey: (u, k) => host.cookieGetKey(String(u), String(k)),
  setCookie: (u, v) => { host.cookieSetCookie(String(u), String(v)); },
  removeCookie: (u) => { host.cookieRemoveCookie(String(u)); }
};
const source = {
  key: ${jsonEncode(rawSourceKey)},
  bookSourceUrl: ${jsonEncode(rawSourceKey)},
  bookSourceName: ${jsonEncode(src?.bookSourceName ?? '')},
  bookSourceComment: ${jsonEncode(src?.bookSourceComment ?? '')},
  header: ${jsonEncode(src?.rawHeader ?? '')},
  loginUrl: ${jsonEncode(src?.loginUrl ?? '')},
  getKey: () => ${jsonEncode(rawSourceKey)},
  getVariable: () => host.sourceGetVariable(),
  setVariable: (v) => { host.sourceSetVariable(v == null ? "" : String(v)); }
};
$jsLibPrefix$prepared
''';

    try {
      final res = await runtime.evaluate(
        wrapped,
        bindings: <String, Object?>{
          'result': result,
          'baseUrl': activeBaseUrl,
          'key': keyword ?? '',
          'page': page ?? 1,
          'book': <String, Object?>{
            'name': session.bookName,
            'bookUrl': session.bookUrl,
            'tocUrl': session.tocUrl,
            'variable': '',
          },
          'chapter': <String, Object?>{
            'title': session.chapterTitle,
            'url': session.chapterUrl,
            'index': session.chapterIndex,
          },
        },
        timeout: jsTimeout,
        cancelToken: cancelToken,
      );
      session.logs.addAll(res.logs);
      return res.value.trim();
    } finally {
      await runtime.dispose();
    }
  }

  /// Rewrites synchronous-looking `java.ajax(...)`, `java.post(...)`,
  /// `java.connect(...)`, and 2-arg `java.get(url, headers)` into `await`
  /// calls inside an async IIFE when present, leaving pure sync scripts untouched
  /// so QuickJS natively returns the final expression completion value.
  static String _prepareLegadoJsBody(String jsCode) {
    final hasAsyncCall =
        jsCode.contains('java.ajax(') ||
        jsCode.contains('java.connect(') ||
        jsCode.contains('java.post(') ||
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

        String? target;
        String? replacementPrefix;
        if (code.startsWith('java.ajax(', i)) {
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

    final lines = tail.split('\n');
    for (var idx = lines.length - 1; idx >= 0; idx--) {
      final line = lines[idx].trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      if (line.startsWith('return ') ||
          line.startsWith('throw ') ||
          line.startsWith('var ') ||
          line.startsWith('let ') ||
          line.startsWith('const ') ||
          line.startsWith('if') ||
          line.startsWith('for') ||
          line.startsWith('while') ||
          line.startsWith('do') ||
          line.startsWith('switch') ||
          line.startsWith('try') ||
          line.startsWith('function ') ||
          line.startsWith('{') ||
          line.endsWith('}')) {
        return trimmed;
      }
      final cleanExpr = line.endsWith(';')
          ? line.substring(0, line.length - 1).trim()
          : line;
      if (cleanExpr.isNotEmpty) {
        final leadingSpace = lines[idx].substring(
          0,
          lines[idx].length - lines[idx].trimLeft().length,
        );
        lines[idx] = '${leadingSpace}return ($cleanExpr);';
      }
      return '$prefix${lines.join('\n')}';
    }
    return trimmed;
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
    for (var i = 0; i < argsText.length; i++) {
      final ch = argsText[i];
      if (!inSingle && !inDouble) {
        if (ch == "'") {
          inSingle = true;
        } else if (ch == '"') {
          inDouble = true;
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
      }
    }
    return false;
  }

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
    if (rule.contains('Packages.') ||
        RegExp(r'\bjava\.lang\.').hasMatch(rule) ||
        rule.contains('importClass(') ||
        rule.contains('org.jsoup.')) {
      throw UnsupportedLegadoRuleFailure(
        message: 'Legado rule uses unsupported Rhino Java API: $rule',
        feature: 'rhino_java_api',
        sourceId: sourceId,
      );
    }
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
    var out = code;
    if (keyword != null) {
      out = out.replaceAll('{{key}}', isJsCode ? keyword : keyword);
    }
    if (page != null) {
      out = out.replaceAll('{{page}}', page.toString());
    }
    return out;
  }

  static List<({int start, int end, String expr})> _findMustacheExpressions(
    String input,
  ) {
    final results = <({int start, int end, String expr})>[];
    var cursor = 0;
    while (cursor < input.length) {
      final open = input.indexOf('{{', cursor);
      if (open == -1) break;
      var depth = 0;
      var inSingle = false;
      var inDouble = false;
      var close = -1;
      for (var i = open + 2; i < input.length - 1; i++) {
        final ch = input.codeUnitAt(i);
        if (ch == 0x5C) {
          i++;
          continue;
        }
        if (ch == 0x27 && !inDouble) {
          inSingle = !inSingle;
        } else if (ch == 0x22 && !inSingle) {
          inDouble = !inDouble;
        } else if (!inSingle && !inDouble) {
          if (ch == 0x7B) {
            depth++;
          } else if (ch == 0x7D) {
            if (depth == 0 && input.codeUnitAt(i + 1) == 0x7D) {
              close = i;
              break;
            }
            if (depth > 0) depth--;
          }
        }
      }
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
}
