/// Diagnostic execution trace returned by [BookProvider] operations.
class SourceDebugTrace {
  final String step;
  final int elapsedMs;
  final int? httpStatus;
  final String? requestUrl;
  final String? matchedPreview;
  final List<String> logs;
  final String? errorMessage;

  const SourceDebugTrace({
    required this.step,
    required this.elapsedMs,
    this.httpStatus,
    this.requestUrl,
    this.matchedPreview,
    this.logs = const [],
    this.errorMessage,
  });
}
