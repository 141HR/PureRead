import '../../../domain/domain.dart';
import '../../../infrastructure/network/source_http_client.dart';
import 'legado_rule_evaluator.dart';
import 'legado_source.dart';

/// Progressive Legado v3 JSON book source driver (`BookProvider` implementation).
class LegadoCompatProvider implements BookProvider {
  @override
  final String providerId;
  final LegadoBookSource source;
  final SourceHttpClient httpClient;
  final LegadoRuleEvaluator evaluator;
  final int? rateLimitMsOverride;
  final int maxTocPages;
  final int maxContentPages;
  final Map<String, LegadoCacheEntry> _cacheEntries =
      <String, LegadoCacheEntry>{};
  final Map<String, String> _javaVars = <String, String>{};
  final Map<String, String> _bookVars = <String, String>{};
  String _sourceVariable = '';
  String _bookVariable = '';
  String _bookCustomVariable = '';
  String _bookName = '';
  String _bookUrl = '';
  String _tocUrl = '';

  LegadoEvalSession _createSession({
    String? bookUrl,
    String? tocUrl,
    String chapterTitle = '',
    String chapterUrl = '',
    int chapterIndex = 0,
  }) {
    return LegadoEvalSession(
      sourceVariable: _sourceVariable,
      bookName: _bookName,
      bookUrl: bookUrl ?? _bookUrl,
      tocUrl: tocUrl ?? _tocUrl,
      bookVariable: _bookVariable,
      bookCustomVariable: _bookCustomVariable,
      chapterTitle: chapterTitle,
      chapterUrl: chapterUrl,
      chapterIndex: chapterIndex,
      javaVars: _javaVars,
      bookVars: _bookVars,
      cacheEntries: _cacheEntries,
    );
  }

  void _syncSession(LegadoEvalSession session) {
    _sourceVariable = session.sourceVariable;
    _bookVariable = session.bookVariable;
    _bookCustomVariable = session.bookCustomVariable;
    if (session.bookName.isNotEmpty) _bookName = session.bookName;
    if (session.bookUrl.isNotEmpty) _bookUrl = session.bookUrl;
    if (session.tocUrl.isNotEmpty) _tocUrl = session.tocUrl;
  }

  int get effectiveRateLimitMs => rateLimitMsOverride ?? source.rateLimitMs;

  @override
  ProviderType get type => ProviderType.legado;

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
    isLocal: false,
    supportsSearch: (source.searchUrl ?? '').trim().isNotEmpty,
    supportsUpdateCheck: true,
    supportsChangeSource: true,
  );

  LegadoCompatProvider({
    required this.providerId,
    required this.source,
    required this.httpClient,
    this.rateLimitMsOverride,
    Duration jsTimeout = const Duration(seconds: 5),
    this.maxTocPages = 20,
    this.maxContentPages = 25,
  }) : evaluator = LegadoRuleEvaluator(
         sourceId: providerId,
         source: source,
         httpClient: httpClient,
         jsTimeout: jsTimeout,
       );

  void _ensureSupported({bool stepWebView = false, String? stepName}) {
    if (source.bookSourceType != 0) {
      throw UnsupportedLegadoRuleFailure(
        message:
            'Legado source "${source.bookSourceName}" has bookSourceType=${source.bookSourceType}; only text sources (0) are supported.',
        feature: 'bookSourceType_${source.bookSourceType}',
        sourceId: providerId,
      );
    }
    if (source.webView || stepWebView) {
      throw UnsupportedLegadoRuleFailure(
        message:
            'Legado source "${source.bookSourceName}" requires webView: true${stepName != null ? " ($stepName)" : ""}, which is unsupported in pure headless mode.',
        feature: 'webView',
        sourceId: providerId,
      );
    }
  }

  @override
  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final sw = Stopwatch()..start();
    _ensureSupported(stepName: 'search');
    evaluator.guardUnsupportedRules(<String?>[
      source.searchUrl,
      source.rawHeader,
      source.jsLib,
      source.ruleSearch.bookList,
      source.ruleSearch.name,
      source.ruleSearch.bookUrl,
      source.ruleSearch.author,
      source.ruleSearch.coverUrl,
      source.ruleSearch.intro,
      source.ruleSearch.lastChapter,
      source.ruleSearch.kind,
    ]);

    final rawSearchUrl = source.searchUrl?.trim() ?? '';
    if (rawSearchUrl.isEmpty) {
      throw UnsupportedLegadoRuleFailure(
        message: 'Legado source has no searchUrl configured',
        feature: 'searchUrl',
        sourceId: providerId,
      );
    }
    if (source.normalizedBaseUrl.isEmpty) {
      throw UnsupportedLegadoRuleFailure(
        message:
            'Legado source has non-HTTP or malformed bookSourceUrl: "${source.bookSourceUrl}"',
        feature: 'malformed_base_url',
        sourceId: providerId,
      );
    }

    _javaVars.clear();
    _bookVars.clear();
    _bookVariable = '';
    _bookCustomVariable = '';
    _bookName = '';
    _bookUrl = '';
    _tocUrl = '';
    final session = _createSession();
    try {
      final baseHeaders = await evaluator.evaluateHeaders(
      baseUrl: source.effectiveBaseUrl,
      session: session,
      cancelToken: cancelToken,
    );

    final req = await evaluator.parseUrlSpecAsync(
      rawSearchUrl,
      baseUrl: source.effectiveBaseUrl,
      defaultHeaders: baseHeaders,
      defaultCharset: source.charset,
      keyword: keyword,
      page: page,
      session: session,
      cancelToken: cancelToken,
    );
    _ensureSupported(stepWebView: req.webView, stepName: 'searchUrl');

    final resp = await httpClient.request(
      req.url,
      method: req.method,
      data: req.body,
      headers: req.headers,
      charsetOverride: req.charset,
      rateLimitMs: effectiveRateLimitMs,
      cancelToken: cancelToken,
    );

    final blocksRes = await evaluator.evaluateListBlocks(
      resp.body,
      source.ruleSearch.bookList,
      baseUrl: resp.finalUrl,
      session: session,
      cancelToken: cancelToken,
    );
    if (blocksRes.items.isEmpty) {
      final redirected =
          _canonicalUrlKey(resp.finalUrl) != _canonicalUrlKey(req.url);
      if (redirected || source.ruleBookInfo.name.trim().isNotEmpty) {
        final fallbackItem = await _tryExtractRedirectDetailSearchItem(
          resp: resp,
          keyword: keyword,
          redirected: redirected,
          session: session,
          cancelToken: cancelToken,
        );
        if (fallbackItem != null) {
          sw.stop();
          return (
            items: <BookSearchItem>[fallbackItem],
            trace: SourceDebugTrace(
              step: 'search',
              elapsedMs: sw.elapsedMilliseconds,
              httpStatus: resp.statusCode,
              requestUrl: resp.finalUrl,
              matchedPreview:
                  '1 items via redirect/detail fallback (charset=${resp.detectedCharset}, first=${fallbackItem.title})',
              logs: List<String>.unmodifiable(session.logs),
            ),
          );
        }
      }
      throw SourceParseFailure(
        message:
            'Legado ruleSearch.bookList matched 0 elements (${source.ruleSearch.bookList})',
        sourceId: providerId,
        step: 'search',
        rule: source.ruleSearch.bookList,
      );
    }

    final blocks = blocksRes.reversed
        ? blocksRes.items.reversed.toList(growable: false)
        : blocksRes.items;

    final items = <BookSearchItem>[];
    for (final block in blocks) {
      cancelToken?.throwIfCancelled();
      final title = await evaluator.evaluateString(
        block,
        source.ruleSearch.name,
        baseUrl: resp.finalUrl,
        keyword: keyword,
        page: page,
        session: session,
        cancelToken: cancelToken,
      );
      final rawBookUrl = source.ruleSearch.bookUrl.trim().isEmpty
          ? resp.finalUrl
          : await evaluator.evaluateString(
              block,
              source.ruleSearch.bookUrl,
              baseUrl: resp.finalUrl,
              keyword: keyword,
              page: page,
              session: session,
              cancelToken: cancelToken,
            );
      if (title.isEmpty || rawBookUrl.isEmpty) {
        continue;
      }

      final author = source.ruleSearch.author.isEmpty
          ? ''
          : await evaluator.evaluateString(
              block,
              source.ruleSearch.author,
              baseUrl: resp.finalUrl,
              keyword: keyword,
              page: page,
              session: session,
              cancelToken: cancelToken,
            );
      final coverUrl = source.ruleSearch.coverUrl.isEmpty
          ? null
          : _resolveOptional(
              await evaluator.evaluateString(
                block,
                source.ruleSearch.coverUrl,
                baseUrl: resp.finalUrl,
                keyword: keyword,
                page: page,
                session: session,
                cancelToken: cancelToken,
              ),
              resp.finalUrl,
            );
      final intro = source.ruleSearch.intro.isEmpty
          ? ''
          : await evaluator.evaluateString(
              block,
              source.ruleSearch.intro,
              baseUrl: resp.finalUrl,
              keyword: keyword,
              page: page,
              session: session,
              cancelToken: cancelToken,
            );
      final lastChapter = source.ruleSearch.lastChapter.isEmpty
          ? ''
          : await evaluator.evaluateString(
              block,
              source.ruleSearch.lastChapter,
              baseUrl: resp.finalUrl,
              keyword: keyword,
              page: page,
              session: session,
              cancelToken: cancelToken,
            );
      final kind = source.ruleSearch.kind.isEmpty
          ? null
          : _nullableTrimmed(
              await evaluator.evaluateString(
                block,
                source.ruleSearch.kind,
                baseUrl: resp.finalUrl,
                keyword: keyword,
                page: page,
                session: session,
                cancelToken: cancelToken,
              ),
            );

      items.add(
        BookSearchItem(
          sourceId: providerId,
          providerType: type,
          bookUrl: LegadoRuleEvaluator.resolveUrlSpec(
            rawBookUrl,
            resp.finalUrl,
          ),
          title: title,
          author: author,
          coverUrl: coverUrl,
          intro: intro,
          latestChapterTitle: lastChapter,
          kind: kind,
        ),
      );
    }

    sw.stop();
    return (
      items: items,
      trace: SourceDebugTrace(
        step: 'search',
        elapsedMs: sw.elapsedMilliseconds,
        httpStatus: resp.statusCode,
        requestUrl: resp.finalUrl,
        matchedPreview: items.isEmpty
            ? '0 items'
            : '${items.length} items (charset=${resp.detectedCharset}, first=${items.first.title})',
        logs: List<String>.unmodifiable(session.logs),
      ),
    );
    } finally {
      _syncSession(session);
    }
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final sw = Stopwatch()..start();
    _ensureSupported(
      stepWebView: source.ruleBookInfo.webView,
      stepName: 'ruleBookInfo',
    );
    evaluator.guardUnsupportedRules(<String?>[
      bookUrl,
      source.rawHeader,
      source.jsLib,
      source.ruleBookInfo.init,
      source.ruleBookInfo.name,
      source.ruleBookInfo.author,
      source.ruleBookInfo.intro,
      source.ruleBookInfo.coverUrl,
      source.ruleBookInfo.tocUrl,
      source.ruleBookInfo.lastChapter,
      source.ruleBookInfo.kind,
      source.ruleBookInfo.wordCount,
    ]);

    final session = _createSession(bookUrl: bookUrl);
    try {
      final baseHeaders = await evaluator.evaluateHeaders(
      baseUrl: source.effectiveBaseUrl,
      session: session,
      cancelToken: cancelToken,
    );

    final req = await evaluator.parseUrlSpecAsync(
      bookUrl,
      baseUrl: source.effectiveBaseUrl,
      defaultHeaders: baseHeaders,
      defaultCharset: source.charset,
      session: session,
      cancelToken: cancelToken,
    );
    _ensureSupported(stepWebView: req.webView, stepName: 'bookUrl');

    final resp = await httpClient.request(
      req.url,
      method: req.method,
      data: req.body,
      headers: req.headers,
      charsetOverride: req.charset,
      rateLimitMs: effectiveRateLimitMs,
      cancelToken: cancelToken,
    );

    var infoInput = resp.body;
    if (source.ruleBookInfo.init.trim().isNotEmpty) {
      final initVal = await evaluator.evaluateString(
        infoInput,
        source.ruleBookInfo.init,
        baseUrl: resp.finalUrl,
        session: session,
        cancelToken: cancelToken,
      );
      if (initVal.isNotEmpty) {
        infoInput = initVal;
      }
    }

    var title = source.ruleBookInfo.name.trim().isEmpty
        ? ''
        : await evaluator.evaluateString(
            infoInput,
            source.ruleBookInfo.name,
            baseUrl: resp.finalUrl,
            session: session,
            cancelToken: cancelToken,
          );
    if (title.isEmpty && source.ruleBookInfo.name.trim().isNotEmpty) {
      throw SourceParseFailure(
        message: 'Legado ruleBookInfo.name returned empty string',
        sourceId: providerId,
        step: 'detail',
        rule: source.ruleBookInfo.name,
      );
    }
    if (title.isEmpty) {
      title = await evaluator.evaluateString(
        resp.body,
        'title@text',
        baseUrl: resp.finalUrl,
        session: session,
        cancelToken: cancelToken,
      );
      if (title.isEmpty) title = '未命名书籍';
    }
    session.bookName = title;

    final author = source.ruleBookInfo.author.isEmpty
        ? ''
        : await evaluator.evaluateString(
            infoInput,
            source.ruleBookInfo.author,
            baseUrl: resp.finalUrl,
            session: session,
            cancelToken: cancelToken,
          );
    final intro = source.ruleBookInfo.intro.isEmpty
        ? ''
        : await evaluator.evaluateString(
            infoInput,
            source.ruleBookInfo.intro,
            baseUrl: resp.finalUrl,
            session: session,
            cancelToken: cancelToken,
          );
    final coverUrl = source.ruleBookInfo.coverUrl.isEmpty
        ? null
        : _resolveOptional(
            await evaluator.evaluateString(
              infoInput,
              source.ruleBookInfo.coverUrl,
              baseUrl: resp.finalUrl,
              session: session,
              cancelToken: cancelToken,
            ),
            resp.finalUrl,
          );
    final lastChapter = source.ruleBookInfo.lastChapter.isEmpty
        ? ''
        : await evaluator.evaluateString(
            infoInput,
            source.ruleBookInfo.lastChapter,
            baseUrl: resp.finalUrl,
            session: session,
            cancelToken: cancelToken,
          );
    final kind = source.ruleBookInfo.kind.isEmpty
        ? null
        : _nullableTrimmed(
            await evaluator.evaluateString(
              infoInput,
              source.ruleBookInfo.kind,
              baseUrl: resp.finalUrl,
              session: session,
              cancelToken: cancelToken,
            ),
          );
    final wordCountStr = source.ruleBookInfo.wordCount.isEmpty
        ? ''
        : await evaluator.evaluateString(
            infoInput,
            source.ruleBookInfo.wordCount,
            baseUrl: resp.finalUrl,
            session: session,
            cancelToken: cancelToken,
          );
    final rawTocUrl = source.ruleBookInfo.tocUrl.isEmpty
        ? resp.finalUrl
        : await evaluator.evaluateString(
            infoInput,
            source.ruleBookInfo.tocUrl,
            baseUrl: resp.finalUrl,
            session: session,
            cancelToken: cancelToken,
          );
    final tocUrl = rawTocUrl.isEmpty
        ? resp.finalUrl
        : LegadoRuleEvaluator.resolveUrlSpec(rawTocUrl, resp.finalUrl);
    session.bookUrl = resp.finalUrl;
    session.tocUrl = tocUrl;

    sw.stop();
    return (
      detail: BookDetail(
        sourceId: providerId,
        providerType: type,
        bookUrl: resp.finalUrl,
        tocUrl: tocUrl,
        title: title,
        author: author,
        coverUrl: coverUrl,
        intro: intro,
        latestChapterTitle: lastChapter,
        kind: kind,
        wordCount: _parseWordCount(wordCountStr),
      ),
      trace: SourceDebugTrace(
        step: 'detail',
        elapsedMs: sw.elapsedMilliseconds,
        httpStatus: resp.statusCode,
        requestUrl: resp.finalUrl,
        matchedPreview: '$title / $author (charset=${resp.detectedCharset})',
        logs: List<String>.unmodifiable(session.logs),
      ),
    );
    } finally {
      _syncSession(session);
    }
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final sw = Stopwatch()..start();
    _ensureSupported(
      stepWebView: source.ruleToc.webView,
      stepName: 'ruleToc',
    );
    evaluator.guardUnsupportedRules(<String?>[
      tocUrl,
      source.rawHeader,
      source.jsLib,
      source.ruleToc.chapterList,
      source.ruleToc.chapterName,
      source.ruleToc.chapterUrl,
      source.ruleToc.nextTocUrl,
      source.ruleToc.preUpdateJs,
    ]);

    final session = _createSession(tocUrl: tocUrl);
    try {
      final baseHeaders = await evaluator.evaluateHeaders(
      baseUrl: source.effectiveBaseUrl,
      session: session,
      cancelToken: cancelToken,
    );

    final visitedUrls = <String>{};
    final chapters = <ChapterMeta>[];
    final now = DateTime.now().toUtc();
    var pageCount = 0;
    var firstStatus = 200;
    var firstFinalUrl = tocUrl;
    var detectedCharset = 'utf-8';
    var reverseAll = false;

    final pendingQueue = <String>[tocUrl];

    while (pendingQueue.isNotEmpty && pageCount < maxTocPages) {
      cancelToken?.throwIfCancelled();
      final currentSpec = pendingQueue.removeAt(0);
      final req = await evaluator.parseUrlSpecAsync(
        currentSpec,
        baseUrl: source.effectiveBaseUrl,
        defaultHeaders: baseHeaders,
        defaultCharset: source.charset,
        session: session,
        cancelToken: cancelToken,
      );
      _ensureSupported(stepWebView: req.webView, stepName: 'tocUrl');

      final canonicalKey = _canonicalUrlKey(req.url);
      if (visitedUrls.contains(canonicalKey)) {
        continue;
      }
      visitedUrls.add(canonicalKey);
      pageCount++;

      final resp = await httpClient.request(
        req.url,
        method: req.method,
        data: req.body,
        headers: req.headers,
        charsetOverride: req.charset,
        rateLimitMs: effectiveRateLimitMs,
        cancelToken: cancelToken,
      );
      if (pageCount == 1) {
        firstStatus = resp.statusCode;
        firstFinalUrl = resp.finalUrl;
        detectedCharset = resp.detectedCharset;
        visitedUrls.add(_canonicalUrlKey(resp.finalUrl));
      }

      final preUpdateRaw = source.ruleToc.preUpdateJs.trim();
      if (preUpdateRaw.isNotEmpty) {
        final preUpdateRule =
            preUpdateRaw.contains('<js>') ||
                preUpdateRaw.toLowerCase().startsWith('@js:')
            ? preUpdateRaw
            : '@js:$preUpdateRaw';
        await evaluator.evaluateString(
          resp.body,
          preUpdateRule,
          baseUrl: resp.finalUrl,
          session: session,
          cancelToken: cancelToken,
        );
      }

      final blocksRes = await evaluator.evaluateListBlocks(
        resp.body,
        source.ruleToc.chapterList,
        baseUrl: resp.finalUrl,
        session: session,
        cancelToken: cancelToken,
      );
      if (blocksRes.reversed) {
        reverseAll = true;
      }
      if (pageCount == 1 && blocksRes.items.isEmpty) {
        throw SourceParseFailure(
          message:
              'Legado ruleToc.chapterList matched 0 elements (${source.ruleToc.chapterList})',
          sourceId: providerId,
          step: 'toc',
          rule: source.ruleToc.chapterList,
        );
      }

      for (final block in blocksRes.items) {
        cancelToken?.throwIfCancelled();
        final title = await evaluator.evaluateString(
          block,
          source.ruleToc.chapterName,
          baseUrl: resp.finalUrl,
          session: session,
          cancelToken: cancelToken,
        );
        final rawUrl = source.ruleToc.chapterUrl.trim().isEmpty
            ? ''
            : await evaluator.evaluateString(
                block,
                source.ruleToc.chapterUrl,
                baseUrl: resp.finalUrl,
                session: session,
                cancelToken: cancelToken,
              );
        if (title.isEmpty) continue;
        final resolvedUrl = rawUrl.isEmpty
            ? resp.finalUrl
            : (_isBareNonHttpIdentifier(rawUrl) &&
                      _startsWithJsRule(source.ruleContent.content))
                  ? rawUrl.trim()
                  : LegadoRuleEvaluator.resolveUrlSpec(rawUrl, resp.finalUrl);
        chapters.add(
          ChapterMeta(
            bookId: firstFinalUrl,
            chapterIndex: chapters.length,
            title: title,
            url: resolvedUrl,
            updatedAt: now,
          ),
        );
      }

      final nextTocRule = source.ruleToc.nextTocUrl.trim();
      if (nextTocRule.isNotEmpty) {
        final nextRawUrls = await evaluator.evaluateList(
          resp.body,
          nextTocRule,
          baseUrl: resp.finalUrl,
          session: session,
          cancelToken: cancelToken,
        );
        for (final rawNext in nextRawUrls) {
          final trimmedNext = rawNext.trim();
          if (trimmedNext.isEmpty) continue;
          final resolvedNext = LegadoRuleEvaluator.resolveUrlSpec(
            trimmedNext,
            resp.finalUrl,
          );
          final key = _canonicalUrlKey(resolvedNext);
          if (!visitedUrls.contains(key) &&
              !pendingQueue.any((u) => _canonicalUrlKey(u) == key)) {
            pendingQueue.add(resolvedNext);
          }
        }
      }
    }

    final finalChapters = reverseAll
        ? _reindexChapters(chapters.reversed.toList(growable: false))
        : chapters;

    sw.stop();
    return (
      chapters: finalChapters,
      trace: SourceDebugTrace(
        step: 'toc',
        elapsedMs: sw.elapsedMilliseconds,
        httpStatus: firstStatus,
        requestUrl: firstFinalUrl,
        matchedPreview: finalChapters.isEmpty
            ? '0 chapters'
            : '${finalChapters.length} chapters across $pageCount page(s) (charset=$detectedCharset)',
        logs: List<String>.unmodifiable(session.logs),
      ),
    );
    } finally {
      _syncSession(session);
    }
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final sw = Stopwatch()..start();
    _ensureSupported(
      stepWebView: source.ruleContent.webView,
      stepName: 'ruleContent',
    );

    final rawChapterUrl = chapter.url;
    if (rawChapterUrl == null || rawChapterUrl.trim().isEmpty) {
      throw SourceParseFailure(
        message: 'ChapterMeta.url is empty for ${chapter.title}',
        sourceId: providerId,
        step: 'content',
      );
    }
    evaluator.guardUnsupportedRules(<String?>[
      rawChapterUrl,
      source.rawHeader,
      source.jsLib,
      source.ruleContent.content,
      source.ruleContent.nextContentUrl,
      source.ruleContent.replaceRegex,
    ]);

    final session = _createSession(
      chapterTitle: chapter.title,
      chapterUrl: rawChapterUrl,
      chapterIndex: chapter.chapterIndex,
    );
    try {
      final baseHeaders = await evaluator.evaluateHeaders(
      baseUrl: source.effectiveBaseUrl,
      session: session,
      cancelToken: cancelToken,
    );

    final visitedUrls = <String>{};
    final pageTexts = <String>[];
    final pendingQueue = <String>[rawChapterUrl];
    var pageCount = 0;
    var firstStatus = 200;
    var firstFinalUrl = rawChapterUrl;
    var detectedCharset = 'utf-8';

    final contentRule = source.ruleContent.content;
    final contentStartsWithJs = _startsWithJsRule(contentRule);

    while (pendingQueue.isNotEmpty && pageCount < maxContentPages) {
      cancelToken?.throwIfCancelled();
      final currentSpec = pendingQueue.removeAt(0);
      final isBareJsChapterId =
          contentStartsWithJs && _isBareNonHttpIdentifier(currentSpec);

      final String pageInput;
      final String evalBaseUrl;
      if (isBareJsChapterId) {
        final bareId = currentSpec.trim();
        if (!visitedUrls.add(bareId)) continue;
        pageCount++;
        if (pageCount == 1) {
          firstStatus = 200;
          firstFinalUrl = bareId;
          detectedCharset = 'direct-js';
        }
        pageInput = bareId;
        evalBaseUrl = source.effectiveBaseUrl;
      } else {
        final req = await evaluator.parseUrlSpecAsync(
          currentSpec,
          baseUrl: source.effectiveBaseUrl,
          defaultHeaders: baseHeaders,
          defaultCharset: source.charset,
          session: session,
          cancelToken: cancelToken,
        );
        _ensureSupported(stepWebView: req.webView, stepName: 'chapterUrl');

        final key = _canonicalUrlKey(req.url);
        if (visitedUrls.contains(key)) continue;
        visitedUrls.add(key);
        pageCount++;

        final resp = await httpClient.request(
          req.url,
          method: req.method,
          data: req.body,
          headers: req.headers,
          charsetOverride: req.charset,
          rateLimitMs: effectiveRateLimitMs,
          cancelToken: cancelToken,
        );

        if (pageCount == 1) {
          firstStatus = resp.statusCode;
          firstFinalUrl = resp.finalUrl;
          detectedCharset = resp.detectedCharset;
          visitedUrls.add(_canonicalUrlKey(resp.finalUrl));
        }
        pageInput = resp.body;
        evalBaseUrl = resp.finalUrl;
      }

      final pageText = await evaluator.evaluateString(
        pageInput,
        contentRule,
        baseUrl: evalBaseUrl,
        session: session,
        cancelToken: cancelToken,
      );
      if (pageText.trim().isNotEmpty) {
        pageTexts.add(pageText.trim());
      }

      final nextContentRule = source.ruleContent.nextContentUrl.trim();
      if (nextContentRule.isNotEmpty) {
        final nextRawUrls = await evaluator.evaluateList(
          pageInput,
          nextContentRule,
          baseUrl: evalBaseUrl,
          session: session,
          cancelToken: cancelToken,
        );
        for (final rawNext in nextRawUrls) {
          final trimmedNext = rawNext.trim();
          if (trimmedNext.isEmpty) continue;
          final resolvedNext =
              contentStartsWithJs && _isBareNonHttpIdentifier(trimmedNext)
              ? trimmedNext
              : LegadoRuleEvaluator.resolveUrlSpec(trimmedNext, evalBaseUrl);
          final nextKey = _canonicalUrlKey(resolvedNext);
          if (!visitedUrls.contains(nextKey) &&
              !pendingQueue.any((u) => _canonicalUrlKey(u) == nextKey)) {
            pendingQueue.add(resolvedNext);
          }
        }
      }
    }

    var text = pageTexts.join('\n');

    final replaceRegexRaw = source.ruleContent.replaceRegex.trim();
    if (replaceRegexRaw.isNotEmpty && text.isNotEmpty) {
      final resolvedReplace = replaceRegexRaw
          .replaceAll('{{chapter.title}}', chapter.title)
          .replaceAll('{{book.name}}', session.bookName);
      final lowerReplace = resolvedReplace.toLowerCase();
      final isJsReplace =
          lowerReplace.startsWith('@js:') || lowerReplace.startsWith('<js>');
      final spec = (resolvedReplace.startsWith('##') || isJsReplace)
          ? resolvedReplace
          : '##$resolvedReplace';
      final replaceBaseUrl =
          SourceHttpClient.tryNormalizeHttpUri(firstFinalUrl) != null
          ? firstFinalUrl
          : source.effectiveBaseUrl;
      text = await evaluator.evaluateString(
        text,
        spec,
        baseUrl: replaceBaseUrl,
        session: session,
        cancelToken: cancelToken,
      );
    }

    if (text.trim().isEmpty) {
      throw SourceParseFailure(
        message: 'Legado ruleContent.content extracted empty text',
        sourceId: providerId,
        step: 'content',
        rule: source.ruleContent.content,
      );
    }

    sw.stop();
    return (
      content: ChapterContent(
        chapterIndex: chapter.chapterIndex,
        title: chapter.title,
        rawText: text,
        sourceUrl: firstFinalUrl,
        fetchedAt: DateTime.now().toUtc(),
      ),
      trace: SourceDebugTrace(
        step: 'content',
        elapsedMs: sw.elapsedMilliseconds,
        httpStatus: firstStatus,
        requestUrl: firstFinalUrl,
        matchedPreview:
            '(${pageCount}p, $detectedCharset) ${text.length > 50 ? "${text.substring(0, 50)}..." : text}',
        logs: List<String>.unmodifiable(session.logs),
      ),
    );
    } finally {
      _syncSession(session);
    }
  }

  Future<BookSearchItem?> _tryExtractRedirectDetailSearchItem({
    required HttpFetchResult resp,
    required String keyword,
    required bool redirected,
    required LegadoEvalSession session,
    CancellationToken? cancelToken,
  }) async {
    final infoRule = source.ruleBookInfo;
    if (infoRule.webView) return null;
    if (infoRule.name.trim().isEmpty && infoRule.init.trim().isEmpty) {
      return null;
    }

    try {
      var infoInput = resp.body;
      if (infoRule.init.trim().isNotEmpty) {
        final initVal = await evaluator.evaluateString(
          infoInput,
          infoRule.init,
          baseUrl: resp.finalUrl,
          session: session,
          cancelToken: cancelToken,
        );
        if (initVal.isNotEmpty) {
          infoInput = initVal;
        }
      }

      final title = infoRule.name.trim().isEmpty
          ? ''
          : (await evaluator.evaluateString(
              infoInput,
              infoRule.name,
              baseUrl: resp.finalUrl,
              session: session,
              cancelToken: cancelToken,
            )).trim();
      if (title.isEmpty) return null;

      final author = infoRule.author.trim().isEmpty
          ? ''
          : (await evaluator.evaluateString(
              infoInput,
              infoRule.author,
              baseUrl: resp.finalUrl,
              session: session,
              cancelToken: cancelToken,
            )).trim();

      final tocUrl = infoRule.tocUrl.trim().isEmpty
          ? ''
          : (await evaluator.evaluateString(
              infoInput,
              infoRule.tocUrl,
              baseUrl: resp.finalUrl,
              session: session,
              cancelToken: cancelToken,
            )).trim();

      final matchedCondition =
          redirected ||
          (keyword.trim().isNotEmpty && title.contains(keyword.trim())) ||
          tocUrl.isNotEmpty ||
          author.isNotEmpty;
      if (!matchedCondition) return null;

      final coverUrl = infoRule.coverUrl.trim().isEmpty
          ? null
          : _resolveOptional(
              await evaluator.evaluateString(
                infoInput,
                infoRule.coverUrl,
                baseUrl: resp.finalUrl,
                session: session,
                cancelToken: cancelToken,
              ),
              resp.finalUrl,
            );
      final intro = infoRule.intro.trim().isEmpty
          ? ''
          : await evaluator.evaluateString(
              infoInput,
              infoRule.intro,
              baseUrl: resp.finalUrl,
              session: session,
              cancelToken: cancelToken,
            );
      final lastChapter = infoRule.lastChapter.trim().isEmpty
          ? ''
          : await evaluator.evaluateString(
              infoInput,
              infoRule.lastChapter,
              baseUrl: resp.finalUrl,
              session: session,
              cancelToken: cancelToken,
            );
      final kind = infoRule.kind.trim().isEmpty
          ? null
          : _nullableTrimmed(
              await evaluator.evaluateString(
                infoInput,
                infoRule.kind,
                baseUrl: resp.finalUrl,
                session: session,
                cancelToken: cancelToken,
              ),
            );

      return BookSearchItem(
        sourceId: providerId,
        providerType: type,
        bookUrl: resp.finalUrl,
        title: title,
        author: author,
        coverUrl: coverUrl,
        intro: intro,
        latestChapterTitle: lastChapter,
        kind: kind,
      );
    } on JsExecutionFailure {
      return null;
    }
  }

  static List<ChapterMeta> _reindexChapters(List<ChapterMeta> chapters) {
    return List<ChapterMeta>.generate(
      chapters.length,
      (i) => chapters[i].copyWith(chapterIndex: i),
      growable: false,
    );
  }

  static String _canonicalUrlKey(String url) {
    final normalized = SourceHttpClient.tryNormalizeHttpUri(url);
    if (normalized == null) return url.trim();
    return normalized.toString();
  }

  static String? _resolveOptional(String rawUrl, String baseUrl) {
    if (rawUrl.trim().isEmpty) return null;
    return SourceHttpClient.resolveUrl(rawUrl, baseUrl);
  }

  static String? _nullableTrimmed(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static final RegExp _urlOptionsSuffixPattern = RegExp(r',\s*\{[\s\S]*\}$');
  static final RegExp _relativeWebFileExtPattern = RegExp(
    r'\.(?:s?html?|xhtml|php\d*|aspx?|jsp|jspx|do|action|json|xml|txt|cgi|py|rb|pl|cfm)$',
    caseSensitive: false,
  );

  static bool _startsWithJsRule(String rule) {
    final lower = rule.trimLeft().toLowerCase();
    return lower.startsWith('@js:') || lower.startsWith('<js>');
  }

  static bool _isBareNonHttpIdentifier(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        trimmed.contains('://') ||
        trimmed.startsWith('//')) {
      return false;
    }
    if (trimmed.contains('/') || trimmed.contains(r'\')) {
      return false;
    }
    if (trimmed.contains('?') || trimmed.contains('#')) {
      return false;
    }
    if (lower.startsWith('@js:') ||
        lower.contains('<js>') ||
        (trimmed.contains('{{') && trimmed.contains('}}'))) {
      return false;
    }
    if (_urlOptionsSuffixPattern.hasMatch(trimmed)) {
      return false;
    }
    if (_relativeWebFileExtPattern.hasMatch(trimmed)) {
      return false;
    }
    if (SourceHttpClient.tryNormalizeHttpUri(trimmed) != null) {
      return false;
    }
    return true;
  }

  static int? _parseWordCount(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }
}
