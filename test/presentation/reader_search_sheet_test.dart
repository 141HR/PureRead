import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/presentation/reader/reader_page.dart';
import 'package:pureread/presentation/reader/reader_page_turn_view.dart';
import 'package:pureread/presentation/reader/reader_search_sheet.dart';

class _SheetTestBookRepo implements BookRepository {
  _SheetTestBookRepo(this.book, this.chapters);

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

class _SheetTestThemeRepo implements ThemeRepository {
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

class _SheetTestPlatformBridge implements PlatformBridge {
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
  group('ReaderSearchSheet & ReaderPage integration', () {
    late _SheetTestBookRepo bookRepo;
    late _SheetTestThemeRepo themeRepo;
    late _SheetTestPlatformBridge platformBridge;
    late Map<int, String> chapterTexts;

    setUp(() {
      final now = DateTime.utc(2026, 11, 25);
      bookRepo = _SheetTestBookRepo(
        Book(
          id: 'search-book',
          providerType: ProviderType.localTxt,
          title: '雪中悍刀行',
          author: '烽火戏诸侯',
          totalChapters: 3,
          createdAt: now,
          updatedAt: now,
        ),
        <ChapterMeta>[
          ChapterMeta(
            bookId: 'search-book',
            chapterIndex: 0,
            title: '第一章 小二上酒',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'search-book',
            chapterIndex: 1,
            title: '第二章 剑气近',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'search-book',
            chapterIndex: 2,
            title: '第三章 大风起',
            updatedAt: now,
          ),
        ],
      );
      chapterTexts = <int, String>{
        0: '第一章 小二上酒\n${List<String>.generate(25, (i) => '第${i + 1}段：北凉风雪夜，小二温酒待客。').join('\n')}',
        1: '第二章 剑气近\n${List<String>.generate(30, (i) => '第${i + 1}段：江南烟雨里行路难。').join('\n')}\n关键段落：天门青莲剑意惊天下！\n尾声。',
        2: '第三章 大风起\n大风起兮云飞扬，再见青莲剑意。',
      };
      themeRepo = _SheetTestThemeRepo();
      platformBridge = _SheetTestPlatformBridge();
    });

    Widget buildReaderHarness() {
      return ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platformBridge),
          localTxtChapterReaderProvider.overrideWithValue(
            (book, chapter) async => chapterTexts[chapter.chapterIndex] ?? '',
          ),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 'search-book')),
      );
    }

    testWidgets('renders highlighted snippet TextSpans, toggles scope, and shows 500-match cap indicator', (
      tester,
    ) async {
      chapterTexts[1] =
          '第二章 剑气近\n${List<String>.filled(520, '剑意').join('，')}';

      final jumped = <(int, int)>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWithValue(bookRepo),
            themeRepositoryProvider.overrideWithValue(themeRepo),
            platformBridgeProvider.overrideWithValue(platformBridge),
            localTxtChapterReaderProvider.overrideWithValue(
              (book, chapter) async => chapterTexts[chapter.chapterIndex] ?? '',
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReaderSearchSheet(
                bookId: 'search-book',
                onJumpToMatch: (ch, offset) async {
                  jumped.add((ch, offset));
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('书内搜索'), findsOneWidget);
      expect(find.text('当前章'), findsOneWidget);
      expect(find.text('全书已缓存章节'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '剑意');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Cap indicator appears when matches exceed 500.
      expect(find.textContaining('500 条上限'), findsOneWidget);
      expect(find.textContaining('共找到 500 处匹配'), findsOneWidget);

      // Verify highlighted TextSpan exists inside rendered Text.rich.
      final richWidgets = tester.widgetList<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && w.textSpan != null,
        ),
      );
      final hasHighlightedHit = richWidgets.any((widget) {
        final root = widget.textSpan;
        if (root is! TextSpan || root.children == null) return false;
        return root.children!.any(
          (span) =>
              span is TextSpan &&
              span.text == '剑意' &&
              span.style?.fontWeight == FontWeight.w700 &&
              span.style?.backgroundColor != null,
        );
      });
      expect(hasHighlightedHit, isTrue);

      // Toggle to 当前章 (ch 0 has no '剑意').
      await tester.tap(find.text('当前章'));
      await tester.pumpAndSettle();
      expect(find.textContaining('未找到包含“剑意”的内容'), findsOneWidget);

      // Toggle back to 全书已缓存章节 and tap first match.
      await tester.tap(find.text('全书已缓存章节'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      expect(jumped, hasLength(1));
      expect(jumped.first.$1, 1);
    });

    testWidgets('opens ReaderSearchSheet via top overlay icon & Ctrl+F, jumps to match, and supports jump undo', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(480, 760);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildReaderHarness());
      await tester.pumpAndSettle();

      // Tap center to reveal overlay, then tap search icon.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await tester.pumpAndSettle();

      final searchIcon = find.byIcon(Icons.search);
      expect(searchIcon, findsOneWidget);
      await tester.tap(searchIcon);
      await tester.pumpAndSettle();

      expect(find.text('书内搜索'), findsOneWidget);

      // Search for phrase in chapter 2 and tap result to jump.
      await tester.enterText(find.byType(TextField), '天门青莲');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('第二章 剑气近'), findsOneWidget);
      await tester.tap(find.text('第二章 剑气近'));
      await tester.pumpAndSettle();

      expect(find.text('书内搜索'), findsNothing);
      expect(find.textContaining('第二章 剑气近'), findsOneWidget);

      // Reveal overlay and confirm 撤回跳转 works after search jump.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await tester.pumpAndSettle();
      expect(find.text('撤回跳转'), findsOneWidget);
      await tester.tap(find.text('撤回跳转'));
      await tester.pumpAndSettle();
      expect(find.textContaining('第一章 小二上酒'), findsWidgets);

      // Hide overlay and press Ctrl+F to reopen ReaderSearchSheet.
      await tester.tapAt(tester.getCenter(find.byType(ReaderPageTurnView)));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.text('书内搜索'), findsOneWidget);
    });
  });
}
