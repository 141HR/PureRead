import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/bookshelf/bookshelf_controller.dart';
import 'package:pureread/application/bookshelf/bookshelf_state.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';

class _FakeBookRepository implements BookRepository {
  final Map<String, Book> books = <String, Book>{};
  final Map<String, List<ChapterMeta>> chapters = <String, List<ChapterMeta>>{};
  final Map<String, ReadingProgress> progress = <String, ReadingProgress>{};
  final Map<String, List<Bookmark>> bookmarks = <String, List<Bookmark>>{};
  final StreamController<List<Book>> _controller =
      StreamController<List<Book>>.broadcast();

  void emit() {
    if (!_controller.isClosed) {
      _controller.add(books.values.toList(growable: false));
    }
  }

  @override
  Stream<List<Book>> watchBooks({String? groupId}) async* {
    yield await listBooks(groupId: groupId);
    yield* _controller.stream;
  }

  @override
  Future<List<Book>> listBooks({String? groupId}) async =>
      books.values.toList(growable: false);

  @override
  Future<Book?> getBookById(String bookId) async => books[bookId];

  @override
  Future<Book?> findBySourceAndUrl(
    String sourceId,
    String originBookUrl,
  ) async => null;

  @override
  Future<void> saveBook(Book book) async {
    books[book.id] = book;
    emit();
  }

  @override
  Future<void> deleteBook(String bookId) async {
    books.remove(bookId);
    chapters.remove(bookId);
    progress.remove(bookId);
    bookmarks.remove(bookId);
    emit();
  }

  @override
  Future<List<BookGroup>> listGroups() async => const <BookGroup>[];

  @override
  Future<void> saveGroup(BookGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<List<ChapterMeta>> listChapters(String bookId) async =>
      chapters[bookId] ?? const <ChapterMeta>[];

  @override
  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex) async =>
      null;

  @override
  Future<void> replaceChapters(String bookId, List<ChapterMeta> list) async {
    chapters[bookId] = list;
  }

  @override
  Future<void> markChapterCached(
    String bookId,
    int chapterIndex,
    String cacheKey, {
    int? wordCount,
  }) async {}

  @override
  Future<ReadingProgress?> getProgress(String bookId) async => progress[bookId];

  @override
  Future<void> saveProgress(ReadingProgress p) async {
    progress[p.bookId] = p;
  }

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async =>
      bookmarks[bookId] ?? const <Bookmark>[];

  @override
  Future<void> saveBookmark(Bookmark bookmark) async {}

  @override
  Future<void> deleteBookmark(String bookmarkId) async {}
}

class _FakeThemeRepository implements ThemeRepository {
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
  Future<void> saveSetting(AppSetting setting) async {
    settings[setting.key] = setting;
  }
}

class _FakePlatformBridge implements PlatformBridge {
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
  group('BookshelfController', () {
    late _FakeBookRepository bookRepo;
    late _FakeThemeRepository themeRepo;
    late _FakePlatformBridge platformBridge;

    Book makeBook({
      required String id,
      required String title,
      bool isPinned = false,
      DateTime? lastReadAt,
      DateTime? updatedAt,
    }) {
      final base = DateTime.utc(2026, 11, 20);
      return Book(
        id: id,
        providerType: ProviderType.localTxt,
        title: title,
        author: '作者',
        isPinned: isPinned,
        lastReadAt: lastReadAt,
        createdAt: base,
        updatedAt: updatedAt ?? base,
      );
    }

    setUp(() {
      bookRepo = _FakeBookRepository();
      themeRepo = _FakeThemeRepository();
      platformBridge = _FakePlatformBridge();
    });

    test('sorts by recentRead, updatedAt, title with pinned always first', () async {
      bookRepo.books['a'] = makeBook(
        id: 'a',
        title: 'Beta',
        lastReadAt: DateTime.utc(2026, 11, 24, 10),
        updatedAt: DateTime.utc(2026, 11, 21),
      );
      bookRepo.books['b'] = makeBook(
        id: 'b',
        title: 'Alpha',
        lastReadAt: DateTime.utc(2026, 11, 24, 8),
        updatedAt: DateTime.utc(2026, 11, 23),
      );
      bookRepo.books['c'] = makeBook(
        id: 'c',
        title: 'Gamma',
        isPinned: true,
        lastReadAt: DateTime.utc(2026, 11, 19),
        updatedAt: DateTime.utc(2026, 11, 19),
      );

      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platformBridge),
        ],
      );
      addTearDown(container.dispose);

      container.read(bookshelfControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      var state = container.read(bookshelfControllerProvider);
      expect(
        state.books.map((b) => b.id).toList(),
        equals(<String>['c', 'a', 'b']),
      );

      await container
          .read(bookshelfControllerProvider.notifier)
          .setSortMode(BookshelfSortMode.updatedAt);
      state = container.read(bookshelfControllerProvider);
      expect(
        state.books.map((b) => b.id).toList(),
        equals(<String>['c', 'b', 'a']),
      );

      await container
          .read(bookshelfControllerProvider.notifier)
          .setSortMode(BookshelfSortMode.title);
      state = container.read(bookshelfControllerProvider);
      expect(
        state.books.map((b) => b.id).toList(),
        equals(<String>['c', 'b', 'a']),
      );
    });

    test('persists viewMode and sortMode across container rebuilds', () async {
      final c1 = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platformBridge),
        ],
      );
      c1.read(bookshelfControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await c1.read(bookshelfControllerProvider.notifier).toggleViewMode();
      await c1
          .read(bookshelfControllerProvider.notifier)
          .setSortMode(BookshelfSortMode.title);
      c1.dispose();

      final c2 = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platformBridge),
        ],
      );
      addTearDown(c2.dispose);
      c2.read(bookshelfControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final restored = c2.read(bookshelfControllerProvider);
      expect(restored.viewMode, BookshelfViewMode.list);
      expect(restored.sortMode, BookshelfSortMode.title);
    });

    test('toggles pin and deletes book', () async {
      bookRepo.books['b1'] = makeBook(id: 'b1', title: 'Book One');
      bookRepo.books['b2'] = makeBook(id: 'b2', title: 'Book Two');

      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platformBridge),
        ],
      );
      addTearDown(container.dispose);
      container.read(bookshelfControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await container.read(bookshelfControllerProvider.notifier).togglePin('b2');
      expect(
        container.read(bookshelfControllerProvider).books.first.id,
        equals('b2'),
      );
      expect(bookRepo.books['b2']!.isPinned, isTrue);

      await container
          .read(bookshelfControllerProvider.notifier)
          .deleteBook('b2');
      expect(bookRepo.books.containsKey('b2'), isFalse);
      expect(
        container.read(bookshelfControllerProvider).books.map((b) => b.id),
        equals(<String>['b1']),
      );
    });

    test('imports multiple TXT files and isolates single-file failure', () async {
      platformBridge.filesToPick = const <String>[
        r'D:\novels\ok.txt',
        r'D:\novels\corrupt.txt',
      ];

      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platformBridge),
          txtBookImporterProvider.overrideWithValue((
            String filePath, {
            String? forcedEncoding,
          }) async {
            if (filePath.endsWith('corrupt.txt')) {
              throw const EncodingFailure(message: '未知文本编码');
            }
            final now = DateTime.utc(2026, 11, 24);
            return (
              book: Book(
                id: 'book-ok',
                providerType: ProviderType.localTxt,
                title: '凡人修仙传',
                localFilePath: filePath,
                totalChapters: 2,
                createdAt: now,
                updatedAt: now,
              ),
              chapters: <ChapterMeta>[
                ChapterMeta(
                  bookId: 'book-ok',
                  chapterIndex: 0,
                  title: '第一章',
                  updatedAt: now,
                ),
                ChapterMeta(
                  bookId: 'book-ok',
                  chapterIndex: 1,
                  title: '第二章',
                  updatedAt: now,
                ),
              ],
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(bookshelfControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await container
          .read(bookshelfControllerProvider.notifier)
          .importLocalTxtFiles();

      final state = container.read(bookshelfControllerProvider);
      expect(state.isImporting, isFalse);
      expect(state.books, hasLength(1));
      expect(state.books.first.title, '凡人修仙传');
      expect(bookRepo.chapters['book-ok'], hasLength(2));
      expect(state.importStatusMessage, contains('1'));
      expect(state.errorMessage, contains('corrupt.txt'));
      expect(state.errorMessage, contains('未知文本编码'));
    });
  });
}
