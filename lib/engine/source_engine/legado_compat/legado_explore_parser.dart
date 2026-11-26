import '../../../domain/entities/explore_category.dart';
import 'legado_source.dart';

/// Parses Legado v3 `exploreUrl` definitions into structured [ExploreCategory]
/// entries across JSON arrays, `&&`/`\n`-delimited `Title::URL` text, group
/// headers, and bare discovery URLs.
class LegadoExploreParser {
  const LegadoExploreParser._();

  static final RegExp _urlOptionsSuffixPattern = RegExp(r',\s*\{[\s\S]*\}$');
  static final RegExp _webFileExtPattern = RegExp(
    r'\.(?:s?html?|xhtml|php\d*|aspx?|jsp|jspx|do|action|json|xml|cgi)(?:$|[?#])',
    caseSensitive: false,
  );
  static final RegExp _asciiPathPattern = RegExp(
    r"^[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+$",
  );

  /// Parses [raw] `exploreUrl` content into an unmodifiable list of
  /// [ExploreCategory] items.
  static List<ExploreCategory> parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const <ExploreCategory>[];

    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final decodedList = LegadoBookSource.tryParseLenientJsonList(trimmed);
      if (decodedList != null) {
        return _parseJsonArray(decodedList);
      }
    }

    final categories = <ExploreCategory>[];
    String? currentGroup;
    for (final rawEntry in _splitDelimitedEntries(raw)) {
      currentGroup = _appendTextEntry(rawEntry, currentGroup, categories);
    }
    return List<ExploreCategory>.unmodifiable(categories);
  }

  static List<ExploreCategory> _parseJsonArray(List<dynamic> jsonList) {
    final categories = <ExploreCategory>[];
    String? currentGroup;

    for (final entry in jsonList) {
      if (entry is String) {
        currentGroup = _appendTextEntry(entry, currentGroup, categories);
        continue;
      }
      if (entry is! Map) continue;

      final map = entry.map((k, v) => MapEntry(k.toString(), v));
      var title = (map['title']?.toString() ?? '').trim();
      final url = (map['url']?.toString() ?? '').trim();
      final flex = extractFlexBasisPercent(map);
      final explicitGroup = _nullableTrimmed(map['group']?.toString());

      if (title.isEmpty && url.isEmpty) {
        continue;
      }

      if (url.isEmpty) {
        currentGroup = title;
        categories.add(
          ExploreCategory(
            title: title,
            url: '',
            group: explicitGroup,
            layoutFlexBasisPercent: flex,
          ),
        );
      } else {
        if (title.isEmpty) {
          title = '发现';
        }
        categories.add(
          ExploreCategory(
            title: title,
            url: url,
            group: explicitGroup ?? currentGroup,
            layoutFlexBasisPercent: flex,
          ),
        );
      }
    }

    return List<ExploreCategory>.unmodifiable(categories);
  }

  static String? _appendTextEntry(
    String rawEntry,
    String? currentGroup,
    List<ExploreCategory> out,
  ) {
    final entry = rawEntry.trim();
    if (entry.isEmpty) return currentGroup;

    final sepIdx = _findTopLevelSeparator(entry);
    if (sepIdx != -1) {
      final rawTitle = entry.substring(0, sepIdx).trim();
      final url = entry.substring(sepIdx + 2).trim();
      if (!_startsWithHttpScheme(rawTitle)) {
        if (url.isEmpty) {
          if (rawTitle.isEmpty) return currentGroup;
          out.add(ExploreCategory(title: rawTitle, url: ''));
          return rawTitle;
        }
        out.add(
          ExploreCategory(
            title: rawTitle.isEmpty ? '发现' : rawTitle,
            url: url,
            group: currentGroup,
          ),
        );
        return currentGroup;
      }
    }

    if (_looksLikeUrl(entry)) {
      out.add(
        ExploreCategory(
          title: '发现',
          url: entry,
          group: currentGroup,
        ),
      );
      return currentGroup;
    }

    out.add(ExploreCategory(title: entry, url: ''));
    return entry;
  }

  static List<String> _splitDelimitedEntries(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final entries = <String>[];
    var start = 0;

    _scanTopLevel(
      normalized,
      onUnclosedNewline: (i) {
        entries.add(normalized.substring(start, i));
        start = i + 1;
      },
      onTopLevel: (i) {
        if (normalized[i] == '\n') {
          entries.add(normalized.substring(start, i));
          start = i + 1;
          return 0;
        }
        if (normalized.startsWith('&&', i)) {
          entries.add(normalized.substring(start, i));
          start = i + 2;
          return 1;
        }
        return 0;
      },
    );

    entries.add(normalized.substring(start));
    return entries;
  }

  static int _findTopLevelSeparator(String entry) {
    var sepIdx = -1;
    _scanTopLevel(
      entry,
      onTopLevel: (i) {
        if (i + 1 < entry.length && entry[i] == ':' && entry[i + 1] == ':') {
          sepIdx = i;
          return -1;
        }
        return 0;
      },
    );
    return sepIdx;
  }

  /// Scans [text] while respecting `<js>...</js>` tags, single/double quotes,
  /// braces, and brackets, invoking [onTopLevel] at each top-level character.
  ///
  /// [onTopLevel] returns `-1` to stop scanning immediately, or `>= 0` for the
  /// number of extra characters to skip past the current index.
  static void _scanTopLevel(
    String text, {
    required int Function(int index) onTopLevel,
    void Function(int index)? onUnclosedNewline,
  }) {
    var inSingle = false;
    var inDouble = false;
    var braceDepth = 0;
    var bracketDepth = 0;
    var inJsTag = false;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];

      if (!inSingle && !inDouble) {
        if (!inJsTag && _matchesTagAt(text, i, '<js>')) {
          inJsTag = true;
          i += 3;
          continue;
        }
        if (inJsTag && _matchesTagAt(text, i, '</js>')) {
          inJsTag = false;
          i += 4;
          continue;
        }
      }
      if (inJsTag) continue;

      if (inSingle || inDouble) {
        if (ch == r'\' && i + 1 < text.length) {
          i++;
          continue;
        }
        if (inSingle && ch == "'") {
          inSingle = false;
        } else if (inDouble && ch == '"') {
          inDouble = false;
        } else if (ch == '\n' &&
            braceDepth == 0 &&
            bracketDepth == 0 &&
            onUnclosedNewline != null) {
          inSingle = false;
          inDouble = false;
          onUnclosedNewline(i);
        }
        continue;
      }

      if (ch == "'" &&
          (braceDepth > 0 ||
              bracketDepth > 0 ||
              _hasClosingQuoteOnLine(text, i + 1, "'"))) {
        inSingle = true;
      } else if (ch == '"' &&
          (braceDepth > 0 ||
              bracketDepth > 0 ||
              _hasClosingQuoteOnLine(text, i + 1, '"'))) {
        inDouble = true;
      } else if (ch == '{') {
        braceDepth++;
      } else if (ch == '}' && braceDepth > 0) {
        braceDepth--;
      } else if (ch == '[') {
        bracketDepth++;
      } else if (ch == ']' && bracketDepth > 0) {
        bracketDepth--;
      } else if (braceDepth == 0 && bracketDepth == 0) {
        final advance = onTopLevel(i);
        if (advance < 0) return;
        i += advance;
      }
    }
  }

  static bool _matchesTagAt(String text, int index, String tag) {
    if (index + tag.length > text.length) return false;
    return text.substring(index, index + tag.length).toLowerCase() == tag;
  }

  static bool _hasClosingQuoteOnLine(String text, int start, String quote) {
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (ch == '\n') return false;
      if (ch == r'\' && i + 1 < text.length) {
        i++;
        continue;
      }
      if (ch == quote) return true;
    }
    return false;
  }

  static bool _startsWithHttpScheme(String text) {
    final lower = text.trimLeft().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static bool _looksLikeUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        trimmed.startsWith('//') ||
        trimmed.startsWith('/') ||
        trimmed.startsWith('./') ||
        trimmed.startsWith('../') ||
        trimmed.startsWith('?')) {
      return true;
    }
    if (_urlOptionsSuffixPattern.hasMatch(trimmed)) {
      return true;
    }
    if ((trimmed.contains('{{') && trimmed.contains('}}')) ||
        lower.contains('<js>') ||
        lower.startsWith('@js:')) {
      return true;
    }
    if (!RegExp(r'\s').hasMatch(trimmed)) {
      if (trimmed.contains('?') && trimmed.contains('=')) {
        return true;
      }
      if (_webFileExtPattern.hasMatch(trimmed)) {
        return true;
      }
      if (trimmed.contains('/') && _asciiPathPattern.hasMatch(trimmed)) {
        return true;
      }
    }
    return false;
  }

  /// Extracts `layout_flexBasisPercent` / `layoutFlexBasisPercent` from a
  /// category JSON object or its nested `style` object.
  static double? extractFlexBasisPercent(Map<String, dynamic> map) {
    final rawStyle = map['style'];
    Map<String, dynamic>? styleMap;
    if (rawStyle is Map) {
      styleMap = rawStyle.map((k, v) => MapEntry(k.toString(), v));
    } else if (rawStyle is String && rawStyle.trim().startsWith('{')) {
      styleMap = LegadoBookSource.tryParseLenientJsonMap(rawStyle);
    }

    final rawValue =
        map['layoutFlexBasisPercent'] ??
        map['layout_flexBasisPercent'] ??
        styleMap?['layout_flexBasisPercent'] ??
        styleMap?['layoutFlexBasisPercent'];
    return _parseFiniteDouble(rawValue);
  }

  static double? _parseFiniteDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final val = raw.toDouble();
      return val.isFinite ? val : null;
    }
    if (raw is String) {
      final parsed = double.tryParse(raw.trim());
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  static String? _nullableTrimmed(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
