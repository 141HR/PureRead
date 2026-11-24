import 'dart:io';

import '../../domain/failures/app_failure.dart';
import 'app_path_resolver.dart';

/// Persistent cache manager for raw online chapter text stored under
/// `cache/chapters/{bookId}/{chapterIndex}.txt`.
///
/// Keeps large chapter bodies out of SQLite while letting users safely inspect
/// and clear cached chapter bytes without disturbing bookshelf metadata or
/// reading progress.
class ChapterCacheStore {
  final AppPathResolver _pathResolver;

  const ChapterCacheStore(this._pathResolver);

  /// Persists raw chapter text for [bookId] / [chapterIndex] and returns its
  /// canonical relative cache key (`{safeBookId}/{chapterIndex}.txt`).
  Future<String> writeChapter(
    String bookId,
    int chapterIndex,
    String rawText,
  ) async {
    _validateChapterIndex(chapterIndex, bookId);
    final file = _pathResolver.chapterCacheFile(bookId, chapterIndex);
    final cacheKey = _pathResolver.chapterCacheKey(bookId, chapterIndex);
    try {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(rawText, flush: true);
      return cacheKey;
    } on FileAccessFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to write chapter cache file: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to write chapter cache: $e',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Reads raw chapter text for [bookId] / [chapterIndex], or returns `null` if
  /// not cached on disk.
  Future<String?> readChapter(String bookId, int chapterIndex) async {
    _validateChapterIndex(chapterIndex, bookId);
    final file = _pathResolver.chapterCacheFile(bookId, chapterIndex);
    try {
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsString();
    } on FileAccessFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to read chapter cache file: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to read chapter cache: $e',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Returns `true` when the chapter cache file exists on disk.
  Future<bool> hasChapter(String bookId, int chapterIndex) async {
    _validateChapterIndex(chapterIndex, bookId);
    final file = _pathResolver.chapterCacheFile(bookId, chapterIndex);
    try {
      return await file.exists();
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to check chapter cache file: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes a single cached chapter file if present.
  Future<void> deleteChapter(String bookId, int chapterIndex) async {
    _validateChapterIndex(chapterIndex, bookId);
    final file = _pathResolver.chapterCacheFile(bookId, chapterIndex);
    try {
      if (await file.exists()) {
        await file.delete();
      }
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } on FileAccessFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to delete chapter cache file: ${e.message}',
        filePath: file.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes all cached chapter files belonging to [bookId].
  Future<void> deleteBookCache(String bookId) async {
    final sampleFile = _pathResolver.chapterCacheFile(bookId, 0);
    final bookDir = sampleFile.parent;
    try {
      if (await bookDir.exists()) {
        await bookDir.delete(recursive: true);
      }
    } on FileAccessFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to delete book cache directory: ${e.message}',
        filePath: bookDir.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Computes total bytes occupied by cached chapters under `cache/chapters/`.
  Future<int> getTotalCacheBytes() async {
    final root = _pathResolver.chaptersCacheDir;
    try {
      if (!await root.exists()) {
        return 0;
      }
      var total = 0;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += await entity.length();
          } on FileSystemException {
            // Skip transiently removed files while computing totals.
          }
        }
      }
      return total;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to measure chapter cache size: ${e.message}',
        filePath: root.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Clears all cached chapter files under `cache/chapters/` and returns the
  /// number of bytes freed.
  Future<int> clearAllCache() async {
    final root = _pathResolver.chaptersCacheDir;
    try {
      final beforeBytes = await getTotalCacheBytes();
      if (await root.exists()) {
        await for (final entity in root.list(followLinks: false)) {
          await entity.delete(recursive: true);
        }
      } else {
        await root.create(recursive: true);
      }
      return beforeBytes;
    } on FileAccessFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to clear chapter cache: ${e.message}',
        filePath: root.path,
        cause: e,
        stackTrace: st,
      );
    }
  }

  static void _validateChapterIndex(int chapterIndex, String bookId) {
    if (chapterIndex < 0) {
      throw FileAccessFailure(
        message: 'Invalid negative chapterIndex $chapterIndex for book $bookId',
        filePath: bookId,
      );
    }
  }
}
