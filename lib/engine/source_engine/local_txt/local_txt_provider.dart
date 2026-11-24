import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/entities/book.dart';
import '../../../domain/entities/book_search_item.dart';
import '../../../domain/entities/chapter.dart';
import '../../../domain/failures/app_failure.dart';
import '../../../domain/services/book_provider.dart';
import '../../../domain/value_objects/cancellation_token.dart';
import '../../../domain/value_objects/provider_capabilities.dart';
import '../../../domain/value_objects/source_debug_trace.dart';
import 'txt_encoding.dart';
import 'txt_isolate_worker.dart';

/// Local TXT implementation of [BookProvider].
///
/// Uses [TxtIsolateWorker] for non-blocking background encoding detection and
/// streaming chapter scanning, and `RandomAccessFile` byte-slice reads for
/// low-latency chapter loading without loading full files into memory.
class LocalTxtProvider implements BookProvider {
  LocalTxtProvider({
    this.providerId = 'local_txt',
    TxtIsolateWorker? worker,
  })  : _worker = worker ?? TxtIsolateWorker(),
        _ownsWorker = worker == null;

  @override
  final String providerId;

  final TxtIsolateWorker _worker;
  final bool _ownsWorker;

  @override
  ProviderType get type => ProviderType.localTxt;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        isLocal: true,
        supportsSearch: false,
        supportsUpdateCheck: false,
        supportsChangeSource: false,
      );

  /// Imports a local TXT file at [filePath], auto-detecting its encoding
  /// (unless [forcedEncoding] is provided) and scanning its chapter index in
  /// the background [TxtIsolateWorker].
  ///
  /// Throws [FileAccessFailure] if the file does not exist or cannot be read,
  /// and [EncodingFailure] if [forcedEncoding] is unsupported or the file
  /// encoding cannot be decoded.
  Future<({Book book, List<ChapterMeta> chapters})> importTxtFile(
    String filePath, {
    String? forcedEncoding,
    String? bookId,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    TxtEncoding? parsedForced;
    if (forcedEncoding != null) {
      parsedForced = TxtEncoding.tryParse(forcedEncoding);
      if (parsedForced == null) {
        throw EncodingFailure(
          message: 'Unsupported TXT encoding: $forcedEncoding',
          filePath: filePath,
          detectedEncoding: forcedEncoding,
        );
      }
    }

    await _ensureReadableFile(filePath);

    try {
      final scan = await _worker.scanFile(
        filePath,
        forcedEncoding: parsedForced,
      );
      cancelToken?.throwIfCancelled();

      final now = DateTime.now().toUtc();
      final resolvedBookId = bookId ?? _deriveBookId(filePath);
      final title = _deriveTitle(filePath);

      final chapters = scan.chapters
          .map(
            (entry) => ChapterMeta(
              bookId: resolvedBookId,
              chapterIndex: entry.chapterIndex,
              title: entry.title,
              byteStart: entry.byteStart,
              byteEnd: entry.byteEnd,
              updatedAt: now,
            ),
          )
          .toList(growable: false);

      final book = Book(
        id: resolvedBookId,
        providerType: ProviderType.localTxt,
        title: title,
        localFilePath: filePath,
        fileEncoding: scan.encoding.label,
        fileSizeBytes: scan.fileBytes,
        fileHash: scan.fileHash,
        totalChapters: chapters.length,
        lastChapterTitle: chapters.isNotEmpty ? chapters.last.title : '',
        createdAt: now,
        updatedAt: now,
      );

      return (book: book, chapters: chapters);
    } on AppFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to import TXT file: ${e.message}',
        filePath: filePath,
        cause: e,
        stackTrace: st,
      );
    } on FormatException catch (e, st) {
      throw EncodingFailure(
        message: 'Failed to decode TXT file: ${e.message}',
        filePath: filePath,
        detectedEncoding: forcedEncoding,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Reads and decodes a single [chapter]'s byte slice from [filePath] using
  /// `RandomAccessFile` inside [TxtIsolateWorker].
  ///
  /// Throws [FileAccessFailure] if [filePath] is missing or byte offsets are
  /// invalid, and [EncodingFailure] if [encoding] is unsupported or decoding
  /// encounters invalid byte sequences.
  Future<String> readChapterText({
    required String filePath,
    required String encoding,
    required ChapterMeta chapter,
    bool allowMalformed = false,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final parsedEncoding = TxtEncoding.tryParse(encoding);
    if (parsedEncoding == null) {
      throw EncodingFailure(
        message: 'Unsupported TXT encoding: $encoding',
        filePath: filePath,
        detectedEncoding: encoding,
      );
    }

    final byteStart = chapter.byteStart;
    final byteEnd = chapter.byteEnd;
    if (byteStart == null || byteEnd == null || byteStart < 0 || byteEnd < byteStart) {
      throw FileAccessFailure(
        message:
            'Invalid byte range [$byteStart, $byteEnd) for chapter "${chapter.title}"',
        filePath: filePath,
      );
    }

    await _ensureReadableFile(filePath);

    try {
      final result = await _worker.readChapter(
        filePath: filePath,
        chapterIndex: chapter.chapterIndex,
        title: chapter.title,
        byteStart: byteStart,
        byteEnd: byteEnd,
        encoding: parsedEncoding,
        allowMalformed: allowMalformed,
      );
      cancelToken?.throwIfCancelled();
      return result.text;
    } on AppFailure {
      rethrow;
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Failed to read chapter "${chapter.title}": ${e.message}',
        filePath: filePath,
        cause: e,
        stackTrace: st,
      );
    } on FormatException catch (e, st) {
      throw EncodingFailure(
        message:
            'Failed to decode chapter "${chapter.title}" as $encoding: ${e.message}',
        filePath: filePath,
        detectedEncoding: encoding,
        cause: e,
        stackTrace: st,
      );
    }
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
        logs: <String>['LocalTxtProvider does not support remote search'],
      ),
    );
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    final imported = await importTxtFile(bookUrl, cancelToken: cancelToken);
    sw.stop();

    final book = imported.book;
    return (
      detail: BookDetail(
        sourceId: providerId,
        providerType: ProviderType.localTxt,
        bookUrl: bookUrl,
        tocUrl: bookUrl,
        title: book.title,
        author: book.author,
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
    final imported = await importTxtFile(tocUrl, cancelToken: cancelToken);
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
    final filePath = chapter.url;
    if (filePath == null || filePath.isEmpty) {
      throw const FileAccessFailure(
        message:
            'Local TXT ChapterMeta lacks a file path in url; call readChapterText() with Book.localFilePath and Book.fileEncoding.',
      );
    }

    final sw = Stopwatch()..start();
    await _ensureReadableFile(filePath);
    final detected = await _worker.detectEncoding(filePath);
    if (detected.isUndecodable) {
      throw EncodingFailure(
        message: 'Unable to detect supported TXT encoding',
        filePath: filePath,
        detectedEncoding: detected.encoding.label,
      );
    }

    final text = await readChapterText(
      filePath: filePath,
      encoding: detected.encoding.label,
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
        requestUrl: filePath,
        matchedPreview: text.length > 80 ? text.substring(0, 80) : text,
      ),
    );
  }

  /// Disposes the internal [TxtIsolateWorker] if this provider owns it.
  Future<void> dispose() async {
    if (_ownsWorker) {
      await _worker.dispose();
    }
  }

  Future<void> _ensureReadableFile(String filePath) async {
    try {
      final type = await FileSystemEntity.type(filePath);
      if (type == FileSystemEntityType.notFound) {
        throw FileAccessFailure(
          message: 'TXT file does not exist: $filePath',
          filePath: filePath,
        );
      }
      if (type == FileSystemEntityType.directory) {
        throw FileAccessFailure(
          message: 'Expected a TXT file but found a directory: $filePath',
          filePath: filePath,
        );
      }
    } on FileSystemException catch (e, st) {
      throw FileAccessFailure(
        message: 'Cannot access TXT file: ${e.message}',
        filePath: filePath,
        cause: e,
        stackTrace: st,
      );
    }
  }

  static String _deriveTitle(String filePath) {
    final base = p.basenameWithoutExtension(filePath).trim();
    if (base.isNotEmpty) return base;
    final full = p.basename(filePath).trim();
    return full.isNotEmpty ? full : 'Untitled';
  }

  static String _deriveBookId(String filePath) {
    final normalized = p.normalize(File(filePath).absolute.path);
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
    return 'txt_${hex(h1)}${hex(h2)}';
  }
}
