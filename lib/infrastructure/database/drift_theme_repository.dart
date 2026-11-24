import 'package:drift/drift.dart';

import '../../domain/entities/app_setting.dart';
import '../../domain/entities/reader_theme.dart';
import '../../domain/repositories/theme_repository.dart';
import 'app_database.dart';
import 'drift_mappers.dart';

/// Drift-backed implementation of [ThemeRepository].
class DriftThemeRepository implements ThemeRepository {
  final AppDatabase _db;

  const DriftThemeRepository(this._db);

  SimpleSelectStatement<$ReaderThemesTable, ReaderThemeRow> _themesQuery() {
    return _db.select(_db.readerThemes)..orderBy([
      (t) => OrderingTerm.desc(t.isBuiltin),
      (t) => OrderingTerm.asc(t.updatedAt),
      (t) => OrderingTerm.asc(t.name),
    ]);
  }

  @override
  Stream<List<ReaderTheme>> watchThemes() {
    return guardDbStream(
      'watchThemes',
      () => _themesQuery().watch().map(
        (rows) => rows.map(readerThemeFromRow).toList(growable: false),
      ),
    );
  }

  @override
  Future<List<ReaderTheme>> listThemes() {
    return guardDbCall('listThemes', () async {
      final rows = await _themesQuery().get();
      return rows.map(readerThemeFromRow).toList(growable: false);
    });
  }

  @override
  Future<ReaderTheme?> getThemeById(String themeId) {
    return guardDbCall('getThemeById', () async {
      final row = await (_db.select(
        _db.readerThemes,
      )..where((t) => t.id.equals(themeId))).getSingleOrNull();
      return row == null ? null : readerThemeFromRow(row);
    });
  }

  @override
  Future<void> saveTheme(ReaderTheme theme) {
    return guardDbCall('saveTheme', () async {
      await _db
          .into(_db.readerThemes)
          .insertOnConflictUpdate(readerThemeToCompanion(theme));
    });
  }

  @override
  Future<void> deleteTheme(String themeId) {
    return guardDbCall('deleteTheme', () async {
      await (_db.delete(
        _db.readerThemes,
      )..where((t) => t.id.equals(themeId))).go();
    });
  }

  @override
  Future<AppSetting?> getSetting(String key) {
    return guardDbCall('getSetting', () async {
      final row = await (_db.select(
        _db.appSettings,
      )..where((s) => s.key.equals(key))).getSingleOrNull();
      return row == null ? null : appSettingFromRow(row);
    });
  }

  @override
  Future<List<AppSetting>> listSettings() {
    return guardDbCall('listSettings', () async {
      final rows = await (_db.select(
        _db.appSettings,
      )..orderBy([(s) => OrderingTerm.asc(s.key)])).get();
      return rows.map(appSettingFromRow).toList(growable: false);
    });
  }

  @override
  Future<void> saveSetting(AppSetting setting) {
    return guardDbCall('saveSetting', () async {
      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(appSettingToCompanion(setting));
    });
  }
}
