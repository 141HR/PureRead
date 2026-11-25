import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/engine/source_engine/parsing/parsing.dart';
import 'package:pureread/infrastructure/js/qjs_sandbox_runtime.dart';

const String _sampleBookHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:title" content="凡人修仙传" />
  <meta property="og:novel:author" content="忘语" />
</head>
<body>
  <form id="login-form">
    <input type="hidden" name="_token" value="tok_987654" />
  </form>
  <div id="book-info" class="card featured">
    <h1>凡人修仙传</h1>
    <div class="introduce">
      山村穷小子，偶然之下，进入到江湖小门派。
      <span class="ad">广告：下载APP免费看</span>
      <p>开启修仙之路。</p>
    </div>
    <img class="cover" data-src="/covers/fanren.jpg" src="/img/placeholder.png" />
  </div>
  <div id="chapters" class="list">
    <p class="header">正文卷</p>
    <a class="chap" href="/book/100/c1.html">第一章 山边小村</a>
    <a class="chap vip" href="/book/100/c2.html">第二章 青牛镇</a>
    <a class="chap" href="/book/100/c3.html">Chapter Three: Trial</a>
    <a class="ad-link" href="https://ads.example.com/promo">推广链接</a>
  </div>
  <div id="content">
    正文第一段。<span class="note">（校对注）</span>正文结尾。
    <p class="ad">关注公众号</p>
    <script>var secret = "ignore-me";</script>
  </div>
</body>
</html>
''';

void main() {
  group('LegadoJsoupBridge (Dart API)', () {
    test('parses HTML, resolves abs: attributes, and cleans up on dispose()', () {
      final bridge = LegadoJsoupBridge();
      expect(bridge.handleCount, 0);
      expect(bridge.isDisposed, isFalse);

      final docId = bridge.parse(
        _sampleBookHtml,
        'https://www.example.com/book/100/',
      );
      expect(docId, greaterThan(0));
      expect(bridge.tagName(docId), '#root');

      final links = bridge.select(docId, '#chapters a.chap');
      expect(links, hasLength(3));
      expect(bridge.attr(links.first, 'href'), '/book/100/c1.html');
      expect(
        bridge.attr(links.first, 'abs:href'),
        'https://www.example.com/book/100/c1.html',
      );
      expect(
        bridge.absUrl(links[1], 'href'),
        'https://www.example.com/book/100/c2.html',
      );

      final coverIds = bridge.select(docId, 'img.cover');
      expect(coverIds, hasLength(1));
      expect(
        bridge.attr(coverIds.first, 'abs:data-src'),
        'https://www.example.com/covers/fanren.jpg',
      );
      expect(bridge.hasAttr(coverIds.first, 'abs:data-src'), isTrue);
      expect(bridge.hasAttr(coverIds.first, 'missing-attr'), isFalse);
      expect(bridge.hasClass(coverIds.first, 'cover'), isTrue);
      expect(bridge.className(coverIds.first), 'cover');

      expect(bridge.handleCount, greaterThan(1));
      bridge.dispose();
      expect(bridge.isDisposed, isTrue);
      expect(bridge.handleCount, 0);
      expect(bridge.select(docId, 'a'), isEmpty);
      expect(bridge.text(docId), isEmpty);
      expect(() => bridge.parse('<p>hi</p>'), throwsStateError);
    });

    test('supports CSS combinators and Jsoup pseudo-selectors without throwing', () {
      final bridge = LegadoJsoupBridge();
      try {
        final docId = bridge.parse(_sampleBookHtml, 'https://example.com');

        // :contains (case-insensitive) & :containsOwn
        final containsTrial = bridge.select(docId, 'a:contains(trial)');
        expect(containsTrial, hasLength(1));
        expect(bridge.text(containsTrial.first), 'Chapter Three: Trial');

        final contentDiv = bridge.select(docId, '#content:containsOwn(正文第一段)');
        expect(contentDiv, hasLength(1));
        expect(bridge.ownText(contentDiv.first), '正文第一段。正文结尾。');

        // :matches
        final matchesChapter = bridge.select(docId, 'a.chap:matches(^第[一二]章)');
        expect(matchesChapter, hasLength(2));

        // :eq, :gt, :lt, :first, :last
        expect(bridge.text(bridge.select(docId, 'a.chap:eq(1)').single), '第二章 青牛镇');
        expect(bridge.text(bridge.select(docId, 'a.chap:eq(-1)').single), 'Chapter Three: Trial');
        expect(bridge.select(docId, 'a.chap:gt(0)'), hasLength(2));
        expect(bridge.select(docId, 'a.chap:lt(2)'), hasLength(2));
        expect(bridge.text(bridge.select(docId, 'a.chap:first').single), '第一章 山边小村');
        expect(bridge.text(bridge.select(docId, 'a.chap:last').single), 'Chapter Three: Trial');

        // :not(...)
        final nonVipChaps = bridge.select(docId, '#chapters a.chap:not(.vip)');
        expect(nonVipChaps, hasLength(2));
        final nonAdLinks = bridge.select(
          docId,
          '#chapters a:not(.ad-link, :contains(青牛))',
        );
        expect(nonAdLinks, hasLength(2));

        // [attr~=regex] (unquoted with character class and quoted)
        final regexLinks = bridge.select(
          docId,
          r'a[href~=/book/\d+/c[12]\.html$]',
        );
        expect(regexLinks, hasLength(2));

        // Child / sibling combinators
        expect(bridge.select(docId, '#chapters > p.header + a'), hasLength(1));
        expect(bridge.select(docId, '#chapters > p.header ~ a.chap'), hasLength(3));

        // Malformed / invalid selectors fall back cleanly
        expect(bridge.select(docId, ''), isEmpty);
        expect(bridge.select(docId, 'div[unclosed'), isEmpty);
        expect(bridge.select(docId, ':matches([invalid)'), isEmpty);
        expect(bridge.select(docId, 'div >> p'), isEmpty);
        expect(bridge.select(docId, ':unknown-pseudo'), isEmpty);
      } finally {
        bridge.dispose();
      }
    });

    test('supports DOM traversal, lookup methods, and clean remove()', () {
      final bridge = LegadoJsoupBridge();
      try {
        final docId = bridge.parse(_sampleBookHtml);
        final infoId = bridge.getElementById(docId, 'book-info');
        expect(infoId, isNotNull);
        expect(bridge.id(infoId!), 'book-info');
        expect(bridge.tagName(infoId), 'div');
        expect(bridge.hasClass(infoId, 'featured'), isTrue);

        expect(bridge.getElementsByTag(docId, 'meta'), hasLength(2));
        expect(bridge.getElementsByClass(docId, 'chap'), hasLength(3));
        expect(bridge.getElementsByAttribute(docId, 'data-src'), hasLength(1));
        expect(
          bridge.getElementsByAttributeValue(docId, 'name', '_token'),
          hasLength(1),
        );

        final children = bridge.children(infoId);
        expect(children, hasLength(3));
        final h1Id = children.first;
        expect(bridge.tagName(h1Id), 'h1');
        expect(bridge.parent(h1Id), infoId);

        final introId = bridge.nextElementSibling(h1Id);
        expect(introId, isNotNull);
        expect(bridge.className(introId!), 'introduce');
        expect(bridge.previousElementSibling(introId), h1Id);

        // Remove .ad nodes and verify DOM update
        for (final adId in bridge.select(docId, '.ad')) {
          bridge.remove(adId);
        }
        expect(bridge.select(docId, '.ad'), isEmpty);
        expect(bridge.text(introId), isNot(contains('广告')));
        expect(bridge.text(introId), contains('山村穷小子'));
        expect(bridge.html(introId), isNot(contains('广告')));
        expect(bridge.outerHtml(h1Id), '<h1>凡人修仙传</h1>');
      } finally {
        bridge.dispose();
      }
    });
  });

  group('LegadoJsoupBridge inside QjsSandboxRuntime', () {
    test('executes real Legado Jsoup scripts including importClass, indexing, loops, and mutation', () async {
      final bridge = LegadoJsoupBridge();
      final runtime = QjsSandboxRuntime(
        sourceId: 'jsoup-e2e',
        syncHostFunctions: bridge.buildSyncHostFunctions(),
      );
      try {
        final res = await runtime.evaluate(
          '''
          ${LegadoJsoupBridge.jsPrelude}
          importClass(org.jsoup.Jsoup);
          importClass(org.jsoup.nodes.Document);
          importClass(org.jsoup.select.Elements);

          const doc = Jsoup.parse(html, 'https://novel.example.com/book/100');
          const doc2 = org.jsoup.Jsoup.parse(html);
          const doc3 = Packages.org.jsoup.Jsoup.parse(html);

          const token = doc2.select('input[name="_token"]').attr('value');
          const ogTitle = doc.select('[property="og:title"]').attr('content');

          // Remove ad nodes before extracting intro & content
          doc.select('.ad, .ad-link').remove();
          const intro = doc.select('.introduce').text();
          const contentOwn = doc.select('#content').ownText();
          const removedAdEmpty = doc.select('#content p.ad').isEmpty();
          const contentHtml = doc3.select('#content p.ad').outerHtml();

          // for (i in a) and for (el of a) and array functional methods
          const a = doc.select('#chapters a.chap');
          const forInItems = [];
          for (i in a) {
            forInItems.push(a[i].text() + '|' + a[i].attr('href'));
          }
          const forOfTitles = [];
          for (const el of a) {
            forOfTitles.push(el.text());
          }
          const mapped = a.map(el => el.absUrl('href'));
          const eachAttrRes = a.eachAttr('abs:href');
          const eachTextRes = a.eachText();
          const forEachCount = (() => {
            let n = 0;
            a.forEach(() => { n++; });
            return n;
          })();
          const flatMapped = doc.select('#book-info').flatMap(
            el => el.select('h1, .introduce p').eachText()
          );

          // Pseudo-selectors & Elements helpers
          const secondChap = doc.select('#chapters a.chap:eq(1)').text();
          const containsChap = doc.select('#chapters a:contains(青牛)').first().attr('href');
          const notVipSize = a.select(':not(.vip)').size();
          const eqFirst = a.eq(0).text();
          const lastText = a.last().text();
          const getSecond = a.get(1).text();
          const emptyCheck = doc.select('.does-not-exist').isEmpty();
          const firstFromSelect = doc.selectFirst('img.cover').attr('abs:data-src');
          const byId = doc.getElementById('book-info').children().get(0).text();
          const arrLen = a.toArray().length;

          JSON.stringify({
            token,
            ogTitle,
            intro,
            contentOwn,
            removedAdEmpty,
            contentHtml,
            forInItems,
            forOfTitles,
            mapped,
            eachAttrRes,
            eachTextRes,
            forEachCount,
            flatMapped,
            secondChap,
            containsChap,
            notVipSize,
            eqFirst,
            lastText,
            getSecond,
            emptyCheck,
            firstFromSelect,
            byId,
            arrLen,
            len: a.length
          });
          ''',
          bindings: const <String, Object?>{'html': _sampleBookHtml},
        );

        expect(res.value, contains('"token":"tok_987654"'));
        expect(res.value, contains('"ogTitle":"凡人修仙传"'));
        expect(res.value, isNot(contains('广告：下载APP免费看')));
        expect(res.value, contains('山村穷小子'));
        expect(res.value, contains('开启修仙之路。'));
        expect(res.value, contains('"contentOwn":"正文第一段。正文结尾。"'));
        expect(res.value, contains('"removedAdEmpty":true'));
        expect(res.value, contains('"contentHtml":"<p class=\\"ad\\">关注公众号</p>"'));
        expect(
          res.value,
          contains(
            '"forInItems":["第一章 山边小村|/book/100/c1.html","第二章 青牛镇|/book/100/c2.html","Chapter Three: Trial|/book/100/c3.html"]',
          ),
        );
        expect(
          res.value,
          contains(
            '"mapped":["https://novel.example.com/book/100/c1.html","https://novel.example.com/book/100/c2.html","https://novel.example.com/book/100/c3.html"]',
          ),
        );
        expect(
          res.value,
          contains(
            '"eachAttrRes":["https://novel.example.com/book/100/c1.html","https://novel.example.com/book/100/c2.html","https://novel.example.com/book/100/c3.html"]',
          ),
        );
        expect(res.value, contains('"forEachCount":3'));
        expect(res.value, contains('"flatMapped":["凡人修仙传","开启修仙之路。"]'));
        expect(res.value, contains('"secondChap":"第二章 青牛镇"'));
        expect(res.value, contains('"containsChap":"/book/100/c2.html"'));
        expect(res.value, contains('"notVipSize":2'));
        expect(res.value, contains('"eqFirst":"第一章 山边小村"'));
        expect(res.value, contains('"lastText":"Chapter Three: Trial"'));
        expect(res.value, contains('"getSecond":"第二章 青牛镇"'));
        expect(res.value, contains('"emptyCheck":true'));
        expect(
          res.value,
          contains('"firstFromSelect":"https://novel.example.com/covers/fanren.jpg"'),
        );
        expect(res.value, contains('"byId":"凡人修仙传"'));
        expect(res.value, contains('"arrLen":3'));
        expect(res.value, contains('"len":3'));

        // Re-evaluating jsPrelude on the same QjsSandboxRuntime must be idempotent.
        final secondEval = await runtime.evaluate(
          '''
          ${LegadoJsoupBridge.jsPrelude}
          Jsoup.parse('<div class="ok">ready</div>').select('.ok').text();
          ''',
        );
        expect(secondEval.value, 'ready');
      } finally {
        bridge.dispose();
        await runtime.dispose();
      }
    });
  });
}
