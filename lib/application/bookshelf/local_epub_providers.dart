import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';

/// Gateway signature for importing a local `.epub` file into a [Book] and its
/// ordered [ChapterMeta] list (extracting and saving any cover image to disk).
typedef EpubBookImporter =
    Future<({Book book, List<ChapterMeta> chapters})> Function(
      String filePath,
    );

/// Provides the active [EpubBookImporter] implementation.
///
/// Overridden at app startup by `buildPureReadOverrides` with
/// `LocalEpubProvider.importEpubFile(..., coverSaveDir: coversDir)`.
final epubBookImporterProvider = Provider<EpubBookImporter>((ref) {
  return (String filePath) async {
    throw FileAccessFailure(
      message: 'EPUB 导入引擎尚未装配，无法导入：$filePath',
      filePath: filePath,
    );
  };
});

/// Resolves a [FileImage] for [coverPath] when the path is non-empty and exists
/// on disk, or returns `null` so UI falls back cleanly to a placeholder cover.
ImageProvider? resolveLocalCoverImageProvider(String? coverPath) {
  final trimmed = coverPath?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final file = File(trimmed);
  if (!file.existsSync()) return null;
  return FileImage(file);
}
