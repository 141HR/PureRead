/// Sealed domain failure hierarchy for PureRead PoC.
sealed class AppFailure implements Exception {
  String get message;
  Object? get cause;
  StackTrace? get stackTrace;

  const AppFailure();

  @override
  String toString() => '$runtimeType: $message';
}

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
