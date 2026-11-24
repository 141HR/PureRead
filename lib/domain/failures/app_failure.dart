/// Sealed domain failure hierarchy for PureRead.
///
/// Engine and infrastructure layers must map low-level exceptions into an
/// [AppFailure] subclass at layer boundaries so uncaught exceptions never crash
/// the UI.
sealed class AppFailure implements Exception {
  /// Human-readable error summary suitable for logs or UI feedback.
  String get message;

  /// Original underlying error object, if any.
  Object? get cause;

  /// Stack trace captured when the failure occurred, if available.
  StackTrace? get stackTrace;

  const AppFailure();

  @override
  String toString() => '$runtimeType: $message';
}

/// Network transport failure (timeout, DNS resolution, HTTP 4xx/5xx).
final class NetworkFailure extends AppFailure {
  @override
  final String message;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  final int? statusCode;
  final String? url;
  final bool isTimeout;

  const NetworkFailure({
    required this.message,
    this.statusCode,
    this.url,
    this.isTimeout = false,
    this.cause,
    this.stackTrace,
  });
}

/// Book source selector or extraction failure (CSS/XPath/JSONPath/regex miss).
final class SourceParseFailure extends AppFailure {
  @override
  final String message;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  final String? sourceId;
  final String? step;
  final String? rule;

  const SourceParseFailure({
    required this.message,
    this.sourceId,
    this.step,
    this.rule,
    this.cause,
    this.stackTrace,
  });
}

/// Failure raised when a Legado rule relies on unsupported advanced features
/// such as `webView: true` or unimplemented `java.*` host APIs.
final class UnsupportedLegadoRuleFailure extends AppFailure {
  @override
  final String message;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  final String? sourceId;
  final String feature;

  const UnsupportedLegadoRuleFailure({
    required this.message,
    required this.feature,
    this.sourceId,
    this.cause,
    this.stackTrace,
  });
}

/// Embedded JavaScript sandbox syntax, runtime, or timeout failure.
final class JsExecutionFailure extends AppFailure {
  @override
  final String message;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  final String? sourceId;
  final String? jsStackTrace;
  final bool isTimeout;

  const JsExecutionFailure({
    required this.message,
    this.sourceId,
    this.jsStackTrace,
    this.isTimeout = false,
    this.cause,
    this.stackTrace,
  });
}

/// Text encoding detection or decoding failure for local files or responses.
final class EncodingFailure extends AppFailure {
  @override
  final String message;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  final String? filePath;
  final String? detectedEncoding;

  const EncodingFailure({
    required this.message,
    this.filePath,
    this.detectedEncoding,
    this.cause,
    this.stackTrace,
  });
}

/// Local filesystem read/write or missing source file failure.
final class FileAccessFailure extends AppFailure {
  @override
  final String message;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  final String? filePath;

  const FileAccessFailure({
    required this.message,
    this.filePath,
    this.cause,
    this.stackTrace,
  });
}

/// SQLite persistence or schema migration failure.
final class DatabaseFailure extends AppFailure {
  @override
  final String message;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  final String? backupSnapshotPath;

  const DatabaseFailure({
    required this.message,
    this.backupSnapshotPath,
    this.cause,
    this.stackTrace,
  });
}

/// Cooperative cancellation signal converted into a typed failure.
final class CancelledFailure extends AppFailure {
  @override
  final String message;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  const CancelledFailure({
    this.message = 'Operation cancelled',
    this.cause,
    this.stackTrace,
  });
}
