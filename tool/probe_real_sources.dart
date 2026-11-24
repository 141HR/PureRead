import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_compat.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

const String _file1Path = r'd:\QQ\Downloads\超级精品书源1031个10月10日.json';
const String _file2Path = r'd:\QQ\Downloads\精品书源合集.json';

class _ProbeOutcome {
  final String sourceName;
  final String fileLabel;
  final String baseUrl;
  final String categoryTag;
  final String queryUsed;
  final String reachedStage;
  final String outcomeType;
  final int? httpStatus;
  final int totalElapsedMs;
  final int searchItems;
  final int tocChapters;
  final int contentChars;
  final String detail;

  const _ProbeOutcome({
    required this.sourceName,
    required this.fileLabel,
    required this.baseUrl,
    required this.categoryTag,
    required this.queryUsed,
    required this.reachedStage,
    required this.outcomeType,
    required this.httpStatus,
    required this.totalElapsedMs,
    required this.searchItems,
    required this.tocChapters,
    required this.contentChars,
    required this.detail,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceName': sourceName,
    'fileLabel': fileLabel,
    'baseUrl': baseUrl,
    'categoryTag': categoryTag,
    'queryUsed': queryUsed,
    'reachedStage': reachedStage,
    'outcomeType': outcomeType,
    'httpStatus': httpStatus,
    'totalElapsedMs': totalElapsedMs,
    'searchItems': searchItems,
    'tocChapters': tocChapters,
    'contentChars': contentChars,
    'detail': detail,
  };
}

Future<void> main(List<String> args) async {
  final file1 = File(_file1Path);
  final file2 = File(_file2Path);
  if (!file1.existsSync() || !file2.existsSync()) {
    stdout.writeln(
      'Missing real corpus files:\n  - $_file1Path (exists=${file1.existsSync()})\n  - $_file2Path (exists=${file2.existsSync()})',
    );
    exitCode = 1;
    return;
  }

  final raw1 = await file1.readAsString();
  final raw2 = await file2.readAsString();

  final syncRes1 = LegadoSourceParser.parseBatchSync(raw1);
  final syncRes2 = LegadoSourceParser.parseBatchSync(raw2);

  final isoRes1 = await LegadoSourceParser.parseBatch(raw1, useIsolate: true);
  final isoRes2 = await LegadoSourceParser.parseBatch(raw2, useIsolate: true);

  stdout.writeln('=== Batch Parse Benchmark ===');
  _printBatchSummary('File1 (1031)', file1.lengthSync(), syncRes1, isoRes1);
  _printBatchSummary('File2 (1662)', file2.lengthSync(), syncRes2, isoRes2);

  final featureCounts1 = _countFeatures(isoRes1.items);
  final featureCounts2 = _countFeatures(isoRes2.items);
  final totalTypeBreakdown = _countTypes(<LegadoParsedSource>[
    ...isoRes1.items,
    ...isoRes2.items,
  ]);

  stdout.writeln('\n=== Compatibility Breakdown ===');
  stdout.writeln('Types: $totalTypeBreakdown');
  stdout.writeln('File1 features: $featureCounts1');
  stdout.writeln('File2 features: $featureCounts2');

  final candidates = _selectDiverseCandidates(
    file1Items: isoRes1.items,
    file2Items: isoRes2.items,
    targetCount: 20,
  );

  stdout.writeln(
    '\n=== Running Bounded Live Smoke Probe (${candidates.length} sources, 6s HTTP timeout) ===',
  );

  final httpClient = SourceHttpClient(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    defaultRateLimitMs: 500,
  );
  final factory = BookProviderFactory(
    httpClient: httpClient,
    defaultJsTimeout: const Duration(seconds: 4),
  );

  final outcomes = <_ProbeOutcome>[];
  try {
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      stdout.writeln(
        '[${i + 1}/${candidates.length}] Probing ${c.item.legado.bookSourceName} '
        '(${c.categoryTag}) -> ${c.item.legado.effectiveBaseUrl}',
      );
      final outcome = await _probeSingleSource(
        factory: factory,
        parsed: c.item,
        fileLabel: c.fileLabel,
        categoryTag: c.categoryTag,
      );
      outcomes.add(outcome);
      stdout.writeln(
        '   -> stage=${outcome.reachedStage}, outcome=${outcome.outcomeType}, '
        'status=${outcome.httpStatus}, ms=${outcome.totalElapsedMs}, '
        'items=${outcome.searchItems}, chapters=${outcome.tocChapters}, '
        'chars=${outcome.contentChars}, detail=${outcome.detail}',
      );
    }
  } finally {
    httpClient.close();
  }

  final reportJson = <String, Object?>{
    'file1': <String, Object?>{
      'path': _file1Path,
      'bytes': file1.lengthSync(),
      'syncMs': syncRes1.elapsedMs,
      'isolateMs': isoRes1.elapsedMs,
      'total': isoRes1.totalCount,
      'parseErrors': isoRes1.parseErrors.length,
      'supported': isoRes1.supportedCount,
      'unsupportedType': isoRes1.unsupportedTypeCount,
      'malformedBaseUrl': isoRes1.malformedBaseUrlCount,
      'unsupportedWebView': isoRes1.unsupportedWebViewCount,
      'unsupportedRhino': isoRes1.unsupportedRhinoCount,
      'fragmentTagged': isoRes1.fragmentTaggedCount,
      'features': featureCounts1,
    },
    'file2': <String, Object?>{
      'path': _file2Path,
      'bytes': file2.lengthSync(),
      'syncMs': syncRes2.elapsedMs,
      'isolateMs': isoRes2.elapsedMs,
      'total': isoRes2.totalCount,
      'parseErrors': isoRes2.parseErrors.length,
      'supported': isoRes2.supportedCount,
      'unsupportedType': isoRes2.unsupportedTypeCount,
      'malformedBaseUrl': isoRes2.malformedBaseUrlCount,
      'unsupportedWebView': isoRes2.unsupportedWebViewCount,
      'unsupportedRhino': isoRes2.unsupportedRhinoCount,
      'fragmentTagged': isoRes2.fragmentTaggedCount,
      'features': featureCounts2,
    },
    'typeBreakdown': totalTypeBreakdown,
    'liveProbeOutcomes': outcomes.map((o) => o.toJson()).toList(),
  };

  stdout.writeln('\n=== PROBE_JSON_BEGIN ===');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(reportJson));
  stdout.writeln('=== PROBE_JSON_END ===');
  await stdout.flush();
  exit(0);
}

void _printBatchSummary(
  String label,
  int bytes,
  LegadoBatchParseResult syncRes,
  LegadoBatchParseResult isoRes,
) {
  stdout.writeln(
    '$label: ${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB | '
    'total=${isoRes.totalCount}, parseErrors=${isoRes.parseErrors.length}, '
    'sync=${syncRes.elapsedMs}ms, isolate=${isoRes.elapsedMs}ms | '
    'supported=${isoRes.supportedCount}, nonText=${isoRes.unsupportedTypeCount}, '
    'malformedUrl=${isoRes.malformedBaseUrlCount}, webView=${isoRes.unsupportedWebViewCount}, '
    'rhino=${isoRes.unsupportedRhinoCount}, fragmentUrl=${isoRes.fragmentTaggedCount}',
  );
}

Map<String, int> _countFeatures(List<LegadoParsedSource> items) {
  final counts = <String, int>{};
  for (final item in items) {
    for (final f in item.detectedFeatures) {
      counts[f] = (counts[f] ?? 0) + 1;
    }
  }
  return counts;
}

Map<String, int> _countTypes(List<LegadoParsedSource> items) {
  final counts = <String, int>{};
  for (final item in items) {
    final key = switch (item.legado.bookSourceType) {
      0 => 'text(0)',
      1 => 'audio(1)',
      2 => 'image(2)',
      3 => 'file(3)',
      final other => 'other($other)',
    };
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

typedef _Candidate = ({
  LegadoParsedSource item,
  String fileLabel,
  String categoryTag,
});

List<_Candidate> _selectDiverseCandidates({
  required List<LegadoParsedSource> file1Items,
  required List<LegadoParsedSource> file2Items,
  required int targetCount,
}) {
  final pool = <_Candidate>[
    for (final item in file1Items)
      if (_isProbeEligible(item))
        (item: item, fileLabel: '1031集', categoryTag: _classifyTag(item)),
    for (final item in file2Items)
      if (_isProbeEligible(item))
        (item: item, fileLabel: '1662合集', categoryTag: _classifyTag(item)),
  ];

  // Prefer higher-weight sources first within each feature category so the
  // sample includes well-curated sources across diverse DSL styles.
  pool.sort((a, b) => b.item.legado.weight.compareTo(a.item.legado.weight));

  final selected = <_Candidate>[];
  final seenHosts = <String>{};
  final byTag = <String, List<_Candidate>>{};
  for (final c in pool) {
    byTag.putIfAbsent(c.categoryTag, () => <_Candidate>[]).add(c);
  }

  final preferredOrder = <String>[
    'GET-CSS',
    'POST-GBK',
    'POST-UTF8',
    'JSONPath',
    'XPath',
    'JS-Embedded',
    'Pagination',
    'FragmentURL',
    'Combinator',
  ];

  // Pick up to 2-3 per bucket first for diversity.
  for (var round = 0; round < 3 && selected.length < targetCount; round++) {
    for (final tag in preferredOrder) {
      if (selected.length >= targetCount) break;
      final list = byTag[tag];
      if (list == null) continue;
      for (final c in list) {
        final host =
            SourceHttpClient.tryNormalizeHttpUri(
              c.item.legado.effectiveBaseUrl,
            )?.host.toLowerCase() ??
            c.item.legado.effectiveBaseUrl;
        if (seenHosts.contains(host)) continue;
        seenHosts.add(host);
        selected.add(c);
        break;
      }
    }
  }

  // Fill remainder up to targetCount.
  for (final c in pool) {
    if (selected.length >= targetCount) break;
    final host =
        SourceHttpClient.tryNormalizeHttpUri(
          c.item.legado.effectiveBaseUrl,
        )?.host.toLowerCase() ??
        c.item.legado.effectiveBaseUrl;
    if (seenHosts.contains(host)) continue;
    seenHosts.add(host);
    selected.add(c);
  }

  return selected;
}

bool _isProbeEligible(LegadoParsedSource item) {
  if (!item.isSupported) return false;
  final s = item.legado;
  if (!s.enabled) return false;
  if ((s.searchUrl ?? '').trim().isEmpty) return false;
  if (s.ruleSearch.bookList.trim().isEmpty ||
      s.ruleSearch.name.trim().isEmpty ||
      s.ruleToc.chapterList.trim().isEmpty ||
      s.ruleContent.content.trim().isEmpty) {
    return false;
  }
  return true;
}

String _classifyTag(LegadoParsedSource item) {
  final f = item.detectedFeatures;
  if (f.contains('jsonPath')) return 'JSONPath';
  if (f.contains('xpath')) return 'XPath';
  if (f.contains('post') && f.contains('gbkCharset')) return 'POST-GBK';
  if (f.contains('post')) return 'POST-UTF8';
  if (f.contains('embeddedJs')) return 'JS-Embedded';
  if (f.contains('fragmentUrl')) return 'FragmentURL';
  if (f.contains('nextTocUrl') || f.contains('nextContentUrl')) {
    return 'Pagination';
  }
  if (f.contains('combinators')) return 'Combinator';
  return 'GET-CSS';
}

Future<_ProbeOutcome> _probeSingleSource({
  required BookProviderFactory factory,
  required LegadoParsedSource parsed,
  required String fileLabel,
  required String categoryTag,
}) async {
  final sw = Stopwatch()..start();
  final provider = factory.createProvider(parsed.domainSource);
  const queries = <String>['凡人修仙传', '诡秘之主'];

  var reached = 'init';
  int? lastStatus;
  var searchItemsCount = 0;
  var tocChaptersCount = 0;
  var contentChars = 0;
  var queryUsed = queries.first;
  final cancelToken = CancellationToken();

  try {
    return await (() async {
      List<BookSearchItem> items = const <BookSearchItem>[];
      SourceParseFailure? lastSearchParseError;

      for (final q in queries) {
        queryUsed = q;
        try {
          final searchRes = await provider.search(
            q,
            page: 1,
            cancelToken: cancelToken,
          );
          lastStatus = searchRes.trace.httpStatus;
          if (searchRes.items.isNotEmpty) {
            items = searchRes.items;
            break;
          }
        } on SourceParseFailure catch (e) {
          lastSearchParseError = e;
        }
      }

      if (items.isEmpty) {
        if (lastSearchParseError != null) throw lastSearchParseError;
        sw.stop();
        return _ProbeOutcome(
          sourceName: parsed.legado.bookSourceName,
          fileLabel: fileLabel,
          baseUrl: parsed.legado.effectiveBaseUrl,
          categoryTag: categoryTag,
          queryUsed: queryUsed,
          reachedStage: 'search',
          outcomeType: 'EmptySearch',
          httpStatus: lastStatus,
          totalElapsedMs: sw.elapsedMilliseconds,
          searchItems: 0,
          tocChapters: 0,
          contentChars: 0,
          detail: 'Search HTTP 200 but matched 0 books',
        );
      }

      reached = 'search';
      searchItemsCount = items.length;
      final pickedBook = items.first;

      final detailRes = await provider.getBookDetail(
        pickedBook.bookUrl,
        cancelToken: cancelToken,
      );
      reached = 'detail';
      lastStatus = detailRes.trace.httpStatus ?? lastStatus;

      final tocRes = await provider.getToc(
        detailRes.detail.tocUrl,
        cancelToken: cancelToken,
      );
      reached = 'toc';
      lastStatus = tocRes.trace.httpStatus ?? lastStatus;
      tocChaptersCount = tocRes.chapters.length;
      if (tocRes.chapters.isEmpty) {
        sw.stop();
        return _ProbeOutcome(
          sourceName: parsed.legado.bookSourceName,
          fileLabel: fileLabel,
          baseUrl: parsed.legado.effectiveBaseUrl,
          categoryTag: categoryTag,
          queryUsed: queryUsed,
          reachedStage: 'toc',
          outcomeType: 'EmptyToc',
          httpStatus: lastStatus,
          totalElapsedMs: sw.elapsedMilliseconds,
          searchItems: searchItemsCount,
          tocChapters: 0,
          contentChars: 0,
          detail: 'Book "${detailRes.detail.title}" had 0 TOC chapters',
        );
      }

      final contentRes = await provider.getChapterContent(
        tocRes.chapters.first,
        cancelToken: cancelToken,
      );
      reached = 'content';
      lastStatus = contentRes.trace.httpStatus ?? lastStatus;
      contentChars = contentRes.content.rawText.length;
      sw.stop();

      final preview = contentRes.content.rawText
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final clipped = preview.length > 48
          ? '${preview.substring(0, 48)}...'
          : preview;

      return _ProbeOutcome(
        sourceName: parsed.legado.bookSourceName,
        fileLabel: fileLabel,
        baseUrl: parsed.legado.effectiveBaseUrl,
        categoryTag: categoryTag,
        queryUsed: queryUsed,
        reachedStage: 'content',
        outcomeType: 'Success',
        httpStatus: lastStatus,
        totalElapsedMs: sw.elapsedMilliseconds,
        searchItems: searchItemsCount,
        tocChapters: tocChaptersCount,
        contentChars: contentChars,
        detail:
            'Book="${detailRes.detail.title}", Ch1="${tocRes.chapters.first.title}", Text="$clipped"',
      );
    })().timeout(const Duration(seconds: 18));
  } on TimeoutException {
    cancelToken.cancel();
    sw.stop();
    return _ProbeOutcome(
      sourceName: parsed.legado.bookSourceName,
      fileLabel: fileLabel,
      baseUrl: parsed.legado.effectiveBaseUrl,
      categoryTag: categoryTag,
      queryUsed: queryUsed,
      reachedStage: reached,
      outcomeType: 'TimeoutException',
      httpStatus: lastStatus,
      totalElapsedMs: sw.elapsedMilliseconds,
      searchItems: searchItemsCount,
      tocChapters: tocChaptersCount,
      contentChars: contentChars,
      detail: 'Overall per-source 18s probe budget exceeded at stage=$reached',
    );
  } on NetworkFailure catch (e) {
    sw.stop();
    return _ProbeOutcome(
      sourceName: parsed.legado.bookSourceName,
      fileLabel: fileLabel,
      baseUrl: parsed.legado.effectiveBaseUrl,
      categoryTag: categoryTag,
      queryUsed: queryUsed,
      reachedStage: reached,
      outcomeType: e.isTimeout ? 'NetworkTimeout' : 'NetworkFailure',
      httpStatus: e.statusCode ?? lastStatus,
      totalElapsedMs: sw.elapsedMilliseconds,
      searchItems: searchItemsCount,
      tocChapters: tocChaptersCount,
      contentChars: contentChars,
      detail: e.message,
    );
  } on SourceParseFailure catch (e) {
    sw.stop();
    return _ProbeOutcome(
      sourceName: parsed.legado.bookSourceName,
      fileLabel: fileLabel,
      baseUrl: parsed.legado.effectiveBaseUrl,
      categoryTag: categoryTag,
      queryUsed: queryUsed,
      reachedStage: e.step ?? reached,
      outcomeType: 'SourceParseFailure',
      httpStatus: lastStatus,
      totalElapsedMs: sw.elapsedMilliseconds,
      searchItems: searchItemsCount,
      tocChapters: tocChaptersCount,
      contentChars: contentChars,
      detail: e.message,
    );
  } on UnsupportedLegadoRuleFailure catch (e) {
    sw.stop();
    return _ProbeOutcome(
      sourceName: parsed.legado.bookSourceName,
      fileLabel: fileLabel,
      baseUrl: parsed.legado.effectiveBaseUrl,
      categoryTag: categoryTag,
      queryUsed: queryUsed,
      reachedStage: reached,
      outcomeType: 'UnsupportedLegadoRuleFailure',
      httpStatus: lastStatus,
      totalElapsedMs: sw.elapsedMilliseconds,
      searchItems: searchItemsCount,
      tocChapters: tocChaptersCount,
      contentChars: contentChars,
      detail: '${e.feature}: ${e.message}',
    );
  } on JsExecutionFailure catch (e) {
    sw.stop();
    return _ProbeOutcome(
      sourceName: parsed.legado.bookSourceName,
      fileLabel: fileLabel,
      baseUrl: parsed.legado.effectiveBaseUrl,
      categoryTag: categoryTag,
      queryUsed: queryUsed,
      reachedStage: reached,
      outcomeType: e.isTimeout ? 'JsTimeoutFailure' : 'JsExecutionFailure',
      httpStatus: lastStatus,
      totalElapsedMs: sw.elapsedMilliseconds,
      searchItems: searchItemsCount,
      tocChapters: tocChaptersCount,
      contentChars: contentChars,
      detail: e.message,
    );
  } on AppFailure catch (e) {
    sw.stop();
    return _ProbeOutcome(
      sourceName: parsed.legado.bookSourceName,
      fileLabel: fileLabel,
      baseUrl: parsed.legado.effectiveBaseUrl,
      categoryTag: categoryTag,
      queryUsed: queryUsed,
      reachedStage: reached,
      outcomeType: e.runtimeType.toString(),
      httpStatus: lastStatus,
      totalElapsedMs: sw.elapsedMilliseconds,
      searchItems: searchItemsCount,
      tocChapters: tocChaptersCount,
      contentChars: contentChars,
      detail: e.message,
    );
  } catch (e) {
    sw.stop();
    return _ProbeOutcome(
      sourceName: parsed.legado.bookSourceName,
      fileLabel: fileLabel,
      baseUrl: parsed.legado.effectiveBaseUrl,
      categoryTag: categoryTag,
      queryUsed: queryUsed,
      reachedStage: reached,
      outcomeType: e.runtimeType.toString(),
      httpStatus: lastStatus,
      totalElapsedMs: sw.elapsedMilliseconds,
      searchItems: searchItemsCount,
      tocChapters: tocChaptersCount,
      contentChars: contentChars,
      detail: e.toString(),
    );
  }
}
