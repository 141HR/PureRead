import 'dart:convert';

import '../../../domain/domain.dart';
import '../../../infrastructure/js/qjs_sandbox_runtime.dart';
import '../../../infrastructure/network/source_http_client.dart';
import '../parsing/legado_selector_engine.dart';

/// Executes a 4-method (`search`, `detail`, `toc`, `content`) JavaScript
/// book-source plugin inside a sandboxed [QjsSandboxRuntime].
class JsPluginProvider implements BookProvider {
  @override
  final String providerId;

  final String sourceName;
  final String baseUrl;
  final String pluginScript;
  final SourceHttpClient httpClient;
  final int rateLimitMs;
  final Duration scriptTimeout;
  final int memoryLimitBytes;

  @override
  ProviderType get type => ProviderType.jsPlugin;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    isLocal: false,
    supportsSearch: true,
    supportsUpdateCheck: true,
    supportsChangeSource: true,
  );

  JsPluginProvider({
    required this.providerId,
    required this.sourceName,
    required this.baseUrl,
    required this.pluginScript,
    required this.httpClient,
    this.rateLimitMs = 500,
    this.scriptTimeout = const Duration(seconds: 5),
    this.memoryLimitBytes = QjsSandboxRuntime.defaultMemoryLimitBytes,
  });

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    final res = await _invokePluginMethod(
      step: 'search',
      methodName: 'search',
      args: <Object?>[keyword, page],
      cancelToken: cancelToken,
    );

    final rawList = _decodeJsonList(res.value, step: 'search');
    final items = rawList
        .map((raw) {
          final map = _asStringMap(raw, step: 'search');
          final bookUrl = _resolveUrl(
            _readRequiredString(map, 'bookUrl', 'search'),
          );
          return BookSearchItem(
            sourceId: providerId,
            providerType: type,
            bookUrl: bookUrl,
            title: _readRequiredString(map, 'title', 'search'),
            author: (map['author'] ?? '').toString().trim(),
            coverUrl: _nullableResolvedUrl(map['coverUrl']?.toString()),
            intro: (map['intro'] ?? '').toString().trim(),
            latestChapterTitle: (map['latestChapterTitle'] ?? '')
                .toString()
                .trim(),
            kind: _nullableTrimmed(map['kind']?.toString()),
          );
        })
        .toList(growable: false);

    return (
      items: items,
      trace: SourceDebugTrace(
        step: res.trace.step,
        elapsedMs: res.trace.elapsedMs,
        httpStatus: res.trace.httpStatus,
        requestUrl: res.trace.requestUrl,
        matchedPreview: items.isEmpty
            ? '0 items'
            : '${items.length} items (first: ${items.first.title})',
        logs: res.trace.logs,
      ),
    );
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    final resolvedBookUrl = _resolveUrl(bookUrl);
    final res = await _invokePluginMethod(
      step: 'detail',
      methodName: 'detail',
      args: <Object?>[resolvedBookUrl],
      cancelToken: cancelToken,
    );

    final map = _decodeJsonMap(res.value, step: 'detail');
    final rawTocUrl = map['tocUrl']?.toString().trim() ?? '';
    final tocUrl = _resolveUrl(
      rawTocUrl.isNotEmpty ? rawTocUrl : resolvedBookUrl,
    );
    final detail = BookDetail(
      sourceId: providerId,
      providerType: type,
      bookUrl: resolvedBookUrl,
      tocUrl: tocUrl,
      title: _readRequiredString(map, 'title', 'detail'),
      author: (map['author'] ?? '').toString().trim(),
      coverUrl: _nullableResolvedUrl(map['coverUrl']?.toString()),
      intro: (map['intro'] ?? '').toString().trim(),
      latestChapterTitle: (map['latestChapterTitle'] ?? '').toString().trim(),
      kind: _nullableTrimmed(map['kind']?.toString()),
      wordCount: int.tryParse(map['wordCount']?.toString() ?? ''),
    );

    return (
      detail: detail,
      trace: SourceDebugTrace(
        step: res.trace.step,
        elapsedMs: res.trace.elapsedMs,
        httpStatus: res.trace.httpStatus,
        requestUrl: res.trace.requestUrl,
        matchedPreview: '${detail.title} / ${detail.author}',
        logs: res.trace.logs,
      ),
    );
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    final resolvedTocUrl = _resolveUrl(tocUrl);
    final res = await _invokePluginMethod(
      step: 'toc',
      methodName: 'toc',
      args: <Object?>[resolvedTocUrl],
      cancelToken: cancelToken,
    );

    final rawList = _decodeJsonList(res.value, step: 'toc');
    final now = DateTime.now().toUtc();
    final chapters = <ChapterMeta>[];
    for (var i = 0; i < rawList.length; i++) {
      final map = _asStringMap(rawList[i], step: 'toc');
      final chapterUrl = _resolveUrl(_readRequiredString(map, 'url', 'toc'));
      chapters.add(
        ChapterMeta(
          bookId: resolvedTocUrl,
          chapterIndex: i,
          title: _readRequiredString(map, 'title', 'toc'),
          url: chapterUrl,
          updatedAt: now,
        ),
      );
    }

    return (
      chapters: chapters,
      trace: SourceDebugTrace(
        step: res.trace.step,
        elapsedMs: res.trace.elapsedMs,
        httpStatus: res.trace.httpStatus,
        requestUrl: res.trace.requestUrl,
        matchedPreview: chapters.isEmpty
            ? '0 chapters'
            : '${chapters.length} chapters (first: ${chapters.first.title})',
        logs: res.trace.logs,
      ),
    );
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    final chapterUrl = chapter.url;
    if (chapterUrl == null || chapterUrl.trim().isEmpty) {
      throw SourceParseFailure(
        message: 'ChapterMeta.url is empty for chapter ${chapter.title}',
        sourceId: providerId,
        step: 'content',
      );
    }
    final resolvedUrl = _resolveUrl(chapterUrl);
    final res = await _invokePluginMethod(
      step: 'content',
      methodName: 'content',
      args: <Object?>[resolvedUrl],
      cancelToken: cancelToken,
    );

    String rawText;
    var title = chapter.title;
    final trimmed = res.value.trim();
    if (trimmed.startsWith('{')) {
      final map = _decodeJsonMap(trimmed, step: 'content');
      rawText = (map['text'] ?? map['content'] ?? '').toString();
      final overrideTitle = map['title']?.toString().trim() ?? '';
      if (overrideTitle.isNotEmpty) {
        title = overrideTitle;
      }
    } else {
      rawText = res.value;
    }

    if (rawText.trim().isEmpty) {
      throw SourceParseFailure(
        message: 'JS plugin returned empty chapter text',
        sourceId: providerId,
        step: 'content',
      );
    }

    final content = ChapterContent(
      chapterIndex: chapter.chapterIndex,
      title: title,
      rawText: rawText,
      sourceUrl: resolvedUrl,
      fetchedAt: DateTime.now().toUtc(),
    );

    return (
      content: content,
      trace: SourceDebugTrace(
        step: res.trace.step,
        elapsedMs: res.trace.elapsedMs,
        httpStatus: res.trace.httpStatus,
        requestUrl: res.trace.requestUrl,
        matchedPreview: rawText.length > 60
            ? '${rawText.substring(0, 60)}...'
            : rawText,
        logs: res.trace.logs,
      ),
    );
  }

  Future<({String value, SourceDebugTrace trace})> _invokePluginMethod({
    required String step,
    required String methodName,
    required List<Object?> args,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final sw = Stopwatch()..start();
    int? lastStatus;
    String? lastUrl;
    AppFailure? hostFailure;

    final runtime = QjsSandboxRuntime(
      sourceId: providerId,
      memoryLimitBytes: memoryLimitBytes,
      syncHostFunctions: <String, HostSyncCallback>{
        'cssSelect': (callArgs) {
          final html = callArgs.isNotEmpty ? (callArgs[0]?.toString() ?? '') : '';
          final rule = callArgs.length > 1 ? (callArgs[1]?.toString() ?? '') : '';
          return LegadoSelectorEngine.selectValues(html, rule);
        },
        'cssSelectOne': (callArgs) {
          final html = callArgs.isNotEmpty ? (callArgs[0]?.toString() ?? '') : '';
          final rule = callArgs.length > 1 ? (callArgs[1]?.toString() ?? '') : '';
          return LegadoSelectorEngine.selectOne(html, rule);
        },
        'cssElements': (callArgs) {
          final html = callArgs.isNotEmpty ? (callArgs[0]?.toString() ?? '') : '';
          final selector =
              callArgs.length > 1 ? (callArgs[1]?.toString() ?? '') : '';
          return LegadoSelectorEngine.selectElements(html, selector);
        },
        'xpath': (callArgs) {
          final html = callArgs.isNotEmpty ? (callArgs[0]?.toString() ?? '') : '';
          final expr = callArgs.length > 1 ? (callArgs[1]?.toString() ?? '') : '';
          return LegadoSelectorEngine.selectXPath(html, expr);
        },
        'jsonPath': (callArgs) {
          final jsonText =
              callArgs.isNotEmpty ? (callArgs[0]?.toString() ?? '') : '';
          final expr = callArgs.length > 1 ? (callArgs[1]?.toString() ?? '') : '';
          return LegadoSelectorEngine.selectJsonPath(jsonText, expr);
        },
      },
      asyncHostFunctions: <String, HostAsyncCallback>{
        'httpGet': (callArgs) async {
          final rawUrl =
              callArgs.isNotEmpty ? (callArgs[0]?.toString() ?? '') : '';
          final url = _resolveUrl(rawUrl);
          final headers = _toStringHeaderMap(
            callArgs.length > 1 ? callArgs[1] : null,
          );
          final charset = callArgs.length > 2 ? callArgs[2]?.toString() : null;
          try {
            final resp = await httpClient.request(
              url,
              method: 'GET',
              headers: headers,
              charsetOverride: charset,
              rateLimitMs: rateLimitMs,
              cancelToken: cancelToken,
            );
            lastStatus = resp.statusCode;
            lastUrl = resp.finalUrl;
            return <String, Object?>{
              'status': resp.statusCode,
              'url': resp.finalUrl,
              'charset': resp.detectedCharset,
              'headers': resp.headers,
              'body': resp.body,
            };
          } on AppFailure catch (e) {
            hostFailure = e;
            rethrow;
          }
        },
        'httpPost': (callArgs) async {
          final rawUrl =
              callArgs.isNotEmpty ? (callArgs[0]?.toString() ?? '') : '';
          final url = _resolveUrl(rawUrl);
          final body = callArgs.length > 1 ? callArgs[1] : null;
          final headers = _toStringHeaderMap(
            callArgs.length > 2 ? callArgs[2] : null,
          );
          final charset = callArgs.length > 3 ? callArgs[3]?.toString() : null;
          try {
            final resp = await httpClient.request(
              url,
              method: 'POST',
              data: body,
              headers: headers,
              charsetOverride: charset,
              rateLimitMs: rateLimitMs,
              cancelToken: cancelToken,
            );
            lastStatus = resp.statusCode;
            lastUrl = resp.finalUrl;
            return <String, Object?>{
              'status': resp.statusCode,
              'url': resp.finalUrl,
              'charset': resp.detectedCharset,
              'headers': resp.headers,
              'body': resp.body,
            };
          } on AppFailure catch (e) {
            hostFailure = e;
            rethrow;
          }
        },
      },
    );

    final serializedArgs = jsonEncode(args);
    final driverScript = '''
var module = globalThis.module || { exports: {} };
var exports = module.exports;
$pluginScript
;(() => {
  const fn = (typeof $methodName === 'function')
    ? $methodName
    : (globalThis.plugin && typeof globalThis.plugin.$methodName === 'function')
      ? globalThis.plugin.$methodName
      : (module.exports && typeof module.exports.$methodName === 'function')
        ? module.exports.$methodName
        : null;
  if (!fn) {
    throw new Error('Missing plugin method: $methodName');
  }
  return fn(...$serializedArgs);
})();
''';

    try {
      final result = await runtime.evaluate(
        driverScript,
        bindings: <String, Object?>{
          'baseUrl': SourceHttpClient.tryNormalizeHttpUri(baseUrl)?.toString() ??
              baseUrl,
          'sourceName': sourceName,
        },
        timeout: scriptTimeout,
        cancelToken: cancelToken,
      );
      sw.stop();
      return (
        value: result.value,
        trace: SourceDebugTrace(
          step: step,
          elapsedMs: sw.elapsedMilliseconds,
          httpStatus: lastStatus,
          requestUrl: lastUrl,
          logs: result.logs,
        ),
      );
    } on AppFailure {
      if (hostFailure != null) {
        throw hostFailure!;
      }
      rethrow;
    } finally {
      await runtime.dispose();
    }
  }

  String _resolveUrl(String url) => SourceHttpClient.resolveUrl(url, baseUrl);

  String? _nullableResolvedUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    return _resolveUrl(url);
  }

  static String? _nullableTrimmed(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static Map<String, String>? _toStringHeaderMap(Object? raw) {
    if (raw is! Map) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  List<dynamic> _decodeJsonList(String raw, {required String step}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) return decoded;
      throw SourceParseFailure(
        message: 'Expected JSON array from $step, got ${decoded.runtimeType}',
        sourceId: providerId,
        step: step,
      );
    } on FormatException catch (e, st) {
      throw SourceParseFailure(
        message: 'Invalid JSON returned by JS plugin $step: ${e.message}',
        sourceId: providerId,
        step: step,
        cause: e,
        stackTrace: st,
      );
    }
  }

  Map<String, dynamic> _decodeJsonMap(String raw, {required String step}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      throw SourceParseFailure(
        message: 'Expected JSON object from $step, got ${decoded.runtimeType}',
        sourceId: providerId,
        step: step,
      );
    } on FormatException catch (e, st) {
      throw SourceParseFailure(
        message: 'Invalid JSON returned by JS plugin $step: ${e.message}',
        sourceId: providerId,
        step: step,
        cause: e,
        stackTrace: st,
      );
    }
  }

  Map<String, dynamic> _asStringMap(dynamic value, {required String step}) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    throw SourceParseFailure(
      message: 'Expected object item in $step list, got ${value.runtimeType}',
      sourceId: providerId,
      step: step,
    );
  }

  String _readRequiredString(
    Map<String, dynamic> map,
    String key,
    String step,
  ) {
    final val = map[key]?.toString().trim() ?? '';
    if (val.isEmpty) {
      throw SourceParseFailure(
        message: 'Missing required field "$key" in $step result',
        sourceId: providerId,
        step: step,
        rule: key,
      );
    }
    return val;
  }
}
