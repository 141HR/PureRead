import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/presentation/bookshelf/bookshelf_page.dart';

class _TestBookRepo implements BookRepository {
  final Map<String, Book> _books = <String, Book>{};
  final Map<String, List<ChapterMeta>> _chapters = <String, List<ChapterMeta>>{};
  final StreamController<List<Book>> _stream =
      StreamController<List<Book>>.broadcast();

  void seed(Book book) {
    _books[book.id] = book;
  }

  @override
  Stream<List<Book>> watchBooks({String? groupId}) async* {
    yield await listBooks(groupId: groupId);
    yield* _stream.stream;
  }

  @override
  Future<List<Book>> listBooks({String? groupId}) async =>
      _books.values.toList(growable: false);

  @override
  Future<Book?> getBookById(String bookId) async => _books[bookId];

  @override
  Future<Book?> findBySourceAndUrl(
    String sourceId,
    String originBookUrl,
  ) async => null;

  @override
  Future<void> saveBook(Book book) async {
    _books[book.id] = book;
    if (!_stream.isClosed) _stream.add(await listBooks());
  }

  @override
  Future<void> deleteBook(String bookId) async {
    _books.remove(bookId);
    if (!_stream.isClosed) _stream.add(await listBooks());
  }

  @override
  Future<List<BookGroup>> listGroups() async => const <BookGroup>[];

  @override
  Future<void> saveGroup(BookGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<List<ChapterMeta>> listChapters(String bookId) async =>
      _chapters[bookId] ?? const <ChapterMeta>[];

  @override
  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex) async =>
      null;

  @override
  Future<void> replaceChapters(String bookId, List<ChapterMeta> chapters) async {
    _chapters[bookId] = chapters;
  }

  @override
  Future<void> markChapterCached(
    String bookId,
    int chapterIndex,
    String cacheKey, {
    int? wordCount,
  }) async {}

  @override
  Future<ReadingProgress?> getProgress(String bookId) async => null;

  @override
  Future<void> saveProgress(ReadingProgress progress) async {}

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async =>
      const <Bookmark>[];

  @override
  Future<void> saveBookmark(Bookmark bookmark) async {}

  @override
  Future<void> deleteBookmark(String bookmarkId) async {}
}

class _TestThemeRepo implements ThemeRepository {
  final Map<String, AppSetting> _settings = <String, AppSetting>{};

  @override
  Stream<List<ReaderTheme>> watchThemes() =>
      Stream<List<ReaderTheme>>.value(buildDefaultReaderThemes());

  @override
  Future<List<ReaderTheme>> listThemes() async => buildDefaultReaderThemes();

  @override
  Future<ReaderTheme?> getThemeById(String themeId) async => null;

  @override
  Future<void> saveTheme(ReaderTheme theme) async {}

  @override
  Future<void> deleteTheme(String themeId) async {}

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

class _TestPlatformBridge implements PlatformBridge {
  List<String> filesToPick = const <String>[];

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async => filesToPick;

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async {}

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents =>
      const Stream<VolumeKeyDirection>.empty();

  @override
  Future<void> setImmersiveMode(bool enabled) async {}

  @override
  Future<void> bossKeyHide() async {}
}

void main() {
  testWidgets('BookshelfPage shows empty CTAs and imports local TXT files', (
    tester,
  ) async {
    final bookRepo = _TestBookRepo();
    final themeRepo = _TestThemeRepo();
    final platform = _TestPlatformBridge()
      ..filesToPick = const <String>[r'D:\books\剑来.txt'];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platform),
          txtBookImporterProvider.overrideWithValue((
            String filePath, {
            String? forcedEncoding,
          }) async {
            final now = DateTime.utc(2026, 11, 24);
            return (
              book: Book(
                id: 'jianlai',
                providerType: ProviderType.localTxt,
                title: '剑来',
                author: '烽火戏诸侯',
                totalChapters: 120,
                lastChapterTitle: '第一章 惊蛰',
                createdAt: now,
                updatedAt: now,
              ),
              chapters: <ChapterMeta>[
                ChapterMeta(
                  bookId: 'jianlai',
                  chapterIndex: 0,
                  title: '第一章 惊蛰',
                  updatedAt: now,
                ),
              ],
            );
          }),
        ],
        child: const MaterialApp(home: BookshelfPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('书架暂无书籍'), findsOneWidget);
    expect(find.text('导入本地 TXT'), findsOneWidget);
    expect(find.text('预览阅读器占位页'), findsOneWidget);

    await tester.tap(find.text('导入本地 TXT'));
    await tester.pumpAndSettle();

    expect(find.text('剑来'), findsNWidgets(2));
    expect(find.text('已成功导入 1 本书籍'), findsOneWidget);
  });

  testWidgets('BookshelfPage supports list/grid switch, pin, sort, and delete', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 24);
    final bookRepo = _TestBookRepo()
      ..seed(
        Book(
          id: 'b1',
          providerType: ProviderType.localTxt,
          title: '三国演义',
          author: '罗贯中',
          totalChapters: 120,
          lastReadAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      )
      ..seed(
        Book(
          id: 'b2',
          providerType: ProviderType.localTxt,
          title: '红楼梦',
          author: '曹雪芹',
          totalChapters: 120,
          lastReadAt: now.subtract(const Duration(days: 1)),
          createdAt: now,
          updatedAt: now,
        ),
      );
    final themeRepo = _TestThemeRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(_TestPlatformBridge()),
        ],
        child: const MaterialApp(home: BookshelfPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('书架 (2)'), findsOneWidget);

    // Switch to list mode.
    await tester.tap(find.byTooltip('切换列表视图'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(2));

    // Delete second book via list action + confirmation dialog.
    await tester.tap(find.byTooltip('删除书籍').last);
    await tester.pumpAndSettle();
    expect(find.text('移除书籍'), findsOneWidget);

    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(find.text('书架 (1)'), findsOneWidget);
  });
}
