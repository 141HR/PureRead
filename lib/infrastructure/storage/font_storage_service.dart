import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/failures/app_failure.dart';
import 'app_path_resolver.dart';

/// Factory creating a Flutter [FontLoader] for a given font family name.
typedef FontLoaderFactory = FontLoader Function(String family);

/// Manages importing local `.ttf`/`.otf` font files into `fonts/` and lazily
/// registering them with Flutter's [FontLoader].
class FontStorageService {
  static const Set<String> supportedExtensions = <String>{'.ttf', '.otf'};

  final AppPathResolver _pathResolver;
  final FontLoaderFactory _fontLoaderFactory;
  final Set<String> _loadedFamilies = <String>{};
  final Map<String, Future<void>> _inFlightLoads = <String, Future<void>>{};

  FontStorageService(
    this._pathResolver, {
    FontLoaderFactory? fontLoaderFactory,
  }) : _fontLoaderFactory = fontLoaderFactory ?? FontLoader.new;

  /// Returns `true` if [fontFamily] has already been loaded in this session.
  bool isFontLoaded(String fontFamily) => _loadedFamilies.contains(fontFamily);

  /// Imports a `.ttf` or `.otf` font from [sourcePath] into the app's `fonts/`
  /// directory, registers it with Flutter's [FontLoader], and returns the
  /// assigned [fontFamily] and POSIX [relativeFontPath].
  Future<({String fontFamily, String relativeFontPath})> importAndRegisterFont(
    String sourcePath,
  ) async {
    if (sourcePath.isEmpty) {
      throw const FileAccessFailure(message: 'Font source path is empty');
    }

    final ext = p.extension(sourcePath).toLowerCase();
    if (!supportedExtensions.contains(ext)) {
      throw FileAccessFailure(
        message: 'Unsupported font format "$ext"; expected .ttf or .otf',
        filePath: sourcePath,
      );
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileAccessFailure(
        message: 'Font source file does not exist',
        filePath: sourcePath,
      );
    }

    try {
      final bytes = await sourceFile.readAsBytes();
      if (bytes.isEmpty) {
        throw FileAccessFailure(
          message: 'Font file is empty',
          filePath: sourcePath,
        );
      }

      final stem = _sanitizeStem(p.basenameWithoutExtension(sourcePath));
      final hashTag = _fnv1a64Hex(bytes);
      final storedFileName = '${stem}_$hashTag$ext';
      final relativeFontPath = 'fonts/$storedFileName';
      final fontFamily = 'pureread_${stem}_$hashTag';

      final fontsDir = _pathResolver.fontsDir;
      if (!await fontsDir.exists()) {
        await fontsDir.create(recursive: true);
      }

      final destFile = File(p.join(fontsDir.path, storedFileName));
      if (!await destFile.exists()) {
        await destFile.writeAsBytes(bytes, flush: true);
      }

      await _loadFontBytesDeduped(fontFamily, bytes);
      return (fontFamily: fontFamily, relativeFontPath: relativeFontPath);
    } catch (error, stackTrace) {
      if (error is FileAccessFailure) rethrow;
      throw FileAccessFailure(
        message: 'Failed to import font from $sourcePath: $error',
        filePath: sourcePath,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Ensures [fontFamily] is registered with Flutter if it refers to a custom
  /// font stored at [relativeFontPath].
  ///
  /// Built-in/system fonts (`fontFamily == 'system'` or null/empty
  /// [relativeFontPath]) return immediately without I/O.
  Future<void> ensureFontLoaded(
    String fontFamily,
    String? relativeFontPath,
  ) async {
    if (fontFamily.isEmpty ||
        fontFamily == 'system' ||
        relativeFontPath == null ||
        relativeFontPath.isEmpty) {
      return;
    }

    await _runDeduped(
      fontFamily,
      () => _loadFromRelativePath(fontFamily, relativeFontPath),
    );
  }

  Future<void> _loadFromRelativePath(
    String fontFamily,
    String relativeFontPath,
  ) async {
    final fontFile = _resolveFontFile(relativeFontPath);
    if (!await fontFile.exists()) {
      throw FileAccessFailure(
        message: 'Stored font file not found for family "$fontFamily"',
        filePath: fontFile.path,
      );
    }

    try {
      final bytes = await fontFile.readAsBytes();
      await _registerFontBytes(fontFamily, bytes);
    } catch (error, stackTrace) {
      if (error is FileAccessFailure) rethrow;
      throw FileAccessFailure(
        message: 'Failed to load font "$fontFamily": $error',
        filePath: fontFile.path,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadFontBytesDeduped(String fontFamily, Uint8List bytes) {
    return _runDeduped(
      fontFamily,
      () => _registerFontBytes(fontFamily, bytes),
    );
  }

  Future<void> _runDeduped(
    String fontFamily,
    Future<void> Function() loader,
  ) async {
    if (_loadedFamilies.contains(fontFamily)) {
      return;
    }

    final existingLoad = _inFlightLoads[fontFamily];
    if (existingLoad != null) {
      await existingLoad;
      return;
    }

    final loadFuture = loader();
    _inFlightLoads[fontFamily] = loadFuture;
    try {
      await loadFuture;
    } finally {
      if (identical(_inFlightLoads[fontFamily], loadFuture)) {
        unawaited(_inFlightLoads.remove(fontFamily));
      }
    }
  }

  Future<void> _registerFontBytes(String fontFamily, Uint8List bytes) async {
    if (_loadedFamilies.contains(fontFamily)) {
      return;
    }
    final loader = _fontLoaderFactory(fontFamily);
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFamilies.add(fontFamily);
  }

  File _resolveFontFile(String relativeFontPath) {
    final normalized = relativeFontPath.replaceAll('\\', '/');
    if (normalized.isEmpty || p.isAbsolute(normalized)) {
      throw FileAccessFailure(
        message: 'Font path must be relative: $relativeFontPath',
        filePath: relativeFontPath,
      );
    }

    final fontsCanonical = p.normalize(p.absolute(_pathResolver.fontsDir.path));
    final File candidate;
    if (normalized.startsWith('fonts/')) {
      candidate = _pathResolver.resolveDataRelativeFile(normalized);
    } else {
      final joined = p.normalize(
        p.absolute(p.joinAll([fontsCanonical, ...normalized.split('/')])),
      );
      candidate = File(joined);
    }

    if (!p.isWithin(fontsCanonical, candidate.path)) {
      throw FileAccessFailure(
        message: 'Font path escapes fonts directory: $relativeFontPath',
        filePath: relativeFontPath,
      );
    }
    return candidate;
  }

  static String _sanitizeStem(String rawStem) {
    final cleaned = rawStem
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'custom_font';
    }
    return cleaned;
  }

  static String _fnv1a64Hex(Uint8List bytes) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    final high = (hash >>> 32) & 0xFFFFFFFF;
    final low = hash & 0xFFFFFFFF;
    return high.toRadixString(16).padLeft(8, '0') +
        low.toRadixString(16).padLeft(8, '0');
  }
}
