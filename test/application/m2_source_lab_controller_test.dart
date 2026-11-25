import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/application/source_lab/replace_rules_controller.dart';
import 'package:pureread/application/source_lab/source_debug_controller.dart';
import 'package:pureread/application/source_lab/source_debug_state.dart';
import 'package:pureread/application/source_lab/sources_controller.dart';
import 'package:pureread/application/source_lab/sources_state.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/sanitizer/sanitizer.dart';

class _TestSourceRepo implements SourceRepository {
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

class _TestBookRepo implements BookRepository {
  final List<Book> books = <Book>[];

  @override
  Stream<List<Book>> watchBooks({String? groupId}) =>
      Stream<List<Book>>.value(books);

  @override
  Future<List<Book>> listBooks({String? groupId}) async => books;

  @override
  Future<Book?> getBookById(String bookId) async => null;

  @override
  Future<Book?> findBySourceAndUrl(
    String sourceId,
    String originBookUrl,
  ) async => null;

  @override
  Future<void> saveBook(Book book) async => books.add(book);

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
  Future<void> replaceChapters(String bookId, List<ChapterMeta> list) async {}

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

class _FakeDebugProvider implements BookProvider {
  _FakeDebugProvider({
    required this.providerId,
    this.tocCompleter,
    this.failWith,
  });

  @override
  final String providerId;
  final Completer<List<ChapterMeta>>? tocCompleter;
  final AppFailure? failWith;

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
    if (failWith != null) throw failWith!;
    return (
      items: <BookSearchItem>[
        BookSearchItem(
          sourceId: providerId,
          providerType: ProviderType.legado,
          bookUrl: 'https://test.com/book/1',
          title: keyword,
          author: '忘语',
        ),
      ],
      trace: const SourceDebugTrace(
        step: 'search',
        elapsedMs: 25,
        httpStatus: 200,
        requestUrl: 'https://test.com/search',
        matchedPreview: '命中 1 条',
      ),
    );
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
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
        elapsedMs: 18,
        httpStatus: 200,
        requestUrl: 'https://test.com/book/1',
      ),
    );
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final now = DateTime.utc(2026, 11, 24);
    final chapters = tocCompleter != null
        ? await tocCompleter!.future
        : <ChapterMeta>[
            ChapterMeta(
              bookId: 'debug',
              chapterIndex: 0,
              title: '第一章 山边小村',
              url: 'https://test.com/ch/0',
              updatedAt: now,
            ),
            ChapterMeta(
              bookId: 'debug',
              chapterIndex: 1,
              title: '第二章 青牛镇',
              url: 'https://test.com/ch/1',
              updatedAt: now,
            ),
          ];
    cancelToken?.throwIfCancelled();
    return (
      chapters: chapters,
      trace: const SourceDebugTrace(
        step: 'toc',
        elapsedMs: 12,
        httpStatus: 200,
      ),
    );
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    return (
      content: ChapterContent(
        chapterIndex: chapter.chapterIndex,
        title: chapter.title,
        rawText: '【广告】${chapter.title} 正文内容。',
        sourceUrl: chapter.url,
        fetchedAt: DateTime.utc(2026, 11, 24),
      ),
      trace: const SourceDebugTrace(
        step: 'content',
        elapsedMs: 15,
        httpStatus: 200,
      ),
    );
  }
}

class _DebugFactoryGateway implements BookProviderFactoryGateway {
  _DebugFactoryGateway(this._provider);

  final BookProvider _provider;

  @override
  BookProvider createProvider(BookSource source) => _provider;
}

void main() {
  group('SourcesController', () {
    test('batch imports .json and .js files, filters, updates weight/toggle, and exports', () async {
      final tempDir = await Directory.systemTemp.createTemp('pureread_src_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final jsonFile = File(p.join(tempDir.path, 'sources.json'));
      await jsonFile.writeAsString('''
[
  {
    "bookSourceName": "笔趣测试",
    "bookSourceGroup": "玄幻",
    "bookSourceUrl": "https://biqu.example.com#🎃",
    "bookSourceType": 0,
    "enabled": true,
    "weight": 10
  },
  {
    "bookSourceName": "有声源",
    "bookSourceGroup": "音频",
    "bookSourceUrl": "https://audio.example.com",
    "bookSourceType": 1
  }
]
''');
      final jsFile = File(p.join(tempDir.path, 'custom.js'));
      await jsFile.writeAsString('''
// @name: 轻量化JS源
// @url: https://js.example.com
// @group: 精品
function search(k) { return []; }
''');

      final sourceRepo = _TestSourceRepo();
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(sourcesControllerProvider.notifier);
      await ctrl.importFilePaths(<String>[jsonFile.path, jsFile.path]);

      final state = container.read(sourcesControllerProvider);
      expect(state.sources.length, 2);
      expect(state.statusMessage, contains('跳过 1 个非文本源'));
      expect(state.groups, containsAll(<String>['全部', '玄幻', '精品']));

      ctrl.selectGroup('精品');
      expect(container.read(sourcesControllerProvider).filteredSources.length, 1);

      ctrl.selectGroup('全部');
      final jsSource = state.sources.firstWhere(
        (s) => s.engineType == SourceEngineType.jsPlugin,
      );
      await ctrl.toggleEnabled(jsSource.id);
      await ctrl.updateWeight(jsSource.id, 99);

      final updatedJs = sourceRepo.sources[jsSource.id]!;
      expect(updatedJs.enabled, isFalse);
      expect(updatedJs.weight, 99);

      final exported = await ctrl.exportSources();
      expect(exported, contains('笔趣测试'));
      expect(exported, contains('轻量化JS源'));

      await ctrl.deleteSource(jsSource.id);
      expect(container.read(sourcesControllerProvider).sources.length, 1);
    });

    test('SourcesState splits composite Legado groups, strips dividers, and sorts by count', () {
      expect(
        SourcesState.parseGroupTags('-------,0206⭐,最终精简版, 0206⭐ '),
        <String>['0206⭐', '最终精简版'],
      );
      expect(SourcesState.parseGroupTags('-------; === ; '), <String>['默认']);

      final s1 = BookSource(
        id: 'g1',
        name: 'S1',
        groupName: '-------,0206⭐,9.28校验',
        engineType: SourceEngineType.legado,
        baseUrl: 'https://g1.example.com',
        rawDefinition: '{}',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final s2 = s1.copyWith(id: 'g2', name: 'S2', groupName: '9.28校验,精品');
      final s3 = s1.copyWith(id: 'g3', name: 'S3', groupName: '9.28校验');
      final s4 = s1.copyWith(id: 'g4', name: 'S4', groupName: '---');

      final st = SourcesState(
        sources: <BookSource>[s1, s2, s3, s4],
        selectedGroup: '0206⭐',
      );
      expect(st.groups.first, '全部');
      expect(st.groups[1], '9.28校验');
      expect(st.countForGroup('9.28校验'), 3);
      expect(st.countForGroup('0206⭐'), 1);
      expect(st.countForGroup('默认'), 1);
      expect(st.filteredSources.map((s) => s.id).toList(), <String>['g1']);
    });
  });

  group('SourceDebugController', () {
    final now = DateTime.utc(2026, 11, 24);
    final testSource = BookSource(
      id: 'src_dbg',
      name: '调试书源',
      engineType: SourceEngineType.legado,
      baseUrl: 'https://test.com',
      rawDefinition: '{}',
      createdAt: now,
      updatedAt: now,
    );

    test('runs search -> detail -> toc -> content and sanitizes text', () async {
      final sourceRepo = _TestSourceRepo()..sources['src_dbg'] = testSource;
      await sourceRepo.saveReplaceRule(
        ReplaceRule(
          id: 'r1',
          name: '去广告',
          pattern: r'【广告】',
          replacement: '',
          isRegex: true,
          updatedAt: now,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          contentSanitizerProvider.overrideWithValue(
            ContentSanitizerImpl(sourceRepository: sourceRepo),
          ),
          bookProviderFactoryProvider.overrideWithValue(
            _DebugFactoryGateway(_FakeDebugProvider(providerId: 'src_dbg')),
          ),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(sourceDebugControllerProvider.notifier);
      await ctrl.startDebug(sourceId: 'src_dbg', keyword: '凡人修仙传');

      final state = container.read(sourceDebugControllerProvider);
      expect(state.isRunning, isFalse);
      expect(state.steps[DebugStepKind.search]?.status, DebugStepStatus.success);
      expect(state.steps[DebugStepKind.detail]?.status, DebugStepStatus.success);
      expect(state.steps[DebugStepKind.toc]?.status, DebugStepStatus.success);
      expect(state.steps[DebugStepKind.content]?.status, DebugStepStatus.success);
      expect(state.rawContent?.rawText, contains('【广告】'));
      expect(state.sanitizedContent, '第一章 山边小村 正文内容。');
      expect(sourceRepo.sources['src_dbg']?.lastCheckStatus, SourceCheckStatus.ok);

      await ctrl.debugChapter(1);
      expect(
        container.read(sourceDebugControllerProvider).sanitizedContent,
        '第二章 青牛镇 正文内容。',
      );
    });

    test('supports mid-run cancellation and unsupported status mapping', () async {
      final tocGate = Completer<List<ChapterMeta>>();
      final sourceRepo = _TestSourceRepo()..sources['src_dbg'] = testSource;

      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookProviderFactoryProvider.overrideWithValue(
            _DebugFactoryGateway(
              _FakeDebugProvider(providerId: 'src_dbg', tocCompleter: tocGate),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(sourceDebugControllerProvider.notifier);
      unawaited(ctrl.startDebug(sourceId: 'src_dbg', keyword: '凡人'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      ctrl.cancelDebug();
      final cancelledState = container.read(sourceDebugControllerProvider);
      expect(cancelledState.isRunning, isFalse);
      expect(
        cancelledState.steps[DebugStepKind.toc]?.status,
        DebugStepStatus.cancelled,
      );
      expect(
        cancelledState.steps[DebugStepKind.content]?.status,
        DebugStepStatus.skipped,
      );
      tocGate.complete(const <ChapterMeta>[]);

      // Test UnsupportedLegadoRuleFailure -> SourceCheckStatus.unsupported.
      final container2 = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookProviderFactoryProvider.overrideWithValue(
            _DebugFactoryGateway(
              _FakeDebugProvider(
                providerId: 'src_dbg',
                failWith: const UnsupportedLegadoRuleFailure(
                  message: 'webView: true 暂不支持',
                  feature: 'webView',
                  sourceId: 'src_dbg',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container2.dispose);
      await container2
          .read(sourceDebugControllerProvider.notifier)
          .startDebug(sourceId: 'src_dbg', keyword: '凡人');
      expect(
        sourceRepo.sources['src_dbg']?.lastCheckStatus,
        SourceCheckStatus.unsupported,
      );
    });
  });

  group('ReplaceRulesController', () {
    test('supports CRUD, global/source/book scopes, regex validation, and live sanitizer preview', () async {
      final sourceRepo = _TestSourceRepo();
      final bookRepo = _TestBookRepo();
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sourceRepo),
          bookRepositoryProvider.overrideWithValue(bookRepo),
          contentSanitizerProvider.overrideWithValue(
            ContentSanitizerImpl(sourceRepository: sourceRepo),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        ReplaceRulesController.validatePattern('[unclosed', isRegex: true),
        isNotNull,
      );

      final ctrl = container.read(replaceRulesControllerProvider.notifier);
      await ctrl.refresh();

      await ctrl.saveRule(
        id: 'g1',
        name: '全局去水印',
        pattern: r'【.*?】',
        replacement: '',
      );
      await ctrl.saveRule(
        id: 's1_rule',
        name: '单源规则',
        pattern: '求月票',
        replacement: '',
        isRegex: false,
        scopeType: RuleScopeType.source,
        scopeTargetId: 's1',
      );
      await ctrl.saveRule(
        id: 'b1_rule',
        name: '单书规则',
        pattern: '未完待续',
        replacement: '完',
        isRegex: false,
        scopeType: RuleScopeType.book,
        scopeTargetId: 'b1',
      );

      await ctrl.updatePreviewContext(
        rawText: '【广告】正文求月票，未完待续',
        sourceId: 's1',
        bookId: 'b1',
      );

      expect(
        container.read(replaceRulesControllerProvider).previewSanitizedText,
        '正文，完',
      );

      // Switching source away excludes source-scoped rule.
      await ctrl.updatePreviewContext(sourceId: 's2', bookId: 'b1');
      expect(
        container.read(replaceRulesControllerProvider).previewSanitizedText,
        '正文求月票，完',
      );

      // Scope filter + toggle + delete.
      ctrl.setScopeFilter(RuleScopeType.source);
      expect(
        container.read(replaceRulesControllerProvider).filteredRules.single.id,
        's1_rule',
      );

      await ctrl.deleteRule('g1');
      expect(sourceRepo.rules.containsKey('g1'), isFalse);
    });
  });
}
