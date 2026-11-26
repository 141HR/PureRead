import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../../engine/reader_engine/inline_image_marker.dart';
import '../../infrastructure/storage/chapter_cache_store.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import 'local_epub_reader_provider.dart';

/// Search scope for [InBookSearchService].
enum InBookSearchScope {
  /// Search only within the active chapter.
  currentChapter,

  /// Search across all indexed local chapters or cached online chapters.
  wholeBook,
}

/// Callback reading text for a single [chapter] during in-book search.
///
/// Returning `null` indicates the chapter is currently unavailable (such as an
/// uncached online chapter) and should be skipped without network requests.
typedef InBookChapterTextReader = Future<String?> Function(ChapterMeta chapter);

/// Single case-insensitive substring match located inside a book chapter.
class InBookSearchMatch {
  final int chapterIndex;
  final String chapterTitle;
  final int charOffset;
  final int matchLength;
  final String snippet;
  final int matchStartInSnippet;

  const InBookSearchMatch({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.charOffset,
    required this.matchLength,
    required this.snippet,
    required this.matchStartInSnippet,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InBookSearchMatch &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          chapterTitle == other.chapterTitle &&
          charOffset == other.charOffset &&
          matchLength == other.matchLength &&
          snippet == other.snippet &&
          matchStartInSnippet == other.matchStartInSnippet;

  @override
  int get hashCode => Object.hash(
    chapterIndex,
    chapterTitle,
    charOffset,
    matchLength,
    snippet,
    matchStartInSnippet,
  );
}

/// Incremental progress snapshot emitted while scanning chapters.
class InBookSearchProgress {
  final int scannedChapters;
  final int totalCandidateChapters;
  final int skippedUncachedChapters;
  final List<InBookSearchMatch> matches;
  final bool isCapped;

  const InBookSearchProgress({
    required this.scannedChapters,
    required this.totalCandidateChapters,
    required this.skippedUncachedChapters,
    required this.matches,
    required this.isCapped,
  });
}

/// Final summary returned by [InBookSearchService.searchBook].
class InBookSearchResult {
  final String query;
  final InBookSearchScope scope;
  final List<InBookSearchMatch> matches;
  final bool isCapped;
  final int scannedChapters;
  final int totalCandidateChapters;
  final int skippedUncachedChapters;

  const InBookSearchResult({
    required this.query,
    required this.scope,
    this.matches = const <InBookSearchMatch>[],
    this.isCapped = false,
    this.scannedChapters = 0,
    this.totalCandidateChapters = 0,
    this.skippedUncachedChapters = 0,
  });
}

final inBookSearchServiceProvider = Provider<InBookSearchService>((ref) {
  return InBookSearchService(
    cacheGateway: ref.watch(chapterCacheGatewayProvider),
    localTxtChapterReader: ref.watch(localTxtChapterReaderProvider),
    localEpubChapterReader: ref.watch(localEpubChapterReaderProvider),
    contentSanitizer: ref.watch(contentSanitizerProvider),
  );
});

/// Full-text in-book keyword search service supporting streaming chapter-by-chapter
/// scanning for local TXT/EPUB books and offline-safe cache scanning for online
/// books without issuing network requests.
class InBookSearchService {
  static const int defaultMaxMatches = 500;
  static const int defaultContextBefore = 24;
  static const int defaultContextAfter = 36;

  const InBookSearchService({
    this.cacheGateway,
    this.chapterCacheStore,
    this.localTxtChapterReader,
    this.localEpubChapterReader,
    this.contentSanitizer,
  });

  final ChapterCacheGateway? cacheGateway;
  final ChapterCacheStore? chapterCacheStore;
  final LocalTxtChapterReader? localTxtChapterReader;
  final LocalEpubChapterReader? localEpubChapterReader;
  final ContentSanitizer? contentSanitizer;

  static bool isOnlineBook(Book book) =>
      book.providerType == ProviderType.jsPlugin ||
      book.providerType == ProviderType.legado;

  /// Searches [query] inside [book] according to [scope], stopping immediately on
  /// [cancelToken] cancellation or once [maxMatches] is reached.
  Future<InBookSearchResult> searchBook({
    required Book book,
    required List<ChapterMeta> chapters,
    required String query,
    required InBookSearchScope scope,
    int currentChapterIndex = 0,
    String? activeChapterText,
    InBookChapterTextReader? chapterTextReader,
    int maxMatches = defaultMaxMatches,
    int contextBefore = defaultContextBefore,
    int contextAfter = defaultContextAfter,
    CancellationToken? cancelToken,
    void Function(InBookSearchProgress progress)? onProgress,
  }) async {
    cancelToken?.throwIfCancelled();

    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty || maxMatches <= 0) {
      return InBookSearchResult(query: trimmedQuery, scope: scope);
    }

    final targets = _resolveTargetChapters(
      book: book,
      chapters: chapters,
      scope: scope,
      currentChapterIndex: currentChapterIndex,
      hasActiveText: activeChapterText != null && activeChapterText.isNotEmpty,
    );

    if (targets.isEmpty) {
      return InBookSearchResult(query: trimmedQuery, scope: scope);
    }

    final matches = <InBookSearchMatch>[];
    var scannedChapters = 0;
    var skippedUncachedChapters = 0;
    var isCapped = false;

    for (var i = 0; i < targets.length; i++) {
      cancelToken?.throwIfCancelled();
      final chapter = targets[i];

      final text = await _loadChapterText(
        book: book,
        chapters: chapters,
        chapter: chapter,
        currentChapterIndex: currentChapterIndex,
        activeChapterText: activeChapterText,
        chapterTextReader: chapterTextReader,
        tolerateChapterParseFailure: targets.length > 1,
      );
      cancelToken?.throwIfCancelled();

      if (text == null) {
        if (isOnlineBook(book)) {
          skippedUncachedChapters++;
        }
        if (onProgress != null &&
            ((i + 1) % 16 == 0 || i + 1 == targets.length)) {
          onProgress(
            InBookSearchProgress(
              scannedChapters: scannedChapters,
              totalCandidateChapters: targets.length,
              skippedUncachedChapters: skippedUncachedChapters,
              matches: List<InBookSearchMatch>.unmodifiable(matches),
              isCapped: isCapped,
            ),
          );
        }
        continue;
      }

      scannedChapters++;
      final beforeCount = matches.length;
      if (text.isNotEmpty) {
        isCapped = _appendChapterMatches(
          text: text,
          query: trimmedQuery,
          chapterIndex: chapter.chapterIndex,
          chapterTitle: chapter.title,
          out: matches,
          maxMatches: maxMatches,
          contextBefore: contextBefore,
          contextAfter: contextAfter,
          cancelToken: cancelToken,
        );
      }

      final foundNew = matches.length > beforeCount;
      if (onProgress != null &&
          (foundNew ||
              isCapped ||
              (i + 1) % 16 == 0 ||
              i + 1 == targets.length)) {
        onProgress(
          InBookSearchProgress(
            scannedChapters: scannedChapters,
            totalCandidateChapters: targets.length,
            skippedUncachedChapters: skippedUncachedChapters,
            matches: List<InBookSearchMatch>.unmodifiable(matches),
            isCapped: isCapped,
          ),
        );
      }

      if (isCapped) {
        break;
      }
    }

    return InBookSearchResult(
      query: trimmedQuery,
      scope: scope,
      matches: List<InBookSearchMatch>.unmodifiable(matches),
      isCapped: isCapped,
      scannedChapters: scannedChapters,
      totalCandidateChapters: targets.length,
      skippedUncachedChapters: skippedUncachedChapters,
    );
  }

  /// Searches a single in-memory [text] string synchronously.
  static ({List<InBookSearchMatch> matches, bool isCapped}) searchInText({
    required String text,
    required String query,
    required int chapterIndex,
    required String chapterTitle,
    int maxMatches = defaultMaxMatches,
    int contextBefore = defaultContextBefore,
    int contextAfter = defaultContextAfter,
    CancellationToken? cancelToken,
  }) {
    cancelToken?.throwIfCancelled();
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty || text.isEmpty || maxMatches <= 0) {
      return const (matches: <InBookSearchMatch>[], isCapped: false);
    }
    final out = <InBookSearchMatch>[];
    final capped = _appendChapterMatches(
      text: text,
      query: trimmedQuery,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      out: out,
      maxMatches: maxMatches,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
      cancelToken: cancelToken,
    );
    return (
      matches: List<InBookSearchMatch>.unmodifiable(out),
      isCapped: capped,
    );
  }

  List<ChapterMeta> _resolveTargetChapters({
    required Book book,
    required List<ChapterMeta> chapters,
    required InBookSearchScope scope,
    required int currentChapterIndex,
    required bool hasActiveText,
  }) {
    if (chapters.isEmpty) {
      if (!hasActiveText) return const <ChapterMeta>[];
      return <ChapterMeta>[
        ChapterMeta(
          bookId: book.id,
          chapterIndex: currentChapterIndex,
          title: book.title,
          updatedAt: book.updatedAt,
        ),
      ];
    }

    if (scope == InBookSearchScope.currentChapter) {
      for (final chapter in chapters) {
        if (chapter.chapterIndex == currentChapterIndex) {
          return <ChapterMeta>[chapter];
        }
      }
      final fallbackIdx = currentChapterIndex.clamp(0, chapters.length - 1);
      return <ChapterMeta>[chapters[fallbackIdx]];
    }

    final sorted = List<ChapterMeta>.of(chapters)
      ..sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));
    return sorted;
  }

  Future<String?> _loadChapterText({
    required Book book,
    required List<ChapterMeta> chapters,
    required ChapterMeta chapter,
    required int currentChapterIndex,
    required String? activeChapterText,
    required InBookChapterTextReader? chapterTextReader,
    required bool tolerateChapterParseFailure,
  }) async {
    if (chapter.chapterIndex == currentChapterIndex &&
        activeChapterText != null &&
        activeChapterText.isNotEmpty) {
      return activeChapterText;
    }

    if (chapterTextReader != null) {
      try {
        return await chapterTextReader(chapter);
      } on SourceParseFailure {
        if (tolerateChapterParseFailure) return null;
        rethrow;
      }
    }

    final String? rawText;
    switch (book.providerType) {
      case ProviderType.localTxt:
        final reader = localTxtChapterReader;
        if (reader == null) {
          throw FileAccessFailure(
            message: '本地 TXT 读取器未配置，无法搜索《${book.title}》',
            filePath: book.localFilePath,
          );
        }
        rawText = await reader(book, chapter);
      case ProviderType.localEpub:
        final reader = localEpubChapterReader;
        if (reader == null) {
          throw FileAccessFailure(
            message: '本地 EPUB 读取器未配置，无法搜索《${book.title}》',
            filePath: book.localFilePath,
          );
        }
        try {
          rawText = await reader(book, chapter, chapters: chapters);
        } on SourceParseFailure {
          if (tolerateChapterParseFailure) return null;
          rethrow;
        }
      case ProviderType.jsPlugin:
      case ProviderType.legado:
        if (cacheGateway != null) {
          rawText = await cacheGateway!.readChapterText(
            book.id,
            chapter.chapterIndex,
          );
        } else if (chapterCacheStore != null) {
          rawText = await chapterCacheStore!.readChapter(
            book.id,
            chapter.chapterIndex,
          );
        } else {
          rawText = null;
        }
    }

    if (rawText == null) return null;

    final sanitizer = contentSanitizer;
    if (sanitizer == null) return rawText;
    return sanitizer.sanitize(
      rawText,
      SanitizeContext(
        bookId: book.id,
        sourceId: book.sourceId,
        chapterTitle: chapter.title,
      ),
    );
  }

  static bool _appendChapterMatches({
    required String text,
    required String query,
    required int chapterIndex,
    required String chapterTitle,
    required List<InBookSearchMatch> out,
    required int maxMatches,
    required int contextBefore,
    required int contextAfter,
    CancellationToken? cancelToken,
  }) {
    final markerSpans = _findMarkerLineSpans(text);
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final useFastPath =
        lowerText.length == text.length && lowerQuery.length == query.length;

    if (useFastPath) {
      final qLen = lowerQuery.length;
      var pos = 0;
      var checks = 0;
      var spanIdx = 0;
      while (pos <= lowerText.length - qLen) {
        if ((++checks & 63) == 0) {
          cancelToken?.throwIfCancelled();
        }
        final hitIdx = lowerText.indexOf(lowerQuery, pos);
        if (hitIdx < 0) break;
        final hitEnd = hitIdx + qLen;
        while (spanIdx < markerSpans.length &&
            markerSpans[spanIdx].end <= hitIdx) {
          spanIdx++;
        }
        if (spanIdx < markerSpans.length &&
            markerSpans[spanIdx].overlaps(hitIdx, hitEnd)) {
          pos = math.max(hitIdx + 1, markerSpans[spanIdx].end);
          continue;
        }
        if (out.length >= maxMatches) {
          return true;
        }
        out.add(
          _buildMatch(
            text: text,
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            charOffset: hitIdx,
            matchLength: qLen,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            markerSpans: markerSpans,
          ),
        );
        pos = hitEnd;
      }
      return false;
    }

    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    var checks = 0;
    var spanIdx = 0;
    for (final match in pattern.allMatches(text)) {
      if ((++checks & 63) == 0) {
        cancelToken?.throwIfCancelled();
      }
      while (spanIdx < markerSpans.length &&
          markerSpans[spanIdx].end <= match.start) {
        spanIdx++;
      }
      if (spanIdx < markerSpans.length &&
          markerSpans[spanIdx].overlaps(match.start, match.end)) {
        continue;
      }
      if (out.length >= maxMatches) {
        return true;
      }
      out.add(
        _buildMatch(
          text: text,
          chapterIndex: chapterIndex,
          chapterTitle: chapterTitle,
          charOffset: match.start,
          matchLength: match.end - match.start,
          contextBefore: contextBefore,
          contextAfter: contextAfter,
          markerSpans: markerSpans,
        ),
      );
    }
    return false;
  }

  static InBookSearchMatch _buildMatch({
    required String text,
    required int chapterIndex,
    required String chapterTitle,
    required int charOffset,
    required int matchLength,
    required int contextBefore,
    required int contextAfter,
    required List<_CharSpan> markerSpans,
  }) {
    final matchEnd = math.min<int>(text.length, charOffset + matchLength);
    final beforeCount = math.max<int>(0, contextBefore);
    final afterCount = math.max<int>(0, contextAfter);

    if (markerSpans.isEmpty) {
      var sliceStart = math.max<int>(0, charOffset - beforeCount);
      if (sliceStart > 0 &&
          sliceStart < charOffset &&
          _isLowSurrogate(text.codeUnitAt(sliceStart))) {
        sliceStart--;
      }

      var sliceEnd = math.min<int>(text.length, matchEnd + afterCount);
      if (sliceEnd < text.length &&
          sliceEnd > matchEnd &&
          _isLowSurrogate(text.codeUnitAt(sliceEnd))) {
        sliceEnd++;
      }

      final rawSlice = text
          .substring(sliceStart, sliceEnd)
          .replaceAll('\r', ' ')
          .replaceAll('\n', ' ');

      final localMatchStart = charOffset - sliceStart;
      final localMatchEnd = localMatchStart + matchLength;

      var trimLeft = 0;
      while (trimLeft < localMatchStart &&
          (rawSlice.codeUnitAt(trimLeft) == 0x20 ||
              rawSlice.codeUnitAt(trimLeft) == 0x09)) {
        trimLeft++;
      }

      var trimRight = rawSlice.length;
      while (trimRight > localMatchEnd &&
          (rawSlice.codeUnitAt(trimRight - 1) == 0x20 ||
              rawSlice.codeUnitAt(trimRight - 1) == 0x09)) {
        trimRight--;
      }

      final core = rawSlice.substring(trimLeft, trimRight);
      final prefix = sliceStart > 0 ? '…' : '';
      final suffix = sliceEnd < text.length ? '…' : '';
      final snippet = '$prefix$core$suffix';
      final matchStartInSnippet = prefix.length + (localMatchStart - trimLeft);

      return InBookSearchMatch(
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        charOffset: charOffset,
        matchLength: matchLength,
        snippet: snippet,
        matchStartInSnippet: matchStartInSnippet,
      );
    }

    var rawBeforeStart = charOffset;
    var remainingBefore = beforeCount;
    var bSpan = markerSpans.length - 1;
    while (bSpan >= 0 && markerSpans[bSpan].start >= charOffset) {
      bSpan--;
    }
    while (rawBeforeStart > 0 && remainingBefore > 0) {
      if (bSpan >= 0 && rawBeforeStart <= markerSpans[bSpan].end) {
        rawBeforeStart = math.min(rawBeforeStart, markerSpans[bSpan].start);
        bSpan--;
        continue;
      }
      final floor = bSpan >= 0 ? markerSpans[bSpan].end : 0;
      final available = rawBeforeStart - floor;
      final take = math.min(remainingBefore, available);
      rawBeforeStart -= take;
      remainingBefore -= take;
    }
    if (rawBeforeStart > 0 &&
        rawBeforeStart < charOffset &&
        _isLowSurrogate(text.codeUnitAt(rawBeforeStart))) {
      rawBeforeStart--;
    }

    var rawAfterEnd = matchEnd;
    var remainingAfter = afterCount;
    var aSpan = 0;
    while (aSpan < markerSpans.length && markerSpans[aSpan].end <= matchEnd) {
      aSpan++;
    }
    while (rawAfterEnd < text.length && remainingAfter > 0) {
      if (aSpan < markerSpans.length &&
          rawAfterEnd >= markerSpans[aSpan].start) {
        rawAfterEnd = math.max(rawAfterEnd, markerSpans[aSpan].end);
        aSpan++;
        continue;
      }
      final ceiling =
          aSpan < markerSpans.length ? markerSpans[aSpan].start : text.length;
      final available = ceiling - rawAfterEnd;
      final take = math.min(remainingAfter, available);
      rawAfterEnd += take;
      remainingAfter -= take;
    }
    if (rawAfterEnd < text.length &&
        rawAfterEnd > matchEnd &&
        _isLowSurrogate(text.codeUnitAt(rawAfterEnd))) {
      rawAfterEnd++;
    }

    var cleanedBefore = '';
    if (rawBeforeStart < charOffset) {
      final rawBefore = text.substring(rawBeforeStart, charOffset);
      final hadTrailingBreak =
          rawBefore.endsWith('\n') || rawBefore.endsWith('\r');
      var stripped = InlineImageMarker.stripMarkers(rawBefore);
      if (hadTrailingBreak && stripped.isNotEmpty && !stripped.endsWith('\n')) {
        stripped = '$stripped ';
      }
      cleanedBefore = stripped.replaceAll('\r', ' ').replaceAll('\n', ' ');
      if (cleanedBefore.length > beforeCount) {
        var cut = cleanedBefore.length - beforeCount;
        if (_isLowSurrogate(cleanedBefore.codeUnitAt(cut))) {
          cut--;
        }
        cleanedBefore = cleanedBefore.substring(cut);
      }
      var trimLeft = 0;
      while (trimLeft < cleanedBefore.length &&
          (cleanedBefore.codeUnitAt(trimLeft) == 0x20 ||
              cleanedBefore.codeUnitAt(trimLeft) == 0x09)) {
        trimLeft++;
      }
      if (trimLeft > 0) {
        cleanedBefore = cleanedBefore.substring(trimLeft);
      }
    }

    var cleanedAfter = '';
    if (rawAfterEnd > matchEnd) {
      final rawAfter = text.substring(matchEnd, rawAfterEnd);
      final hadLeadingBreak =
          rawAfter.startsWith('\n') || rawAfter.startsWith('\r');
      var stripped = InlineImageMarker.stripMarkers(rawAfter);
      if (hadLeadingBreak &&
          stripped.isNotEmpty &&
          !stripped.startsWith('\n')) {
        stripped = ' $stripped';
      }
      cleanedAfter = stripped.replaceAll('\r', ' ').replaceAll('\n', ' ');
      if (cleanedAfter.length > afterCount) {
        var cut = afterCount;
        if (_isLowSurrogate(cleanedAfter.codeUnitAt(cut))) {
          cut++;
        }
        cleanedAfter = cleanedAfter.substring(
          0,
          math.min(cleanedAfter.length, cut),
        );
      }
      var trimRight = cleanedAfter.length;
      while (trimRight > 0 &&
          (cleanedAfter.codeUnitAt(trimRight - 1) == 0x20 ||
              cleanedAfter.codeUnitAt(trimRight - 1) == 0x09)) {
        trimRight--;
      }
      if (trimRight < cleanedAfter.length) {
        cleanedAfter = cleanedAfter.substring(0, trimRight);
      }
    }

    final matchedChunk = text.substring(charOffset, matchEnd);
    final prefix = rawBeforeStart > 0 ? '…' : '';
    final suffix = rawAfterEnd < text.length ? '…' : '';
    final snippet = '$prefix$cleanedBefore$matchedChunk$cleanedAfter$suffix';
    final matchStartInSnippet = prefix.length + cleanedBefore.length;

    return InBookSearchMatch(
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      charOffset: charOffset,
      matchLength: matchLength,
      snippet: snippet,
      matchStartInSnippet: matchStartInSnippet,
    );
  }

  static List<_CharSpan> _findMarkerLineSpans(String text) {
    if (!text.contains(InlineImageMarker.prefix)) {
      return const <_CharSpan>[];
    }
    final spans = <_CharSpan>[];
    final len = text.length;
    var i = 0;
    while (i < len) {
      final lineStart = i;
      while (i < len && text.codeUnitAt(i) != 0x0A) {
        i++;
      }
      var renderEnd = i;
      if (renderEnd > lineStart && text.codeUnitAt(renderEnd - 1) == 0x0D) {
        renderEnd--;
      }
      if (i < len && text.codeUnitAt(i) == 0x0A) {
        i++;
      }
      if (renderEnd > lineStart &&
          InlineImageMarker.isImageLine(text.substring(lineStart, renderEnd))) {
        spans.add(_CharSpan(lineStart, i));
      }
    }
    return spans;
  }

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}

class _CharSpan {
  const _CharSpan(this.start, this.end);

  final int start;
  final int end;

  bool overlaps(int a, int b) => a < end && b > start;
}
