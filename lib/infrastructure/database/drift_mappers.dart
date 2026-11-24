import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';

import '../../domain/entities/app_setting.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/book_group.dart';
import '../../domain/entities/book_source.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/reader_theme.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/replace_rule.dart';
import '../../domain/failures/app_failure.dart';
import '../../domain/value_objects/pagination_config.dart';
import '../../domain/value_objects/provider_capabilities.dart';
import 'app_database.dart';

/// Executes [action] and converts any SQLite / Drift exception into a
/// [DatabaseFailure].
Future<T> guardDbCall<T>(
  String operation,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    throw _mapToDatabaseFailure(operation, error, stackTrace);
  }
}

/// Wraps a stream returned by [streamFactory] so synchronous creation errors and
/// async stream errors are converted into [DatabaseFailure].
Stream<T> guardDbStream<T>(
  String operation,
  Stream<T> Function() streamFactory,
) {
  try {
    return streamFactory().handleError((Object error, StackTrace stackTrace) {
      throw _mapToDatabaseFailure(operation, error, stackTrace);
    });
  } catch (error, stackTrace) {
    return Stream<T>.error(
      _mapToDatabaseFailure(operation, error, stackTrace),
      stackTrace,
    );
  }
}

DatabaseFailure _mapToDatabaseFailure(
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  if (error is DatabaseFailure) {
    return error;
  }
  if (error is DriftRemoteException && error.remoteCause is DatabaseFailure) {
    return error.remoteCause as DatabaseFailure;
  }
  if (error is DriftWrappedException && error.cause is DatabaseFailure) {
    return error.cause as DatabaseFailure;
  }
  if (error is CouldNotRollBackException && error.cause is DatabaseFailure) {
    return error.cause as DatabaseFailure;
  }
  return DatabaseFailure(
    message: '$operation failed: $error',
    cause: error,
    stackTrace: stackTrace,
  );
}

int toEpochMs(DateTime dateTime) => dateTime.toUtc().millisecondsSinceEpoch;

int? toEpochMsNullable(DateTime? dateTime) =>
    dateTime?.toUtc().millisecondsSinceEpoch;

DateTime fromEpochMs(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);

DateTime? fromEpochMsNullable(int? epochMs) => epochMs == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);

String providerTypeToDb(ProviderType type) {
  return switch (type) {
    ProviderType.localTxt => 'local_txt',
    ProviderType.localEpub => 'local_epub',
    ProviderType.jsPlugin => 'js_plugin',
    ProviderType.legado => 'legado',
  };
}

ProviderType providerTypeFromDb(String raw) {
  return switch (raw) {
    'local_txt' => ProviderType.localTxt,
    'local_epub' => ProviderType.localEpub,
    'js_plugin' => ProviderType.jsPlugin,
    'legado' => ProviderType.legado,
    _ => throw DatabaseFailure(message: 'Unknown provider_type: $raw'),
  };
}

String sourceEngineTypeToDb(SourceEngineType type) {
  return switch (type) {
    SourceEngineType.jsPlugin => 'js_plugin',
    SourceEngineType.legado => 'legado',
  };
}

SourceEngineType sourceEngineTypeFromDb(String raw) {
  return switch (raw) {
    'js_plugin' => SourceEngineType.jsPlugin,
    'legado' => SourceEngineType.legado,
    _ => throw DatabaseFailure(message: 'Unknown engine_type: $raw'),
  };
}

String sourceCheckStatusToDb(SourceCheckStatus status) {
  return switch (status) {
    SourceCheckStatus.unknown => 'unknown',
    SourceCheckStatus.ok => 'ok',
    SourceCheckStatus.error => 'error',
    SourceCheckStatus.unsupported => 'unsupported',
  };
}

SourceCheckStatus sourceCheckStatusFromDb(String raw) {
  return switch (raw) {
    'unknown' => SourceCheckStatus.unknown,
    'ok' => SourceCheckStatus.ok,
    'error' => SourceCheckStatus.error,
    'unsupported' => SourceCheckStatus.unsupported,
    _ => throw DatabaseFailure(message: 'Unknown last_check_status: $raw'),
  };
}

String ruleScopeTypeToDb(RuleScopeType scopeType) {
  return switch (scopeType) {
    RuleScopeType.global => 'global',
    RuleScopeType.source => 'source',
    RuleScopeType.book => 'book',
  };
}

RuleScopeType ruleScopeTypeFromDb(String raw) {
  return switch (raw) {
    'global' => RuleScopeType.global,
    'source' => RuleScopeType.source,
    'book' => RuleScopeType.book,
    _ => throw DatabaseFailure(message: 'Unknown scope_type: $raw'),
  };
}

String columnModeToDb(ColumnMode mode) {
  return switch (mode) {
    ColumnMode.auto => 'auto',
    ColumnMode.single => 'single',
    ColumnMode.double => 'double',
  };
}

ColumnMode columnModeFromDb(String raw) {
  return switch (raw) {
    'auto' => ColumnMode.auto,
    'single' => ColumnMode.single,
    'double' => ColumnMode.double,
    _ => throw DatabaseFailure(message: 'Unknown column_mode: $raw'),
  };
}

String pageTurnModeToDb(PageTurnMode mode) {
  return switch (mode) {
    PageTurnMode.none => 'none',
    PageTurnMode.slide => 'slide',
    PageTurnMode.cover => 'cover',
    PageTurnMode.scroll => 'scroll',
    PageTurnMode.simulation => 'simulation',
  };
}

PageTurnMode pageTurnModeFromDb(String raw) {
  return switch (raw) {
    'none' => PageTurnMode.none,
    'slide' => PageTurnMode.slide,
    'cover' => PageTurnMode.cover,
    'scroll' => PageTurnMode.scroll,
    'simulation' => PageTurnMode.simulation,
    _ => throw DatabaseFailure(message: 'Unknown page_turn_mode: $raw'),
  };
}

BookGroupsCompanion bookGroupToCompanion(BookGroup group) {
  return BookGroupsCompanion(
    id: Value(group.id),
    name: Value(group.name),
    sortOrder: Value(group.sortOrder),
    createdAt: Value(toEpochMs(group.createdAt)),
    updatedAt: Value(toEpochMs(group.updatedAt)),
  );
}

BookGroup bookGroupFromRow(BookGroupRow row) {
  return BookGroup(
    id: row.id,
    name: row.name,
    sortOrder: row.sortOrder,
    createdAt: fromEpochMs(row.createdAt),
    updatedAt: fromEpochMs(row.updatedAt),
  );
}

BooksCompanion bookToCompanion(Book book) {
  return BooksCompanion(
    id: Value(book.id),
    sourceId: Value(book.sourceId),
    providerType: Value(providerTypeToDb(book.providerType)),
    originBookUrl: Value(book.originBookUrl),
    tocUrl: Value(book.tocUrl),
    title: Value(book.title),
    author: Value(book.author),
    coverPath: Value(book.coverPath),
    intro: Value(book.intro),
    localFilePath: Value(book.localFilePath),
    fileEncoding: Value(book.fileEncoding),
    fileSizeBytes: Value(book.fileSizeBytes),
    fileHash: Value(book.fileHash),
    groupId: Value(book.groupId),
    isPinned: Value(book.isPinned),
    totalChapters: Value(book.totalChapters),
    unreadCount: Value(book.unreadCount),
    lastChapterTitle: Value(book.lastChapterTitle),
    lastReadAt: Value(toEpochMsNullable(book.lastReadAt)),
    latestChapterAt: Value(toEpochMsNullable(book.latestChapterAt)),
    createdAt: Value(toEpochMs(book.createdAt)),
    updatedAt: Value(toEpochMs(book.updatedAt)),
  );
}

Book bookFromRow(BookRow row) {
  return Book(
    id: row.id,
    sourceId: row.sourceId,
    providerType: providerTypeFromDb(row.providerType),
    originBookUrl: row.originBookUrl,
    tocUrl: row.tocUrl,
    title: row.title,
    author: row.author,
    coverPath: row.coverPath,
    intro: row.intro,
    localFilePath: row.localFilePath,
    fileEncoding: row.fileEncoding,
    fileSizeBytes: row.fileSizeBytes,
    fileHash: row.fileHash,
    groupId: row.groupId,
    isPinned: row.isPinned,
    totalChapters: row.totalChapters,
    unreadCount: row.unreadCount,
    lastChapterTitle: row.lastChapterTitle,
    lastReadAt: fromEpochMsNullable(row.lastReadAt),
    latestChapterAt: fromEpochMsNullable(row.latestChapterAt),
    createdAt: fromEpochMs(row.createdAt),
    updatedAt: fromEpochMs(row.updatedAt),
  );
}

ChaptersCompanion chapterToCompanion(String bookId, ChapterMeta chapter) {
  return ChaptersCompanion(
    id: chapter.id == null ? const Value.absent() : Value(chapter.id!),
    bookId: Value(bookId),
    chapterIndex: Value(chapter.chapterIndex),
    title: Value(chapter.title),
    url: Value(chapter.url),
    byteStart: Value(chapter.byteStart),
    byteEnd: Value(chapter.byteEnd),
    epubHref: Value(chapter.epubHref),
    isCached: Value(chapter.isCached),
    cacheKey: Value(chapter.cacheKey),
    wordCount: Value(chapter.wordCount),
    updatedAt: Value(toEpochMs(chapter.updatedAt)),
  );
}

ChapterMeta chapterFromRow(ChapterRow row) {
  return ChapterMeta(
    id: row.id,
    bookId: row.bookId,
    chapterIndex: row.chapterIndex,
    title: row.title,
    url: row.url,
    byteStart: row.byteStart,
    byteEnd: row.byteEnd,
    epubHref: row.epubHref,
    isCached: row.isCached,
    cacheKey: row.cacheKey,
    wordCount: row.wordCount,
    updatedAt: fromEpochMs(row.updatedAt),
  );
}

ReadingProgressRecordsCompanion readingProgressToCompanion(
  ReadingProgress progress,
) {
  return ReadingProgressRecordsCompanion(
    bookId: Value(progress.bookId),
    chapterIndex: Value(progress.chapterIndex),
    charOffset: Value(progress.charOffset),
    chapterTitleSnapshot: Value(progress.chapterTitleSnapshot),
    progressPercent: Value(progress.progressPercent),
    readingDurationSec: Value(progress.readingDurationSec),
    updatedAt: Value(toEpochMs(progress.updatedAt)),
    deviceId: Value(progress.deviceId),
  );
}

ReadingProgress readingProgressFromRow(ReadingProgressRow row) {
  return ReadingProgress(
    bookId: row.bookId,
    chapterIndex: row.chapterIndex,
    charOffset: row.charOffset,
    chapterTitleSnapshot: row.chapterTitleSnapshot,
    progressPercent: row.progressPercent,
    readingDurationSec: row.readingDurationSec,
    updatedAt: fromEpochMs(row.updatedAt),
    deviceId: row.deviceId,
  );
}

BookmarksCompanion bookmarkToCompanion(Bookmark bookmark) {
  return BookmarksCompanion(
    id: Value(bookmark.id),
    bookId: Value(bookmark.bookId),
    chapterIndex: Value(bookmark.chapterIndex),
    charOffset: Value(bookmark.charOffset),
    excerpt: Value(bookmark.excerpt),
    note: Value(bookmark.note),
    createdAt: Value(toEpochMs(bookmark.createdAt)),
  );
}

Bookmark bookmarkFromRow(BookmarkRow row) {
  return Bookmark(
    id: row.id,
    bookId: row.bookId,
    chapterIndex: row.chapterIndex,
    charOffset: row.charOffset,
    excerpt: row.excerpt,
    note: row.note,
    createdAt: fromEpochMs(row.createdAt),
  );
}

BookSourcesCompanion bookSourceToCompanion(BookSource source) {
  return BookSourcesCompanion(
    id: Value(source.id),
    name: Value(source.name),
    groupName: Value(source.groupName),
    engineType: Value(sourceEngineTypeToDb(source.engineType)),
    baseUrl: Value(source.baseUrl),
    rawDefinition: Value(source.rawDefinition),
    enabled: Value(source.enabled),
    weight: Value(source.weight),
    rateLimitMs: Value(source.rateLimitMs),
    lastCheckStatus: Value(sourceCheckStatusToDb(source.lastCheckStatus)),
    lastErrorSummary: Value(source.lastErrorSummary),
    createdAt: Value(toEpochMs(source.createdAt)),
    updatedAt: Value(toEpochMs(source.updatedAt)),
  );
}

BookSource bookSourceFromRow(BookSourceRow row) {
  return BookSource(
    id: row.id,
    name: row.name,
    groupName: row.groupName,
    engineType: sourceEngineTypeFromDb(row.engineType),
    baseUrl: row.baseUrl,
    rawDefinition: row.rawDefinition,
    enabled: row.enabled,
    weight: row.weight,
    rateLimitMs: row.rateLimitMs,
    lastCheckStatus: sourceCheckStatusFromDb(row.lastCheckStatus),
    lastErrorSummary: row.lastErrorSummary,
    createdAt: fromEpochMs(row.createdAt),
    updatedAt: fromEpochMs(row.updatedAt),
  );
}

ReplaceRulesCompanion replaceRuleToCompanion(ReplaceRule rule) {
  return ReplaceRulesCompanion(
    id: Value(rule.id),
    name: Value(rule.name),
    groupName: Value(rule.groupName),
    pattern: Value(rule.pattern),
    replacement: Value(rule.replacement),
    isRegex: Value(rule.isRegex),
    scopeType: Value(ruleScopeTypeToDb(rule.scopeType)),
    scopeTargetId: Value(rule.scopeTargetId),
    enabled: Value(rule.enabled),
    sortOrder: Value(rule.sortOrder),
    updatedAt: Value(toEpochMs(rule.updatedAt)),
  );
}

ReplaceRule replaceRuleFromRow(ReplaceRuleRow row) {
  return ReplaceRule(
    id: row.id,
    name: row.name,
    groupName: row.groupName,
    pattern: row.pattern,
    replacement: row.replacement,
    isRegex: row.isRegex,
    scopeType: ruleScopeTypeFromDb(row.scopeType),
    scopeTargetId: row.scopeTargetId,
    enabled: row.enabled,
    sortOrder: row.sortOrder,
    updatedAt: fromEpochMs(row.updatedAt),
  );
}

ReaderThemesCompanion readerThemeToCompanion(ReaderTheme theme) {
  return ReaderThemesCompanion(
    id: Value(theme.id),
    name: Value(theme.name),
    isBuiltin: Value(theme.isBuiltin),
    isDark: Value(theme.isDark),
    bgColor: Value(theme.bgColor),
    textColor: Value(theme.textColor),
    secondaryTextColor: Value(theme.secondaryTextColor),
    bgTexturePath: Value(theme.bgTexturePath),
    fontFamily: Value(theme.fontFamily),
    fontPath: Value(theme.fontPath),
    fontSize: Value(theme.fontSize),
    fontWeight: Value(theme.fontWeight),
    lineHeight: Value(theme.lineHeight),
    paragraphSpacing: Value(theme.paragraphSpacing),
    letterSpacing: Value(theme.letterSpacing),
    paragraphIndentChars: Value(theme.paragraphIndentChars),
    marginHorizontal: Value(theme.marginHorizontal),
    marginVertical: Value(theme.marginVertical),
    columnMode: Value(columnModeToDb(theme.columnMode)),
    maxContentWidth: Value(theme.maxContentWidth),
    pageTurnMode: Value(pageTurnModeToDb(theme.pageTurnMode)),
    enablePunctuationHanging: Value(theme.enablePunctuationHanging),
    enableCjkSpacing: Value(theme.enableCjkSpacing),
    updatedAt: Value(toEpochMs(theme.updatedAt)),
  );
}

ReaderTheme readerThemeFromRow(ReaderThemeRow row) {
  return ReaderTheme(
    id: row.id,
    name: row.name,
    isBuiltin: row.isBuiltin,
    isDark: row.isDark,
    bgColor: row.bgColor,
    textColor: row.textColor,
    secondaryTextColor: row.secondaryTextColor,
    bgTexturePath: row.bgTexturePath,
    fontFamily: row.fontFamily,
    fontPath: row.fontPath,
    fontSize: row.fontSize,
    fontWeight: row.fontWeight,
    lineHeight: row.lineHeight,
    paragraphSpacing: row.paragraphSpacing,
    letterSpacing: row.letterSpacing,
    paragraphIndentChars: row.paragraphIndentChars,
    marginHorizontal: row.marginHorizontal,
    marginVertical: row.marginVertical,
    columnMode: columnModeFromDb(row.columnMode),
    maxContentWidth: row.maxContentWidth,
    pageTurnMode: pageTurnModeFromDb(row.pageTurnMode),
    enablePunctuationHanging: row.enablePunctuationHanging,
    enableCjkSpacing: row.enableCjkSpacing,
    updatedAt: fromEpochMs(row.updatedAt),
  );
}

AppSettingsCompanion appSettingToCompanion(AppSetting setting) {
  return AppSettingsCompanion(
    key: Value(setting.key),
    value: Value(setting.value),
    updatedAt: Value(toEpochMs(setting.updatedAt)),
  );
}

AppSetting appSettingFromRow(AppSettingRow row) {
  return AppSetting(
    key: row.key,
    value: row.value,
    updatedAt: fromEpochMs(row.updatedAt),
  );
}
