import '../value_objects/sanitize_context.dart';

/// Unified chapter text sanitization pipeline.
///
/// Applies global, source-scoped, and book-scoped replacement rules in priority
/// order and normalizes paragraph indentation/whitespace without mutating the
/// cached raw chapter text on disk.
abstract interface class ContentSanitizer {
  Future<String> sanitize(String rawContent, SanitizeContext context);
}
