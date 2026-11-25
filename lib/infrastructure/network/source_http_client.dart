import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../../domain/domain.dart';

/// Result returned by [SourceHttpClient.request].
class HttpFetchResult {
  final String body;
  final int statusCode;
  final String finalUrl;
  final String detectedCharset;
  final Map<String, String> headers;
  final String? redirectLocation;

  const HttpFetchResult({
    required this.body,
    required this.statusCode,
    required this.finalUrl,
    required this.detectedCharset,
    required this.headers,
    this.redirectLocation,
  });
}

/// Cookie container maintaining strictly isolated [CookieJar] instances per
/// normalized HTTP host (`uri.host.toLowerCase()`).
class HostIsolatedCookieJar implements CookieJar {
  HostIsolatedCookieJar({this.ignoreExpires = false});

  @override
  final bool ignoreExpires;

  final Map<String, CookieJar> _hostJars = <String, CookieJar>{};

  static String hostKeyForUri(Uri uri) {
    final host = uri.host.trim().toLowerCase();
    return host.isEmpty ? '_default_' : host;
  }

  /// Returns the isolated [CookieJar] assigned to [host].
  CookieJar jarForHost(String host) {
    final normalized = host.trim().toLowerCase();
    final key = normalized.isEmpty ? '_default_' : normalized;
    return _hostJars.putIfAbsent(
      key,
      () => CookieJar(ignoreExpires: ignoreExpires),
    );
  }

  /// Exposed for testing/inspection of active host keys.
  Iterable<String> get trackedHosts => _hostJars.keys;

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) {
    return jarForHost(hostKeyForUri(uri)).saveFromResponse(uri, cookies);
  }

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) {
    return jarForHost(hostKeyForUri(uri)).loadForRequest(uri);
  }

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) {
    final key = hostKeyForUri(uri);
    final jar = _hostJars[key];
    if (jar == null) return Future<void>.value();
    return jar.delete(uri, withDomainSharedCookie);
  }

  @override
  Future<void> deleteAll() async {
    for (final jar in _hostJars.values) {
      await jar.deleteAll();
    }
    _hostJars.clear();
  }

  /// Removes all stored cookies for the host of [uri].
  Future<void> deleteHost(Uri uri) async {
    final key = hostKeyForUri(uri);
    final jar = _hostJars.remove(key);
    if (jar != null) {
      await jar.deleteAll();
    }
  }
}

/// Per-host rate limiter serializing dispatch slots so concurrent requests to
/// the same host honor [rateLimitMs] spacing without blocking other hosts.
class _HostRateLimiter {
  final Map<String, Future<void>> _tails = <String, Future<void>>{};
  final Map<String, int> _lastDispatchUs = <String, int>{};
  final Stopwatch _clock = Stopwatch()..start();

  Future<void> acquire(
    String hostKey,
    int rateLimitMs, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    if (rateLimitMs <= 0) return;

    final previous = _tails[hostKey] ?? Future<void>.value();
    final turnCompleter = Completer<void>();
    _tails[hostKey] = turnCompleter.future;

    try {
      await previous.catchError((Object _) {});
      cancelToken?.throwIfCancelled();

      final minGapUs = rateLimitMs * 1000;
      final lastUs = _lastDispatchUs[hostKey];
      if (lastUs != null) {
        final elapsedUs = _clock.elapsedMicroseconds - lastUs;
        final waitUs = minGapUs - elapsedUs;
        if (waitUs > 0) {
          await _cancellableDelay(
            Duration(microseconds: waitUs),
            cancelToken: cancelToken,
          );
        }
      }

      cancelToken?.throwIfCancelled();
      _lastDispatchUs[hostKey] = _clock.elapsedMicroseconds;
    } finally {
      if (identical(_tails[hostKey], turnCompleter.future)) {
        unawaited(_tails.remove(hostKey));
      }
      if (!turnCompleter.isCompleted) {
        turnCompleter.complete();
      }
    }
  }

  static Future<void> _cancellableDelay(
    Duration duration, {
    CancellationToken? cancelToken,
  }) {
    cancelToken?.throwIfCancelled();
    final completer = Completer<void>();
    Timer? timer;
    void onCancel() {
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(const CancelledFailure());
      }
    }

    cancelToken?.addListener(onCancel);
    timer = Timer(duration, () {
      cancelToken?.removeListener(onCancel);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future.whenComplete(() {
      cancelToken?.removeListener(onCancel);
    });
  }
}

/// Shared HTTP client for online book sources (`JsPluginProvider` and
/// `LegadoCompatProvider`).
///
/// Features:
/// - Per-host rate limiting (`rateLimitMs`)
/// - Per-host isolated [CookieJar] with `getCookie`/`getKey`/`setCookie`/`removeCookie`
/// - Cooperative [CancellationToken] bridging to Dio [CancelToken]
/// - Deterministic charset decoding (`explicitCharset -> Content-Type -> <meta charset> -> UTF-8 -> GB18030/GBK`)
class SourceHttpClient {
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  final Dio _dio;
  final HostIsolatedCookieJar cookieJar;
  final int defaultRateLimitMs;
  final Map<String, String> defaultHeaders;
  final _HostRateLimiter _rateLimiter = _HostRateLimiter();

  SourceHttpClient({
    Dio? dio,
    HostIsolatedCookieJar? cookieJar,
    this.defaultRateLimitMs = 0,
    Map<String, String>? defaultHeaders,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 15),
  }) : cookieJar = cookieJar ?? HostIsolatedCookieJar(),
       defaultHeaders = Map<String, String>.unmodifiable(
         defaultHeaders ?? const <String, String>{},
       ),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: connectTimeout,
               receiveTimeout: receiveTimeout,
               responseType: ResponseType.bytes,
               followRedirects: true,
               maxRedirects: 5,
               validateStatus: (status) => status != null && status < 500,
             ),
           ) {
    if (!_dio.interceptors.any((i) => i is CookieManager)) {
      _dio.interceptors.add(
        CookieManager(this.cookieJar, ignoreInvalidCookies: true),
      );
    }
  }

  /// Strips `#fragment` tags cleanly and returns a valid HTTP/HTTPS [Uri],
  /// or `null` when [raw] is malformed or non-HTTP.
  static Uri? tryNormalizeHttpUri(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final fragIdx = trimmed.indexOf('#');
    if (fragIdx != -1) {
      trimmed = trimmed.substring(0, fragIdx).trim();
    }
    if (trimmed.isEmpty) return null;

    var parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme) {
      if (!trimmed.contains('://') &&
          RegExp(
            r'^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(:\d+)?(/.*)?$',
          ).hasMatch(trimmed)) {
        parsed = Uri.tryParse('https://$trimmed');
      }
    }
    if (parsed == null) return null;
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (parsed.host.trim().isEmpty) return null;
    return parsed.removeFragment();
  }

  /// Resolves [targetUrl] against [baseUrl], stripping `#fragment` tags on
  /// [baseUrl] and gracefully handling malformed URLs without throwing.
  static String resolveUrl(String targetUrl, String baseUrl) {
    final trimmed = targetUrl.trim();
    if (trimmed.isEmpty) {
      return tryNormalizeHttpUri(baseUrl)?.toString() ?? baseUrl.trim();
    }

    final parsedTarget = Uri.tryParse(trimmed);
    if (parsedTarget != null && parsedTarget.hasScheme) {
      final scheme = parsedTarget.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        return trimmed;
      }
      return trimmed;
    }

    final normalizedBase = tryNormalizeHttpUri(baseUrl);
    if (normalizedBase == null) {
      return trimmed;
    }

    if (trimmed.startsWith('//')) {
      return '${normalizedBase.scheme}:$trimmed';
    }

    try {
      return normalizedBase.resolve(trimmed).toString();
    } on FormatException {
      return trimmed;
    }
  }

  /// Sends an HTTP request with per-host rate limiting, per-host cookies,
  /// cooperative cancellation, and deterministic charset decoding.
  Future<HttpFetchResult> request(
    String url, {
    String method = 'GET',
    Object? data,
    Map<String, String>? headers,
    String? charsetOverride,
    int? rateLimitMs,
    Duration? timeout,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final normalizedUri = tryNormalizeHttpUri(url);
    if (normalizedUri == null) {
      throw NetworkFailure(
        message: 'Invalid or non-HTTP URL: "$url"',
        url: url,
      );
    }

    final effectiveRateLimit = rateLimitMs ?? defaultRateLimitMs;
    await _rateLimiter.acquire(
      HostIsolatedCookieJar.hostKeyForUri(normalizedUri),
      effectiveRateLimit,
      cancelToken: cancelToken,
    );

    final dioCancel = CancelToken();
    void onCancel() {
      if (!dioCancel.isCancelled) {
        dioCancel.cancel('Cancelled by PureRead CancellationToken');
      }
    }

    cancelToken?.addListener(onCancel);

    try {
      final upperMethod = method.trim().isEmpty
          ? 'GET'
          : method.trim().toUpperCase();
      final mergedHeaders = _mergeHeaders(
        defaultHeaders: defaultHeaders,
        requestHeaders: headers,
        method: upperMethod,
        data: data,
      );

      final response = await _dio.requestUri<List<int>>(
        normalizedUri,
        data: data,
        cancelToken: dioCancel,
        options: Options(
          method: upperMethod,
          headers: mergedHeaders,
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          sendTimeout: data != null ? timeout : null,
          receiveTimeout: timeout,
        ),
      );

      cancelToken?.throwIfCancelled();

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 400 || statusCode == 0) {
        throw NetworkFailure(
          message: 'HTTP $statusCode from $normalizedUri',
          statusCode: statusCode == 0 ? null : statusCode,
          url: normalizedUri.toString(),
        );
      }

      final rawBytes = Uint8List.fromList(response.data ?? const <int>[]);
      final contentType = response.headers.value(Headers.contentTypeHeader);
      final decoded = decodeResponseBytes(
        rawBytes,
        explicitCharset: charsetOverride,
        contentTypeHeader: contentType,
      );

      final flatHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          flatHeaders[name.toLowerCase()] = values.join(', ');
        }
      });

      final redirectLocation =
          flatHeaders['location'] ??
          (response.redirects.isNotEmpty
              ? response.redirects.first.location.toString()
              : null);
      final rawFinalUri = response.realUri.toString();
      final finalUri = rawFinalUri.isEmpty
          ? normalizedUri.toString()
          : resolveUrl(rawFinalUri, normalizedUri.toString());
      return HttpFetchResult(
        body: decoded.text,
        statusCode: statusCode,
        finalUrl: finalUri,
        detectedCharset: decoded.charsetName,
        headers: flatHeaders,
        redirectLocation: redirectLocation,
      );
    } on AppFailure {
      rethrow;
    } on DioException catch (e, st) {
      if (e.type == DioExceptionType.cancel ||
          (cancelToken?.isCancelled ?? false)) {
        throw CancelledFailure(cause: e, stackTrace: st);
      }
      final isTimeout =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      throw NetworkFailure(
        message:
            'Network request failed ($normalizedUri): ${e.message ?? e.type.name}',
        statusCode: e.response?.statusCode,
        url: normalizedUri.toString(),
        isTimeout: isTimeout,
        cause: e,
        stackTrace: st,
      );
    } finally {
      cancelToken?.removeListener(onCancel);
    }
  }

  /// Returns all stored cookies for the host of [urlOrDomain] formatted as a
  /// `Cookie` header string (`name1=val1; name2=val2`).
  Future<String> getCookie(String urlOrDomain) async {
    final uri = tryNormalizeHttpUri(urlOrDomain);
    if (uri == null) return '';
    final cookies = await cookieJar.loadForRequest(uri);
    if (cookies.isEmpty) return '';
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  /// Returns the value of cookie [key] for the host of [urlOrDomain], or `''`.
  Future<String> getKey(String urlOrDomain, String key) async {
    final uri = tryNormalizeHttpUri(urlOrDomain);
    if (uri == null || key.trim().isEmpty) return '';
    final cookies = await cookieJar.loadForRequest(uri);
    for (final cookie in cookies) {
      if (cookie.name == key) {
        return cookie.value;
      }
    }
    return '';
  }

  /// Parses and stores [cookieHeaderOrSetCookie] for the host of [urlOrDomain].
  Future<void> setCookie(
    String urlOrDomain,
    String cookieHeaderOrSetCookie,
  ) async {
    final uri = tryNormalizeHttpUri(urlOrDomain);
    if (uri == null) return;
    final trimmed = cookieHeaderOrSetCookie.trim();
    if (trimmed.isEmpty) return;

    final lower = trimmed.toLowerCase();
    final looksLikeSetCookieAttr =
        lower.contains('expires=') ||
        lower.contains('max-age=') ||
        lower.contains('path=') ||
        lower.contains('domain=') ||
        lower.contains('httponly') ||
        lower.contains('samesite=');

    final parsedCookies = <Cookie>[];
    if (looksLikeSetCookieAttr) {
      try {
        parsedCookies.add(Cookie.fromSetCookieValue(trimmed));
      } on HttpException {
        // Ignore malformed Set-Cookie attributes safely.
      }
    } else {
      for (final part in trimmed.split(';')) {
        final item = part.trim();
        if (item.isEmpty) continue;
        final eqIdx = item.indexOf('=');
        if (eqIdx <= 0) continue;
        final name = item.substring(0, eqIdx).trim();
        final value = item.substring(eqIdx + 1).trim();
        if (name.isNotEmpty) {
          parsedCookies.add(Cookie(name, value));
        }
      }
    }

    if (parsedCookies.isNotEmpty) {
      await cookieJar.saveFromResponse(uri, parsedCookies);
    }
  }

  /// Removes all stored cookies for the host of [urlOrDomain].
  Future<void> removeCookie(String urlOrDomain) async {
    final uri = tryNormalizeHttpUri(urlOrDomain);
    if (uri == null) return;
    await cookieJar.deleteHost(uri);
  }

  /// Clears all stored cookies across every host.
  Future<void> clearAllCookies() => cookieJar.deleteAll();

  /// Encodes a query parameter or form value according to [charset].
  static String encodeQueryComponentForCharset(
    String value, {
    String? charset,
  }) {
    final norm = _normalizeCharsetName(charset);
    if (norm == 'gbk' || norm == 'gb2312' || norm == 'gb18030') {
      final bytes = gbk.encode(value);
      return _percentEncodeBytes(bytes);
    }
    return Uri.encodeQueryComponent(value);
  }

  static String _percentEncodeBytes(List<int> bytes) {
    final out = StringBuffer();
    for (final byte in bytes) {
      if ((byte >= 0x41 && byte <= 0x5A) ||
          (byte >= 0x61 && byte <= 0x7A) ||
          (byte >= 0x30 && byte <= 0x39) ||
          byte == 0x2D ||
          byte == 0x5F ||
          byte == 0x2E ||
          byte == 0x7E) {
        out.writeCharCode(byte);
      } else if (byte == 0x20) {
        out.write('+');
      } else {
        out.write('%');
        out.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return out.toString();
  }

  /// Decodes raw HTTP response bytes in deterministic order:
  /// `explicitCharset -> Content-Type -> <meta charset> -> UTF-8 -> GB18030/GBK`.
  ///
  /// Never calls `Charset.detect()`.
  static ({String text, String charsetName}) decodeResponseBytes(
    Uint8List bytes, {
    String? explicitCharset,
    String? contentTypeHeader,
  }) {
    if (bytes.isEmpty) {
      return (text: '', charsetName: 'utf-8');
    }

    final targetName =
        _normalizeCharsetName(explicitCharset) ??
        _extractCharsetFromContentType(contentTypeHeader) ??
        _sniffMetaCharset(bytes);

    if (targetName != null) {
      final decoded = _tryDecodeDeclaredCharset(bytes, targetName);
      if (decoded != null) {
        return (text: _stripLeadingBom(decoded), charsetName: targetName);
      }
      throw EncodingFailure(
        message: 'Failed to decode bytes using declared charset "$targetName"',
        detectedEncoding: targetName,
      );
    }

    if (_hasUtf8Bom(bytes)) {
      return (
        text: _stripLeadingBom(utf8.decode(bytes, allowMalformed: true)),
        charsetName: 'utf-8',
      );
    }

    try {
      return (
        text: _stripLeadingBom(utf8.decode(bytes, allowMalformed: false)),
        charsetName: 'utf-8',
      );
    } on FormatException {
      try {
        return (
          text: _decodeGb18030(bytes, allowMalformed: false),
          charsetName: 'gb18030',
        );
      } on FormatException {
        return (
          text: _stripLeadingBom(utf8.decode(bytes, allowMalformed: true)),
          charsetName: 'utf-8-lossy',
        );
      }
    }
  }

  static Map<String, dynamic> _mergeHeaders({
    required Map<String, String> defaultHeaders,
    required Map<String, String>? requestHeaders,
    required String method,
    required Object? data,
  }) {
    final result = LinkedHashMap<String, dynamic>(
      equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
      hashCode: (k) => k.toLowerCase().hashCode,
    );

    for (final entry in defaultHeaders.entries) {
      result[entry.key] = entry.value;
    }
    if (requestHeaders != null) {
      for (final entry in requestHeaders.entries) {
        result[entry.key] = entry.value;
      }
    }

    if (!result.containsKey(HttpHeaders.userAgentHeader)) {
      result[HttpHeaders.userAgentHeader] = defaultUserAgent;
    }
    if (result.containsKey(HttpHeaders.cookieHeader)) {
      final cookieVal = result.remove(HttpHeaders.cookieHeader);
      result[HttpHeaders.cookieHeader] = cookieVal;
    }
    if (method == 'POST' &&
        !result.containsKey(HttpHeaders.contentTypeHeader) &&
        data is String) {
      result[HttpHeaders.contentTypeHeader] =
          'application/x-www-form-urlencoded';
    }
    return result;
  }

  static String? _tryDecodeDeclaredCharset(
    Uint8List bytes,
    String charsetName,
  ) {
    if (charsetName == 'utf-8' || charsetName == 'utf8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (charsetName == 'gbk' ||
        charsetName == 'gb2312' ||
        charsetName == 'gb18030' ||
        charsetName == 'cp936') {
      return _decodeGb18030(bytes, allowMalformed: true);
    }
    final codec = Charset.getByName(charsetName);
    if (codec != null) {
      return codec.decode(bytes);
    }
    return null;
  }

  static Uint16List? _gbkFastTable;

  static Uint16List _getGbkFastTable() {
    final existing = _gbkFastTable;
    if (existing != null) return existing;

    final table = Uint16List(65536);
    final keys = <int>[];
    final batch = BytesBuilder(copy: false);
    for (var b1 = 0x81; b1 <= 0xFE; b1++) {
      for (var b2 = 0x40; b2 <= 0xFE; b2++) {
        if (b2 == 0x7F) continue;
        keys.add((b1 << 8) | b2);
        batch.addByte(b1);
        batch.addByte(b2);
      }
    }
    final decoded = gbk.decode(batch.takeBytes(), allowMalformed: true);
    final len = decoded.length < keys.length ? decoded.length : keys.length;
    for (var i = 0; i < len; i++) {
      final codeUnit = decoded.codeUnitAt(i);
      if (codeUnit != 0xFFFD) {
        table[keys[i]] = codeUnit;
      }
    }
    _gbkFastTable = table;
    return table;
  }

  static String _decodeGb18030(
    Uint8List bytes, {
    required bool allowMalformed,
  }) {
    var allAscii = true;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] >= 0x80) {
        allAscii = false;
        break;
      }
    }
    if (allAscii) {
      return String.fromCharCodes(bytes);
    }

    final table = _getGbkFastTable();
    final out = Uint16List(bytes.length);
    var outLen = 0;
    var i = 0;

    while (i < bytes.length) {
      final b1 = bytes[i];
      if (b1 <= 0x7F) {
        out[outLen++] = b1;
        i++;
        continue;
      }
      if (b1 < 0x81 || b1 > 0xFE || i + 1 >= bytes.length) {
        if (!allowMalformed) {
          throw FormatException(
            'Invalid GB18030 byte at offset $i',
            bytes,
            i,
          );
        }
        out[outLen++] = 0xFFFD;
        i++;
        continue;
      }

      final b2 = bytes[i + 1];
      if (b2 >= 0x30 && b2 <= 0x39) {
        if (i + 3 < bytes.length) {
          final b3 = bytes[i + 2];
          final b4 = bytes[i + 3];
          if (b3 >= 0x81 && b3 <= 0xFE && b4 >= 0x30 && b4 <= 0x39) {
            final linear =
                (((b1 - 0x81) * 10 + (b2 - 0x30)) * 126 + (b3 - 0x81)) * 10 +
                (b4 - 0x30);
            if (linear >= 189000 && linear <= 1237575) {
              final cp = 0x10000 + (linear - 189000);
              out[outLen++] = 0xD800 + ((cp - 0x10000) >> 10);
              out[outLen++] = 0xDC00 + ((cp - 0x10000) & 0x3FF);
              i += 4;
              continue;
            }
            if (linear >= 0 && linear <= 39419) {
              out[outLen++] = 0xFFFD;
              i += 4;
              continue;
            }
          }
        }
        if (!allowMalformed) {
          throw FormatException(
            'Malformed 4-byte GB18030 sequence at offset $i',
            bytes,
            i,
          );
        }
        out[outLen++] = 0xFFFD;
        i++;
        continue;
      }

      final mapped = table[(b1 << 8) | b2];
      if (mapped != 0) {
        out[outLen++] = mapped;
        i += 2;
      } else if ((b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFE)) {
        if (!allowMalformed) {
          throw FormatException(
            'Unmapped GBK byte pair 0x${((b1 << 8) | b2).toRadixString(16)}',
            bytes,
            i,
          );
        }
        out[outLen++] = 0xFFFD;
        i += 2;
      } else {
        if (!allowMalformed) {
          throw FormatException(
            'Invalid GB18030 trail byte at offset $i',
            bytes,
            i,
          );
        }
        out[outLen++] = 0xFFFD;
        i++;
      }
    }

    return String.fromCharCodes(out, 0, outLen);
  }

  static bool _hasUtf8Bom(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
  }

  static String _stripLeadingBom(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  static String? _normalizeCharsetName(String? raw) {
    if (raw == null) return null;
    final trimmed = raw
        .trim()
        .toLowerCase()
        .replaceAll('"', '')
        .replaceAll("'", '');
    if (trimmed.isEmpty) return null;
    if (trimmed == 'utf8') return 'utf-8';
    return trimmed;
  }

  static String? _extractCharsetFromContentType(String? header) {
    if (header == null || header.isEmpty) return null;
    final match = RegExp(
      r'charset\s*=\s*([^\s;,]+)',
      caseSensitive: false,
    ).firstMatch(header);
    return _normalizeCharsetName(match?.group(1));
  }

  static String? _sniffMetaCharset(Uint8List bytes) {
    final headLen = bytes.length < 4096 ? bytes.length : 4096;
    final asciiHead = latin1.decode(bytes.sublist(0, headLen));
    final metaCharset = RegExp(
      r'''<meta[^>]+charset\s*=\s*["']?\s*([a-zA-Z0-9_-]+)''',
      caseSensitive: false,
    ).firstMatch(asciiHead);
    if (metaCharset != null) {
      return _normalizeCharsetName(metaCharset.group(1));
    }
    final xmlEncoding = RegExp(
      r'''<\?xml[^>]+encoding\s*=\s*["']([a-zA-Z0-9_-]+)["']''',
      caseSensitive: false,
    ).firstMatch(asciiHead);
    return _normalizeCharsetName(xmlEncoding?.group(1));
  }

  void close() {
    _dio.close(force: true);
  }
}
