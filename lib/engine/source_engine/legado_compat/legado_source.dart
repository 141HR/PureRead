import 'dart:convert';
import 'dart:isolate';

import '../../../domain/entities/book_source.dart';
import '../../../domain/failures/app_failure.dart';
import '../../../infrastructure/network/source_http_client.dart';
import '../parsing/pure_md5.dart';

/// Compatibility classification for a parsed Legado v3 source definition.
enum LegadoCompatibilityStatus {
  supported,
  unsupportedType,
  malformedBaseUrl,
  unsupportedWebView,
  unsupportedRhino,
}

/// Legado `ruleSearch` rule subset.
class LegadoSearchRule {
  final String bookList;
  final String name;
  final String author;
  final String bookUrl;
  final String coverUrl;
  final String intro;
  final String lastChapter;
  final String kind;
  final String wordCount;
  final String checkKeyWord;
  final bool webView;

  const LegadoSearchRule({
    this.bookList = '',
    this.name = '',
    this.author = '',
    this.bookUrl = '',
    this.coverUrl = '',
    this.intro = '',
    this.lastChapter = '',
    this.kind = '',
    this.wordCount = '',
    this.checkKeyWord = '',
    this.webView = false,
  });

  factory LegadoSearchRule.fromJson(Map<String, dynamic> json) {
    return LegadoSearchRule(
      bookList: (json['bookList'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      bookUrl: (json['bookUrl'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      intro: (json['intro'] ?? '').toString(),
      lastChapter: (json['lastChapter'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      wordCount: (json['wordCount'] ?? '').toString(),
      checkKeyWord: (json['checkKeyWord'] ?? '').toString(),
      webView: json['webView'] == true,
    );
  }
}

/// Legado `ruleExplore` rule subset.
class LegadoExploreRule {
  final String bookList;
  final String name;
  final String author;
  final String bookUrl;
  final String coverUrl;
  final String intro;
  final String lastChapter;
  final String kind;
  final String wordCount;
  final bool webView;

  const LegadoExploreRule({
    this.bookList = '',
    this.name = '',
    this.author = '',
    this.bookUrl = '',
    this.coverUrl = '',
    this.intro = '',
    this.lastChapter = '',
    this.kind = '',
    this.wordCount = '',
    this.webView = false,
  });

  factory LegadoExploreRule.fromJson(Map<String, dynamic> json) {
    return LegadoExploreRule(
      bookList: (json['bookList'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      bookUrl: (json['bookUrl'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      intro: (json['intro'] ?? '').toString(),
      lastChapter: (json['lastChapter'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      wordCount: (json['wordCount'] ?? '').toString(),
      webView: json['webView'] == true,
    );
  }

  bool get isEmpty =>
      bookList.trim().isEmpty &&
      name.trim().isEmpty &&
      author.trim().isEmpty &&
      bookUrl.trim().isEmpty &&
      coverUrl.trim().isEmpty &&
      intro.trim().isEmpty &&
      lastChapter.trim().isEmpty &&
      kind.trim().isEmpty &&
      wordCount.trim().isEmpty &&
      !webView;
}

/// Legado `ruleBookInfo` rule subset.
class LegadoBookInfoRule {
  final String init;
  final String name;
  final String author;
  final String intro;
  final String coverUrl;
  final String tocUrl;
  final String lastChapter;
  final String kind;
  final String wordCount;
  final String canReName;
  final bool webView;

  const LegadoBookInfoRule({
    this.init = '',
    this.name = '',
    this.author = '',
    this.intro = '',
    this.coverUrl = '',
    this.tocUrl = '',
    this.lastChapter = '',
    this.kind = '',
    this.wordCount = '',
    this.canReName = '',
    this.webView = false,
  });

  factory LegadoBookInfoRule.fromJson(Map<String, dynamic> json) {
    return LegadoBookInfoRule(
      init: (json['init'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      intro: (json['intro'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      tocUrl: (json['tocUrl'] ?? '').toString(),
      lastChapter: (json['lastChapter'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      wordCount: (json['wordCount'] ?? '').toString(),
      canReName: (json['canReName'] ?? '').toString(),
      webView: json['webView'] == true,
    );
  }
}

/// Legado `ruleToc` rule subset.
class LegadoTocRule {
  final String chapterList;
  final String chapterName;
  final String chapterUrl;
  final String nextTocUrl;
  final String isVip;
  final String isPay;
  final String updateTime;
  final String preUpdateJs;
  final bool webView;

  const LegadoTocRule({
    this.chapterList = '',
    this.chapterName = '',
    this.chapterUrl = '',
    this.nextTocUrl = '',
    this.isVip = '',
    this.isPay = '',
    this.updateTime = '',
    this.preUpdateJs = '',
    this.webView = false,
  });

  factory LegadoTocRule.fromJson(Map<String, dynamic> json) {
    return LegadoTocRule(
      chapterList: (json['chapterList'] ?? '').toString(),
      chapterName: (json['chapterName'] ?? '').toString(),
      chapterUrl: (json['chapterUrl'] ?? '').toString(),
      nextTocUrl: (json['nextTocUrl'] ?? '').toString(),
      isVip: (json['isVip'] ?? '').toString(),
      isPay: (json['isPay'] ?? '').toString(),
      updateTime: (json['updateTime'] ?? '').toString(),
      preUpdateJs: (json['preUpdateJs'] ?? '').toString(),
      webView: json['webView'] == true,
    );
  }
}

/// Legado `ruleContent` rule subset.
class LegadoContentRule {
  final String content;
  final String nextContentUrl;
  final String replaceRegex;
  final String sourceRegex;
  final String webJs;
  final bool webView;

  const LegadoContentRule({
    this.content = '',
    this.nextContentUrl = '',
    this.replaceRegex = '',
    this.sourceRegex = '',
    this.webJs = '',
    this.webView = false,
  });

  factory LegadoContentRule.fromJson(Map<String, dynamic> json) {
    return LegadoContentRule(
      content: (json['content'] ?? '').toString(),
      nextContentUrl: (json['nextContentUrl'] ?? '').toString(),
      replaceRegex: (json['replaceRegex'] ?? '').toString(),
      sourceRegex: (json['sourceRegex'] ?? '').toString(),
      webJs: (json['webJs'] ?? '').toString(),
      webView: json['webView'] == true,
    );
  }
}

/// Typed representation of a Legado v3 JSON book source.
class LegadoBookSource {
  final String bookSourceName;
  final String bookSourceUrl;
  final String normalizedBaseUrl;
  final bool hasFragmentTag;
  final String bookSourceGroup;
  final int bookSourceType;
  final String bookSourceComment;
  final bool enabled;
  final bool enabledExplore;
  final int weight;
  final int rateLimitMs;
  final String? searchUrl;
  final String? exploreUrl;
  final String? loginUrl;
  final String? jsLib;
  final String? rawHeader;
  final Map<String, String> headers;
  final String? charset;
  final bool webView;
  final LegadoSearchRule ruleSearch;
  final LegadoExploreRule ruleExplore;
  final LegadoBookInfoRule ruleBookInfo;
  final LegadoTocRule ruleToc;
  final LegadoContentRule ruleContent;
  final String rawJson;

  const LegadoBookSource({
    required this.bookSourceName,
    required this.bookSourceUrl,
    this.normalizedBaseUrl = '',
    this.hasFragmentTag = false,
    this.bookSourceGroup = '默认',
    this.bookSourceType = 0,
    this.bookSourceComment = '',
    this.enabled = true,
    this.enabledExplore = true,
    this.weight = 0,
    this.rateLimitMs = 500,
    this.searchUrl,
    this.exploreUrl,
    this.loginUrl,
    this.jsLib,
    this.rawHeader,
    this.headers = const <String, String>{},
    this.charset,
    this.webView = false,
    required this.ruleSearch,
    this.ruleExplore = const LegadoExploreRule(),
    required this.ruleBookInfo,
    required this.ruleToc,
    required this.ruleContent,
    this.rawJson = '',
  });

  /// Effective base URL with any `#fragment` tag stripped for HTTP resolution.
  String get effectiveBaseUrl =>
      normalizedBaseUrl.isNotEmpty ? normalizedBaseUrl : bookSourceUrl;

  /// Whether online discovery/explore is enabled and configured.
  bool get hasExplore =>
      enabledExplore && (exploreUrl?.trim().isNotEmpty ?? false);

  factory LegadoBookSource.fromJsonString(String rawJson) {
    final decoded = jsonDecode(_stripBom(rawJson).trim());
    if (decoded is! Map) {
      throw const FormatException('Legado source JSON must be an object');
    }
    return LegadoBookSource.fromJson(
      decoded.map((k, v) => MapEntry(k.toString(), v)),
      rawJsonOverride: rawJson,
    );
  }

  factory LegadoBookSource.fromJson(
    Map<String, dynamic> json, {
    String? rawJsonOverride,
  }) {
    final rawUrl = (json['bookSourceUrl'] ?? '').toString().trim();
    final normalizedUri = SourceHttpClient.tryNormalizeHttpUri(rawUrl);
    final normalizedBaseUrl = normalizedUri?.toString() ?? '';
    final hasFragmentTag = rawUrl.contains('#');
    final rawGroup = (json['bookSourceGroup'] ?? '').toString().trim();
    final rawType = json['bookSourceType'];
    final sourceType = rawType is int
        ? rawType
        : int.tryParse(rawType?.toString() ?? '') ?? 0;

    final rawHeader = json['header'] is Map
        ? jsonEncode(json['header'])
        : json['header']?.toString();
    final rawExploreUrl = json['exploreUrl'] is List || json['exploreUrl'] is Map
        ? jsonEncode(json['exploreUrl'])
        : json['exploreUrl']?.toString();

    return LegadoBookSource(
      bookSourceName:
          (json['bookSourceName'] ?? 'Unnamed Legado Source').toString().trim(),
      bookSourceUrl: rawUrl,
      normalizedBaseUrl: normalizedBaseUrl,
      hasFragmentTag: hasFragmentTag,
      bookSourceGroup: rawGroup.isEmpty ? '默认' : rawGroup,
      bookSourceType: sourceType,
      bookSourceComment: (json['bookSourceComment'] ?? '').toString(),
      enabled: json['enabled'] is bool
          ? json['enabled'] as bool
          : json['enabled']?.toString().toLowerCase() != 'false',
      enabledExplore: json['enabledExplore'] is bool
          ? json['enabledExplore'] as bool
          : json['enabledExplore']?.toString().toLowerCase() != 'false',
      weight: json['weight'] is int
          ? json['weight'] as int
          : int.tryParse(json['weight']?.toString() ?? '') ?? 0,
      rateLimitMs: parseConcurrentRateMs(json['concurrentRate']),
      searchUrl: _normalizeOptional(json['searchUrl']),
      exploreUrl: _normalizeOptional(rawExploreUrl),
      loginUrl: _normalizeOptional(json['loginUrl']),
      jsLib: _normalizeOptional(json['jsLib']),
      rawHeader: _normalizeOptional(rawHeader),
      headers: parseStaticHeaderField(json['header']),
      charset: _normalizeOptional(json['charset']),
      webView: json['webView'] == true,
      ruleSearch: LegadoSearchRule.fromJson(_asMap(json['ruleSearch'])),
      ruleExplore: LegadoExploreRule.fromJson(_asMap(json['ruleExplore'])),
      ruleBookInfo: LegadoBookInfoRule.fromJson(_asMap(json['ruleBookInfo'])),
      ruleToc: LegadoTocRule.fromJson(_asMap(json['ruleToc'])),
      ruleContent: LegadoContentRule.fromJson(_asMap(json['ruleContent'])),
      rawJson: rawJsonOverride ?? jsonEncode(json),
    );
  }

  /// Parses Legado `concurrentRate` strings (`"500"`, `"1/1000"`, `"2/1000"`)
  /// into a minimum inter-request delay in milliseconds.
  static int parseConcurrentRateMs(dynamic raw, {int defaultRateMs = 500}) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return defaultRateMs;
    if (text.contains('/')) {
      final parts = text.split('/');
      if (parts.length == 2) {
        final count = int.tryParse(parts[0].trim());
        final windowMs = int.tryParse(parts[1].trim());
        if (count != null && count > 0 && windowMs != null && windowMs >= 0) {
          return (windowMs / count).ceil();
        }
      }
    }
    final direct = int.tryParse(text);
    if (direct != null && direct >= 0) {
      return direct;
    }
    return defaultRateMs;
  }

  /// Parses static `header` definitions safely across Map, strict JSON, lenient
  /// single-quoted/unquoted JSON, `Key: Value` lines, and bare User-Agent
  /// strings. Dynamic `<js>`/`@js:` headers return `{}` here and are evaluated
  /// at request time.
  static Map<String, String> parseStaticHeaderField(dynamic raw) {
    if (raw == null) return const <String, String>{};
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const <String, String>{};
      if (trimmed.contains('<js>') || trimmed.toLowerCase().startsWith('@js:')) {
        return const <String, String>{};
      }
      final parsedMap = tryParseLenientJsonMap(trimmed);
      if (parsedMap != null) {
        return parsedMap.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      }
      if (trimmed.contains(':')) {
        final headers = <String, String>{};
        for (final line in trimmed.split('\n')) {
          final idx = line.indexOf(':');
          if (idx <= 0) continue;
          final key = line.substring(0, idx).trim();
          final val = line.substring(idx + 1).trim();
          if (RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(key) && val.isNotEmpty) {
            headers[key] = val;
          }
        }
        if (headers.isNotEmpty) return headers;
      }
      if (trimmed.startsWith('Mozilla/') || trimmed.contains('AppleWebKit')) {
        return <String, String>{'User-Agent': trimmed};
      }
    }
    return const <String, String>{};
  }

  /// Parses strict JSON objects and lenient JS-object literals (single quotes,
  /// unquoted keys, trailing commas) without invoking JS.
  static Map<String, dynamic>? tryParseLenientJsonMap(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } on FormatException {
      // Fall through to lenient normalizer.
    }

    final normalized = _normalizeLenientJson(trimmed);
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Parses strict JSON arrays and lenient JS-array literals (single quotes,
  /// unquoted keys, trailing commas) without invoking JS.
  static List<dynamic>? tryParseLenientJsonList(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List<dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Fall through to lenient normalizer.
    }

    final normalized = _normalizeLenientJson(trimmed);
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is List<dynamic>) {
        return decoded;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String _normalizeLenientJson(String input) {
    final out = StringBuffer();
    var i = 0;
    var inDouble = false;
    var inSingle = false;

    while (i < input.length) {
      final ch = input[i];
      if (inDouble) {
        out.write(ch);
        if (ch == r'\' && i + 1 < input.length) {
          i++;
          out.write(input[i]);
        } else if (ch == '"') {
          inDouble = false;
        }
        i++;
        continue;
      }
      if (inSingle) {
        if (ch == r'\' && i + 1 < input.length) {
          final next = input[i + 1];
          if (next == "'") {
            out.write("'");
          } else {
            out.write(ch);
            out.write(next);
          }
          i += 2;
          continue;
        }
        if (ch == "'") {
          out.write('"');
          inSingle = false;
        } else if (ch == '"') {
          out.write(r'\"');
        } else if (ch == '\n') {
          out.write(r'\n');
        } else if (ch == '\r') {
          out.write(r'\r');
        } else {
          out.write(ch);
        }
        i++;
        continue;
      }

      if (ch == '"') {
        inDouble = true;
        out.write(ch);
        i++;
      } else if (ch == "'") {
        inSingle = true;
        out.write('"');
        i++;
      } else if (ch == ',' && _isTrailingComma(input, i + 1)) {
        i++;
      } else if (_isIdentStart(ch) && _looksLikeObjectKey(input, i)) {
        final start = i;
        while (i < input.length && _isIdentPart(input[i])) {
          i++;
        }
        final ident = input.substring(start, i);
        if (ident == 'true' || ident == 'false' || ident == 'null') {
          out.write(ident);
        } else {
          out.write('"$ident"');
        }
      } else {
        out.write(ch);
        i++;
      }
    }
    return out.toString();
  }

  static bool _isTrailingComma(String input, int start) {
    for (var i = start; i < input.length; i++) {
      final c = input[i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
      return c == '}' || c == ']';
    }
    return false;
  }

  static bool _looksLikeObjectKey(String input, int start) {
    var prev = start - 1;
    while (prev >= 0 &&
        (input[prev] == ' ' ||
            input[prev] == '\t' ||
            input[prev] == '\n' ||
            input[prev] == '\r')) {
      prev--;
    }
    if (prev < 0 || (input[prev] != '{' && input[prev] != ',')) {
      return false;
    }
    var end = start;
    while (end < input.length && _isIdentPart(input[end])) {
      end++;
    }
    while (end < input.length &&
        (input[end] == ' ' ||
            input[end] == '\t' ||
            input[end] == '\n' ||
            input[end] == '\r')) {
      end++;
    }
    return end < input.length && input[end] == ':';
  }

  static bool _isIdentStart(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F ||
        code == 0x24;
  }

  static bool _isIdentPart(String ch) {
    final code = ch.codeUnitAt(0);
    return _isIdentStart(ch) || (code >= 0x30 && code <= 0x39);
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }

  static String? _normalizeOptional(dynamic raw) {
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static String _stripBom(String raw) {
    if (raw.isNotEmpty && raw.codeUnitAt(0) == 0xFEFF) {
      return raw.substring(1);
    }
    return raw;
  }
}

/// Parsed Legado source paired with its domain [BookSource] entity and
/// compatibility classification.
class LegadoParsedSource {
  final LegadoBookSource legado;
  final BookSource domainSource;
  final LegadoCompatibilityStatus compatibility;
  final List<String> unsupportedReasons;
  final Set<String> detectedFeatures;

  const LegadoParsedSource({
    required this.legado,
    required this.domainSource,
    required this.compatibility,
    this.unsupportedReasons = const <String>[],
    this.detectedFeatures = const <String>{},
  });

  bool get isSupported => compatibility == LegadoCompatibilityStatus.supported;
}

/// Result of batch-parsing a Legado JSON object or array.
class LegadoBatchParseResult {
  final List<LegadoParsedSource> items;
  final List<String> parseErrors;
  final int elapsedMs;

  const LegadoBatchParseResult({
    required this.items,
    this.parseErrors = const <String>[],
    this.elapsedMs = 0,
  });

  int get totalCount => items.length;
  int get supportedCount =>
      items.where((i) => i.compatibility == LegadoCompatibilityStatus.supported).length;
  int get unsupportedTypeCount => items
      .where((i) => i.compatibility == LegadoCompatibilityStatus.unsupportedType)
      .length;
  int get malformedBaseUrlCount => items
      .where(
        (i) => i.compatibility == LegadoCompatibilityStatus.malformedBaseUrl,
      )
      .length;
  int get unsupportedWebViewCount => items
      .where(
        (i) => i.compatibility == LegadoCompatibilityStatus.unsupportedWebView,
      )
      .length;
  int get unsupportedRhinoCount => items
      .where(
        (i) => i.compatibility == LegadoCompatibilityStatus.unsupportedRhino,
      )
      .length;
  int get fragmentTaggedCount =>
      items.where((i) => i.legado.hasFragmentTag).length;
}

/// Isolate-friendly batch parser and compatibility classifier for Legado JSON
/// book sources (single objects or 1,000+ element arrays).
class LegadoSourceParser {
  const LegadoSourceParser._();

  static const int defaultIsolateThresholdBytes = 256 * 1024;

  /// Parses a Legado JSON string (object or array), offloading large payloads
  /// to a background `Isolate` when [useIsolate] is `true`.
  static Future<LegadoBatchParseResult> parseBatch(
    String rawJson, {
    bool useIsolate = true,
    int isolateThresholdBytes = defaultIsolateThresholdBytes,
    DateTime? timestamp,
  }) async {
    final ts = (timestamp ?? DateTime.now()).toUtc();
    if (useIsolate && rawJson.length >= isolateThresholdBytes) {
      return Isolate.run(() => parseBatchSync(rawJson, timestamp: ts));
    }
    return parseBatchSync(rawJson, timestamp: ts);
  }

  /// Synchronous batch parser safe to run directly inside an Isolate or test.
  static LegadoBatchParseResult parseBatchSync(
    String rawJson, {
    DateTime? timestamp,
  }) {
    final sw = Stopwatch()..start();
    final now = (timestamp ?? DateTime.now()).toUtc();
    final cleaned = LegadoBookSource._stripBom(rawJson).trim();
    if (cleaned.isEmpty) {
      throw const SourceParseFailure(
        message: 'Legado JSON input is empty',
        step: 'import',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException catch (e, st) {
      throw SourceParseFailure(
        message: 'Invalid Legado JSON syntax: ${e.message}',
        step: 'import',
        cause: e,
        stackTrace: st,
      );
    }

    final List<dynamic> entries;
    if (decoded is List<dynamic>) {
      entries = decoded;
    } else if (decoded is Map) {
      entries = <dynamic>[decoded];
    } else {
      throw SourceParseFailure(
        message: 'Legado JSON must be an object or array, got ${decoded.runtimeType}',
        step: 'import',
      );
    }

    final parsedItems = <LegadoParsedSource>[];
    final errors = <String>[];
    final seenIds = <String, int>{};

    for (var i = 0; i < entries.length; i++) {
      final rawEntry = entries[i];
      if (rawEntry is! Map) {
        errors.add('Entry #$i is not a JSON object (${rawEntry.runtimeType})');
        continue;
      }

      try {
        final jsonMap = rawEntry.map((k, v) => MapEntry(k.toString(), v));
        final rawItemJson = jsonEncode(jsonMap);
        final legado = LegadoBookSource.fromJson(
          jsonMap,
          rawJsonOverride: rawItemJson,
        );
        final classification = classifySource(legado, rawItemJson);

        final idSeed =
            '${legado.effectiveBaseUrl}|${legado.bookSourceName}|${legado.bookSourceType}';
        final baseId = 'legado_${PureMd5.digest16Hex(idSeed)}';
        final dupCount = seenIds[baseId] ?? 0;
        seenIds[baseId] = dupCount + 1;
        final id = dupCount == 0 ? baseId : '${baseId}_$dupCount';

        final checkStatus = switch (classification.compatibility) {
          LegadoCompatibilityStatus.supported => SourceCheckStatus.unknown,
          LegadoCompatibilityStatus.unsupportedType ||
          LegadoCompatibilityStatus.unsupportedWebView ||
          LegadoCompatibilityStatus.unsupportedRhino =>
            SourceCheckStatus.unsupported,
          LegadoCompatibilityStatus.malformedBaseUrl => SourceCheckStatus.error,
        };

        final domainSource = BookSource(
          id: id,
          name: legado.bookSourceName.isEmpty
              ? '未命名书源 #$i'
              : legado.bookSourceName,
          groupName: legado.bookSourceGroup,
          engineType: SourceEngineType.legado,
          baseUrl: legado.bookSourceUrl,
          rawDefinition: rawItemJson,
          enabled: legado.enabled,
          weight: legado.weight,
          rateLimitMs: legado.rateLimitMs,
          lastCheckStatus: checkStatus,
          lastErrorSummary: classification.unsupportedReasons.isEmpty
              ? null
              : classification.unsupportedReasons.join('; '),
          createdAt: now,
          updatedAt: now,
        );

        parsedItems.add(
          LegadoParsedSource(
            legado: legado,
            domainSource: domainSource,
            compatibility: classification.compatibility,
            unsupportedReasons: classification.unsupportedReasons,
            detectedFeatures: classification.features,
          ),
        );
      } catch (e) {
        errors.add('Entry #$i failed to parse: $e');
      }
    }

    sw.stop();
    return LegadoBatchParseResult(
      items: List<LegadoParsedSource>.unmodifiable(parsedItems),
      parseErrors: List<String>.unmodifiable(errors),
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  static final RegExp _nonJsoupPackagesPattern = RegExp(
    r'Packages\.(?!org\.jsoup\b)',
  );
  static final RegExp _rhinoJavaPackagePattern = RegExp(
    r'\bjava\.(?:lang|net|io|util)\.',
  );
  static final RegExp _nonJsoupImportClassPattern = RegExp(
    r'importClass\(\s*(?!(?:Packages\.)?org\.jsoup\.)',
  );
  static final RegExp _symmetricCryptoPattern = RegExp(
    r'(?:createSymmetricCrypto|\b(?:aes|des)(?:Base64|Encode|Decode|Encrypt|Decrypt)|CryptoJS\.(?:AES|DES)|(?:AES|DES)/)',
    caseSensitive: false,
  );
  static final RegExp _digestHmacPattern = RegExp(
    r'\b(?:digestHex|digestBase64|createDigest|createHMac|HMacHex|HMacBase64|sha1Encode|sha256Encode|sha512Encode|hexEncodeToString)\b',
    caseSensitive: false,
  );
  static final RegExp _bookVariablePattern = RegExp(
    r'\bbook\.(?:getVariable|putVariable|variable|getCustomVariable|putCustomVariable)\b',
  );

  /// Returns `true` when [text] references Rhino/Java APIs outside the
  /// supported `org.jsoup.*` DOM bridge (`Packages.<non-jsoup>`, `java.lang.*`,
  /// `java.net.*`, `java.io.*`, `java.util.*`, or non-Jsoup `importClass(...)`).
  static bool hasUnsupportedRhinoApi(String text) {
    return _nonJsoupPackagesPattern.hasMatch(text) ||
        _rhinoJavaPackagePattern.hasMatch(text) ||
        _nonJsoupImportClassPattern.hasMatch(text);
  }

  /// Classifies a [LegadoBookSource] and collects its detected DSL features.
  static ({
    LegadoCompatibilityStatus compatibility,
    List<String> unsupportedReasons,
    Set<String> features,
  }) classifySource(LegadoBookSource legado, [String? rawBlob]) {
    final blob = rawBlob ?? legado.rawJson;
    final features = _detectFeatures(legado, blob);
    final reasons = <String>[];

    if (legado.bookSourceType != 0) {
      final typeLabel = switch (legado.bookSourceType) {
        1 => 'audio',
        2 => 'image/manga',
        3 => 'file',
        _ => 'type=${legado.bookSourceType}',
      };
      reasons.add('bookSourceType=$typeLabel (only text type 0 supported)');
      return (
        compatibility: LegadoCompatibilityStatus.unsupportedType,
        unsupportedReasons: reasons,
        features: features,
      );
    }

    if (legado.normalizedBaseUrl.isEmpty) {
      reasons.add('malformed or non-HTTP bookSourceUrl: "${legado.bookSourceUrl}"');
      return (
        compatibility: LegadoCompatibilityStatus.malformedBaseUrl,
        unsupportedReasons: reasons,
        features: features,
      );
    }

    final hasStepWebView = legado.webView ||
        legado.ruleSearch.webView ||
        legado.ruleBookInfo.webView ||
        legado.ruleToc.webView ||
        legado.ruleContent.webView ||
        (legado.searchUrl?.contains('"webView":true') ?? false) ||
        (legado.searchUrl?.contains("'webView':true") ?? false);
    final hasBrowserApi = blob.contains('startBrowserAwait') ||
        RegExp(r'\bjava\.webView\b(?!UA)').hasMatch(blob);

    if (hasStepWebView || hasBrowserApi) {
      if (hasStepWebView) reasons.add('webView: true');
      if (hasBrowserApi) reasons.add('java.startBrowserAwait / java.webView');
      return (
        compatibility: LegadoCompatibilityStatus.unsupportedWebView,
        unsupportedReasons: reasons,
        features: features,
      );
    }

    if (hasUnsupportedRhinoApi(blob)) {
      reasons.add(
        'Rhino Java API (non-Jsoup Packages.*/java.lang/net/io/util)',
      );
      return (
        compatibility: LegadoCompatibilityStatus.unsupportedRhino,
        unsupportedReasons: reasons,
        features: features,
      );
    }

    return (
      compatibility: LegadoCompatibilityStatus.supported,
      unsupportedReasons: const <String>[],
      features: features,
    );
  }

  static Set<String> _detectFeatures(LegadoBookSource s, String blob) {
    final f = <String>{};
    if ((s.searchUrl ?? '').isNotEmpty) f.add('searchUrl');
    if ((s.exploreUrl ?? '').isNotEmpty) f.add('exploreUrl');
    if ((s.loginUrl ?? '').isNotEmpty) f.add('loginUrl');
    if (s.hasFragmentTag) f.add('fragmentUrl');
    if ((s.charset ?? '').toLowerCase().contains('gb') ||
        blob.toLowerCase().contains('gbk') ||
        blob.toLowerCase().contains('gb2312') ||
        blob.toLowerCase().contains('gb18030')) {
      f.add('gbkCharset');
    }
    if (blob.contains('POST') || blob.contains('post')) f.add('post');
    if (s.rawHeader != null) f.add('header');
    if (blob.contains('{{') && blob.contains('}}')) f.add('templateMustache');
    if (blob.contains('##')) f.add('regexReplace');
    if (s.ruleContent.replaceRegex.trim().isNotEmpty) f.add('replaceRegex');
    if (s.ruleToc.nextTocUrl.trim().isNotEmpty) f.add('nextTocUrl');
    if (s.ruleContent.nextContentUrl.trim().isNotEmpty) f.add('nextContentUrl');
    if (blob.contains('<js>') || blob.contains('@js:')) f.add('embeddedJs');
    if (blob.contains('@XPath:') ||
        blob.contains('@xpath:') ||
        blob.contains('"//')) {
      f.add('xpath');
    }
    if (blob.contains(r'$.') || blob.toLowerCase().contains('@json:')) {
      f.add('jsonPath');
    }
    if (blob.toLowerCase().contains('@css:')) f.add('cssPrefix');
    if (blob.contains('&&') || blob.contains('||') || blob.contains('%%')) {
      f.add('combinators');
    }
    if (blob.contains('class.') ||
        blob.contains('id.') ||
        blob.contains('tag.') ||
        blob.contains('text.') ||
        blob.contains('children') ||
        blob.contains('!')) {
      f.add('legadoDefaultChain');
    }
    if (_hasColonRegexRule(s)) f.add('colonRegex');
    if (_symmetricCryptoPattern.hasMatch(blob)) f.add('symmetricCrypto');
    if (blob.contains('org.jsoup.')) f.add('jsoup');
    if (blob.contains('ajaxAll')) f.add('ajaxAll');
    if (_digestHmacPattern.hasMatch(blob)) f.add('digestHmac');
    if (_bookVariablePattern.hasMatch(blob)) f.add('bookVariable');
    if (s.ruleSearch.checkKeyWord.trim().isNotEmpty) f.add('checkKeyWord');
    if (s.ruleToc.preUpdateJs.trim().isNotEmpty) f.add('preUpdateJs');
    return f;
  }

  static bool _hasColonRegexRule(LegadoBookSource s) {
    final fields = <String>[
      s.ruleSearch.bookList,
      s.ruleSearch.name,
      s.ruleSearch.author,
      s.ruleSearch.bookUrl,
      s.ruleExplore.bookList,
      s.ruleExplore.name,
      s.ruleExplore.author,
      s.ruleExplore.bookUrl,
      s.ruleExplore.coverUrl,
      s.ruleExplore.intro,
      s.ruleExplore.lastChapter,
      s.ruleExplore.kind,
      s.ruleBookInfo.init,
      s.ruleBookInfo.name,
      s.ruleToc.chapterList,
      s.ruleToc.chapterName,
      s.ruleToc.chapterUrl,
      s.ruleContent.content,
    ];
    for (final raw in fields) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (t.toLowerCase().contains('@regex:')) return true;
      for (final part in t.split(RegExp(r'\n|\&\&|\|\||%%'))) {
        final p = part.trim();
        if (p.startsWith(':') && !p.startsWith('::')) return true;
      }
    }
    return false;
  }
}
