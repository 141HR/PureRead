import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/application/search/book_detail_controller.dart';
import 'package:pureread/application/search/change_source_controller.dart';
import 'package:pureread/application/search/change_source_state.dart';
import 'package:pureread/application/search/chapter_title_matcher.dart';
import 'package:pureread/application/search/search_controller.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/presentation/search/change_source_sheet.dart';

class _MemoryBookRepo implements BookRepository {
  final Map<String, Book> books = <String, Book>{};
  final Map<String, List<ChapterMeta>> chapters = <String, List<ChapterMeta>>{};
  final Map<String, ReadingProgress> progress = <String, ReadingProgress>{};

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
  Future<ReadingProgress?> getProgress(String bookId) async => progress[bookId];

  @override
  Future<void> saveProgress(ReadingProgress p) async => progress[p.bookId] = p;

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
    for (final s in list) {
      sources[s.id] = s;
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

class _MemoryCacheGateway implements ChapterCacheGateway {
  final Map<String, String> cache = <String, String>{};
  final List<String> deletedBooks = <String>[];

  @override
  String buildCacheKey(String bookId, int chapterIndex) =>
      '$bookId/$chapterIndex.txt';

  @override
  Future<String?> readChapterText(String bookId, int chapterIndex) async =>
      cache[buildCacheKey(bookId, chapterIndex)];

  @override
  Future<String> writeChapterText(
    String bookId,
    int chapterIndex,
    String rawText,
  ) async {
    final key = buildCacheKey(bookId, chapterIndex);
    cache[key] = rawText;
    return key;
  }

  @override
  Future<void> deleteBookCache(String bookId) async {
    deletedBooks.add(bookId);
    cache.removeWhere((k, _) => k.startsWith('$bookId/'));
  }

  @override
  Future<int> getTotalCacheBytes() async => 0;

  @override
  Future<void> clearAllCache() async => cache.clear();
}

class _ConfigurableProvider implements BookProvider {
  _ConfigurableProvider({
    required this.providerId,
    this.onSearch,
    this.onDetail,
    this.onToc,
  });

  @override
  final String providerId;

  final Future<List<BookSearchItem>> Function(
    String keyword,
    CancellationToken? cancelToken,
  )? onSearch;
  final Future<BookDetail> Function(String bookUrl)? onDetail;
  final Future<List<ChapterMeta>> Function(String tocUrl)? onToc;

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
    cancelToken?.throwIfCancelled();
    final items = onSearch == null
        ? const <BookSearchItem>[]
        : await onSearch!(keyword, cancelToken);
    return (
      items: items,
      trace: const SourceDebugTrace(step: 'search', elapsedMs: 10),
    );
  }

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
            tocUrl: bookUrl,
            title: '详情',
          )
        : await onDetail!(bookUrl);
    return (
      detail: detail,
      trace: const SourceDebugTrace(step: 'detail', elapsedMs: 10),
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
      trace: const SourceDebugTrace(step: 'toc', elapsedMs: 10),
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

class _MapFactoryGateway implements BookProviderFactoryGateway {
  _MapFactoryGateway(this.providers);

  final Map<String, BookProvider> providers;

  @override
  BookProvider createProvider(BookSource source) => providers[source.id]!;
}

void main() {
  final now = DateTime.utc(2026, 11, 24);

  BookSource makeSource(String id, String name, {int weight = 0, bool enabled = true}) {
    return BookSource(
      id: id,
      name: name,
      engineType: SourceEngineType.legado,
      baseUrl: 'https://$id.example.com',
      rawDefinition: '{}',
      enabled: enabled,
      weight: weight,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('ChapterTitleMatcher', () {
    test('normalizes Chinese and Arabic numerals and strips noise', () {
      final chapters = <ChapterMeta>[
        ChapterMeta(bookId: 'b', chapterIndex: 0, title: '第一章 初出茅庐', updatedAt: now),
        ChapterMeta(bookId: 'b', chapterIndex: 1, title: '第123章：惊变（求月票）', updatedAt: now),
        ChapterMeta(bookId: 'b', chapterIndex: 2, title: '第一百二十四章 尾声', updatedAt: now),
      ];

      final match = ChapterTitleMatcher.findBestMatch(
        '正文 第一百二十三章 惊变',
        chapters,
        preferredIndex: 1,
      );
      expect(match.isConfident, isTrue);
      expect(match.isExact, isTrue);
      expect(match.matchedIndex, 1);
    });

    test('marks low-confidence mismatch for manual fallback', () {
      final chapters = <ChapterMeta>[
        ChapterMeta(bookId: 'b', chapterIndex: 0, title: '楔子 陌路', updatedAt: now),
        ChapterMeta(bookId: 'b', chapterIndex: 1, title: '卷一 风暴起', updatedAt: now),
      ];

      final match = ChapterTitleMatcher.findBestMatch(
        '第500章 最终决战',
        chapters,
      );
      expect(match.isConfident, isFalse);
    });
  });

  group('SearchController & BookDetailController', () {
    test('enforces bounded concurrency, aggregates by (title, author), and cancels', () async {
      final bookRepo = _MemoryBookRepo();
      final sourceRepo = _MemorySourceRepo();
      var inFlight = 0;
      var maxInFlight = 0;
      final gates = <String, Completer<List<BookSearchItem>>>{};
      final providers = <String, BookProvider>{};

      for (var i = 0; i < 5; i++) {
        final id = 's$i';
        sourceRepo.sources[id] = makeSource(id, '源$i', weight: 10 - i);
        final completer = Completer<List<BookSearchItem>>();
        gates[id] = completer;
        providers[id] = _ConfigurableProvider(
          providerId: id,
          onSearch: (keyword, token) async {
            inFlight++;
            if (inFlight > maxInFlight) maxInFlight = inFlight;
            try {
              if (id == 's2') {
                throw const NetworkFailure(message: '超时', isTimeout: true);
              }
              return await completer.future;
            } finally {
              inFlight--;
            }
          },
        );
      }
      sourceRepo.sources['disabled'] = makeSource(
        'disabled',
        '禁用源',
        enabled: false,
      );

      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookProviderFactoryProvider.overrideWithValue(
            _MapFactoryGateway(providers),
          ),
          searchConcurrencyLimitProvider.overrideWithValue(2),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(searchControllerProvider, (_, _) {});
      addTearDown(sub.close);

      final searchFuture = container
          .read(searchControllerProvider.notifier)
          .search('凡人修仙传');
      await Future<void>.delayed(Duration.zero);

      expect(maxInFlight, lessThanOrEqualTo(2));
      expect(container.read(searchControllerProvider).isSearching, isTrue);

      gates['s0']!.complete(<BookSearchItem>[
        const BookSearchItem(
          sourceId: 's0',
          providerType: ProviderType.legado,
          bookUrl: 'https://s0/1',
          title: '《凡人修仙传》',
          author: '作者：忘语',
          latestChapterTitle: '第2000章',
        ),
      ]);
      gates['s1']!.complete(<BookSearchItem>[
        const BookSearchItem(
          sourceId: 's1',
          providerType: ProviderType.legado,
          bookUrl: 'https://s1/1',
          title: '凡人修仙传',
          author: '忘语',
          intro: '一个普通山村穷小子。',
        ),
      ]);
      gates['s3']!.complete(const <BookSearchItem>[]);
      gates['s4']!.complete(const <BookSearchItem>[]);

      await searchFuture;

      final state = container.read(searchControllerProvider);
      expect(state.isSearching, isFalse);
      expect(state.totalSources, 5);
      expect(state.completedSources, 5);
      expect(state.sourceErrors.length, 1);
      expect(state.results.length, 1);
      expect(state.results.single.sourceCount, 2);
      expect(state.results.single.sources.first.item.sourceId, 's0');

      // Load BookDetail + TOC and add to bookshelf.
      await container
          .read(bookDetailControllerProvider.notifier)
          .loadAggregatedBook(state.results.single);

      // Update providers for detail & toc test.
      providers['s0'] = _ConfigurableProvider(
        providerId: 's0',
        onDetail: (url) async => BookDetail(
          sourceId: 's0',
          providerType: ProviderType.legado,
          bookUrl: url,
          tocUrl: '$url/toc',
          title: '凡人修仙传',
          author: '忘语',
          intro: '简介详情',
        ),
        onToc: (tocUrl) async => <ChapterMeta>[
          ChapterMeta(bookId: '', chapterIndex: 0, title: '第一章 七玄门', url: 'c0', updatedAt: now),
          ChapterMeta(bookId: '', chapterIndex: 1, title: '第二章 墨大夫', url: 'c1', updatedAt: now),
        ],
      );

      await container.read(bookDetailControllerProvider.notifier).reload();
      final detailState = container.read(bookDetailControllerProvider);
      expect(detailState.chapters.length, 2);

      final bookId = await container
          .read(bookDetailControllerProvider.notifier)
          .prepareForReader(initialChapterIndex: 1);
      expect(bookId, isNotNull);
      expect(bookRepo.books[bookId!]?.totalChapters, 2);
      expect(bookRepo.chapters[bookId]?.length, 2);
      expect(bookRepo.progress[bookId]?.chapterIndex, 1);
    });

    test('cancelSearch stops in-flight workers and keeps partial hits', () async {
      final sourceRepo = _MemorySourceRepo()
        ..sources['s1'] = makeSource('s1', '快源')
        ..sources['s2'] = makeSource('s2', '慢源');

      final slowGate = Completer<List<BookSearchItem>>();
      final providers = <String, BookProvider>{
        's1': _ConfigurableProvider(
          providerId: 's1',
          onSearch: (_, _) async => const <BookSearchItem>[
            BookSearchItem(
              sourceId: 's1',
              providerType: ProviderType.legado,
              bookUrl: 'u1',
              title: '诡秘之主',
              author: '爱潜水的乌贼',
            ),
          ],
        ),
        's2': _ConfigurableProvider(
          providerId: 's2',
          onSearch: (_, _) => slowGate.future,
        ),
      };

      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookProviderFactoryProvider.overrideWithValue(
            _MapFactoryGateway(providers),
          ),
        ],
      );
      addTearDown(container.dispose);

      unawaited(
        container.read(searchControllerProvider.notifier).search('诡秘之主'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(searchControllerProvider).results.length, 1);

      container.read(searchControllerProvider.notifier).cancelSearch();
      expect(container.read(searchControllerProvider).isSearching, isFalse);
      expect(container.read(searchControllerProvider).results.length, 1);
      slowGate.complete(const <BookSearchItem>[]);
    });
  });

  group('ChangeSourceController & ChangeSourceSheet', () {
    test('switches source, wipes old cache, and persists matched chapter', () async {
      final bookRepo = _MemoryBookRepo();
      final sourceRepo = _MemorySourceRepo()
        ..sources['old'] = makeSource('old', '旧源')
        ..sources['new'] = makeSource('new', '新源', weight: 10);
      final cacheGateway = _MemoryCacheGateway()
        ..cache['b1/0.txt'] = 'stale-chapter';

      final oldBook = Book(
        id: 'b1',
        sourceId: 'old',
        providerType: ProviderType.legado,
        originBookUrl: 'https://old.com/b1',
        title: '雪中悍刀行',
        author: '烽火戏诸侯',
        totalChapters: 2,
        createdAt: now,
        updatedAt: now,
      );
      await bookRepo.saveBook(oldBook);

      final providers = <String, BookProvider>{
        'old': _ConfigurableProvider(
          providerId: 'old',
          onSearch: (_, _) async => const <BookSearchItem>[
            BookSearchItem(
              sourceId: 'old',
              providerType: ProviderType.legado,
              bookUrl: 'https://old.com/b1',
              title: '雪中悍刀行',
              author: '烽火戏诸侯',
              latestChapterTitle: '第10章',
            ),
          ],
        ),
        'new': _ConfigurableProvider(
          providerId: 'new',
          onSearch: (_, _) async => const <BookSearchItem>[
            BookSearchItem(
              sourceId: 'new',
              providerType: ProviderType.legado,
              bookUrl: 'https://new.com/b1',
              title: '雪中悍刀行',
              author: '烽火戏诸侯',
              latestChapterTitle: '第100章',
            ),
          ],
          onDetail: (url) async => BookDetail(
            sourceId: 'new',
            providerType: ProviderType.legado,
            bookUrl: url,
            tocUrl: '$url/toc',
            title: '雪中悍刀行',
            author: '烽火戏诸侯',
          ),
          onToc: (_) async => <ChapterMeta>[
            ChapterMeta(bookId: '', chapterIndex: 0, title: '第1章 北凉', url: 'n0', updatedAt: now),
            ChapterMeta(bookId: '', chapterIndex: 1, title: '第12章 芦苇荡', url: 'n1', updatedAt: now),
          ],
        ),
      };

      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(bookRepo),
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          chapterCacheGatewayProvider.overrideWithValue(cacheGateway),
          bookProviderFactoryProvider.overrideWithValue(
            _MapFactoryGateway(providers),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(changeSourceControllerProvider, (_, _) {});
      addTearDown(sub.close);

      final ctrl = container.read(changeSourceControllerProvider.notifier);
      await ctrl.loadCandidates(
        book: oldBook,
        currentChapterIndex: 1,
        currentChapterTitle: '第十二章 芦苇荡',
      );

      final state = container.read(changeSourceControllerProvider);
      expect(state.candidates.length, 2);
      expect(state.candidates.first.source.id, 'new');

      await ctrl.selectCandidate(0);
      final afterSelect = container.read(changeSourceControllerProvider);
      expect(afterSelect.selectedTargetChapterIndex, 1);
      expect(afterSelect.showManualPicker, isFalse);

      final switchResult = await ctrl.confirmSwitch();
      expect(switchResult, isNotNull);
      expect(switchResult!.updatedBook.sourceId, 'new');
      expect(switchResult.targetChapterIndex, 1);
      expect(cacheGateway.deletedBooks, contains('b1'));
      expect(bookRepo.chapters['b1']?.length, 2);
      expect(bookRepo.progress['b1']?.chapterIndex, 1);
    });

    testWidgets('ChangeSourceSheet shows manual fallback picker on low similarity', (
      tester,
    ) async {
      final bookRepo = _MemoryBookRepo();
      final sourceRepo = _MemorySourceRepo()
        ..sources['s2'] = makeSource('s2', '备选源');
      final cacheGateway = _MemoryCacheGateway();
      final targetBook = Book(
        id: 'b2',
        sourceId: 's1',
        providerType: ProviderType.legado,
        originBookUrl: 'https://s1.com/b2',
        title: '诛仙',
        author: '萧鼎',
        createdAt: now,
        updatedAt: now,
      );

      final providers = <String, BookProvider>{
        's2': _ConfigurableProvider(
          providerId: 's2',
          onSearch: (_, _) async => const <BookSearchItem>[
            BookSearchItem(
              sourceId: 's2',
              providerType: ProviderType.legado,
              bookUrl: 'https://s2.com/b2',
              title: '诛仙',
              author: '萧鼎',
              latestChapterTitle: '大结局',
            ),
          ],
          onToc: (_) async => <ChapterMeta>[
            ChapterMeta(bookId: '', chapterIndex: 0, title: '楔子', url: 'u0', updatedAt: now),
            ChapterMeta(bookId: '', chapterIndex: 1, title: '草庙村', url: 'u1', updatedAt: now),
          ],
        ),
      };

      ChangeSourceSwitchResult? poppedResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWithValue(bookRepo),
            sourceRepositoryProvider.overrideWithValue(sourceRepo),
            chapterCacheGatewayProvider.overrideWithValue(cacheGateway),
            bookProviderFactoryProvider.overrideWithValue(
              _MapFactoryGateway(providers),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      poppedResult = await ChangeSourceSheet.show(
                        context,
                        book: targetBook,
                        currentChapterIndex: 0,
                        currentChapterTitle: '第999章 完全不同的标题',
                      );
                    },
                    child: const Text('打开换源'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开换源'));
      await tester.pumpAndSettle();

      expect(find.text('备选源'), findsOneWidget);
      await tester.tap(find.text('备选源'));
      await tester.pumpAndSettle();

      // Low similarity triggers manual fallback picker automatically.
      expect(find.text('未精确命中，请手动确认目标章节'), findsOneWidget);
      expect(find.text('草庙村'), findsOneWidget);

      await tester.tap(find.text('草庙村'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('确认切换'));
      await tester.pumpAndSettle();

      expect(poppedResult, isNotNull);
      expect(poppedResult!.targetChapterIndex, 1);
      expect(poppedResult!.updatedBook.sourceId, 's2');
    });
  });
}
