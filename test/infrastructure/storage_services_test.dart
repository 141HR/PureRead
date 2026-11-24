import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/storage/storage.dart';

class _RecordingFontLoader extends FontLoader {
  final List<({String family, Uint8List bytes})> loadedFonts;

  _RecordingFontLoader(super.family, this.loadedFonts);

  @override
  Future<void> loadFont(Uint8List list, String family) async {
    loadedFonts.add((family: family, bytes: list));
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pureread_storage_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppPathResolver', () {
    test('resolves all 7 directories in standard mode', () async {
      final supportDir = Directory(p.join(tempDir.path, 'support'));
      final cacheBaseDir = Directory(p.join(tempDir.path, 'app_cache'));
      final exePath = p.join(tempDir.path, 'bin', 'pureread.exe');

      final resolver = await AppPathResolver.resolve(
        executablePath: exePath,
        isWindowsOverride: false,
        supportDirProvider: () async => supportDir,
        cacheDirProvider: () async => cacheBaseDir,
      );

      expect(resolver.isPortable, isFalse);
      expect(resolver.dbDir.path, p.join(supportDir.path, 'db'));
      expect(
        resolver.dbBackupsDir.path,
        p.join(supportDir.path, 'db', 'backups'),
      );
      expect(
        resolver.databaseFile.path,
        p.join(supportDir.path, 'db', 'pureread.db'),
      );
      expect(resolver.fontsDir.path, p.join(supportDir.path, 'fonts'));
      expect(resolver.coversDir.path, p.join(supportDir.path, 'covers'));
      expect(resolver.importsDir.path, p.join(supportDir.path, 'imports'));
      expect(
        resolver.chaptersCacheDir.path,
        p.join(cacheBaseDir.path, 'cache', 'chapters'),
      );
      expect(
        resolver.tmpCacheDir.path,
        p.join(cacheBaseDir.path, 'cache', 'tmp'),
      );

      expect(await resolver.dbDir.exists(), isTrue);
      expect(await resolver.dbBackupsDir.exists(), isTrue);
      expect(await resolver.fontsDir.exists(), isTrue);
      expect(await resolver.coversDir.exists(), isTrue);
      expect(await resolver.importsDir.exists(), isTrue);
      expect(await resolver.chaptersCacheDir.exists(), isTrue);
      expect(await resolver.tmpCacheDir.exists(), isTrue);

      expect(resolver.chapterCacheKey('book-1', 4), 'book-1/4.txt');
      expect(
        resolver.chapterCacheFile('book-1', 4).path,
        p.join(cacheBaseDir.path, 'cache', 'chapters', 'book-1', '4.txt'),
      );
      expect(
        () => resolver.resolveDataRelativeFile('../escape.txt'),
        throwsA(isA<FileAccessFailure>()),
      );
      expect(
        () => resolver.chapterCacheFile('..', 0),
        throwsA(isA<FileAccessFailure>()),
      );
    });

    test('activates Windows portable mode when .portable marker file exists', () async {
      final exeDir = Directory(p.join(tempDir.path, 'portable_marker_app'));
      await exeDir.create(recursive: true);
      await File(p.join(exeDir.path, '.portable')).create();
      final exePath = p.join(exeDir.path, 'pureread.exe');

      final resolver = await AppPathResolver.resolve(
        executablePath: exePath,
        isWindowsOverride: true,
        supportDirProvider: () async =>
            throw StateError('Should not query OS support dir in portable mode'),
        cacheDirProvider: () async =>
            throw StateError('Should not query OS cache dir in portable mode'),
      );

      final expectedDataRoot = p.join(exeDir.path, 'portable', 'data');
      expect(resolver.isPortable, isTrue);
      expect(resolver.dataRootDir.path, expectedDataRoot);
      expect(resolver.dbDir.path, p.join(expectedDataRoot, 'db'));
      expect(
        resolver.dbBackupsDir.path,
        p.join(expectedDataRoot, 'db', 'backups'),
      );
      expect(resolver.fontsDir.path, p.join(expectedDataRoot, 'fonts'));
      expect(resolver.coversDir.path, p.join(expectedDataRoot, 'covers'));
      expect(resolver.importsDir.path, p.join(expectedDataRoot, 'imports'));
      expect(
        resolver.chaptersCacheDir.path,
        p.join(expectedDataRoot, 'cache', 'chapters'),
      );
      expect(
        resolver.tmpCacheDir.path,
        p.join(expectedDataRoot, 'cache', 'tmp'),
      );
      expect(await resolver.dbBackupsDir.exists(), isTrue);
      expect(await resolver.tmpCacheDir.exists(), isTrue);
    });

    test('activates Windows portable mode when portable/ folder exists', () async {
      final exeDir = Directory(p.join(tempDir.path, 'portable_dir_app'));
      await Directory(p.join(exeDir.path, 'portable')).create(recursive: true);
      final exePath = p.join(exeDir.path, 'pureread.exe');

      final resolver = await AppPathResolver.resolve(
        executablePath: exePath,
        isWindowsOverride: true,
        supportDirProvider: () async =>
            throw StateError('Should not query OS support dir in portable mode'),
        cacheDirProvider: () async =>
            throw StateError('Should not query OS cache dir in portable mode'),
      );

      expect(resolver.isPortable, isTrue);
      expect(
        resolver.dataRootDir.path,
        p.join(exeDir.path, 'portable', 'data'),
      );
    });

    test('ignores .portable marker on non-Windows platforms', () async {
      final exeDir = Directory(p.join(tempDir.path, 'non_win_app'));
      await exeDir.create(recursive: true);
      await File(p.join(exeDir.path, '.portable')).create();

      final supportDir = Directory(p.join(tempDir.path, 'std_support'));
      final cacheBaseDir = Directory(p.join(tempDir.path, 'std_cache'));

      final resolver = await AppPathResolver.resolve(
        executablePath: p.join(exeDir.path, 'pureread'),
        isWindowsOverride: false,
        supportDirProvider: () async => supportDir,
        cacheDirProvider: () async => cacheBaseDir,
      );

      expect(resolver.isPortable, isFalse);
      expect(resolver.dataRootDir.path, supportDir.path);
    });
  });

  group('FontStorageService', () {
    test('imports .ttf/.otf fonts, registers via FontLoader, and deduplicates reloads', () async {
      final resolver = await AppPathResolver.resolve(
        executablePath: p.join(tempDir.path, 'pureread.exe'),
        isWindowsOverride: false,
        supportDirProvider: () async =>
            Directory(p.join(tempDir.path, 'support')),
        cacheDirProvider: () async =>
            Directory(p.join(tempDir.path, 'cache')),
      );

      final loadedFonts = <({String family, Uint8List bytes})>[];
      final fontService = FontStorageService(
        resolver,
        fontLoaderFactory: (family) =>
            _RecordingFontLoader(family, loadedFonts),
      );

      final ttfSource = File(p.join(tempDir.path, '霞鹜文楷.ttf'));
      final ttfBytes = Uint8List.fromList([0, 1, 0, 0, 10, 20, 30, 40]);
      await ttfSource.writeAsBytes(ttfBytes);

      final otfSource = File(p.join(tempDir.path, 'SourceHanSerif.OTF'));
      final otfBytes = Uint8List.fromList([0x4F, 0x54, 0x54, 0x4F, 1, 2, 3]);
      await otfSource.writeAsBytes(otfBytes);

      final importedTtf = await fontService.importAndRegisterFont(ttfSource.path);
      expect(importedTtf.relativeFontPath, startsWith('fonts/'));
      expect(importedTtf.relativeFontPath, endsWith('.ttf'));
      expect(
        await resolver.resolveDataRelativeFile(importedTtf.relativeFontPath).exists(),
        isTrue,
      );
      expect(fontService.isFontLoaded(importedTtf.fontFamily), isTrue);
      expect(loadedFonts.length, 1);
      expect(loadedFonts.first.family, importedTtf.fontFamily);
      expect(loadedFonts.first.bytes, equals(ttfBytes));

      // Subsequent ensureFontLoaded is a no-op once loaded in session.
      await fontService.ensureFontLoaded(
        importedTtf.fontFamily,
        importedTtf.relativeFontPath,
      );
      expect(loadedFonts.length, 1);

      // System font is a no-op.
      await fontService.ensureFontLoaded('system', null);
      expect(loadedFonts.length, 1);

      // Simulate restart with a fresh FontStorageService and concurrent calls.
      final restartedLoaded = <({String family, Uint8List bytes})>[];
      final restartedService = FontStorageService(
        resolver,
        fontLoaderFactory: (family) =>
            _RecordingFontLoader(family, restartedLoaded),
      );
      await Future.wait([
        restartedService.ensureFontLoaded(
          importedTtf.fontFamily,
          importedTtf.relativeFontPath,
        ),
        restartedService.ensureFontLoaded(
          importedTtf.fontFamily,
          importedTtf.relativeFontPath,
        ),
      ]);
      expect(restartedLoaded.length, 1);
      expect(restartedLoaded.first.bytes, equals(ttfBytes));

      // Verify .otf support as well.
      final importedOtf = await fontService.importAndRegisterFont(otfSource.path);
      expect(importedOtf.relativeFontPath, endsWith('.otf'));
      expect(loadedFonts.length, 2);
    });

    test('throws FileAccessFailure on invalid, missing, or escaping font paths', () async {
      final resolver = await AppPathResolver.resolve(
        executablePath: p.join(tempDir.path, 'pureread.exe'),
        isWindowsOverride: false,
        supportDirProvider: () async =>
            Directory(p.join(tempDir.path, 'support')),
        cacheDirProvider: () async =>
            Directory(p.join(tempDir.path, 'cache')),
      );
      final fontService = FontStorageService(
        resolver,
        fontLoaderFactory: (family) => _RecordingFontLoader(family, []),
      );

      final badExtFile = File(p.join(tempDir.path, 'not_a_font.txt'));
      await badExtFile.writeAsString('hello');
      final emptyTtfFile = File(p.join(tempDir.path, 'empty.ttf'));
      await emptyTtfFile.writeAsBytes(const <int>[]);

      await expectLater(
        () => fontService.importAndRegisterFont(
          p.join(tempDir.path, 'missing.ttf'),
        ),
        throwsA(isA<FileAccessFailure>()),
      );
      await expectLater(
        () => fontService.importAndRegisterFont(badExtFile.path),
        throwsA(isA<FileAccessFailure>()),
      );
      await expectLater(
        () => fontService.importAndRegisterFont(emptyTtfFile.path),
        throwsA(isA<FileAccessFailure>()),
      );
      await expectLater(
        () => fontService.ensureFontLoaded('custom', 'fonts/missing.ttf'),
        throwsA(isA<FileAccessFailure>()),
      );
      await expectLater(
        () => fontService.ensureFontLoaded('custom', '../db/pureread.db'),
        throwsA(isA<FileAccessFailure>()),
      );
    });
  });
}
