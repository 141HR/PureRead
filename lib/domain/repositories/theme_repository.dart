import '../entities/app_setting.dart';
import '../entities/reader_theme.dart';

/// Repository contract for reader themes and global application settings.
abstract interface class ThemeRepository {
  Stream<List<ReaderTheme>> watchThemes();

  Future<List<ReaderTheme>> listThemes();

  Future<ReaderTheme?> getThemeById(String themeId);

  Future<void> saveTheme(ReaderTheme theme);

  Future<void> deleteTheme(String themeId);

  Future<AppSetting?> getSetting(String key);

  Future<List<AppSetting>> listSettings();

  Future<void> saveSetting(AppSetting setting);
}
