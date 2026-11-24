import 'dart:convert';

import '../../../domain/domain.dart';
import '../../../infrastructure/js/qjs_sandbox_runtime.dart';
import '../parsing/html_selector_helper.dart';

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
    this.headers = const {},
    this.charset,
    this.webView = false,
  });
}

class LegadoRuleEvaluator {
  final String sourceId;
  final Duration jsTimeout;

  const LegadoRuleEvaluator({
    required this.sourceId,
    this.jsTimeout = const Duration(seconds: 5),
  });

  /// Parses a Legado URL expression such as:
  /// `/search,{"method":"POST","body":"key={{key}}&page={{page}}","charset":"GBK","headers":{"X-Token":"1"}}`
  static LegadoRequestSpec parseUrlSpec(
    String rawSpec, {
    required String baseUrl,
    Map<String, String> defaultHeaders = const {},
    String? defaultCharset,
    String? keyword,
    int? page,
  }) {
    var interpolated = rawSpec.trim();
    if (keyword != null) {
      interpolated = interpolated.replaceAll('{{key}}', keyword);
    }
    if (page != null) {
      interpolated = interpolated.replaceAll('{{page}}', page.toString());
    }

    String urlPart = interpolated;
    Map<String, dynamic>? optionJson;

    final commaIdx = interpolated.indexOf(',{');
    if (commaIdx != -1) {
      urlPart = interpolated.substring(0, commaIdx).trim();
      final jsonPart = interpolated.substring(commaIdx + 1).trim();
      final decoded = jsonDecode(jsonPart);
      if (decoded is Map) {
        optionJson = decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    }

    final resolvedUrl = Uri.tryParse(urlPart)?.hasScheme == true
        ? urlPart
        : Uri.parse(baseUrl).resolve(urlPart).toString();

    final mergedHeaders = <String, String>{...defaultHeaders};
    if (optionJson != null && optionJson['headers'] is Map) {
      final optHeaders = optionJson['headers'] as Map;
      for (final entry in optHeaders.entries) {
        mergedHeaders[entry.key.toString()] = entry.value.toString();
      }
    }

    final method =
        (optionJson?['method']?.toString().trim().toUpperCase() ?? 'GET');
    final body = optionJson?['body']?.toString();
    final charset = optionJson?['charset']?.toString().trim() ?? defaultCharset;
    final webView = optionJson?['webView'] == true;

    return LegadoRequestSpec(
      url: resolvedUrl,
      method: method.isEmpty ? 'GET' : method,
      body: body,
      headers: mergedHeaders,
      charset: charset,
      webView: webView,
    );
  }

  /// Evaluates a Legado field rule supporting:
  /// - CSS selectors (`div.item a@text`, `a@href`, `#content@html`, `@textNodes`)
  /// - XPath (`@XPath:...` or `//...`)
  /// - JSONPath (`@Json:...` or `$. ...`)
  /// - Regex replacement (`##pattern##replacement` and `##pattern##replacement###`)
  /// - Inline `<js>...</js>` and `@js:...` snippets executed in QuickJS
  Future<List<String>> evaluateList(
    String input,
    String rule, {
    required String baseUrl,
    CancellationToken? cancelToken,
  }) async {
    final trimmedRule = rule.trim();
    if (trimmedRule.isEmpty) return const [];

    _guardUnsupportedFeatures(trimmedRule);

    final parsedRule = _splitJsSegments(trimmedRule);
    var values = <String>[];

    if (parsedRule.selectorPart.isNotEmpty) {
      values = _evaluateSelectorAndRegex(input, parsedRule.selectorPart);
    } else if (parsedRule.jsSegments.isNotEmpty) {
      values = [input];
    }

    for (final jsCode in parsedRule.jsSegments) {
      final nextValues = <String>[];
      final sourceInputs = values.isEmpty ? <String>[''] : values;
      for (final val in sourceInputs) {
        final jsOut = await _runJsSnippet(
          jsCode,
          result: val,
          baseUrl: baseUrl,
          cancelToken: cancelToken,
        );
        if (jsOut.isNotEmpty) {
          nextValues.add(jsOut);
        }
      }
      values = nextValues;
    }

    return values;
  }

  Future<String> evaluateString(
    String input,
    String rule, {
    required String baseUrl,
    CancellationToken? cancelToken,
  }) async {
    final list = await evaluateList(
      input,
      rule,
      baseUrl: baseUrl,
      cancelToken: cancelToken,
    );
    return list.isEmpty ? '' : list.first;
  }

  List<String> evaluateElementsHtml(String htmlText, String listRule) {
    final trimmed = listRule.trim();
    if (trimmed.isEmpty) return const [];
    _guardUnsupportedFeatures(trimmed);

    // Strip any trailing regex/js if present; normally bookList / chapterList
    // is a pure CSS selector like `div.book-item` or `ul.chapters li`.
    final selectorOnly = trimmed.split('<js>').first.split('##').first.trim();
    return HtmlSelectorHelper.selectElementsHtml(htmlText, selectorOnly);
  }

  List<String> _evaluateSelectorAndRegex(String input, String selectorAndRegex) {
    // Split `##pattern##replacement` (and optional trailing `###`).
    final hashIndex = selectorAndRegex.indexOf('##');
    final selectorPart = (hashIndex == -1
            ? selectorAndRegex
            : selectorAndRegex.substring(0, hashIndex))
        .trim();
    final regexSpec =
        hashIndex == -1 ? '' : selectorAndRegex.substring(hashIndex + 2);

    List<String> extracted;
    if (selectorPart.isEmpty) {
      extracted = [input];
    } else if (selectorPart.startsWith('@XPath:') ||
        selectorPart.startsWith('//')) {
      final expr = selectorPart.startsWith('@XPath:')
          ? selectorPart.substring(7).trim()
          : selectorPart;
      extracted = HtmlSelectorHelper.selectXPath(input, expr);
    } else if (selectorPart.startsWith('@Json:') ||
        selectorPart.startsWith(r'$.')) {
      final expr = selectorPart.startsWith('@Json:')
          ? selectorPart.substring(6).trim()
          : selectorPart;
      extracted = HtmlSelectorHelper.selectJsonPath(input, expr);
    } else {
      final cssExpr = selectorPart.startsWith('@css:')
          ? selectorPart.substring(5).trim()
          : selectorPart;
      extracted = HtmlSelectorHelper.selectCss(input, cssExpr);
    }

    if (regexSpec.isEmpty) {
      return extracted;
    }
    return extracted
        .map((item) => _applyLegadoRegex(item, regexSpec))
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static String _applyLegadoRegex(String text, String regexSpec) {
    var firstOnly = false;
    var spec = regexSpec;
    if (spec.endsWith('###')) {
      firstOnly = true;
      spec = spec.substring(0, spec.length - 3);
    }

    final parts = spec.split('##');
    final pattern = parts.isNotEmpty ? parts[0] : '';
    final replacement = parts.length > 1 ? parts[1] : '';
    if (pattern.isEmpty) return text;

    final regex = RegExp(pattern, multiLine: true, dotAll: true);
    final updated = firstOnly
        ? text.replaceFirst(regex, replacement)
        : text.replaceAll(regex, replacement);
    return updated.trim();
  }

  Future<String> _runJsSnippet(
    String jsCode, {
    required String result,
    required String baseUrl,
    CancellationToken? cancelToken,
  }) async {
    final memory = <String, String>{};
    final runtime = QjsSandboxRuntime(
      sourceId: sourceId,
      syncHostFunctions: {
        'base64Decode': (args) =>
            utf8.decode(base64Decode(args.first?.toString() ?? '')),
        'encodeURI': (args) =>
            Uri.encodeFull(args.first?.toString() ?? ''),
      },
    );

    final wrapped = '''
const java = {
  base64Decode: (s) => host.base64Decode(String(s)),
  encodeURI: (s) => host.encodeURI(String(s)),
  put: (k, v) => { __javaMem[String(k)] = String(v); return v; },
  get: (k) => __javaMem[String(k)] ?? "",
  log: (msg) => host.log(String(msg)),
};
$jsCode
''';

    try {
      final res = await runtime.evaluate(
        wrapped,
        bindings: {
          'result': result,
          'baseUrl': baseUrl,
          '__javaMem': memory,
        },
        timeout: jsTimeout,
        cancelToken: cancelToken,
      );
      return res.value.trim();
    } finally {
      await runtime.dispose();
    }
  }

  static ({String selectorPart, List<String> jsSegments}) _splitJsSegments(
    String rule,
  ) {
    final jsAtIdx = rule.indexOf('@js:');
    if (jsAtIdx != -1) {
      return (
        selectorPart: rule.substring(0, jsAtIdx).trim(),
        jsSegments: [rule.substring(jsAtIdx + 4).trim()],
      );
    }

    final jsMatches = RegExp(
      r'<js>([\s\S]*?)</js>',
      caseSensitive: false,
    ).allMatches(rule).toList();
    if (jsMatches.isEmpty) {
      return (selectorPart: rule, jsSegments: const []);
    }

    final prefix = rule.substring(0, jsMatches.first.start).trim();
    final segments = jsMatches
        .map((m) => (m.group(1) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return (selectorPart: prefix, jsSegments: segments);
  }

  void _guardUnsupportedFeatures(String rule) {
    if (rule.contains('Packages.') || rule.contains('java.webView')) {
      throw UnsupportedLegadoRuleFailure(
        message: 'Legado rule uses unsupported Rhino/WebView Java API: $rule',
        feature: 'rhino_java_api',
        sourceId: sourceId,
      );
    }
  }
}
