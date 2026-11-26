import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/app/app.dart';
import 'package:pureread/app/router.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/presentation/explore/explore_page.dart';
import 'package:pureread/presentation/search/online_book_detail_pane.dart';

class _TestBookRepo implements BookRepository {
  final Map<String, Book> books = <String, Book>{};
  final Map<String, List<ChapterMeta>> chapters = <String, List<ChapterMeta>>{};

  @override
  Stream<List<Book>> watchBooks({String? groupId}) =>
      Stream<List<Book>>.value(books.values.toList(growable: false));

  @override
  Future<List<Book>> listBooks({String? groupId}) async =>
      books.values.toList(growable: false);

  @override
  Future<Book?> getBookById(String bookId) async => books[bookId];

  @override
  Future<Book?> findBySourceAndUrl(
    String sourceId,
    String originBookUrl,
  ) async {
    for (final book in books.values) {
      if (book.sourceId == sourceId && book.originBookUrl == originBookUrl) {
        return book;
      }
    }
    return null;
  }

  @override
  Future<void> saveBook(Book book) async => books[book.id] = book;

  @override
  Future<void> deleteBook(String bookId) async => books.remove(bookId);

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
  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex) async => null;

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

class _TestSourceRepo implements SourceRepository {
  _TestSourceRepo(this._sources);

  final List<BookSource> _sources;

  @override
  Stream<List<BookSource>> watchSources() =>
      Stream<List<BookSource>>.value(_sources);

  @override
  Future<List<BookSource>> listSources({bool enabledOnly = false}) async {
    if (!enabledOnly) return _sources;
    return _sources.where((s) => s.enabled).toList(growable: false);
  }

  @override
  Future<BookSource?> getSourceById(String sourceId) async {
    for (final s in _sources) {
      if (s.id == sourceId) return s;
    }
    return null;
  }

  @override
  Future<void> saveSource(BookSource source) async {}

  @override
  Future<void> saveSources(List<BookSource> sources) async {}

  @override
  Future<void> deleteSource(String sourceId) async {}

  @override
  Future<List<ReplaceRule>> listReplaceRules({
    bool enabledOnly = false,
    String? sourceId,
    String? bookId,
  }) async => const <ReplaceRule>[];

  @override
  Future<void> saveReplaceRule(ReplaceRule rule) async {}

  @override
  Future<void> deleteReplaceRule(String ruleId) async {}
}

class _FakeExplorableProvider implements ExplorableBookProvider {
  _FakeExplorableProvider(this.source, this._now);

  final BookSource source;
  final DateTime _now;

  @override
  String get providerId => source.id;

  @override
  ProviderType get type => ProviderType.legado;

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
    isLocal: false,
    supportsSearch: true,
    supportsUpdateCheck: true,
    supportsChangeSource: true,
    supportsExplore: source.id != 'no_explore',
  );

  @override
  Future<({List<ExploreCategory> categories, SourceDebugTrace trace})>
  getExploreCategories({CancellationToken? cancelToken}) async {
    if (source.id == 's1') {
      return (
        categories: const <ExploreCategory>[
          ExploreCategory(title: '热门榜单', url: ''),
          ExploreCategory(
            title: '风云榜',
            url: '/rank/fengyun/{{page}}',
            group: '热门榜单',
          ),
          ExploreCategory(
            title: '新书榜',
            url: '/rank/new/{{page}}',
            group: '热门榜单',
          ),
          ExploreCategory(title: '分类精选', url: ''),
          ExploreCategory(
            title: '错误榜',
            url: '/rank/error/{{page}}',
            group: '分类精选',
          ),
        ],
        trace: const SourceDebugTrace(
          step: 'explore_categories',
          elapsedMs: 5,
          matchedPreview: '5 categories',
        ),
      );
    }

    return (
      categories: const <ExploreCategory>[
        ExploreCategory(title: '女生频道', url: ''),
        ExploreCategory(
          title: '古言榜',
          url: '/rank/guyan/{{page}}',
          group: '女生频道',
        ),
      ],
      trace: const SourceDebugTrace(
        step: 'explore_categories',
        elapsedMs: 4,
        matchedPreview: '2 categories',
      ),
    );
  }

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> explore(
    ExploreCategory category, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    if (category.url.contains('/error/')) {
      throw SourceParseFailure(
        message: '模拟排行榜解析失败：ruleExplore.bookList 为空',
        sourceId: providerId,
        step: 'explore',
      );
    }

    if (source.id == 's2') {
      return (
        items: <BookSearchItem>[
          BookSearchItem(
            sourceId: providerId,
            providerType: ProviderType.legado,
            bookUrl: 'https://s2.example.com/book/901',
            title: '盛世风华',
            author: '南风',
            latestChapterTitle: '第88章 锦绣山河',
            intro: '来自乙发现源的古言榜首作品。',
            kind: '古言',
          ),
        ],
        trace: const SourceDebugTrace(
          step: 'explore',
          elapsedMs: 11,
          httpStatus: 200,
        ),
      );
    }

    if (category.url.contains('/new/')) {
      return (
        items: <BookSearchItem>[
          BookSearchItem(
            sourceId: providerId,
            providerType: ProviderType.legado,
            bookUrl: 'https://s1.example.com/book/201',
            title: '青萍新剑',
            author: '陆沉',
            latestChapterTitle: '第12章 初出茅庐',
            intro: '新书榜第一名。',
            kind: '武侠',
          ),
        ],
        trace: const SourceDebugTrace(
          step: 'explore',
          elapsedMs: 9,
          httpStatus: 200,
        ),
      );
    }

    if (page == 1) {
      return (
        items: <BookSearchItem>[
          BookSearchItem(
            sourceId: providerId,
            providerType: ProviderType.legado,
            bookUrl: 'https://s1.example.com/book/1',
            title: '玄幻榜首',
            author: '青莲剑仙',
            latestChapterTitle: '第999章 证道',
            intro: '风云榜第一名长篇玄幻佳作。',
            kind: '玄幻',
          ),
          BookSearchItem(
            sourceId: providerId,
            providerType: ProviderType.legado,
            bookUrl: 'https://s1.example.com/book/2',
            title: '星辰大道',
            author: '流年',
            latestChapterTitle: '第520章 星海之门',
            intro: '风云榜第二名。',
            kind: '仙侠',
          ),
          BookSearchItem(
            sourceId: providerId,
            providerType: ProviderType.legado,
            bookUrl: 'https://s1.example.com/book/3',
            title: '都市潜龙',
            author: '墨白',
            latestChapterTitle: '第310章 风云际会',
            intro: '风云榜第三名。',
            kind: '都市',
          ),
          BookSearchItem(
            sourceId: providerId,
            providerType: ProviderType.legado,
            bookUrl: 'https://s1.example.com/book/4',
            title: '沧海余生',
            author: '听雨',
            latestChapterTitle: '第200章 归途',
            intro: '风云榜第四名。',
            kind: '历史',
          ),
        ],
        trace: const SourceDebugTrace(
          step: 'explore',
          elapsedMs: 14,
          httpStatus: 200,
        ),
      );
    }

    if (page == 2) {
      return (
        items: <BookSearchItem>[
          BookSearchItem(
            sourceId: providerId,
            providerType: ProviderType.legado,
            bookUrl: 'https://s1.example.com/book/5',
            title: '第二页榜五',
            author: '云客',
            latestChapterTitle: '第80章 破晓',
            intro: '分页加载第2页结果。',
            kind: '科幻',
          ),
        ],
        trace: const SourceDebugTrace(
          step: 'explore',
          elapsedMs: 12,
          httpStatus: 200,
        ),
      );
    }

    return (
      items: const <BookSearchItem>[],
      trace: const SourceDebugTrace(
        step: 'explore',
        elapsedMs: 8,
        httpStatus: 200,
      ),
    );
  }

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    return (
      items: const <BookSearchItem>[],
      trace: const SourceDebugTrace(step: 'search', elapsedMs: 1),
    );
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    return (
      detail: BookDetail(
        sourceId: providerId,
        providerType: ProviderType.legado,
        bookUrl: bookUrl,
        tocUrl: '$bookUrl/toc',
        title: bookUrl.endsWith('/901') ? '盛世风华' : '玄幻榜首',
        author: bookUrl.endsWith('/901') ? '南风' : '青莲剑仙',
        intro: '详情页完整简介 ($providerId)',
        latestChapterTitle: '第999章 证道',
      ),
      trace: const SourceDebugTrace(step: 'detail', elapsedMs: 6),
    );
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    return (
      chapters: <ChapterMeta>[
        ChapterMeta(
          bookId: '',
          chapterIndex: 0,
          title: '第一章 序幕 ($providerId)',
          url: '$tocUrl/0',
          updatedAt: _now,
        ),
        ChapterMeta(
          bookId: '',
          chapterIndex: 1,
          title: '第二章 启程 ($providerId)',
          url: '$tocUrl/1',
          updatedAt: _now,
        ),
      ],
      trace: const SourceDebugTrace(step: 'toc', elapsedMs: 5),
    );
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }
}

class _TestFactoryGateway implements BookProviderFactoryGateway {
  _TestFactoryGateway(this._now);

  final DateTime _now;

  @override
  BookProvider createProvider(BookSource source) =>
      _FakeExplorableProvider(source, _now);
}

void main() {
  final now = DateTime.utc(2026, 11, 26);
  final sampleSources = <BookSource>[
    BookSource(
      id: 's1',
      name: '起点发现源',
      groupName: '男频',
      engineType: SourceEngineType.legado,
      baseUrl: 'https://s1.example.com',
      rawDefinition: '{}',
      weight: 20,
      createdAt: now,
      updatedAt: now,
    ),
    BookSource(
      id: 's2',
      name: '晋江发现源',
      groupName: '女频',
      engineType: SourceEngineType.legado,
      baseUrl: 'https://s2.example.com',
      rawDefinition: '{}',
      weight: 10,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  testWidgets(
    'Empty state shows friendly prompt and navigates to /sources on tap',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);

      var callbackTriggered = false;
      final bookRepo = _TestBookRepo();
      final emptySourceRepo = _TestSourceRepo(<BookSource>[
        BookSource(
          id: 'no_explore',
          name: '无发现书源',
          engineType: SourceEngineType.legado,
          baseUrl: 'https://none.example.com',
          rawDefinition: '{}',
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWithValue(bookRepo),
            sourceRepositoryProvider.overrideWithValue(emptySourceRepo),
            bookProviderFactoryProvider.overrideWithValue(
              _TestFactoryGateway(now),
            ),
          ],
          child: MaterialApp(
            home: ExplorePage(
              onNavigateToSources: () => callbackTriggered = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('发现与排行榜'), findsOneWidget);
      expect(find.textContaining('exploreUrl'), findsOneWidget);
      expect(find.text('前往书源管理'), findsOneWidget);

      await tester.tap(find.text('前往书源管理'));
      await tester.pumpAndSettle();
      expect(callbackTriggered, isTrue);

      // Also verify GoRouter navigation to AppRoutes.sources when mounted under PureReadApp.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWithValue(bookRepo),
            sourceRepositoryProvider.overrideWithValue(emptySourceRepo),
            bookProviderFactoryProvider.overrideWithValue(
              _TestFactoryGateway(now),
            ),
          ],
          child: const PureReadApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发现').last);
      await tester.pumpAndSettle();
      expect(find.text('前往书源管理'), findsOneWidget);

      await tester.tap(find.text('前往书源管理'));
      await tester.pumpAndSettle();
      expect(find.text('书源工作台'), findsOneWidget);
      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(PureReadApp)),
          listen: false,
        ).read(routerProvider).state.uri.path,
        AppRoutes.sources,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Multi-viewport layout test across 390x800, 720x720, 1024x720, and 1280x800 has zero overflow',
    (tester) async {
      final bookRepo = _TestBookRepo();
      final sourceRepo = _TestSourceRepo(sampleSources);
      const viewports = <Size>[
        Size(390, 800),
        Size(720, 720),
        Size(1024, 720),
        Size(1280, 800),
      ];

      for (final size in viewports) {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;

        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey<Size>(size),
            overrides: [
              bookRepositoryProvider.overrideWithValue(bookRepo),
              sourceRepositoryProvider.overrideWithValue(sourceRepo),
              bookProviderFactoryProvider.overrideWithValue(
                _TestFactoryGateway(now),
              ),
            ],
            child: const PureReadApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('发现').last);
        await tester.pumpAndSettle();

        expect(
          find.text('玄幻榜首'),
          findsOneWidget,
          reason: 'Expected books rendered at viewport $size',
        );
        expect(
          find.text('#1'),
          findsOneWidget,
          reason: 'Expected #1 badge at viewport $size',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Expected zero exceptions at viewport $size',
        );

        // At 1280x800 (3-pane desktop), inline OnlineBookDetailPane is present.
        if (size.width >= 1200) {
          expect(find.byType(OnlineBookDetailPane), findsOneWidget);
        }

        // At 720x720 and 1024x720 inside DesktopShell (~80px NavigationRail),
        // ExplorePage receives ~639px / ~943px (2-pane medium) and opens a
        // modal bottom sheet on book tap without overflowing.
        if (size.width == 720 || size.width == 1024) {
          expect(find.byType(OnlineBookDetailPane), findsNothing);
          await tester.tap(find.text('玄幻榜首'));
          await tester.pumpAndSettle();
          expect(find.byType(OnlineBookDetailPane), findsOneWidget);
          expect(find.text('目录预览 (2 章)'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('关闭详情'));
          await tester.pumpAndSettle();
        }
      }
      addTearDown(tester.view.reset);
    },
  );

  testWidgets(
    'Desktop 3-pane switches sources, categories, renders #1/#2/#3 badges, paginates, and shows/clears errors',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);

      final bookRepo = _TestBookRepo();
      final sourceRepo = _TestSourceRepo(sampleSources);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWithValue(bookRepo),
            sourceRepositoryProvider.overrideWithValue(sourceRepo),
            bookProviderFactoryProvider.overrideWithValue(
              _TestFactoryGateway(now),
            ),
          ],
          child: const MaterialApp(home: ExplorePage()),
        ),
      );
      await tester.pumpAndSettle();

      // Initial load: highest weight source s1, first clickable category 风云榜.
      expect(find.text('起点发现源'), findsOneWidget);
      expect(find.text('晋江发现源'), findsOneWidget);
      expect(find.text('热门榜单'), findsOneWidget);
      expect(find.text('分类精选'), findsOneWidget);
      expect(find.text('风云榜'), findsOneWidget);
      expect(find.text('新书榜'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('玄幻榜首'), findsOneWidget);

      // Select book -> right OnlineBookDetailPane loads TOC.
      await tester.tap(find.text('玄幻榜首'));
      await tester.pumpAndSettle();
      expect(find.text('目录预览 (2 章)'), findsOneWidget);
      expect(find.text('第一章 序幕 (s1)'), findsOneWidget);

      // Load page 2 via 加载更多.
      await tester.scrollUntilVisible(
        find.text('加载更多'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('第二页榜五'), findsOneWidget);
      expect(find.text('#5'), findsOneWidget);

      // Switch category to 新书榜.
      await tester.tap(find.text('新书榜'));
      await tester.pumpAndSettle();
      expect(find.text('青萍新剑'), findsOneWidget);
      expect(find.text('星辰大道'), findsNothing);
      expect(find.text('#2'), findsNothing);

      // Trigger error banner on 错误榜 and dismiss it.
      await tester.tap(find.text('错误榜'));
      await tester.pumpAndSettle();
      expect(find.textContaining('模拟排行榜解析失败'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭错误提示'));
      await tester.pumpAndSettle();
      expect(find.textContaining('模拟排行榜解析失败'), findsNothing);

      // Filter sources and switch to s2.
      await tester.enterText(find.byType(TextField), '晋江');
      await tester.pumpAndSettle();
      expect(find.text('权重 20'), findsNothing);
      expect(find.text('权重 10'), findsOneWidget);
      expect(find.text('晋江发现源'), findsOneWidget);

      await tester.tap(find.text('晋江发现源'));
      await tester.pumpAndSettle();
      expect(find.text('盛世风华'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mobile layout drills down to OnlineBookDetailPane and navigates back via AppBar and PopScope',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.reset);

      final bookRepo = _TestBookRepo();
      final sourceRepo = _TestSourceRepo(sampleSources);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWithValue(bookRepo),
            sourceRepositoryProvider.overrideWithValue(sourceRepo),
            bookProviderFactoryProvider.overrideWithValue(
              _TestFactoryGateway(now),
            ),
          ],
          child: const MaterialApp(home: ExplorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnlineBookDetailPane), findsNothing);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('玄幻榜首'), findsOneWidget);

      // Tap book to drill down to detail view.
      await tester.tap(find.text('玄幻榜首'));
      await tester.pumpAndSettle();
      expect(find.byType(OnlineBookDetailPane), findsOneWidget);
      expect(find.byTooltip('返回榜单'), findsOneWidget);
      expect(find.text('目录预览 (2 章)'), findsOneWidget);

      // Return via AppBar back button.
      await tester.tap(find.byTooltip('返回榜单'));
      await tester.pumpAndSettle();
      expect(find.byType(OnlineBookDetailPane), findsNothing);
      expect(find.text('玄幻榜首'), findsOneWidget);

      // Drill down again and verify PopScope intercepts back navigation cleanly.
      await tester.tap(find.text('玄幻榜首'));
      await tester.pumpAndSettle();
      expect(find.byType(OnlineBookDetailPane), findsOneWidget);

      final popScope = tester.widget<PopScope<Object?>>(
        find.byWidgetPredicate((widget) => widget is PopScope),
      );
      expect(popScope.canPop, isFalse);
      popScope.onPopInvokedWithResult?.call(false, null);
      await tester.pumpAndSettle();

      expect(find.byType(OnlineBookDetailPane), findsNothing);
      expect(find.text('玄幻榜首'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
