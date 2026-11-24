import 'dart:convert';
import 'dart:io';

import '../../domain/domain.dart';
import '../../infrastructure/js/qjs_sandbox_runtime.dart';
import '../../infrastructure/network/source_http_client.dart';
import 'js_plugin/js_plugin_provider.dart';
import 'legado_compat/legado_compat_provider.dart';
import 'legado_compat/legado_source.dart';
import 'parsing/pure_md5.dart';

/// Factory instantiating concrete online [BookProvider] implementations from
/// persisted [BookSource] definitions.
class BookProviderFactory {
  final SourceHttpClient httpClient;
  final Duration defaultJsTimeout;
  final int defaultMemoryLimitBytes;

  const BookProviderFactory({
    required this.httpClient,
    this.defaultJsTimeout = const Duration(seconds: 5),
    this.defaultMemoryLimitBytes = QjsSandboxRuntime.defaultMemoryLimitBytes,
  });

  /// Creates a [BookProvider] configured for [source].
  ///
  /// Throws [SourceParseFailure] when [source.rawDefinition] cannot be decoded.
  BookProvider createProvider(BookSource source) {
    switch (source.engineType) {
      case SourceEngineType.jsPlugin:
        final script = _extractJsPluginScript(source);
        return JsPluginProvider(
          providerId: source.id,
          sourceName: source.name,
          baseUrl: source.baseUrl,
          pluginScript: script,
          httpClient: httpClient,
          rateLimitMs: source.rateLimitMs,
          scriptTimeout: defaultJsTimeout,
          memoryLimitBytes: defaultMemoryLimitBytes,
        );

      case SourceEngineType.legado:
        final LegadoBookSource legado;
        try {
          legado = LegadoBookSource.fromJsonString(source.rawDefinition);
        } on FormatException catch (e, st) {
          throw SourceParseFailure(
            message:
                'Invalid Legado JSON definition for "${source.name}": ${e.message}',
            sourceId: source.id,
            step: 'registry',
            cause: e,
            stackTrace: st,
          );
        }
        return LegadoCompatProvider(
          providerId: source.id,
          source: legado,
          httpClient: httpClient,
          rateLimitMsOverride: source.rateLimitMs,
          jsTimeout: defaultJsTimeout,
        );
    }
  }

  static String _extractJsPluginScript(BookSource source) {
    final trimmed = source.rawDefinition.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final script =
              decoded['rawDefinition'] ??
              decoded['pluginScript'] ??
              decoded['script'];
          if (script is String && script.trim().isNotEmpty) {
            return script;
          }
        }
      } on FormatException {
        // Treat rawDefinition as direct JS script.
      }
    }
    if (trimmed.isEmpty) {
      throw SourceParseFailure(
        message: 'JS plugin source "${source.name}" has empty script',
        sourceId: source.id,
        step: 'registry',
      );
    }
    return source.rawDefinition;
  }
}

/// Result returned by [SourceImportExportService.importFromText] and
/// [SourceImportExportService.importFromFile].
class SourceImportBatch {
  final List<BookSource> sources;
  final List<LegadoParsedSource> legadoDetails;
  final int skippedNonTextCount;
  final int invalidCount;
  final List<String> messages;

  const SourceImportBatch({
    this.sources = const <BookSource>[],
    this.legadoDetails = const <LegadoParsedSource>[],
    this.skippedNonTextCount = 0,
    this.invalidCount = 0,
    this.messages = const <String>[],
  });
}

/// Auto-detecting import and export service for Legado JSON and JS plugin
/// book sources.
class SourceImportExportService {
  const SourceImportExportService();

  /// Imports book sources from a local `.json` or `.js` file path.
  Future<SourceImportBatch> importFromFile(
    String filePath, {
    bool useIsolate = true,
    bool skipNonTextSources = true,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileAccessFailure(
        message: 'Book source file does not exist: $filePath',
        filePath: filePath,
      );
    }
    try {
      final rawText = await file.readAsString();
      final name = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : filePath;
      return await importFromText(
        rawText,
        fileName: name,
        useIsolate: useIsolate,
        skipNonTextSources: skipNonTextSources,
      );
    } on AppFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to read book source file: ${e.message}',
        filePath: filePath,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Auto-detects Legado JSON vs JS plugin format and imports matching
  /// [BookSource] entities.
  Future<SourceImportBatch> importFromText(
    String rawText, {
    String? fileName,
    bool useIsolate = true,
    bool skipNonTextSources = true,
  }) async {
    final cleaned = _stripBom(rawText).trim();
    if (cleaned.isEmpty) {
      return const SourceImportBatch(
        invalidCount: 1,
        messages: <String>['Source import input is empty'],
      );
    }

    final lowerName = fileName?.toLowerCase() ?? '';
    final looksLikeJson =
        lowerName.endsWith('.json') ||
        cleaned.startsWith('{') ||
        cleaned.startsWith('[');

    if (looksLikeJson) {
      return _importJsonPayload(
        cleaned,
        useIsolate: useIsolate,
        skipNonTextSources: skipNonTextSources,
        strictJson: lowerName.endsWith('.json'),
      );
    }

    return _importJsPluginText(cleaned, fileName: fileName);
  }

  Future<SourceImportBatch> _importJsonPayload(
    String jsonText, {
    required bool useIsolate,
    required bool skipNonTextSources,
    required bool strictJson,
  }) async {
    // Fast-path large Legado JSON arrays (>= 256 KB) directly to Isolate parser
    // without decoding twice on the root isolate.
    if (useIsolate &&
        jsonText.length >= LegadoSourceParser.defaultIsolateThresholdBytes &&
        !jsonText.contains('"engineType"')) {
      return _importLegadoViaBatch(
        jsonText,
        useIsolate: true,
        skipNonTextSources: skipNonTextSources,
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e, st) {
      if (!strictJson && _looksLikeJsPluginScript(jsonText)) {
        return _importJsPluginText(jsonText);
      }
      throw SourceParseFailure(
        message: 'Invalid source JSON: ${e.message}',
        step: 'import',
        cause: e,
        stackTrace: st,
      );
    }

    final List<dynamic> entries;
    if (decoded is List<dynamic>) {
      entries = decoded;
    } else if (decoded is Map) {
      // Check for PureRead export envelope `{ "sources": [...] }`.
      if (decoded['format'] == 'pureread-sources' &&
          decoded['sources'] is List<dynamic>) {
        entries = decoded['sources'] as List<dynamic>;
      } else {
        entries = <dynamic>[decoded];
      }
    } else {
      throw const SourceParseFailure(
        message: 'Source JSON root must be an object or array',
        step: 'import',
      );
    }

    final containsJsPlugin = entries.any(
      (e) =>
          e is Map &&
          (e['engineType'] == 'jsPlugin' ||
              e['engineType'] == 'js_plugin' ||
              e.containsKey('pluginScript') ||
              e.containsKey('script')),
    );

    if (!containsJsPlugin) {
      return _importLegadoViaBatch(
        jsonEncode(entries),
        useIsolate: useIsolate,
        skipNonTextSources: skipNonTextSources,
      );
    }

    final now = DateTime.now().toUtc();
    final imported = <BookSource>[];
    final legadoDetails = <LegadoParsedSource>[];
    var skippedNonText = 0;
    var invalid = 0;
    final messages = <String>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is! Map) {
        invalid++;
        continue;
      }
      final map = entry.map((k, v) => MapEntry(k.toString(), v));
      final engineStr = map['engineType']?.toString() ?? '';
      if (engineStr == 'jsPlugin' ||
          engineStr == 'js_plugin' ||
          map.containsKey('pluginScript') ||
          map.containsKey('script')) {
        final rawDef =
            (map['rawDefinition'] ?? map['pluginScript'] ?? map['script'] ?? '')
                .toString();
        if (rawDef.trim().isEmpty) {
          invalid++;
          continue;
        }
        final name =
            (map['bookSourceName'] ?? map['name'] ?? 'JS 插件书源').toString();
        final baseUrl =
            (map['bookSourceUrl'] ?? map['baseUrl'] ?? '').toString();
        final group =
            (map['bookSourceGroup'] ?? map['groupName'] ?? 'JS插件').toString();
        final explicitId = map['id']?.toString().trim();
        final id = (explicitId != null && explicitId.isNotEmpty)
            ? explicitId
            : 'js_${PureMd5.digest16Hex('$name|$baseUrl|$rawDef')}';

        imported.add(
          BookSource(
            id: id,
            name: name,
            groupName: group.isEmpty ? 'JS插件' : group,
            engineType: SourceEngineType.jsPlugin,
            baseUrl: baseUrl,
            rawDefinition: rawDef,
            enabled: map['enabled'] is bool ? map['enabled'] as bool : true,
            weight: _asInt(map['weight'], fallback: 0),
            rateLimitMs: _asInt(map['rateLimitMs'], fallback: 500),
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        final singleBatch = LegadoSourceParser.parseBatchSync(
          jsonEncode(<dynamic>[map]),
          timestamp: now,
        );
        invalid += singleBatch.parseErrors.length;
        for (final parsed in singleBatch.items) {
          legadoDetails.add(parsed);
          if (skipNonTextSources &&
              parsed.compatibility ==
                  LegadoCompatibilityStatus.unsupportedType) {
            skippedNonText++;
            continue;
          }
          imported.add(parsed.domainSource);
        }
      }
    }

    if (skippedNonText > 0) {
      messages.add('已跳过 $skippedNonText 个非小说文本书源（音频/图片/文件类型）');
    }
    if (invalid > 0) {
      messages.add('有 $invalid 条书源格式不完整已被跳过');
    }

    return SourceImportBatch(
      sources: List<BookSource>.unmodifiable(imported),
      legadoDetails: List<LegadoParsedSource>.unmodifiable(legadoDetails),
      skippedNonTextCount: skippedNonText,
      invalidCount: invalid,
      messages: List<String>.unmodifiable(messages),
    );
  }

  Future<SourceImportBatch> _importLegadoViaBatch(
    String jsonText, {
    required bool useIsolate,
    required bool skipNonTextSources,
  }) async {
    final batch = await LegadoSourceParser.parseBatch(
      jsonText,
      useIsolate: useIsolate,
    );
    final accepted = <BookSource>[];
    var skippedNonText = 0;

    for (final item in batch.items) {
      if (skipNonTextSources &&
          item.compatibility == LegadoCompatibilityStatus.unsupportedType) {
        skippedNonText++;
        continue;
      }
      accepted.add(item.domainSource);
    }

    final messages = <String>[];
    if (skippedNonText > 0) {
      messages.add('已跳过 $skippedNonText 个非小说文本书源（音频/图片/文件类型）');
    }
    if (batch.parseErrors.isNotEmpty) {
      messages.add('有 ${batch.parseErrors.length} 条书源解析失败已被跳过');
    }

    return SourceImportBatch(
      sources: List<BookSource>.unmodifiable(accepted),
      legadoDetails: batch.items,
      skippedNonTextCount: skippedNonText,
      invalidCount: batch.parseErrors.length,
      messages: List<String>.unmodifiable(messages),
    );
  }

  SourceImportBatch _importJsPluginText(String scriptText, {String? fileName}) {
    final now = DateTime.now().toUtc();
    final name =
        _extractJsHeader(scriptText, 'name') ??
        _stripFileExtension(fileName) ??
        'JS 插件书源';
    final baseUrl =
        _extractJsHeader(scriptText, 'baseUrl') ??
        _extractJsHeader(scriptText, 'url') ??
        '';
    final group = _extractJsHeader(scriptText, 'group') ?? 'JS插件';
    final explicitId = _extractJsHeader(scriptText, 'id');
    final rateStr =
        _extractJsHeader(scriptText, 'rateLimitMs') ??
        _extractJsHeader(scriptText, 'rateLimit');
    final rateLimitMs = int.tryParse(rateStr ?? '') ?? 500;

    final id = (explicitId != null && explicitId.isNotEmpty)
        ? explicitId
        : 'js_${PureMd5.digest16Hex('$name|$baseUrl|$scriptText')}';

    return SourceImportBatch(
      sources: <BookSource>[
        BookSource(
          id: id,
          name: name,
          groupName: group,
          engineType: SourceEngineType.jsPlugin,
          baseUrl: baseUrl,
          rawDefinition: scriptText,
          enabled: true,
          weight: 0,
          rateLimitMs: rateLimitMs.clamp(0, 60000),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }

  /// Exports selected [sources] into a shareable JSON (or standalone `.js` for
  /// a single JS plugin) string that round-trips cleanly through
  /// [importFromText].
  String exportSources(List<BookSource> sources, {bool pretty = true}) {
    if (sources.isEmpty) return '[]';

    if (sources.length == 1 &&
        sources.first.engineType == SourceEngineType.jsPlugin) {
      return _ensureJsMetadataHeaders(sources.first);
    }

    final exported = <Object?>[];
    for (final source in sources) {
      if (source.engineType == SourceEngineType.legado) {
        try {
          final decoded = jsonDecode(source.rawDefinition);
          if (decoded is Map) {
            exported.add(decoded);
            continue;
          }
        } on FormatException {
          // Fall back to structured map below.
        }
      }
      exported.add(<String, Object?>{
        'id': source.id,
        'bookSourceName': source.name,
        'bookSourceGroup': source.groupName,
        'bookSourceUrl': source.baseUrl,
        'engineType': source.engineType.name,
        'enabled': source.enabled,
        'weight': source.weight,
        'rateLimitMs': source.rateLimitMs,
        'rawDefinition': source.rawDefinition,
      });
    }

    return pretty
        ? const JsonEncoder.withIndent('  ').convert(exported)
        : jsonEncode(exported);
  }

  static String _ensureJsMetadataHeaders(BookSource source) {
    final raw = source.rawDefinition;
    final lines = <String>[];
    if (_extractJsHeader(raw, 'id') == null) {
      lines.add('// @id ${source.id}');
    }
    if (_extractJsHeader(raw, 'name') == null) {
      lines.add('// @name ${source.name}');
    }
    if (_extractJsHeader(raw, 'baseUrl') == null &&
        _extractJsHeader(raw, 'url') == null &&
        source.baseUrl.isNotEmpty) {
      lines.add('// @baseUrl ${source.baseUrl}');
    }
    if (_extractJsHeader(raw, 'group') == null && source.groupName.isNotEmpty) {
      lines.add('// @group ${source.groupName}');
    }
    if (_extractJsHeader(raw, 'rateLimitMs') == null &&
        _extractJsHeader(raw, 'rateLimit') == null) {
      lines.add('// @rateLimitMs ${source.rateLimitMs}');
    }
    if (lines.isEmpty) return raw;
    return '${lines.join('\n')}\n$raw';
  }

  static String? _extractJsHeader(String source, String key) {
    final pattern = RegExp(
      r'^\s*//\s*@' + RegExp.escape(key) + r'\s*[:=]?\s*(.+)$',
      multiLine: true,
    );
    final match = pattern.firstMatch(source);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static bool _looksLikeJsPluginScript(String text) {
    return text.contains('function search') ||
        text.contains('function detail') ||
        text.contains('function toc') ||
        text.contains('function content') ||
        text.contains('async function');
  }

  static String? _stripFileExtension(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) return null;
    final trimmed = fileName.trim();
    final dotIdx = trimmed.lastIndexOf('.');
    if (dotIdx <= 0) return trimmed;
    return trimmed.substring(0, dotIdx);
  }

  static int _asInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static String _stripBom(String raw) {
    if (raw.isNotEmpty && raw.codeUnitAt(0) == 0xFEFF) {
      return raw.substring(1);
    }
    return raw;
  }
}
