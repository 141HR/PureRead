import '../value_objects/cancellation_token.dart';

class JsExecutionResult {
  final String value;
  final List<String> logs;
  final int elapsedMs;

  const JsExecutionResult({
    required this.value,
    this.logs = const [],
    this.elapsedMs = 0,
  });
}

abstract interface class JsRuntime {
  Future<JsExecutionResult> evaluate(
    String script, {
    Map<String, Object?> bindings = const {},
    Duration timeout = const Duration(seconds: 5),
    CancellationToken? cancelToken,
  });

  Future<void> dispose();
}
