import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:json_path/json_path.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// Shared HTML / CSS / XPath / JSONPath extractor used by both
/// [JsPluginProvider] and [LegadoCompatProvider].
class HtmlSelectorHelper {
  const HtmlSelectorHelper._();

  static List<String> selectCss(String htmlText, String rule) {
    final doc = html_parser.parse(htmlText);
    final root = doc.documentElement;
    if (root == null) return const [];
    return _evaluateCssChainOnNode(root, rule);
  }

  static String selectCssOne(String htmlText, String rule) {
    final matches = selectCss(htmlText, rule);
    return matches.isEmpty ? '' : matches.first;
  }

  static List<String> selectElementsHtml(String htmlText, String cssSelector) {
    final doc = html_parser.parse(htmlText);
    return doc.querySelectorAll(cssSelector).map((e) => e.outerHtml).toList();
  }

  static List<String> selectXPath(String htmlText, String expr) {
    final xpath = HtmlXPath.html(htmlText);
    final result = xpath.query(expr);
    final attrs = result.attrs
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (attrs.isNotEmpty) return attrs;
    return result.nodes
        .map((n) => (n.text ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static List<String> selectJsonPath(String jsonText, String expr) {
    final decoded = jsonDecode(jsonText);
    final path = JsonPath(expr);
    return path.readValues(decoded).map((value) {
      if (value == null) return '';
      if (value is String) return value;
      return jsonEncode(value);
    }).toList();
  }

  /// Evaluates a Legado-style chained CSS rule such as:
  /// - `div.book@text`
  /// - `a.0@href`
  /// - `div.item@tag.a.0@href`
  /// - `#content@html`
  /// - `.intro@textNodes`
  static List<String> _evaluateCssChainOnNode(Element root, String rule) {
    final parts = rule
        .split('@')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const [];

    const extractionTokens = {
      'text',
      'textnodes',
      'owntext',
      'html',
      'all',
      'href',
      'src',
    };

    String extractor = 'text';
    final selectorParts = <String>[];

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;
      if (isLast && _isAttributeOrExtractorToken(part, extractionTokens)) {
        extractor = part;
      } else {
        selectorParts.add(part);
      }
    }

    var currentNodes = <Element>[root];
    for (final rawStep in selectorParts) {
      final nextNodes = <Element>[];
      final parsed = _parseIndexedSelector(rawStep);
      for (final node in currentNodes) {
        final matched = _queryLegadoSelector(node, parsed.selector);
        if (parsed.index != null) {
          final idx = parsed.index! < 0
              ? matched.length + parsed.index!
              : parsed.index!;
          if (idx >= 0 && idx < matched.length) {
            nextNodes.add(matched[idx]);
          }
        } else {
          nextNodes.addAll(matched);
        }
      }
      currentNodes = nextNodes;
      if (currentNodes.isEmpty) return const [];
    }

    return currentNodes
        .map((el) => _extractValue(el, extractor))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static bool _isAttributeOrExtractorToken(
    String token,
    Set<String> knownTokens,
  ) {
    final lower = token.toLowerCase();
    if (knownTokens.contains(lower)) return true;
    // Plain attribute name without CSS combinators/dots/brackets/hashes.
    return RegExp(r'^[a-zA-Z_][a-zA-Z0-9_-]*$').hasMatch(token);
  }

  static ({String selector, int? index}) _parseIndexedSelector(String raw) {
    // Handle `tag.a.0` or `div.item.-1` or `a.0`.
    final indexMatch = RegExp(r'^(.*)\.(-?\d+)$').firstMatch(raw);
    if (indexMatch != null) {
      final prefix = indexMatch.group(1)!.trim();
      final idx = int.tryParse(indexMatch.group(2)!);
      if (prefix.isNotEmpty && idx != null) {
        return (selector: prefix, index: idx);
      }
    }
    return (selector: raw, index: null);
  }

  static List<Element> _queryLegadoSelector(Element node, String selector) {
    // Convert Legado prefixes (`tag.a`, `class.foo`, `id.bar`) to standard CSS.
    final normalized = _normalizeLegadoCssStep(selector);
    if (normalized.isEmpty) return [node];
    return node.querySelectorAll(normalized);
  }

  static String _normalizeLegadoCssStep(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('tag.')) {
      return trimmed.substring(4);
    }
    if (trimmed.startsWith('class.')) {
      return '.${trimmed.substring(6).trim().replaceAll(' ', '.')}';
    }
    if (trimmed.startsWith('id.')) {
      return '#${trimmed.substring(3)}';
    }
    return trimmed;
  }

  static String _extractValue(Element el, String extractor) {
    switch (extractor.toLowerCase()) {
      case 'text':
        return _cleanText(el.text);
      case 'textnodes':
      case 'owntext':
        final directText = el.nodes
            .where((n) => n.nodeType == Node.TEXT_NODE)
            .map((n) => n.text ?? '')
            .join('\n');
        return _cleanText(directText);
      case 'html':
      case 'all':
        return _htmlToParagraphs(el.innerHtml);
      default:
        return (el.attributes[extractor] ?? '').trim();
    }
  }

  static String _cleanText(String raw) {
    return raw
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _htmlToParagraphs(String htmlSnippet) {
    var text = htmlSnippet
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"');
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return lines.join('\n');
  }
}
