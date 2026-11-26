import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/explore/explore_controller.dart';
import 'package:pureread/application/explore/explore_state.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/application/search/book_detail_controller.dart';
import 'package:pureread/application/search/search_state.dart';
import 'package:pureread/domain/domain.dart';

class _MemoryBookRepo implements BookRepository {
  @override
  Stream<List<Book>> watchBooks({String? groupId}) =>
      const Stream<List<Book>>.empty();

  @override
  Future<List<Book>> listBooks({String? groupId}) async => const <Book>[];

  @override
  Future<Book?> getBookById(String bookId) async => null;

  @override
  Future<Book?> findBySourceAndUrl(
    String sourceId,
    String originBookUrl,
  ) async => null;

  @override
  Future<void> saveBook(Book book) async {}

  @override
  Future<void> deleteBook(String bookId) async {}

  @override
  Future<List<BookGroup>> listGroups() async => const <BookGroup>[];

  @override
  Future<void> saveGroup(BookGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<List<ChapterMeta>> listChapters(String bookId) async =>
      const <ChapterMeta>[];

  @override
  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex) async => null;

  @override
  Future<void> replaceChapters(
    String bookId,
    List<ChapterMeta> chapters,
  ) async {}

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

class _MemorySourceRepo implements SourceRepository {
  final Map<String, BookSource> sources = <String, BookSource>{};

  @override
  Stream<List<BookSource>> watchSources() =>
      Stream<List<BookSource>>.value(sources.values.toList(growable: false));

  @override
  Future<List<BookSource>> listSources({bool enabledOnly = false}) async {
    if (!enabledOnly) return sources.values.toList(growable: false);
    return sources.values.where((s) => s.enabled).toList(growable: false);
  }

  @override
  Future<BookSource?> getSourceById(String sourceId) async => sources[sourceId];

  @override
  Future<void> saveSource(BookSource source) async => sources[source.id] = source;

  @override
  Future<void> saveSources(List<BookSource> list) async {
    for (final source in list) {
      sources[source.id] = source;
    }
  }

  @override
  Future<void> deleteSource(String sourceId) async => sources.remove(sourceId);

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

class _NonExplorableProvider implements BookProvider {
  _NonExplorableProvider(this.providerId);

  @override
  final String providerId;

  @override
  ProviderType get type => ProviderType.legado;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    isLocal: false,
    supportsSearch: true,
    supportsUpdateCheck: true,
    supportsChangeSource: true,
    supportsExplore: false,
  );

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async => throw UnimplementedError();
}

class _FakeExplorableProvider implements ExplorableBookProvider {
  _FakeExplorableProvider({
    required this.providerId,
    this.supportsExplore = true,
    this.onGetCategories,
    this.onExplore,
    this.onDetail,
    this.onToc,
  });

  @override
  final String providerId;

  final bool supportsExplore;

  final Future<List<ExploreCategory>> Function(CancellationToken? cancelToken)?
  onGetCategories;

  final Future<List<BookSearchItem>> Function(
    ExploreCategory category,
    int page,
    CancellationToken? cancelToken,
  )?
  onExplore;

  final Future<BookDetail> Function(String bookUrl)? onDetail;
  final Future<List<ChapterMeta>> Function(String tocUrl)? onToc;

  int getCategoriesCalls = 0;
  final List<({ExploreCategory category, int page})> exploreCalls =
      <({ExploreCategory category, int page})>[];

  @override
  ProviderType get type => ProviderType.legado;

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
    isLocal: false,
    supportsSearch: true,
    supportsUpdateCheck: true,
    supportsChangeSource: true,
    supportsExplore: supportsExplore,
  );

  @override
  Future<({List<ExploreCategory> categories, SourceDebugTrace trace})>
  getExploreCategories({CancellationToken? cancelToken}) async {
    getCategoriesCalls++;
    cancelToken?.throwIfCancelled();
    final categories = onGetCategories == null
        ? const <ExploreCategory>[]
        : await onGetCategories!(cancelToken);
    return (
      categories: categories,
      trace: const SourceDebugTrace(step: 'explore_categories', elapsedMs: 12),
    );
  }

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> explore(
    ExploreCategory category, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    exploreCalls.add((category: category, page: page));
    cancelToken?.throwIfCancelled();
    final items = onExplore == null
        ? const <BookSearchItem>[]
        : await onExplore!(category, page, cancelToken);
    return (
      items: items,
      trace: SourceDebugTrace(step: 'explore_p$page', elapsedMs: 15),
    );
  }

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final detail = onDetail == null
        ? BookDetail(
            sourceId: providerId,
            providerType: ProviderType.legado,
            bookUrl: bookUrl,
            tocUrl: '$bookUrl/toc',
            title: '详情《$bookUrl》',
            author: '作者甲',
            intro: '详情简介',
          )
        : await onDetail!(bookUrl);
    return (
      detail: detail,
      trace: const SourceDebugTrace(step: 'detail', elapsedMs: 8),
    );
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final chapters = onToc == null
        ? const <ChapterMeta>[]
        : await onToc!(tocUrl);
    return (
      chapters: chapters,
      trace: const SourceDebugTrace(step: 'toc', elapsedMs: 9),
    );
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async => throw UnimplementedError();
}

class _ConfigurableFactoryGateway implements BookProviderFactoryGateway {
  _ConfigurableFactoryGateway(this.builders);

  final Map<String, FutureOr<BookProvider> Function(BookSource source)>
  builders;

  @override
  FutureOr<BookProvider> createProvider(BookSource source) {
    final builder = builders[source.id];
    if (builder == null) {
      throw StateError('No builder for ${source.id}');
    }
    return builder(source);
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 26);

  BookSource makeSource(
    String id,
    String name, {
    String groupName = '默认',
    int weight = 0,
    bool enabled = true,
  }) {
    return BookSource(
      id: id,
      name: name,
      groupName: groupName,
      engineType: SourceEngineType.legado,
      baseUrl: 'https://$id.example.com',
      rawDefinition: '{}',
      enabled: enabled,
      weight: weight,
      createdAt: now,
      updatedAt: now,
    );
  }

  BookSearchItem makeBook(
    String sourceId,
    String bookUrl,
    String title, {
    String author = '忘语',
  }) {
    return BookSearchItem(
      sourceId: sourceId,
      providerType: ProviderType.legado,
      bookUrl: bookUrl,
      title: title,
      author: author,
      intro: '$title 简介',
      latestChapterTitle: '最新章节',
    );
  }

  ProviderContainer createContainer({
    required _MemorySourceRepo sourceRepo,
    required Map<String, FutureOr<BookProvider> Function(BookSource)>
    builders,
    _MemoryBookRepo? bookRepo,
  }) {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(bookRepo ?? _MemoryBookRepo()),
        sourceRepositoryProvider.overrideWithValue(sourceRepo),
        bookProviderFactoryProvider.overrideWithValue(
          _ConfigurableFactoryGateway(builders),
        ),
      ],
    );
    addTearDown(container.dispose);

    final exploreSub = container.listen(exploreControllerProvider, (_, _) {});
    final exploreDetailSub = container.listen(
      exploreBookDetailControllerProvider,
      (_, _) {},
    );
    final searchDetailSub = container.listen(
      bookDetailControllerProvider,
      (_, _) {},
    );
    addTearDown(exploreSub.close);
    addTearDown(exploreDetailSub.close);
    addTearDown(searchDetailSub.close);

    return container;
  }

  group('ExploreState', () {
    test('filteredSources matches name or groupName case-insensitively and '
        'copyWith supports clear flags', () {
      final s1 = makeSource('s1', 'Qidian Books', groupName: '玄幻精选');
      final s2 = makeSource('s2', 'JinJiang', groupName: 'Urban Romance');
      const header = ExploreCategory(title: '榜单', url: '');
      const cat = ExploreCategory(title: '热榜', url: '/hot');

      final state = ExploreState(
        exploreSources: <BookSource>[s1, s2],
        selectedSourceId: 's1',
        sourceFilterQuery: 'urban',
        categories: const <ExploreCategory>[header, cat],
        selectedCategory: cat,
        selectedBookUrl: 'https://book/1',
        lastTrace: const SourceDebugTrace(step: 'explore', elapsedMs: 5),
        errorMessage: 'err',
      );

      expect(state.selectedSource, s1);
      expect(state.filteredSources, <BookSource>[s2]);
      expect(
        state.copyWith(sourceFilterQuery: 'QIDIAN').filteredSources,
        <BookSource>[s1],
      );
      expect(state.clickableCategories, const <ExploreCategory>[cat]);

      final cleared = state.copyWith(
        clearSelectedSource: true,
        clearSelectedCategory: true,
        clearSelectedBookUrl: true,
        clearLastTrace: true,
        clearError: true,
      );
      expect(cleared.selectedSourceId, isNull);
      expect(cleared.selectedSource, isNull);
      expect(cleared.selectedCategory, isNull);
      expect(cleared.selectedBookUrl, isNull);
      expect(cleared.lastTrace, isNull);
      expect(cleared.errorMessage, isNull);
    });
  });

  group('ExploreController', () {
    test('filters/sorts explore sources, isolates malformed JSON sources, and '
        'preserves valid selection on reload', () async {
      final sourceRepo = _MemorySourceRepo()
        ..sources['broken'] = makeSource('broken', '坏源', weight: 999)
        ..sources['disabled'] = makeSource(
          'disabled',
          '禁用源',
          weight: 500,
          enabled: false,
        )
        ..sources['no_explore'] = makeSource('no_explore', '无发现源', weight: 300)
        ..sources['flag_false'] = makeSource('flag_false', '能力禁用源', weight: 200)
        ..sources['low_b'] = makeSource('low_b', 'Beta源', weight: 10)
        ..sources['low_a'] = makeSource('low_a', 'Alpha源', weight: 10)
        ..sources['high'] = makeSource(
          'high',
          '高权重源',
          groupName: '精品',
          weight: 100,
        );

      final highProvider = _FakeExplorableProvider(
        providerId: 'high',
        onGetCategories: (_) async => const <ExploreCategory>[
          ExploreCategory(title: '总榜', url: '/high/top'),
        ],
        onExplore: (_, page, _) async => <BookSearchItem>[
          makeBook('high', 'https://high/b1', '高权重榜一'),
        ],
      );
      final lowAProvider = _FakeExplorableProvider(
        providerId: 'low_a',
        onGetCategories: (_) async => const <ExploreCategory>[
          ExploreCategory(title: '分类A', url: '/low_a/cat'),
        ],
      );
      final lowBProvider = _FakeExplorableProvider(providerId: 'low_b');

      final container = createContainer(
        sourceRepo: sourceRepo,
        builders: {
          'broken': (_) => throw const FormatException('Unexpected token <'),
          'disabled': (_) => _FakeExplorableProvider(providerId: 'disabled'),
          'no_explore': (_) => _NonExplorableProvider('no_explore'),
          'flag_false': (_) => _FakeExplorableProvider(
            providerId: 'flag_false',
            supportsExplore: false,
          ),
          'low_b': (_) => lowBProvider,
          'low_a': (_) => lowAProvider,
          'high': (_) => highProvider,
        },
      );

      final controller = container.read(exploreControllerProvider.notifier);
      await controller.loadExploreSources();

      var state = container.read(exploreControllerProvider);
      expect(state.errorMessage, isNull);
      expect(
        state.exploreSources.map((s) => s.id).toList(),
        const <String>['high', 'low_a', 'low_b'],
      );
      expect(state.selectedSourceId, 'high');
      expect(state.selectedCategory?.title, '总榜');
      expect(state.items.map((b) => b.title).toList(), const <String>['高权重榜一']);

      controller.setSourceFilterQuery('精品');
      expect(
        container.read(exploreControllerProvider).filteredSources.single.id,
        'high',
      );

      // Select low_a, then reload sources while low_a remains valid -> preserve selection.
      await controller.selectSource('low_a');
      expect(container.read(exploreControllerProvider).selectedSourceId, 'low_a');

      await controller.loadExploreSources();
      state = container.read(exploreControllerProvider);
      expect(state.selectedSourceId, 'low_a');
      expect(lowAProvider.getCategoriesCalls, 1);

      // Remove low_a -> reload falls back to first sorted valid source ('high').
      sourceRepo.sources.remove('low_a');
      await controller.loadExploreSources();
      state = container.read(exploreControllerProvider);
      expect(state.selectedSourceId, 'high');
    });

    test('caches categories per source and reloads only on forceReloadCategories '
        'or forceRefresh', () async {
      final sourceRepo = _MemorySourceRepo()
        ..sources['s1'] = makeSource('s1', '源一', weight: 20)
        ..sources['s2'] = makeSource('s2', '源二', weight: 10);

      var s1CatFetchCount = 0;
      final s1Provider = _FakeExplorableProvider(
        providerId: 's1',
        onGetCategories: (_) async {
          s1CatFetchCount++;
          return <ExploreCategory>[
            ExploreCategory(title: '排行$s1CatFetchCount', url: '/s1/$s1CatFetchCount'),
          ];
        },
        onExplore: (cat, page, _) async => <BookSearchItem>[
          makeBook('s1', 'https://s1/${cat.title}', '书籍${cat.title}'),
        ],
      );
      final s2Provider = _FakeExplorableProvider(
        providerId: 's2',
        onGetCategories: (_) async => const <ExploreCategory>[
          ExploreCategory(title: '源二榜', url: '/s2/rank'),
        ],
      );

      final container = createContainer(
        sourceRepo: sourceRepo,
        builders: {
          's1': (_) => s1Provider,
          's2': (_) => s2Provider,
        },
      );

      final controller = container.read(exploreControllerProvider.notifier);
      await controller.loadExploreSources();

      expect(s1Provider.getCategoriesCalls, 1);
      expect(
        container
            .read(exploreControllerProvider)
            .categoryCacheBySourceId['s1']
            ?.single
            .title,
        '排行1',
      );

      // Switch to s2, then switch back to s1 -> hits cache without calling provider.
      await controller.selectSource('s2');
      expect(s2Provider.getCategoriesCalls, 1);
      await controller.selectSource('s1');
      expect(s1Provider.getCategoriesCalls, 1);
      expect(container.read(exploreControllerProvider).selectedCategory?.title, '排行1');

      // Force reload categories for s1 -> fetches fresh categories and updates cache.
      await controller.selectSource('s1', forceReloadCategories: true);
      expect(s1Provider.getCategoriesCalls, 2);
      expect(container.read(exploreControllerProvider).selectedCategory?.title, '排行2');

      // loadExploreSources(forceRefresh: true) clears cache and reloads s1.
      await controller.loadExploreSources(forceRefresh: true);
      expect(s1Provider.getCategoriesCalls, 3);
      expect(container.read(exploreControllerProvider).selectedCategory?.title, '排行3');
    });

    test('skips group headers when auto-selecting first category and ignores '
        'header clicks', () async {
      final sourceRepo = _MemorySourceRepo()
        ..sources['s1'] = makeSource('s1', '分组发现源')
        ..sources['headers_only'] = makeSource('headers_only', '纯标题源');

      const header1 = ExploreCategory(title: '男频排行榜', url: '');
      const header2 = ExploreCategory(title: '子分组', url: '   ');
      const firstReal = ExploreCategory(
        title: '玄幻热榜',
        url: '/xuanhuan',
        group: '男频排行榜',
      );
      const secondReal = ExploreCategory(
        title: '都市新书',
        url: '/dushi',
        group: '男频排行榜',
      );

      final s1Provider = _FakeExplorableProvider(
        providerId: 's1',
        onGetCategories: (_) async => const <ExploreCategory>[
          header1,
          header2,
          firstReal,
          secondReal,
        ],
        onExplore: (cat, page, _) async => <BookSearchItem>[
          makeBook('s1', 'https://s1/${cat.url}', '书_${cat.title}'),
        ],
      );
      final headersOnlyProvider = _FakeExplorableProvider(
        providerId: 'headers_only',
        onGetCategories: (_) async => const <ExploreCategory>[header1, header2],
      );

      final container = createContainer(
        sourceRepo: sourceRepo,
        builders: {
          's1': (_) => s1Provider,
          'headers_only': (_) => headersOnlyProvider,
        },
      );

      final controller = container.read(exploreControllerProvider.notifier);
      await controller.loadExploreSources();

      var state = container.read(exploreControllerProvider);
      expect(state.clickableCategories, const <ExploreCategory>[
        firstReal,
        secondReal,
      ]);
      expect(state.selectedCategory, firstReal);
      expect(s1Provider.exploreCalls.length, 1);
      expect(s1Provider.exploreCalls.single.category, firstReal);
      expect(state.items.single.title, '书_玄幻热榜');

      // Clicking a group header must be ignored completely.
      await controller.selectCategory(header1);
      state = container.read(exploreControllerProvider);
      expect(state.selectedCategory, firstReal);
      expect(s1Provider.exploreCalls.length, 1);
      expect(state.items.single.title, '书_玄幻热榜');

      // Source with only group headers has no selectedCategory and never calls explore().
      await controller.selectSource('headers_only');
      state = container.read(exploreControllerProvider);
      expect(state.selectedCategory, isNull);
      expect(state.items, isEmpty);
      expect(state.hasMore, isFalse);
      expect(headersOnlyProvider.exploreCalls, isEmpty);
    });

    test('paginates with URL deduplication, terminates hasMore when empty or '
        'zero unique items, and guards concurrent loadNextPage', () async {
      final sourceRepo = _MemorySourceRepo()
        ..sources['s1'] = makeSource('s1', '分页源');

      final page2Gate = Completer<List<BookSearchItem>>();
      final s1Provider = _FakeExplorableProvider(
        providerId: 's1',
        onGetCategories: (_) async => const <ExploreCategory>[
          ExploreCategory(title: '畅销榜', url: '/bestseller'),
        ],
        onExplore: (_, page, _) async {
          return switch (page) {
            1 => <BookSearchItem>[
              makeBook('s1', 'https://book/1', '书一'),
              makeBook('s1', 'https://book/2', '书二'),
            ],
            2 => page2Gate.future,
            3 => <BookSearchItem>[
              // All duplicates -> 0 new unique items => hasMore = false
              makeBook('s1', 'https://book/1', '书一'),
              makeBook('s1', 'https://book/3', '书三'),
            ],
            _ => const <BookSearchItem>[],
          };
        },
      );

      final container = createContainer(
        sourceRepo: sourceRepo,
        builders: {'s1': (_) => s1Provider},
      );

      final controller = container.read(exploreControllerProvider.notifier);
      await controller.loadExploreSources();

      expect(container.read(exploreControllerProvider).currentPage, 1);
      expect(container.read(exploreControllerProvider).hasMore, isTrue);

      // Fire two concurrent loadNextPage() calls; second must be ignored.
      final firstLoadMore = controller.loadNextPage();
      final secondLoadMore = controller.loadNextPage();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(exploreControllerProvider).isLoadingMore, isTrue);
      expect(
        s1Provider.exploreCalls.where((c) => c.page == 2).length,
        1,
      );

      page2Gate.complete(<BookSearchItem>[
        makeBook('s1', 'https://book/2', '书二重复'),
        makeBook('s1', 'https://book/3', '书三'),
      ]);
      await Future.wait<void>(<Future<void>>[firstLoadMore, secondLoadMore]);

      var state = container.read(exploreControllerProvider);
      expect(state.isLoadingMore, isFalse);
      expect(state.currentPage, 2);
      expect(state.hasMore, isTrue);
      expect(
        state.items.map((b) => b.bookUrl).toList(),
        const <String>['https://book/1', 'https://book/2', 'https://book/3'],
      );
      expect(state.items[1].title, '书二');

      // Page 3 returns only duplicate URLs -> hasMore becomes false.
      await controller.loadNextPage();
      state = container.read(exploreControllerProvider);
      expect(state.hasMore, isFalse);
      expect(state.items.length, 3);

      // Further loadNextPage() must not trigger page 4.
      await controller.loadNextPage();
      expect(s1Provider.exploreCalls.any((c) => c.page == 4), isFalse);

      // refreshCurrentCategory resets back to page 1.
      await controller.refreshCurrentCategory();
      state = container.read(exploreControllerProvider);
      expect(state.currentPage, 1);
      expect(state.items.length, 2);
      expect(state.hasMore, isTrue);
    });

    test('cancels stale requests on rapid source/category switch and on '
        'container dispose', () async {
      final sourceRepo = _MemorySourceRepo()
        ..sources['s1'] = makeSource('s1', '慢源一', weight: 20)
        ..sources['s2'] = makeSource('s2', '快源二', weight: 10);

      final s1CategoryGate = Completer<List<ExploreCategory>>();
      CancellationToken? s1CategoryToken;
      final s1Provider = _FakeExplorableProvider(
        providerId: 's1',
        onGetCategories: (token) {
          s1CategoryToken = token;
          return s1CategoryGate.future;
        },
      );

      final slowCat1Gate = Completer<List<BookSearchItem>>();
      final slowNextPageGate = Completer<List<BookSearchItem>>();
      CancellationToken? cat1Token;
      CancellationToken? nextPageToken;

      const cat1 = ExploreCategory(title: '分类一', url: '/c1');
      const cat2 = ExploreCategory(title: '分类二', url: '/c2');

      final s2Provider = _FakeExplorableProvider(
        providerId: 's2',
        onGetCategories: (_) async => const <ExploreCategory>[cat1, cat2],
        onExplore: (cat, page, token) {
          if (cat == cat1 && page == 1) {
            cat1Token = token;
            return slowCat1Gate.future;
          }
          if (cat == cat2 && page == 2) {
            nextPageToken = token;
            return slowNextPageGate.future;
          }
          return Future<List<BookSearchItem>>.value(<BookSearchItem>[
            makeBook('s2', 'https://s2/${cat.title}/$page', '快书_${cat.title}'),
          ]);
        },
      );

      final container = createContainer(
        sourceRepo: sourceRepo,
        builders: {
          's1': (_) => s1Provider,
          's2': (_) => s2Provider,
        },
      );

      final controller = container.read(exploreControllerProvider.notifier);

      // Start loading s1 (stalls on categories), rapidly switch to s2.
      final loadSourcesFuture = controller.loadExploreSources();
      await Future<void>.delayed(Duration.zero);
      expect(s1CategoryToken, isNotNull);
      expect(s1CategoryToken!.isCancelled, isFalse);

      final switchToS2Future = controller.selectSource('s2');
      await Future<void>.delayed(Duration.zero);

      // s1 category request was cancelled; s2 auto-selected cat1 (now stalled).
      expect(s1CategoryToken!.isCancelled, isTrue);
      expect(cat1Token, isNotNull);
      expect(cat1Token!.isCancelled, isFalse);

      // Rapidly switch category from cat1 to cat2 while cat1 is still stalled.
      await controller.selectCategory(cat2);
      expect(cat1Token!.isCancelled, isTrue);

      // Complete both stale futures late; neither may clobber cat2 state.
      s1CategoryGate.complete(const <ExploreCategory>[
        ExploreCategory(title: '过期分类', url: '/stale'),
      ]);
      slowCat1Gate.complete(<BookSearchItem>[
        makeBook('s2', 'https://stale/book', '过期书籍'),
      ]);
      await loadSourcesFuture;
      await switchToS2Future;

      final state = container.read(exploreControllerProvider);
      expect(state.selectedSourceId, 's2');
      expect(state.selectedCategory, cat2);
      expect(state.items.single.title, '快书_分类二');
      expect(state.errorMessage, isNull);

      // Start loadNextPage() on cat2, then dispose container -> token cancelled.
      final loadMoreFuture = controller.loadNextPage();
      await Future<void>.delayed(Duration.zero);
      expect(nextPageToken, isNotNull);
      expect(nextPageToken!.isCancelled, isFalse);

      container.dispose();
      expect(nextPageToken!.isCancelled, isTrue);

      slowNextPageGate.complete(<BookSearchItem>[
        makeBook('s2', 'https://s2/late', '销毁后返回'),
      ]);
      await loadMoreFuture;
    });

    test('selectBookForDetail loads into exploreBookDetailControllerProvider '
        'without affecting bookDetailControllerProvider', () async {
      final sourceRepo = _MemorySourceRepo()
        ..sources['s1'] = makeSource('s1', '起点发现', weight: 88);

      final s1Provider = _FakeExplorableProvider(
        providerId: 's1',
        onGetCategories: (_) async => const <ExploreCategory>[
          ExploreCategory(title: '月票榜', url: '/yuepiao'),
        ],
        onExplore: (_, page, _) async => <BookSearchItem>[
          makeBook('s1', 'https://explore/book/1', '发现之书', author: '爱潜水的乌贼'),
        ],
        onDetail: (url) async => BookDetail(
          sourceId: 's1',
          providerType: ProviderType.legado,
          bookUrl: url,
          tocUrl: '$url/toc',
          title: '发现之书',
          author: '爱潜水的乌贼',
          intro: '详细简介',
          latestChapterTitle: '第100章',
        ),
        onToc: (tocUrl) async => <ChapterMeta>[
          ChapterMeta(
            bookId: '',
            chapterIndex: 0,
            title: '第一章 启程',
            url: '$tocUrl/0',
            updatedAt: now,
          ),
        ],
      );

      final searchBookProvider = _FakeExplorableProvider(
        providerId: 'search_src',
        onDetail: (url) async => BookDetail(
          sourceId: 'search_src',
          providerType: ProviderType.legado,
          bookUrl: url,
          tocUrl: '$url/toc',
          title: '搜索页书籍',
          author: '搜索作者',
        ),
      );
      sourceRepo.sources['search_src'] = makeSource(
        'search_src',
        '搜索专用源',
        weight: 10,
      );

      final container = createContainer(
        sourceRepo: sourceRepo,
        builders: {
          's1': (_) => s1Provider,
          'search_src': (_) => searchBookProvider,
        },
      );

      // Populate SearchPage's BookDetailController first.
      const searchItem = BookSearchItem(
        sourceId: 'search_src',
        providerType: ProviderType.legado,
        bookUrl: 'https://search/book/99',
        title: '搜索页书籍',
        author: '搜索作者',
      );
      await container
          .read(bookDetailControllerProvider.notifier)
          .loadAggregatedBook(
            const AggregatedSearchBook(
              groupKey: '搜索页书籍||搜索作者',
              title: '搜索页书籍',
              author: '搜索作者',
              sources: <AggregatedSearchSourceEntry>[
                AggregatedSearchSourceEntry(
                  item: searchItem,
                  sourceName: '搜索专用源',
                  sourceWeight: 10,
                ),
              ],
            ),
          );

      final searchDetailBefore = container.read(bookDetailControllerProvider);
      expect(searchDetailBefore.displayTitle, '搜索页书籍');

      // Load explore feed and select book for detail preview.
      final exploreController = container.read(
        exploreControllerProvider.notifier,
      );
      await exploreController.loadExploreSources();
      final exploreItem = container.read(exploreControllerProvider).items.single;

      await exploreController.selectBookForDetail(exploreItem);

      final exploreState = container.read(exploreControllerProvider);
      expect(exploreState.selectedBookUrl, 'https://explore/book/1');

      final exploreDetail = container.read(exploreBookDetailControllerProvider);
      expect(exploreDetail.displayTitle, '发现之书');
      expect(exploreDetail.activeSourceEntry?.sourceName, '起点发现');
      expect(exploreDetail.activeSourceEntry?.sourceWeight, 88);
      expect(exploreDetail.chapters.length, 1);
      expect(exploreDetail.chapters.single.title, '第一章 启程');

      // SearchPage's BookDetailController remains completely untouched.
      final searchDetailAfter = container.read(bookDetailControllerProvider);
      expect(searchDetailAfter.displayTitle, '搜索页书籍');
      expect(
        searchDetailAfter.activeSourceEntry?.item.bookUrl,
        'https://search/book/99',
      );
    });

    test('handles explore errors, clearError, empty page termination, and '
        'clearing state when no explorable sources remain', () async {
      final sourceRepo = _MemorySourceRepo()
        ..sources['s1'] = makeSource('s1', '异常源');

      var shouldFailExplore = true;
      final s1Provider = _FakeExplorableProvider(
        providerId: 's1',
        onGetCategories: (_) async => const <ExploreCategory>[
          ExploreCategory(title: '热榜', url: '/hot'),
        ],
        onExplore: (_, page, _) async {
          if (shouldFailExplore) {
            throw const NetworkFailure(message: '网络超时', isTimeout: true);
          }
          if (page == 1) {
            return <BookSearchItem>[makeBook('s1', 'https://b/1', '书1')];
          }
          return const <BookSearchItem>[];
        },
      );

      final container = createContainer(
        sourceRepo: sourceRepo,
        builders: {'s1': (_) => s1Provider},
      );
      final controller = container.read(exploreControllerProvider.notifier);

      await controller.loadExploreSources();
      expect(container.read(exploreControllerProvider).errorMessage, '网络超时');

      controller.clearError();
      expect(container.read(exploreControllerProvider).errorMessage, isNull);

      shouldFailExplore = false;
      await controller.refreshCurrentCategory();
      expect(container.read(exploreControllerProvider).items.length, 1);
      expect(container.read(exploreControllerProvider).hasMore, isTrue);

      // Empty page 2 sets hasMore = false.
      await controller.loadNextPage();
      expect(container.read(exploreControllerProvider).hasMore, isFalse);

      // Removing all sources clears selection, categories, and items.
      sourceRepo.sources.clear();
      await controller.loadExploreSources();
      final emptyState = container.read(exploreControllerProvider);
      expect(emptyState.exploreSources, isEmpty);
      expect(emptyState.selectedSourceId, isNull);
      expect(emptyState.categories, isEmpty);
      expect(emptyState.selectedCategory, isNull);
      expect(emptyState.items, isEmpty);
      expect(emptyState.hasMore, isFalse);
    });
  });
}
