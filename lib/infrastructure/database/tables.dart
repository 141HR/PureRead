import 'package:drift/drift.dart';

/// Bookshelf groups table (`book_groups`).
@DataClassName('BookGroupRow')
class BookGroups extends Table {
  @override
  String get tableName => 'book_groups';

  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get id => text()();

  TextColumn get name => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();
}

/// Primary books metadata table (`books`).
@DataClassName('BookRow')
@TableIndex(
  name: 'idx_books_shelf_sort',
  columns: {
    #groupId,
    IndexedColumn(#isPinned, orderBy: OrderingMode.desc),
    IndexedColumn(#lastReadAt, orderBy: OrderingMode.desc),
  },
)
@TableIndex(
  name: 'idx_books_source_url',
  columns: {#sourceId, #originBookUrl},
)
class Books extends Table {
  @override
  String get tableName => 'books';

  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get id => text()();

  TextColumn get sourceId => text().nullable()();

  TextColumn get providerType => text()();

  TextColumn get originBookUrl => text().nullable()();

  TextColumn get tocUrl => text().nullable()();

  TextColumn get title => text()();

  TextColumn get author => text().withDefault(const Constant(''))();

  TextColumn get coverPath => text().nullable()();

  TextColumn get intro => text().withDefault(const Constant(''))();

  TextColumn get localFilePath => text().nullable()();

  TextColumn get fileEncoding => text().nullable()();

  IntColumn get fileSizeBytes => integer().nullable()();

  TextColumn get fileHash => text().nullable()();

  TextColumn get groupId => text()
      .nullable()
      .references(BookGroups, #id, onDelete: KeyAction.setNull)();

  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  IntColumn get totalChapters => integer().withDefault(const Constant(0))();

  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  TextColumn get lastChapterTitle => text().withDefault(const Constant(''))();

  IntColumn get lastReadAt => integer().nullable()();

  IntColumn get latestChapterAt => integer().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();
}

/// Unified chapter index metadata table (`chapters`).
@DataClassName('ChapterRow')
@TableIndex(
  name: 'idx_chapters_book_index',
  columns: {#bookId, #chapterIndex},
  unique: true,
)
class Chapters extends Table {
  @override
  String get tableName => 'chapters';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  IntColumn get chapterIndex => integer()();

  TextColumn get title => text()();

  TextColumn get url => text().nullable()();

  IntColumn get byteStart => integer().nullable()();

  IntColumn get byteEnd => integer().nullable()();

  TextColumn get epubHref => text().nullable()();

  BoolColumn get isCached => boolean().withDefault(const Constant(false))();

  TextColumn get cacheKey => text().nullable()();

  IntColumn get wordCount => integer().withDefault(const Constant(0))();

  IntColumn get updatedAt => integer()();
}

/// Per-book exact reading progress table (`reading_progress`).
@DataClassName('ReadingProgressRow')
class ReadingProgressRecords extends Table {
  @override
  String get tableName => 'reading_progress';

  @override
  Set<Column<Object>> get primaryKey => {bookId};

  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  IntColumn get chapterIndex => integer().withDefault(const Constant(0))();

  IntColumn get charOffset => integer().withDefault(const Constant(0))();

  TextColumn get chapterTitleSnapshot =>
      text().withDefault(const Constant(''))();

  RealColumn get progressPercent => real().withDefault(const Constant(0.0))();

  IntColumn get readingDurationSec => integer().withDefault(const Constant(0))();

  IntColumn get updatedAt => integer()();

  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

/// Bookmarks and reader annotations table (`bookmarks`).
@DataClassName('BookmarkRow')
@TableIndex(
  name: 'idx_bookmarks_book_pos',
  columns: {#bookId, #chapterIndex, #charOffset},
)
class Bookmarks extends Table {
  @override
  String get tableName => 'bookmarks';

  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get id => text()();

  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  IntColumn get chapterIndex => integer()();

  IntColumn get charOffset => integer()();

  TextColumn get excerpt => text()();

  TextColumn get note => text().withDefault(const Constant(''))();

  IntColumn get createdAt => integer()();
}

/// Online book source definitions table (`book_sources`).
@DataClassName('BookSourceRow')
@TableIndex(
  name: 'idx_sources_enabled_weight',
  columns: {#enabled, IndexedColumn(#weight, orderBy: OrderingMode.desc)},
)
class BookSources extends Table {
  @override
  String get tableName => 'book_sources';

  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get groupName => text().withDefault(const Constant('默认'))();

  TextColumn get engineType => text()();

  TextColumn get baseUrl => text()();

  TextColumn get rawDefinition => text()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  IntColumn get weight => integer().withDefault(const Constant(0))();

  IntColumn get rateLimitMs => integer().withDefault(const Constant(500))();

  TextColumn get lastCheckStatus =>
      text().withDefault(const Constant('unknown'))();

  TextColumn get lastErrorSummary => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();
}

/// Content sanitization rules table (`replace_rules`).
@DataClassName('ReplaceRuleRow')
@TableIndex(
  name: 'idx_replace_rules_active',
  columns: {#enabled, #scopeType, #scopeTargetId, #sortOrder},
)
class ReplaceRules extends Table {
  @override
  String get tableName => 'replace_rules';

  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get groupName => text().withDefault(const Constant('通用'))();

  TextColumn get pattern => text()();

  TextColumn get replacement => text().withDefault(const Constant(''))();

  BoolColumn get isRegex => boolean().withDefault(const Constant(true))();

  TextColumn get scopeType => text().withDefault(const Constant('global'))();

  TextColumn get scopeTargetId => text().nullable()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  IntColumn get updatedAt => integer()();
}

/// Reader theme and typography presets table (`reader_themes`).
@DataClassName('ReaderThemeRow')
class ReaderThemes extends Table {
  @override
  String get tableName => 'reader_themes';

  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get id => text()();

  TextColumn get name => text()();

  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();

  BoolColumn get isDark => boolean().withDefault(const Constant(false))();

  IntColumn get bgColor => integer()();

  IntColumn get textColor => integer()();

  IntColumn get secondaryTextColor => integer()();

  TextColumn get bgTexturePath => text().nullable()();

  TextColumn get fontFamily => text().withDefault(const Constant('system'))();

  TextColumn get fontPath => text().nullable()();

  RealColumn get fontSize => real().withDefault(const Constant(18.0))();

  IntColumn get fontWeight => integer().withDefault(const Constant(400))();

  RealColumn get lineHeight => real().withDefault(const Constant(1.65))();

  RealColumn get paragraphSpacing => real().withDefault(const Constant(12.0))();

  RealColumn get letterSpacing => real().withDefault(const Constant(0.2))();

  IntColumn get paragraphIndentChars =>
      integer().withDefault(const Constant(2))();

  RealColumn get marginHorizontal => real().withDefault(const Constant(20.0))();

  RealColumn get marginVertical => real().withDefault(const Constant(24.0))();

  TextColumn get columnMode => text().withDefault(const Constant('auto'))();

  RealColumn get maxContentWidth => real().withDefault(const Constant(760.0))();

  TextColumn get pageTurnMode => text().withDefault(const Constant('cover'))();

  BoolColumn get enablePunctuationHanging =>
      boolean().withDefault(const Constant(true))();

  BoolColumn get enableCjkSpacing =>
      boolean().withDefault(const Constant(true))();

  IntColumn get updatedAt => integer()();
}

/// Global key-value application settings table (`app_settings`).
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  @override
  String get tableName => 'app_settings';

  @override
  Set<Column<Object>> get primaryKey => {key};

  TextColumn get key => text()();

  TextColumn get value => text()();

  IntColumn get updatedAt => integer()();
}
