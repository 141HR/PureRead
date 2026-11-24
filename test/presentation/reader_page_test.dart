import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/presentation/reader/reader_page.dart';
import 'package:pureread/presentation/reader/reader_page_painter.dart';
import 'package:pureread/presentation/reader/reader_page_turn_view.dart';

class _TestReaderBookRepo implements BookRepository {
  _TestReaderBookRepo(this.book, this.chapters);

  Book book;
  final List<ChapterMeta> chapters;
  ReadingProgress? progress;
  final List<Bookmark> bookmarks = <Bookmark>[];

  @override
  Stream<List<Book>> watchBooks({String? groupId}) =>
      Stream<List<Book>>.value(<Book>[book]);

  @override
  Future<List<Book>> listBooks({String? groupId}) async => <Book>[book];

  @override
  Future<Book?> getBookById(String bookId) async =>
      book.id == bookId ? book : null;

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
      chapters[chapterIndex];

  @override
  Future<void> replaceChapters(String bookId, List<ChapterMeta> list) async {}

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

class _TestThemeRepo implements ThemeRepository {
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

class _TestPlatformBridge implements PlatformBridge {
  final List<bool> immersiveCalls = <bool>[];
  int bossKeyCalls = 0;

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async => const <String>[];

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async {}

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents =>
      const Stream<VolumeKeyDirection>.empty();

  @override
  Future<void> setImmersiveMode(bool enabled) async =>
      immersiveCalls.add(enabled);

  @override
  Future<void> bossKeyHide() async => bossKeyCalls++;
}

void main() {
  group('ReaderPagePainter', () {
    test('trims trailing \\r and \\n cleanly', () {
      expect(ReaderPagePainter.trimTrailingLineBreaks('正文内容。\r\n'), '正文内容。');
      expect(ReaderPagePainter.trimTrailingLineBreaks('正文内容。\n'), '正文内容。');
      expect(ReaderPagePainter.trimTrailingLineBreaks('正文内容。'), '正文内容。');
    });

    test('paints single-column and dual-column slices including charXOffsets', () {
      const config = PaginationConfig(
        columnWidth: 280,
        columnHeight: 400,
        columnCount: 2,
        columnGap: 32,
        fontSize: 18,
      );
      const left = PageSlice(
        chapterIndex: 0,
        pageIndex: 0,
        startCharOffset: 0,
        endCharOffset: 10,
        lines: <LayoutLine>[
          LayoutLine(
            text: '测试Flutter行\n',
            startCharOffset: 0,
            endCharOffset: 10,
            x: 36,
            y: 0,
            width: 180,
            height: 28,
            isParagraphStart: true,
            isParagraphEnd: true,
          ),
        ],
      );
      const right = PageSlice(
        chapterIndex: 0,
        pageIndex: 1,
        startCharOffset: 10,
        endCharOffset: 14,
        lines: <LayoutLine>[
          LayoutLine(
            text: '精确定位',
            startCharOffset: 10,
            endCharOffset: 14,
            x: 0,
            y: 0,
            width: 72,
            height: 28,
            charXOffsets: <double>[0, 18, 36, 54],
          ),
        ],
      );

      final painter = ReaderPagePainter(
        config: config,
        leftPage: left,
        rightPage: right,
        backgroundColor: const Color(0xFFF7F4EC),
        textColor: const Color(0xFF2C2A26),
        secondaryTextColor: const Color(0xFF78736A),
        headerText: '书名 · 第一章',
        footerLeftText: '1 / 2',
        footerRightText: '50.0% 18:55',
        contentTopOffset: 32,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(700, 500));
      final picture = recorder.endRecording();
      expect(picture.approximateBytesUsed, greaterThan(0));
      picture.dispose();
    });
  });

  group('ReaderPage adaptive layout, overlays, shortcuts & drag', () {
    late _TestReaderBookRepo bookRepo;
    late _TestThemeRepo themeRepo;
    late _TestPlatformBridge platformBridge;
    late Map<int, String> chapterTexts;

    setUp(() {
      final now = DateTime.utc(2026, 11, 24);
      bookRepo = _TestReaderBookRepo(
        Book(
          id: 'novel-1',
          providerType: ProviderType.localTxt,
          title: '雪中悍刀行',
          author: '烽火戏诸侯',
          totalChapters: 3,
          createdAt: now,
          updatedAt: now,
        ),
        <ChapterMeta>[
          ChapterMeta(
            bookId: 'novel-1',
            chapterIndex: 0,
            title: '第一章 小二上酒',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'novel-1',
            chapterIndex: 1,
            title: '第二章 剑气近',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'novel-1',
            chapterIndex: 2,
            title: '第三章 大风起',
            updatedAt: now,
          ),
        ],
      );
      chapterTexts = <int, String>{
        0: '第一章 小二上酒\n${List<String>.generate(50, (i) => '第${i + 1}段：北凉风雪夜，小二温酒待客来。PureRead 测试混排 123。').join('\n')}',
        1: '第二章 剑气近\n${List<String>.generate(30, (i) => '第${i + 1}段：大雪坪上剑意凌霄，千里不留行。').join('\n')}',
        2: '第三章 大风起\n${List<String>.generate(30, (i) => '第${i + 1}段：大风起兮云飞扬，威加海内兮归故乡。').join('\n')}',
      };
      themeRepo = _TestThemeRepo();
      platformBridge = _TestPlatformBridge();
    });

    Widget buildHarness() {
      return ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platformBridge),
          localTxtChapterReaderProvider.overrideWithValue(
            (book, chapter) async => chapterTexts[chapter.chapterIndex] ?? '',
          ),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 'novel-1')),
      );
    }

    testWidgets('switches between single and dual-column layouts by viewport width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 760);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // Dual-column mode shows left & right page footer labels.
      expect(find.textContaining('第 1 / '), findsOneWidget);
      expect(find.text('第 2 页'), findsOneWidget);

      // Narrow mobile size switches to single column (after 40ms debounce).
      tester.view.physicalSize = const Size(420, 760);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      expect(find.text('第 2 页'), findsNothing);
      expect(find.textContaining('1 / '), findsOneWidget);
    });

    testWidgets('handles keyboard shortcuts, TOC search, jump-undo, and settings', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1100, 760);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // ArrowRight advances spread (page 1 -> page 3).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.textContaining('第 3 / '), findsOneWidget);

      // F11 toggles immersive mode.
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(platformBridge.immersiveCalls, contains(true));

      // Ctrl+H triggers boss key.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(platformBridge.bossKeyCalls, 1);

      // KeyT opens TOC drawer, filter by keyword, jump to chapter 3.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      expect(find.text('共 3 章'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '大风');
      await tester.pumpAndSettle();
      expect(find.text('第三章 大风起'), findsOneWidget);
      expect(find.text('第一章 小二上酒'), findsNothing);

      await tester.tap(find.text('第三章 大风起'));
      await tester.pumpAndSettle();
      expect(find.textContaining('第三章 大风起'), findsWidgets);

      // Tap center of reader canvas to show overlay and tap 撤回跳转.
      final viewCenter = tester.getCenter(find.byType(ReaderPageTurnView));
      await tester.tapAt(viewCenter);
      await tester.pumpAndSettle();

      expect(find.text('撤回跳转'), findsOneWidget);
      await tester.tap(find.text('撤回跳转'));
      await tester.pumpAndSettle();
      expect(find.textContaining('第 3 / '), findsOneWidget);

      // Open settings sheet via bottom overlay button and switch theme + page turn mode.
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('排版与主题设置'), findsOneWidget);

      await tester.tap(find.text('OLED 纯黑'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('滚动'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('滚动'));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFF000000));
    });

    testWidgets('cover mode supports cancel spring-back and full swipe turn', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 760);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();
      expect(find.textContaining('1 / '), findsOneWidget);

      // Short drag (< 22% width) cancels and springs back to page 1.
      await tester.drag(find.byType(ReaderPageTurnView), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 / '), findsOneWidget);

      // Long drag (> 22% width) turns to page 2.
      await tester.drag(find.byType(ReaderPageTurnView), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 / '), findsOneWidget);
    });
  });
}
