import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';

/// Gateway signature for reading a single chapter's plain text from a local
/// `.epub` book, optionally passing sibling [chapters] so `#fragment`
/// multi-anchor slicing stops cleanly before the next chapter anchor.
typedef LocalEpubChapterReader =
    Future<String> Function(
      Book book,
      ChapterMeta chapter, {
      List<ChapterMeta>? chapters,
    });

/// Gateway signature for reading raw bytes of an embedded EPUB resource (such as
/// an inline illustration) identified by its normalized POSIX [archivePath].
typedef LocalEpubImageReader =
    Future<Uint8List?> Function(Book book, String archivePath);

/// Provides the active [LocalEpubChapterReader] implementation.
///
/// Overridden at app startup by `buildPureReadOverrides` with
/// `LocalEpubProvider.readChapterText`.
final localEpubChapterReaderProvider = Provider<LocalEpubChapterReader>((ref) {
  return (
    Book book,
    ChapterMeta chapter, {
    List<ChapterMeta>? chapters,
  }) async {
    throw FileAccessFailure(
      message: '本地 EPUB 读取引擎尚未装配，无法读取《${book.title}》${chapter.title}',
      filePath: book.localFilePath,
    );
  };
});

/// Provides the active [LocalEpubImageReader] implementation.
///
/// Overridden at app startup by `buildPureReadOverrides` with
/// `LocalEpubProvider.readImageBytes`.
final localEpubImageReaderProvider = Provider<LocalEpubImageReader>((ref) {
  return (Book book, String archivePath) async => null;
});
