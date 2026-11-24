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
