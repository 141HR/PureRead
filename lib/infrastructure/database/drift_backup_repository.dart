import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../domain/domain.dart';
import '../storage/app_path_resolver.dart';
import 'app_database.dart';
import 'database_backup_guard.dart';
import 'drift_mappers.dart';

/// Drift + `package:archive` implementation of [BackupRepository] handling
/// `.pureread.zip` export, archive/manifest validation, pre-restore database
/// snapshots via [DatabaseBackupGuard], transactional merge/overwrite restore,
/// and rolling DB snapshot listing.
class DriftBackupRepository implements BackupRepository {
  static const int supportedFormatVersion = 1;
  static const String manifestEntryPath = 'manifest.json';

  static const String bookGroupsEntryPath = 'data/book_groups.json';
  static const String booksEntryPath = 'data/books.json';
  static const String readingProgressEntryPath = 'data/reading_progress.json';
  static const String bookmarksEntryPath = 'data/bookmarks.json';
  static const String bookSourcesEntryPath = 'data/book_sources.json';
  static const String replaceRulesEntryPath = 'data/replace_rules.json';
  static const String readerThemesEntryPath = 'data/reader_themes.json';
  static const String appSettingsEntryPath = 'data/app_settings.json';

  static const List<String> requiredDataEntries = <String>[
    bookGroupsEntryPath,
    booksEntryPath,
    readingProgressEntryPath,
    bookmarksEntryPath,
    bookSourcesEntryPath,
    replaceRulesEntryPath,
    readerThemesEntryPath,
    appSettingsEntryPath,
  ];

  static const Set<String> _supportedFontExtensions = <String>{'.ttf', '.otf'};

  final AppDatabase _db;
  final AppPathResolver _pathResolver;
  final DatabaseBackupGuard _backupGuard;
  final String appVersion;
  final DateTime Function() _nowProvider;

  DriftBackupRepository(
    this._db,
    this._pathResolver, {
    DatabaseBackupGuard? backupGuard,
    this.appVersion = '0.4.0+4',
    DateTime Function()? nowProvider,
  }) : _backupGuard =
           backupGuard ??
           _db.backupGuard ??
           DatabaseBackupGuard(backupsDirPath: _pathResolver.dbBackupsDir.path),
       _nowProvider = nowProvider ?? _defaultNow;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  @override
  Future<BackupManifest> inspectBackup(String archivePath) async {
    final parsed = await _readAndValidateArchive(archivePath);
    return parsed.manifest;
  }

  @override
  Future<String> exportBackup(
    String targetArchivePath, {
    bool includeCustomFonts = true,
  }) async {
    if (targetArchivePath.trim().isEmpty) {
      throw FileAccessFailure(
        message: '备份导出路径不能为空',
        filePath: targetArchivePath,
      );
    }

    final snapshot = await guardDbCall('exportBackup.query', () async {
      return _db.transaction(() async {
        final groupRows =
            await (_db.select(_db.bookGroups)..orderBy([
                  (g) => OrderingTerm.asc(g.sortOrder),
                  (g) => OrderingTerm.asc(g.createdAt),
                  (g) => OrderingTerm.asc(g.id),
                ]))
                .get();
        final bookRows =
            await (_db.select(_db.books)..orderBy([
                  (b) => OrderingTerm.asc(b.createdAt),
                  (b) => OrderingTerm.asc(b.id),
                ]))
                .get();
        final progressRows =
            await (_db.select(_db.readingProgressRecords)..orderBy([
                  (p) => OrderingTerm.asc(p.bookId),
                ]))
                .get();
        final bookmarkRows =
            await (_db.select(_db.bookmarks)..orderBy([
                  (bm) => OrderingTerm.asc(bm.bookId),
                  (bm) => OrderingTerm.asc(bm.chapterIndex),
                  (bm) => OrderingTerm.asc(bm.charOffset),
                  (bm) => OrderingTerm.asc(bm.id),
                ]))
                .get();
        final sourceRows =
            await (_db.select(_db.bookSources)..orderBy([
                  (s) => OrderingTerm.desc(s.weight),
                  (s) => OrderingTerm.asc(s.id),
                ]))
                .get();
        final ruleRows =
            await (_db.select(_db.replaceRules)..orderBy([
                  (r) => OrderingTerm.asc(r.scopeType),
                  (r) => OrderingTerm.asc(r.sortOrder),
                  (r) => OrderingTerm.asc(r.id),
                ]))
                .get();
        final themeRows =
            await (_db.select(_db.readerThemes)..orderBy([
                  (t) => OrderingTerm.desc(t.isBuiltin),
                  (t) => OrderingTerm.asc(t.id),
                ]))
                .get();
        final settingRows =
            await (_db.select(_db.appSettings)..orderBy([
                  (s) => OrderingTerm.asc(s.key),
                ]))
                .get();

        return (
          groups: groupRows.map(bookGroupFromRow).toList(growable: false),
          books: bookRows.map(bookFromRow).toList(growable: false),
          progress: progressRows
              .map(readingProgressFromRow)
              .toList(growable: false),
          bookmarks: bookmarkRows.map(bookmarkFromRow).toList(growable: false),
          sources: sourceRows.map(bookSourceFromRow).toList(growable: false),
          rules: ruleRows.map(replaceRuleFromRow).toList(growable: false),
          themes: themeRows.map(readerThemeFromRow).toList(growable: false),
          settings: settingRows.map(appSettingFromRow).toList(growable: false),
        );
      });
    });

    final fontFiles = includeCustomFonts
        ? await _collectCustomFontFiles()
        : const <({String entryPath, Uint8List bytes})>[];

    final now = _nowProvider().toUtc();
    final counts = <String, int>{
      'book_groups': snapshot.groups.length,
      'books': snapshot.books.length,
      'reading_progress': snapshot.progress.length,
      'bookmarks': snapshot.bookmarks.length,
      'book_sources': snapshot.sources.length,
      'replace_rules': snapshot.rules.length,
      'reader_themes': snapshot.themes.length,
      'app_settings': snapshot.settings.length,
      'fonts': fontFiles.length,
    };

    final manifestMap = <String, Object?>{
      'formatVersion': supportedFormatVersion,
      'appVersion': appVersion,
      'schemaVersion': _db.schemaVersion,
      'exportedAt': now.toIso8601String(),
      'counts': counts,
    };

    const jsonEncoder = JsonEncoder.withIndent('  ');
    final archive = Archive();
    try {
      archive.addFile(
        ArchiveFile.string(manifestEntryPath, jsonEncoder.convert(manifestMap)),
      );
      archive.addFile(
        ArchiveFile.string(
          bookGroupsEntryPath,
          jsonEncoder.convert(
            snapshot.groups.map(_bookGroupToJson).toList(growable: false),
          ),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          booksEntryPath,
          jsonEncoder.convert(
            snapshot.books.map(_bookToJson).toList(growable: false),
          ),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          readingProgressEntryPath,
          jsonEncoder.convert(
            snapshot.progress
                .map(_readingProgressToJson)
                .toList(growable: false),
          ),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          bookmarksEntryPath,
          jsonEncoder.convert(
            snapshot.bookmarks.map(_bookmarkToJson).toList(growable: false),
          ),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          bookSourcesEntryPath,
          jsonEncoder.convert(
            snapshot.sources.map(_bookSourceToJson).toList(growable: false),
          ),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          replaceRulesEntryPath,
          jsonEncoder.convert(
            snapshot.rules.map(_replaceRuleToJson).toList(growable: false),
          ),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          readerThemesEntryPath,
          jsonEncoder.convert(
            snapshot.themes.map(_readerThemeToJson).toList(growable: false),
          ),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          appSettingsEntryPath,
          jsonEncoder.convert(
            snapshot.settings.map(_appSettingToJson).toList(growable: false),
          ),
        ),
      );

      for (final font in fontFiles) {
        archive.addFile(ArchiveFile.bytes(font.entryPath, font.bytes));
      }

      final encoded = ZipEncoder().encodeBytes(archive, modified: now);
      return await _writeArchiveAtomically(targetArchivePath, encoded);
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw FileAccessFailure(
        message: '导出备份文件失败：$error',
        filePath: targetArchivePath,
        cause: error,
        stackTrace: stackTrace,
      );
    } finally {
      archive.clearSync();
    }
  }

  @override
  Future<void> restoreBackup(
    String archivePath, {
    BackupRestoreMode mode = BackupRestoreMode.merge,
  }) async {
    // Validate archive integrity, manifest, and JSON payloads before mutating
    // the database or rotating snapshots.
    final parsed = await _readAndValidateArchive(archivePath);

    // Ensure the database file is initialized before creating a snapshot.
    await guardDbCall('restoreBackup.ensureOpen', () async {
      await _db.customSelect('SELECT 1;').get();
    });

    String? preRestoreSnapshotPath;
    final dbPath = _db.dbFilePath;
    if (dbPath != null) {
      preRestoreSnapshotPath = await _backupGuard.backupBeforeUpgrade(
        dbFilePath: dbPath,
        oldVersion: _db.schemaVersion,
        checkpointWal: () =>
            _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);'),
      );
    }

    try {
      await _db.transaction(() async {
        if (mode == BackupRestoreMode.overwrite) {
          await _db.delete(_db.bookmarks).go();
          await _db.delete(_db.readingProgressRecords).go();
          await _db.delete(_db.chapters).go();
          await _db.delete(_db.books).go();
          await _db.delete(_db.bookGroups).go();
          await _db.delete(_db.bookSources).go();
          await _db.delete(_db.replaceRules).go();
          await _db.delete(_db.readerThemes).go();
          await _db.delete(_db.appSettings).go();
        }

        if (parsed.bookGroups.isNotEmpty) {
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(
              _db.bookGroups,
              parsed.bookGroups
                  .map(bookGroupToCompanion)
                  .toList(growable: false),
            );
          });
        }

        final existingGroupIds = (await _db.select(
          _db.bookGroups,
        ).get()).map((g) => g.id).toSet();

        final sanitizedBooks = parsed.books
            .map((book) {
              if (book.groupId != null &&
                  !existingGroupIds.contains(book.groupId)) {
                return book.copyWith(clearGroupId: true);
              }
              return book;
            })
            .toList(growable: false);

        if (sanitizedBooks.isNotEmpty) {
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(
              _db.books,
              sanitizedBooks.map(bookToCompanion).toList(growable: false),
            );
          });
        }

        final existingBookIds = (await _db.select(
          _db.books,
        ).get()).map((b) => b.id).toSet();

        final validProgress = parsed.readingProgress
            .where((progress) => existingBookIds.contains(progress.bookId))
            .toList(growable: false);
        if (validProgress.isNotEmpty) {
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(
              _db.readingProgressRecords,
              validProgress
                  .map(readingProgressToCompanion)
                  .toList(growable: false),
            );
          });
        }

        final validBookmarks = parsed.bookmarks
            .where((bookmark) => existingBookIds.contains(bookmark.bookId))
            .toList(growable: false);
        if (validBookmarks.isNotEmpty) {
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(
              _db.bookmarks,
              validBookmarks.map(bookmarkToCompanion).toList(growable: false),
            );
          });
        }

        if (parsed.bookSources.isNotEmpty) {
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(
              _db.bookSources,
              parsed.bookSources
                  .map(bookSourceToCompanion)
                  .toList(growable: false),
            );
          });
        }

        if (parsed.replaceRules.isNotEmpty) {
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(
              _db.replaceRules,
              parsed.replaceRules
                  .map(replaceRuleToCompanion)
                  .toList(growable: false),
            );
          });
        }

        if (parsed.readerThemes.isNotEmpty) {
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(
              _db.readerThemes,
              parsed.readerThemes
                  .map(readerThemeToCompanion)
                  .toList(growable: false),
            );
          });
        }

        if (parsed.appSettings.isNotEmpty) {
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(
              _db.appSettings,
              parsed.appSettings
                  .map(appSettingToCompanion)
                  .toList(growable: false),
            );
          });
        }
      });
    } catch (error, stackTrace) {
      if (error is DatabaseFailure) {
        if (error.backupSnapshotPath != null ||
            preRestoreSnapshotPath == null) {
          rethrow;
        }
        throw DatabaseFailure(
          message: error.message,
          backupSnapshotPath: preRestoreSnapshotPath,
          cause: error.cause ?? error,
          stackTrace: error.stackTrace ?? stackTrace,
        );
      }
      throw DatabaseFailure(
        message: '恢复备份数据库事务失败：$error',
        backupSnapshotPath: preRestoreSnapshotPath,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    await _restoreCustomFonts(parsed.fonts);
  }

  @override
  Future<List<String>> listDatabaseSnapshots() {
    return _backupGuard.listBackups();
  }

  Future<List<({String entryPath, Uint8List bytes})>>
  _collectCustomFontFiles() async {
    final fontsDir = _pathResolver.fontsDir;
    if (!await fontsDir.exists()) {
      return const <({String entryPath, Uint8List bytes})>[];
    }

    final collected = <({String entryPath, Uint8List bytes})>[];
    try {
      await for (final entity in fontsDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_supportedFontExtensions.contains(ext)) continue;

        final rel = p.relative(entity.path, from: fontsDir.path);
        final relPosix = p.posix.joinAll(p.split(rel));
        if (relPosix.isEmpty || relPosix == '.' || relPosix.startsWith('..')) {
          continue;
        }
        final bytes = await entity.readAsBytes();
        collected.add((entryPath: 'fonts/$relPosix', bytes: bytes));
      }
      collected.sort((a, b) => a.entryPath.compareTo(b.entryPath));
      return collected;
    } catch (error, stackTrace) {
      throw FileAccessFailure(
        message: '读取自定义字体文件失败：$error',
        filePath: fontsDir.path,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<String> _writeArchiveAtomically(
    String targetArchivePath,
    Uint8List bytes,
  ) async {
    final targetFile = File(targetArchivePath);
    final tempFile = File('$targetArchivePath.tmp');
    try {
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }
      await tempFile.writeAsBytes(bytes, flush: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      return targetFile.path;
    } catch (error, stackTrace) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {
          // Best-effort temp cleanup.
        }
      }
      throw FileAccessFailure(
        message: '写入备份文件失败：$error',
        filePath: targetArchivePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _restoreCustomFonts(
    List<({String relativePath, Uint8List bytes})> fonts,
  ) async {
    if (fonts.isEmpty) return;

    try {
      final fontsDir = _pathResolver.fontsDir;
      if (!await fontsDir.exists()) {
        await fontsDir.create(recursive: true);
      }
      final fontsCanonical = p.normalize(p.absolute(fontsDir.path));

      for (final font in fonts) {
        final destFile = _pathResolver.resolveDataRelativeFile(
          font.relativePath,
        );
        final destCanonical = p.normalize(p.absolute(destFile.path));
        if (!p.isWithin(fontsCanonical, destCanonical)) {
          throw FileAccessFailure(
            message: '非法字体路径：${font.relativePath}',
            filePath: font.relativePath,
          );
        }
        if (!await destFile.parent.exists()) {
          await destFile.parent.create(recursive: true);
        }
        await destFile.writeAsBytes(font.bytes, flush: true);
      }
    } catch (error, stackTrace) {
      if (error is FileAccessFailure) rethrow;
      throw FileAccessFailure(
        message: '写入恢复字体文件失败：$error',
        filePath: _pathResolver.fontsDir.path,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<_ParsedBackupArchive> _readAndValidateArchive(
    String archivePath,
  ) async {
    if (archivePath.trim().isEmpty) {
      throw FileAccessFailure(message: '备份文件路径不能为空', filePath: archivePath);
    }

    final file = File(archivePath);
    if (!await file.exists()) {
      throw FileAccessFailure(
        message: '备份文件不存在：$archivePath',
        filePath: archivePath,
      );
    }

    final Uint8List rawBytes;
    try {
      rawBytes = await file.readAsBytes();
    } catch (error, stackTrace) {
      throw FileAccessFailure(
        message: '读取备份文件失败：$error',
        filePath: archivePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (rawBytes.isEmpty) {
      throw FileAccessFailure(
        message: '备份文件为空：$archivePath',
        filePath: archivePath,
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(
        rawBytes,
        verify: true,
        throwOnError: true,
      );
    } catch (error, stackTrace) {
      throw FileAccessFailure(
        message: '备份压缩包损坏或格式无效：$error',
        filePath: archivePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    try {
      final fileEntries = <String, ArchiveFile>{};
      for (final entry in archive) {
        if (!entry.isFile || entry.isDirectory) {
          continue;
        }
        final normalized = _normalizeEntryPath(entry.name);
        if (normalized == null) {
          throw FileAccessFailure(
            message: '备份包包含非法条目路径：${entry.name}',
            filePath: archivePath,
          );
        }
        fileEntries[normalized] = entry;
      }

      final manifestEntry = fileEntries[manifestEntryPath];
      if (manifestEntry == null) {
        throw FileAccessFailure(
          message: '备份包缺少 manifest.json',
          filePath: archivePath,
        );
      }

      final manifest = _parseManifest(
        _readJsonMap(manifestEntry, archivePath, manifestEntryPath),
        archivePath,
      );

      for (final requiredEntry in requiredDataEntries) {
        if (!fileEntries.containsKey(requiredEntry)) {
          throw FileAccessFailure(
            message: '备份包缺少数据文件：$requiredEntry',
            filePath: archivePath,
          );
        }
      }

      final groups = _parseList(
        fileEntries[bookGroupsEntryPath]!,
        archivePath,
        bookGroupsEntryPath,
        _bookGroupFromJson,
      );
      final books = _parseList(
        fileEntries[booksEntryPath]!,
        archivePath,
        booksEntryPath,
        _bookFromJson,
      );
      final progress = _parseList(
        fileEntries[readingProgressEntryPath]!,
        archivePath,
        readingProgressEntryPath,
        _readingProgressFromJson,
      );
      final bookmarks = _parseList(
        fileEntries[bookmarksEntryPath]!,
        archivePath,
        bookmarksEntryPath,
        _bookmarkFromJson,
      );
      final sources = _parseList(
        fileEntries[bookSourcesEntryPath]!,
        archivePath,
        bookSourcesEntryPath,
        _bookSourceFromJson,
      );
      final rules = _parseList(
        fileEntries[replaceRulesEntryPath]!,
        archivePath,
        replaceRulesEntryPath,
        _replaceRuleFromJson,
      );
      final themes = _parseList(
        fileEntries[readerThemesEntryPath]!,
        archivePath,
        readerThemesEntryPath,
        _readerThemeFromJson,
      );
      final settings = _parseList(
        fileEntries[appSettingsEntryPath]!,
        archivePath,
        appSettingsEntryPath,
        _appSettingFromJson,
      );

      final actualCounts = <String, int>{
        'book_groups': groups.length,
        'books': books.length,
        'reading_progress': progress.length,
        'bookmarks': bookmarks.length,
        'book_sources': sources.length,
        'replace_rules': rules.length,
        'reader_themes': themes.length,
        'app_settings': settings.length,
      };
      for (final entry in actualCounts.entries) {
        final declared = manifest.recordCounts[entry.key];
        if (declared != null && declared != entry.value) {
          throw FileAccessFailure(
            message:
                '备份包校验失败：${entry.key} 声明数量 ($declared) 与实际记录数 (${entry.value}) 不一致',
            filePath: archivePath,
          );
        }
      }

      final fonts = <({String relativePath, Uint8List bytes})>[];
      final fontsCanonical = p.normalize(
        p.absolute(_pathResolver.fontsDir.path),
      );
      for (final entry in fileEntries.entries) {
        if (!entry.key.startsWith('fonts/')) continue;
        final subPath = entry.key.substring('fonts/'.length);
        if (subPath.isEmpty || subPath.contains(':')) {
          throw FileAccessFailure(
            message: '备份包包含非法字体路径：${entry.key}',
            filePath: archivePath,
          );
        }
        final resolved = _pathResolver.resolveDataRelativeFile(entry.key);
        if (!p.isWithin(fontsCanonical, p.normalize(p.absolute(resolved.path)))) {
          throw FileAccessFailure(
            message: '备份包字体路径越界：${entry.key}',
            filePath: archivePath,
          );
        }
        final ext = p.extension(entry.key).toLowerCase();
        if (!_supportedFontExtensions.contains(ext)) {
          throw FileAccessFailure(
            message: '备份包包含不支持的字体格式：${entry.key}',
            filePath: archivePath,
          );
        }
        final fontBytes = _readEntryBytes(entry.value, archivePath, entry.key);
        if (fontBytes.isEmpty) {
          throw FileAccessFailure(
            message: '备份包中的字体文件为空：${entry.key}',
            filePath: archivePath,
          );
        }
        fonts.add((relativePath: entry.key, bytes: fontBytes));
      }

      final declaredFonts = manifest.recordCounts['fonts'];
      if (declaredFonts != null && declaredFonts != fonts.length) {
        throw FileAccessFailure(
          message:
              '备份包校验失败：fonts 声明数量 ($declaredFonts) 与实际文件数 (${fonts.length}) 不一致',
          filePath: archivePath,
        );
      }

      return _ParsedBackupArchive(
        manifest: manifest,
        bookGroups: groups,
        books: books,
        readingProgress: progress,
        bookmarks: bookmarks,
        bookSources: sources,
        replaceRules: rules,
        readerThemes: themes,
        appSettings: settings,
        fonts: fonts,
      );
    } on FileAccessFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw FileAccessFailure(
        message: '备份包解析校验失败：$error',
        filePath: archivePath,
        cause: error,
        stackTrace: stackTrace,
      );
    } finally {
      archive.clearSync();
    }
  }

  static String? _normalizeEntryPath(String rawName) {
    var normalized = rawName.replaceAll('\\', '/').trim();
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('\u0000')) {
      return null;
    }
    final segments = normalized.split('/');
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        return null;
      }
    }
    return normalized;
  }

  static Uint8List _readEntryBytes(
    ArchiveFile entry,
    String archivePath,
    String entryPath,
  ) {
    try {
      final bytes = entry.readBytes();
      if (bytes == null) {
        throw FileAccessFailure(
          message: '无法读取压缩包条目：$entryPath',
          filePath: archivePath,
        );
      }
      return bytes;
    } catch (error, stackTrace) {
      if (error is FileAccessFailure) rethrow;
      throw FileAccessFailure(
        message: '备份条目损坏 ($entryPath)：$error',
        filePath: archivePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Map<String, Object?> _readJsonMap(
    ArchiveFile entry,
    String archivePath,
    String entryPath,
  ) {
    final bytes = _readEntryBytes(entry, archivePath, entryPath);
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('Expected JSON object');
      }
      return Map<String, Object?>.from(decoded);
    } catch (error, stackTrace) {
      throw FileAccessFailure(
        message: '无效的 JSON 对象 ($entryPath)：$error',
        filePath: archivePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static List<T> _parseList<T>(
    ArchiveFile entry,
    String archivePath,
    String entryPath,
    T Function(Map<String, Object?> json) mapper,
  ) {
    final bytes = _readEntryBytes(entry, archivePath, entryPath);
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        throw const FormatException('Expected JSON array');
      }
      final items = <T>[];
      for (final element in decoded) {
        if (element is! Map) {
          throw const FormatException('Expected JSON object item in array');
        }
        items.add(mapper(Map<String, Object?>.from(element)));
      }
      return items;
    } catch (error, stackTrace) {
      if (error is FileAccessFailure) rethrow;
      throw FileAccessFailure(
        message: '解析数据表 $entryPath 失败：$error',
        filePath: archivePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  BackupManifest _parseManifest(
    Map<String, Object?> json,
    String archivePath,
  ) {
    final formatVersion = _requireInt(json, 'formatVersion');
    if (formatVersion < 1 || formatVersion > supportedFormatVersion) {
      throw FileAccessFailure(
        message: '不支持的备份格式版本：v$formatVersion',
        filePath: archivePath,
      );
    }

    final appVersion = _requireNonEmptyString(json, 'appVersion');
    final schemaVersion = _requireInt(json, 'schemaVersion');
    if (schemaVersion < 1 || schemaVersion > _db.schemaVersion) {
      throw FileAccessFailure(
        message:
            '备份数据库 Schema 版本 (v$schemaVersion) 高于当前应用支持版本 (v${_db.schemaVersion})',
        filePath: archivePath,
      );
    }

    final exportedAt = _requireDateTime(json, 'exportedAt');
    final rawCounts = json['counts'] ?? json['recordCounts'];
    if (rawCounts is! Map) {
      throw FileAccessFailure(
        message: 'manifest.json 缺少有效的 counts 字段',
        filePath: archivePath,
      );
    }

    final counts = <String, int>{};
    for (final entry in rawCounts.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! num) {
        throw FileAccessFailure(
          message: 'manifest.json counts 字段格式无效',
          filePath: archivePath,
        );
      }
      counts[key] = value.toInt();
    }

    return BackupManifest(
      formatVersion: formatVersion,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      exportedAt: exportedAt,
      recordCounts: counts,
    );
  }
}

class _ParsedBackupArchive {
  final BackupManifest manifest;
  final List<BookGroup> bookGroups;
  final List<Book> books;
  final List<ReadingProgress> readingProgress;
  final List<Bookmark> bookmarks;
  final List<BookSource> bookSources;
  final List<ReplaceRule> replaceRules;
  final List<ReaderTheme> readerThemes;
  final List<AppSetting> appSettings;
  final List<({String relativePath, Uint8List bytes})> fonts;

  const _ParsedBackupArchive({
    required this.manifest,
    required this.bookGroups,
    required this.books,
    required this.readingProgress,
    required this.bookmarks,
    required this.bookSources,
    required this.replaceRules,
    required this.readerThemes,
    required this.appSettings,
    required this.fonts,
  });
}

Map<String, Object?> _bookGroupToJson(BookGroup group) {
  return <String, Object?>{
    'id': group.id,
    'name': group.name,
    'sort_order': group.sortOrder,
    'created_at': toEpochMs(group.createdAt),
    'updated_at': toEpochMs(group.updatedAt),
  };
}

BookGroup _bookGroupFromJson(Map<String, Object?> json) {
  return BookGroup(
    id: _requireNonEmptyString(json, 'id'),
    name: _requireString(json, 'name'),
    sortOrder: _optionalInt(json, 'sort_order') ?? 0,
    createdAt: _requireDateTime(json, 'created_at'),
    updatedAt: _requireDateTime(json, 'updated_at'),
  );
}

Map<String, Object?> _bookToJson(Book book) {
  return <String, Object?>{
    'id': book.id,
    'source_id': book.sourceId,
    'provider_type': providerTypeToDb(book.providerType),
    'origin_book_url': book.originBookUrl,
    'toc_url': book.tocUrl,
    'title': book.title,
    'author': book.author,
    'cover_path': book.coverPath,
    'intro': book.intro,
    'local_file_path': book.localFilePath,
    'file_encoding': book.fileEncoding,
    'file_size_bytes': book.fileSizeBytes,
    'file_hash': book.fileHash,
    'group_id': book.groupId,
    'is_pinned': book.isPinned,
    'total_chapters': book.totalChapters,
    'unread_count': book.unreadCount,
    'last_chapter_title': book.lastChapterTitle,
    'last_read_at': toEpochMsNullable(book.lastReadAt),
    'latest_chapter_at': toEpochMsNullable(book.latestChapterAt),
    'created_at': toEpochMs(book.createdAt),
    'updated_at': toEpochMs(book.updatedAt),
  };
}

Book _bookFromJson(Map<String, Object?> json) {
  return Book(
    id: _requireNonEmptyString(json, 'id'),
    sourceId: _optionalString(json, 'source_id'),
    providerType: providerTypeFromDb(_requireString(json, 'provider_type')),
    originBookUrl: _optionalString(json, 'origin_book_url'),
    tocUrl: _optionalString(json, 'toc_url'),
    title: _requireString(json, 'title'),
    author: _optionalString(json, 'author') ?? '',
    coverPath: _optionalString(json, 'cover_path'),
    intro: _optionalString(json, 'intro') ?? '',
    localFilePath: _optionalString(json, 'local_file_path'),
    fileEncoding: _optionalString(json, 'file_encoding'),
    fileSizeBytes: _optionalInt(json, 'file_size_bytes'),
    fileHash: _optionalString(json, 'file_hash'),
    groupId: _optionalString(json, 'group_id'),
    isPinned: _optionalBool(json, 'is_pinned') ?? false,
    totalChapters: _optionalInt(json, 'total_chapters') ?? 0,
    unreadCount: _optionalInt(json, 'unread_count') ?? 0,
    lastChapterTitle: _optionalString(json, 'last_chapter_title') ?? '',
    lastReadAt: _optionalDateTime(json, 'last_read_at'),
    latestChapterAt: _optionalDateTime(json, 'latest_chapter_at'),
    createdAt: _requireDateTime(json, 'created_at'),
    updatedAt: _requireDateTime(json, 'updated_at'),
  );
}

Map<String, Object?> _readingProgressToJson(ReadingProgress progress) {
  return <String, Object?>{
    'book_id': progress.bookId,
    'chapter_index': progress.chapterIndex,
    'char_offset': progress.charOffset,
    'chapter_title_snapshot': progress.chapterTitleSnapshot,
    'progress_percent': progress.progressPercent,
    'reading_duration_sec': progress.readingDurationSec,
    'updated_at': toEpochMs(progress.updatedAt),
    'device_id': progress.deviceId,
  };
}

ReadingProgress _readingProgressFromJson(Map<String, Object?> json) {
  return ReadingProgress(
    bookId: _requireNonEmptyString(json, 'book_id'),
    chapterIndex: _optionalInt(json, 'chapter_index') ?? 0,
    charOffset: _optionalInt(json, 'char_offset') ?? 0,
    chapterTitleSnapshot: _optionalString(json, 'chapter_title_snapshot') ?? '',
    progressPercent: _optionalDouble(json, 'progress_percent') ?? 0.0,
    readingDurationSec: _optionalInt(json, 'reading_duration_sec') ?? 0,
    updatedAt: _requireDateTime(json, 'updated_at'),
    deviceId: _optionalString(json, 'device_id') ?? '',
  );
}

Map<String, Object?> _bookmarkToJson(Bookmark bookmark) {
  return <String, Object?>{
    'id': bookmark.id,
    'book_id': bookmark.bookId,
    'chapter_index': bookmark.chapterIndex,
    'char_offset': bookmark.charOffset,
    'excerpt': bookmark.excerpt,
    'note': bookmark.note,
    'created_at': toEpochMs(bookmark.createdAt),
  };
}

Bookmark _bookmarkFromJson(Map<String, Object?> json) {
  return Bookmark(
    id: _requireNonEmptyString(json, 'id'),
    bookId: _requireNonEmptyString(json, 'book_id'),
    chapterIndex: _requireInt(json, 'chapter_index'),
    charOffset: _requireInt(json, 'char_offset'),
    excerpt: _requireString(json, 'excerpt'),
    note: _optionalString(json, 'note') ?? '',
    createdAt: _requireDateTime(json, 'created_at'),
  );
}

Map<String, Object?> _bookSourceToJson(BookSource source) {
  return <String, Object?>{
    'id': source.id,
    'name': source.name,
    'group_name': source.groupName,
    'engine_type': sourceEngineTypeToDb(source.engineType),
    'base_url': source.baseUrl,
    'raw_definition': source.rawDefinition,
    'enabled': source.enabled,
    'weight': source.weight,
    'rate_limit_ms': source.rateLimitMs,
    'last_check_status': sourceCheckStatusToDb(source.lastCheckStatus),
    'last_error_summary': source.lastErrorSummary,
    'created_at': toEpochMs(source.createdAt),
    'updated_at': toEpochMs(source.updatedAt),
  };
}

BookSource _bookSourceFromJson(Map<String, Object?> json) {
  return BookSource(
    id: _requireNonEmptyString(json, 'id'),
    name: _requireString(json, 'name'),
    groupName: _optionalString(json, 'group_name') ?? '默认',
    engineType: sourceEngineTypeFromDb(_requireString(json, 'engine_type')),
    baseUrl: _requireString(json, 'base_url'),
    rawDefinition: _requireString(json, 'raw_definition'),
    enabled: _optionalBool(json, 'enabled') ?? true,
    weight: _optionalInt(json, 'weight') ?? 0,
    rateLimitMs: _optionalInt(json, 'rate_limit_ms') ?? 500,
    lastCheckStatus: sourceCheckStatusFromDb(
      _optionalString(json, 'last_check_status') ?? 'unknown',
    ),
    lastErrorSummary: _optionalString(json, 'last_error_summary'),
    createdAt: _requireDateTime(json, 'created_at'),
    updatedAt: _requireDateTime(json, 'updated_at'),
  );
}

Map<String, Object?> _replaceRuleToJson(ReplaceRule rule) {
  return <String, Object?>{
    'id': rule.id,
    'name': rule.name,
    'group_name': rule.groupName,
    'pattern': rule.pattern,
    'replacement': rule.replacement,
    'is_regex': rule.isRegex,
    'scope_type': ruleScopeTypeToDb(rule.scopeType),
    'scope_target_id': rule.scopeTargetId,
    'enabled': rule.enabled,
    'sort_order': rule.sortOrder,
    'updated_at': toEpochMs(rule.updatedAt),
  };
}

ReplaceRule _replaceRuleFromJson(Map<String, Object?> json) {
  return ReplaceRule(
    id: _requireNonEmptyString(json, 'id'),
    name: _requireString(json, 'name'),
    groupName: _optionalString(json, 'group_name') ?? '通用',
    pattern: _requireString(json, 'pattern'),
    replacement: _optionalString(json, 'replacement') ?? '',
    isRegex: _optionalBool(json, 'is_regex') ?? true,
    scopeType: ruleScopeTypeFromDb(
      _optionalString(json, 'scope_type') ?? 'global',
    ),
    scopeTargetId: _optionalString(json, 'scope_target_id'),
    enabled: _optionalBool(json, 'enabled') ?? true,
    sortOrder: _optionalInt(json, 'sort_order') ?? 0,
    updatedAt: _requireDateTime(json, 'updated_at'),
  );
}

Map<String, Object?> _readerThemeToJson(ReaderTheme theme) {
  return <String, Object?>{
    'id': theme.id,
    'name': theme.name,
    'is_builtin': theme.isBuiltin,
    'is_dark': theme.isDark,
    'bg_color': theme.bgColor,
    'text_color': theme.textColor,
    'secondary_text_color': theme.secondaryTextColor,
    'bg_texture_path': theme.bgTexturePath,
    'font_family': theme.fontFamily,
    'font_path': theme.fontPath,
    'font_size': theme.fontSize,
    'font_weight': theme.fontWeight,
    'line_height': theme.lineHeight,
    'paragraph_spacing': theme.paragraphSpacing,
    'letter_spacing': theme.letterSpacing,
    'paragraph_indent_chars': theme.paragraphIndentChars,
    'margin_horizontal': theme.marginHorizontal,
    'margin_vertical': theme.marginVertical,
    'column_mode': columnModeToDb(theme.columnMode),
    'max_content_width': theme.maxContentWidth,
    'page_turn_mode': pageTurnModeToDb(theme.pageTurnMode),
    'enable_punctuation_hanging': theme.enablePunctuationHanging,
    'enable_cjk_spacing': theme.enableCjkSpacing,
    'updated_at': toEpochMs(theme.updatedAt),
  };
}

ReaderTheme _readerThemeFromJson(Map<String, Object?> json) {
  return ReaderTheme(
    id: _requireNonEmptyString(json, 'id'),
    name: _requireString(json, 'name'),
    isBuiltin: _optionalBool(json, 'is_builtin') ?? false,
    isDark: _optionalBool(json, 'is_dark') ?? false,
    bgColor: _requireInt(json, 'bg_color'),
    textColor: _requireInt(json, 'text_color'),
    secondaryTextColor: _requireInt(json, 'secondary_text_color'),
    bgTexturePath: _optionalString(json, 'bg_texture_path'),
    fontFamily: _optionalString(json, 'font_family') ?? 'system',
    fontPath: _optionalString(json, 'font_path'),
    fontSize: _optionalDouble(json, 'font_size') ?? 18.0,
    fontWeight: _optionalInt(json, 'font_weight') ?? 400,
    lineHeight: _optionalDouble(json, 'line_height') ?? 1.65,
    paragraphSpacing: _optionalDouble(json, 'paragraph_spacing') ?? 12.0,
    letterSpacing: _optionalDouble(json, 'letter_spacing') ?? 0.2,
    paragraphIndentChars: _optionalInt(json, 'paragraph_indent_chars') ?? 2,
    marginHorizontal: _optionalDouble(json, 'margin_horizontal') ?? 20.0,
    marginVertical: _optionalDouble(json, 'margin_vertical') ?? 24.0,
    columnMode: columnModeFromDb(
      _optionalString(json, 'column_mode') ?? 'auto',
    ),
    maxContentWidth: _optionalDouble(json, 'max_content_width') ?? 760.0,
    pageTurnMode: pageTurnModeFromDb(
      _optionalString(json, 'page_turn_mode') ?? 'cover',
    ),
    enablePunctuationHanging:
        _optionalBool(json, 'enable_punctuation_hanging') ?? true,
    enableCjkSpacing: _optionalBool(json, 'enable_cjk_spacing') ?? true,
    updatedAt: _requireDateTime(json, 'updated_at'),
  );
}

Map<String, Object?> _appSettingToJson(AppSetting setting) {
  return <String, Object?>{
    'key': setting.key,
    'value': setting.value,
    'updated_at': toEpochMs(setting.updatedAt),
  };
}

AppSetting _appSettingFromJson(Map<String, Object?> json) {
  return AppSetting(
    key: _requireNonEmptyString(json, 'key'),
    value: _requireString(json, 'value'),
    updatedAt: _requireDateTime(json, 'updated_at'),
  );
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Missing or invalid string field "$key"');
  }
  return value;
}

String _requireNonEmptyString(Map<String, Object?> json, String key) {
  final value = _requireString(json, key);
  if (value.trim().isEmpty) {
    throw FormatException('Field "$key" must not be empty');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Invalid string field "$key"');
  }
  return value;
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw FormatException('Missing or invalid integer field "$key"');
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw FormatException('Invalid integer field "$key"');
}

double? _optionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Invalid numeric field "$key"');
}

bool? _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  if (value is int && (value == 0 || value == 1)) return value == 1;
  throw FormatException('Invalid boolean field "$key"');
}

DateTime _requireDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return fromEpochMs(value);
  }
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw FormatException('Missing or invalid timestamp field "$key"');
}

DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) {
    return fromEpochMs(value);
  }
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw FormatException('Invalid timestamp field "$key"');
}
