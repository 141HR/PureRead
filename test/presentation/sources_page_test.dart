import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/sanitizer/sanitizer.dart';
import 'package:pureread/presentation/sources/sources_page.dart';

class _SourcesPageSourceRepo implements SourceRepository {
  final Map<String, BookSource> sources = <String, BookSource>{};
  final Map<String, ReplaceRule> rules = <String, ReplaceRule>{};

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
  Future<void> saveSource(BookSource source) async {
    sources[source.id] = source;
  }

  @override
  Future<void> saveSources(List<BookSource> list) async {
    for (final s in list) {
      sources[s.id] = s;
    }
  }

  @override
  Future<void> deleteSource(String sourceId) async {
    sources.remove(sourceId);
  }

  @override
  Future<List<ReplaceRule>> listReplaceRules({
    bool enabledOnly = false,
    String? sourceId,
    String? bookId,
  }) async {
    return rules.values.where((r) {
      if (enabledOnly && !r.enabled) return false;
      if (sourceId != null || bookId != null) {
        return switch (r.scopeType) {
          RuleScopeType.global => true,
          RuleScopeType.source =>
            sourceId != null && r.scopeTargetId == sourceId,
          RuleScopeType.book => bookId != null && r.scopeTargetId == bookId,
        };
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Future<void> saveReplaceRule(ReplaceRule rule) async {
    rules[rule.id] = rule;
  }

  @override
  Future<void> deleteReplaceRule(String ruleId) async {
    rules.remove(ruleId);
  }
}

class _SourcesPageBookRepo implements BookRepository {
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
  Future<void> replaceChapters(String bookId, List<ChapterMeta> chapters) async {}

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

class _SourcesPageProvider implements BookProvider {
  _SourcesPageProvider(this.providerId, this._now);

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
          bookUrl: 'https://demo.example.com/1',
          title: keyword,
          author: '忘语',
        ),
      ],
      trace: const SourceDebugTrace(
        step: 'search',
        elapsedMs: 12,
        httpStatus: 200,
        requestUrl: 'https://demo.example.com/search',
        matchedPreview: '凡人修仙传',
      ),
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
      ),
      trace: const SourceDebugTrace(
        step: 'detail',
        elapsedMs: 9,
        httpStatus: 200,
      ),
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
          title: '第一章 预览',
          url: '$tocUrl/0',
          updatedAt: _now,
        ),
      ],
      trace: const SourceDebugTrace(
        step: 'toc',
        elapsedMs: 7,
        httpStatus: 200,
      ),
    );
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    return (
      content: ChapterContent(
        chapterIndex: 0,
        title: chapter.title,
        rawText: '【水印广告】正文第一段',
        fetchedAt: _now,
      ),
      trace: const SourceDebugTrace(
        step: 'content',
        elapsedMs: 11,
        httpStatus: 200,
      ),
    );
  }
}

class _SourcesPageFactoryGateway implements BookProviderFactoryGateway {
  _SourcesPageFactoryGateway(this._now);

  final DateTime _now;

  @override
  BookProvider createProvider(BookSource source) =>
      _SourcesPageProvider(source.id, _now);
}

void main() {
  final now = DateTime.utc(2026, 11, 24);

  testWidgets('SourcesPage renders 3 tabs and runs source import, debug trace, and sanitizer preview', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);

    final sourceRepo = _SourcesPageSourceRepo();
    final bookRepo = _SourcesPageBookRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookRepositoryProvider.overrideWithValue(bookRepo),
          contentSanitizerProvider.overrideWithValue(
            ContentSanitizerImpl(sourceRepository: sourceRepo),
          ),
          bookProviderFactoryProvider.overrideWithValue(
            _SourcesPageFactoryGateway(now),
          ),
        ],
        child: const MaterialApp(home: SourcesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('书源管理'), findsOneWidget);
    expect(find.text('书源调试台'), findsOneWidget);
    expect(find.text('正文净化规则'), findsOneWidget);

    // Tab 1: paste-import JSON source.
    await tester.tap(find.text('粘贴导入'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).last,
      '{"bookSourceName":"测试精品源","bookSourceGroup":"精品","bookSourceUrl":"https://demo.example.com"}',
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.text('测试精品源'), findsOneWidget);
    expect(find.text('精品 (1)'), findsOneWidget);

    // Tab 3: create replace rule and verify live sanitizer preview.
    await tester.tap(find.text('正文净化规则'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增规则'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '规则名称'),
      '去除水印广告',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '匹配模式（正则或纯文本）'),
      '【水印广告】',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('去除水印广告'), findsOneWidget);

    // Tab 2: run 4-step source debug trace and inspect sanitized output.
    await tester.tap(find.text('书源调试台'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始调试'));
    await tester.pumpAndSettle();

    expect(find.text('HTTP 200'), findsNWidgets(4));
    expect(find.text('【水印广告】正文第一段'), findsOneWidget);
    expect(find.text('正文第一段'), findsOneWidget);
  });

  testWidgets('SourcesPage renders cleanly on mobile viewport without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final sourceRepo = _SourcesPageSourceRepo();
    final bookRepo = _SourcesPageBookRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookRepositoryProvider.overrideWithValue(bookRepo),
        ],
        child: const MaterialApp(home: SourcesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无在线书源'), findsOneWidget);

    await tester.tap(find.text('书源调试台'));
    await tester.pumpAndSettle();
    expect(find.text('开始调试'), findsOneWidget);

    await tester.tap(find.text('正文净化规则'));
    await tester.pumpAndSettle();
    expect(find.text('实时净化预览 (ContentSanitizer)'), findsOneWidget);
  });
}
