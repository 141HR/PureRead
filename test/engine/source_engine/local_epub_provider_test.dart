import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/local_epub/local_epub.dart';

Uint8List _buildZipBytes(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

Uint8List _utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('pureread_epub_test_');
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('EpubPathUtils', () {
    test('normalizes POSIX paths, resolves relative ../ segments, and safely URL-decodes', () {
      expect(
        EpubPathUtils.normalizeArchivePath(r'/OEBPS\./Text/../Text/ch1.xhtml'),
        'OEBPS/Text/ch1.xhtml',
      );
      expect(
        EpubPathUtils.safeUrlDecode('100%_raw+file%20%E7%AC%AC1%E7%AB%A0.xhtml'),
        '100%_raw+file 第1章.xhtml',
      );

      final resolved = EpubPathUtils.resolveHref(
        'OEBPS/meta/content.opf',
        '../text/%E7%AC%AC%201%20%E7%AB%A0/ch%2B1.xhtml#sec%20a',
      );
      expect(resolved.archivePath, 'OEBPS/text/第 1 章/ch+1.xhtml');
      expect(resolved.fragment, 'sec a');
      expect(resolved.epubHref, 'OEBPS/text/第 1 章/ch+1.xhtml#sec a');
    });
  });

  group('EpubXhtmlExtractor', () {
    test('strips ignored tags, normalizes inline spacing, and preserves crisp block breaks', () {
      const html = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <title>Hidden Head Title</title>
    <style>p { color: red; }</style>
    <script>console.log("should not appear");</script>
  </head>
  <body>
    <noscript>Enable JS</noscript>
    <svg><text>SVG Noise</text></svg>
    <h1>  Chapter   One  </h1>
    <p>  First   <span>inline</span>\n\t<strong>words</strong>! </p>
    <div>Line one<br/>Line two</div>
    <blockquote>Quote paragraph</blockquote>
    <ul><li>Item A</li><li>Item B</li></ul>
    <table><tr><th>H1</th><th>H2</th></tr><tr><td>C1</td><td>C2</td></tr></table>
  </body>
</html>
''';

      final extracted = EpubXhtmlExtractor.extractText(_utf8Bytes(html));
      expect(extracted, isNot(contains('Hidden Head Title')));
      expect(extracted, isNot(contains('color: red')));
      expect(extracted, isNot(contains('should not appear')));
      expect(extracted, isNot(contains('Enable JS')));
      expect(extracted, isNot(contains('SVG Noise')));
      expect(
        extracted,
        'Chapter One\n'
        'First inline words!\n'
        'Line one\n'
        'Line two\n'
        'Quote paragraph\n'
        'Item A\n'
        'Item B\n'
        'H1 H2\n'
        'C1 C2',
      );
    });

    test('decodes UTF-8 BOM, UTF-16LE BOM, and declared GBK XHTML bytes', () {
      final utf8BomBytes = Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('<p>UTF8 BOM 内容</p>'),
      ]);
      expect(EpubXhtmlExtractor.extractText(utf8BomBytes), 'UTF8 BOM 内容');

      final utf16LeBytes = Uint8List.fromList(
        const Utf16Encoder().encodeUtf16Le('<p>UTF16LE 内容</p>', true),
      );
      expect(EpubXhtmlExtractor.extractText(utf16LeBytes), 'UTF16LE 内容');

      const gbkHtml =
          '<html><head><meta charset="gbk"/></head><body><p>GBK 中文段落。</p></body></html>';
      final gbkBytes = Uint8List.fromList(gbk.encode(gbkHtml));
      expect(EpubXhtmlExtractor.extractText(gbkBytes), 'GBK 中文段落。');
    });

    test('slices multi-anchor #fragment chapters cleanly without leaking subsequent sections', () {
      const multiChapterHtml = '''
<html>
  <body>
    <p>Prologue before first anchor.</p>
    <section id="s1">
      <h1>Section 1</h1>
      <p>First section body.</p>
    </section>
    <h2 id="s2">Section 2</h2>
    <p>Second section body.</p>
    <a name="s3"></a>
    <h3>Section 3</h3>
    <p>Third section body.</p>
    <h4><a id="s4">4.</a> Section Four</h4>
    <p>Fourth section body.</p>
  </body>
</html>
''';
      final bytes = _utf8Bytes(multiChapterHtml);

      expect(
        EpubXhtmlExtractor.extractText(bytes, stopFragment: 's1'),
        'Prologue before first anchor.',
      );
      expect(
        EpubXhtmlExtractor.extractText(
          bytes,
          fragment: 's1',
          stopFragments: const <String>['s2', 's3', 's4'],
        ),
        'Section 1\nFirst section body.',
      );
      expect(
        EpubXhtmlExtractor.extractText(
          bytes,
          fragment: 's2',
          stopFragments: const <String>['s3', 's4'],
        ),
        'Section 2\nSecond section body.',
      );
      expect(
        EpubXhtmlExtractor.extractText(
          bytes,
          fragment: 's3',
          stopFragments: const <String>['s4'],
        ),
        'Section 3\nThird section body.',
      );
      expect(
        EpubXhtmlExtractor.extractText(bytes, fragment: 's4'),
        '4. Section Four\nFourth section body.',
      );

      // Self-closing XHTML anchors (<a id="..."/>) must also slice cleanly.
      const selfClosingAnchors = '''
<html>
  <body>
    <a id="a1" />
    <p>Anchor One Text</p>
    <a id="a2" />
    <p>Anchor Two Text</p>
  </body>
</html>
''';
      final scBytes = _utf8Bytes(selfClosingAnchors);
      expect(
        EpubXhtmlExtractor.extractText(
          scBytes,
          fragment: 'a1',
          stopFragment: 'a2',
        ),
        'Anchor One Text',
      );
      expect(
        EpubXhtmlExtractor.extractText(scBytes, fragment: 'a2'),
        'Anchor Two Text',
      );
    });
  });

  group('LocalEpubProvider', () {
    late LocalEpubProvider provider;

    setUp(() {
      provider = LocalEpubProvider();
    });

    test('exposes exact localEpub BookProvider capabilities and handles search & cancellation', () async {
      expect(provider.providerId, 'local_epub');
      expect(provider.type, ProviderType.localEpub);
      expect(
        provider.capabilities,
        const ProviderCapabilities(
          isLocal: true,
          supportsSearch: false,
          supportsUpdateCheck: false,
          supportsChangeSource: false,
        ),
      );

      final searchRes = await provider.search('keyword');
      expect(searchRes.items, isEmpty);
      expect(searchRes.trace.step, 'search');

      final cancelled = CancellationToken()..cancel();
      await expectLater(
        () => provider.importEpubFile(
          '${tmpDir.path}${Platform.pathSeparator}any.epub',
          cancelToken: cancelled,
        ),
        throwsA(isA<CancelledFailure>()),
      );
    });

    test('parses EPUB 2 with nested NCX navPoints, meta[name=cover], and cover saving', () async {
      final pngCover = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];
      final epubBytes = _buildZipBytes(<String, List<int>>{
        'mimetype': _utf8Bytes('application/epub+zip'),
        'META-INF/container.xml': _utf8Bytes('''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
        'OEBPS/content.opf': _utf8Bytes('''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>EPUB Two Chronicle</dc:title>
    <dc:creator>Author One</dc:creator>
    <dc:creator>Author Two</dc:creator>
    <dc:description>&lt;p&gt;An epic EPUB 2 novel.&lt;/p&gt;</dc:description>
    <dc:language>zh-CN</dc:language>
    <meta content="cover-image-id" name="cover"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="cover-image-id" href="images/cover.png" media-type="image/png"/>
    <item id="v1" href="text/vol1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="v2" href="text/vol2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="v1"/>
    <itemref idref="c1"/>
    <itemref idref="v2"/>
  </spine>
</package>
'''),
        'OEBPS/toc.ncx': _utf8Bytes('''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>Volume I</text></navLabel>
      <content src="text/vol1.xhtml"/>
      <navPoint id="np2" playOrder="2">
        <navLabel><text>Chapter 1</text></navLabel>
        <content src="text/ch1.xhtml"/>
      </navPoint>
      <navPoint id="np3" playOrder="3">
        <navLabel><text>Chapter 2</text></navLabel>
        <content src="text/ch1.xhtml#part2"/>
      </navPoint>
    </navPoint>
    <navPoint id="np4" playOrder="4">
      <navLabel><text>Volume II</text></navLabel>
      <content src="text/vol2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
'''),
        'OEBPS/images/cover.png': pngCover,
        'OEBPS/text/vol1.xhtml': _utf8Bytes('<html><body><h1>Volume I</h1><p>Intro 1</p></body></html>'),
        'OEBPS/text/ch1.xhtml': _utf8Bytes('''
<html>
  <head><style>.x{display:none}</style></head>
  <body>
    <h1>Chapter 1</h1>
    <p>Opening scene.</p>
    <h2 id="part2">Chapter 2</h2>
    <p>Second part content.</p>
  </body>
</html>
'''),
        'OEBPS/text/vol2.xhtml': _utf8Bytes('<html><body><h1>Volume II</h1><p>Final book.</p></body></html>'),
      });

      final epubFile = File('${tmpDir.path}${Platform.pathSeparator}epub2_nested.epub');
      await epubFile.writeAsBytes(epubBytes);
      final coversDir = Directory('${tmpDir.path}${Platform.pathSeparator}covers');

      final imported = await provider.importEpubFile(
        epubFile.path,
        coverSaveDir: coversDir.path,
      );

      expect(imported.book.providerType, ProviderType.localEpub);
      expect(imported.book.title, 'EPUB Two Chronicle');
      expect(imported.book.author, 'Author One, Author Two');
      expect(imported.book.intro, 'An epic EPUB 2 novel.');
      expect(imported.book.localFilePath, epubFile.path);
      expect(imported.book.fileEncoding, 'UTF-8');
      expect(imported.book.fileSizeBytes, epubBytes.length);
      expect(imported.book.fileHash, isNotEmpty);
      expect(imported.book.totalChapters, 4);
      expect(imported.book.lastChapterTitle, 'Volume II');
      expect(imported.coverExtension, '.png');
      expect(imported.coverBytes, Uint8List.fromList(pngCover));
      expect(imported.book.coverPath, isNotNull);
      expect(await File(imported.book.coverPath!).readAsBytes(), pngCover);

      expect(
        imported.chapters.map((c) => c.title).toList(),
        const <String>['Volume I', 'Chapter 1', 'Chapter 2', 'Volume II'],
      );
      expect(
        imported.chapters.map((c) => c.epubHref).toList(),
        const <String>[
          'OEBPS/text/vol1.xhtml',
          'OEBPS/text/ch1.xhtml',
          'OEBPS/text/ch1.xhtml#part2',
          'OEBPS/text/vol2.xhtml',
        ],
      );

      final ch1Text = await provider.readChapterText(
        filePath: epubFile.path,
        chapter: imported.chapters[1],
      );
      expect(ch1Text, 'Chapter 1\nOpening scene.');

      final ch2Text = await provider.readChapterText(
        filePath: epubFile.path,
        chapter: imported.chapters[2],
      );
      expect(ch2Text, 'Chapter 2\nSecond part content.');

      // Deterministic fileHash check on re-import.
      final reimported = await provider.importEpubFile(epubFile.path);
      expect(reimported.book.id, imported.book.id);
      expect(reimported.book.fileHash, imported.book.fileHash);
      expect(reimported.book.coverPath, isNull);
    });

    test('parses EPUB 3 preferring NAV over NCX, cover-image property, and multi-anchor single-XHTML split', () async {
      final jpgCover = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46];
      final epubBytes = _buildZipBytes(<String, List<int>>{
        'META-INF/container.xml': _utf8Bytes('''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
        'OPS/package.opf': _utf8Bytes('''
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>EPUB Three Guide</dc:title>
    <dc:creator>Modern Author</dc:creator>
    <dc:description>NAV &amp; Multi-anchor test.</dc:description>
  </metadata>
  <manifest>
    <item id="nav" href="nav/toc.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="cover" href="media/cover.jpg" media-type="image/jpeg" properties="cover-image svg"/>
    <item id="story" href="text/story.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="story"/>
  </spine>
</package>
'''),
        'OPS/nav/toc.xhtml': _utf8Bytes('''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <nav epub:type="landmarks">
      <ol><li><a href="../text/story.xhtml#s1">Start</a></li></ol>
    </nav>
    <nav epub:type="toc">
      <ol>
        <li>
          <a href="../text/story.xhtml#s1">Part Alpha</a>
          <ol>
            <li><a href="../text/story.xhtml#s2">Part Beta</a></li>
          </ol>
        </li>
        <li><span>Group Header Without Href</span>
          <ol>
            <li><a href="../text/story.xhtml#s3">Part Gamma</a></li>
          </ol>
        </li>
      </ol>
    </nav>
  </body>
</html>
'''),
        'OPS/toc.ncx': _utf8Bytes('''
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="old1"><navLabel><text>Old NCX Entry</text></navLabel><content src="text/story.xhtml"/></navPoint>
  </navMap>
</ncx>
'''),
        'OPS/media/cover.jpg': jpgCover,
        'OPS/text/story.xhtml': _utf8Bytes('''
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <section id="s1">
      <h1>Part Alpha</h1>
      <p>Alpha content line.</p>
    </section>
    <h2 id="s2">Part Beta</h2>
    <p>Beta content line.</p>
    <a name="s3"></a>
    <h3>Part Gamma</h3>
    <p>Gamma content line.</p>
  </body>
</html>
'''),
      });

      final epubFile = File('${tmpDir.path}${Platform.pathSeparator}epub3_nav.epub');
      await epubFile.writeAsBytes(epubBytes);

      final imported = await provider.importEpubFile(epubFile.path);
      expect(imported.book.title, 'EPUB Three Guide');
      expect(imported.book.author, 'Modern Author');
      expect(imported.book.intro, 'NAV & Multi-anchor test.');
      expect(imported.coverExtension, '.jpg');
      expect(imported.coverBytes, Uint8List.fromList(jpgCover));

      // NAV preferred over NCX; landmarks ignored; span-only li skipped.
      expect(
        imported.chapters.map((c) => c.title).toList(),
        const <String>['Part Alpha', 'Part Beta', 'Part Gamma'],
      );
      expect(
        imported.chapters.map((c) => c.epubHref).toList(),
        const <String>[
          'OPS/text/story.xhtml#s1',
          'OPS/text/story.xhtml#s2',
          'OPS/text/story.xhtml#s3',
        ],
      );

      // Fresh provider (cold cache) reading single ChapterMeta still slices cleanly!
      final freshProvider = LocalEpubProvider();
      expect(
        await freshProvider.readChapterText(
          filePath: epubFile.path,
          chapter: imported.chapters[0],
        ),
        'Part Alpha\nAlpha content line.',
      );
      expect(
        await freshProvider.readChapterText(
          filePath: epubFile.path,
          chapter: imported.chapters[1],
        ),
        'Part Beta\nBeta content line.',
      );
      expect(
        await freshProvider.readChapterText(
          filePath: epubFile.path,
          chapter: imported.chapters[2],
        ),
        'Part Gamma\nGamma content line.',
      );
    });

    test('falls back to .opf scan when container.xml is absent or malformed, spine-only TOC, and fallback cover', () async {
      final webpCover = <int>[
        0x52, 0x49, 0x46, 0x46, 12, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x20,
      ];
      final epubBytes = _buildZipBytes(<String, List<int>>{
        'META-INF/container.xml': _utf8Bytes('<broken><xml'),
        'book/package.opf': _utf8Bytes('''
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Spine Fallback Book</dc:title>
  </metadata>
  <manifest>
    <item id="cover" href="art/cover.webp" media-type="image/webp"/>
    <item id="preface" href="pages/preface.xhtml" media-type="application/xhtml+xml"/>
    <item id="p1" href="pages/p1.xhtml" media-type="application/xhtml+xml"/>
    <item id="p2" href="pages/p2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="preface" linear="no"/>
    <itemref idref="p1"/>
    <itemref idref="p2"/>
  </spine>
</package>
'''),
        'book/art/cover.webp': webpCover,
        'book/pages/preface.xhtml': _utf8Bytes('<html><body><p>Copyright notice</p></body></html>'),
        'book/pages/p1.xhtml': _utf8Bytes('<html><body><h1>Spine First</h1><p>Body 1</p></body></html>'),
        'book/pages/p2.xhtml': _utf8Bytes('<html><head><title>Spine Second</title></head><body><p>Body 2</p></body></html>'),
      });

      final epubFile = File('${tmpDir.path}${Platform.pathSeparator}spine_fallback.epub');
      await epubFile.writeAsBytes(epubBytes);

      final imported = await provider.importEpubFile(epubFile.path);
      expect(imported.book.title, 'Spine Fallback Book');
      expect(imported.coverExtension, '.webp');
      expect(imported.coverBytes, Uint8List.fromList(webpCover));
      expect(imported.chapters.length, 2);
      expect(imported.chapters[0].title, 'Spine First');
      expect(imported.chapters[0].epubHref, 'book/pages/p1.xhtml');
      expect(imported.chapters[1].title, 'Spine Second');
      expect(imported.chapters[1].epubHref, 'book/pages/p2.xhtml');

      expect(
        await provider.readChapterText(
          filePath: epubFile.path,
          chapter: imported.chapters[1],
        ),
        'Body 2',
      );

      // Absent container.xml + empty dc:title falls back to .opf scan & filename.
      final noContainerBytes = _buildZipBytes(<String, List<int>>{
        'nested/only.opf': _utf8Bytes('''
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"></metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>
'''),
        'nested/toc.ncx': _utf8Bytes('''
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1"><navLabel><text>NCX Without Spine Attr</text></navLabel><content src="ch1.xhtml"/></navPoint>
  </navMap>
</ncx>
'''),
        'nested/ch1.xhtml': _utf8Bytes('<html><body><p>Hello NCX fallback</p></body></html>'),
      });
      final noContainerFile = File('${tmpDir.path}${Platform.pathSeparator}no_container_fallback.epub');
      await noContainerFile.writeAsBytes(noContainerBytes);
      final noContainerImported = await provider.importEpubFile(noContainerFile.path);
      expect(noContainerImported.book.title, 'no_container_fallback');
      expect(noContainerImported.chapters.length, 1);
      expect(noContainerImported.chapters.first.title, 'NCX Without Spine Attr');
      expect(
        await provider.readChapterText(
          filePath: noContainerFile.path,
          chapter: noContainerImported.chapters.first,
        ),
        'Hello NCX fallback',
      );
    });

    test('handles URL-encoded subdir paths and BookProvider detail/toc/content contract', () async {
      final epubBytes = _buildZipBytes(<String, List<int>>{
        'META-INF/container.xml': _utf8Bytes('''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/meta/my%20book.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
        'OEBPS/meta/my book.opf': _utf8Bytes('''
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Encoded Subdir Book</dc:title>
    <dc:creator>Path Tester</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="../nav/nav%20main.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="../chapters/%E7%AC%AC%201%20%E7%AB%A0/ch%2B1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>
'''),
        'OEBPS/nav/nav main.xhtml': _utf8Bytes('''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="../chapters/%E7%AC%AC%201%20%E7%AB%A0/ch%2B1.xhtml#sec%201">Encoded Chapter 1</a></li>
      </ol>
    </nav>
  </body>
</html>
'''),
        'OEBPS/chapters/第 1 章/ch+1.xhtml': _utf8Bytes('''
<html><body><div id="sec 1"><p>Decoded path success!</p></div></body></html>
'''),
      });

      final epubFile = File('${tmpDir.path}${Platform.pathSeparator}encoded_paths.epub');
      await epubFile.writeAsBytes(epubBytes);

      final detailRes = await provider.getBookDetail(epubFile.path);
      expect(detailRes.detail.title, 'Encoded Subdir Book');
      expect(detailRes.detail.author, 'Path Tester');
      expect(detailRes.trace.step, 'detail');

      final tocRes = await provider.getToc(epubFile.path);
      expect(tocRes.chapters.length, 1);
      expect(tocRes.chapters.first.epubHref, 'OEBPS/chapters/第 1 章/ch+1.xhtml#sec 1');
      expect(tocRes.trace.step, 'toc');

      final contentRes = await provider.getChapterContent(tocRes.chapters.first);
      expect(contentRes.content.rawText, 'Decoded path success!');
      expect(contentRes.trace.step, 'content');

      // Works on a fresh provider instance when chapter.url is supplied.
      final freshProvider = LocalEpubProvider();
      final viaUrlRes = await freshProvider.getChapterContent(
        tocRes.chapters.first.copyWith(url: epubFile.path),
      );
      expect(viaUrlRes.content.rawText, 'Decoded path success!');
    });

    test('maps missing files to FileAccessFailure and corrupt ZIPs or missing OPF/spine to SourceParseFailure', () async {
      final missingPath = '${tmpDir.path}${Platform.pathSeparator}nonexistent.epub';
      await expectLater(
        () => provider.importEpubFile(missingPath),
        throwsA(isA<FileAccessFailure>()),
      );
      await expectLater(
        () => provider.readChapterText(
          filePath: missingPath,
          chapter: ChapterMeta(
            bookId: 'b',
            chapterIndex: 0,
            title: 'ch0',
            epubHref: 'ch0.xhtml',
            updatedAt: DateTime.utc(2026, 11, 25),
          ),
        ),
        throwsA(isA<FileAccessFailure>()),
      );

      // Directory instead of file -> FileAccessFailure
      await expectLater(
        () => provider.importEpubFile(tmpDir.path),
        throwsA(isA<FileAccessFailure>()),
      );

      // Corrupted / non-ZIP file -> SourceParseFailure
      final corruptZip = File('${tmpDir.path}${Platform.pathSeparator}corrupt.epub');
      await corruptZip.writeAsBytes(const <int>[0x50, 0x4B, 0x00, 0xFF, 0x12, 0x34]);
      await expectLater(
        () => provider.importEpubFile(corruptZip.path),
        throwsA(isA<SourceParseFailure>()),
      );

      // Valid ZIP without any OPF -> SourceParseFailure
      final noOpfZip = File('${tmpDir.path}${Platform.pathSeparator}no_opf.epub');
      await noOpfZip.writeAsBytes(
        _buildZipBytes(<String, List<int>>{'hello.txt': _utf8Bytes('not an epub')}),
      );
      await expectLater(
        () => provider.importEpubFile(noOpfZip.path),
        throwsA(isA<SourceParseFailure>()),
      );

      // Valid ZIP with OPF missing <spine> -> SourceParseFailure
      final noSpineZip = File('${tmpDir.path}${Platform.pathSeparator}no_spine.epub');
      await noSpineZip.writeAsBytes(
        _buildZipBytes(<String, List<int>>{
          'META-INF/container.xml': _utf8Bytes('''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
'''),
          'content.opf': _utf8Bytes('''
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>No Spine</dc:title></metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
</package>
'''),
          'c1.xhtml': _utf8Bytes('<p>Text</p>'),
        }),
      );
      await expectLater(
        () => provider.importEpubFile(noSpineZip.path),
        throwsA(isA<SourceParseFailure>()),
      );

      // Valid ZIP with empty <spine/> -> SourceParseFailure
      final emptySpineZip = File('${tmpDir.path}${Platform.pathSeparator}empty_spine.epub');
      await emptySpineZip.writeAsBytes(
        _buildZipBytes(<String, List<int>>{
          'content.opf': _utf8Bytes('''
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Empty Spine</dc:title></metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine/>
</package>
'''),
          'c1.xhtml': _utf8Bytes('<p>Text</p>'),
        }),
      );
      await expectLater(
        () => provider.importEpubFile(emptySpineZip.path),
        throwsA(isA<SourceParseFailure>()),
      );

      // Chapter entry missing inside otherwise valid EPUB -> SourceParseFailure
      final validEpub = File('${tmpDir.path}${Platform.pathSeparator}missing_entry.epub');
      await validEpub.writeAsBytes(
        _buildZipBytes(<String, List<int>>{
          'content.opf': _utf8Bytes('''
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Missing Entry</dc:title></metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="c1"/></spine>
</package>
'''),
          'c1.xhtml': _utf8Bytes('<p>Present</p>'),
        }),
      );
      await expectLater(
        () => provider.readChapterText(
          filePath: validEpub.path,
          chapter: ChapterMeta(
            bookId: 'b',
            chapterIndex: 0,
            title: 'missing',
            epubHref: 'does_not_exist.xhtml',
            updatedAt: DateTime.utc(2026, 11, 25),
          ),
        ),
        throwsA(isA<SourceParseFailure>()),
      );
    });
  });
}
