import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_compat.dart';
import 'package:pureread/engine/source_engine/parsing/legado_selector_engine.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

const String _file1Path = r'd:\QQ\Downloads\超级精品书源1031个10月10日.json';
const String _file2Path = r'd:\QQ\Downloads\精品书源合集.json';

final RegExp _aesPattern = RegExp(
  r'(?:\baes(?:Base64|Encode|Decode|Encrypt|Decrypt|CBC|ECB)?\b|CryptoJS\.AES|AES/)',
  caseSensitive: false,
);
final RegExp _desPattern = RegExp(
  r'(?:\bdes(?:ede)?(?:Base64|Encode|Decode|Encrypt|Decrypt|CBC|ECB)?\b|CryptoJS\.DES|DES/|DESede/)',
  caseSensitive: false,
);
final RegExp _digestHmacPattern = RegExp(
  r'(?:\bdigestHex\b|\bdigestBase64\b|\bsha1(?:Hex|Base64)?\b|\bsha256(?:Hex|Base64)?\b|\bsha512(?:Hex|Base64)?\b|\bHmacSHA\d*\b|\bmacHex\b|\bmacBase64\b|\bhmac\b)',
  caseSensitive: false,
);
final RegExp _cachePattern = RegExp(
  r'\bcache\.(?:get|put|delete|getInt|putInt)\b',
);
final RegExp _nonJsoupImportClassPattern = RegExp(
  r'importClass\((?!org\.jsoup\.)',
);
final RegExp _javaLangPattern = RegExp(r'\bjava\.lang\.');
final RegExp _javaWebViewPattern = RegExp(r'\bjava\.webView\b(?!UA)');

typedef _CohortAPin = ({String name, String host, String bucket});

const List<_CohortAPin> _m2BaselinePins = <_CohortAPin>[
  (name: '开心文学网', host: 'www.kxwx.org', bucket: 'GET-CSS'),
  (name: '搜小说🎃', host: 'wap.sou78.com', bucket: 'POST-GBK'),
  (name: '千凡小说', host: 'www.qfxs123.com', bucket: 'POST-UTF8'),
  (name: '猫眼看书🎃#3', host: 'api.lemiyigou.com', bucket: 'JSONPath'),
  (name: '手机小说', host: 'm.shoujix.com', bucket: 'XPath'),
  (name: '🖤㊣♛塔读文学一程1201', host: 'www.tadu.com', bucket: 'JS-Embedded'),
  (name: '英文小说（英文）', host: 'novel.tingroom.com', bucket: 'Pagination'),
  (name: '🎃76小说🎃', host: 'wap.qiliuwx.com', bucket: 'FragmentURL'),
  (name: '笔趣阁', host: 'www.biquge001.com', bucket: 'Combinator'),
  (name: '博爱书屋', host: 'www.bequgew.info', bucket: 'GET-CSS'),
  (name: '🎃御书屋🎃#4', host: 'm.wmp8.com', bucket: 'POST-GBK'),
  (name: '🎃悠悠文学🎃', host: 'm.uuwx.la', bucket: 'POST-UTF8'),
  (name: '🎃黑岩小说🎃', host: 'www.heiyan.com', bucket: 'JSONPath'),
  (name: '🎃多多书院🎃#2', host: 'www.txtduo.net', bucket: 'XPath'),
  (name: '🎃天域小说️🎃', host: 'www.tycqzw.net', bucket: 'JS-Embedded'),
  (name: '话本小说', host: 'www.ihuaben.com', bucket: 'Pagination'),
  (name: '🎃当阅读网🎃', host: 'www.dangyuedu.com', bucket: 'FragmentURL'),
  (name: '刺猬猫备用™💯', host: 'www.ciweimao.com', bucket: 'Combinator'),
  (name: 'zhsxs', host: 'www.zhswx.com', bucket: 'GET-CSS'),
  (name: '🎃笔迷读吧🎃', host: 'www.bimidu.com', bucket: 'POST-GBK'),
];

class _RecordedHttpAttempt {
  final String requestedUrl;
  final String? finalUrl;
  final int? statusCode;

  const _RecordedHttpAttempt({
    required this.requestedUrl,
    this.finalUrl,
    this.statusCode,
  });
}

class _TrackingHttpClient extends SourceHttpClient {
  final Map<CancellationToken, List<_RecordedHttpAttempt>> _attemptsByToken =
      <CancellationToken, List<_RecordedHttpAttempt>>{};

  _TrackingHttpClient({
    required super.connectTimeout,
    required super.receiveTimeout,
    required super.defaultRateLimitMs,
  });

  void beginScope(CancellationToken token) {
    _attemptsByToken[token] = <_RecordedHttpAttempt>[];
  }

  void clearScope(CancellationToken token) {
    _attemptsByToken[token]?.clear();
  }

  List<_RecordedHttpAttempt> takeScope(CancellationToken token) {
    return _attemptsByToken.remove(token) ?? const <_RecordedHttpAttempt>[];
  }

  List<_RecordedHttpAttempt> peekScope(CancellationToken token) {
    return List<_RecordedHttpAttempt>.unmodifiable(
      _attemptsByToken[token] ?? const <_RecordedHttpAttempt>[],
    );
  }

  @override
  Future<HttpFetchResult> request(
    String url, {
    String method = 'GET',
    Object? data,
    Map<String, String>? headers,
    String? charsetOverride,
    int? rateLimitMs,
    Duration? timeout,
    CancellationToken? cancelToken,
  }) async {
    final normalizedReq = SourceHttpClient.tryNormalizeHttpUri(url)?.toString() ?? url;
    try {
      final result = await super.request(
        url,
        method: method,
        data: data,
        headers: headers,
        charsetOverride: charsetOverride,
        rateLimitMs: rateLimitMs,
        timeout: timeout,
        cancelToken: cancelToken,
      );
      if (cancelToken != null) {
        _attemptsByToken[cancelToken]?.add(
          _RecordedHttpAttempt(
            requestedUrl: normalizedReq,
            finalUrl: result.finalUrl,
            statusCode: result.statusCode,
          ),
        );
      }
      return result;
    } on NetworkFailure catch (e) {
      if (cancelToken != null) {
        _attemptsByToken[cancelToken]?.add(
          _RecordedHttpAttempt(
            requestedUrl: normalizedReq,
            statusCode: e.statusCode,
          ),
        );
      }
      rethrow;
    }
  }
}

class _AnnotatedSource {
  final LegadoParsedSource parsed;
  final String fileLabel;
  final String host;
  final String? checkKeyWord;
  final bool hasPreUpdateJs;
  final Set<String> extendedFeatures;

  const _AnnotatedSource({
    required this.parsed,
    required this.fileLabel,
    required this.host,
    required this.checkKeyWord,
    required this.hasPreUpdateJs,
    required this.extendedFeatures,
  });
}

class _ProbeCandidate {
  final _AnnotatedSource source;
  final String cohort;
  final String categoryTag;

  const _ProbeCandidate({
    required this.source,
    required this.cohort,
    required this.categoryTag,
  });
}

class _ProbeOutcome {
  final String cohort;
  final String sourceName;
  final String fileLabel;
  final String baseUrl;
  final String host;
  final String categoryTag;
  final String classifierStatus;
  final List<String> extendedFeatures;
  final String queryUsed;
  final String reachedStage;
  final String outcomeType;
  final int? httpStatus;
  final int elapsedMs;
  final int searchItems;
  final int tocChapters;
  final int contentChars;
  final String detail;
  final bool redirectedOnSearch;

  const _ProbeOutcome({
    required this.cohort,
    required this.sourceName,
    required this.fileLabel,
    required this.baseUrl,
    required this.host,
    required this.categoryTag,
    required this.classifierStatus,
    required this.extendedFeatures,
    required this.queryUsed,
    required this.reachedStage,
    required this.outcomeType,
    required this.httpStatus,
    required this.elapsedMs,
    required this.searchItems,
    required this.tocChapters,
    required this.contentChars,
    required this.detail,
    required this.redirectedOnSearch,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'cohort': cohort,
    'sourceName': sourceName,
    'fileLabel': fileLabel,
    'baseUrl': baseUrl,
    'host': host,
    'categoryTag': categoryTag,
    'classifierStatus': classifierStatus,
    'extendedFeatures': extendedFeatures,
    'queryUsed': queryUsed,
    'reachedStage': reachedStage,
    'outcomeType': outcomeType,
    'httpStatus': httpStatus,
    'elapsedMs': elapsedMs,
    'searchItems': searchItems,
    'tocChapters': tocChapters,
    'contentChars': contentChars,
    'detail': detail,
    'redirectedOnSearch': redirectedOnSearch,
  };
}

class _CliArgs {
  final String? outputPath;
  final int concurrency;

  const _CliArgs({this.outputPath, this.concurrency = 4});
}

_CliArgs _parseArgs(List<String> args) {
  String? outputPath;
  var concurrency = 4;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--output' && i + 1 < args.length) {
      outputPath = args[++i];
    } else if (arg.startsWith('--output=')) {
      outputPath = arg.substring('--output='.length);
    } else if (arg == '--concurrency' && i + 1 < args.length) {
      concurrency = int.tryParse(args[++i]) ?? concurrency;
    } else if (arg.startsWith('--concurrency=')) {
      concurrency =
          int.tryParse(arg.substring('--concurrency='.length)) ?? concurrency;
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln(
        'Usage: dart run tool/probe_m3_compat.dart [--output <jsonPath>] [--concurrency <n>]',
      );
      exit(0);
    }
  }

  return _CliArgs(
    outputPath: outputPath?.trim().isEmpty ?? true ? null : outputPath!.trim(),
    concurrency: concurrency < 1 ? 1 : concurrency,
  );
}

Future<void> main(List<String> args) async {
  final cli = _parseArgs(args);

  final file1 = File(_file1Path);
  final file2 = File(_file2Path);
  if (!file1.existsSync() || !file2.existsSync()) {
    stderr.writeln(
      'Missing real corpus files:\n'
      '  - $_file1Path (exists=${file1.existsSync()})\n'
      '  - $_file2Path (exists=${file2.existsSync()})',
    );
    exitCode = 1;
    return;
  }

  final raw1 = await file1.readAsString();
  final raw2 = await file2.readAsString();

  final isoRes1 = await LegadoSourceParser.parseBatch(raw1, useIsolate: true);
  final isoRes2 = await LegadoSourceParser.parseBatch(raw2, useIsolate: true);

  final annotated1 = isoRes1.items
      .map((item) => _annotateSource(item, '1031集'))
      .toList(growable: false);
  final annotated2 = isoRes2.items
      .map((item) => _annotateSource(item, '1662合集'))
      .toList(growable: false);
  final allAnnotated = <_AnnotatedSource>[...annotated1, ...annotated2];

  final baseFeatures1 = _countBaseFeatures(isoRes1.items);
  final baseFeatures2 = _countBaseFeatures(isoRes2.items);
  final extFeatures1 = _countExtendedFeatures(annotated1);
  final extFeatures2 = _countExtendedFeatures(annotated2);
  final extFeaturesTotal = _countExtendedFeatures(allAnnotated);
  final totalTypeBreakdown = _countTypes(<LegadoParsedSource>[
    ...isoRes1.items,
    ...isoRes2.items,
  ]);

  stdout.writeln('=== M3 Real-Corpus Static Compatibility Breakdown ===');
  _printBatchSummary('File1 (1031)', file1.lengthSync(), isoRes1);
  _printBatchSummary('File2 (1662)', file2.lengthSync(), isoRes2);
  stdout.writeln(
    'Combined: total=${isoRes1.totalCount + isoRes2.totalCount}, '
    'supported=${isoRes1.supportedCount + isoRes2.supportedCount}, '
    'nonText=${isoRes1.unsupportedTypeCount + isoRes2.unsupportedTypeCount}, '
    'malformedUrl=${isoRes1.malformedBaseUrlCount + isoRes2.malformedBaseUrlCount}, '
    'webView=${isoRes1.unsupportedWebViewCount + isoRes2.unsupportedWebViewCount}, '
    'rhino=${isoRes1.unsupportedRhinoCount + isoRes2.unsupportedRhinoCount}, '
    'fragmentUrl=${isoRes1.fragmentTaggedCount + isoRes2.fragmentTaggedCount}',
  );
  stdout.writeln('Types: $totalTypeBreakdown');
  stdout.writeln('Extended Features (Combined): $extFeaturesTotal');

  final selection = _buildCohorts(allAnnotated);
  stdout.writeln(
    '\n=== Selected Probe Cohorts (concurrency=${cli.concurrency}) ===',
  );
  stdout.writeln(
    'Cohort A (m2-baseline): ${selection.cohortA.length} sources '
    '(missingPins=${selection.missingCohortAPins})',
  );
  stdout.writeln(
    'Cohort B (m3-targeted): ${selection.cohortB.length} sources '
    '(${selection.cohortBBucketCounts})',
  );

  final allCandidates = <_ProbeCandidate>[
    ...selection.cohortA,
    ...selection.cohortB,
  ];

  final httpClient = _TrackingHttpClient(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    defaultRateLimitMs: 500,
  );
  final factory = BookProviderFactory(
    httpClient: httpClient,
    defaultJsTimeout: const Duration(seconds: 4),
  );

  late final List<_ProbeOutcome> outcomes;
  try {
    outcomes = await _runConcurrentProbes(
      candidates: allCandidates,
      concurrency: cli.concurrency,
      factory: factory,
      httpClient: httpClient,
    );
  } finally {
    httpClient.close();
  }

  final cohortAOutcomes = outcomes
      .where((o) => o.cohort == 'm2-baseline')
      .toList(growable: false);
  final cohortBOutcomes = outcomes
      .where((o) => o.cohort == 'm3-targeted')
      .toList(growable: false);

  stdout.writeln('\n=== Probe Outcome Summary ===');
  stdout.writeln('Cohort A (m2-baseline): ${_summarizeOutcomes(cohortAOutcomes)}');
  stdout.writeln('Cohort B (m3-targeted): ${_summarizeOutcomes(cohortBOutcomes)}');

  final reportJson = <String, Object?>{
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'probeConfig': <String, Object?>{
      'httpConnectTimeoutSeconds': 6,
      'httpReceiveTimeoutSeconds': 6,
      'defaultRateLimitMs': 500,
      'jsTimeoutSeconds': 4,
      'perSourceCapSeconds': 18,
      'concurrency': cli.concurrency,
      'defaultQueries': const <String>['凡人修仙传', '诡秘之主'],
      'preferRuleSearchCheckKeyWord': true,
    },
    'staticSummary': <String, Object?>{
      'file1': _batchStaticJson(
        path: _file1Path,
        bytes: file1.lengthSync(),
        res: isoRes1,
        baseFeatures: baseFeatures1,
        extendedFeatures: extFeatures1,
      ),
      'file2': _batchStaticJson(
        path: _file2Path,
        bytes: file2.lengthSync(),
        res: isoRes2,
        baseFeatures: baseFeatures2,
        extendedFeatures: extFeatures2,
      ),
      'combined': <String, Object?>{
        'total': isoRes1.totalCount + isoRes2.totalCount,
        'parseErrors': isoRes1.parseErrors.length + isoRes2.parseErrors.length,
        'supported': isoRes1.supportedCount + isoRes2.supportedCount,
        'unsupportedType':
            isoRes1.unsupportedTypeCount + isoRes2.unsupportedTypeCount,
        'malformedBaseUrl':
            isoRes1.malformedBaseUrlCount + isoRes2.malformedBaseUrlCount,
        'unsupportedWebView':
            isoRes1.unsupportedWebViewCount + isoRes2.unsupportedWebViewCount,
        'unsupportedRhino':
            isoRes1.unsupportedRhinoCount + isoRes2.unsupportedRhinoCount,
        'fragmentTagged':
            isoRes1.fragmentTaggedCount + isoRes2.fragmentTaggedCount,
        'typeBreakdown': totalTypeBreakdown,
        'extendedFeatures': extFeaturesTotal,
      },
    },
    'cohortSelection': <String, Object?>{
      'cohortACount': selection.cohortA.length,
      'missingCohortAPins': selection.missingCohortAPins,
      'cohortBCount': selection.cohortB.length,
      'cohortBBuckets': selection.cohortBBucketCounts,
      'uniqueHostsProbed': allCandidates.map((c) => c.source.host).toSet().length,
    },
    'outcomeSummaries': <String, Object?>{
      'm2Baseline': _summarizeOutcomes(cohortAOutcomes),
      'm3Targeted': _summarizeOutcomes(cohortBOutcomes),
      'm3TargetedByCategory': _summarizeByCategory(cohortBOutcomes),
    },
    'outcomes': outcomes.map((o) => o.toJson()).toList(growable: false),
  };

  final encoded = const JsonEncoder.withIndent('  ').convert(reportJson);
  if (cli.outputPath != null) {
    final outFile = File(cli.outputPath!);
    outFile.parent.createSync(recursive: true);
    await outFile.writeAsString('$encoded\n');
    stdout.writeln('Wrote JSON report to ${outFile.path}');
  } else {
    stdout.writeln('\n=== PROBE_JSON_BEGIN ===');
    stdout.writeln(encoded);
    stdout.writeln('=== PROBE_JSON_END ===');
  }

  await stdout.flush();
  exit(0);
}

Map<String, Object?> _batchStaticJson({
  required String path,
  required int bytes,
  required LegadoBatchParseResult res,
  required Map<String, int> baseFeatures,
  required Map<String, int> extendedFeatures,
}) {
  return <String, Object?>{
    'path': path,
    'bytes': bytes,
    'isolateMs': res.elapsedMs,
    'total': res.totalCount,
    'parseErrors': res.parseErrors.length,
    'supported': res.supportedCount,
    'unsupportedType': res.unsupportedTypeCount,
    'malformedBaseUrl': res.malformedBaseUrlCount,
    'unsupportedWebView': res.unsupportedWebViewCount,
    'unsupportedRhino': res.unsupportedRhinoCount,
    'fragmentTagged': res.fragmentTaggedCount,
    'baseFeatures': baseFeatures,
    'extendedFeatures': extendedFeatures,
  };
}

void _printBatchSummary(
  String label,
  int bytes,
  LegadoBatchParseResult isoRes,
) {
  stdout.writeln(
    '$label: ${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB | '
    'total=${isoRes.totalCount}, parseErrors=${isoRes.parseErrors.length}, '
    'isolate=${isoRes.elapsedMs}ms | supported=${isoRes.supportedCount}, '
    'nonText=${isoRes.unsupportedTypeCount}, '
    'malformedUrl=${isoRes.malformedBaseUrlCount}, '
    'webView=${isoRes.unsupportedWebViewCount}, '
    'rhino=${isoRes.unsupportedRhinoCount}, '
    'fragmentUrl=${isoRes.fragmentTaggedCount}',
  );
}

_AnnotatedSource _annotateSource(LegadoParsedSource item, String fileLabel) {
  final s = item.legado;
  final blob = s.rawJson;
  final host =
      SourceHttpClient.tryNormalizeHttpUri(s.effectiveBaseUrl)?.host.toLowerCase() ??
      s.effectiveBaseUrl.toLowerCase();

  String? checkKeyWord;
  var hasPreUpdateJs = false;
  try {
    final decoded = jsonDecode(blob);
    if (decoded is Map) {
      final rs = decoded['ruleSearch'];
      if (rs is Map) {
        final ck = rs['checkKeyWord']?.toString().trim();
        if (ck != null && ck.isNotEmpty) {
          checkKeyWord = ck;
        }
      }
      if (checkKeyWord == null) {
        final topCk = decoded['checkKeyWord']?.toString().trim();
        if (topCk != null && topCk.isNotEmpty) {
          checkKeyWord = topCk;
        }
      }
      hasPreUpdateJs = _hasNonEmptyKey(decoded, 'preUpdateJs');
    }
  } catch (_) {}

  final ext = <String>{};
  final ruleFields = <String>[
    s.ruleSearch.bookList,
    s.ruleSearch.name,
    s.ruleSearch.author,
    s.ruleSearch.bookUrl,
    s.ruleSearch.coverUrl,
    s.ruleSearch.intro,
    s.ruleSearch.lastChapter,
    s.ruleSearch.kind,
    s.ruleSearch.wordCount,
    s.ruleBookInfo.init,
    s.ruleBookInfo.name,
    s.ruleBookInfo.author,
    s.ruleBookInfo.intro,
    s.ruleBookInfo.coverUrl,
    s.ruleBookInfo.tocUrl,
    s.ruleBookInfo.lastChapter,
    s.ruleBookInfo.kind,
    s.ruleBookInfo.wordCount,
    s.ruleToc.chapterList,
    s.ruleToc.chapterName,
    s.ruleToc.chapterUrl,
    s.ruleToc.nextTocUrl,
    s.ruleContent.content,
    s.ruleContent.nextContentUrl,
  ];

  final usesRegexRule = ruleFields.any(_containsRegexListSyntax);
  if (usesRegexRule) ext.add('regexListRule');

  final hasCreateSymmetricCrypto = blob.contains('createSymmetricCrypto');
  final hasAes = _aesPattern.hasMatch(blob);
  final hasDes = _desPattern.hasMatch(blob);
  if (hasCreateSymmetricCrypto) ext.add('createSymmetricCrypto');
  if (hasAes) ext.add('aes');
  if (hasDes) ext.add('des');
  if (hasCreateSymmetricCrypto || hasAes || hasDes) ext.add('cryptoAny');

  final hasOrgJsoup = blob.contains('org.jsoup.');
  final hasPackages = blob.contains('Packages.');
  final hasJavaLang = _javaLangPattern.hasMatch(blob);
  final hasOtherImportClass = _nonJsoupImportClassPattern.hasMatch(blob);
  if (hasOrgJsoup) ext.add('orgJsoup');
  if (hasOrgJsoup && !hasPackages && !hasJavaLang && !hasOtherImportClass) {
    ext.add('orgJsoupOnly');
  }
  if (hasPackages) ext.add('rhinoPackages');
  if (hasJavaLang) ext.add('rhinoJavaLang');
  if (blob.contains('importClass(')) ext.add('rhinoImportClass');
  if (item.compatibility == LegadoCompatibilityStatus.unsupportedRhino) {
    ext.add('classifierRejectedRhino');
  }

  if (blob.contains('java.ajaxAll') || blob.contains('ajaxAll')) {
    ext.add('javaAjaxAll');
  }
  if (blob.contains('digestHex')) ext.add('javaDigestHex');
  if (_digestHmacPattern.hasMatch(blob)) ext.add('digestShaHmac');
  if (blob.contains('book.getVariable') || blob.contains('book.putVariable')) {
    ext.add('bookVariable');
  }
  if (_cachePattern.hasMatch(blob)) ext.add('cacheGetPut');
  if (checkKeyWord != null) ext.add('checkKeyWord');
  if (hasPreUpdateJs) ext.add('preUpdateJs');
  if ((s.loginUrl ?? '').isNotEmpty) ext.add('loginUrl');
  if ((s.jsLib ?? '').isNotEmpty) ext.add('jsLib');
  if (blob.contains('timeFormatUTC')) ext.add('javaTimeFormatUTC');
  if (blob.contains('java.post')) ext.add('javaPost');

  final hasWebView =
      item.compatibility == LegadoCompatibilityStatus.unsupportedWebView ||
      s.webView ||
      s.ruleSearch.webView ||
      s.ruleBookInfo.webView ||
      s.ruleToc.webView ||
      s.ruleContent.webView ||
      blob.contains('startBrowserAwait') ||
      _javaWebViewPattern.hasMatch(blob);
  if (hasWebView) ext.add('webView');

  return _AnnotatedSource(
    parsed: item,
    fileLabel: fileLabel,
    host: host,
    checkKeyWord: checkKeyWord,
    hasPreUpdateJs: hasPreUpdateJs,
    extendedFeatures: Set<String>.unmodifiable(ext),
  );
}

bool _containsRegexListSyntax(String rule) {
  final trimmed = rule.trim();
  if (trimmed.isEmpty) return false;
  if (LegadoSelectorEngine.isRegexListRule(trimmed)) return true;
  if (trimmed.toLowerCase().contains('@regex:')) return true;
  for (final sep in const <String>['\n', '&&', '||', '%%']) {
    if (!trimmed.contains(sep)) continue;
    for (final part in trimmed.split(sep)) {
      if (LegadoSelectorEngine.isRegexListRule(part)) return true;
    }
  }
  return false;
}

bool _hasNonEmptyKey(Object? node, String key) {
  if (node is Map) {
    final val = node[key];
    if (val != null && val.toString().trim().isNotEmpty) {
      return true;
    }
    for (final v in node.values) {
      if (_hasNonEmptyKey(v, key)) return true;
    }
  } else if (node is List) {
    for (final v in node) {
      if (_hasNonEmptyKey(v, key)) return true;
    }
  }
  return false;
}

Map<String, int> _countBaseFeatures(List<LegadoParsedSource> items) {
  final counts = <String, int>{};
  for (final item in items) {
    for (final f in item.detectedFeatures) {
      counts[f] = (counts[f] ?? 0) + 1;
    }
  }
  return counts;
}

Map<String, int> _countExtendedFeatures(List<_AnnotatedSource> items) {
  final counts = <String, int>{};
  for (final item in items) {
    for (final f in item.extendedFeatures) {
      counts[f] = (counts[f] ?? 0) + 1;
    }
  }
  final sortedKeys = counts.keys.toList()..sort();
  return <String, int>{for (final k in sortedKeys) k: counts[k]!};
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

bool _isProbeShapeEligible(_AnnotatedSource a) {
  final s = a.parsed.legado;
  if (s.bookSourceType != 0) return false;
  if (s.normalizedBaseUrl.isEmpty) return false;
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

({
  List<_ProbeCandidate> cohortA,
  List<_ProbeCandidate> cohortB,
  List<String> missingCohortAPins,
  Map<String, int> cohortBBucketCounts,
}) _buildCohorts(List<_AnnotatedSource> all) {
  final seenHosts = <String>{};
  final cohortA = <_ProbeCandidate>[];
  final missingPins = <String>[];

  // Cohort A: exact 20 sources from docs/m2-source-compat-report.md Section 3.
  for (final pin in _m2BaselinePins) {
    final matches = all.where((a) {
      return _isProbeShapeEligible(a) &&
          a.parsed.legado.bookSourceName == pin.name &&
          a.host == pin.host;
    }).toList();

    if (matches.isEmpty) {
      missingPins.add('${pin.name} (${pin.host})');
      continue;
    }
    matches.sort(
      (a, b) => b.parsed.legado.weight.compareTo(a.parsed.legado.weight),
    );
    final chosen = matches.first;
    seenHosts.add(chosen.host);
    cohortA.add(
      _ProbeCandidate(
        source: chosen,
        cohort: 'm2-baseline',
        categoryTag: pin.bucket,
      ),
    );
  }

  // Cohort B: up to 28 distinct-host text sources across 4 M3 target buckets.
  final eligibleB = all.where((a) {
    if (!_isProbeShapeEligible(a)) return false;
    if (seenHosts.contains(a.host)) return false;
    if (a.extendedFeatures.contains('webView')) return false;
    if (a.extendedFeatures.contains('rhinoPackages') ||
        a.extendedFeatures.contains('rhinoJavaLang') ||
        _nonJsoupImportClassPattern.hasMatch(a.parsed.legado.rawJson)) {
      return false;
    }
    return true;
  }).toList();

  eligibleB.sort(
    (a, b) => b.parsed.legado.weight.compareTo(a.parsed.legado.weight),
  );

  final cohortB = <_ProbeCandidate>[];
  final bucketCounts = <String, int>{
    'm3-regex': 0,
    'm3-crypto': 0,
    'm3-jsoup': 0,
    'm3-js-api': 0,
  };

  void addToCohortB(_AnnotatedSource item, String bucketTag) {
    seenHosts.add(item.host);
    cohortB.add(
      _ProbeCandidate(
        source: item,
        cohort: 'm3-targeted',
        categoryTag: bucketTag,
      ),
    );
  }

  // 1) :regex / @regex: (up to 7, headless-supported)
  for (final a in eligibleB) {
    if (bucketCounts['m3-regex']! >= 7) break;
    if (seenHosts.contains(a.host)) continue;
    if (!a.parsed.isSupported) continue;
    if (!a.extendedFeatures.contains('regexListRule')) continue;
    bucketCounts['m3-regex'] = bucketCounts['m3-regex']! + 1;
    addToCohortB(a, 'm3-regex');
  }

  // 2) aes / des / createSymmetricCrypto (up to 7, round-robin sub-buckets)
  final cryptoPools = <List<_AnnotatedSource>>[
    eligibleB
        .where(
          (a) =>
              a.parsed.isSupported &&
              a.extendedFeatures.contains('createSymmetricCrypto'),
        )
        .toList(),
    eligibleB
        .where(
          (a) => a.parsed.isSupported && a.extendedFeatures.contains('aes'),
        )
        .toList(),
    eligibleB
        .where(
          (a) => a.parsed.isSupported && a.extendedFeatures.contains('des'),
        )
        .toList(),
  ];
  _pickRoundRobin(
    pools: cryptoPools,
    maxCount: 7,
    seenHosts: seenHosts,
    onPick: (a) {
      bucketCounts['m3-crypto'] = bucketCounts['m3-crypto']! + 1;
      addToCohortB(a, 'm3-crypto');
    },
  );

  // 3) org.jsoup-only (up to 7)
  for (final a in eligibleB) {
    if (bucketCounts['m3-jsoup']! >= 7) break;
    if (seenHosts.contains(a.host)) continue;
    if (!a.extendedFeatures.contains('orgJsoupOnly')) continue;
    bucketCounts['m3-jsoup'] = bucketCounts['m3-jsoup']! + 1;
    addToCohortB(a, 'm3-jsoup');
  }

  // 4) java.ajaxAll / digestHex / sha / hmac / book.getVariable / timeFormatUTC / java.post (up to 7)
  final jsApiPools = <List<_AnnotatedSource>>[
    eligibleB
        .where(
          (a) =>
              a.parsed.isSupported &&
              a.extendedFeatures.contains('javaAjaxAll'),
        )
        .toList(),
    eligibleB
        .where(
          (a) =>
              a.parsed.isSupported &&
              a.extendedFeatures.contains('digestShaHmac'),
        )
        .toList(),
    eligibleB
        .where(
          (a) =>
              a.parsed.isSupported &&
              a.extendedFeatures.contains('bookVariable'),
        )
        .toList(),
    eligibleB
        .where(
          (a) =>
              a.parsed.isSupported &&
              a.extendedFeatures.contains('javaTimeFormatUTC'),
        )
        .toList(),
    eligibleB
        .where(
          (a) =>
              a.parsed.isSupported && a.extendedFeatures.contains('javaPost'),
        )
        .toList(),
  ];
  _pickRoundRobin(
    pools: jsApiPools,
    maxCount: 7,
    seenHosts: seenHosts,
    onPick: (a) {
      bucketCounts['m3-js-api'] = bucketCounts['m3-js-api']! + 1;
      addToCohortB(a, 'm3-js-api');
    },
  );

  return (
    cohortA: cohortA,
    cohortB: cohortB,
    missingCohortAPins: missingPins,
    cohortBBucketCounts: bucketCounts,
  );
}

void _pickRoundRobin({
  required List<List<_AnnotatedSource>> pools,
  required int maxCount,
  required Set<String> seenHosts,
  required void Function(_AnnotatedSource) onPick,
}) {
  var picked = 0;
  var progressed = true;
  while (picked < maxCount && progressed) {
    progressed = false;
    for (final pool in pools) {
      if (picked >= maxCount) break;
      for (final a in pool) {
        if (seenHosts.contains(a.host)) continue;
        onPick(a);
        picked++;
        progressed = true;
        break;
      }
    }
  }
}

Future<List<_ProbeOutcome>> _runConcurrentProbes({
  required List<_ProbeCandidate> candidates,
  required int concurrency,
  required BookProviderFactory factory,
  required _TrackingHttpClient httpClient,
}) async {
  final results = List<_ProbeOutcome?>.filled(candidates.length, null);
  var nextIndex = 0;
  final activeHosts = <String>{};

  Future<void> worker() async {
    while (true) {
      int? pickedIdx;
      for (var i = nextIndex; i < candidates.length; i++) {
        if (results[i] != null) continue;
        final host = candidates[i].source.host;
        if (!activeHosts.contains(host)) {
          pickedIdx = i;
          activeHosts.add(host);
          if (i == nextIndex) {
            while (nextIndex < candidates.length &&
                (results[nextIndex] != null ||
                    activeHosts.contains(candidates[nextIndex].source.host))) {
              nextIndex++;
            }
          }
          break;
        }
      }
      if (pickedIdx == null) {
        final hasUnstarted = results.any((r) => r == null);
        if (!hasUnstarted) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }

      final candidate = candidates[pickedIdx];
      try {
        stdout.writeln(
          '[${pickedIdx + 1}/${candidates.length}] [${candidate.cohort}:${candidate.categoryTag}] '
          '${candidate.source.parsed.legado.bookSourceName} -> '
          '${candidate.source.parsed.legado.effectiveBaseUrl}',
        );
        final outcome = await _probeSingleSource(
          factory: factory,
          httpClient: httpClient,
          candidate: candidate,
        );
        results[pickedIdx] = outcome;
        stdout.writeln(
          '   -> [${candidate.cohort}:${candidate.categoryTag}] '
          '${outcome.sourceName}: stage=${outcome.reachedStage}, '
          'outcome=${outcome.outcomeType}, status=${outcome.httpStatus}, '
          'redir=${outcome.redirectedOnSearch}, ms=${outcome.elapsedMs}, '
          'items=${outcome.searchItems}, ch=${outcome.tocChapters}, '
          'chars=${outcome.contentChars} | ${outcome.detail}',
        );
      } finally {
        activeHosts.remove(candidate.source.host);
        if (pickedIdx < nextIndex) {
          nextIndex = pickedIdx + 1;
        }
      }
    }
  }

  final workerCount =
      concurrency < candidates.length ? concurrency : candidates.length;
  await Future.wait(
    List<Future<void>>.generate(workerCount, (_) => worker()),
  );

  return results.whereType<_ProbeOutcome>().toList(growable: false);
}

Future<_ProbeOutcome> _probeSingleSource({
  required BookProviderFactory factory,
  required _TrackingHttpClient httpClient,
  required _ProbeCandidate candidate,
}) async {
  final parsed = candidate.source.parsed;
  final sw = Stopwatch()..start();
  final provider = factory.createProvider(parsed.domainSource);

  final queries = <String>[
    if (candidate.source.checkKeyWord != null) candidate.source.checkKeyWord!,
    if (candidate.source.checkKeyWord != '凡人修仙传') '凡人修仙传',
    if (candidate.source.checkKeyWord != '诡秘之主') '诡秘之主',
  ];

  var reached = 'init';
  int? lastStatus;
  var searchItemsCount = 0;
  var tocChaptersCount = 0;
  var contentChars = 0;
  var queryUsed = queries.first;
  var redirectedOnSearch = false;
  final cancelToken = CancellationToken();
  httpClient.beginScope(cancelToken);

  final classifierStatus = parsed.compatibility.name;
  final extList = candidate.source.extendedFeatures.toList()..sort();

  _ProbeOutcome buildOutcome({
    required String reachedStage,
    required String outcomeType,
    required int? httpStatus,
    required String detail,
    int? items,
    int? chapters,
    int? chars,
  }) {
    final fullDetail =
        (!parsed.isSupported && parsed.unsupportedReasons.isNotEmpty)
        ? '$detail [classifier=$classifierStatus: ${parsed.unsupportedReasons.join("; ")}]'
        : detail;
    return _ProbeOutcome(
      cohort: candidate.cohort,
      sourceName: parsed.legado.bookSourceName,
      fileLabel: candidate.source.fileLabel,
      baseUrl: parsed.legado.effectiveBaseUrl,
      host: candidate.source.host,
      categoryTag: candidate.categoryTag,
      classifierStatus: classifierStatus,
      extendedFeatures: extList,
      queryUsed: queryUsed,
      reachedStage: reachedStage,
      outcomeType: outcomeType,
      httpStatus: httpStatus,
      elapsedMs: sw.elapsedMilliseconds,
      searchItems: items ?? searchItemsCount,
      tocChapters: chapters ?? tocChaptersCount,
      contentChars: chars ?? contentChars,
      detail: fullDetail,
      redirectedOnSearch: redirectedOnSearch,
    );
  }

  void updateSearchTrackingFromScope() {
    final attempts = httpClient.peekScope(cancelToken);
    if (attempts.isEmpty) return;
    final last = attempts.last;
    lastStatus = last.statusCode ?? lastStatus;
    if (last.finalUrl != null) {
      final reqUri = Uri.tryParse(last.requestedUrl);
      final finalUri = Uri.tryParse(last.finalUrl!);
      if (reqUri != null && finalUri != null) {
        redirectedOnSearch =
            reqUri.host.toLowerCase() != finalUri.host.toLowerCase() ||
            reqUri.path != finalUri.path;
      }
    }
  }

  try {
    return await (() async {
      var items = const <BookSearchItem>[];
      SourceParseFailure? lastSearchParseError;

      for (final q in queries) {
        queryUsed = q;
        httpClient.clearScope(cancelToken);
        try {
          final searchRes = await provider.search(
            q,
            page: 1,
            cancelToken: cancelToken,
          );
          updateSearchTrackingFromScope();
          lastStatus = searchRes.trace.httpStatus ?? lastStatus;
          if (searchRes.items.isNotEmpty) {
            items = searchRes.items;
            break;
          }
        } on SourceParseFailure catch (e) {
          updateSearchTrackingFromScope();
          lastSearchParseError = e;
        }
      }

      if (items.isEmpty) {
        if (lastSearchParseError != null) throw lastSearchParseError;
        sw.stop();
        return buildOutcome(
          reachedStage: 'search',
          outcomeType: 'EmptySearch',
          httpStatus: lastStatus,
          detail: 'Search returned 0 books for queries $queries',
          items: 0,
          chapters: 0,
          chars: 0,
        );
      }

      reached = 'search';
      searchItemsCount = items.length;
      final pickedBook = items.first;

      httpClient.clearScope(cancelToken);
      final detailRes = await provider.getBookDetail(
        pickedBook.bookUrl,
        cancelToken: cancelToken,
      );
      reached = 'detail';
      lastStatus = detailRes.trace.httpStatus ?? lastStatus;

      httpClient.clearScope(cancelToken);
      final tocRes = await provider.getToc(
        detailRes.detail.tocUrl,
        cancelToken: cancelToken,
      );
      reached = 'toc';
      lastStatus = tocRes.trace.httpStatus ?? lastStatus;
      tocChaptersCount = tocRes.chapters.length;
      if (tocRes.chapters.isEmpty) {
        sw.stop();
        return buildOutcome(
          reachedStage: 'toc',
          outcomeType: 'EmptyToc',
          httpStatus: lastStatus,
          detail: 'Book "${detailRes.detail.title}" had 0 TOC chapters',
          chapters: 0,
          chars: 0,
        );
      }

      httpClient.clearScope(cancelToken);
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

      return buildOutcome(
        reachedStage: 'content',
        outcomeType: 'Success',
        httpStatus: lastStatus,
        detail:
            'Book="${detailRes.detail.title}", Ch1="${tocRes.chapters.first.title}", Text="$clipped"',
      );
    })().timeout(const Duration(seconds: 18));
  } on TimeoutException {
    cancelToken.cancel();
    sw.stop();
    return buildOutcome(
      reachedStage: reached,
      outcomeType: 'TimeoutException',
      httpStatus: lastStatus,
      detail: 'Overall per-source 18s probe budget exceeded at stage=$reached',
    );
  } on NetworkFailure catch (e) {
    sw.stop();
    return buildOutcome(
      reachedStage: reached,
      outcomeType: e.isTimeout ? 'NetworkTimeout' : 'NetworkFailure',
      httpStatus: e.statusCode ?? lastStatus,
      detail: e.message,
    );
  } on SourceParseFailure catch (e) {
    sw.stop();
    return buildOutcome(
      reachedStage: e.step ?? reached,
      outcomeType: 'SourceParseFailure',
      httpStatus: lastStatus,
      detail: e.message,
    );
  } on UnsupportedLegadoRuleFailure catch (e) {
    sw.stop();
    return buildOutcome(
      reachedStage: reached,
      outcomeType: 'UnsupportedLegadoRuleFailure',
      httpStatus: lastStatus,
      detail: '${e.feature}: ${e.message}',
    );
  } on JsExecutionFailure catch (e) {
    sw.stop();
    return buildOutcome(
      reachedStage: reached,
      outcomeType: e.isTimeout ? 'JsTimeoutFailure' : 'JsExecutionFailure',
      httpStatus: lastStatus,
      detail: e.message,
    );
  } on AppFailure catch (e) {
    sw.stop();
    return buildOutcome(
      reachedStage: reached,
      outcomeType: e.runtimeType.toString(),
      httpStatus: lastStatus,
      detail: e.message,
    );
  } catch (e) {
    sw.stop();
    return buildOutcome(
      reachedStage: reached,
      outcomeType: e.runtimeType.toString(),
      httpStatus: lastStatus,
      detail: e.toString(),
    );
  } finally {
    httpClient.takeScope(cancelToken);
  }
}

Map<String, Object?> _summarizeOutcomes(List<_ProbeOutcome> list) {
  final byOutcome = <String, int>{};
  final byStage = <String, int>{};
  var redirectedCount = 0;
  for (final o in list) {
    byOutcome[o.outcomeType] = (byOutcome[o.outcomeType] ?? 0) + 1;
    byStage[o.reachedStage] = (byStage[o.reachedStage] ?? 0) + 1;
    if (o.redirectedOnSearch) redirectedCount++;
  }
  return <String, Object?>{
    'total': list.length,
    'success': byOutcome['Success'] ?? 0,
    'redirectedOnSearch': redirectedCount,
    'byOutcome': byOutcome,
    'byStage': byStage,
  };
}

Map<String, Object?> _summarizeByCategory(List<_ProbeOutcome> list) {
  final grouped = <String, List<_ProbeOutcome>>{};
  for (final o in list) {
    grouped.putIfAbsent(o.categoryTag, () => <_ProbeOutcome>[]).add(o);
  }
  return <String, Object?>{
    for (final entry in grouped.entries)
      entry.key: _summarizeOutcomes(entry.value),
  };
}
