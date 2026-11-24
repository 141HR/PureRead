import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/presentation/search/search_page.dart';

class _WidgetBookRepo implements BookRepository {
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
    for (final b in books.values) {
      if (b.sourceId == sourceId && b.originBookUrl == originBookUrl) return b;
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

class _WidgetSourceRepo implements SourceRepository {
  _WidgetSourceRepo(this._sources);

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

class _WidgetBookProvider implements BookProvider {
  _WidgetBookProvider(this.providerId, this._now);

  @override
  final String providerId;
  final DateTime _now;

  @override
  ProviderType get type => ProviderType.legado;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    isLocal: false,
    supportsSearch: true,
    supportsUpdateCheck: true,
    supportsChangeSource: true,
  );

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    return (
      items: <BookSearchItem>[
        BookSearchItem(
          sourceId: providerId,
          providerType: ProviderType.legado,
          bookUrl: 'https://$providerId.example.com/book/1',
          title: keyword,
          author: '忘语',
          latestChapterTitle: '第100章',
          intro: '来自 $providerId 的简介',
        ),
      ],
      trace: const SourceDebugTrace(step: 'search', elapsedMs: 8),
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
        title: '凡人修仙传',
        author: '忘语',
        intro: '详情介绍 ($providerId)',
        latestChapterTitle: '第100章',
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
          title: '第一章 七玄门 ($providerId)',
          url: '$tocUrl/0',
          updatedAt: _now,
        ),
        ChapterMeta(
          bookId: '',
          chapterIndex: 1,
          title: '第二章 墨大夫 ($providerId)',
          url: '$tocUrl/1',
          updatedAt: _now,
        ),
      ],
      trace: const SourceDebugTrace(step: 'toc', elapsedMs: 7),
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

class _WidgetFactoryGateway implements BookProviderFactoryGateway {
  _WidgetFactoryGateway(this._now);

  final DateTime _now;

  @override
  BookProvider createProvider(BookSource source) =>
      _WidgetBookProvider(source.id, _now);
}

void main() {
  final now = DateTime.utc(2026, 11, 24);
  final sources = <BookSource>[
    BookSource(
      id: 's1',
      name: '甲书源',
      engineType: SourceEngineType.legado,
      baseUrl: 'https://s1.example.com',
      rawDefinition: '{}',
      weight: 20,
      createdAt: now,
      updatedAt: now,
    ),
    BookSource(
      id: 's2',
      name: '乙书源',
      engineType: SourceEngineType.legado,
      baseUrl: 'https://s2.example.com',
      rawDefinition: '{}',
      weight: 10,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  testWidgets('Desktop SearchPage renders 2-pane layout, aggregates results, and adds to bookshelf', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);

    final bookRepo = _WidgetBookRepo();
    final sourceRepo = _WidgetSourceRepo(sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookProviderFactoryProvider.overrideWithValue(
            _WidgetFactoryGateway(now),
          ),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('多源聚合搜索'), findsOneWidget);
    expect(find.text('选择左侧任意书籍以预览详情与章节目录'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '凡人修仙传');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    expect(find.text('2 个书源'), findsOneWidget);
    await tester.tap(find.text('2 个书源'));
    await tester.pumpAndSettle();

    expect(find.text('目录预览 (2 章)'), findsOneWidget);
    expect(find.text('第一章 七玄门 (s1)'), findsOneWidget);

    // Switch preview source chip to s2.
    await tester.tap(find.text('乙书源'));
    await tester.pumpAndSettle();
    expect(find.text('第一章 七玄门 (s2)'), findsOneWidget);

    // Add to bookshelf.
    await tester.tap(find.text('加入书架'));
    await tester.pumpAndSettle();

    expect(find.text('已在书架'), findsOneWidget);
    expect(bookRepo.books.length, 1);
    expect(bookRepo.books.values.single.sourceId, 's2');
  });

  testWidgets('Mobile SearchPage navigates from results to detail and back cleanly', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final bookRepo = _WidgetBookRepo();
    final sourceRepo = _WidgetSourceRepo(sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookProviderFactoryProvider.overrideWithValue(
            _WidgetFactoryGateway(now),
          ),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('多源聚合搜索'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '凡人修仙传');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2 个书源'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('返回搜索结果'), findsOneWidget);
    expect(find.text('目录预览 (2 章)'), findsOneWidget);

    await tester.tap(find.byTooltip('返回搜索结果'));
    await tester.pumpAndSettle();

    expect(find.text('2 个书源'), findsOneWidget);
  });
}
