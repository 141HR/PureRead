import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'epub_path_utils.dart';

/// Pure-Dart XHTML/HTML byte decoder and text extractor for EPUB chapters.
///
/// Decodes BOM-prefixed and declared charset encodings cleanly, drops
/// `<script>`, `<style>`, `<head>`, `<svg>`, `<noscript>`, preserves crisp
/// paragraph boundaries for block tags, normalizes inline spacing, and slices
/// multi-anchor `#fragment` spine chapters without leaking subsequent chapters.
class EpubXhtmlExtractor {
  const EpubXhtmlExtractor._();

  static const Set<String> _ignoredTags = <String>{
    'script',
    'style',
    'head',
    'svg',
    'noscript',
    'template',
  };

  static const Set<String> _nonSvgIgnoredTags = <String>{
    'script',
    'style',
    'head',
    'noscript',
    'template',
  };

  static const Set<String> _blockTags = <String>{
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'blockquote',
    'tr',
    'section',
    'article',
    'aside',
    'header',
    'footer',
    'main',
    'nav',
    'figure',
    'figcaption',
    'pre',
    'dt',
    'dd',
    'address',
    'table',
    'ul',
    'ol',
    'dl',
  };

  static const Set<String> _breakTags = <String>{'br', 'hr'};
  static const Set<String> _cellSeparatorTags = <String>{'td', 'th'};

  static final RegExp _xmlEncodingRegex = RegExp(
    r'''<\?xml[^>]*?\bencoding\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  static final RegExp _metaCharsetRegex = RegExp(
    r'''<meta\b[^>]*?\bcharset\s*=\s*["']?\s*([A-Za-z0-9._-]+)''',
    caseSensitive: false,
  );

  static final RegExp _inlineWhitespaceRegex = RegExp(r'[ \t\r\n\f\u00A0]+');

  /// Decodes XML/XHTML/HTML [bytes] to a Dart [String], stripping any BOM and
  /// honoring XML declaration or HTML `<meta charset>` encoding hints.
  static String decodeBytesToString(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _stripLeadingBom(
        utf8.decode(Uint8List.sublistView(bytes, 3), allowMalformed: true),
      );
    }

    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        final slice = Uint8List.sublistView(bytes, 2);
        return _stripLeadingBom(
          (utf16.decoder as Utf16Decoder).decodeUtf16Le(
            slice,
            0,
            slice.length,
            false,
          ),
        );
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        final slice = Uint8List.sublistView(bytes, 2);
        return _stripLeadingBom(
          (utf16.decoder as Utf16Decoder).decodeUtf16Be(
            slice,
            0,
            slice.length,
            false,
          ),
        );
      }
    }

    final hintedEncoding = _detectDeclaredEncoding(bytes);
    if (hintedEncoding != null) {
      return _stripLeadingBom(_decodeWithLabel(bytes, hintedEncoding));
    }

    try {
      return _stripLeadingBom(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      try {
        return _stripLeadingBom(gbk.decode(bytes, allowMalformed: false));
      } on FormatException {
        return _stripLeadingBom(utf8.decode(bytes, allowMalformed: true));
      }
    }
  }

  static String? _detectDeclaredEncoding(Uint8List bytes) {
    final prefixLen = bytes.length < 1024 ? bytes.length : 1024;
    final prefix = latin1.decode(
      Uint8List.sublistView(bytes, 0, prefixLen),
      allowInvalid: true,
    );
    final xmlMatch = _xmlEncodingRegex.firstMatch(prefix);
    if (xmlMatch != null) {
      return xmlMatch.group(1)?.trim();
    }
    final metaMatch = _metaCharsetRegex.firstMatch(prefix);
    if (metaMatch != null) {
      return metaMatch.group(1)?.trim();
    }
    return null;
  }

  static String _decodeWithLabel(Uint8List bytes, String label) {
    final normalized = label
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(' ', '');
    switch (normalized) {
      case 'utf-8':
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'utf-16le':
      case 'utf16le':
        return (utf16.decoder as Utf16Decoder).decodeUtf16Le(
          bytes,
          0,
          bytes.length,
          true,
        );
      case 'utf-16be':
      case 'utf16be':
        return (utf16.decoder as Utf16Decoder).decodeUtf16Be(
          bytes,
          0,
          bytes.length,
          true,
        );
      case 'utf-16':
      case 'utf16':
        return utf16.decode(bytes);
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
      case 'cp936':
      case 'ms936':
        return gbk.decode(bytes, allowMalformed: true);
      case 'iso-8859-1':
      case 'iso8859-1':
      case 'latin1':
      case 'latin-1':
        return latin1.decode(bytes, allowInvalid: true);
      default:
        final resolved = Charset.getByName(normalized);
        if (resolved != null) {
          return resolved.decode(bytes);
        }
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static String _stripLeadingBom(String value) {
    if (value.isNotEmpty && value.codeUnitAt(0) == 0xFEFF) {
      return value.substring(1);
    }
    return value;
  }

  /// Extracts clean paragraph-delimited text from raw XHTML/HTML [bytes].
  ///
  /// When [fragment] is provided, extraction begins at the element matching
  /// `[id=fragment]` or `<a name=fragment>` and stops cleanly before the first
  /// element matching [stopFragment] or any entry in [stopFragments].
  ///
  /// When [onImage] is provided, `<img>` and `<svg>` descendant `<image>` tags
  /// invoke [onImage] and any non-empty returned marker is emitted on its own
  /// standalone line.
  static String extractText(
    Uint8List bytes, {
    String? fragment,
    String? stopFragment,
    List<String> stopFragments = const <String>[],
    String? Function(String rawSrc, String alt)? onImage,
  }) {
    final htmlText = decodeBytesToString(bytes);
    return extractTextFromHtml(
      htmlText,
      fragment: fragment,
      stopFragment: stopFragment,
      stopFragments: stopFragments,
      onImage: onImage,
    );
  }

  /// Extracts clean paragraph-delimited text from decoded [htmlText].
  static String extractTextFromHtml(
    String htmlText, {
    String? fragment,
    String? stopFragment,
    List<String> stopFragments = const <String>[],
    String? Function(String rawSrc, String alt)? onImage,
  }) {
    if (htmlText.trim().isEmpty) return '';

    final doc = html_parser.parse(htmlText);
    final root = doc.body ?? doc.documentElement;
    if (root == null) return '';

    final startIds = _expandAnchorCandidates(fragment);
    final stopIds = <String>{
      if (stopFragment != null) ..._expandAnchorCandidates(stopFragment),
      for (final stop in stopFragments) ..._expandAnchorCandidates(stop),
    }..removeAll(startIds);

    dom.Element? startElement;
    if (startIds.isNotEmpty) {
      startElement = _findAnchorElement(root, startIds);
      if (startElement == null && stopIds.isNotEmpty) {
        // Avoid leaking unrelated chapters from a multi-chapter XHTML file
        // when the requested anchor is missing.
        return '';
      }
    }

    final containerBoundStop =
        startElement != null &&
        stopIds.isEmpty &&
        _shouldStopOnContainerExit(startElement);

    final walker = _DomTextWalker(
      startElement: startElement,
      stopIds: stopIds,
      containerBoundStop: containerBoundStop,
      onImage: onImage,
    );
    walker.walk(root);
    return walker.finish();
  }

  /// Extracts `<title>` and the first heading (`<h1>`-`<h3>`) from an XHTML
  /// document for spine-only chapter title fallback.
  static ({String? title, String? heading}) extractDocumentTitles(
    String htmlText,
  ) {
    if (htmlText.trim().isEmpty) {
      return (title: null, heading: null);
    }
    final doc = html_parser.parse(htmlText);
    final rawTitle = doc.head?.querySelector('title')?.text;
    final cleanTitle = rawTitle == null ? null : normalizeInlineText(rawTitle);

    String? heading;
    final body = doc.body ?? doc.documentElement;
    if (body != null) {
      for (final selector in const <String>['h1', 'h2', 'h3']) {
        final el = body.querySelector(selector);
        if (el != null) {
          final text = normalizeInlineText(el.text);
          if (text.isNotEmpty) {
            heading = text;
            break;
          }
        }
      }
    }

    return (
      title: (cleanTitle != null && cleanTitle.isNotEmpty) ? cleanTitle : null,
      heading: heading,
    );
  }

  /// Collapses inline HTML whitespace runs (`[\t\r\n\f ]` and NBSP) to single
  /// spaces and trims leading/trailing whitespace.
  static String normalizeInlineText(String raw) {
    if (raw.isEmpty) return '';
    return raw
        .replaceAll('\uFEFF', '')
        .replaceAll(_inlineWhitespaceRegex, ' ')
        .trim();
  }

  static Set<String> _expandAnchorCandidates(String? rawFragment) {
    if (rawFragment == null) return const <String>{};
    final trimmed = rawFragment.trim();
    if (trimmed.isEmpty) return const <String>{};
    final decoded = EpubPathUtils.safeUrlDecode(trimmed);
    if (decoded == trimmed || decoded.isEmpty) {
      return <String>{trimmed};
    }
    return <String>{trimmed, decoded};
  }

  static dom.Element? _findAnchorElement(
    dom.Element root,
    Set<String> targetIds,
  ) {
    dom.Element? visit(dom.Element el) {
      final tag = (el.localName ?? '').toLowerCase();
      if (_ignoredTags.contains(tag)) return null;
      if (_elementMatchesAnyId(el, targetIds)) {
        return el;
      }
      for (final child in el.children) {
        final hit = visit(child);
        if (hit != null) return hit;
      }
      return null;
    }

    return visit(root);
  }

  static bool _elementMatchesAnyId(dom.Element el, Set<String> targetIds) {
    if (targetIds.isEmpty) return false;
    final id = el.id.trim();
    if (id.isNotEmpty && targetIds.contains(id)) {
      return true;
    }
    final tag = (el.localName ?? '').toLowerCase();
    if (tag == 'a') {
      final nameAttr = el.attributes['name']?.trim();
      if (nameAttr != null &&
          nameAttr.isNotEmpty &&
          targetIds.contains(nameAttr)) {
        return true;
      }
    }
    for (final entry in el.attributes.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key == 'xml:id') {
        final val = entry.value.trim();
        if (val.isNotEmpty && targetIds.contains(val)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _shouldStopOnContainerExit(dom.Element el) {
    final tag = (el.localName ?? '').toLowerCase();
    if (tag == 'section' || tag == 'article') {
      return normalizeInlineText(el.text).isNotEmpty;
    }
    if (tag == 'div') {
      if (normalizeInlineText(el.text).isEmpty) return false;
      return el.querySelector('p, div, blockquote, li, tr, section, article') !=
          null;
    }
    return false;
  }
}

class _DomTextWalker {
  _DomTextWalker({
    required this.startElement,
    required this.stopIds,
    required this.containerBoundStop,
    this.onImage,
  }) : _capturing = startElement == null;

  final dom.Element? startElement;
  final Set<String> stopIds;
  final bool containerBoundStop;
  final String? Function(String rawSrc, String alt)? onImage;

  bool _capturing;
  bool _stopped = false;
  int _preDepth = 0;

  final List<String> _lines = <String>[];
  final StringBuffer _currentLine = StringBuffer();
  bool _pendingSpace = false;

  void walk(dom.Node node) {
    if (_stopped) return;

    if (node is dom.Element) {
      final tag = (node.localName ?? '').toLowerCase();
      if (onImage == null) {
        if (EpubXhtmlExtractor._ignoredTags.contains(tag)) {
          return;
        }
      } else if (EpubXhtmlExtractor._nonSvgIgnoredTags.contains(tag)) {
        return;
      }

      final isStart = identical(node, startElement);
      if (_capturing && !isStart && stopIds.isNotEmpty) {
        if (EpubXhtmlExtractor._elementMatchesAnyId(node, stopIds)) {
          _flushLine();
          _stopped = true;
          return;
        }
      }

      var startedHere = false;
      if (!_capturing && isStart) {
        _capturing = true;
        startedHere = true;
      }

      if (tag == 'svg') {
        if (_capturing) {
          _walkSvgForImages(node);
        }
        if (startedHere && containerBoundStop) {
          _stopped = true;
        }
        return;
      }

      if (tag == 'img' && onImage != null) {
        if (_capturing) {
          final rawSrc = _extractHtmlImgSrc(node);
          if (rawSrc != null && rawSrc.isNotEmpty) {
            final alt = EpubXhtmlExtractor.normalizeInlineText(
              node.attributes['alt'] ?? '',
            );
            _emitImage(rawSrc, alt);
          }
        }
        if (isStart && containerBoundStop) {
          _stopped = true;
        }
        return;
      }

      if (_capturing && EpubXhtmlExtractor._breakTags.contains(tag)) {
        _flushLine();
        if (isStart && containerBoundStop) {
          _stopped = true;
        }
        return;
      }

      final isBlock = EpubXhtmlExtractor._blockTags.contains(tag);
      final isPre = tag == 'pre';
      if (_capturing && isBlock) {
        _flushLine();
      }
      if (isPre) {
        _preDepth++;
      }

      for (final child in node.nodes) {
        walk(child);
        if (_stopped) break;
      }

      if (isPre) {
        _preDepth--;
      }

      if (_stopped) return;

      if (_capturing) {
        if (isBlock) {
          _flushLine();
        } else if (EpubXhtmlExtractor._cellSeparatorTags.contains(tag) &&
            _currentLine.isNotEmpty) {
          _pendingSpace = true;
        }
      }
      if (startedHere && containerBoundStop) {
        _stopped = true;
      }
      return;
    }

    if (node is dom.Text && _capturing) {
      _appendText(node.data);
    }
  }

  void _walkSvgForImages(dom.Element svgParent) {
    if (_stopped) return;
    for (final child in svgParent.children) {
      if (_stopped) break;
      final tag = (child.localName ?? '').toLowerCase();
      if (EpubXhtmlExtractor._nonSvgIgnoredTags.contains(tag)) {
        continue;
      }
      if (stopIds.isNotEmpty &&
          EpubXhtmlExtractor._elementMatchesAnyId(child, stopIds)) {
        _flushLine();
        _stopped = true;
        return;
      }
      if (tag == 'image') {
        final rawSrc = _extractSvgImageSrc(child);
        if (rawSrc != null && rawSrc.isNotEmpty) {
          final alt = EpubXhtmlExtractor.normalizeInlineText(
            child.attributes['alt'] ??
                child.attributes['aria-label'] ??
                child.attributes['title'] ??
                '',
          );
          _emitImage(rawSrc, alt);
        }
        continue;
      }
      _walkSvgForImages(child);
    }
  }

  void _emitImage(String rawSrc, String alt) {
    final callback = onImage;
    if (callback == null) return;
    final marker = callback(rawSrc, alt);
    if (marker == null) return;
    final cleanMarker = marker.trim();
    if (cleanMarker.isEmpty) return;
    _flushLine();
    _lines.add(cleanMarker);
    _pendingSpace = false;
  }

  static String? _extractHtmlImgSrc(dom.Element el) {
    final src = el.attributes['src']?.trim() ?? '';
    final dataSrc = el.attributes['data-src']?.trim() ?? '';
    if (src.isNotEmpty) {
      if (src.toLowerCase().startsWith('data:') &&
          dataSrc.isNotEmpty &&
          !dataSrc.toLowerCase().startsWith('data:')) {
        return dataSrc;
      }
      return src;
    }
    return dataSrc.isEmpty ? null : dataSrc;
  }

  static String? _extractSvgImageSrc(dom.Element el) {
    String? hrefFallback;
    for (final entry in el.attributes.entries) {
      final key = entry.key.toString().toLowerCase();
      final val = entry.value.trim();
      if (val.isEmpty) continue;
      if (key == 'xlink:href') {
        return val;
      }
      if (key == 'href') {
        hrefFallback ??= val;
      }
    }
    return hrefFallback;
  }

  void _appendText(String raw) {
    if (raw.isEmpty) return;
    final cleaned = raw.replaceAll('\uFEFF', '');
    if (cleaned.isEmpty) return;

    if (_preDepth > 0) {
      final normalizedBreaks = cleaned
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      final parts = normalizedBreaks.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) {
          _flushLine();
        }
        final part = parts[i].replaceAll('\u00A0', ' ');
        if (part.isNotEmpty) {
          if (_pendingSpace && _currentLine.isNotEmpty) {
            _currentLine.write(' ');
          }
          _pendingSpace = false;
          _currentLine.write(part);
        }
      }
      return;
    }

    final collapsed = cleaned.replaceAll(
      EpubXhtmlExtractor._inlineWhitespaceRegex,
      ' ',
    );
    if (collapsed.isEmpty) return;

    if (collapsed == ' ') {
      if (_currentLine.isNotEmpty) {
        _pendingSpace = true;
      }
      return;
    }

    final startsWithSpace = collapsed.startsWith(' ');
    final endsWithSpace = collapsed.endsWith(' ');
    var start = 0;
    var end = collapsed.length;
    if (startsWithSpace) start++;
    if (endsWithSpace && end > start) end--;
    if (start >= end) {
      if (_currentLine.isNotEmpty) {
        _pendingSpace = true;
      }
      return;
    }

    final core = collapsed.substring(start, end);
    if (_currentLine.isNotEmpty && (_pendingSpace || startsWithSpace)) {
      _currentLine.write(' ');
    }
    _currentLine.write(core);
    _pendingSpace = endsWithSpace;
  }

  void _flushLine() {
    if (_currentLine.isNotEmpty) {
      final line = _currentLine.toString().trim();
      if (line.isNotEmpty) {
        _lines.add(line);
      }
      _currentLine.clear();
    }
    _pendingSpace = false;
  }

  String finish() {
    _flushLine();
    return _lines.join('\n');
  }
}
