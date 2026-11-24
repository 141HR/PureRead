import '../entities/book_source.dart';
import '../entities/replace_rule.dart';

/// Repository contract for online book sources and content sanitization rules.
abstract interface class SourceRepository {
  Stream<List<BookSource>> watchSources();

  Future<List<BookSource>> listSources({bool enabledOnly = false});

  Future<BookSource?> getSourceById(String sourceId);

  Future<void> saveSource(BookSource source);

  Future<void> saveSources(List<BookSource> sources);

  Future<void> deleteSource(String sourceId);

  Future<List<ReplaceRule>> listReplaceRules({
    bool enabledOnly = false,
    String? sourceId,
    String? bookId,
  });

  Future<void> saveReplaceRule(ReplaceRule rule);

  Future<void> deleteReplaceRule(String ruleId);
}
