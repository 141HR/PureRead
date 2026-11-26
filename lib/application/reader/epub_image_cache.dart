import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import 'local_epub_reader_provider.dart';

/// Optional custom decoder hook (defaults to bounded [ui.instantiateImageCodec]).
typedef EpubImageDecoder = Future<ui.Image?> Function(Uint8List bytes);

/// Provides a lifecycle-managed [EpubImageCache] wired to
/// [localEpubImageReaderProvider].
final epubImageCacheProvider = Provider.autoDispose<EpubImageCache>((ref) {
  final cache = EpubImageCache(
    imageReader: ref.watch(localEpubImageReaderProvider),
  );
  ref.onDispose(cache.dispose);
  return cache;
});

/// Bounded LRU `ui.Image` cache for EPUB inline illustrations.
///
/// Deduplicates concurrent loads, caps decoded raster width to
/// [maxTargetWidth], disposes evicted GPU textures cleanly, and records failed
/// image keys so broken illustrations render a fallback without retry loops.
class EpubImageCache extends ChangeNotifier {
  EpubImageCache({
    required this.imageReader,
    int maxEntries = 12,
    int maxTargetWidth = 1600,
    int maxFailedEntries = 256,
    this.imageDecoder,
  })  : maxEntries = maxEntries < 1 ? 1 : maxEntries,
        maxTargetWidth = maxTargetWidth < 1 ? 1 : maxTargetWidth,
        _maxFailedEntries = maxFailedEntries < 1 ? 1 : maxFailedEntries;

  final LocalEpubImageReader imageReader;
  final int maxEntries;
  final int maxTargetWidth;
  final int _maxFailedEntries;
  final EpubImageDecoder? imageDecoder;

  final LinkedHashMap<String, ui.Image> _cache =
      LinkedHashMap<String, ui.Image>();
  final Map<String, Future<ui.Image?>> _inFlight =
      <String, Future<ui.Image?>>{};
  final LinkedHashSet<String> _failedKeys = LinkedHashSet<String>();

  int _generation = 0;
  bool _disposed = false;

  /// Builds a collision-free cache key for [bookKey] and [archivePath].
  static String buildCacheKey(String bookKey, String archivePath) =>
      '$bookKey\u0000$archivePath';

  int get cachedCount => _cache.length;
  int get failedCount => _failedKeys.length;
  int get inFlightCount => _inFlight.length;

  /// Synchronously returns a cached [ui.Image] and refreshes its LRU position.
  ui.Image? getCached(String bookKey, String archivePath) {
    if (_disposed || archivePath.isEmpty) return null;
    final key = buildCacheKey(bookKey, archivePath);
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
    }
    return existing;
  }

  /// Whether loading or decoding [archivePath] for [bookKey] previously failed.
  bool isFailed(String bookKey, String archivePath) {
    if (archivePath.isEmpty) return false;
    return _failedKeys.contains(buildCacheKey(bookKey, archivePath));
  }

  /// Whether loading or decoding [cacheKey] previously failed.
  bool isFailedKey(String cacheKey) => _failedKeys.contains(cacheKey);

  /// Whether an asynchronous decode for [archivePath] is currently in flight.
  bool isLoading(String bookKey, String archivePath) {
    if (_disposed || archivePath.isEmpty) return false;
    return _inFlight.containsKey(buildCacheKey(bookKey, archivePath));
  }

  /// Loads, decodes, and caches [archivePath] for [book], deduplicating
  /// concurrent requests.
  Future<ui.Image?> loadImage(Book book, String archivePath) {
    if (_disposed || archivePath.isEmpty) {
      return Future<ui.Image?>.value(null);
    }

    final key = buildCacheKey(book.id, archivePath);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future<ui.Image?>.value(cached);
    }

    if (_failedKeys.contains(key)) {
      return Future<ui.Image?>.value(null);
    }

    final existingFuture = _inFlight[key];
    if (existingFuture != null) {
      return existingFuture;
    }

    final startGeneration = _generation;
    late final Future<ui.Image?> future;
    future = _loadAndDecode(
      book: book,
      archivePath: archivePath,
      cacheKey: key,
      startGeneration: startGeneration,
    ).whenComplete(() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    });

    _inFlight[key] = future;
    return future;
  }

  Future<ui.Image?> _loadAndDecode({
    required Book book,
    required String archivePath,
    required String cacheKey,
    required int startGeneration,
  }) async {
    ui.Image? decoded;
    try {
      final bytes = await imageReader(book, archivePath);
      if (_disposed || startGeneration != _generation) {
        return null;
      }
      if (bytes == null || bytes.isEmpty) {
        _recordFailure(cacheKey);
        notifyListeners();
        return null;
      }

      decoded = await _decodeBounded(bytes);
      if (_disposed || startGeneration != _generation) {
        decoded?.dispose();
        return null;
      }
      if (decoded == null) {
        _recordFailure(cacheKey);
        notifyListeners();
        return null;
      }

      _insertLru(cacheKey, decoded);
      notifyListeners();
      return decoded;
    } catch (_) {
      decoded?.dispose();
      if (!_disposed && startGeneration == _generation) {
        _recordFailure(cacheKey);
        notifyListeners();
      }
      return null;
    }
  }

  Future<ui.Image?> _decodeBounded(Uint8List bytes) async {
    final customDecoder = imageDecoder;
    if (customDecoder != null) {
      return customDecoder(bytes);
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxTargetWidth,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  void _insertLru(String cacheKey, ui.Image image) {
    final replaced = _cache.remove(cacheKey);
    if (replaced != null && !identical(replaced, image)) {
      replaced.dispose();
    }
    while (_cache.length >= maxEntries && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final oldestImage = _cache.remove(oldestKey);
      oldestImage?.dispose();
    }
    _cache[cacheKey] = image;
  }

  void _recordFailure(String cacheKey) {
    _failedKeys.remove(cacheKey);
    while (_failedKeys.length >= _maxFailedEntries && _failedKeys.isNotEmpty) {
      _failedKeys.remove(_failedKeys.first);
    }
    _failedKeys.add(cacheKey);
  }

  /// Disposes all cached [ui.Image] objects and resets failure tracking.
  void clear() {
    _generation++;
    _inFlight.clear();
    _failedKeys.clear();
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _inFlight.clear();
    _failedKeys.clear();
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    super.dispose();
  }
}
