import '../../domain/entities/book_group.dart';
import '../../domain/entities/reader_theme.dart';

/// Default seed records populated when initializing a fresh database.
abstract final class DefaultDatabaseSeeds {
  static const String defaultGroupId = 'default';
  static const String defaultGroupName = '默认分组';

  static const String eyeCareIvoryId = 'eye_care_ivory';
  static const String parchmentWarmId = 'parchment_warm';
  static const String slateNightId = 'slate_night';
  static const String oledPureBlackId = 'oled_pure_black';

  /// Creates the default bookshelf group.
  static BookGroup defaultGroup(DateTime timestamp) {
    final utc = timestamp.toUtc();
    return BookGroup(
      id: defaultGroupId,
      name: defaultGroupName,
      sortOrder: 0,
      createdAt: utc,
      updatedAt: utc,
    );
  }

  /// Creates the 4 built-in reader themes.
  static List<ReaderTheme> builtInThemes(DateTime timestamp) {
    final utc = timestamp.toUtc();
    return [
      ReaderTheme(
        id: eyeCareIvoryId,
        name: '米白护眼',
        isBuiltin: true,
        isDark: false,
        bgColor: 0xFFF7F4EC,
        textColor: 0xFF262626,
        secondaryTextColor: 0xFF737068,
        updatedAt: utc,
      ),
      ReaderTheme(
        id: parchmentWarmId,
        name: '羊皮纸感',
        isBuiltin: true,
        isDark: false,
        bgColor: 0xFFF5F0E6,
        textColor: 0xFF2B2620,
        secondaryTextColor: 0xFF7A7063,
        updatedAt: utc,
      ),
      ReaderTheme(
        id: slateNightId,
        name: '静谧暗灰',
        isBuiltin: true,
        isDark: true,
        bgColor: 0xFF1E2228,
        textColor: 0xFFD0D6DE,
        secondaryTextColor: 0xFF838C99,
        updatedAt: utc,
      ),
      ReaderTheme(
        id: oledPureBlackId,
        name: 'OLED 纯黑',
        isBuiltin: true,
        isDark: true,
        bgColor: 0xFF000000,
        textColor: 0xFFB8BCC2,
        secondaryTextColor: 0xFF686D75,
        updatedAt: utc,
      ),
    ];
  }
}
