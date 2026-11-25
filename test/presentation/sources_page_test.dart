import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/application/source_lab/source_health_checker.dart';
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
  _SourcesPageProvider(this._now, {this.providerId = ''});

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
  _SourcesPageFactoryGateway(this._now, {this.onSearch});

  final DateTime _now;
  final Future<({List<BookSearchItem> items, SourceDebugTrace trace})> Function(
    BookSource source,
    String keyword,
    CancellationToken? cancelToken,
  )?
  onSearch;

  @override
  BookProvider createProvider(BookSource source) => onSearch == null
      ? _SourcesPageProvider(_now, providerId: source.id)
      : _CallbackSearchProvider(source, _now, onSearch!);
}

class _CallbackSearchProvider extends _SourcesPageProvider {
  _CallbackSearchProvider(this._source, DateTime now, this._onSearch)
    : super(now, providerId: _source.id);

  final BookSource _source;
  final Future<({List<BookSearchItem> items, SourceDebugTrace trace})> Function(
    BookSource source,
    String keyword,
    CancellationToken? cancelToken,
  )
  _onSearch;

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) => _onSearch(_source, keyword, cancelToken);
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

  testWidgets(
    'SourcesPage shows split group chips sorted by count and opens searchable all-groups dialog',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.reset);

      final sourceRepo = _SourcesPageSourceRepo();
      final groups = <String>[
        '-------,0206⭐,高频分组',
        '高频分组,精选',
        '高频分组,轻小说',
        '玄幻',
        '都市',
        '悬疑',
        '历史',
      ];
      for (var i = 0; i < groups.length; i++) {
        await sourceRepo.saveSource(
          BookSource(
            id: 'src_$i',
            name: '书源$i',
            groupName: groups[i],
            engineType: SourceEngineType.legado,
            baseUrl: 'https://s$i.example.com',
            rawDefinition: '{}',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sourceRepo),
            bookRepositoryProvider.overrideWithValue(_SourcesPageBookRepo()),
          ],
          child: const MaterialApp(home: SourcesPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Divider-only token filtered; frequency-first chip shown; >6 groups button shown.
      expect(find.textContaining('-------'), findsNothing);
      expect(find.text('高频分组 (3)'), findsOneWidget);
      expect(find.textContaining('全部分组'), findsOneWidget);

      await tester.tap(find.textContaining('全部分组'));
      await tester.pumpAndSettle();
      expect(find.text('选择书源分组'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '筛选分组名称...'),
        '轻小说',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('轻小说 (1)').last);
      await tester.pumpAndSettle();

      expect(find.text('书源2'), findsOneWidget);
      expect(find.text('书源3'), findsNothing);
    },
  );

  testWidgets(
    'SourcesPage runs batch health check with live progress, filters by health status, disables and deletes failed sources with confirmation',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);

      final sourceRepo = _SourcesPageSourceRepo();
      await sourceRepo.saveSources(<BookSource>[
        BookSource(
          id: 'src_ok',
          name: '正常书源',
          groupName: '精品',
          engineType: SourceEngineType.legado,
          baseUrl: 'https://ok.example.com',
          rawDefinition: '{}',
          createdAt: now,
          updatedAt: now,
        ),
        BookSource(
          id: 'src_fail',
          name: '报错书源',
          groupName: '精品',
          engineType: SourceEngineType.legado,
          baseUrl: 'https://fail.example.com',
          rawDefinition: '{}',
          createdAt: now,
          updatedAt: now,
        ),
        BookSource(
          id: 'src_timeout',
          name: '超时书源',
          groupName: '精品',
          engineType: SourceEngineType.legado,
          baseUrl: 'https://slow.example.com',
          rawDefinition: '{}',
          createdAt: now,
          updatedAt: now,
        ),
        BookSource(
          id: 'src_disabled',
          name: '禁用书源',
          groupName: '精品',
          engineType: SourceEngineType.legado,
          baseUrl: 'https://disabled.example.com',
          rawDefinition: '{}',
          enabled: false,
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      final searchGate = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sourceRepo),
            bookRepositoryProvider.overrideWithValue(_SourcesPageBookRepo()),
            healthCheckConcurrencyProvider.overrideWithValue(2),
            healthCheckTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 80),
            ),
            bookProviderFactoryProvider.overrideWithValue(
              _SourcesPageFactoryGateway(
                now,
                onSearch: (source, keyword, cancelToken) async {
                  if (source.id == 'src_ok') {
                    await searchGate.future;
                    return (
                      items: <BookSearchItem>[
                        BookSearchItem(
                          sourceId: source.id,
                          providerType: ProviderType.legado,
                          bookUrl: 'https://ok.example.com/1',
                          title: keyword,
                        ),
                      ],
                      trace: const SourceDebugTrace(
                        step: 'search',
                        elapsedMs: 5,
                        httpStatus: 200,
                      ),
                    );
                  }
                  if (source.id == 'src_fail') {
                    throw SourceParseFailure(
                      message: 'HTTP 404 Not Found',
                      sourceId: source.id,
                      step: 'search',
                    );
                  }
                  // src_timeout hangs past 80ms timeout.
                  final cancelCompleter = Completer<void>();
                  cancelToken?.addListener(() {
                    if (!cancelCompleter.isCompleted) {
                      cancelCompleter.completeError(const CancelledFailure());
                    }
                  });
                  await cancelCompleter.future;
                  throw const CancelledFailure();
                },
              ),
            ),
          ],
          child: const MaterialApp(home: SourcesPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Initially 4 unchecked sources.
      expect(find.text('未测 (4)'), findsOneWidget);
      expect(find.text('批量测活'), findsOneWidget);

      await tester.tap(find.text('批量测活'));
      await tester.pump();

      // Live progress bar & stop button shown while searchGate is open.
      expect(find.text('停止测活'), findsOneWidget);
      expect(find.textContaining('测活进度'), findsOneWidget);

      // Release healthy source and let timeout finish.
      searchGate.complete();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      expect(find.text('批量测活'), findsOneWidget);
      expect(find.text('正常 (1)'), findsOneWidget);
      expect(find.text('失效 (2)'), findsOneWidget);
      expect(find.text('未测 (0)'), findsOneWidget);
      expect(find.text('超时'), findsOneWidget);
      expect(find.text('异常'), findsOneWidget);
      expect(find.text('暂不支持'), findsOneWidget);
      expect(find.text('HTTP 404 Not Found'), findsOneWidget);

      // Filter by failedOnly.
      await tester.tap(find.text('失效 (2)'));
      await tester.pumpAndSettle();
      expect(find.text('报错书源'), findsOneWidget);
      expect(find.text('超时书源'), findsOneWidget);
      expect(find.text('正常书源'), findsNothing);

      // Filter by okOnly.
      await tester.tap(find.text('正常 (1)'));
      await tester.pumpAndSettle();
      expect(find.text('正常书源'), findsOneWidget);
      expect(find.text('报错书源'), findsNothing);

      // Reset to all health states.
      await tester.tap(find.text('全部状态'));
      await tester.pumpAndSettle();

      // Disable failed sources.
      await tester.tap(find.text('禁用失效源'));
      await tester.pumpAndSettle();
      expect(sourceRepo.sources['src_fail']?.enabled, isFalse);
      expect(sourceRepo.sources['src_timeout']?.enabled, isFalse);
      expect(sourceRepo.sources['src_ok']?.enabled, isTrue);

      // Delete failed sources requires confirmation dialog.
      await tester.tap(find.text('清理失效源'));
      await tester.pumpAndSettle();
      expect(find.text('清理失效书源'), findsOneWidget);

      // Cancel preserves failed sources.
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(sourceRepo.sources.containsKey('src_fail'), isTrue);

      // Confirm deletion removes only failed sources.
      await tester.tap(find.text('清理失效源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();

      expect(sourceRepo.sources.containsKey('src_fail'), isFalse);
      expect(sourceRepo.sources.containsKey('src_timeout'), isFalse);
      expect(sourceRepo.sources.containsKey('src_ok'), isTrue);
      expect(sourceRepo.sources.containsKey('src_disabled'), isTrue);
    },
  );

  testWidgets(
    'SourcesPage stops active batch health check and renders health controls on mobile without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      final sourceRepo = _SourcesPageSourceRepo();
      await sourceRepo.saveSources(<BookSource>[
        BookSource(
          id: 'm1',
          name: '移动端源1',
          groupName: '默认',
          engineType: SourceEngineType.legado,
          baseUrl: 'https://m1.example.com',
          rawDefinition: '{}',
          lastCheckStatus: SourceCheckStatus.error,
          lastErrorSummary: '连接失败',
          createdAt: now,
          updatedAt: now,
        ),
        BookSource(
          id: 'm2',
          name: '移动端源2',
          groupName: '默认',
          engineType: SourceEngineType.legado,
          baseUrl: 'https://m2.example.com',
          rawDefinition: '{}',
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sourceRepo),
            bookRepositoryProvider.overrideWithValue(_SourcesPageBookRepo()),
            bookProviderFactoryProvider.overrideWithValue(
              _SourcesPageFactoryGateway(
                now,
                onSearch: (source, keyword, cancelToken) async {
                  final cancelCompleter = Completer<void>();
                  cancelToken?.addListener(() {
                    if (!cancelCompleter.isCompleted) {
                      cancelCompleter.completeError(const CancelledFailure());
                    }
                  });
                  await cancelCompleter.future;
                  throw const CancelledFailure();
                },
              ),
            ),
          ],
          child: const MaterialApp(home: SourcesPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('失效 (1)'), findsOneWidget);
      expect(find.text('禁用失效源'), findsOneWidget);
      expect(find.text('清理失效源'), findsOneWidget);

      await tester.tap(find.text('批量测活'));
      await tester.pump();
      expect(find.text('停止测活'), findsOneWidget);

      await tester.tap(find.text('停止测活'));
      await tester.pumpAndSettle();
      expect(find.text('批量测活'), findsOneWidget);
      expect(find.textContaining('已停止测活'), findsOneWidget);
    },
  );
}
