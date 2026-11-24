import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/domain.dart';

/// Current disk usage summary for rebuildable reader caches.
class CacheStats {
  final int chapterCacheBytes;
  final int cachedFileCount;
  final int tempCacheBytes;

  const CacheStats({
    required this.chapterCacheBytes,
    required this.cachedFileCount,
    this.tempCacheBytes = 0,
  });

  int get totalBytes => chapterCacheBytes + tempCacheBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheStats &&
          runtimeType == other.runtimeType &&
          chapterCacheBytes == other.chapterCacheBytes &&
          cachedFileCount == other.cachedFileCount &&
          tempCacheBytes == other.tempCacheBytes;

  @override
  int get hashCode =>
      Object.hash(chapterCacheBytes, cachedFileCount, tempCacheBytes);
}

/// Gateway for inspecting and clearing rebuildable online chapter & temp
/// caches without mutating shelf metadata, reading progress, or bookmarks.
abstract interface class CacheManagementGateway {
  Future<CacheStats> getCacheStats();

  Future<int> clearChapterCache();
}

/// Filesystem-backed [CacheManagementGateway] operating on `cache/chapters/`
/// and optional `cache/tmp/`, with an optional hook to reset SQLite
/// `chapters.is_cached` flags after clearing.
class DirectoryCacheManagementGateway implements CacheManagementGateway {
  final Directory chaptersCacheDir;
  final Directory? tmpCacheDir;
  final Future<void> Function()? onChapterCacheCleared;

  const DirectoryCacheManagementGateway({
    required this.chaptersCacheDir,
    this.tmpCacheDir,
    this.onChapterCacheCleared,
  });

  @override
  Future<CacheStats> getCacheStats() async {
    try {
      final chaptersUsage = await _measureDirectory(chaptersCacheDir);
      final tempUsage = tmpCacheDir == null
          ? (bytes: 0, count: 0)
          : await _measureDirectory(tmpCacheDir!);
      return CacheStats(
        chapterCacheBytes: chaptersUsage.bytes,
        cachedFileCount: chaptersUsage.count,
        tempCacheBytes: tempUsage.bytes,
      );
    } catch (error, stackTrace) {
      if (error is FileAccessFailure) rethrow;
      throw FileAccessFailure(
        message: '统计缓存大小失败：$error',
        filePath: chaptersCacheDir.path,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<int> clearChapterCache() async {
    try {
      var freedBytes = await _clearDirectoryContents(chaptersCacheDir);
      if (tmpCacheDir != null) {
        freedBytes += await _clearDirectoryContents(tmpCacheDir!);
      }
      if (onChapterCacheCleared != null) {
        await onChapterCacheCleared!();
      }
      return freedBytes;
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw FileAccessFailure(
        message: '清理章节缓存失败：$error',
        filePath: chaptersCacheDir.path,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<({int bytes, int count})> _measureDirectory(Directory dir) async {
    if (!await dir.exists()) {
      return (bytes: 0, count: 0);
    }
    var bytes = 0;
    var count = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        bytes += await entity.length();
        count++;
      }
    }
    return (bytes: bytes, count: count);
  }

  Future<int> _clearDirectoryContents(Directory dir) async {
    if (!await dir.exists()) {
      return 0;
    }
    var freed = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        freed += await entity.length();
        await entity.delete();
      } else if (entity is Directory) {
        final subUsage = await _measureDirectory(entity);
        freed += subUsage.bytes;
        await entity.delete(recursive: true);
      } else {
        await entity.delete(recursive: true);
      }
    }
    return freed;
  }
}

/// Callback returning the default export destination path for a `.pureread.zip`
/// archive at [timestamp].
typedef BackupExportPathResolver = Future<String> Function(DateTime timestamp);

/// Formats a canonical PureRead backup archive filename for [timestamp].
String formatBackupArchiveFileName(DateTime timestamp) {
  final utc = timestamp.toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  final hh = utc.hour.toString().padLeft(2, '0');
  final mm = utc.minute.toString().padLeft(2, '0');
  final ss = utc.second.toString().padLeft(2, '0');
  return 'pureread_backup_$y$m${d}_$hh$mm$ss.pureread.zip';
}

/// Formats byte counts into a compact human-readable string (`B`, `KB`, `MB`, `GB`).
String formatByteSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => _StubBackupRepository(),
);

final cacheManagementGatewayProvider = Provider<CacheManagementGateway>(
  (ref) => const _NoOpCacheManagementGateway(),
);

final backupExportPathResolverProvider = Provider<BackupExportPathResolver>((
  ref,
) {
  return (DateTime timestamp) async {
    return p.join(
      Directory.systemTemp.path,
      'pureread_backups',
      formatBackupArchiveFileName(timestamp),
    );
  };
});

class _StubBackupRepository implements BackupRepository {
  @override
  Future<BackupManifest> inspectBackup(String archivePath) async {
    throw FileAccessFailure(
      message: '备份服务尚未装配，无法校验：$archivePath',
      filePath: archivePath,
    );
  }

  @override
  Future<String> exportBackup(
    String targetArchivePath, {
    bool includeCustomFonts = true,
  }) async {
    throw FileAccessFailure(
      message: '备份服务尚未装配，无法导出：$targetArchivePath',
      filePath: targetArchivePath,
    );
  }

  @override
  Future<void> restoreBackup(
    String archivePath, {
    BackupRestoreMode mode = BackupRestoreMode.merge,
  }) async {
    throw FileAccessFailure(
      message: '备份服务尚未装配，无法恢复：$archivePath',
      filePath: archivePath,
    );
  }

  @override
  Future<List<String>> listDatabaseSnapshots() async => const <String>[];
}

class _NoOpCacheManagementGateway implements CacheManagementGateway {
  const _NoOpCacheManagementGateway();

  @override
  Future<CacheStats> getCacheStats() async =>
      const CacheStats(chapterCacheBytes: 0, cachedFileCount: 0);

  @override
  Future<int> clearChapterCache() async => 0;
}
