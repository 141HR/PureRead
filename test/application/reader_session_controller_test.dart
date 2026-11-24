import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_session_controller.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';

class _FakeReaderBookRepo implements BookRepository {
  Book? book;
  List<ChapterMeta> chapters = <ChapterMeta>[];
  ReadingProgress? progress;
  final List<ReadingProgress> savedProgressHistory = <ReadingProgress>[];
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
  Future<void> saveBook(Book b) async {
    book = b;
  }

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
  Future<void> saveProgress(ReadingProgress p) async {
    progress = p;
    savedProgressHistory.add(p);
  }

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async =>
      List<Bookmark>.unmodifiable(bookmarks);

  @override
  Future<void> saveBookmark(Bookmark bookmark) async {
    bookmarks.add(bookmark);
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    bookmarks.removeWhere((b) => b.id == bookmarkId);
  }
}

class _FakeThemeRepo implements ThemeRepository {
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
  Future<void> saveTheme(ReaderTheme theme) async {
    themes[theme.id] = theme;
  }

  @override
  Future<void> deleteTheme(String themeId) async {
    themes.remove(themeId);
  }

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
  final StreamController<VolumeKeyDirection> volumeController =
      StreamController<VolumeKeyDirection>.broadcast();
  final List<bool> keepScreenOnCalls = <bool>[];
  final List<bool> volumePagingCalls = <bool>[];
  final List<bool> immersiveCalls = <bool>[];
  List<String> filesToReturn = const <String>[];
  int bossKeyCount = 0;

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async => filesToReturn;

  @override
  Future<void> setKeepScreenOn(bool enabled) async =>
      keepScreenOnCalls.add(enabled);

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async =>
      volumePagingCalls.add(enabled);

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents => volumeController.stream;

  @override
  Future<void> setImmersiveMode(bool enabled) async =>
      immersiveCalls.add(enabled);

  @override
  Future<void> bossKeyHide() async => bossKeyCount++;

  Future<void> dispose() => volumeController.close();
}

class _FakeFontGateway implements FontLoaderGateway {
  final List<String> importedPaths = <String>[];

  @override
  Future<({String fontFamily, String relativeFontPath})> importAndRegisterFont(
    String sourcePath,
  ) async {
    importedPaths.add(sourcePath);
    return (
      fontFamily: 'CustomWenKai',
      relativeFontPath: 'fonts/CustomWenKai.ttf',
    );
  }

  @override
  Future<void> ensureFontLoaded(
    String fontFamily,
    String? relativeFontPath,
  ) async {}
}

/// Deterministic character-count fake paginator used to test exact
/// `charOffset` anchoring, two-column spread pairing, and pre-pagination cache.
class _FakePaginator implements ReaderPaginator {
  final List<(int chapterIndex, PaginationConfig config)> calls =
      <(int, PaginationConfig)>[];

  @override
  Future<List<PageSlice>> paginateChapter({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    int? priorityCharOffset,
  }) async {
    calls.add((chapterIndex, config));
    final charsPerPage =
        ((config.columnWidth / config.fontSize) * 4).round().clamp(20, 120);
    final slices = <PageSlice>[];
    var offset = 0;
    while (offset < sanitizedText.length) {
      final end = (offset + charsPerPage).clamp(0, sanitizedText.length);
      final sliceText = sanitizedText.substring(offset, end);
      slices.add(
        PageSlice(
          chapterIndex: chapterIndex,
          pageIndex: slices.length,
          startCharOffset: offset,
          endCharOffset: end,
          lines: <LayoutLine>[
            LayoutLine(
              text: sliceText,
              startCharOffset: offset,
              endCharOffset: end,
              x: 0,
              y: 0,
              width: config.columnWidth * 0.8,
              height: config.fontSize * config.lineHeightMultiplier,
              isParagraphStart: true,
              isParagraphEnd: true,
            ),
          ],
        ),
      );
      offset = end;
    }
    if (slices.isEmpty) {
      slices.add(
        PageSlice(
          chapterIndex: chapterIndex,
          pageIndex: 0,
          startCharOffset: 0,
          endCharOffset: 0,
          lines: const <LayoutLine>[],
        ),
      );
    }
    return slices;
  }
}

void main() {
  group('ReaderSessionController', () {
    late _FakeReaderBookRepo bookRepo;
    late _FakeThemeRepo themeRepo;
    late _FakePlatformBridge platformBridge;
    late _FakeFontGateway fontGateway;
    late _FakePaginator paginator;
    late Map<int, String> chapterTexts;

    setUp(() {
      final now = DateTime.utc(2026, 11, 24);
      bookRepo = _FakeReaderBookRepo()
        ..book = Book(
          id: 'book-1',
          providerType: ProviderType.localTxt,
          title: '雪中悍刀行',
          author: '烽火戏诸侯',
          totalChapters: 3,
          createdAt: now,
          updatedAt: now,
        )
        ..chapters = <ChapterMeta>[
          ChapterMeta(
            bookId: 'book-1',
            chapterIndex: 0,
            title: '第一章 小二上酒',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'book-1',
            chapterIndex: 1,
            title: '第二章 剑气近',
            updatedAt: now,
          ),
          ChapterMeta(
            bookId: 'book-1',
            chapterIndex: 2,
            title: '第三章 江湖夜雨',
            updatedAt: now,
          ),
        ];
      chapterTexts = <int, String>{
        0: '第一章 小二上酒\n${'北凉王府风雪漫天，江湖夜雨十年灯。' * 30}',
        1: '第二章 剑气近\n${'一剑开天门，万里风雷动。' * 20}',
        2: '第三章 江湖夜雨\n${'青衫磊落险峰行，山河远阔。' * 20}',
      };
      themeRepo = _FakeThemeRepo();
      platformBridge = _FakePlatformBridge();
      fontGateway = _FakeFontGateway();
      paginator = _FakePaginator();
    });

    tearDown(() async {
      await platformBridge.dispose();
    });

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          platformBridgeProvider.overrideWithValue(platformBridge),
          fontLoaderGatewayProvider.overrideWithValue(fontGateway),
          readerPaginatorProvider.overrideWithValue(paginator),
          localTxtChapterReaderProvider.overrideWithValue(
            (book, chapter) async => chapterTexts[chapter.chapterIndex] ?? '',
          ),
        ],
      );
    }

    test('preserves session-stable anchorOffset across A -> B -> C -> A resize and font changes', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      // Keep provider alive across test.
      final sub = container.listen(
        readerSessionControllerProvider('book-1'),
        (_, _) {},
      );
      addTearDown(sub.close);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final controller = container.read(
        readerSessionControllerProvider('book-1').notifier,
      );

      // A: narrow single-column viewport.
      controller.updateViewportSize(const Size(400, 700), debounce: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Turn forward 2 pages so anchorOffset is non-zero in mid-chapter.
      await controller.nextPage();
      await controller.nextPage();
      final stateA = container.read(readerSessionControllerProvider('book-1'));
      final originalAnchor = stateA.anchorOffset;
      final originalPageIdx = stateA.currentPageIndex;
      expect(originalAnchor, greaterThan(0));
      expect(stateA.columnCount, 1);

      // B: wide dual-column desktop viewport.
      controller.updateViewportSize(const Size(1200, 720), debounce: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final stateB = container.read(readerSessionControllerProvider('book-1'));
      expect(stateB.columnCount, 2);
      expect(stateB.anchorOffset, equals(originalAnchor));

      // C: enlarge font size while in dual-column mode.
      await controller.updateTheme(stateB.activeTheme.copyWith(fontSize: 28.0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final stateC = container.read(readerSessionControllerProvider('book-1'));
      expect(stateC.anchorOffset, equals(originalAnchor));

      // Return to A: original narrow viewport + original 18pt font size.
      await controller.updateTheme(stateC.activeTheme.copyWith(fontSize: 18.0));
      controller.updateViewportSize(const Size(400, 700), debounce: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final restored = container.read(readerSessionControllerProvider('book-1'));
      expect(restored.anchorOffset, equals(originalAnchor));
      expect(restored.currentPageIndex, equals(originalPageIdx));
      expect(
        restored.currentPages[restored.currentPageIndex].containsOffset(
          originalAnchor,
        ),
        isTrue,
      );
    });

    test('transitions across chapter boundaries and pre-caches adjacent chapters', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final sub = container.listen(
        readerSessionControllerProvider('book-1'),
        (_, _) {},
      );
      addTearDown(sub.close);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final controller = container.read(
        readerSessionControllerProvider('book-1').notifier,
      );
      controller.updateViewportSize(const Size(1200, 720), debounce: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Adjacent chapter 1 should already be pre-paginated!
      expect(paginator.calls.any((c) => c.$1 == 1), isTrue);

      // Turn to end of chapter 0 and cross into chapter 1.
      while (container
              .read(readerSessionControllerProvider('book-1'))
              .currentChapterIndex ==
          0) {
        await controller.nextPage();
      }
      final ch1State = container.read(
        readerSessionControllerProvider('book-1'),
      );
      expect(ch1State.currentChapterIndex, 1);
      expect(ch1State.anchorOffset, 0);

      // Step backward from start of chapter 1 -> lands on last spread of ch 0.
      await controller.prevPage();
      final backState = container.read(
        readerSessionControllerProvider('book-1'),
      );
      expect(backState.currentChapterIndex, 0);
      expect(backState.currentPageIndex, greaterThan(0));
    });

    test('supports TOC jump, progress seek, jump-undo stack, and bookmarks', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final sub = container.listen(
        readerSessionControllerProvider('book-1'),
        (_, _) {},
      );
      addTearDown(sub.close);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final controller = container.read(
        readerSessionControllerProvider('book-1').notifier,
      );
      controller.updateViewportSize(const Size(420, 760), debounce: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.nextPage();
      final preJumpState = container.read(
        readerSessionControllerProvider('book-1'),
      );
      final preJumpAnchor = preJumpState.anchorOffset;
      expect(preJumpState.canUndoJump, isFalse);

      // Jump to chapter 2 via TOC.
      await controller.jumpToChapter(2);
      var afterJump = container.read(readerSessionControllerProvider('book-1'));
      expect(afterJump.currentChapterIndex, 2);
      expect(afterJump.canUndoJump, isTrue);

      // Add a bookmark at chapter 2, then seek to chapter 0 via slider.
      await controller.addBookmark(note: '重点段落');
      expect(bookRepo.bookmarks, hasLength(1));
      await controller.jumpToProgressRatio(0.1);
      expect(
        container.read(readerSessionControllerProvider('book-1')).currentChapterIndex,
        0,
      );

      // Jump to saved bookmark, then undo twice back to pre-jump ch 0 anchor.
      await controller.jumpToBookmark(bookRepo.bookmarks.first);
      expect(
        container.read(readerSessionControllerProvider('book-1')).currentChapterIndex,
        2,
      );

      await controller.undoLastJump(); // back to 0.1 ratio
      await controller.undoLastJump(); // back to ch 2
      await controller.undoLastJump(); // back to original ch 0 anchor
      afterJump = container.read(readerSessionControllerProvider('book-1'));
      expect(afterJump.currentChapterIndex, 0);
      expect(afterJump.anchorOffset, equals(preJumpAnchor));
      expect(afterJump.canUndoJump, isFalse);

      await controller.deleteBookmark(bookRepo.bookmarks.first.id);
      expect(bookRepo.bookmarks, isEmpty);
    });

    test('debounces progress save <= 500ms, flushes on dispose, and restores platform flags', () async {
      final container = createContainer();
      final sub = container.listen(
        readerSessionControllerProvider('book-1'),
        (_, _) {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final controller = container.read(
        readerSessionControllerProvider('book-1').notifier,
      );
      controller.updateViewportSize(const Size(420, 760), debounce: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.toggleKeepScreenOn();
      await controller.toggleVolumeKeyPaging();
      await controller.toggleImmersive();

      // Volume key down turns page forward when enabled.
      platformBridge.volumeController.add(VolumeKeyDirection.down);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        container.read(readerSessionControllerProvider('book-1')).currentPageIndex,
        1,
      );

      // Debounced save fires within 500ms.
      await Future<void>.delayed(const Duration(milliseconds: 420));
      expect(bookRepo.progress?.charOffset, greaterThan(0));

      // Import custom font updates active theme and persists.
      platformBridge.filesToReturn = const <String>[r'D:\fonts\WenKai.ttf'];
      await controller.importCustomFont();
      expect(fontGateway.importedPaths, equals(<String>[r'D:\fonts\WenKai.ttf']));
      expect(
        container
            .read(readerSessionControllerProvider('book-1'))
            .activeTheme
            .fontFamily,
        'CustomWenKai',
      );

      sub.close();
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(platformBridge.keepScreenOnCalls.last, isFalse);
      expect(platformBridge.volumePagingCalls.last, isFalse);
      expect(platformBridge.immersiveCalls.last, isFalse);
    });
  });
}
