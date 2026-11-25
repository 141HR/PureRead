import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/in_book_search_service.dart';
import 'package:pureread/application/reader/reader_search_controller.dart';
import 'package:pureread/application/reader/reader_session_controller.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/reader_engine.dart';
import 'package:pureread/engine/source_engine/local_epub/local_epub.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/infrastructure/storage/app_path_resolver.dart';
import 'package:pureread/infrastructure/storage/chapter_cache_store.dart';

Uint8List _buildEpubBytes(Map<String, String> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile.bytes(entry.key, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class _FakeSearchBookRepo implements BookRepository {
  Book? book;
  List<ChapterMeta> chapters = <ChapterMeta>[];
  ReadingProgress? progress;
  final List<Bookmark> bookmarks = <Bookmark>[];

  @override
  Stream<List<Book>> watchBooks({String? groupId}) =>
      Stream<List<Book>>.value(book == null ? const <Book>[] : <Book>[book!]);

  @override
  Future<List<Book>> listBooks({String? groupId}) async =>
      book == null ? const <Book>[] : <Book>[book!];

  @override
  Future<Book?> getBookById(String bookId) async =>
      book?.id == bookId ? book : null;

  @override
  Future<Book?> findBySourceAndUrl(
    String sourceId,
    String originBookUrl,
  ) async => null;

  @override
  Future<void> saveBook(Book b) async => book = b;

  @override
  Future<void> deleteBook(String bookId) async {}

  @override
  Future<List<BookGroup>> listGroups() async => const <BookGroup>[];

  @override
  Future<void> saveGroup(BookGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<List<ChapterMeta>> listChapters(String bookId) async => chapters;

  @override
  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex) async =>
      chapters.firstWhere((c) => c.chapterIndex == chapterIndex);

  @override
  Future<void> replaceChapters(String bookId, List<ChapterMeta> list) async =>
      chapters = list;

  @override
  Future<void> markChapterCached(
    String bookId,
    int chapterIndex,
    String cacheKey, {
    int? wordCount,
  }) async {}

  @override
  Future<ReadingProgress?> getProgress(String bookId) async => progress;

  @override
  Future<void> saveProgress(ReadingProgress p) async => progress = p;

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async =>
      List<Bookmark>.unmodifiable(bookmarks);

  @override
  Future<void> saveBookmark(Bookmark bookmark) async => bookmarks.add(bookmark);

  @override
  Future<void> deleteBookmark(String bookmarkId) async =>
      bookmarks.removeWhere((b) => b.id == bookmarkId);
}

class _FakeSearchThemeRepo implements ThemeRepository {
  final Map<String, ReaderTheme> themes = <String, ReaderTheme>{
    for (final t in buildDefaultReaderThemes()) t.id: t,
  };
  final Map<String, AppSetting> settings = <String, AppSetting>{};

  @override
  Stream<List<ReaderTheme>> watchThemes() =>
      Stream<List<ReaderTheme>>.value(themes.values.toList(growable: false));

  @override
  Future<List<ReaderTheme>> listThemes() async =>
      themes.values.toList(growable: false);

  @override
  Future<ReaderTheme?> getThemeById(String themeId) async => themes[themeId];

  @override
  Future<void> saveTheme(ReaderTheme theme) async => themes[theme.id] = theme;

  @override
  Future<void> deleteTheme(String themeId) async => themes.remove(themeId);

  @override
  Future<AppSetting?> getSetting(String key) async => settings[key];

  @override
  Future<List<AppSetting>> listSettings() async =>
      settings.values.toList(growable: false);

  @override
  Future<void> saveSetting(AppSetting setting) async =>
      settings[setting.key] = setting;
}

class _NoopPlatformBridge implements PlatformBridge {
  @override
  Future<void> bossKeyHide() async {}

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async => const <String>[];

  @override
  Future<void> setImmersiveMode(bool enabled) async {}

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async {}

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents =>
      const Stream<VolumeKeyDirection>.empty();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pureread_inbook_search_');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('InBookSearchService', () {
    test('performs case-insensitive match and preserves exact snippet indices across newlines & emojis', () {
      const text =
          '序言 🚀 星火燎原\n前面有很多铺垫内容用来拉开上下文长度，确保出现省略号。PureRead 阅读器支持全文搜索！\n后面还有很长很长的一段结尾文字用来验证上下文截断省略号效果。';

      final result = InBookSearchService.searchInText(
        text: text,
        query: 'pureread',
        chapterIndex: 0,
        chapterTitle: '序言',
      );

      expect(result.isCapped, isFalse);
      expect(result.matches, hasLength(1));

      final match = result.matches.first;
      expect(match.chapterIndex, 0);
      expect(match.chapterTitle, '序言');
      expect(match.matchLength, 'pureread'.length);
      expect(
        text.substring(match.charOffset, match.charOffset + match.matchLength),
        'PureRead',
      );
      expect(
        match.snippet.substring(
          match.matchStartInSnippet,
          match.matchStartInSnippet + match.matchLength,
        ),
        'PureRead',
      );
      expect(match.snippet, startsWith('…'));
      expect(match.snippet, endsWith('…'));

      // Match near start of text avoids leading ellipsis and protects surrogate pairs.
      final emojiLead = InBookSearchService.searchInText(
        text: '🚀PureRead启动',
        query: 'pureread',
        chapterIndex: 0,
        chapterTitle: '测试',
        contextBefore: 1,
        contextAfter: 1,
      );
      expect(emojiLead.matches, hasLength(1));
      final emojiMatch = emojiLead.matches.first;
      expect(
        emojiMatch.snippet.substring(
          emojiMatch.matchStartInSnippet,
          emojiMatch.matchStartInSnippet + emojiMatch.matchLength,
        ),
        'PureRead',
      );
      expect(emojiMatch.snippet, contains('🚀'));
    });

    test('caps results at 500 matches and marks isCapped only when exceeding cap', () {
      final exact500 = List<String>.filled(500, '剑气').join('，');
      final exactResult = InBookSearchService.searchInText(
        text: exact500,
        query: '剑气',
        chapterIndex: 0,
        chapterTitle: '测试章',
      );
      expect(exactResult.matches, hasLength(500));
      expect(exactResult.isCapped, isFalse);

      final overCap = List<String>.filled(540, '剑气').join('，');
      final cappedResult = InBookSearchService.searchInText(
        text: overCap,
        query: '剑气',
        chapterIndex: 0,
        chapterTitle: '测试章',
      );
      expect(cappedResult.matches, hasLength(500));
      expect(cappedResult.isCapped, isTrue);
    });

    test('supports CancellationToken before and during multi-chapter scan', () async {
      final now = DateTime.utc(2026, 11, 25);
      final book = Book(
        id: 'cancel-book',
        providerType: ProviderType.localTxt,
        title: '取消测试',
        createdAt: now,
        updatedAt: now,
      );
      final chapters = List<ChapterMeta>.generate(
        5,
        (i) => ChapterMeta(
          bookId: book.id,
          chapterIndex: i,
          title: '第${i + 1}章',
          updatedAt: now,
        ),
      );

      const service = InBookSearchService();
      final preCancelled = CancellationToken()..cancel();
      await expectLater(
        service.searchBook(
          book: book,
          chapters: chapters,
          query: '剑',
          scope: InBookSearchScope.wholeBook,
          chapterTextReader: (_) async => '一剑光寒',
          cancelToken: preCancelled,
        ),
        throwsA(isA<CancelledFailure>()),
      );

      final midToken = CancellationToken();
      var readCount = 0;
      await expectLater(
        service.searchBook(
          book: book,
          chapters: chapters,
          query: '剑',
          scope: InBookSearchScope.wholeBook,
          chapterTextReader: (chapter) async {
            readCount++;
            if (chapter.chapterIndex == 1) {
              midToken.cancel();
            }
            return '一剑开天门';
          },
          cancelToken: midToken,
        ),
        throwsA(isA<CancelledFailure>()),
      );
      expect(readCount, 2);
    });

    test('scans local TXT chapters cleanly via LocalTxtProvider without full-file load', () async {
      final txtFile = File(p.join(tempDir.path, 'local_search.txt'));
      await txtFile.writeAsString(
        '第一章 风起北凉\n北凉铁骑踏雪而来，剑气如霜。\n\n'
        '第二章 剑出青州\n青州城头并无动静。\n\n'
        '第三章 再遇北凉\n十年之后北凉旧事重提。\n',
      );

      final txtProvider = LocalTxtProvider();
      addTearDown(txtProvider.dispose);

      final imported = await txtProvider.importTxtFile(txtFile.path);
      expect(imported.chapters, hasLength(3));

      final readChapters = <int>[];
      final service = InBookSearchService(
        localTxtChapterReader: (book, chapter) async {
          readChapters.add(chapter.chapterIndex);
          return txtProvider.readChapterText(
            filePath: book.localFilePath!,
            encoding: book.fileEncoding ?? 'utf-8',
            chapter: chapter,
          );
        },
      );

      final currentOnly = await service.searchBook(
        book: imported.book,
        chapters: imported.chapters,
        query: '北凉',
        scope: InBookSearchScope.currentChapter,
        currentChapterIndex: 0,
      );
      expect(currentOnly.matches, hasLength(2));
      expect(currentOnly.matches.every((m) => m.chapterIndex == 0), isTrue);
      expect(readChapters, <int>[0]);

      readChapters.clear();
      final wholeBook = await service.searchBook(
        book: imported.book,
        chapters: imported.chapters,
        query: '北凉',
        scope: InBookSearchScope.wholeBook,
        currentChapterIndex: 0,
      );
      expect(wholeBook.scannedChapters, 3);
      expect(readChapters, <int>[0, 1, 2]);
      expect(wholeBook.matches.map((m) => m.chapterIndex).toList(), <int>[
        0,
        0,
        2,
        2,
      ]);
    });

    test('scans local EPUB chapters cleanly via LocalEpubProvider', () async {
      final epubFile = File(p.join(tempDir.path, 'local_search.epub'));
      final epubBytes = _buildEpubBytes(<String, String>{
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''',
        'OEBPS/content.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>EPUB 搜索测试</dc:title>
    <dc:creator>测试作者</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''',
        'OEBPS/nav.xhtml': '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="ch1.xhtml">第一章 启程</a></li>
        <li><a href="ch2.xhtml">第二章 归途</a></li>
      </ol>
    </nav>
  </body>
</html>
''',
        'OEBPS/ch1.xhtml': '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>第一章 启程</h1><p>星海漫游指南的第一页。</p></body>
</html>
''',
        'OEBPS/ch2.xhtml': '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>第二章 归途</h1><p>再度翻开星海日志。</p></body>
</html>
''',
      });
      await epubFile.writeAsBytes(epubBytes, flush: true);

      final epubProvider = LocalEpubProvider();
      final imported = await epubProvider.importEpubFile(
        epubFile.path,
        extractCover: false,
      );
      expect(imported.chapters, hasLength(2));

      final service = InBookSearchService(
        localEpubChapterReader: (book, chapter, {chapters}) =>
            epubProvider.readChapterText(
              filePath: book.localFilePath!,
              chapter: chapter,
              chapters: chapters,
            ),
      );

      final result = await service.searchBook(
        book: imported.book,
        chapters: imported.chapters,
        query: '星海',
        scope: InBookSearchScope.wholeBook,
      );
      expect(result.scannedChapters, 2);
      expect(result.matches, hasLength(2));
      expect(result.matches[0].chapterIndex, 0);
      expect(result.matches[1].chapterIndex, 1);
    });

    test('scans online book ChapterCacheStore + active chapter text without network fetches', () async {
      final pathResolver = AppPathResolver.fromRoots(
        dataRootDir: Directory(p.join(tempDir.path, 'data')),
        cacheRootDir: Directory(p.join(tempDir.path, 'cache')),
      );
      final cacheStore = ChapterCacheStore(pathResolver);
      const bookId = 'online-book-1';
      final now = DateTime.utc(2026, 11, 25);
      final book = Book(
        id: bookId,
        sourceId: 'src-1',
        providerType: ProviderType.legado,
        title: '在线搜索测试',
        totalChapters: 4,
        createdAt: now,
        updatedAt: now,
      );
      final chapters = List<ChapterMeta>.generate(
        4,
        (i) => ChapterMeta(
          bookId: bookId,
          chapterIndex: i,
          title: '第${i + 1}章',
          url: 'https://example.com/ch/$i',
          isCached: i == 0 || i == 2,
          updatedAt: now,
        ),
      );

      await cacheStore.writeChapter(bookId, 0, '第一章 青莲剑歌在缓存中。');
      await cacheStore.writeChapter(bookId, 2, '第三章 青莲再现于缓存中。');

      final service = InBookSearchService(chapterCacheStore: cacheStore);
      final result = await service.searchBook(
        book: book,
        chapters: chapters,
        query: '青莲',
        scope: InBookSearchScope.wholeBook,
        currentChapterIndex: 1,
        activeChapterText: '第二章 正在阅读的青莲段落。',
      );

      expect(result.scannedChapters, 3);
      expect(result.skippedUncachedChapters, 1);
      expect(result.matches.map((m) => m.chapterIndex).toList(), <int>[0, 1, 2]);
    });
  });

  group('ReaderSearchController & jumpToSearchAnchor', () {
    test('searches across chapters, jumps centered on charOffset, pushes jumpUndoStack, and undoes', () async {
      final now = DateTime.utc(2026, 11, 25);
      final bookRepo = _FakeSearchBookRepo()
        ..book = Book(
          id: 'book-jump',
          providerType: ProviderType.localTxt,
          title: '雪中悍刀行',
          totalChapters: 3,
          createdAt: now,
          updatedAt: now,
        )
        ..chapters = <ChapterMeta>[
          ChapterMeta(
            bookId: 'book-jump',
            chapterIndex: 0,
            title: '第一章 启程',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'book-jump',
            chapterIndex: 1,
            title: '第二章 剑气近',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'book-jump',
            chapterIndex: 2,
            title: '第三章 终局',
            updatedAt: now,
          ),
        ];

      final ch1Text =
          '第二章 剑气近\n${'江南烟雨蒙蒙，古道西风瘦马。' * 40}终于在深处找到天门秘境！${'山高水长。' * 20}';
      final chapterTexts = <int, String>{
        0: '第一章 启程\n${'北凉风雪漫天飞舞。' * 30}',
        1: ch1Text,
        2: '第三章 终局\n天门再开。',
      };

      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(_FakeSearchThemeRepo()),
          platformBridgeProvider.overrideWithValue(_NoopPlatformBridge()),
          readerPaginatorProvider.overrideWithValue(IncrementalTextPaginator()),
          localTxtChapterReaderProvider.overrideWithValue(
            (book, chapter) async => chapterTexts[chapter.chapterIndex] ?? '',
          ),
        ],
      );
      addTearDown(container.dispose);

      final sessionSub = container.listen(
        readerSessionControllerProvider('book-jump'),
        (_, _) {},
      );
      final searchSub = container.listen(
        readerSearchControllerProvider('book-jump'),
        (_, _) {},
      );
      addTearDown(sessionSub.close);
      addTearDown(searchSub.close);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sessionCtrl = container.read(
        readerSessionControllerProvider('book-jump').notifier,
      );
      sessionCtrl.updateViewportSize(const Size(360, 560), debounce: false);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      await sessionCtrl.nextPage();
      final preJump = container.read(
        readerSessionControllerProvider('book-jump'),
      );
      final originalAnchor = preJump.anchorOffset;
      expect(preJump.currentChapterIndex, 0);
      expect(originalAnchor, greaterThan(0));
      expect(preJump.canUndoJump, isFalse);

      final searchCtrl = container.read(
        readerSearchControllerProvider('book-jump').notifier,
      );
      await searchCtrl.search('天门');

      final wholeBookState = container.read(
        readerSearchControllerProvider('book-jump'),
      );
      expect(wholeBookState.isSearching, isFalse);
      expect(wholeBookState.matches, hasLength(2));
      expect(wholeBookState.matches[0].chapterIndex, 1);
      expect(wholeBookState.matches[1].chapterIndex, 2);

      // Switching to currentChapter finds 0 matches because '天门' is in ch 1 & 2.
      await searchCtrl.setScope(InBookSearchScope.currentChapter);
      expect(
        container.read(readerSearchControllerProvider('book-jump')).matches,
        isEmpty,
      );

      // Switch back to wholeBook and jump to chapter 1's deep match.
      await searchCtrl.setScope(InBookSearchScope.wholeBook);
      final targetMatch = container
          .read(readerSearchControllerProvider('book-jump'))
          .matches
          .first;
      await sessionCtrl.jumpToSearchAnchor(
        targetMatch.chapterIndex,
        targetMatch.charOffset,
      );

      final afterJump = container.read(
        readerSessionControllerProvider('book-jump'),
      );
      expect(afterJump.currentChapterIndex, 1);
      expect(afterJump.anchorOffset, targetMatch.charOffset);
      expect(afterJump.canUndoJump, isTrue);
      expect(afterJump.jumpUndoStack.last.chapterIndex, 0);
      expect(afterJump.jumpUndoStack.last.charOffset, originalAnchor);
      expect(
        afterJump.currentPages[afterJump.currentPageIndex].containsOffset(
          targetMatch.charOffset,
        ),
        isTrue,
      );
      expect(bookRepo.progress?.chapterIndex, 1);
      expect(bookRepo.progress?.charOffset, targetMatch.charOffset);

      // Undo restores exact chapter 0 anchor.
      await sessionCtrl.undoLastJump();
      final undone = container.read(
        readerSessionControllerProvider('book-jump'),
      );
      expect(undone.currentChapterIndex, 0);
      expect(undone.anchorOffset, originalAnchor);
      expect(undone.canUndoJump, isFalse);
    });
  });
}
