import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../../domain/domain.dart';

class HttpFetchResult {
  final String body;
  final int statusCode;
  final String finalUrl;
  final String detectedCharset;
  final Map<String, String> headers;

  const HttpFetchResult({
    required this.body,
    required this.statusCode,
    required this.finalUrl,
    required this.detectedCharset,
    required this.headers,
  });
}

class SourceHttpClient {
  final Dio _dio;
  final CookieJar cookieJar;

  SourceHttpClient({
    Dio? dio,
    CookieJar? cookieJar,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 15),
  })  : cookieJar = cookieJar ?? CookieJar(),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: connectTimeout,
                receiveTimeout: receiveTimeout,
                responseType: ResponseType.bytes,
                validateStatus: (status) => status != null && status < 500,
              ),
            ) {
    if (!_dio.interceptors.any((i) => i is CookieManager)) {
      _dio.interceptors.add(CookieManager(this.cookieJar));
    }
  }

  Future<HttpFetchResult> request(
    String url, {
    String method = 'GET',
    Object? data,
    Map<String, String>? headers,
    String? charsetOverride,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final dioCancel = CancelToken();
    void onCancel() {
      if (!dioCancel.isCancelled) {
        dioCancel.cancel('Cancelled by PureRead CancellationToken');
      }
    }

    cancelToken?.addListener(onCancel);

    try {
      final upperMethod = method.toUpperCase();
      final mergedHeaders = <String, dynamic>{...?headers};
      if (upperMethod == 'POST' &&
          !mergedHeaders.keys
              .any((k) => k.toLowerCase() == 'content-type') &&
          data is String) {
        mergedHeaders['Content-Type'] = 'application/x-www-form-urlencoded';
      }

      final response = await _dio.request<List<int>>(
        url,
        data: data,
        cancelToken: dioCancel,
        options: Options(
          method: upperMethod,
          headers: mergedHeaders.isEmpty ? null : mergedHeaders,
          responseType: ResponseType.bytes,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 400) {
        throw NetworkFailure(
          message: 'HTTP $statusCode from $url',
          statusCode: statusCode,
          url: url,
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
          flatHeaders[name] = values.join(', ');
        }
      });

      return HttpFetchResult(
        body: decoded.text,
        statusCode: statusCode,
        finalUrl: response.realUri.toString(),
        detectedCharset: decoded.charsetName,
        headers: flatHeaders,
      );
    } on DioException catch (e, st) {
      if (e.type == DioExceptionType.cancel ||
          (cancelToken?.isCancelled ?? false)) {
        throw CancelledFailure(cause: e, stackTrace: st);
      }
      final isTimeout = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      throw NetworkFailure(
        message: 'Network request failed ($url): ${e.message ?? e.type.name}',
        statusCode: e.response?.statusCode,
        url: url,
        isTimeout: isTimeout,
        cause: e,
        stackTrace: st,
      );
    } finally {
      cancelToken?.removeListener(onCancel);
    }
  }

  static ({String text, String charsetName}) decodeResponseBytes(
    Uint8List bytes, {
    String? explicitCharset,
    String? contentTypeHeader,
  }) {
    if (bytes.isEmpty) {
      return (text: '', charsetName: 'utf-8');
    }

    final targetName = _normalizeCharsetName(explicitCharset) ??
        _extractCharsetFromContentType(contentTypeHeader) ??
        _sniffMetaCharset(bytes);

    if (targetName != null) {
      final decoded = _tryDecodeByName(bytes, targetName);
      if (decoded != null) {
        return (text: decoded, charsetName: targetName);
      }
      throw EncodingFailure(
        message: 'Failed to decode bytes using declared charset "$targetName"',
        detectedEncoding: targetName,
      );
    }

    try {
      return (
        text: utf8.decode(bytes, allowMalformed: false),
        charsetName: 'utf-8',
      );
    } on FormatException {
      try {
        return (
          text: gbk.decode(bytes, allowMalformed: false),
          charsetName: 'gbk',
        );
      } on FormatException {
        return (
          text: utf8.decode(bytes, allowMalformed: true),
          charsetName: 'utf-8-lossy',
        );
      }
    }
  }

  static String? _tryDecodeByName(Uint8List bytes, String charsetName) {
    if (charsetName == 'utf-8' || charsetName == 'utf8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (charsetName == 'gbk' ||
        charsetName == 'gb2312' ||
        charsetName == 'gb18030') {
      return gbk.decode(bytes, allowMalformed: true);
    }
    final codec = Charset.getByName(charsetName);
    if (codec != null) {
      return codec.decode(bytes);
    }
    return null;
  }

  static String? _normalizeCharsetName(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim().toLowerCase().replaceAll('"', '').replaceAll("'", '');
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static String? _extractCharsetFromContentType(String? header) {
    if (header == null || header.isEmpty) return null;
    final match = RegExp(
      r'charset\s*=\s*([^\s;]+)',
      caseSensitive: false,
    ).firstMatch(header);
    return _normalizeCharsetName(match?.group(1));
  }

  static String? _sniffMetaCharset(Uint8List bytes) {
    final headLen = bytes.length < 2048 ? bytes.length : 2048;
    final asciiHead = latin1.decode(bytes.sublist(0, headLen));
    final metaCharset = RegExp(
      r'''<meta[^>]+charset\s*=\s*["']?\s*([a-zA-Z0-9_-]+)''',
      caseSensitive: false,
    ).firstMatch(asciiHead);
    return _normalizeCharsetName(metaCharset?.group(1));
  }

  void close() {
    _dio.close(force: true);
  }
}
