import 'dart:typed_data';

/// Bibliographic metadata extracted from an EPUB OPF `<metadata>` element.
class EpubMetadata {
  const EpubMetadata({
    this.title = '',
    this.author = '',
    this.description = '',
    this.language = '',
    this.identifier = '',
  });

  final String title;
  final String author;
  final String description;
  final String language;
  final String identifier;
}

/// Single `<item>` entry from an EPUB OPF `<manifest>`.
class EpubManifestItem {
  const EpubManifestItem({
    required this.id,
    required this.archivePath,
    required this.rawHref,
    required this.mediaType,
    this.properties = const <String>[],
  });

  final String id;

  /// Normalized POSIX archive path relative to the EPUB ZIP root.
  final String archivePath;

  /// Raw `href` string declared in the OPF `<manifest>`.
  final String rawHref;
  final String mediaType;
  final List<String> properties;

  bool hasProperty(String token) {
    final needle = token.toLowerCase();
    for (final prop in properties) {
      if (prop.toLowerCase() == needle) return true;
    }
    return false;
  }

  bool get isHtmlLike {
    final mt = mediaType.toLowerCase();
    if (mt == 'application/xhtml+xml' || mt == 'text/html') {
      return true;
    }
    final lower = archivePath.toLowerCase();
    return lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  bool get isImageLike {
    final mt = mediaType.toLowerCase();
    if (mt.startsWith('image/')) return true;
    final lower = archivePath.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg');
  }
}

/// Single `<itemref>` entry from an EPUB OPF `<spine>`.
class EpubSpineItem {
  const EpubSpineItem({
    required this.idref,
    required this.manifestItem,
    this.linear = true,
  });

  final String idref;
  final EpubManifestItem manifestItem;
  final bool linear;
}

/// Ordered table-of-contents chapter entry resolved from EPUB 3 NAV, EPUB 2 NCX,
/// or OPF `<spine>` fallback.
class EpubChapterEntry {
  const EpubChapterEntry({
    required this.chapterIndex,
    required this.title,
    required this.epubHref,
    required this.archivePath,
    this.fragment,
  });

  final int chapterIndex;
  final String title;

  /// Archive-normalized POSIX path plus optional `#fragment` anchor.
  final String epubHref;

  /// Archive-normalized POSIX path without `#fragment`.
  final String archivePath;

  /// Optional decoded `#fragment` identifier (without leading `#`).
  final String? fragment;
}

/// Extracted cover image payload and inferred extension from an EPUB archive.
class EpubCoverData {
  const EpubCoverData({
    required this.bytes,
    required this.extension,
    required this.archivePath,
    this.mediaType,
  });

  final Uint8List bytes;

  /// File extension with leading dot (e.g. `.jpg`, `.png`), or empty string
  /// if unknown.
  final String extension;
  final String archivePath;
  final String? mediaType;
}

/// Isolate-sendable result of parsing an EPUB 2/3 container and package.
class EpubParsedBook {
  const EpubParsedBook({
    required this.filePath,
    required this.fileSizeBytes,
    required this.fileHash,
    required this.opfPath,
    required this.metadata,
    required this.manifest,
    required this.spine,
    required this.chapters,
    this.cover,
  });

  final String filePath;
  final int fileSizeBytes;
  final String fileHash;
  final String opfPath;
  final EpubMetadata metadata;
  final List<EpubManifestItem> manifest;
  final List<EpubSpineItem> spine;
  final List<EpubChapterEntry> chapters;
  final EpubCoverData? cover;
}
