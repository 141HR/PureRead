import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../../domain/failures/app_failure.dart';
import 'epub_models.dart';
import 'epub_path_utils.dart';
import 'epub_xhtml_extractor.dart';

/// Pure-Dart, `Isolate.run`-safe EPUB 2/3 ZIP container & package parser.
///
/// Parses `META-INF/container.xml` with `.opf` scan fallback, OPF `<metadata>`,
/// `<manifest>`, `<spine>`, cover image extraction (`cover-image` /
/// `<meta name="cover">` / fallback), and ordered chapter resolution
/// (EPUB 3 NAV -> EPUB 2 NCX -> OPF `<spine>` fallback).
class EpubContainerParser {
  const EpubContainerParser();

  /// Parses an EPUB file at [filePath] inside a background [Isolate].
  Future<EpubParsedBook> parseFile(
    String filePath, {
    bool extractCover = true,
  }) {
    return Isolate.run(
      () => parseFileSync(filePath, extractCover: extractCover),
    );
  }

  /// Reads and extracts text for a single chapter [epubHref] inside a
  /// background [Isolate].
  Future<String> readChapterTextFromFile({
    required String filePath,
    required String epubHref,
    String? stopFragment,
    List<String> stopFragments = const <String>[],
  }) {
    return Isolate.run(
      () => readChapterTextFromFileSync(
        filePath: filePath,
        epubHref: epubHref,
        stopFragment: stopFragment,
        stopFragments: stopFragments,
      ),
    );
  }

  /// Synchronous isolate-safe EPUB file parser using streaming ZIP directory
  /// reads (`InputFileStream` + `ZipDecoder.decodeStream`).
  static EpubParsedBook parseFileSync(
    String filePath, {
    bool extractCover = true,
  }) {
    _ensureReadableFileSync(filePath);
    final fileSizeBytes = File(filePath).lengthSync();
    final fileHash = EpubPathUtils.computeFastFileHashSync(filePath);

    InputFileStream? input;
    Archive? archive;
    try {
      input = InputFileStream(filePath);
      archive = ZipDecoder().decodeStream(input, verify: true);
      return _parseArchive(
        archive,
        filePath: filePath,
        fileSizeBytes: fileSizeBytes,
        fileHash: fileHash,
        extractCover: extractCover,
      );
    } on AppFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to read EPUB file: ${e.message}',
        filePath: filePath,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on ArchiveException catch (e, st) {
      throw SourceParseFailure(
        message: 'Malformed or non-EPUB ZIP archive: ${e.message}',
        step: 'detail',
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on XmlException catch (e, st) {
      throw SourceParseFailure(
        message: 'Malformed XML in EPUB package: ${e.message}',
        step: 'detail',
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on FormatException catch (e, st) {
      throw SourceParseFailure(
        message: 'Malformed EPUB archive payload: ${e.message}',
        step: 'detail',
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on RangeError catch (e, st) {
      throw SourceParseFailure(
        message: 'Truncated or corrupted EPUB ZIP structure: $e',
        step: 'detail',
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } finally {
      archive?.clearSync();
      input?.closeSync();
    }
  }

  /// Parses an in-memory EPUB ZIP byte buffer.
  static EpubParsedBook parseBytes(
    Uint8List bytes, {
    String filePath = '',
    bool extractCover = true,
  }) {
    if (bytes.isEmpty) {
      throw const SourceParseFailure(
        message: 'EPUB byte buffer is empty',
        step: 'detail',
      );
    }
    Archive? archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
      return _parseArchive(
        archive,
        filePath: filePath,
        fileSizeBytes: bytes.length,
        fileHash: EpubPathUtils.computeFastBytesHash(bytes),
        extractCover: extractCover,
      );
    } on AppFailure {
      rethrow;
    } on ArchiveException catch (e, st) {
      throw SourceParseFailure(
        message: 'Malformed or non-EPUB ZIP bytes: ${e.message}',
        step: 'detail',
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on XmlException catch (e, st) {
      throw SourceParseFailure(
        message: 'Malformed XML in EPUB package: ${e.message}',
        step: 'detail',
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on FormatException catch (e, st) {
      throw SourceParseFailure(
        message: 'Malformed EPUB byte payload: ${e.message}',
        step: 'detail',
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on RangeError catch (e, st) {
      throw SourceParseFailure(
        message: 'Truncated or corrupted EPUB ZIP bytes: $e',
        step: 'detail',
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } finally {
      archive?.clearSync();
    }
  }

  /// Synchronous isolate-safe reader for a single chapter [epubHref] inside an
  /// EPUB file at [filePath].
  static String readChapterTextFromFileSync({
    required String filePath,
    required String epubHref,
    String? stopFragment,
    List<String> stopFragments = const <String>[],
  }) {
    _ensureReadableFileSync(filePath);
    InputFileStream? input;
    Archive? archive;
    try {
      input = InputFileStream(filePath);
      archive = ZipDecoder().decodeStream(input, verify: true);
      return _readChapterFromArchive(
        archive,
        epubHref: epubHref,
        stopFragment: stopFragment,
        stopFragments: stopFragments,
      );
    } on AppFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to read EPUB file: ${e.message}',
        filePath: filePath,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on ArchiveException catch (e, st) {
      throw SourceParseFailure(
        message: 'Corrupted EPUB ZIP while reading chapter: ${e.message}',
        step: 'content',
        rule: epubHref,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on FormatException catch (e, st) {
      throw SourceParseFailure(
        message: 'Malformed EPUB chapter payload: ${e.message}',
        step: 'content',
        rule: epubHref,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on RangeError catch (e, st) {
      throw SourceParseFailure(
        message: 'Corrupted EPUB ZIP entry: $e',
        step: 'content',
        rule: epubHref,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } finally {
      archive?.clearSync();
      input?.closeSync();
    }
  }

  /// Reads and extracts a single chapter [epubHref] from in-memory EPUB bytes.
  static String readChapterTextFromBytes(
    Uint8List epubBytes, {
    required String epubHref,
    String? stopFragment,
    List<String> stopFragments = const <String>[],
  }) {
    if (epubBytes.isEmpty) {
      throw const SourceParseFailure(
        message: 'EPUB byte buffer is empty',
        step: 'content',
      );
    }
    Archive? archive;
    try {
      archive = ZipDecoder().decodeBytes(epubBytes, verify: true);
      return _readChapterFromArchive(
        archive,
        epubHref: epubHref,
        stopFragment: stopFragment,
        stopFragments: stopFragments,
      );
    } on AppFailure {
      rethrow;
    } on ArchiveException catch (e, st) {
      throw SourceParseFailure(
        message: 'Corrupted EPUB ZIP bytes while reading chapter: ${e.message}',
        step: 'content',
        rule: epubHref,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } finally {
      archive?.clearSync();
    }
  }

  static void _ensureReadableFileSync(String filePath) {
    try {
      final type = FileSystemEntity.typeSync(filePath);
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
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Cannot access EPUB file: ${e.message}',
        filePath: filePath,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    }
  }

  static String _readChapterFromArchive(
    Archive archive, {
    required String epubHref,
    String? stopFragment,
    List<String> stopFragments = const <String>[],
  }) {
    final trimmedHref = epubHref.trim();
    if (trimmedHref.isEmpty) {
      throw const SourceParseFailure(
        message: 'EPUB chapter href is empty',
        step: 'content',
      );
    }

    final index = _ArchiveIndex.fromArchive(archive);
    final split = EpubPathUtils.splitHref(trimmedHref);
    final rawPath = split.path;
    final decodedPath = EpubPathUtils.normalizeArchivePath(
      EpubPathUtils.safeUrlDecode(rawPath),
    );
    final rawNormPath = EpubPathUtils.normalizeArchivePath(rawPath);

    var entry = index.findAny(<String>[decodedPath, rawNormPath]);
    if (entry == null) {
      // Fallback: caller may have supplied an OPF-relative href; locate OPF
      // and resolve relative to its folder.
      final opf = _locateOpf(index, throwIfMissing: false);
      if (opf != null) {
        final resolved = EpubPathUtils.resolveHref(opf.path, rawPath);
        entry = index.findAny(<String>[
          resolved.archivePath,
          resolved.rawArchivePath,
        ]);
      }
    }

    if (entry == null) {
      throw SourceParseFailure(
        message: 'EPUB chapter entry not found: $decodedPath',
        step: 'content',
        rule: epubHref,
      );
    }

    final bytes = _readEntryBytes(entry);
    return EpubXhtmlExtractor.extractText(
      bytes,
      fragment: split.fragment,
      stopFragment: stopFragment,
      stopFragments: stopFragments,
    );
  }

  static EpubParsedBook _parseArchive(
    Archive archive, {
    required String filePath,
    required int fileSizeBytes,
    required String fileHash,
    required bool extractCover,
  }) {
    final index = _ArchiveIndex.fromArchive(archive);
    if (index.isEmpty) {
      throw const SourceParseFailure(
        message: 'EPUB ZIP archive contains no files',
        step: 'detail',
      );
    }

    final opfResolved = _locateOpf(index, throwIfMissing: true)!;
    final opfPath = opfResolved.path;
    final opfDoc = opfResolved.document;
    final packageEl = opfDoc.rootElement;

    final metadataEl = _findFirstElement(packageEl, 'metadata');
    final metaParse = _parseMetadata(metadataEl);

    final manifestEl = _findFirstElement(packageEl, 'manifest');
    final manifestParse = _parseManifest(
      manifestEl,
      opfPath: opfPath,
      index: index,
    );

    final spineEl = _findFirstElement(packageEl, 'spine');
    if (spineEl == null) {
      throw const SourceParseFailure(
        message: 'EPUB OPF package is missing <spine>',
        step: 'toc',
      );
    }
    final spineTocId = spineEl.getAttribute('toc')?.trim();
    final spine = _parseSpine(spineEl, manifestParse.byId);
    if (spine.isEmpty) {
      throw const SourceParseFailure(
        message: 'EPUB <spine> has no valid chapter references',
        step: 'toc',
      );
    }

    EpubCoverData? cover;
    if (extractCover) {
      final guideEl = _findFirstElement(packageEl, 'guide');
      cover = _extractCover(
        index: index,
        opfPath: opfPath,
        manifest: manifestParse.items,
        byId: manifestParse.byId,
        metaCoverId: metaParse.coverId,
        guideEl: guideEl,
      );
    }

    final chapters = _buildChapters(
      index: index,
      opfPath: opfPath,
      bookTitle: metaParse.metadata.title,
      manifest: manifestParse.items,
      byId: manifestParse.byId,
      spineTocId: spineTocId,
      spine: spine,
    );

    return EpubParsedBook(
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      fileHash: fileHash,
      opfPath: opfPath,
      metadata: metaParse.metadata,
      manifest: List<EpubManifestItem>.unmodifiable(manifestParse.items),
      spine: List<EpubSpineItem>.unmodifiable(spine),
      chapters: List<EpubChapterEntry>.unmodifiable(chapters),
      cover: cover,
    );
  }

  static ({String path, XmlDocument document})? _locateOpf(
    _ArchiveIndex index, {
    required bool throwIfMissing,
  }) {
    final containerEntry = index.find('META-INF/container.xml');
    if (containerEntry != null) {
      try {
        final containerXml = EpubXhtmlExtractor.decodeBytesToString(
          _readEntryBytes(containerEntry),
        );
        final doc = XmlDocument.parse(containerXml);
        final rootfiles = doc
            .findAllElements('rootfile', namespaceUri: '*')
            .toList(growable: false);

        final orderedCandidates = <String>[];
        for (final rf in rootfiles) {
          final fullPath = rf.getAttribute('full-path')?.trim() ?? '';
          if (fullPath.isEmpty) continue;
          final mediaType =
              rf.getAttribute('media-type')?.trim().toLowerCase() ?? '';
          if (mediaType == 'application/oebps-package+xml' ||
              fullPath.toLowerCase().endsWith('.opf')) {
            orderedCandidates.insert(0, fullPath);
          } else {
            orderedCandidates.add(fullPath);
          }
        }

        for (final rawPath in orderedCandidates) {
          final decoded = EpubPathUtils.normalizeArchivePath(
            EpubPathUtils.safeUrlDecode(rawPath),
          );
          final rawNorm = EpubPathUtils.normalizeArchivePath(rawPath);
          final entry = index.findAny(<String>[decoded, rawNorm]);
          if (entry != null) {
            final parsedOpf = _tryParseOpfEntry(entry);
            if (parsedOpf != null) {
              return (path: entry.normalizedPath, document: parsedOpf);
            }
          }
        }
      } on XmlException {
        // Fall back to scanning the ZIP for .opf files.
      } on SourceParseFailure {
        // Fall back to scanning the ZIP for .opf files.
      }
    }

    // Fallback scan for *.opf when container.xml is absent or malformed.
    final opfEntries = index.entries
        .where((e) => e.normalizedPath.toLowerCase().endsWith('.opf'))
        .toList(growable: false)
      ..sort((a, b) {
        final depthA = '/'.allMatches(a.normalizedPath).length;
        final depthB = '/'.allMatches(b.normalizedPath).length;
        if (depthA != depthB) return depthA.compareTo(depthB);
        if (a.normalizedPath.length != b.normalizedPath.length) {
          return a.normalizedPath.length.compareTo(b.normalizedPath.length);
        }
        return a.normalizedPath.compareTo(b.normalizedPath);
      });

    for (final entry in opfEntries) {
      final doc = _tryParseOpfEntry(entry);
      if (doc != null) {
        return (path: entry.normalizedPath, document: doc);
      }
    }

    if (throwIfMissing) {
      throw const SourceParseFailure(
        message: 'No valid OPF package found in EPUB archive',
        step: 'detail',
      );
    }
    return null;
  }

  static XmlDocument? _tryParseOpfEntry(_IndexedArchiveEntry entry) {
    try {
      final xmlText = EpubXhtmlExtractor.decodeBytesToString(
        _readEntryBytes(entry),
      );
      if (xmlText.trim().isEmpty) return null;
      final doc = XmlDocument.parse(xmlText);
      final rootName = doc.rootElement.localName.toLowerCase();
      if (rootName == 'package' ||
          _findFirstElement(doc.rootElement, 'manifest') != null ||
          _findFirstElement(doc.rootElement, 'spine') != null) {
        return doc;
      }
      return null;
    } on XmlException {
      return null;
    } on SourceParseFailure {
      return null;
    }
  }

  static ({EpubMetadata metadata, String? coverId}) _parseMetadata(
    XmlElement? metadataEl,
  ) {
    if (metadataEl == null) {
      return (metadata: const EpubMetadata(), coverId: null);
    }

    var title = '';
    for (final el in metadataEl.findAllElements('title', namespaceUri: '*')) {
      final candidate = EpubXhtmlExtractor.normalizeInlineText(el.innerText);
      if (candidate.isNotEmpty) {
        title = candidate;
        break;
      }
    }

    final authors = <String>[];
    for (final el in metadataEl.findAllElements('creator', namespaceUri: '*')) {
      final candidate = EpubXhtmlExtractor.normalizeInlineText(el.innerText);
      if (candidate.isNotEmpty && !authors.contains(candidate)) {
        authors.add(candidate);
      }
    }

    var description = '';
    for (final el in metadataEl.findAllElements(
      'description',
      namespaceUri: '*',
    )) {
      final rawDesc = el.innerText.trim();
      if (rawDesc.isEmpty) continue;
      if (RegExp(r'<[a-zA-Z/][^>]*>').hasMatch(rawDesc)) {
        description = EpubXhtmlExtractor.extractTextFromHtml(rawDesc);
      } else {
        description = rawDesc;
      }
      if (description.isNotEmpty) break;
    }

    var language = '';
    for (final el in metadataEl.findAllElements('language', namespaceUri: '*')) {
      final candidate = EpubXhtmlExtractor.normalizeInlineText(el.innerText);
      if (candidate.isNotEmpty) {
        language = candidate;
        break;
      }
    }

    var identifier = '';
    for (final el in metadataEl.findAllElements(
      'identifier',
      namespaceUri: '*',
    )) {
      final candidate = EpubXhtmlExtractor.normalizeInlineText(el.innerText);
      if (candidate.isNotEmpty) {
        identifier = candidate;
        break;
      }
    }

    String? coverId;
    for (final meta in metadataEl.findAllElements('meta', namespaceUri: '*')) {
      final name = meta.getAttribute('name')?.trim().toLowerCase();
      if (name == 'cover') {
        final content = meta.getAttribute('content')?.trim();
        if (content != null && content.isNotEmpty) {
          coverId = content;
          break;
        }
      }
    }

    return (
      metadata: EpubMetadata(
        title: title,
        author: authors.join(', '),
        description: description,
        language: language,
        identifier: identifier,
      ),
      coverId: coverId,
    );
  }

  static ({
    List<EpubManifestItem> items,
    Map<String, EpubManifestItem> byId,
    Map<String, EpubManifestItem> byArchivePath,
  }) _parseManifest(
    XmlElement? manifestEl, {
    required String opfPath,
    required _ArchiveIndex index,
  }) {
    final items = <EpubManifestItem>[];
    final byId = <String, EpubManifestItem>{};
    final byArchivePath = <String, EpubManifestItem>{};

    if (manifestEl == null) {
      return (items: items, byId: byId, byArchivePath: byArchivePath);
    }

    for (final el in manifestEl.findElements('item', namespaceUri: '*')) {
      final id = el.getAttribute('id')?.trim() ?? '';
      final rawHref = el.getAttribute('href')?.trim() ?? '';
      final mediaType = el.getAttribute('media-type')?.trim() ?? '';
      if (id.isEmpty || rawHref.isEmpty) continue;

      final propsRaw = el.getAttribute('properties')?.trim() ?? '';
      final properties = propsRaw.isEmpty
          ? const <String>[]
          : propsRaw
                .split(RegExp(r'\s+'))
                .where((s) => s.isNotEmpty)
                .toList(growable: false);

      final resolved = EpubPathUtils.resolveHref(opfPath, rawHref);
      final matchedEntry = index.findAny(<String>[
        resolved.archivePath,
        resolved.rawArchivePath,
      ]);
      final canonicalPath = matchedEntry?.normalizedPath ?? resolved.archivePath;

      final item = EpubManifestItem(
        id: id,
        archivePath: canonicalPath,
        rawHref: rawHref,
        mediaType: mediaType,
        properties: properties,
      );
      items.add(item);
      byId[id] = item;
      byArchivePath[canonicalPath] = item;
    }

    return (items: items, byId: byId, byArchivePath: byArchivePath);
  }

  static List<EpubSpineItem> _parseSpine(
    XmlElement spineEl,
    Map<String, EpubManifestItem> byId,
  ) {
    final spine = <EpubSpineItem>[];
    for (final itemref in spineEl.findElements('itemref', namespaceUri: '*')) {
      final idref = itemref.getAttribute('idref')?.trim() ?? '';
      if (idref.isEmpty) continue;
      final item = byId[idref];
      if (item == null) continue;
      final linearAttr =
          itemref.getAttribute('linear')?.trim().toLowerCase() ?? 'yes';
      spine.add(
        EpubSpineItem(
          idref: idref,
          manifestItem: item,
          linear: linearAttr != 'no',
        ),
      );
    }
    return spine;
  }

  static EpubCoverData? _extractCover({
    required _ArchiveIndex index,
    required String opfPath,
    required List<EpubManifestItem> manifest,
    required Map<String, EpubManifestItem> byId,
    required String? metaCoverId,
    required XmlElement? guideEl,
  }) {
    EpubManifestItem? candidateItem;

    // 1. EPUB 3 manifest item with properties="cover-image".
    for (final item in manifest) {
      if (item.hasProperty('cover-image')) {
        candidateItem = item;
        break;
      }
    }

    // 2. EPUB 2 <meta name="cover" content="id"/>.
    if (candidateItem == null && metaCoverId != null) {
      final byMetaId = byId[metaCoverId];
      if (byMetaId != null) {
        if (byMetaId.isImageLike) {
          candidateItem = byMetaId;
        } else if (byMetaId.isHtmlLike) {
          final htmlCover = _extractCoverFromHtmlEntry(
            index: index,
            htmlPath: byMetaId.archivePath,
          );
          if (htmlCover != null) return htmlCover;
        }
      }
      if (candidateItem == null && byMetaId == null) {
        final resolved = EpubPathUtils.resolveHref(opfPath, metaCoverId);
        for (final item in manifest) {
          if (item.isImageLike &&
              (item.rawHref == metaCoverId ||
                  item.archivePath == resolved.archivePath)) {
            candidateItem = item;
            break;
          }
        }
        if (candidateItem == null) {
          final directEntry = index.findAny(<String>[
            resolved.archivePath,
            resolved.rawArchivePath,
          ]);
          if (directEntry != null) {
            final ext = p.posix.extension(directEntry.normalizedPath).toLowerCase();
            if (_isDirectImageExtension(ext)) {
              return _coverFromEntry(directEntry, mediaType: null);
            }
          }
        }
      }
    }

    // 3. Fallback: manifest cover item id or href heuristics.
    if (candidateItem == null) {
      for (final item in manifest) {
        if (!item.isImageLike) continue;
        final idLower = item.id.toLowerCase();
        final baseLower = p.posix
            .basenameWithoutExtension(item.archivePath)
            .toLowerCase();
        if (idLower == 'cover' ||
            idLower == 'cover-image' ||
            baseLower == 'cover') {
          candidateItem = item;
          break;
        }
      }
    }

    if (candidateItem == null) {
      for (final item in manifest) {
        if (!item.isImageLike) continue;
        final idLower = item.id.toLowerCase();
        final pathLower = item.archivePath.toLowerCase();
        if (idLower.contains('cover') || pathLower.contains('cover')) {
          candidateItem = item;
          break;
        }
      }
    }

    // 4. Fallback: OPF <guide><reference type="cover" href="..."/>.
    if (candidateItem == null && guideEl != null) {
      for (final ref in guideEl.findElements('reference', namespaceUri: '*')) {
        final type = ref.getAttribute('type')?.trim().toLowerCase() ?? '';
        final href = ref.getAttribute('href')?.trim() ?? '';
        if (type == 'cover' && href.isNotEmpty) {
          final resolved = EpubPathUtils.resolveHref(opfPath, href);
          final entry = index.findAny(<String>[
            resolved.archivePath,
            resolved.rawArchivePath,
          ]);
          if (entry != null) {
            final ext = p.posix.extension(entry.normalizedPath).toLowerCase();
            if (_isDirectImageExtension(ext)) {
              return _coverFromEntry(entry, mediaType: null);
            }
            final htmlCover = _extractCoverFromHtmlEntry(
              index: index,
              htmlPath: entry.normalizedPath,
            );
            if (htmlCover != null) return htmlCover;
          }
        }
      }
    }

    if (candidateItem == null) return null;

    final coverEntry = index.find(candidateItem.archivePath);
    if (coverEntry != null) {
      return _coverFromEntry(coverEntry, mediaType: candidateItem.mediaType);
    }
    return null;
  }

  static EpubCoverData? _extractCoverFromHtmlEntry({
    required _ArchiveIndex index,
    required String htmlPath,
  }) {
    final entry = index.find(htmlPath);
    if (entry == null) return null;
    final bytes = _readEntryBytesSafe(entry);
    if (bytes == null || bytes.isEmpty) return null;
    final htmlText = EpubXhtmlExtractor.decodeBytesToString(bytes);
    final imgSrc = _extractFirstImageSrc(htmlText);
    if (imgSrc == null) return null;
    final imgResolved = EpubPathUtils.resolveHref(entry.normalizedPath, imgSrc);
    final imgEntry = index.findAny(<String>[
      imgResolved.archivePath,
      imgResolved.rawArchivePath,
    ]);
    if (imgEntry == null) return null;
    return _coverFromEntry(imgEntry, mediaType: null);
  }

  static EpubCoverData? _coverFromEntry(
    _IndexedArchiveEntry entry, {
    required String? mediaType,
  }) {
    final bytes = _readEntryBytesSafe(entry);
    if (bytes == null || bytes.isEmpty) return null;
    final ext = EpubPathUtils.inferImageExtension(
      archivePath: entry.normalizedPath,
      mediaType: mediaType,
      bytes: bytes,
    );
    return EpubCoverData(
      bytes: bytes,
      extension: ext,
      archivePath: entry.normalizedPath,
      mediaType: mediaType,
    );
  }

  static String? _extractFirstImageSrc(String htmlText) {
    if (htmlText.trim().isEmpty) return null;
    final doc = html_parser.parse(htmlText);
    final img = doc.querySelector('img');
    final src = img?.attributes['src']?.trim();
    if (src != null && src.isNotEmpty) return src;
    final svgImg = doc.querySelector('image');
    if (svgImg != null) {
      for (final entry in svgImg.attributes.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key == 'href' || key == 'xlink:href') {
          final val = entry.value.trim();
          if (val.isNotEmpty) return val;
        }
      }
    }
    return null;
  }

  static bool _isDirectImageExtension(String ext) {
    return ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.png' ||
        ext == '.webp' ||
        ext == '.gif' ||
        ext == '.bmp';
  }

  static List<EpubChapterEntry> _buildChapters({
    required _ArchiveIndex index,
    required String opfPath,
    required String bookTitle,
    required List<EpubManifestItem> manifest,
    required Map<String, EpubManifestItem> byId,
    required String? spineTocId,
    required List<EpubSpineItem> spine,
  }) {
    // 1. Prefer EPUB 3 NAV (manifest item with properties="nav").
    for (final item in manifest) {
      if (!item.hasProperty('nav')) continue;
      final navEntry = index.find(item.archivePath);
      if (navEntry == null) continue;
      final navChapters = _parseNavChapters(
        navEntry: navEntry,
        opfPath: opfPath,
        index: index,
      );
      if (navChapters.isNotEmpty) {
        return navChapters;
      }
    }

    // 2. Fall back to EPUB 2 NCX (<spine toc="id"> or application/x-dtbncx+xml).
    EpubManifestItem? ncxItem;
    if (spineTocId != null && spineTocId.isNotEmpty) {
      ncxItem = byId[spineTocId];
    }
    if (ncxItem == null) {
      for (final item in manifest) {
        if (item.mediaType.toLowerCase() == 'application/x-dtbncx+xml' ||
            item.archivePath.toLowerCase().endsWith('.ncx')) {
          ncxItem = item;
          break;
        }
      }
    }
    if (ncxItem != null) {
      final ncxEntry = index.find(ncxItem.archivePath);
      if (ncxEntry != null) {
        final ncxChapters = _parseNcxChapters(
          ncxEntry: ncxEntry,
          opfPath: opfPath,
          index: index,
        );
        if (ncxChapters.isNotEmpty) {
          return ncxChapters;
        }
      }
    }

    // 3. Fall back to OPF <spine> <itemref> order.
    final linearItems = spine
        .where((item) => item.linear)
        .toList(growable: false);
    final selectedSpine = linearItems.isNotEmpty ? linearItems : spine;

    final chapters = <EpubChapterEntry>[];
    for (var i = 0; i < selectedSpine.length; i++) {
      final item = selectedSpine[i].manifestItem;
      final chapterTitle = _inferSpineChapterTitle(
        index: index,
        item: item,
        bookTitle: bookTitle,
        fallbackIndex: i,
      );
      chapters.add(
        EpubChapterEntry(
          chapterIndex: i,
          title: chapterTitle,
          epubHref: item.archivePath,
          archivePath: item.archivePath,
        ),
      );
    }
    return chapters;
  }

  static List<EpubChapterEntry> _parseNavChapters({
    required _IndexedArchiveEntry navEntry,
    required String opfPath,
    required _ArchiveIndex index,
  }) {
    final bytes = _readEntryBytesSafe(navEntry);
    if (bytes == null || bytes.isEmpty) return const <EpubChapterEntry>[];

    final htmlText = EpubXhtmlExtractor.decodeBytesToString(bytes);
    final doc = html_parser.parse(htmlText);
    final tocNav = _findTocNavElement(doc);
    if (tocNav == null) return const <EpubChapterEntry>[];

    final chapters = <EpubChapterEntry>[];

    void walkListContainer(dom.Element container) {
      for (final child in container.children) {
        final tag = (child.localName ?? '').toLowerCase();
        if (tag == 'li') {
          final anchor = _findDirectListItemAnchor(child);
          if (anchor != null) {
            final rawHref = anchor.attributes['href']?.trim() ?? '';
            if (rawHref.isNotEmpty && !_isExternalUri(rawHref)) {
              final resolved = _resolveTocHref(
                index: index,
                tocFilePath: navEntry.normalizedPath,
                opfPath: opfPath,
                rawHref: rawHref,
              );
              var title = EpubXhtmlExtractor.normalizeInlineText(anchor.text);
              if (title.isEmpty) {
                title =
                    anchor.attributes['title']?.trim() ??
                    anchor.querySelector('img')?.attributes['alt']?.trim() ??
                    '';
              }
              if (title.isEmpty) {
                title = 'Chapter ${chapters.length + 1}';
              }
              chapters.add(
                EpubChapterEntry(
                  chapterIndex: chapters.length,
                  title: title,
                  epubHref: resolved.epubHref,
                  archivePath: resolved.archivePath,
                  fragment: resolved.fragment,
                ),
              );
            }
          }
          for (final liChild in child.children) {
            final liChildTag = (liChild.localName ?? '').toLowerCase();
            if (liChildTag == 'ol' || liChildTag == 'ul') {
              walkListContainer(liChild);
            }
          }
        } else if (tag == 'ol' || tag == 'ul') {
          walkListContainer(child);
        }
      }
    }

    for (final child in tocNav.children) {
      final tag = (child.localName ?? '').toLowerCase();
      if (tag == 'ol' || tag == 'ul') {
        walkListContainer(child);
      }
    }
    if (chapters.isEmpty) {
      final fallbackList = tocNav.querySelector('ol, ul');
      if (fallbackList != null) {
        walkListContainer(fallbackList);
      }
    }
    return chapters;
  }

  static dom.Element? _findTocNavElement(dom.Document doc) {
    final navs = doc.querySelectorAll('nav');
    if (navs.isEmpty) return null;

    for (final nav in navs) {
      if (_navHasTypeToken(nav, 'toc') || _navHasRoleToken(nav, 'doc-toc')) {
        return nav;
      }
    }
    for (final nav in navs) {
      if (_navHasTypeToken(nav, 'landmarks') ||
          _navHasTypeToken(nav, 'page-list')) {
        continue;
      }
      final idOrClass =
          '${nav.id} ${nav.attributes['class'] ?? ''}'.toLowerCase();
      if (idOrClass.contains('toc')) {
        return nav;
      }
    }
    for (final nav in navs) {
      if (_navHasTypeToken(nav, 'landmarks') ||
          _navHasTypeToken(nav, 'page-list')) {
        continue;
      }
      if (nav.querySelector('a[href]') != null) {
        return nav;
      }
    }
    return null;
  }

  static bool _navHasTypeToken(dom.Element nav, String token) {
    for (final entry in nav.attributes.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key == 'epub:type' || key.endsWith(':type') || key == 'type') {
        final tokens = entry.value
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty);
        if (tokens.contains(token)) return true;
      }
    }
    return false;
  }

  static bool _navHasRoleToken(dom.Element nav, String token) {
    final role = nav.attributes['role']?.toLowerCase() ?? '';
    if (role.isEmpty) return false;
    return role.split(RegExp(r'\s+')).contains(token);
  }

  static dom.Element? _findDirectListItemAnchor(dom.Element li) {
    for (final child in li.children) {
      final tag = (child.localName ?? '').toLowerCase();
      if (tag == 'ol' || tag == 'ul') continue;
      if (tag == 'a') return child;
      final nested = child.querySelector('a');
      if (nested != null) return nested;
    }
    return null;
  }

  static List<EpubChapterEntry> _parseNcxChapters({
    required _IndexedArchiveEntry ncxEntry,
    required String opfPath,
    required _ArchiveIndex index,
  }) {
    final bytes = _readEntryBytesSafe(ncxEntry);
    if (bytes == null || bytes.isEmpty) return const <EpubChapterEntry>[];

    final ncxText = EpubXhtmlExtractor.decodeBytesToString(bytes);
    try {
      final doc = XmlDocument.parse(ncxText);
      final navMap = doc
          .findAllElements('navMap', namespaceUri: '*')
          .firstOrNull;
      if (navMap == null) return const <EpubChapterEntry>[];

      final chapters = <EpubChapterEntry>[];

      void visitNavPoint(XmlElement navPoint) {
        var title = '';
        final navLabel = _findFirstElement(navPoint, 'navLabel');
        if (navLabel != null) {
          final textEl = _findFirstElement(navLabel, 'text');
          if (textEl != null) {
            title = EpubXhtmlExtractor.normalizeInlineText(textEl.innerText);
          }
        }

        final contentEl = _findFirstElement(navPoint, 'content');
        final rawSrc = contentEl?.getAttribute('src')?.trim() ?? '';
        if (rawSrc.isNotEmpty && !_isExternalUri(rawSrc)) {
          final resolved = _resolveTocHref(
            index: index,
            tocFilePath: ncxEntry.normalizedPath,
            opfPath: opfPath,
            rawHref: rawSrc,
          );
          chapters.add(
            EpubChapterEntry(
              chapterIndex: chapters.length,
              title: title.isNotEmpty ? title : 'Chapter ${chapters.length + 1}',
              epubHref: resolved.epubHref,
              archivePath: resolved.archivePath,
              fragment: resolved.fragment,
            ),
          );
        }

        for (final childPoint in navPoint.findElements(
          'navPoint',
          namespaceUri: '*',
        )) {
          visitNavPoint(childPoint);
        }
      }

      for (final point in navMap.findElements('navPoint', namespaceUri: '*')) {
        visitNavPoint(point);
      }
      return chapters;
    } on XmlException {
      return _parseLooseNcxHtmlFallback(
        ncxText: ncxText,
        ncxPath: ncxEntry.normalizedPath,
        opfPath: opfPath,
        index: index,
      );
    }
  }

  static List<EpubChapterEntry> _parseLooseNcxHtmlFallback({
    required String ncxText,
    required String ncxPath,
    required String opfPath,
    required _ArchiveIndex index,
  }) {
    final doc = html_parser.parse(ncxText);
    final navMap = doc.querySelector('navmap');
    if (navMap == null) return const <EpubChapterEntry>[];

    final chapters = <EpubChapterEntry>[];

    void visitNavPoint(dom.Element navPoint) {
      String title = '';
      String rawSrc = '';
      for (final child in navPoint.children) {
        final tag = (child.localName ?? '').toLowerCase();
        if (tag == 'navlabel') {
          final textEl = child.querySelector('text');
          title = EpubXhtmlExtractor.normalizeInlineText(
            textEl?.text ?? child.text,
          );
        } else if (tag == 'content') {
          rawSrc = child.attributes['src']?.trim() ?? '';
        }
      }

      if (rawSrc.isNotEmpty && !_isExternalUri(rawSrc)) {
        final resolved = _resolveTocHref(
          index: index,
          tocFilePath: ncxPath,
          opfPath: opfPath,
          rawHref: rawSrc,
        );
        chapters.add(
          EpubChapterEntry(
            chapterIndex: chapters.length,
            title: title.isNotEmpty ? title : 'Chapter ${chapters.length + 1}',
            epubHref: resolved.epubHref,
            archivePath: resolved.archivePath,
            fragment: resolved.fragment,
          ),
        );
      }

      for (final child in navPoint.children) {
        if ((child.localName ?? '').toLowerCase() == 'navpoint') {
          visitNavPoint(child);
        }
      }
    }

    for (final child in navMap.children) {
      if ((child.localName ?? '').toLowerCase() == 'navpoint') {
        visitNavPoint(child);
      }
    }
    return chapters;
  }

  static ({String archivePath, String? fragment, String epubHref})
  _resolveTocHref({
    required _ArchiveIndex index,
    required String tocFilePath,
    required String opfPath,
    required String rawHref,
  }) {
    final primary = EpubPathUtils.resolveHref(tocFilePath, rawHref);
    final primaryMatch = index.findAny(<String>[
      primary.archivePath,
      primary.rawArchivePath,
    ]);
    if (primaryMatch != null) {
      final path = primaryMatch.normalizedPath;
      final frag = primary.fragment;
      return (
        archivePath: path,
        fragment: frag,
        epubHref: (frag != null && frag.isNotEmpty) ? '$path#$frag' : path,
      );
    }

    if (opfPath.isNotEmpty) {
      final fallback = EpubPathUtils.resolveHref(opfPath, rawHref);
      final fallbackMatch = index.findAny(<String>[
        fallback.archivePath,
        fallback.rawArchivePath,
      ]);
      if (fallbackMatch != null) {
        final path = fallbackMatch.normalizedPath;
        final frag = fallback.fragment;
        return (
          archivePath: path,
          fragment: frag,
          epubHref: (frag != null && frag.isNotEmpty) ? '$path#$frag' : path,
        );
      }
    }

    return (
      archivePath: primary.archivePath,
      fragment: primary.fragment,
      epubHref: primary.epubHref,
    );
  }

  static String _inferSpineChapterTitle({
    required _ArchiveIndex index,
    required EpubManifestItem item,
    required String bookTitle,
    required int fallbackIndex,
  }) {
    final entry = index.find(item.archivePath);
    if (entry != null && item.isHtmlLike) {
      final bytes = _readEntryBytesSafe(entry);
      if (bytes != null && bytes.isNotEmpty) {
        final htmlText = EpubXhtmlExtractor.decodeBytesToString(bytes);
        final titles = EpubXhtmlExtractor.extractDocumentTitles(htmlText);
        final heading = titles.heading;
        if (heading != null && heading.isNotEmpty && heading.length <= 120) {
          return heading;
        }
        final docTitle = titles.title;
        if (docTitle != null &&
            docTitle.isNotEmpty &&
            docTitle.length <= 120 &&
            docTitle != bookTitle) {
          return docTitle;
        }
      }
    }

    final stem = p.posix.basenameWithoutExtension(item.archivePath).trim();
    if (stem.isNotEmpty) return stem;
    return 'Chapter ${fallbackIndex + 1}';
  }

  static bool _isExternalUri(String rawHref) {
    final lower = rawHref.trim().toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('javascript:') ||
        lower.startsWith('data:');
  }

  static XmlElement? _findFirstElement(XmlElement parent, String localName) {
    for (final child in parent.findElements(localName, namespaceUri: '*')) {
      return child;
    }
    return null;
  }

  static Uint8List _readEntryBytes(_IndexedArchiveEntry entry) {
    try {
      final bytes = entry.file.readBytes();
      if (bytes == null) {
        throw SourceParseFailure(
          message: 'EPUB entry has no readable content: ${entry.normalizedPath}',
          step: 'content',
          rule: entry.normalizedPath,
        );
      }
      return bytes;
    } on ArchiveException catch (e, st) {
      throw SourceParseFailure(
        message:
            'Corrupted EPUB entry "${entry.normalizedPath}": ${e.message}',
        step: 'content',
        rule: entry.normalizedPath,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    } on FormatException catch (e, st) {
      throw SourceParseFailure(
        message:
            'Corrupted EPUB entry "${entry.normalizedPath}": ${e.message}',
        step: 'content',
        rule: entry.normalizedPath,
        cause: e.toString(),
        stackTrace: StackTrace.fromString(st.toString()),
      );
    }
  }

  static Uint8List? _readEntryBytesSafe(_IndexedArchiveEntry entry) {
    try {
      return entry.file.readBytes();
    } catch (_) {
      return null;
    }
  }
}

class _IndexedArchiveEntry {
  const _IndexedArchiveEntry({
    required this.normalizedPath,
    required this.file,
  });

  final String normalizedPath;
  final ArchiveFile file;
}

class _ArchiveIndex {
  _ArchiveIndex._(this.entries, this._exact, this._lower);

  factory _ArchiveIndex.fromArchive(Archive archive) {
    final entries = <_IndexedArchiveEntry>[];
    final exact = <String, _IndexedArchiveEntry>{};
    final lower = <String, _IndexedArchiveEntry>{};

    for (final file in archive.files) {
      if (!file.isFile) continue;
      final normalized = EpubPathUtils.normalizeArchivePath(file.name);
      if (normalized.isEmpty) continue;
      if (normalized.startsWith('__MACOSX/') || normalized == '__MACOSX') {
        continue;
      }
      final entry = _IndexedArchiveEntry(normalizedPath: normalized, file: file);
      entries.add(entry);
      exact[normalized] = entry;
      lower[normalized.toLowerCase()] = entry;
    }

    return _ArchiveIndex._(entries, exact, lower);
  }

  final List<_IndexedArchiveEntry> entries;
  final Map<String, _IndexedArchiveEntry> _exact;
  final Map<String, _IndexedArchiveEntry> _lower;

  bool get isEmpty => entries.isEmpty;

  _IndexedArchiveEntry? find(String path) {
    final norm = EpubPathUtils.normalizeArchivePath(path);
    if (norm.isEmpty) return null;
    return _exact[norm] ?? _lower[norm.toLowerCase()];
  }

  _IndexedArchiveEntry? findAny(Iterable<String> paths) {
    for (final path in paths) {
      final norm = EpubPathUtils.normalizeArchivePath(path);
      if (norm.isEmpty) continue;
      final exactHit = _exact[norm];
      if (exactHit != null) return exactHit;
    }
    for (final path in paths) {
      final norm = EpubPathUtils.normalizeArchivePath(path);
      if (norm.isEmpty) continue;
      final lowerHit = _lower[norm.toLowerCase()];
      if (lowerHit != null) return lowerHit;
    }
    return null;
  }
}
