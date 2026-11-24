import 'package:drift/drift.dart';

import '../../domain/entities/book_source.dart';
import '../../domain/entities/replace_rule.dart';
import '../../domain/repositories/source_repository.dart';
import 'app_database.dart';
import 'drift_mappers.dart';

/// Drift-backed implementation of [SourceRepository].
class DriftSourceRepository implements SourceRepository {
  final AppDatabase _db;

  const DriftSourceRepository(this._db);

  SimpleSelectStatement<$BookSourcesTable, BookSourceRow> _sourcesQuery({
    bool enabledOnly = false,
  }) {
    final query = _db.select(_db.bookSources);
    if (enabledOnly) {
      query.where((s) => s.enabled.equals(true));
    }
    query.orderBy([
      (s) => OrderingTerm.desc(s.weight),
      (s) => OrderingTerm.asc(s.name),
    ]);
    return query;
  }

  @override
  Stream<List<BookSource>> watchSources() {
    return guardDbStream(
      'watchSources',
      () => _sourcesQuery().watch().map(
        (rows) => rows.map(bookSourceFromRow).toList(growable: false),
      ),
    );
  }

  @override
  Future<List<BookSource>> listSources({bool enabledOnly = false}) {
    return guardDbCall('listSources', () async {
      final rows = await _sourcesQuery(enabledOnly: enabledOnly).get();
      return rows.map(bookSourceFromRow).toList(growable: false);
    });
  }

  @override
  Future<BookSource?> getSourceById(String sourceId) {
    return guardDbCall('getSourceById', () async {
      final row = await (_db.select(
        _db.bookSources,
      )..where((s) => s.id.equals(sourceId))).getSingleOrNull();
      return row == null ? null : bookSourceFromRow(row);
    });
  }

  @override
  Future<void> saveSource(BookSource source) {
    return guardDbCall('saveSource', () async {
      await _db
          .into(_db.bookSources)
          .insertOnConflictUpdate(bookSourceToCompanion(source));
    });
  }

  @override
  Future<void> saveSources(List<BookSource> sources) {
    return guardDbCall('saveSources', () async {
      if (sources.isEmpty) {
        return;
      }
      await _db.transaction(() async {
        await _db.batch((b) {
          b.insertAllOnConflictUpdate(
            _db.bookSources,
            sources.map(bookSourceToCompanion).toList(growable: false),
          );
        });
      });
    });
  }

  @override
  Future<void> deleteSource(String sourceId) {
    return guardDbCall('deleteSource', () async {
      await (_db.delete(
        _db.bookSources,
      )..where((s) => s.id.equals(sourceId))).go();
    });
  }

  @override
  Future<List<ReplaceRule>> listReplaceRules({
    bool enabledOnly = false,
    String? sourceId,
    String? bookId,
  }) {
    return guardDbCall('listReplaceRules', () async {
      final query = _db.select(_db.replaceRules);
      query.where((r) {
        Expression<bool> predicate = const Constant(true);
        if (enabledOnly) {
          predicate = predicate & r.enabled.equals(true);
        }
        if (sourceId != null || bookId != null) {
          Expression<bool> scopePredicate = r.scopeType.equals('global');
          if (sourceId != null) {
            scopePredicate =
                scopePredicate |
                (r.scopeType.equals('source') &
                    r.scopeTargetId.equals(sourceId));
          }
          if (bookId != null) {
            scopePredicate =
                scopePredicate |
                (r.scopeType.equals('book') & r.scopeTargetId.equals(bookId));
          }
          predicate = predicate & scopePredicate;
        }
        return predicate;
      });
      query.orderBy([
        (r) => OrderingTerm.asc(r.sortOrder),
        (r) => OrderingTerm.asc(r.updatedAt),
      ]);

      final rows = await query.get();
      final rules = rows.map(replaceRuleFromRow).toList(growable: false);
      rules.sort((a, b) {
        final scopeCmp = _scopeRank(a.scopeType).compareTo(
          _scopeRank(b.scopeType),
        );
        if (scopeCmp != 0) return scopeCmp;
        final orderCmp = a.sortOrder.compareTo(b.sortOrder);
        if (orderCmp != 0) return orderCmp;
        return a.updatedAt.compareTo(b.updatedAt);
      });
      return rules;
    });
  }

  static int _scopeRank(RuleScopeType scopeType) {
    return switch (scopeType) {
      RuleScopeType.global => 0,
      RuleScopeType.source => 1,
      RuleScopeType.book => 2,
    };
  }

  @override
  Future<void> saveReplaceRule(ReplaceRule rule) {
    return guardDbCall('saveReplaceRule', () async {
      await _db
          .into(_db.replaceRules)
          .insertOnConflictUpdate(replaceRuleToCompanion(rule));
    });
  }

  @override
  Future<void> deleteReplaceRule(String ruleId) {
    return guardDbCall('deleteReplaceRule', () async {
      await (_db.delete(
        _db.replaceRules,
      )..where((r) => r.id.equals(ruleId))).go();
    });
  }
}
