import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../domain/domain.dart';
import 'core_providers.dart';
import 'reader/chapter_preload_scheduler.dart';

/// Factory gateway creating a [BookProvider] instance for an online [BookSource].
///
/// Stage 1 provides a safe unconfigured stub; Stage 2 overrides this provider
/// with the production `BookProviderFactory` from `source_registry.dart`.
abstract interface class BookProviderFactoryGateway {
  FutureOr<BookProvider> createProvider(BookSource source);
}

/// Summary returned when importing `.json` / `.js` sources or pasted text.
class SourceImportResult {
  final List<BookSource> sources;
  final int skippedNonTextCount;
  final int invalidCount;
  final List<String> messages;

  const SourceImportResult({
    this.sources = const <BookSource>[],
    this.skippedNonTextCount = 0,
    this.invalidCount = 0,
    this.messages = const <String>[],
  });
}

/// Gateway handling auto-detected import and serialization export for
/// Legado JSON and JS plugin book sources.
abstract interface class SourceImportExportGateway {
  Future<SourceImportResult> parseImportText(
    String rawText, {
    String? fileName,
  });

  Future<SourceImportResult> parseImportFile(String filePath);

  Future<String> exportSources(List<BookSource> sources);
}

/// Gateway abstracting raw online chapter cache storage on disk
/// (`cache/chapters/{bookId}/{chapterIndex}.txt`).
abstract interface class ChapterCacheGateway {
  String buildCacheKey(String bookId, int chapterIndex);

  Future<String?> readChapterText(String bookId, int chapterIndex);

  Future<String> writeChapterText(
    String bookId,
    int chapterIndex,
    String rawText,
  );

  Future<void> deleteBookCache(String bookId);

  Future<int> getTotalCacheBytes();

  Future<void> clearAllCache();
}

final bookProviderFactoryProvider = Provider<BookProviderFactoryGateway>(
  (ref) => const _StubBookProviderFactoryGateway(),
);

final sourceImportExportGatewayProvider = Provider<SourceImportExportGateway>(
  (ref) => const _DefaultSourceImportExportGateway(),
);

final chapterCacheGatewayProvider = Provider<ChapterCacheGateway>(
  (ref) => _InMemoryChapterCacheGateway(),
);

final chapterPreloadSchedulerProvider = Provider<ChapterPreloadScheduler>((
  ref,
) {
  final scheduler = ChapterPreloadScheduler(
    bookRepository: ref.watch(bookRepositoryProvider),
    sourceRepository: ref.watch(sourceRepositoryProvider),
    providerFactory: ref.watch(bookProviderFactoryProvider),
    cacheGateway: ref.watch(chapterCacheGatewayProvider),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

class _StubBookProviderFactoryGateway implements BookProviderFactoryGateway {
  const _StubBookProviderFactoryGateway();

  @override
  BookProvider createProvider(BookSource source) =>
      _UnconfiguredBookProvider(source);
}

class _UnconfiguredBookProvider implements BookProvider {
  const _UnconfiguredBookProvider(this._source);

  final BookSource _source;

  @override
  String get providerId => _source.id;

  @override
  ProviderType get type => _source.engineType == SourceEngineType.jsPlugin
      ? ProviderType.jsPlugin
      : ProviderType.legado;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    isLocal: false,
    supportsSearch: true,
    supportsUpdateCheck: true,
    supportsChangeSource: true,
  );

  SourceParseFailure _failure(String step) => SourceParseFailure(
    message: '在线书源引擎尚未装配，无法执行 $step 请求（${_source.name}）',
    sourceId: _source.id,
    step: step,
  );

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    throw _failure('search');
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    throw _failure('detail');
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    throw _failure('toc');
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    throw _failure('content');
  }
}

class _DefaultSourceImportExportGateway implements SourceImportExportGateway {
  const _DefaultSourceImportExportGateway();

  @override
  Future<SourceImportResult> parseImportFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileAccessFailure(
        message: '书源文件不存在：$filePath',
        filePath: filePath,
      );
    }
    try {
      final rawText = await file.readAsString();
      return await parseImportText(rawText, fileName: p.basename(filePath));
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw FileAccessFailure(
        message: '读取书源文件失败：$error',
        filePath: filePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<SourceImportResult> parseImportText(
    String rawText, {
    String? fileName,
  }) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return const SourceImportResult(
        invalidCount: 1,
        messages: <String>['导入内容为空'],
      );
    }

    final lowerName = fileName?.toLowerCase() ?? '';
    final looksLikeJson =
        lowerName.endsWith('.json') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[');

    if (looksLikeJson) {
      try {
        final decoded = jsonDecode(trimmed);
        final now = DateTime.now().toUtc();
        final sources = <BookSource>[];
        var skippedNonText = 0;
        var invalid = 0;
        final messages = <String>[];

        final candidates = <Object?>[];
        if (decoded is List<Object?>) {
          candidates.addAll(decoded);
        } else if (decoded is Map<Object?, Object?>) {
          candidates.add(decoded);
        } else {
          return const SourceImportResult(
            invalidCount: 1,
            messages: <String>['JSON 根节点必须是书源对象或数组'],
          );
        }

        for (final entry in candidates) {
          if (entry is! Map<Object?, Object?>) {
            invalid++;
            continue;
          }
          final map = <String, Object?>{};
          entry.forEach((k, v) {
            if (k != null) {
              map[k.toString()] = v;
            }
          });

          final sourceType = _asInt(map['bookSourceType'], fallback: 0);
          if (sourceType != 0) {
            skippedNonText++;
            continue;
          }

          final rawUrl = _asString(map['bookSourceUrl']).trim();
          final rawName = _asString(map['bookSourceName']).trim();
          if (rawUrl.isEmpty && rawName.isEmpty) {
            invalid++;
            continue;
          }

          final baseUrl = _stripFragment(rawUrl.isNotEmpty ? rawUrl : rawName);
          final name = rawName.isNotEmpty ? rawName : baseUrl;
          final id = _stableId('legado', rawUrl.isNotEmpty ? rawUrl : name);
          final group = _asString(map['bookSourceGroup']).trim();
          final enabled = _asBool(map['enabled'], fallback: true);
          final weight = _asInt(map['weight'], fallback: 0);
          final rateLimitMs = _resolveRateLimit(map);

          sources.add(
            BookSource(
              id: id,
              name: name,
              groupName: group.isEmpty ? '默认' : group,
              engineType: SourceEngineType.legado,
              baseUrl: baseUrl,
              rawDefinition: jsonEncode(map),
              enabled: enabled,
              weight: weight,
              rateLimitMs: rateLimitMs,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        if (skippedNonText > 0) {
          messages.add('已跳过 $skippedNonText 个非小说文本书源（音频/图片/文件类型）');
        }
        if (invalid > 0) {
          messages.add('有 $invalid 条书源格式不完整已被跳过');
        }

        return SourceImportResult(
          sources: sources,
          skippedNonTextCount: skippedNonText,
          invalidCount: invalid,
          messages: messages,
        );
      } catch (error) {
        if (lowerName.endsWith('.json')) {
          return SourceImportResult(
            invalidCount: 1,
            messages: <String>['JSON 解析失败：$error'],
          );
        }
      }
    }

    // Treat as JS plugin source.
    final now = DateTime.now().toUtc();
    final name =
        _extractJsHeader(trimmed, 'name') ??
        (fileName != null && fileName.isNotEmpty
            ? p.basenameWithoutExtension(fileName)
            : 'JS 插件书源');
    final baseUrl = _extractJsHeader(trimmed, 'url') ??
        _extractJsHeader(trimmed, 'baseUrl') ??
        '';
    final group = _extractJsHeader(trimmed, 'group') ?? 'JS插件';
    final explicitId = _extractJsHeader(trimmed, 'id');
    final rateStr = _extractJsHeader(trimmed, 'rateLimit');
    final rateLimitMs = int.tryParse(rateStr ?? '') ?? 500;
    final id = explicitId != null && explicitId.isNotEmpty
        ? explicitId
        : _stableId('js', '$name::$baseUrl::$trimmed');

    return SourceImportResult(
      sources: <BookSource>[
        BookSource(
          id: id,
          name: name,
          groupName: group,
          engineType: SourceEngineType.jsPlugin,
          baseUrl: _stripFragment(baseUrl),
          rawDefinition: trimmed,
          enabled: true,
          weight: 0,
          rateLimitMs: rateLimitMs.clamp(0, 60000),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }

  @override
  Future<String> exportSources(List<BookSource> sources) async {
    if (sources.isEmpty) return '[]';
    if (sources.length == 1 &&
        sources.first.engineType == SourceEngineType.jsPlugin) {
      return sources.first.rawDefinition;
    }

    final exported = <Object?>[];
    for (final source in sources) {
      if (source.engineType == SourceEngineType.legado) {
        try {
          final decoded = jsonDecode(source.rawDefinition);
          if (decoded is Map<Object?, Object?>) {
            exported.add(decoded);
            continue;
          }
        } catch (_) {
          // Fall back to structured summary map below.
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
    return const JsonEncoder.withIndent('  ').convert(exported);
  }

  static String _asString(Object? value) {
    if (value == null) return '';
    return value.toString();
  }

  static int _asInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static bool _asBool(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return fallback;
  }

  static int _resolveRateLimit(Map<String, Object?> map) {
    final explicit = _asInt(map['rateLimitMs'], fallback: -1);
    if (explicit >= 0) return explicit.clamp(0, 60000);
    final concurrentRate = _asString(map['concurrentRate']).trim();
    if (concurrentRate.isEmpty) return 500;
    final directMs = int.tryParse(concurrentRate);
    if (directMs != null && directMs >= 0) {
      return directMs.clamp(0, 60000);
    }
    final slashIdx = concurrentRate.indexOf('/');
    if (slashIdx > 0) {
      final count = int.tryParse(concurrentRate.substring(0, slashIdx).trim());
      final windowMs = int.tryParse(
        concurrentRate.substring(slashIdx + 1).trim(),
      );
      if (count != null && count > 0 && windowMs != null && windowMs > 0) {
        return (windowMs ~/ count).clamp(0, 60000);
      }
    }
    return 500;
  }

  static String _stripFragment(String url) {
    final hashIdx = url.indexOf('#');
    if (hashIdx <= 0) return url;
    return url.substring(0, hashIdx).trim();
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

  static String _stableId(String prefix, String raw) {
    var hash1 = 0x811c9dc5;
    var hash2 = 0x9e3779b9;
    for (final unit in utf8.encode(raw)) {
      hash1 ^= unit;
      hash1 = (hash1 * 0x01000193) & 0x7fffffff;
      hash2 ^= unit;
      hash2 = (hash2 * 0x85ebca6b) & 0x7fffffff;
    }
    return '${prefix}_${hash1.toRadixString(16)}_${hash2.toRadixString(16)}';
  }
}

class _InMemoryChapterCacheGateway implements ChapterCacheGateway {
  final Map<String, String> _cache = <String, String>{};

  @override
  String buildCacheKey(String bookId, int chapterIndex) =>
      '$bookId/$chapterIndex.txt';

  @override
  Future<String?> readChapterText(String bookId, int chapterIndex) async =>
      _cache[buildCacheKey(bookId, chapterIndex)];

  @override
  Future<String> writeChapterText(
    String bookId,
    int chapterIndex,
    String rawText,
  ) async {
    final key = buildCacheKey(bookId, chapterIndex);
    _cache[key] = rawText;
    return key;
  }

  @override
  Future<void> deleteBookCache(String bookId) async {
    final prefix = '$bookId/';
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  @override
  Future<int> getTotalCacheBytes() async {
    var total = 0;
    for (final content in _cache.values) {
      total += utf8.encode(content).length;
    }
    return total;
  }

  @override
  Future<void> clearAllCache() async {
    _cache.clear();
  }
}
