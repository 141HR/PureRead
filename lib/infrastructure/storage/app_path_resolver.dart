import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/failures/app_failure.dart';

/// Callback returning a platform directory (injectable for tests).
typedef DirectoryProvider = Future<Directory> Function();

/// Resolves persistent data and rebuildable cache directories for PureRead.
///
/// Supports standard OS storage (`ApplicationSupport` + `ApplicationCache`)
/// and Windows portable mode when either a `.portable` marker file or a
/// `portable/` directory exists alongside the executable.
class AppPathResolver {
  static const String databaseFileName = 'pureread.db';
  static const String portableMarkerFileName = '.portable';
  static const String portableDirName = 'portable';

  /// Root directory for persistent user data (`db/`, `fonts/`, `covers/`, `imports/`).
  final Directory dataRootDir;

  /// Root directory for rebuildable cache data (`chapters/`, `tmp/`).
  final Directory cacheRootDir;

  /// Whether Windows portable mode is active.
  final bool isPortable;

  const AppPathResolver.fromRoots({
    required this.dataRootDir,
    required this.cacheRootDir,
    this.isPortable = false,
  });

  /// Resolves application directories for the current runtime environment.
  static Future<AppPathResolver> resolve({
    String? executablePath,
    bool? isWindowsOverride,
    DirectoryProvider? supportDirProvider,
    DirectoryProvider? cacheDirProvider,
    bool createDirectories = true,
  }) async {
    try {
      final isWindows = isWindowsOverride ?? Platform.isWindows;
      final resolvedExePath = executablePath ?? Platform.resolvedExecutable;
      final exeDir = p.dirname(resolvedExePath);

      final AppPathResolver resolver;
      if (isWindows && _detectPortableMode(exeDir)) {
        final portableDataRoot = Directory(
          p.join(exeDir, portableDirName, 'data'),
        );
        final portableCacheRoot = Directory(
          p.join(portableDataRoot.path, 'cache'),
        );
        resolver = AppPathResolver.fromRoots(
          dataRootDir: portableDataRoot,
          cacheRootDir: portableCacheRoot,
          isPortable: true,
        );
      } else {
        final supportDir =
            await (supportDirProvider ?? getApplicationSupportDirectory)();
        final cacheBaseDir =
            await (cacheDirProvider ?? getApplicationCacheDirectory)();
        resolver = AppPathResolver.fromRoots(
          dataRootDir: supportDir,
          cacheRootDir: Directory(p.join(cacheBaseDir.path, 'cache')),
          isPortable: false,
        );
      }

      if (createDirectories) {
        await resolver.ensureDirectoriesExist();
      }
      return resolver;
    } catch (error, stackTrace) {
      if (error is FileAccessFailure) rethrow;
      throw FileAccessFailure(
        message: 'Failed to resolve application directories: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static bool _detectPortableMode(String executableDir) {
    final markerFile = File(p.join(executableDir, portableMarkerFileName));
    if (markerFile.existsSync()) {
      return true;
    }
    final portableDir = Directory(p.join(executableDir, portableDirName));
    return portableDir.existsSync();
  }

  /// Persistent SQLite directory (`db/`).
  Directory get dbDir => Directory(p.join(dataRootDir.path, 'db'));

  /// Pre-upgrade database snapshot directory (`db/backups/`).
  Directory get dbBackupsDir =>
      Directory(p.join(dataRootDir.path, 'db', 'backups'));

  /// Primary SQLite database file (`db/pureread.db`).
  File get databaseFile => File(p.join(dbDir.path, databaseFileName));

  /// Imported custom `.ttf` / `.otf` fonts directory (`fonts/`).
  Directory get fontsDir => Directory(p.join(dataRootDir.path, 'fonts'));

  /// Cached book cover images directory (`covers/`).
  Directory get coversDir => Directory(p.join(dataRootDir.path, 'covers'));

  /// Imported local books workspace directory (`imports/`).
  Directory get importsDir => Directory(p.join(dataRootDir.path, 'imports'));

  /// Online chapter raw text cache directory (`cache/chapters/`).
  Directory get chaptersCacheDir =>
      Directory(p.join(cacheRootDir.path, 'chapters'));

  /// Temporary extraction / import staging directory (`cache/tmp/`).
  Directory get tmpCacheDir => Directory(p.join(cacheRootDir.path, 'tmp'));

  /// Ensures all managed storage subdirectories exist on disk.
  Future<void> ensureDirectoriesExist() async {
    try {
      final dirs = <Directory>[
        dbDir,
        dbBackupsDir,
        fontsDir,
        coversDir,
        importsDir,
        chaptersCacheDir,
        tmpCacheDir,
      ];
      for (final dir in dirs) {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }
    } catch (error, stackTrace) {
      throw FileAccessFailure(
        message: 'Failed to create storage directories: $error',
        filePath: dataRootDir.path,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Resolves the relative cache key (`{bookId}/{chapterIndex}.txt`) for an
  /// online chapter text file.
  String chapterCacheKey(String bookId, int chapterIndex) {
    final safeBookId = _sanitizePathSegment(bookId);
    return '$safeBookId/$chapterIndex.txt';
  }

  /// Resolves the chapter cache [File] under `cache/chapters/{bookId}/`.
  File chapterCacheFile(String bookId, int chapterIndex) {
    final safeBookId = _sanitizePathSegment(bookId);
    return File(p.join(chaptersCacheDir.path, safeBookId, '$chapterIndex.txt'));
  }

  /// Resolves a relative path inside [dataRootDir] while rejecting traversal
  /// outside [dataRootDir].
  File resolveDataRelativeFile(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.isEmpty || p.isAbsolute(normalized)) {
      throw FileAccessFailure(
        message: 'Relative storage path must be non-empty and relative',
        filePath: relativePath,
      );
    }
    final rootCanonical = p.normalize(p.absolute(dataRootDir.path));
    final targetCanonical = p.normalize(
      p.absolute(p.joinAll([rootCanonical, ...normalized.split('/')])),
    );
    if (!p.isWithin(rootCanonical, targetCanonical)) {
      throw FileAccessFailure(
        message: 'Path escapes data root directory: $relativePath',
        filePath: relativePath,
      );
    }
    return File(targetCanonical);
  }

  static String _sanitizePathSegment(String segment) {
    final sanitized = segment.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      throw FileAccessFailure(
        message: 'Invalid path segment: $segment',
        filePath: segment,
      );
    }
    return sanitized;
  }
}
