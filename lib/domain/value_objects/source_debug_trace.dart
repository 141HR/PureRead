/// Diagnostic execution trace returned by [BookProvider] operations.
class SourceDebugTrace {
  /// Provider step name (`search`, `detail`, `toc`, or `content`).
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceDebugTrace &&
          runtimeType == other.runtimeType &&
          step == other.step &&
          elapsedMs == other.elapsedMs &&
          httpStatus == other.httpStatus &&
          requestUrl == other.requestUrl &&
          matchedPreview == other.matchedPreview &&
          _stringListEquals(logs, other.logs) &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        step,
        elapsedMs,
        httpStatus,
        requestUrl,
        matchedPreview,
        Object.hashAll(logs),
        errorMessage,
      );
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
