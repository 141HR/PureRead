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
    Duration jsTimeout = const Duration(seconds: 5),
  }) : evaluator = LegadoRuleEvaluator(
          sourceId: providerId,
          jsTimeout: jsTimeout,
        );

  void _ensureSupported({bool stepWebView = false, String? stepName}) {
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
    final sw = Stopwatch()..start();
    _ensureSupported(stepName: 'search');

    final rawSearchUrl = source.searchUrl?.trim() ?? '';
    if (rawSearchUrl.isEmpty) {
      throw UnsupportedLegadoRuleFailure(
        message: 'Legado source has no searchUrl configured',
        feature: 'searchUrl',
        sourceId: providerId,
      );
    }

    final req = LegadoRuleEvaluator.parseUrlSpec(
      rawSearchUrl,
      baseUrl: source.bookSourceUrl,
      defaultHeaders: source.headers,
      defaultCharset: source.charset,
      keyword: keyword,
      page: page,
    );
    _ensureSupported(stepWebView: req.webView, stepName: 'searchUrl');

    final resp = await httpClient.request(
      req.url,
      method: req.method,
      data: req.body,
      headers: req.headers,
      charsetOverride: req.charset,
      cancelToken: cancelToken,
    );

    final itemBlocks = evaluator.evaluateElementsHtml(
      resp.body,
      source.ruleSearch.bookList,
    );
    if (itemBlocks.isEmpty) {
      throw SourceParseFailure(
        message:
            'Legado ruleSearch.bookList matched 0 elements (${source.ruleSearch.bookList})',
        sourceId: providerId,
        step: 'search',
        rule: source.ruleSearch.bookList,
      );
    }

    final items = <BookSearchItem>[];
    for (final block in itemBlocks) {
      final title = await evaluator.evaluateString(
        block,
        source.ruleSearch.name,
        baseUrl: resp.finalUrl,
        cancelToken: cancelToken,
      );
      final rawBookUrl = await evaluator.evaluateString(
        block,
        source.ruleSearch.bookUrl,
        baseUrl: resp.finalUrl,
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
              cancelToken: cancelToken,
            );
      final coverUrl = source.ruleSearch.coverUrl.isEmpty
          ? null
          : _resolveOptional(
              await evaluator.evaluateString(
                block,
                source.ruleSearch.coverUrl,
                baseUrl: resp.finalUrl,
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
              cancelToken: cancelToken,
            );
      final lastChapter = source.ruleSearch.lastChapter.isEmpty
          ? ''
          : await evaluator.evaluateString(
              block,
              source.ruleSearch.lastChapter,
              baseUrl: resp.finalUrl,
              cancelToken: cancelToken,
            );

      items.add(
        BookSearchItem(
          sourceId: providerId,
          providerType: type,
          bookUrl: _resolveUrl(rawBookUrl, resp.finalUrl),
          title: title,
          author: author,
          coverUrl: coverUrl,
          intro: intro,
          latestChapterTitle: lastChapter,
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
      ),
    );
  }

  @override
  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    _ensureSupported(
      stepWebView: source.ruleBookInfo.webView,
      stepName: 'ruleBookInfo',
    );

    final req = LegadoRuleEvaluator.parseUrlSpec(
      bookUrl,
      baseUrl: source.bookSourceUrl,
      defaultHeaders: source.headers,
      defaultCharset: source.charset,
    );
    _ensureSupported(stepWebView: req.webView, stepName: 'bookUrl');

    final resp = await httpClient.request(
      req.url,
      method: req.method,
      data: req.body,
      headers: req.headers,
      charsetOverride: req.charset,
      cancelToken: cancelToken,
    );

    final title = await evaluator.evaluateString(
      resp.body,
      source.ruleBookInfo.name,
      baseUrl: resp.finalUrl,
      cancelToken: cancelToken,
    );
    if (title.isEmpty) {
      throw SourceParseFailure(
        message: 'Legado ruleBookInfo.name returned empty string',
        sourceId: providerId,
        step: 'detail',
        rule: source.ruleBookInfo.name,
      );
    }

    final author = source.ruleBookInfo.author.isEmpty
        ? ''
        : await evaluator.evaluateString(
            resp.body,
            source.ruleBookInfo.author,
            baseUrl: resp.finalUrl,
            cancelToken: cancelToken,
          );
    final intro = source.ruleBookInfo.intro.isEmpty
        ? ''
        : await evaluator.evaluateString(
            resp.body,
            source.ruleBookInfo.intro,
            baseUrl: resp.finalUrl,
            cancelToken: cancelToken,
          );
    final rawTocUrl = source.ruleBookInfo.tocUrl.isEmpty
        ? resp.finalUrl
        : await evaluator.evaluateString(
            resp.body,
            source.ruleBookInfo.tocUrl,
            baseUrl: resp.finalUrl,
            cancelToken: cancelToken,
          );
    final tocUrl = rawTocUrl.isEmpty
        ? resp.finalUrl
        : _resolveUrl(rawTocUrl, resp.finalUrl);

    sw.stop();
    return (
      detail: BookDetail(
        sourceId: providerId,
        providerType: type,
        bookUrl: resp.finalUrl,
        tocUrl: tocUrl,
        title: title,
        author: author,
        intro: intro,
      ),
      trace: SourceDebugTrace(
        step: 'detail',
        elapsedMs: sw.elapsedMilliseconds,
        httpStatus: resp.statusCode,
        requestUrl: resp.finalUrl,
        matchedPreview: '$title / $author (charset=${resp.detectedCharset})',
      ),
    );
  }

  @override
  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    _ensureSupported(
      stepWebView: source.ruleToc.webView,
      stepName: 'ruleToc',
    );

    final req = LegadoRuleEvaluator.parseUrlSpec(
      tocUrl,
      baseUrl: source.bookSourceUrl,
      defaultHeaders: source.headers,
      defaultCharset: source.charset,
    );
    _ensureSupported(stepWebView: req.webView, stepName: 'tocUrl');

    final resp = await httpClient.request(
      req.url,
      method: req.method,
      data: req.body,
      headers: req.headers,
      charsetOverride: req.charset,
      cancelToken: cancelToken,
    );

    final blocks = evaluator.evaluateElementsHtml(
      resp.body,
      source.ruleToc.chapterList,
    );
    if (blocks.isEmpty) {
      throw SourceParseFailure(
        message:
            'Legado ruleToc.chapterList matched 0 elements (${source.ruleToc.chapterList})',
        sourceId: providerId,
        step: 'toc',
        rule: source.ruleToc.chapterList,
      );
    }

    final chapters = <ChapterMeta>[];
    final now = DateTime.now().toUtc();
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final title = await evaluator.evaluateString(
        block,
        source.ruleToc.chapterName,
        baseUrl: resp.finalUrl,
        cancelToken: cancelToken,
      );
      final rawUrl = await evaluator.evaluateString(
        block,
        source.ruleToc.chapterUrl,
        baseUrl: resp.finalUrl,
        cancelToken: cancelToken,
      );
      if (title.isEmpty || rawUrl.isEmpty) continue;
      chapters.add(
        ChapterMeta(
          bookId: resp.finalUrl,
          chapterIndex: chapters.length,
          title: title,
          url: _resolveUrl(rawUrl, resp.finalUrl),
          updatedAt: now,
        ),
      );
    }

    sw.stop();
    return (
      chapters: chapters,
      trace: SourceDebugTrace(
        step: 'toc',
        elapsedMs: sw.elapsedMilliseconds,
        httpStatus: resp.statusCode,
        requestUrl: resp.finalUrl,
        matchedPreview: chapters.isEmpty
            ? '0 chapters'
            : '${chapters.length} chapters (charset=${resp.detectedCharset})',
      ),
    );
  }

  @override
  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    _ensureSupported(
      stepWebView: source.ruleContent.webView,
      stepName: 'ruleContent',
    );

    final rawChapterUrl = chapter.url;
    if (rawChapterUrl == null || rawChapterUrl.isEmpty) {
      throw SourceParseFailure(
        message: 'ChapterMeta.url is empty for ${chapter.title}',
        sourceId: providerId,
        step: 'content',
      );
    }

    final req = LegadoRuleEvaluator.parseUrlSpec(
      rawChapterUrl,
      baseUrl: source.bookSourceUrl,
      defaultHeaders: source.headers,
      defaultCharset: source.charset,
    );
    _ensureSupported(stepWebView: req.webView, stepName: 'chapterUrl');

    final resp = await httpClient.request(
      req.url,
      method: req.method,
      data: req.body,
      headers: req.headers,
      charsetOverride: req.charset,
      cancelToken: cancelToken,
    );

    var text = await evaluator.evaluateString(
      resp.body,
      source.ruleContent.content,
      baseUrl: resp.finalUrl,
      cancelToken: cancelToken,
    );

    if (source.ruleContent.replaceRegex.isNotEmpty) {
      final spec = source.ruleContent.replaceRegex.startsWith('##')
          ? source.ruleContent.replaceRegex
          : '##${source.ruleContent.replaceRegex}';
      final regexReplaced = await evaluator.evaluateString(
        text,
        spec,
        baseUrl: resp.finalUrl,
        cancelToken: cancelToken,
      );
      text = regexReplaced;
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
        sourceUrl: resp.finalUrl,
        fetchedAt: DateTime.now().toUtc(),
      ),
      trace: SourceDebugTrace(
        step: 'content',
        elapsedMs: sw.elapsedMilliseconds,
        httpStatus: resp.statusCode,
        requestUrl: resp.finalUrl,
        matchedPreview:
            '(${resp.detectedCharset}) ${text.length > 50 ? "${text.substring(0, 50)}..." : text}',
      ),
    );
  }

  static String _resolveUrl(String rawUrl, String baseUrl) {
    final trimmed = rawUrl.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return trimmed;
    return Uri.parse(baseUrl).resolve(trimmed).toString();
  }

  static String? _resolveOptional(String rawUrl, String baseUrl) {
    if (rawUrl.trim().isEmpty) return null;
    return _resolveUrl(rawUrl, baseUrl);
  }
}
