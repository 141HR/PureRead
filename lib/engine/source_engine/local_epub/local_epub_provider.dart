import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../domain/entities/book.dart';
import '../../../domain/entities/book_search_item.dart';
import '../../../domain/entities/chapter.dart';
import '../../../domain/failures/app_failure.dart';
import '../../../domain/services/book_provider.dart';
import '../../../domain/value_objects/cancellation_token.dart';
import '../../../domain/value_objects/provider_capabilities.dart';
import '../../../domain/value_objects/source_debug_trace.dart';
import 'epub_container_parser.dart';
import 'epub_models.dart';
import 'epub_path_utils.dart';

/// Local EPUB 2/3 implementation of [BookProvider].
///
/// Parses EPUB ZIP containers, metadata, covers, NAV/NCX/spine chapters, and
/// chapter XHTML content inside background `Isolate.run` workers via
/// [EpubContainerParser].
class LocalEpubProvider implements BookProvider {
  LocalEpubProvider({
    this.providerId = 'local_epub',
    EpubContainerParser? parser,
    this.maxCachedBookIndices = 8,
  }) : _parser = parser ?? const EpubContainerParser();

  @override
  final String providerId;

  final EpubContainerParser _parser;
  final int maxCachedBookIndices;

  final LinkedHashMap<String, _CachedEpubIndex> _indexCache =
      LinkedHashMap<String, _CachedEpubIndex>();
  final Map<String, String> _bookFilePaths = <String, String>{};

  @override
  ProviderType get type => ProviderType.localEpub;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        isLocal: true,
        supportsSearch: false,
        supportsUpdateCheck: false,
        supportsChangeSource: false,
      );

  /// Imports a local EPUB 2/3 file at [filePath], parsing its OPF metadata,
  /// ordered chapters (NAV -> NCX -> spine fallback), deterministic content
  /// hash, and optional cover image.
  ///
  /// When [coverSaveDir] is provided and a cover image is present in the EPUB,
  /// the cover bytes are written to [coverSaveDir] and [Book.coverPath] is
  /// populated with the saved file path.
  ///
  /// Throws [FileAccessFailure] if the file is missing or unreadable (or cover
  /// persistence fails), and [SourceParseFailure] if the archive is not a valid
  /// EPUB ZIP or is missing an OPF/spine.
  Future<({
    Book book,
    List<ChapterMeta> chapters,
    Uint8List? coverBytes,
    String? coverExtension,
  })> importEpubFile(
    String filePath, {
    String? bookId,
    String? coverSaveDir,
    bool extractCover = true,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final stat = await _ensureReadableFile(filePath);

    final parsed = await _parser.parseFile(
      filePath,
      extractCover: extractCover,
    );
    cancelToken?.throwIfCancelled();

    final now = DateTime.now().toUtc();
    final resolvedBookId = (bookId != null && bookId.trim().isNotEmpty)
        ? bookId.trim()
        : _deriveBookId(filePath);

    _rememberBookIndex(
      filePath: filePath,
      stat: stat,
      opfPath: parsed.opfPath,
      chapters: parsed.chapters,
      bookId: resolvedBookId,
    );

    final cover = parsed.cover;
    String? savedCoverPath;
    if (extractCover &&
        cover != null &&
        cover.bytes.isNotEmpty &&
        coverSaveDir != null &&
        coverSaveDir.trim().isNotEmpty) {
      savedCoverPath = await _writeCoverFile(
        coverSaveDir: coverSaveDir,
        bookId: resolvedBookId,
        cover: cover,
      );
      cancelToken?.throwIfCancelled();
    }

    final title = parsed.metadata.title.trim().isNotEmpty
        ? parsed.metadata.title.trim()
        : _deriveTitleFromPath(filePath);

    final chapters = parsed.chapters
        .map(
          (entry) => ChapterMeta(
            bookId: resolvedBookId,
            chapterIndex: entry.chapterIndex,
            title: entry.title,
            epubHref: entry.epubHref,
            updatedAt: now,
          ),
        )
        .toList(growable: false);

    final book = Book(
      id: resolvedBookId,
      providerType: ProviderType.localEpub,
      title: title,
      author: parsed.metadata.author,
      coverPath: savedCoverPath,
      intro: parsed.metadata.description,
      localFilePath: filePath,
      fileEncoding: 'UTF-8',
      fileSizeBytes: parsed.fileSizeBytes,
      fileHash: parsed.fileHash,
      totalChapters: chapters.length,
      lastChapterTitle: chapters.isNotEmpty ? chapters.last.title : '',
      createdAt: now,
      updatedAt: now,
    );

    return (
      book: book,
      chapters: chapters,
      coverBytes: cover?.bytes,
      coverExtension: cover?.extension,
    );
  }

  /// Reads and extracts clean plain text for [chapter] from the EPUB file at
  /// [filePath].
  ///
  /// For multi-anchor single-XHTML EPUBs (multiple TOC chapters referencing
  /// different `#fragment` IDs in the same XHTML file), provide [nextChapter],
  /// [chapters], or [stopFragment] — or rely on the EPUB container's TOC index
  /// automatically so slicing stops cleanly before the next chapter's anchor.
  Future<String> readChapterText({
    required String filePath,
    required ChapterMeta chapter,
    ChapterMeta? nextChapter,
    List<ChapterMeta>? chapters,
    String? stopFragment,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final stat = await _ensureReadableFile(filePath);

    final epubHref = chapter.epubHref?.trim();
    if (epubHref == null || epubHref.isEmpty) {
      throw SourceParseFailure(
        message: 'EPUB chapter "${chapter.title}" is missing epubHref',
        step: 'content',
      );
    }

    final stopFragments = await _resolveStopFragments(
      filePath: filePath,
      stat: stat,
      chapter: chapter,
      epubHref: epubHref,
      nextChapter: nextChapter,
      chapters: chapters,
      explicitStopFragment: stopFragment,
    );
    cancelToken?.throwIfCancelled();

    final text = await _parser.readChapterTextFromFile(
      filePath: filePath,
      epubHref: epubHref,
      stopFragments: stopFragments,
    );
    cancelToken?.throwIfCancelled();
    return text;
  }

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    return (
      items: const <BookSearchItem>[],
      trace: const SourceDebugTrace(
        step: 'search',
        elapsedMs: 0,
        logs: <String>['LocalEpubProvider does not support remote search'],
      ),
    );
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    final imported = await importEpubFile(
      bookUrl,
      extractCover: false,
      cancelToken: cancelToken,
    );
    sw.stop();

    final book = imported.book;
    return (
      detail: BookDetail(
        sourceId: providerId,
        providerType: ProviderType.localEpub,
        bookUrl: bookUrl,
        tocUrl: bookUrl,
        title: book.title,
        author: book.author,
        coverUrl: book.coverPath,
        intro: book.intro,
        latestChapterTitle: book.lastChapterTitle,
      ),
      trace: SourceDebugTrace(
        step: 'detail',
        elapsedMs: sw.elapsedMilliseconds,
        requestUrl: bookUrl,
        matchedPreview: book.title,
      ),
    );
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    final imported = await importEpubFile(
      tocUrl,
      extractCover: false,
      cancelToken: cancelToken,
    );
    sw.stop();

    return (
      chapters: imported.chapters,
      trace: SourceDebugTrace(
        step: 'toc',
        elapsedMs: sw.elapsedMilliseconds,
        requestUrl: tocUrl,
        matchedPreview: '${imported.chapters.length} chapters',
      ),
    );
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final explicitPath = chapter.url?.trim();
    final filePath = (explicitPath != null && explicitPath.isNotEmpty)
        ? explicitPath
        : _bookFilePaths[chapter.bookId];

    if (filePath == null || filePath.isEmpty) {
      throw const FileAccessFailure(
        message:
            'Local EPUB ChapterMeta lacks a file path in url; call readChapterText() with Book.localFilePath.',
      );
    }

    final sw = Stopwatch()..start();
    final text = await readChapterText(
      filePath: filePath,
      chapter: chapter,
      cancelToken: cancelToken,
    );
    sw.stop();

    return (
      content: ChapterContent(
        chapterIndex: chapter.chapterIndex,
        title: chapter.title,
        rawText: text,
        sourceUrl: filePath,
        fetchedAt: DateTime.now().toUtc(),
      ),
      trace: SourceDebugTrace(
        step: 'content',
        elapsedMs: sw.elapsedMilliseconds,
        requestUrl: chapter.epubHref ?? filePath,
        matchedPreview: text.length > 80 ? text.substring(0, 80) : text,
      ),
    );
  }

  Future<List<String>> _resolveStopFragments({
    required String filePath,
    required FileStat stat,
    required ChapterMeta chapter,
    required String epubHref,
    required ChapterMeta? nextChapter,
    required List<ChapterMeta>? chapters,
    required String? explicitStopFragment,
  }) async {
    if (explicitStopFragment != null &&
        explicitStopFragment.trim().isNotEmpty) {
      return <String>[explicitStopFragment.trim()];
    }

    final currentSplit = EpubPathUtils.splitHref(epubHref);
    final currentPath = EpubPathUtils.normalizeArchivePath(
      EpubPathUtils.safeUrlDecode(currentSplit.path),
    );
    final currentFrag = currentSplit.fragment;

    if (nextChapter != null) {
      final nextHref = nextChapter.epubHref?.trim();
      if (nextHref != null && nextHref.isNotEmpty) {
        final nextSplit = EpubPathUtils.splitHref(nextHref);
        final nextPath = EpubPathUtils.normalizeArchivePath(
          EpubPathUtils.safeUrlDecode(nextSplit.path),
        );
        if (nextPath.toLowerCase() == currentPath.toLowerCase() &&
            nextSplit.fragment != null &&
            nextSplit.fragment!.isNotEmpty &&
            nextSplit.fragment != currentFrag) {
          return <String>[nextSplit.fragment!];
        }
      }
      return const <String>[];
    }

    if (chapters != null && chapters.isNotEmpty) {
      return _collectSubsequentFragmentsFromMeta(
        chapters: chapters,
        chapter: chapter,
        currentHref: epubHref,
        currentPath: currentPath,
        currentFrag: currentFrag,
      );
    }

    // Automatically consult the cached or freshly parsed container TOC so
    // callers passing a single ChapterMeta still slice multi-anchor files.
    final cached = await _getOrLoadBookIndex(filePath, stat);
    if (cached == null || cached.chapters.isEmpty) {
      return const <String>[];
    }

    final resolvedCurrentPath = _resolvePathAgainstOpf(
      currentPath,
      cached.opfPath,
      cached.knownArchivePaths,
    );
    final resolvedCurrentHref = (currentFrag != null && currentFrag.isNotEmpty)
        ? '$resolvedCurrentPath#$currentFrag'
        : resolvedCurrentPath;

    var idx = -1;
    if (chapter.chapterIndex >= 0 &&
        chapter.chapterIndex < cached.chapters.length) {
      final candidate = cached.chapters[chapter.chapterIndex];
      if (candidate.epubHref.toLowerCase() ==
          resolvedCurrentHref.toLowerCase()) {
        idx = chapter.chapterIndex;
      }
    }
    if (idx < 0) {
      for (var i = 0; i < cached.chapters.length; i++) {
        if (cached.chapters[i].epubHref.toLowerCase() ==
            resolvedCurrentHref.toLowerCase()) {
          idx = i;
          break;
        }
      }
    }
    if (idx < 0) {
      return const <String>[];
    }

    final stops = <String>[];
    for (var i = idx + 1; i < cached.chapters.length; i++) {
      final entry = cached.chapters[i];
      if (entry.archivePath.toLowerCase() !=
          resolvedCurrentPath.toLowerCase()) {
        continue;
      }
      final frag = entry.fragment;
      if (frag != null &&
          frag.isNotEmpty &&
          frag != currentFrag &&
          !stops.contains(frag)) {
        stops.add(frag);
      }
    }
    return stops;
  }

  static List<String> _collectSubsequentFragmentsFromMeta({
    required List<ChapterMeta> chapters,
    required ChapterMeta chapter,
    required String currentHref,
    required String currentPath,
    required String? currentFrag,
  }) {
    var idx = -1;
    if (chapter.chapterIndex >= 0 && chapter.chapterIndex < chapters.length) {
      final candidate = chapters[chapter.chapterIndex];
      if (candidate.epubHref?.trim().toLowerCase() ==
          currentHref.toLowerCase()) {
        idx = chapter.chapterIndex;
      }
    }
    if (idx < 0) {
      for (var i = 0; i < chapters.length; i++) {
        if (chapters[i].epubHref?.trim().toLowerCase() ==
            currentHref.toLowerCase()) {
          idx = i;
          break;
        }
      }
    }
    if (idx < 0) return const <String>[];

    final stops = <String>[];
    for (var i = idx + 1; i < chapters.length; i++) {
      final nextHref = chapters[i].epubHref?.trim();
      if (nextHref == null || nextHref.isEmpty) continue;
      final split = EpubPathUtils.splitHref(nextHref);
      final nextPath = EpubPathUtils.normalizeArchivePath(
        EpubPathUtils.safeUrlDecode(split.path),
      );
      if (nextPath.toLowerCase() != currentPath.toLowerCase()) continue;
      final frag = split.fragment;
      if (frag != null &&
          frag.isNotEmpty &&
          frag != currentFrag &&
          !stops.contains(frag)) {
        stops.add(frag);
      }
    }
    return stops;
  }

  static String _resolvePathAgainstOpf(
    String path,
    String opfPath,
    Set<String> knownArchivePaths,
  ) {
    final lower = path.toLowerCase();
    for (final known in knownArchivePaths) {
      if (known.toLowerCase() == lower) {
        return known;
      }
    }
    if (opfPath.isNotEmpty) {
      final candidate = EpubPathUtils.resolveHref(opfPath, path).archivePath;
      final candLower = candidate.toLowerCase();
      for (final known in knownArchivePaths) {
        if (known.toLowerCase() == candLower) {
          return known;
        }
      }
    }
    return path;
  }

  Future<_CachedEpubIndex?> _getOrLoadBookIndex(
    String filePath,
    FileStat stat,
  ) async {
    final cacheKey = _canonicalPathKey(filePath);
    final existing = _indexCache[cacheKey];
    if (existing != null &&
        existing.fileSize == stat.size &&
        existing.modifiedMs == stat.modified.millisecondsSinceEpoch) {
      _indexCache.remove(cacheKey);
      _indexCache[cacheKey] = existing;
      return existing;
    }

    final parsed = await _parser.parseFile(filePath, extractCover: false);
    final cached = _rememberBookIndex(
      filePath: filePath,
      stat: stat,
      opfPath: parsed.opfPath,
      chapters: parsed.chapters,
    );
    return cached;
  }

  _CachedEpubIndex _rememberBookIndex({
    required String filePath,
    required FileStat stat,
    required String opfPath,
    required List<EpubChapterEntry> chapters,
    String? bookId,
  }) {
    if (bookId != null) {
      _bookFilePaths[bookId] = filePath;
    }
    final cacheKey = _canonicalPathKey(filePath);
    final entry = _CachedEpubIndex(
      fileSize: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      opfPath: opfPath,
      chapters: chapters,
      knownArchivePaths: chapters.map((c) => c.archivePath).toSet(),
    );

    if (maxCachedBookIndices > 0) {
      _indexCache.remove(cacheKey);
      if (_indexCache.length >= maxCachedBookIndices) {
        _indexCache.remove(_indexCache.keys.first);
      }
      _indexCache[cacheKey] = entry;
    }
    return entry;
  }

  Future<FileStat> _ensureReadableFile(String filePath) async {
    if (filePath.trim().isEmpty) {
      throw FileAccessFailure(
        message: 'EPUB file path cannot be empty',
        filePath: filePath,
      );
    }
    try {
      final type = await FileSystemEntity.type(filePath);
      if (type == FileSystemEntityType.notFound) {
        throw FileAccessFailure(
          message: 'EPUB file does not exist: $filePath',
          filePath: filePath,
        );
      }
      if (type == FileSystemEntityType.directory) {
        throw FileAccessFailure(
          message: 'Expected an EPUB file but found a directory: $filePath',
          filePath: filePath,
        );
      }
      return await File(filePath).stat();
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Cannot access EPUB file: ${e.message}',
        filePath: filePath,
        cause: e,
        stackTrace: st,
      );
    }
  }

  Future<String> _writeCoverFile({
    required String coverSaveDir,
    required String bookId,
    required EpubCoverData cover,
  }) async {
    try {
      final dir = Directory(coverSaveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final stem = _sanitizeFileStem(bookId);
      final rawExt = cover.extension.trim();
      final ext = rawExt.isEmpty
          ? '.jpg'
          : (rawExt.startsWith('.') ? rawExt : '.$rawExt');
      final destFile = File(p.join(dir.path, '$stem$ext'));
      await destFile.writeAsBytes(cover.bytes, flush: true);
      return destFile.path;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to save EPUB cover image: ${e.message}',
        filePath: coverSaveDir,
        cause: e,
        stackTrace: st,
      );
    }
  }

  static String _sanitizeFileStem(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'epub_cover' : cleaned;
  }

  static String _canonicalPathKey(String filePath) {
    final normalized = p.normalize(File(filePath).absolute.path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static String _deriveTitleFromPath(String filePath) {
    final base = p.basenameWithoutExtension(filePath).trim();
    if (base.isNotEmpty) return base;
    final full = p.basename(filePath).trim();
    return full.isNotEmpty ? full : 'Untitled';
  }

  static String _deriveBookId(String filePath) {
    final normalized = _canonicalPathKey(filePath);
    final bytes = utf8.encode(normalized);
    var h1 = -3750763034362895579;
    var h2 = 0x9e3779b97f4a7c15;
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      h1 = (h1 ^ b) * 0x100000001b3;
      h2 = (h2 ^ (b + i)) * 0x100000001b3;
    }
    String hex(int v) =>
        (((v >>> 32) & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')) +
        ((v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0'));
    return 'epub_${hex(h1)}${hex(h2)}';
  }
}

class _CachedEpubIndex {
  const _CachedEpubIndex({
    required this.fileSize,
    required this.modifiedMs,
    required this.opfPath,
    required this.chapters,
    required this.knownArchivePaths,
  });

  final int fileSize;
  final int modifiedMs;
  final String opfPath;
  final List<EpubChapterEntry> chapters;
  final Set<String> knownArchivePaths;
}
