import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../domain/domain.dart';
import '../engine/reader_engine/platform_font_resolver.dart';
import '../infrastructure/platform/method_channel_platform_bridge.dart';
import '../infrastructure/platform/platform_bridge.dart';
import 'reader/reader_theme_x.dart';

/// Gateway signature for importing a local `.txt` file into a [Book] and its
/// indexed [ChapterMeta] list.
typedef TxtBookImporter =
    Future<({Book book, List<ChapterMeta> chapters})> Function(
      String filePath, {
      String? forcedEncoding,
    });

/// Gateway signature for reading a single chapter's raw text from a local TXT
/// file.
typedef LocalTxtChapterReader =
    Future<String> Function(Book book, ChapterMeta chapter);

/// Gateway abstraction for importing custom `.ttf` / `.otf` fonts and
/// ensuring previously imported fonts are loaded into Flutter's font registry.
abstract interface class FontLoaderGateway {
  Future<({String fontFamily, String relativeFontPath})> importAndRegisterFont(
    String sourcePath,
  );

  Future<void> ensureFontLoaded(
    String fontFamily,
    String? relativeFontPath,
  );
}

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => _InMemoryBookRepository(),
);

final themeRepositoryProvider = Provider<ThemeRepository>(
  (ref) => _InMemoryThemeRepository(),
);

final sourceRepositoryProvider = Provider<SourceRepository>(
  (ref) => _InMemorySourceRepository(),
);

final readerPaginatorProvider = Provider<ReaderPaginator>(
  (ref) => _FallbackReaderPaginator(),
);

final contentSanitizerProvider = Provider<ContentSanitizer>(
  (ref) => _DefaultContentSanitizer(),
);

final txtBookImporterProvider = Provider<TxtBookImporter>((ref) {
  return (String filePath, {String? forcedEncoding}) async {
    throw FileAccessFailure(
      message: 'TXT 导入引擎尚未装配，无法导入：$filePath',
      filePath: filePath,
    );
  };
});

final localTxtChapterReaderProvider = Provider<LocalTxtChapterReader>((ref) {
  return (Book book, ChapterMeta chapter) async {
    throw FileAccessFailure(
      message: '本地 TXT 读取引擎尚未装配，无法读取《${book.title}》${chapter.title}',
      filePath: book.localFilePath,
    );
  };
});

final fontLoaderGatewayProvider = Provider<FontLoaderGateway>(
  (ref) => _DefaultFontLoaderGateway(),
);

final platformBridgeProvider = Provider<PlatformBridge>((ref) {
  final bridge = MethodChannelPlatformBridge();
  ref.onDispose(() {
    unawaited(bridge.dispose());
  });
  return bridge;
});

class _DefaultFontLoaderGateway implements FontLoaderGateway {
  final Set<String> _loadedFamilies = <String>{};

  @override
  Future<({String fontFamily, String relativeFontPath})> importAndRegisterFont(
    String sourcePath,
  ) async {
    final file = File(sourcePath);
    if (!file.existsSync()) {
      throw FileAccessFailure(
        message: '字体文件不存在：$sourcePath',
        filePath: sourcePath,
      );
    }
    final baseName = p.basenameWithoutExtension(sourcePath);
    final family = 'PureReadCustom_$baseName';
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFamilies.add(family);
    return (fontFamily: family, relativeFontPath: sourcePath);
  }

  @override
  Future<void> ensureFontLoaded(
    String fontFamily,
    String? relativeFontPath,
  ) async {
    if (relativeFontPath == null ||
        relativeFontPath.isEmpty ||
        _loadedFamilies.contains(fontFamily)) {
      return;
    }
    final file = File(relativeFontPath);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(fontFamily)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFamilies.add(fontFamily);
  }
}

class _InMemoryBookRepository implements BookRepository {
  final Map<String, Book> _books = <String, Book>{};
  final Map<String, BookGroup> _groups = <String, BookGroup>{};
  final Map<String, List<ChapterMeta>> _chapters = <String, List<ChapterMeta>>{};
  final Map<String, ReadingProgress> _progress = <String, ReadingProgress>{};
  final Map<String, List<Bookmark>> _bookmarks = <String, List<Bookmark>>{};
  final StreamController<List<Book>> _booksController =
      StreamController<List<Book>>.broadcast();

  void _emitBooks() {
    if (!_booksController.isClosed) {
      _booksController.add(_books.values.toList(growable: false));
    }
  }

  @override
  Stream<List<Book>> watchBooks({String? groupId}) async* {
    yield await listBooks(groupId: groupId);
    yield* _booksController.stream.map((books) {
      if (groupId == null) return books;
      return books.where((b) => b.groupId == groupId).toList(growable: false);
    });
  }

  @override
  Future<List<Book>> listBooks({String? groupId}) async {
    final all = _books.values.toList(growable: false);
    if (groupId == null) return all;
    return all.where((b) => b.groupId == groupId).toList(growable: false);
  }

  @override
  Future<Book?> getBookById(String bookId) async => _books[bookId];

  @override
  Future<Book?> findBySourceAndUrl(
    String sourceId,
    String originBookUrl,
  ) async {
    for (final book in _books.values) {
      if (book.sourceId == sourceId && book.originBookUrl == originBookUrl) {
        return book;
      }
    }
    return null;
  }

  @override
  Future<void> saveBook(Book book) async {
    _books[book.id] = book;
    _emitBooks();
  }

  @override
  Future<void> deleteBook(String bookId) async {
    _books.remove(bookId);
    _chapters.remove(bookId);
    _progress.remove(bookId);
    _bookmarks.remove(bookId);
    _emitBooks();
  }

  @override
  Future<List<BookGroup>> listGroups() async =>
      _groups.values.toList(growable: false);

  @override
  Future<void> saveGroup(BookGroup group) async {
    _groups[group.id] = group;
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    _groups.remove(groupId);
  }

  @override
  Future<List<ChapterMeta>> listChapters(String bookId) async =>
      List<ChapterMeta>.unmodifiable(_chapters[bookId] ?? const <ChapterMeta>[]);

  @override
  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex) async {
    final list = _chapters[bookId];
    if (list == null) return null;
    for (final chapter in list) {
      if (chapter.chapterIndex == chapterIndex) return chapter;
    }
    return null;
  }

  @override
  Future<void> replaceChapters(String bookId, List<ChapterMeta> chapters) async {
    _chapters[bookId] = List<ChapterMeta>.from(chapters);
  }

  @override
  Future<void> markChapterCached(
    String bookId,
    int chapterIndex,
    String cacheKey, {
    int? wordCount,
  }) async {
    final list = _chapters[bookId];
    if (list == null) return;
    _chapters[bookId] = list
        .map(
          (ch) => ch.chapterIndex == chapterIndex
              ? ch.copyWith(
                  isCached: true,
                  cacheKey: cacheKey,
                  wordCount: wordCount ?? ch.wordCount,
                )
              : ch,
        )
        .toList();
  }

  @override
  Future<ReadingProgress?> getProgress(String bookId) async => _progress[bookId];

  @override
  Future<void> saveProgress(ReadingProgress progress) async {
    _progress[progress.bookId] = progress;
  }

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async =>
      List<Bookmark>.unmodifiable(_bookmarks[bookId] ?? const <Bookmark>[]);

  @override
  Future<void> saveBookmark(Bookmark bookmark) async {
    final list = _bookmarks.putIfAbsent(bookmark.bookId, () => <Bookmark>[]);
    final idx = list.indexWhere((b) => b.id == bookmark.id);
    if (idx >= 0) {
      list[idx] = bookmark;
    } else {
      list.add(bookmark);
    }
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    for (final list in _bookmarks.values) {
      list.removeWhere((b) => b.id == bookmarkId);
    }
  }
}

class _InMemoryThemeRepository implements ThemeRepository {
  _InMemoryThemeRepository() {
    for (final theme in buildDefaultReaderThemes()) {
      _themes[theme.id] = theme;
    }
  }

  final Map<String, ReaderTheme> _themes = <String, ReaderTheme>{};
  final Map<String, AppSetting> _settings = <String, AppSetting>{};
  final StreamController<List<ReaderTheme>> _controller =
      StreamController<List<ReaderTheme>>.broadcast();

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_themes.values.toList(growable: false));
    }
  }

  @override
  Stream<List<ReaderTheme>> watchThemes() async* {
    yield await listThemes();
    yield* _controller.stream;
  }

  @override
  Future<List<ReaderTheme>> listThemes() async =>
      _themes.values.toList(growable: false);

  @override
  Future<ReaderTheme?> getThemeById(String themeId) async => _themes[themeId];

  @override
  Future<void> saveTheme(ReaderTheme theme) async {
    _themes[theme.id] = theme;
    _emit();
  }

  @override
  Future<void> deleteTheme(String themeId) async {
    _themes.remove(themeId);
    _emit();
  }

  @override
  Future<AppSetting?> getSetting(String key) async => _settings[key];

  @override
  Future<List<AppSetting>> listSettings() async =>
      _settings.values.toList(growable: false);

  @override
  Future<void> saveSetting(AppSetting setting) async {
    _settings[setting.key] = setting;
  }
}

class _InMemorySourceRepository implements SourceRepository {
  final Map<String, BookSource> _sources = <String, BookSource>{};
  final Map<String, ReplaceRule> _rules = <String, ReplaceRule>{};

  @override
  Stream<List<BookSource>> watchSources() =>
      Stream<List<BookSource>>.value(_sources.values.toList(growable: false));

  @override
  Future<List<BookSource>> listSources({bool enabledOnly = false}) async {
    final values = _sources.values;
    if (!enabledOnly) return values.toList(growable: false);
    return values.where((s) => s.enabled).toList(growable: false);
  }

  @override
  Future<BookSource?> getSourceById(String sourceId) async =>
      _sources[sourceId];

  @override
  Future<void> saveSource(BookSource source) async {
    _sources[source.id] = source;
  }

  @override
  Future<void> saveSources(List<BookSource> sources) async {
    for (final source in sources) {
      _sources[source.id] = source;
    }
  }

  @override
  Future<void> deleteSource(String sourceId) async {
    _sources.remove(sourceId);
  }

  @override
  Future<List<ReplaceRule>> listReplaceRules({
    bool enabledOnly = false,
    String? sourceId,
    String? bookId,
  }) async {
    return _rules.values.where((r) {
      if (enabledOnly && !r.enabled) return false;
      return switch (r.scopeType) {
        RuleScopeType.global => true,
        RuleScopeType.source =>
          sourceId != null && r.scopeTargetId == sourceId,
        RuleScopeType.book => bookId != null && r.scopeTargetId == bookId,
      };
    }).toList(growable: false);
  }

  @override
  Future<void> saveReplaceRule(ReplaceRule rule) async {
    _rules[rule.id] = rule;
  }

  @override
  Future<void> deleteReplaceRule(String ruleId) async {
    _rules.remove(ruleId);
  }
}

class _DefaultContentSanitizer implements ContentSanitizer {
  @override
  Future<String> sanitize(String rawContent, SanitizeContext context) async {
    final normalized = rawContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final buffer = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (buffer.isNotEmpty && buffer.last.isNotEmpty) {
          buffer.add('');
        }
      } else {
        buffer.add(trimmed);
      }
    }
    while (buffer.isNotEmpty && buffer.last.isEmpty) {
      buffer.removeLast();
    }
    return buffer.join('\n');
  }
}

class _FallbackReaderPaginator implements ReaderPaginator {
  @override
  Future<List<PageSlice>> paginateChapter({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    int? priorityCharOffset,
  }) async {
    if (sanitizedText.isEmpty) {
      return <PageSlice>[
        PageSlice(
          chapterIndex: chapterIndex,
          pageIndex: 0,
          startCharOffset: 0,
          endCharOffset: 0,
          lines: const <LayoutLine>[],
        ),
      ];
    }

    final fontFamily = resolvePlatformFontFamily(config.fontFamily);
    final fontFamilyFallback = resolvePlatformFontFamilyFallback();
    final fontWeight = FontWeight.values.firstWhere(
      (w) => w.value == config.fontWeightValue,
      orElse: () => FontWeight.w400,
    );
    final baseStyle = TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: config.fontSize,
      fontWeight: fontWeight,
      height: config.lineHeightMultiplier,
      letterSpacing: config.letterSpacing,
    );

    final probe = TextPainter(
      text: TextSpan(text: '汉', style: baseStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final lineHeight = probe.height > 0
        ? probe.height
        : config.fontSize * config.lineHeightMultiplier;
    final approxGlyphW = probe.width > 0 ? probe.width : config.fontSize;

    final pages = <PageSlice>[];
    var currentLines = <LayoutLine>[];
    var currentY = 0.0;
    var pageStart = 0;

    var pos = 0;
    var isFirstParagraph = true;
    while (pos < sanitizedText.length) {
      final pStart = pos;
      while (pos < sanitizedText.length &&
          sanitizedText.codeUnitAt(pos) != 0x0A) {
        pos++;
      }
      var pRenderEnd = pos;
      if (pRenderEnd > pStart &&
          sanitizedText.codeUnitAt(pRenderEnd - 1) == 0x0D) {
        pRenderEnd--;
      }
      if (pos < sanitizedText.length && sanitizedText.codeUnitAt(pos) == 0x0A) {
        pos++;
      }
      final pEnd = pos;
      final isTitle = isFirstParagraph && pRenderEnd > pStart;
      isFirstParagraph = false;

      if (pStart == pRenderEnd) {
        if (currentLines.isNotEmpty &&
            currentY + lineHeight > config.columnHeight + 0.01) {
          pages.add(
            PageSlice(
              chapterIndex: chapterIndex,
              pageIndex: pages.length,
              startCharOffset: pageStart,
              endCharOffset: currentLines.last.endCharOffset,
              lines: currentLines,
            ),
          );
          currentLines = <LayoutLine>[];
          currentY = 0.0;
          pageStart = pStart;
        }
        currentLines.add(
          LayoutLine(
            text: sanitizedText.substring(pStart, pEnd),
            startCharOffset: pStart,
            endCharOffset: pEnd,
            x: 0,
            y: currentY,
            width: 0,
            height: lineHeight,
            isParagraphStart: true,
            isParagraphEnd: true,
            isChapterTitle: false,
          ),
        );
        currentY += lineHeight + config.paragraphSpacing;
        continue;
      }

      final indent = (!isTitle && config.paragraphIndentChars > 0)
          ? config.paragraphIndentChars * config.fontSize
          : 0.0;

      var lineStart = pStart;
      while (lineStart < pRenderEnd) {
        final isParaStart = lineStart == pStart;
        final x = isParaStart ? indent : 0.0;
        final maxLineW = (config.columnWidth - x).clamp(
          config.fontSize,
          config.columnWidth,
        );
        final estimatedChars = (maxLineW / approxGlyphW).floor().clamp(1, 200);
        var lineRenderEnd = (lineStart + estimatedChars).clamp(
          lineStart + 1,
          pRenderEnd,
        );

        // Refine using TextPainter to avoid overflow.
        while (lineRenderEnd > lineStart + 1) {
          probe.text = TextSpan(
            text: sanitizedText.substring(lineStart, lineRenderEnd),
            style: isTitle
                ? baseStyle.copyWith(fontWeight: FontWeight.w700)
                : baseStyle,
          );
          probe.layout();
          if (probe.width <= maxLineW + 0.5) break;
          lineRenderEnd--;
        }
        // Protect surrogate pairs.
        if (lineRenderEnd < pRenderEnd &&
            _isLowSurrogate(sanitizedText.codeUnitAt(lineRenderEnd)) &&
            lineRenderEnd - 1 > lineStart) {
          lineRenderEnd--;
        }

        final isParaEnd = lineRenderEnd >= pRenderEnd;
        final fullLineEnd = isParaEnd ? pEnd : lineRenderEnd;
        probe.text = TextSpan(
          text: sanitizedText.substring(lineStart, lineRenderEnd),
          style: isTitle
              ? baseStyle.copyWith(fontWeight: FontWeight.w700)
              : baseStyle,
        );
        probe.layout();

        if (currentLines.isNotEmpty &&
            currentY + lineHeight > config.columnHeight + 0.01) {
          pages.add(
            PageSlice(
              chapterIndex: chapterIndex,
              pageIndex: pages.length,
              startCharOffset: pageStart,
              endCharOffset: currentLines.last.endCharOffset,
              lines: currentLines,
            ),
          );
          currentLines = <LayoutLine>[];
          currentY = 0.0;
          pageStart = lineStart;
        }

        currentLines.add(
          LayoutLine(
            text: sanitizedText.substring(lineStart, fullLineEnd),
            startCharOffset: lineStart,
            endCharOffset: fullLineEnd,
            x: x,
            y: currentY,
            width: probe.width,
            height: lineHeight,
            isParagraphStart: isParaStart,
            isParagraphEnd: isParaEnd,
            isChapterTitle: isTitle,
          ),
        );
        currentY += lineHeight;
        if (isParaEnd) {
          currentY += config.paragraphSpacing;
        }
        lineStart = lineRenderEnd;
      }
    }

    if (currentLines.isNotEmpty) {
      pages.add(
        PageSlice(
          chapterIndex: chapterIndex,
          pageIndex: pages.length,
          startCharOffset: pageStart,
          endCharOffset: sanitizedText.length,
          lines: currentLines,
        ),
      );
    }

    return pages;
  }

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}
