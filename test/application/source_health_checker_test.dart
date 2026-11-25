import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/m2_providers.dart';
import 'package:pureread/application/source_lab/source_health_checker.dart';
import 'package:pureread/application/source_lab/sources_controller.dart';
import 'package:pureread/application/source_lab/sources_state.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

class _RecordingSourceRepo implements SourceRepository {
  final Map<String, BookSource> sources = <String, BookSource>{};
  final List<int> saveSourcesBatchSizes = <int>[];
  final List<String> deletedIds = <String>[];

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
    saveSourcesBatchSizes.add(list.length);
    for (final s in list) {
      sources[s.id] = s;
    }
  }

  @override
  Future<void> deleteSource(String sourceId) async {
    deletedIds.add(sourceId);
    sources.remove(sourceId);
  }

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

typedef _SearchHandler =
    Future<({List<BookSearchItem> items, SourceDebugTrace trace})> Function(
      String keyword,
      int page,
      CancellationToken? cancelToken,
    );

class _ConfigurableProvider implements BookProvider {
  _ConfigurableProvider({
    required this.providerId,
    this.supportsSearch = true,
    this.onSearch,
  });

  @override
  final String providerId;
  final bool supportsSearch;
  final _SearchHandler? onSearch;

  @override
  ProviderType get type => ProviderType.legado;

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
    isLocal: false,
    supportsSearch: supportsSearch,
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
    if (onSearch != null) {
      return onSearch!(keyword, page, cancelToken);
    }
    return (
      items: <BookSearchItem>[
        BookSearchItem(
          sourceId: providerId,
          providerType: ProviderType.legado,
          bookUrl: 'https://$providerId.example.com/book/1',
          title: keyword,
          author: '作者',
        ),
      ],
      trace: const SourceDebugTrace(step: 'search', elapsedMs: 5, httpStatus: 200),
    );
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) => throw UnimplementedError();
}

class _MapFactoryGateway implements BookProviderFactoryGateway {
  _MapFactoryGateway(this._builder);

  final BookProvider Function(BookSource source) _builder;

  @override
  BookProvider createProvider(BookSource source) => _builder(source);
}

class _RealBookProviderFactoryGateway implements BookProviderFactoryGateway {
  const _RealBookProviderFactoryGateway(this._factory);

  final BookProviderFactory _factory;

  @override
  BookProvider createProvider(BookSource source) =>
      _factory.createProvider(source);
}

BookSource _makeSource({
  required String id,
  String? name,
  String groupName = '默认',
  SourceEngineType engineType = SourceEngineType.legado,
  String? baseUrl,
  String rawDefinition = '{}',
  bool enabled = true,
  int weight = 0,
  SourceCheckStatus lastCheckStatus = SourceCheckStatus.unknown,
  String? lastErrorSummary,
}) {
  final now = DateTime.utc(2026, 11, 25);
  return BookSource(
    id: id,
    name: name ?? '书源_$id',
    groupName: groupName,
    engineType: engineType,
    baseUrl: baseUrl ?? 'https://$id.example.com',
    rawDefinition: rawDefinition,
    enabled: enabled,
    weight: weight,
    lastCheckStatus: lastCheckStatus,
    lastErrorSummary: lastErrorSummary,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('SourceHealthChecker', () {
    test('extracts Legado ruleSearch.checkKeyWord and falls back to 凡人', () {
      final withKeyword = _makeSource(
        id: 'kw',
        rawDefinition: jsonEncode(<String, Object?>{
          'ruleSearch': <String, Object?>{'checkKeyWord': '  剑来  '},
        }),
      );
      final emptyKeyword = _makeSource(
        id: 'empty_kw',
        rawDefinition: jsonEncode(<String, Object?>{
          'ruleSearch': <String, Object?>{'checkKeyWord': '   '},
        }),
      );
      final jsSource = _makeSource(
        id: 'js',
        engineType: SourceEngineType.jsPlugin,
        rawDefinition: 'function search(k) { return []; }',
      );
      final malformed = _makeSource(id: 'bad', rawDefinition: '{not json');

      expect(SourceHealthChecker.extractTestKeyword(withKeyword), '剑来');
      expect(SourceHealthChecker.extractTestKeyword(emptyKeyword), '凡人');
      expect(SourceHealthChecker.extractTestKeyword(jsSource), '凡人');
      expect(SourceHealthChecker.extractTestKeyword(malformed), '凡人');
    });

    test(
      'classifies ok, failed, timeout, disabled, non-search, and unsupported sources with batched persistence',
      () async {
        final repo = _RecordingSourceRepo();
        final capturedKeywords = <String, String>{};
        final invokedSources = <String>[];

        final sources = <BookSource>[
          _makeSource(
            id: 'ok_src',
            rawDefinition: jsonEncode(<String, Object?>{
              'ruleSearch': <String, Object?>{'checkKeyWord': '诡秘之主'},
            }),
            lastCheckStatus: SourceCheckStatus.error,
            lastErrorSummary: '历史错误',
          ),
          _makeSource(id: 'empty_items'),
          _makeSource(id: 'parse_err'),
          _makeSource(id: 'timeout_src'),
          _makeSource(id: 'disabled_src', enabled: false),
          _makeSource(id: 'no_search_cap'),
          _makeSource(
            id: 'webview_src',
            rawDefinition: jsonEncode(<String, Object?>{'webView': true}),
          ),
        ];

        final checker = SourceHealthChecker(
          providerFactory: _MapFactoryGateway((source) {
            if (source.id == 'no_search_cap') {
              return _ConfigurableProvider(
                providerId: source.id,
                supportsSearch: false,
              );
            }
            return _ConfigurableProvider(
              providerId: source.id,
              onSearch: (keyword, page, cancelToken) async {
                invokedSources.add(source.id);
                capturedKeywords[source.id] = keyword;
                switch (source.id) {
                  case 'ok_src':
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
                        elapsedMs: 10,
                        httpStatus: 200,
                      ),
                    );
                  case 'empty_items':
                    return (
                      items: const <BookSearchItem>[],
                      trace: const SourceDebugTrace(
                        step: 'search',
                        elapsedMs: 10,
                        httpStatus: 200,
                      ),
                    );
                  case 'parse_err':
                    throw SourceParseFailure(
                      message: 'HTTP 403\nForbidden   by   origin   ${'x' * 150}',
                      sourceId: source.id,
                      step: 'search',
                    );
                  case 'timeout_src':
                    // Simulate an uncooperative provider hanging past timeout.
                    await Completer<void>().future;
                    throw StateError('unreachable');
                  default:
                    throw StateError('unexpected invocation: ${source.id}');
                }
              },
            );
          }),
          sourceRepository: repo,
          concurrency: 3,
          perSourceTimeout: const Duration(milliseconds: 50),
          persistBatchSize: 3,
        );

        final progressEvents = <SourceHealthCheckProgress>[];
        final summary = await checker.checkSources(
          sources,
          onProgress: progressEvents.add,
        );

        expect(summary.totalCount, 7);
        expect(summary.checkedCount, 7);
        expect(summary.okCount, 1);
        expect(summary.failedCount, 2);
        expect(summary.timeoutCount, 1);
        expect(summary.unsupportedCount, 3);
        expect(summary.totalErrorCount, 3);
        expect(summary.isCancelled, isFalse);

        // Disabled, non-search, and static webView sources never hit search().
        expect(
          invokedSources,
          unorderedEquals(<String>[
            'ok_src',
            'empty_items',
            'parse_err',
            'timeout_src',
          ]),
        );
        expect(capturedKeywords['ok_src'], '诡秘之主');
        expect(capturedKeywords['empty_items'], '凡人');

        // Batched persistence: 7 items with batchSize 3 => [3, 3, 1].
        expect(repo.saveSourcesBatchSizes, <int>[3, 3, 1]);

        expect(repo.sources['ok_src']?.lastCheckStatus, SourceCheckStatus.ok);
        expect(repo.sources['ok_src']?.lastErrorSummary, isNull);

        expect(
          repo.sources['empty_items']?.lastCheckStatus,
          SourceCheckStatus.error,
        );
        expect(
          repo.sources['empty_items']?.lastErrorSummary,
          contains('凡人'),
        );

        expect(
          repo.sources['parse_err']?.lastCheckStatus,
          SourceCheckStatus.error,
        );
        final errSummary = repo.sources['parse_err']!.lastErrorSummary!;
        expect(errSummary.length, lessThanOrEqualTo(SourceHealthChecker.maxErrorSummaryLength));
        expect(errSummary, isNot(contains('\n')));

        expect(
          repo.sources['timeout_src']?.lastCheckStatus,
          SourceCheckStatus.error,
        );
        expect(
          repo.sources['timeout_src']?.lastErrorSummary,
          contains('超时'),
        );

        expect(
          repo.sources['disabled_src']?.lastCheckStatus,
          SourceCheckStatus.unsupported,
        );
        expect(
          repo.sources['no_search_cap']?.lastCheckStatus,
          SourceCheckStatus.unsupported,
        );
        expect(
          repo.sources['webview_src']?.lastCheckStatus,
          SourceCheckStatus.unsupported,
        );

        expect(progressEvents.length, 8); // 7 incremental + 1 final completed
        expect(progressEvents.last.isCompleted, isTrue);
        expect(progressEvents.last.checkedCount, 7);
      },
    );

    test('enforces bounded concurrency of 5 across concurrent sources', () async {
      final repo = _RecordingSourceRepo();
      var inFlight = 0;
      var maxInFlight = 0;

      final sources = List<BookSource>.generate(
        14,
        (i) => _makeSource(id: 'c_$i'),
      );

      final checker = SourceHealthChecker(
        providerFactory: _MapFactoryGateway(
          (source) => _ConfigurableProvider(
            providerId: source.id,
            onSearch: (keyword, page, cancelToken) async {
              inFlight++;
              maxInFlight = math.max(maxInFlight, inFlight);
              await Future<void>.delayed(const Duration(milliseconds: 25));
              inFlight--;
              return (
                items: <BookSearchItem>[
                  BookSearchItem(
                    sourceId: source.id,
                    providerType: ProviderType.legado,
                    bookUrl: 'https://x.com/1',
                    title: keyword,
                  ),
                ],
                trace: const SourceDebugTrace(
                  step: 'search',
                  elapsedMs: 25,
                  httpStatus: 200,
                ),
              );
            },
          ),
        ),
        sourceRepository: repo,
      );

      final summary = await checker.checkSources(sources);
      expect(summary.okCount, 14);
      expect(maxInFlight, SourceHealthChecker.defaultConcurrency);
    });

    test('respects CancellationToken mid-run and flushes completed results', () async {
      final repo = _RecordingSourceRepo();
      final cancelToken = CancellationToken();
      final slowGate = Completer<void>();
      var started = 0;
      var fastDone = 0;

      final sources = List<BookSource>.generate(
        8,
        (i) => _makeSource(id: 's_$i'),
      );
      await repo.saveSources(sources);
      repo.saveSourcesBatchSizes.clear();

      final checker = SourceHealthChecker(
        providerFactory: _MapFactoryGateway(
          (source) => _ConfigurableProvider(
            providerId: source.id,
            onSearch: (keyword, page, token) async {
              final idx = int.parse(source.id.substring(2));
              started++;
              if (idx < 2) {
                fastDone++;
                return (
                  items: <BookSearchItem>[
                    BookSearchItem(
                      sourceId: source.id,
                      providerType: ProviderType.legado,
                      bookUrl: 'https://x.com/1',
                      title: keyword,
                    ),
                  ],
                  trace: const SourceDebugTrace(
                    step: 'search',
                    elapsedMs: 1,
                    httpStatus: 200,
                  ),
                );
              }
              final gate = Completer<void>();
              token?.addListener(() {
                if (!gate.isCompleted) {
                  gate.completeError(const CancelledFailure());
                }
              });
              await Future.any(<Future<void>>[slowGate.future, gate.future]);
              throw const CancelledFailure();
            },
          ),
        ),
        sourceRepository: repo,
        concurrency: 3,
        persistBatchSize: 5,
      );

      final future = checker.checkSources(
        sources,
        cancelToken: cancelToken,
        onProgress: (p) {
          if (p.checkedCount >= 2 && !cancelToken.isCancelled) {
            cancelToken.cancel();
          }
        },
      );

      final summary = await future;
      expect(summary.isCancelled, isTrue);
      expect(fastDone, 2);
      expect(summary.okCount, 2);
      expect(started, lessThan(8));
      expect(repo.sources['s_0']?.lastCheckStatus, SourceCheckStatus.ok);
      expect(repo.sources['s_1']?.lastCheckStatus, SourceCheckStatus.ok);
      // Uncompleted sources retain unknown status.
      expect(repo.sources['s_7']?.lastCheckStatus, SourceCheckStatus.unknown);
    });

    test('integrates with real BookProviderFactory and Legado checkKeyWord over HTTP', () async {
      final requestedKeywords = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      unawaited(
        server.forEach((req) async {
          if (req.uri.path == '/search') {
            final q = req.uri.queryParameters['q'] ?? '';
            requestedKeywords.add(q);
            req.response.statusCode = HttpStatus.ok;
            req.response.headers.contentType = ContentType.html;
            req.response.write(
              '<html><body><div class="book"><a href="/book/1">$q</a></div></body></html>',
            );
          } else {
            req.response.statusCode = HttpStatus.internalServerError;
          }
          await req.response.close();
        }),
      );

      final baseUrl = 'http://127.0.0.1:${server.port}';
      final okSource = _makeSource(
        id: 'real_ok',
        baseUrl: baseUrl,
        rawDefinition: jsonEncode(<String, Object?>{
          'bookSourceName': '真实测试源',
          'bookSourceUrl': baseUrl,
          'bookSourceType': 0,
          'searchUrl': '/search?q={{key}}',
          'ruleSearch': <String, Object?>{
            'checkKeyWord': '雪中悍刀行',
            'bookList': '.book',
            'name': 'a@text',
            'bookUrl': 'a@href',
          },
        }),
      );
      final errSource = _makeSource(
        id: 'real_err',
        baseUrl: baseUrl,
        rawDefinition: jsonEncode(<String, Object?>{
          'bookSourceName': '失败测试源',
          'bookSourceUrl': baseUrl,
          'bookSourceType': 0,
          'searchUrl': '/broken?q={{key}}',
          'ruleSearch': <String, Object?>{
            'bookList': '.book',
            'name': 'a@text',
            'bookUrl': 'a@href',
          },
        }),
      );

      final httpClient = SourceHttpClient();
      addTearDown(httpClient.close);
      final repo = _RecordingSourceRepo();
      final checker = SourceHealthChecker(
        providerFactory: _RealBookProviderFactoryGateway(
          BookProviderFactory(httpClient: httpClient),
        ),
        sourceRepository: repo,
        concurrency: 2,
      );

      final summary = await checker.checkSources(<BookSource>[
        okSource,
        errSource,
      ]);

      expect(requestedKeywords, <String>['雪中悍刀行']);
      expect(summary.okCount, 1);
      expect(summary.failedCount, 1);
      expect(repo.sources['real_ok']?.lastCheckStatus, SourceCheckStatus.ok);
      expect(
        repo.sources['real_err']?.lastCheckStatus,
        SourceCheckStatus.error,
      );
    });
  });

  group('SourcesController health check, cleanup, and import deduplication', () {
    test('deduplicates by normalized baseUrl + name in importFilePaths and importFromText', () async {
      final tempDir = await Directory.systemTemp.createTemp('pureread_dedupe_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final repo = _RecordingSourceRepo();
      // Pre-existing source in repository.
      await repo.saveSource(
        _makeSource(
          id: 'existing_1',
          name: '笔趣阁',
          baseUrl: 'https://biqu.example.com/',
        ),
      );

      final file1 = File(p.join(tempDir.path, 'batch1.json'));
      await file1.writeAsString(
        jsonEncode(<Map<String, Object?>>[
          // Duplicate of existing (trailing slash + fragment + host case)
          <String, Object?>{
            'bookSourceName': '  笔趣阁 ',
            'bookSourceUrl': 'HTTPS://BIQU.EXAMPLE.COM#tag1',
            'bookSourceType': 0,
          },
          // New source A
          <String, Object?>{
            'bookSourceName': '新书源A',
            'bookSourceUrl': 'https://a.example.com:443/',
            'bookSourceType': 0,
          },
          // Duplicate of A within same batch
          <String, Object?>{
            'bookSourceName': '新书源A',
            'bookSourceUrl': 'https://a.example.com',
            'bookSourceType': 0,
          },
          // Same baseUrl as A, different name => NOT duplicate
          <String, Object?>{
            'bookSourceName': '新书源A-分站',
            'bookSourceUrl': 'https://a.example.com',
            'bookSourceType': 0,
          },
        ]),
      );

      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(repo),
          sourceImportExportGatewayProvider.overrideWithValue(
            buildGatewayForTest(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(sourcesControllerProvider.notifier);
      await ctrl.importFilePaths(<String>[file1.path]);

      var state = container.read(sourcesControllerProvider);
      expect(state.sources.length, 3); // existing_1 + 新书源A + 新书源A-分站
      expect(state.statusMessage, contains('已导入 2 个书源'));
      expect(state.statusMessage, contains('跳过 2 个重复书源'));

      // Paste import containing one duplicate and one new source.
      final ok = await ctrl.importFromText(
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'bookSourceName': '新书源A',
            'bookSourceUrl': 'https://a.example.com/#frag',
            'bookSourceType': 0,
          },
          <String, Object?>{
            'bookSourceName': '新书源B',
            'bookSourceUrl': 'https://b.example.com',
            'bookSourceType': 0,
          },
        ]),
      );
      expect(ok, isTrue);

      state = container.read(sourcesControllerProvider);
      expect(state.sources.length, 4);
      expect(state.statusMessage, contains('已导入 1 个书源'));
      expect(state.statusMessage, contains('跳过 1 个重复书源'));
    });

    test('filters by SourceHealthFilter, runs batch check on visibleOnly, disables & deletes failed sources', () async {
      final repo = _RecordingSourceRepo();
      await repo.saveSources(<BookSource>[
        _makeSource(id: 'v_ok', name: '可见正常', groupName: '精品'),
        _makeSource(id: 'v_fail', name: '可见失效', groupName: '精品'),
        _makeSource(id: 'other_grp', name: '其他分组', groupName: '普通'),
      ]);

      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(repo),
          bookProviderFactoryProvider.overrideWithValue(
            _MapFactoryGateway(
              (source) => _ConfigurableProvider(
                providerId: source.id,
                onSearch: (keyword, page, token) async {
                  if (source.id == 'v_fail') {
                    throw SourceParseFailure(
                      message: '解析失败',
                      sourceId: source.id,
                      step: 'search',
                    );
                  }
                  return (
                    items: <BookSearchItem>[
                      BookSearchItem(
                        sourceId: source.id,
                        providerType: ProviderType.legado,
                        bookUrl: 'https://ok.com/1',
                        title: keyword,
                      ),
                    ],
                    trace: const SourceDebugTrace(
                      step: 'search',
                      elapsedMs: 5,
                      httpStatus: 200,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(sourcesControllerProvider.notifier);
      await ctrl.refresh();

      ctrl.selectGroup('精品');
      await ctrl.startBatchHealthCheck(visibleOnly: true);

      var state = container.read(sourcesControllerProvider);
      expect(state.isCheckingHealth, isFalse);
      expect(state.healthTotalCount, 2);
      expect(state.healthCheckedCount, 2);
      expect(state.healthOkCount, 1);
      expect(state.healthFailedCount, 1);
      expect(state.failedCount, 1);
      expect(repo.sources['other_grp']?.lastCheckStatus, SourceCheckStatus.unknown);

      // Clear group filter and verify health filters.
      ctrl.selectGroup('全部');
      ctrl.setHealthFilter(SourceHealthFilter.okOnly);
      expect(
        container.read(sourcesControllerProvider).filteredSources.map((s) => s.id),
        <String>['v_ok'],
      );

      ctrl.setHealthFilter(SourceHealthFilter.failedOnly);
      expect(
        container.read(sourcesControllerProvider).filteredSources.map((s) => s.id),
        <String>['v_fail'],
      );

      ctrl.setHealthFilter(SourceHealthFilter.uncheckedOnly);
      expect(
        container.read(sourcesControllerProvider).filteredSources.map((s) => s.id),
        <String>['other_grp'],
      );

      ctrl.setHealthFilter(SourceHealthFilter.all);

      // Disable failed sources leaves ok & unchecked enabled.
      await ctrl.disableFailedSources();
      expect(repo.sources['v_fail']?.enabled, isFalse);
      expect(repo.sources['v_ok']?.enabled, isTrue);
      expect(repo.sources['other_grp']?.enabled, isTrue);
      expect(
        container.read(sourcesControllerProvider).statusMessage,
        contains('已禁用 1 个失效书源'),
      );

      // Delete failed sources removes only failed source.
      await ctrl.deleteFailedSources();
      expect(repo.sources.containsKey('v_fail'), isFalse);
      expect(repo.sources.containsKey('v_ok'), isTrue);
      expect(repo.sources.containsKey('other_grp'), isTrue);
      state = container.read(sourcesControllerProvider);
      expect(state.failedCount, 0);
      expect(state.statusMessage, contains('已清理 1 个失效书源'));
    });

    test('cancelBatchHealthCheck stops active check cleanly', () async {
      final repo = _RecordingSourceRepo();
      await repo.saveSources(
        List<BookSource>.generate(6, (i) => _makeSource(id: 'c_$i')),
      );

      final gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(repo),
          healthCheckConcurrencyProvider.overrideWithValue(2),
          bookProviderFactoryProvider.overrideWithValue(
            _MapFactoryGateway(
              (source) => _ConfigurableProvider(
                providerId: source.id,
                onSearch: (keyword, page, token) async {
                  final cancelCompleter = Completer<void>();
                  token?.addListener(() {
                    if (!cancelCompleter.isCompleted) {
                      cancelCompleter.completeError(const CancelledFailure());
                    }
                  });
                  await Future.any(<Future<void>>[
                    gate.future,
                    cancelCompleter.future,
                  ]);
                  throw const CancelledFailure();
                },
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(sourcesControllerProvider.notifier);
      await ctrl.refresh();

      final runFuture = ctrl.startBatchHealthCheck();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(sourcesControllerProvider).isCheckingHealth, isTrue);

      ctrl.cancelBatchHealthCheck();
      expect(container.read(sourcesControllerProvider).isCheckingHealth, isFalse);

      await runFuture;
      final state = container.read(sourcesControllerProvider);
      expect(state.isCheckingHealth, isFalse);
      expect(state.statusMessage, contains('已停止测活'));
    });
  });
}

SourceImportExportGateway buildGatewayForTest() {
  return const _ServiceGateway(SourceImportExportService());
}

class _ServiceGateway implements SourceImportExportGateway {
  const _ServiceGateway(this._service);
  final SourceImportExportService _service;

  @override
  Future<SourceImportResult> parseImportFile(String filePath) async {
    final batch = await _service.importFromFile(filePath);
    return SourceImportResult(
      sources: batch.sources,
      skippedNonTextCount: batch.skippedNonTextCount,
      invalidCount: batch.invalidCount,
      messages: batch.messages,
    );
  }

  @override
  Future<SourceImportResult> parseImportText(
    String rawText, {
    String? fileName,
  }) async {
    final batch = await _service.importFromText(rawText, fileName: fileName);
    return SourceImportResult(
      sources: batch.sources,
      skippedNonTextCount: batch.skippedNonTextCount,
      invalidCount: batch.invalidCount,
      messages: batch.messages,
    );
  }

  @override
  Future<String> exportSources(List<BookSource> sources) async =>
      _service.exportSources(sources);
}
