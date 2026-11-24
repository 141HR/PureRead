import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:json_path/json_path.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// Selector and rule extraction engine for JS plugins and Legado book sources.
///
/// Supports:
/// - Standard CSS selectors and `@css:` explicit CSS mode
/// - Legado default chained rules (`class.X.N@tag.Y@text`, `id.X`, `tag.X.N`,
///   `text.X`, `children`, `!index` / `!a:b`, `@text`, `@textNodes`, `@ownText`,
///   `@html`, `@all`, `@outerHtml`, `@innerHtml`, `@href`, `@src`, `@attr`)
/// - XPath (`@XPath:` / `//` / `./`)
/// - JSONPath (`$.` / `$[` / `@Json:`)
/// - All-in-one regex list rules (`:pattern` / `@regex:pattern`) with inline
///   flag translation (`(?s)`, `(?i)`, `(?m)`, `(?is)`, `(?ms)`) and `$0`..`$N`
///   capture propagation
/// - Combinators (`||`, `&&`, `%%`)
/// - Regex replacements (`##pattern##replacement` and `###` first-only)
/// - `{{...}}`, `{$. ...}`, and `<a,b>` page conditional interpolation
class LegadoSelectorEngine {
  const LegadoSelectorEngine._();

  static const String _regexMatchEnvelopePrefix = '\u0000__LEGADO_REGEX_MATCH__:';
  static final RegExp _inlineFlagTokenRegex = RegExp(
    r'\(\?((?:[imsuxdIMSUD]+(?:-[imsuxdIMSUD]+)?)|(?:-[imsuxdIMSUD]+))([):])',
  );
  static final RegExp _captureGroupRefRegex = RegExp(r'\$\{\d+\}|\$\d+');

  /// Returns `true` when [input] carries an encoded all-in-one regex match
  /// item produced by [selectElements].
  static bool isRegexMatchEnvelope(String input) =>
      input.startsWith(_regexMatchEnvelopePrefix);

  /// Encodes a regex match's capture groups (`$0`, `$1`, ...) into an opaque
  /// item block string for downstream field evaluation.
  static String encodeRegexMatch(List<String> groups) =>
      '$_regexMatchEnvelopePrefix${jsonEncode(groups)}';

  /// Decodes an item block produced by an all-in-one `:regex` / `@regex:` list
  /// rule into its capture groups (`$0`, `$1`, ...), or `null` for normal HTML/JSON.
  static List<String>? decodeRegexMatch(String input) {
    if (!input.startsWith(_regexMatchEnvelopePrefix)) return null;
    try {
      final decoded = jsonDecode(
        input.substring(_regexMatchEnvelopePrefix.length),
      );
      if (decoded is List) {
        return decoded.map((e) => e?.toString() ?? '').toList(growable: false);
      }
    } catch (_) {}
    return null;
  }

  /// Returns `true` when [rule] uses all-in-one `:regex` (excluding `::`) or
  /// `@regex:` syntax.
  static bool isRegexListRule(String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.toLowerCase().startsWith('@regex:')) return true;
    return trimmed.startsWith(':') && !trimmed.startsWith('::');
  }

  /// Returns `true` when [template] references capture group placeholders such
  /// as `$0`, `$1`, `$2`, or `${1}`.
  static bool containsCaptureGroupRef(String template) =>
      _captureGroupRefRegex.hasMatch(template);

  /// Expands `$0`, `$1`, ..., `${N}` capture placeholders in [template] from
  /// [groups].
  static String expandCaptureGroups(String template, List<String> groups) {
    if (!template.contains(r'$')) return template;
    return template.replaceAllMapped(RegExp(r'\$\{(\d+)\}|\$(\d+)'), (m) {
      final idxStr = m.group(1) ?? m.group(2)!;
      final groupIdx = int.tryParse(idxStr);
      if (groupIdx != null && groupIdx >= 0 && groupIdx < groups.length) {
        return groups[groupIdx];
      }
      return m.group(0)!;
    });
  }

  /// Compiles a Java/PCRE-flavored Legado regex pattern into a Dart [RegExp],
  /// translating inline flag directives (`(?s)`, `(?i)`, `(?m)`, `(?is)`,
  /// `(?ms)`, etc.) into `dotAll`, `caseSensitive`, and `multiLine`.
  ///
  /// Returns `null` when [rawPattern] is empty or syntactically invalid.
  static RegExp? compileLegadoRegex(
    String rawPattern, {
    bool defaultDotAll = false,
    bool defaultMultiLine = false,
    bool defaultCaseSensitive = true,
  }) {
    if (rawPattern.isEmpty) return null;
    var dotAll = defaultDotAll;
    var multiLine = defaultMultiLine;
    var caseSensitive = defaultCaseSensitive;

    final out = StringBuffer();
    var inCharClass = false;
    var i = 0;

    while (i < rawPattern.length) {
      final ch = rawPattern[i];
      if (ch == r'\' && i + 1 < rawPattern.length) {
        out.write(ch);
        out.write(rawPattern[i + 1]);
        i += 2;
        continue;
      }
      if (ch == '[' && !inCharClass) {
        inCharClass = true;
        out.write(ch);
        i++;
        continue;
      }
      if (ch == ']' && inCharClass) {
        inCharClass = false;
        out.write(ch);
        i++;
        continue;
      }

      if (!inCharClass &&
          ch == '(' &&
          i + 2 < rawPattern.length &&
          rawPattern[i + 1] == '?') {
        final match = _inlineFlagTokenRegex.matchAsPrefix(rawPattern, i);
        if (match != null) {
          final flagSpec = match.group(1)!;
          final terminator = match.group(2)!;
          var neg = false;
          for (var j = 0; j < flagSpec.length; j++) {
            final f = flagSpec[j].toLowerCase();
            if (f == '-') {
              neg = true;
              continue;
            }
            switch (f) {
              case 's':
                dotAll = !neg;
              case 'm':
                multiLine = !neg;
              case 'i':
                caseSensitive = neg;
              default:
                break;
            }
          }
          if (terminator == ':') {
            out.write('(?:');
          }
          i = match.end;
          continue;
        }
      }

      out.write(ch);
      i++;
    }

    final cleaned = out.toString();
    if (cleaned.isEmpty) return null;
    try {
      return RegExp(
        cleaned,
        dotAll: dotAll,
        multiLine: multiLine,
        caseSensitive: caseSensitive,
      );
    } on FormatException {
      return null;
    }
  }

  static const Set<String> _knownExtractors = <String>{
    'text',
    'textnodes',
    'owntext',
    'html',
    'all',
    'outerhtml',
    'innerhtml',
    'href',
    'src',
  };

  static const Set<String> _commonAttributes = <String>{
    'href',
    'src',
    'data-src',
    'data-original',
    'data-url',
    'content',
    'value',
    'alt',
    'action',
    'onclick',
    'placeholder',
    'url',
    'target',
    'rel',
    'type',
  };

  static const Set<String> _htmlTagNames = <String>{
    'a',
    'p',
    'div',
    'span',
    'li',
    'ul',
    'ol',
    'dl',
    'dt',
    'dd',
    'tr',
    'td',
    'th',
    'tbody',
    'thead',
    'tfoot',
    'table',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'em',
    'strong',
    'i',
    'b',
    'u',
    's',
    'small',
    'big',
    'img',
    'br',
    'hr',
    'body',
    'head',
    'section',
    'article',
    'header',
    'footer',
    'nav',
    'main',
    'aside',
    'pre',
    'code',
    'blockquote',
    'form',
    'label',
    'input',
    'select',
    'option',
    'button',
    'font',
    'center',
    'cite',
  };

  /// Evaluates [rule] against HTML or JSON [input], returning all extracted
  /// non-empty strings.
  static List<String> selectValues(String input, String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const <String>[];
    return _evalCombinators<String>(
      trimmed,
      leafEval: (branch) => _evaluateSingleValueRule(input, branch),
    );
  }

  /// Evaluates [rule] and returns a single string.
  ///
  /// When the top-level rule uses `&&`, results from all branches are joined by
  /// [joinSeparator]. Otherwise returns the first matched value (or `''`).
  static String selectOne(
    String input,
    String rule, {
    String joinSeparator = '\n',
  }) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return '';
    final orParts = splitTopLevel(trimmed, '||');
    if (orParts.length > 1) {
      for (final branch in orParts) {
        final val = selectOne(input, branch, joinSeparator: joinSeparator);
        if (val.isNotEmpty) return val;
      }
      return '';
    }

    final andParts = splitTopLevel(trimmed, '&&');
    if (andParts.length > 1) {
      final combined = <String>[];
      for (final branch in andParts) {
        final vals = selectValues(input, branch);
        combined.addAll(vals.where((v) => v.isNotEmpty));
      }
      return combined.join(joinSeparator);
    }

    final values = selectValues(input, trimmed);
    return values.isEmpty ? '' : values.first;
  }

  /// Evaluates a list selector rule (e.g. `bookList` or `chapterList`) and
  /// returns HTML `outerHtml` snippets, JSON-encoded element strings, or
  /// capture-group envelopes for `:regex` / `@regex:` rules.
  static List<String> selectElements(String input, String listRule) {
    final trimmed = listRule.trim();
    if (trimmed.isEmpty) return const <String>[];
    final regexGroups = decodeRegexMatch(input);
    final effectiveInput = regexGroups == null
        ? input
        : (regexGroups.isEmpty ? '' : regexGroups[0]);

    if (isRegexListRule(trimmed)) {
      return _selectRegexElements(effectiveInput, trimmed);
    }

    return _evalCombinators<String>(
      trimmed,
      leafEval: (branch) => _evaluateSingleElementRule(effectiveInput, branch),
    );
  }

  /// Convenience CSS-only helper equivalent to `selectValues`.
  static List<String> selectCss(String htmlText, String rule) =>
      selectValues(htmlText, rule);

  /// Convenience CSS-only helper returning first match or `''`.
  static String selectCssOne(String htmlText, String rule) =>
      selectOne(htmlText, rule);

  /// Selects elements matching standard [cssSelector] and returns `outerHtml`.
  static List<String> selectElementsHtml(String htmlText, String cssSelector) {
    final doc = html_parser.parse(htmlText);
    final root = doc.documentElement;
    if (root == null) return const <String>[];
    return _querySelectorSafe(root, cssSelector)
        .map((e) => e.outerHtml)
        .toList(growable: false);
  }

  /// Evaluates an XPath expression against HTML [htmlText].
  static List<String> selectXPath(String htmlText, String expr) {
    final cleanExpr = expr.trim();
    if (cleanExpr.isEmpty) return const <String>[];
    try {
      final xpath = _createHtmlXPath(htmlText);
      if (xpath == null) return const <String>[];
      final result = xpath.query(cleanExpr);
      final attrs = result.attrs
          .whereType<String>()
          .map(_cleanText)
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (attrs.isNotEmpty) return attrs;
      return result.nodes
          .map((n) => _cleanText(n.text ?? ''))
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  /// Evaluates an XPath expression returning matched element HTML strings.
  static List<String> selectXPathElements(String htmlText, String expr) {
    final cleanExpr = expr.trim();
    if (cleanExpr.isEmpty) return const <String>[];
    try {
      final xpath = _createHtmlXPath(htmlText);
      if (xpath == null) return const <String>[];
      final result = xpath.query(cleanExpr);
      final out = <String>[];
      for (final xNode in result.nodes) {
        final domNode = xNode.node;
        if (domNode is Element) {
          out.add(domNode.outerHtml);
        }
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  /// Evaluates a JSONPath expression against JSON [jsonText].
  static List<String> selectJsonPath(String jsonText, String expr) {
    final cleanExpr = expr.trim();
    if (cleanExpr.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(jsonText);
      final path = JsonPath(cleanExpr);
      final out = <String>[];
      for (final value in path.readValues(decoded)) {
        if (value == null) continue;
        if (value is String) {
          if (value.isNotEmpty) out.add(value);
        } else if (value is num || value is bool) {
          out.add(value.toString());
        } else {
          out.add(jsonEncode(value));
        }
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  /// Evaluates a JSONPath expression for list iteration, unpacking an array
  /// match so both `$.items[*]` and `$.items` yield individual JSON item
  /// strings.
  static List<String> selectJsonElements(String jsonText, String expr) {
    final cleanExpr = expr.trim();
    if (cleanExpr.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(jsonText);
      final path = JsonPath(cleanExpr);
      final rawMatches = path.readValues(decoded).toList(growable: false);
      final out = <String>[];
      if (rawMatches.length == 1 && rawMatches.first is List<Object?>) {
        final list = rawMatches.first as List<Object?>;
        for (final item in list) {
          if (item != null) {
            out.add(item is String ? item : jsonEncode(item));
          }
        }
        return out;
      }
      for (final item in rawMatches) {
        if (item != null) {
          out.add(item is String ? item : jsonEncode(item));
        }
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  /// Applies Legado `##pattern##replacement` (and trailing `###` first-only)
  /// to [text]. Supports `$0`..`$9` and `${n}` capture group substitutions.
  static String applyRegexSpec(String text, String regexSpec) {
    if (regexSpec.isEmpty) return text;
    var firstOnly = false;
    var spec = regexSpec;
    if (spec.endsWith('###')) {
      firstOnly = true;
      spec = spec.substring(0, spec.length - 3);
    }

    final sepIdx = spec.indexOf('##');
    final String pattern;
    final String replacement;
    if (sepIdx == -1) {
      pattern = spec;
      replacement = '';
    } else {
      pattern = spec.substring(0, sepIdx);
      final rest = spec.substring(sepIdx + 2);
      final secondSep = rest.indexOf('##');
      replacement = secondSep == -1 ? rest : rest.substring(0, secondSep);
    }
    if (pattern.isEmpty) return text;

    final regex = compileLegadoRegex(
      pattern,
      defaultMultiLine: true,
      defaultDotAll: true,
    );
    if (regex == null) return text;
    final updated = firstOnly
        ? text.replaceFirstMapped(
            regex,
            (m) => _expandReplacement(replacement, m),
          )
        : text.replaceAllMapped(
            regex,
            (m) => _expandReplacement(replacement, m),
          );
    return updated.trim();
  }

  /// Resolves Legado `<firstPage,nextPages>` page conditionals.
  static String resolvePageConditionals(String rawTemplate, int page) {
    if (!rawTemplate.contains('<') || !rawTemplate.contains(',')) {
      return rawTemplate;
    }
    return rawTemplate.replaceAllMapped(RegExp(r'<([^<>]*),([^<>]*)>'), (m) {
      final first = m.group(1) ?? '';
      final rest = m.group(2) ?? '';
      return page <= 1 ? first : rest;
    });
  }

  /// Resolves Legado `<firstPage,nextPages>` conditionals, `{{...}}` mustache
  /// expressions, and `{$.jsonPath}` inline templates.
  static String interpolateTemplate(
    String rawTemplate, {
    String? key,
    int? page,
    String? baseUrl,
    String? result,
    Map<String, String> variables = const <String, String>{},
    String? contextInput,
    String Function(String jsExpression)? jsEvaluator,
  }) {
    var out = rawTemplate;

    if (page != null) {
      out = resolvePageConditionals(out, page);
    }

    // Resolve `{{...}}` mustache templates.
    if (out.contains('{{') && out.contains('}}')) {
      out = _replaceMustacheBlocks(out, (expr) {
        final trimmed = expr.trim();
        if (trimmed == 'key') return key ?? '{{key}}';
        if (trimmed == 'page') return page?.toString() ?? '{{page}}';
        if (trimmed == 'baseUrl' && baseUrl != null) return baseUrl;
        if (trimmed == 'result' && result != null) return result;
        if (trimmed.startsWith('@get:{') && trimmed.endsWith('}')) {
          final k = trimmed.substring(6, trimmed.length - 1).trim();
          return variables[k] ?? '';
        }
        if (trimmed.startsWith('java.get(') && trimmed.endsWith(')')) {
          final k = _stripQuotes(trimmed.substring(9, trimmed.length - 1));
          return variables[k] ?? '';
        }
        if (trimmed.startsWith(r'$.') ||
            trimmed.startsWith(r'$[') ||
            trimmed.startsWith('@Json:') ||
            trimmed.startsWith('@json:')) {
          if (contextInput != null) {
            final clean = trimmed.startsWith('@')
                ? trimmed.substring(6).trim()
                : trimmed;
            return selectOne(contextInput, clean);
          }
        }
        if (trimmed.startsWith('@@') && contextInput != null) {
          return selectOne(contextInput, trimmed.substring(2).trim());
        }
        if (jsEvaluator != null) {
          var jsExpr = trimmed;
          if (jsExpr.startsWith('@js:')) {
            jsExpr = jsExpr.substring(4).trim();
          }
          return jsEvaluator(jsExpr);
        }
        return '';
      });
    }

    // Resolve single-brace JSONPath/selector tokens such as `/i/{$.NovelID}/`.
    if (contextInput != null && (out.contains(r'{$.') || out.contains('{@@'))) {
      out = out.replaceAllMapped(RegExp(r'\{(\$\.[^}]+|@@[^}]+)\}'), (m) {
        final inner = m.group(1)!.trim();
        final rule = inner.startsWith('@@') ? inner.substring(2) : inner;
        return selectOne(contextInput, rule);
      });
    }

    return out;
  }

  static List<T> _evalCombinators<T>(
    String rule, {
    required List<T> Function(String branch) leafEval,
  }) {
    final orParts = splitTopLevel(rule, '||');
    if (orParts.length > 1) {
      for (final part in orParts) {
        final res = _evalCombinators<T>(part, leafEval: leafEval);
        if (res.isNotEmpty) return res;
      }
      return <T>[];
    }

    final andParts = splitTopLevel(rule, '&&');
    if (andParts.length > 1) {
      final combined = <T>[];
      for (final part in andParts) {
        combined.addAll(_evalCombinators<T>(part, leafEval: leafEval));
      }
      return combined;
    }

    final zipParts = splitTopLevel(rule, '%%');
    if (zipParts.length > 1) {
      final lists = zipParts
          .map((part) => _evalCombinators<T>(part, leafEval: leafEval))
          .where((l) => l.isNotEmpty)
          .toList(growable: false);
      if (lists.isEmpty) return <T>[];
      var maxLen = 0;
      for (final list in lists) {
        if (list.length > maxLen) maxLen = list.length;
      }
      final zipped = <T>[];
      for (var i = 0; i < maxLen; i++) {
        for (final list in lists) {
          if (i < list.length) {
            zipped.add(list[i]);
          }
        }
      }
      return zipped;
    }

    return leafEval(rule.trim());
  }

  static List<String> _evaluateSingleValueRule(String input, String rule) {
    final regexGroups = decodeRegexMatch(input);
    final effectiveInput = regexGroups == null
        ? input
        : (regexGroups.isEmpty ? '' : regexGroups[0]);
    final (:selectorPart, :regexSpec) = splitTrailingRegex(rule);

    List<String> extracted;
    if (selectorPart.isEmpty) {
      extracted = <String>[effectiveInput];
    } else if (regexGroups != null && containsCaptureGroupRef(selectorPart)) {
      extracted = <String>[expandCaptureGroups(selectorPart, regexGroups)];
    } else if (_isXPathRule(selectorPart)) {
      final expr = _stripPrefixCaseInsensitive(selectorPart, '@xpath:');
      extracted = selectXPath(effectiveInput, expr);
    } else if (_isJsonPathRule(selectorPart)) {
      final expr = _stripPrefixCaseInsensitive(selectorPart, '@json:');
      extracted = selectJsonPath(effectiveInput, expr);
    } else if (selectorPart.toLowerCase().startsWith('@css:')) {
      final cssRule = selectorPart.substring(5).trim();
      extracted = _evaluateCssChain(
        effectiveInput,
        cssRule,
        forceStandardCss: true,
      );
    } else {
      extracted = _evaluateCssChain(effectiveInput, selectorPart);
    }

    if (regexSpec.isEmpty) {
      return extracted
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return extracted
        .map((item) => applyRegexSpec(item, regexSpec))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _selectRegexElements(String input, String rule) {
    final orParts = _splitRegexCombinator(rule, '||');
    if (orParts.length > 1) {
      for (var i = 0; i < orParts.length; i++) {
        final branch = orParts[i].trim();
        final effectiveBranch = (i > 0 && !_hasExplicitModePrefix(branch))
            ? '@regex:$branch'
            : branch;
        final res = selectElements(input, effectiveBranch);
        if (res.isNotEmpty) return res;
      }
      return const <String>[];
    }

    final zipParts = _splitRegexCombinator(rule, '%%');
    if (zipParts.length > 1) {
      return _evalCombinators<String>(
        rule,
        leafEval: (branch) => _evaluateSingleElementRule(input, branch),
      );
    }

    final rawBody = _stripRegexListPrefix(rule);
    final andParts = _splitRegexCombinator(rawBody, '&&');
    if (andParts.length > 1) {
      final hasExplicitSubMode = andParts
          .skip(1)
          .any((p) => _hasExplicitModePrefix(p.trim()));
      if (hasExplicitSubMode) {
        final combined = <String>[];
        for (var i = 0; i < andParts.length; i++) {
          final part = andParts[i].trim();
          final effective = i == 0 ? '@regex:$part' : part;
          combined.addAll(selectElements(input, effective));
        }
        return combined;
      }
      return _evaluateRegexNarrowChain(input, andParts);
    }

    return _evaluateRegexListMatches(input, rawBody);
  }

  static List<String> _splitRegexCombinator(String rule, String operator) {
    final parts = <String>[];
    var inCharClass = false;
    var parenDepth = 0;
    var start = 0;

    for (var i = 0; i < rule.length; i++) {
      final ch = rule.codeUnitAt(i);
      if (ch == 0x5C) {
        i++;
        continue;
      }
      if (ch == 0x5B && !inCharClass) {
        inCharClass = true;
      } else if (ch == 0x5D && inCharClass) {
        inCharClass = false;
      } else if (!inCharClass) {
        if (ch == 0x28) {
          parenDepth++;
        } else if (ch == 0x29 && parenDepth > 0) {
          parenDepth--;
        } else if (parenDepth == 0 && rule.startsWith(operator, i)) {
          parts.add(rule.substring(start, i).trim());
          start = i + operator.length;
          i += operator.length - 1;
        }
      }
    }
    parts.add(rule.substring(start).trim());
    return parts.where((p) => p.isNotEmpty).toList(growable: false);
  }

  static List<String> _evaluateRegexNarrowChain(
    String input,
    List<String> patterns,
  ) {
    var currentText = input;
    var dotAll = false;
    var multiLine = false;
    var caseSensitive = true;
    for (var i = 0; i < patterns.length - 1; i++) {
      final regex = compileLegadoRegex(
        patterns[i].trim(),
        defaultDotAll: dotAll,
        defaultMultiLine: multiLine,
        defaultCaseSensitive: caseSensitive,
      );
      if (regex == null) return const <String>[];
      dotAll = regex.isDotAll;
      multiLine = regex.isMultiLine;
      caseSensitive = regex.isCaseSensitive;
      final matched = regex
          .allMatches(currentText)
          .map((m) => m.group(0) ?? '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (matched.isEmpty) return const <String>[];
      currentText = matched.join('\n');
    }
    return _evaluateRegexListMatches(
      currentText,
      patterns.last.trim(),
      defaultDotAll: dotAll,
      defaultMultiLine: multiLine,
      defaultCaseSensitive: caseSensitive,
    );
  }

  static List<String> _evaluateRegexListMatches(
    String input,
    String pattern, {
    bool defaultDotAll = false,
    bool defaultMultiLine = false,
    bool defaultCaseSensitive = true,
  }) {
    final regex = compileLegadoRegex(
      pattern,
      defaultDotAll: defaultDotAll,
      defaultMultiLine: defaultMultiLine,
      defaultCaseSensitive: defaultCaseSensitive,
    );
    if (regex == null) return const <String>[];
    final out = <String>[];
    for (final match in regex.allMatches(input)) {
      final full = match.group(0) ?? '';
      if (full.isEmpty) continue;
      final groups = List<String>.generate(
        match.groupCount + 1,
        (idx) => match.group(idx) ?? '',
        growable: false,
      );
      out.add(encodeRegexMatch(groups));
    }
    return out;
  }

  static String _stripRegexListPrefix(String rule) {
    final trimmed = rule.trim();
    if (trimmed.toLowerCase().startsWith('@regex:')) {
      return trimmed.substring(7).trim();
    }
    if (trimmed.startsWith(':') && !trimmed.startsWith('::')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  static bool _hasExplicitModePrefix(String branch) {
    final lower = branch.toLowerCase();
    return isRegexListRule(branch) ||
        lower.startsWith('@css:') ||
        _isXPathRule(branch) ||
        _isJsonPathRule(branch);
  }

  static List<String> _evaluateSingleElementRule(
    String input,
    String listRule,
  ) {
    if (isRegexListRule(listRule)) {
      return _selectRegexElements(input, listRule);
    }

    final (:selectorPart, :regexSpec) = splitTrailingRegex(listRule);
    final targetRule = selectorPart.isEmpty ? listRule : selectorPart;

    if (_isXPathRule(targetRule)) {
      final expr = _stripPrefixCaseInsensitive(targetRule, '@xpath:');
      return selectXPathElements(input, expr);
    }
    if (_isJsonPathRule(targetRule)) {
      final expr = _stripPrefixCaseInsensitive(targetRule, '@json:');
      return selectJsonElements(input, expr);
    }

    final forceStdCss = targetRule.toLowerCase().startsWith('@css:');
    final effective = forceStdCss ? targetRule.substring(5).trim() : targetRule;

    final doc = html_parser.parse(input);
    final root = doc.documentElement;
    if (root == null) return const <String>[];

    final parts = _splitAtSteps(effective);
    if (parts.isEmpty) return const <String>[];

    var currentNodes = <Element>[root];
    for (final step in parts) {
      currentNodes = _applyElementStep(
        currentNodes,
        step,
        forceStandardCss: forceStdCss,
      );
      if (currentNodes.isEmpty) return const <String>[];
    }

    final htmlList = currentNodes
        .map((e) => e.outerHtml)
        .toList(growable: false);
    if (regexSpec.isEmpty) return htmlList;
    return htmlList
        .map((item) => applyRegexSpec(item, regexSpec))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _evaluateCssChain(
    String htmlText,
    String rule, {
    bool forceStandardCss = false,
  }) {
    final doc = html_parser.parse(htmlText);
    final root = doc.documentElement;
    if (root == null) return const <String>[];

    final parts = _splitAtSteps(rule);
    if (parts.isEmpty) return const <String>[];

    var extractor = 'text';
    var selectorParts = parts;

    if (parts.length == 1) {
      if (_knownExtractors.contains(parts.first.toLowerCase())) {
        extractor = parts.first;
        selectorParts = const <String>[];
      }
    } else {
      final last = parts.last;
      if (_isLikelyExtractorToken(last)) {
        extractor = last;
        selectorParts = parts.sublist(0, parts.length - 1);
      }
    }

    var currentNodes = <Element>[root];
    for (var i = 0; i < selectorParts.length; i++) {
      final step = selectorParts[i];
      final nextNodes = _applyElementStep(
        currentNodes,
        step,
        forceStandardCss: forceStandardCss,
      );

      // Disambiguate ambiguous final token (e.g. `title` or `name`) when
      // selecting child elements returns empty and the token could be an attr.
      if (nextNodes.isEmpty &&
          i == selectorParts.length - 1 &&
          extractor == 'text' &&
          _isPlainIdentifier(step) &&
          currentNodes.any((el) => el.attributes.containsKey(step))) {
        extractor = step;
        break;
      }

      currentNodes = nextNodes;
      if (currentNodes.isEmpty) return const <String>[];
    }

    if (selectorParts.isEmpty &&
        currentNodes.length == 1 &&
        identical(currentNodes.first, root)) {
      // Unwrap synthetic <html><body> wrapper for HTML snippet inputs when
      // evaluating bare `@text` / `@html` / `@href`.
      final body = doc.body;
      if (body != null && !htmlText.toLowerCase().contains('<html')) {
        if (body.children.length == 1 &&
            _commonAttributes.contains(extractor.toLowerCase())) {
          currentNodes = <Element>[body.children.first];
        } else {
          currentNodes = <Element>[body];
        }
      }
    }

    return currentNodes
        .map((el) => _extractValue(el, extractor))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static List<Element> _applyElementStep(
    List<Element> currentNodes,
    String rawStep, {
    required bool forceStandardCss,
  }) {
    final nextNodes = <Element>[];
    if (forceStandardCss) {
      for (final node in currentNodes) {
        nextNodes.addAll(_querySelectorSafe(node, rawStep));
      }
      return nextNodes;
    }

    final stepSpec = _parseLegadoStep(rawStep);
    for (final node in currentNodes) {
      var matched = _querySingleLegadoSelector(node, stepSpec.selector);
      if (stepSpec.excludedIndices.isNotEmpty && matched.isNotEmpty) {
        matched = _applyExclusions(matched, stepSpec.excludedIndices);
      }
      if (stepSpec.index != null) {
        final rawIdx = stepSpec.index!;
        final idx = rawIdx < 0 ? matched.length + rawIdx : rawIdx;
        if (idx >= 0 && idx < matched.length) {
          nextNodes.add(matched[idx]);
        }
      } else {
        nextNodes.addAll(matched);
      }
    }
    return nextNodes;
  }

  static List<Element> _querySingleLegadoSelector(
    Element node,
    String selector,
  ) {
    final trimmed = selector.trim();
    if (trimmed.isEmpty) return <Element>[node];

    if (trimmed == 'children') {
      return List<Element>.of(node.children);
    }

    if (trimmed.startsWith('text.')) {
      final needle = trimmed.substring(5);
      if (needle.isEmpty) return const <Element>[];
      final allDescendants = node.querySelectorAll('*');
      final ownMatches = <Element>[];
      for (final el in allDescendants) {
        if (_directText(el).contains(needle)) {
          ownMatches.add(el);
        }
      }
      if (ownMatches.isNotEmpty) return ownMatches;
      if (node.localName != 'html' && _directText(node).contains(needle)) {
        return <Element>[node];
      }
      final fullMatches = allDescendants
          .where((el) => el.text.contains(needle))
          .toList(growable: false);
      if (fullMatches.isNotEmpty) return fullMatches;
      if (node.localName != 'html' && node.text.contains(needle)) {
        return <Element>[node];
      }
      return const <Element>[];
    }

    if (trimmed.startsWith('class.')) {
      final classes = trimmed
          .substring(6)
          .trim()
          .split(RegExp(r'\s+'))
          .where((c) => c.isNotEmpty)
          .toList(growable: false);
      if (classes.isEmpty) return const <Element>[];
      final css = classes.map((c) => '.${_escapeCssIdentIfNeeded(c)}').join();
      return _querySelectorSafe(node, css);
    }

    if (trimmed.startsWith('id.')) {
      final idValue = trimmed.substring(3).trim();
      if (idValue.isEmpty) return const <Element>[];
      final escaped = idValue.replaceAll('"', r'\"');
      return _querySelectorSafe(node, '[id="$escaped"]');
    }

    if (trimmed.startsWith('tag.')) {
      final tagSelector = trimmed.substring(4).trim();
      if (tagSelector.isEmpty) return const <Element>[];
      return _querySelectorSafe(node, tagSelector);
    }

    return _querySelectorSafe(node, trimmed);
  }

  static List<Element> _querySelectorSafe(Element node, String selector) {
    final trimmed = selector.trim();
    if (trimmed.isEmpty) return <Element>[node];

    // Support jQuery-style `:contains(text)` and `:eq(n)` extensions seen in
    // real Legado sources.
    if (trimmed.contains(':contains(') || trimmed.contains(':eq(')) {
      return _queryExtendedCss(node, trimmed);
    }

    try {
      return node.querySelectorAll(trimmed);
    } catch (_) {
      return const <Element>[];
    }
  }

  static List<Element> _queryExtendedCss(Element root, String selector) {
    final parts = selector.split('>');
    var current = <Element>[root];

    for (final rawPart in parts) {
      var part = rawPart.trim();
      if (part.isEmpty) continue;

      String? containsText;
      final containsMatch = RegExp(r':contains\(([^)]+)\)').firstMatch(part);
      if (containsMatch != null) {
        containsText = _stripQuotes(containsMatch.group(1)!);
        part = part.replaceRange(
          containsMatch.start,
          containsMatch.end,
          '',
        ).trim();
      }

      int? eqIndex;
      final eqMatch = RegExp(r':eq\((-?\d+)\)').firstMatch(part);
      if (eqMatch != null) {
        eqIndex = int.tryParse(eqMatch.group(1)!);
        part = part.replaceRange(eqMatch.start, eqMatch.end, '').trim();
      }

      final baseSelector = part.isEmpty ? '*' : part;
      final next = <Element>[];
      for (final node in current) {
        try {
          var matches = node.querySelectorAll(baseSelector);
          if (containsText != null) {
            matches = matches
                .where((el) => el.text.contains(containsText!))
                .toList(growable: false);
          }
          if (eqIndex != null) {
            final idx = eqIndex < 0 ? matches.length + eqIndex : eqIndex;
            if (idx >= 0 && idx < matches.length) {
              next.add(matches[idx]);
            }
          } else {
            next.addAll(matches);
          }
        } catch (_) {
          return const <Element>[];
        }
      }
      current = next;
      if (current.isEmpty) return const <Element>[];
    }
    return current;
  }

  static ({
    String selector,
    int? index,
    List<String> excludedIndices,
  }) _parseLegadoStep(String raw) {
    var working = raw.trim();
    var excludedTokens = const <String>[];

    // Extract trailing `!0`, `!-1`, `!0:-1`, `!0,1` outside `[...]`.
    final bangIdx = _lastIndexOutsideBrackets(working, '!');
    if (bangIdx != -1) {
      final spec = working.substring(bangIdx + 1).trim();
      if (RegExp(r'^-?\d+(?:[:,\s]+-?\d+)*$').hasMatch(spec)) {
        excludedTokens = spec
            .split(RegExp(r'[:,\s]+'))
            .where((t) => t.isNotEmpty)
            .toList(growable: false);
        working = working.substring(0, bangIdx).trim();
      }
    }

    int? index;
    final idxMatch = RegExp(r'^(.*)\.(-?\d+)$').firstMatch(working);
    if (idxMatch != null) {
      final prefix = idxMatch.group(1)!.trim();
      final parsedIdx = int.tryParse(idxMatch.group(2)!);
      if (prefix.isNotEmpty && parsedIdx != null) {
        working = prefix;
        index = parsedIdx;
      }
    }

    return (
      selector: working,
      index: index,
      excludedIndices: excludedTokens,
    );
  }

  static List<Element> _applyExclusions(
    List<Element> items,
    List<String> excludedTokens,
  ) {
    final excluded = <int>{};
    for (final token in excludedTokens) {
      final rawIdx = int.tryParse(token);
      if (rawIdx == null) continue;
      final resolved = rawIdx < 0 ? items.length + rawIdx : rawIdx;
      if (resolved >= 0 && resolved < items.length) {
        excluded.add(resolved);
      }
    }
    if (excluded.isEmpty) return items;
    final out = <Element>[];
    for (var i = 0; i < items.length; i++) {
      if (!excluded.contains(i)) {
        out.add(items[i]);
      }
    }
    return out;
  }

  static bool _isLikelyExtractorToken(String token) {
    final lower = token.toLowerCase();
    if (_knownExtractors.contains(lower)) return true;
    if (_commonAttributes.contains(lower)) return true;
    if (lower.startsWith('data-')) return true;
    if (_htmlTagNames.contains(lower)) return false;
    return _isPlainIdentifier(token);
  }

  static bool _isPlainIdentifier(String token) =>
      RegExp(r'^[a-zA-Z_][a-zA-Z0-9_-]*$').hasMatch(token);

  static String _extractValue(Element el, String extractor) {
    switch (extractor.toLowerCase()) {
      case 'text':
        return _cleanText(el.text);
      case 'textnodes':
      case 'owntext':
        return _cleanText(_directText(el));
      case 'html':
      case 'all':
        return htmlToParagraphs(el.innerHtml);
      case 'innerhtml':
        return el.innerHtml.trim();
      case 'outerhtml':
        return el.outerHtml.trim();
      default:
        return (el.attributes[extractor] ?? '').trim();
    }
  }

  static String _directText(Element el) {
    return el.nodes
        .where((n) => n.nodeType == Node.TEXT_NODE)
        .map((n) => n.text ?? '')
        .join('\n');
  }

  /// Converts an HTML fragment into clean newline-separated paragraphs while
  /// stripping `<script>`, `<style>`, and HTML comments.
  static String htmlToParagraphs(String htmlSnippet) {
    var text = htmlSnippet
        .replaceAll(
          RegExp(r'<!--[\s\S]*?-->', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|li|h[1-6]|tr)\s*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<(p|div)[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '');

    text = _decodeHtmlEntities(text);

    final lines = text
        .split('\n')
        .map((line) => line.replaceAll('\u00A0', ' ').trim())
        .where((line) => line.isNotEmpty);
    return lines.join('\n');
  }

  static String _decodeHtmlEntities(String input) {
    var out = input
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&ensp;', ' ')
        .replaceAll('&emsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'");
    if (out.contains('&#')) {
      out = out.replaceAllMapped(RegExp(r'&#(x?[0-9a-fA-F]+);'), (m) {
        final raw = m.group(1)!;
        final code = raw.startsWith('x') || raw.startsWith('X')
            ? int.tryParse(raw.substring(1), radix: 16)
            : int.tryParse(raw);
        if (code != null && code > 0 && code <= 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return m.group(0)!;
      });
    }
    return out;
  }

  static String _cleanText(String raw) {
    return raw
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static HtmlXPath? _createHtmlXPath(String htmlText) {
    final trimmed = htmlText.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.contains('<html')) {
      return HtmlXPath.html(trimmed);
    }
    final frag = html_parser.parseFragment(trimmed);
    if (frag.children.length == 1) {
      return HtmlXPath.node(frag.children.first);
    }
    return HtmlXPath.html(trimmed);
  }

  static bool _isXPathRule(String rule) {
    final lower = rule.toLowerCase();
    return lower.startsWith('@xpath:') ||
        rule.startsWith('//') ||
        rule.startsWith('./');
  }

  static bool _isJsonPathRule(String rule) {
    final lower = rule.toLowerCase();
    return lower.startsWith('@json:') ||
        rule.startsWith(r'$.') ||
        rule.startsWith(r'$[') ||
        rule == r'$';
  }

  static String _stripPrefixCaseInsensitive(String input, String prefix) {
    if (input.toLowerCase().startsWith(prefix.toLowerCase())) {
      return input.substring(prefix.length).trim();
    }
    return input;
  }

  /// Splits trailing `##pattern##replacement` out of [rule] outside quotes and
  /// brackets.
  static ({String selectorPart, String regexSpec}) splitTrailingRegex(
    String rule,
  ) {
    var inSingle = false;
    var inDouble = false;
    var bracketDepth = 0;
    var parenDepth = 0;
    var braceDepth = 0;

    for (var i = 0; i < rule.length - 1; i++) {
      final ch = rule.codeUnitAt(i);
      if (ch == 0x5C) {
        i++;
        continue;
      }
      if (ch == 0x27 && !inDouble) {
        inSingle = !inSingle;
      } else if (ch == 0x22 && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (ch == 0x5B) {
          bracketDepth++;
        } else if (ch == 0x5D && bracketDepth > 0) {
          bracketDepth--;
        } else if (ch == 0x28) {
          parenDepth++;
        } else if (ch == 0x29 && parenDepth > 0) {
          parenDepth--;
        } else if (ch == 0x7B) {
          braceDepth++;
        } else if (ch == 0x7D && braceDepth > 0) {
          braceDepth--;
        } else if (ch == 0x23 &&
            rule.codeUnitAt(i + 1) == 0x23 &&
            bracketDepth == 0 &&
            parenDepth == 0 &&
            braceDepth == 0) {
          return (
            selectorPart: rule.substring(0, i).trim(),
            regexSpec: rule.substring(i + 2),
          );
        }
      }
    }
    return (selectorPart: rule.trim(), regexSpec: '');
  }

  /// Splits [rule] on top-level combinator [operator] (`||`, `&&`, `%%`)
  /// outside quotes and brackets.
  static List<String> splitTopLevel(String rule, String operator) {
    final parts = <String>[];
    var inSingle = false;
    var inDouble = false;
    var bracketDepth = 0;
    var parenDepth = 0;
    var braceDepth = 0;
    var start = 0;

    for (var i = 0; i < rule.length; i++) {
      final ch = rule.codeUnitAt(i);
      if (ch == 0x5C) {
        i++;
        continue;
      }
      if (ch == 0x27 && !inDouble) {
        inSingle = !inSingle;
      } else if (ch == 0x22 && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (ch == 0x5B) {
          bracketDepth++;
        } else if (ch == 0x5D && bracketDepth > 0) {
          bracketDepth--;
        } else if (ch == 0x28) {
          parenDepth++;
        } else if (ch == 0x29 && parenDepth > 0) {
          parenDepth--;
        } else if (ch == 0x7B) {
          braceDepth++;
        } else if (ch == 0x7D && braceDepth > 0) {
          braceDepth--;
        } else if (bracketDepth == 0 &&
            parenDepth == 0 &&
            braceDepth == 0 &&
            rule.startsWith(operator, i)) {
          parts.add(rule.substring(start, i).trim());
          start = i + operator.length;
          i += operator.length - 1;
        }
      }
    }
    parts.add(rule.substring(start).trim());
    return parts.where((p) => p.isNotEmpty).toList(growable: false);
  }

  static List<String> _splitAtSteps(String rule) {
    final parts = <String>[];
    var inSingle = false;
    var inDouble = false;
    var bracketDepth = 0;
    var parenDepth = 0;
    var start = 0;

    for (var i = 0; i < rule.length; i++) {
      final ch = rule.codeUnitAt(i);
      if (ch == 0x5C) {
        i++;
        continue;
      }
      if (ch == 0x27 && !inDouble) {
        inSingle = !inSingle;
      } else if (ch == 0x22 && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (ch == 0x5B) {
          bracketDepth++;
        } else if (ch == 0x5D && bracketDepth > 0) {
          bracketDepth--;
        } else if (ch == 0x28) {
          parenDepth++;
        } else if (ch == 0x29 && parenDepth > 0) {
          parenDepth--;
        } else if (ch == 0x40 && bracketDepth == 0 && parenDepth == 0) {
          final seg = rule.substring(start, i).trim();
          if (seg.isNotEmpty) parts.add(seg);
          start = i + 1;
        }
      }
    }
    final tail = rule.substring(start).trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  static int _lastIndexOutsideBrackets(String input, String char) {
    final targetCode = char.codeUnitAt(0);
    var inSingle = false;
    var inDouble = false;
    var bracketDepth = 0;
    var parenDepth = 0;
    var last = -1;

    for (var i = 0; i < input.length; i++) {
      final ch = input.codeUnitAt(i);
      if (ch == 0x27 && !inDouble) {
        inSingle = !inSingle;
      } else if (ch == 0x22 && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (ch == 0x5B) {
          bracketDepth++;
        } else if (ch == 0x5D && bracketDepth > 0) {
          bracketDepth--;
        } else if (ch == 0x28) {
          parenDepth++;
        } else if (ch == 0x29 && parenDepth > 0) {
          parenDepth--;
        } else if (ch == targetCode && bracketDepth == 0 && parenDepth == 0) {
          last = i;
        }
      }
    }
    return last;
  }

  static String _expandReplacement(String template, Match match) {
    if (!template.contains(r'$')) return template;
    return template.replaceAllMapped(RegExp(r'\$\{(\d+)\}|\$(\d+)'), (m) {
      final idxStr = m.group(1) ?? m.group(2)!;
      final groupIdx = int.tryParse(idxStr);
      if (groupIdx != null && groupIdx >= 0 && groupIdx <= match.groupCount) {
        return match.group(groupIdx) ?? '';
      }
      return m.group(0)!;
    });
  }

  static String _replaceMustacheBlocks(
    String input,
    String Function(String expr) resolver,
  ) {
    final out = StringBuffer();
    var cursor = 0;
    while (cursor < input.length) {
      final open = input.indexOf('{{', cursor);
      if (open == -1) {
        out.write(input.substring(cursor));
        break;
      }
      out.write(input.substring(cursor, open));
      final close = _findMatchingDoubleBraceClose(input, open + 2);
      if (close == -1) {
        out.write(input.substring(open));
        break;
      }
      final expr = input.substring(open + 2, close);
      out.write(resolver(expr));
      cursor = close + 2;
    }
    return out.toString();
  }

  static int _findMatchingDoubleBraceClose(String input, int start) {
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    for (var i = start; i < input.length - 1; i++) {
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
            return i;
          }
          if (depth > 0) depth--;
        }
      }
    }
    return -1;
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

  static String _escapeCssIdentIfNeeded(String className) {
    if (RegExp(r'^[a-zA-Z_-][a-zA-Z0-9_-]*$').hasMatch(className)) {
      return className;
    }
    return '[class~="${className.replaceAll('"', r'\"')}"]';
  }
}
