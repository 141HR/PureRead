import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/reader_engine.dart';
import 'package:pureread/engine/source_engine/local_epub/local_epub.dart';
import 'package:pureread/engine/source_engine/sanitizer/sanitizer.dart';

Uint8List _buildZipBytes(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _fakePngHeader(int width, int height) {
  final bd = ByteData(24);
  const sig = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < sig.length; i++) {
    bd.setUint8(i, sig[i]);
  }
  bd.setUint32(8, 13, Endian.big);
  // 'IHDR'
  bd.setUint8(12, 0x49);
  bd.setUint8(13, 0x48);
  bd.setUint8(14, 0x44);
  bd.setUint8(15, 0x52);
  bd.setUint32(16, width, Endian.big);
  bd.setUint32(20, height, Endian.big);
  return bd.buffer.asUint8List();
}

Uint8List _fakeGifHeader(int width, int height, {bool gif87a = false}) {
  final out = Uint8List(10);
  final sig = gif87a ? 'GIF87a' : 'GIF89a';
  for (var i = 0; i < 6; i++) {
    out[i] = sig.codeUnitAt(i);
  }
  out[6] = width & 0xFF;
  out[7] = (width >> 8) & 0xFF;
  out[8] = height & 0xFF;
  out[9] = (height >> 8) & 0xFF;
  return out;
}

Uint8List _fakeJpegWithSof(
  int width,
  int height, {
  int sofMarker = 0xC0,
  bool includeExifThumbnail = false,
}) {
  final bytes = <int>[0xFF, 0xD8];
  if (includeExifThumbnail) {
    // APP1 segment containing an embedded thumbnail SOF0 (64x48) that must be
    // skipped cleanly by segment length rather than parsed as the main image.
    final app1Payload = <int>[
      0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // Exif\0\0
      0xFF, 0xD8,
      0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x30, 0x00, 0x40, 0x03, 1, 2, 3,
      0xFF, 0xD9,
    ];
    final len = app1Payload.length + 2;
    bytes.addAll(<int>[0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF]);
    bytes.addAll(app1Payload);
  }
  // Padding 0xFF before SOF marker
  bytes.addAll(<int>[
    0xFF,
    0xFF,
    sofMarker,
    0x00,
    0x0B,
    0x08,
    (height >> 8) & 0xFF,
    height & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    0x03,
    1,
    2,
    3,
    0xFF,
    0xDA,
    0x00,
    0x04,
    0x00,
    0x00,
    0xFF,
    0xD9,
  ]);
  return Uint8List.fromList(bytes);
}

Uint8List _fakeWebpVp8(int width, int height) {
  final bd = ByteData(30);
  // 'RIFF' ... 'WEBP' 'VP8 '
  bd.setUint8(0, 0x52);
  bd.setUint8(1, 0x49);
  bd.setUint8(2, 0x46);
  bd.setUint8(3, 0x46);
  bd.setUint32(4, 22, Endian.little);
  bd.setUint8(8, 0x57);
  bd.setUint8(9, 0x45);
  bd.setUint8(10, 0x42);
  bd.setUint8(11, 0x50);
  bd.setUint8(12, 0x56);
  bd.setUint8(13, 0x50);
  bd.setUint8(14, 0x38);
  bd.setUint8(15, 0x20);
  bd.setUint32(16, 10, Endian.little);
  // Keyframe bit 0 = 0 + sync code 9D 01 2A
  bd.setUint8(20, 0x00);
  bd.setUint8(23, 0x9D);
  bd.setUint8(24, 0x01);
  bd.setUint8(25, 0x2A);
  bd.setUint16(26, width & 0x3FFF, Endian.little);
  bd.setUint16(28, height & 0x3FFF, Endian.little);
  return bd.buffer.asUint8List();
}

Uint8List _fakeWebpVp8L(int width, int height) {
  final bd = ByteData(25);
  bd.setUint8(0, 0x52);
  bd.setUint8(1, 0x49);
  bd.setUint8(2, 0x46);
  bd.setUint8(3, 0x46);
  bd.setUint32(4, 17, Endian.little);
  bd.setUint8(8, 0x57);
  bd.setUint8(9, 0x45);
  bd.setUint8(10, 0x42);
  bd.setUint8(11, 0x50);
  bd.setUint8(12, 0x56);
  bd.setUint8(13, 0x50);
  bd.setUint8(14, 0x38);
  bd.setUint8(15, 0x4C);
  bd.setUint32(16, 5, Endian.little);
  bd.setUint8(20, 0x2F);
  final packed = ((width - 1) & 0x3FFF) | (((height - 1) & 0x3FFF) << 14);
  bd.setUint32(21, packed, Endian.little);
  return bd.buffer.asUint8List();
}

Uint8List _fakeWebpVp8X(int width, int height, {bool withPrecedingChunk = false}) {
  final extra = withPrecedingChunk ? 10 : 0;
  final bd = ByteData(30 + extra);
  bd.setUint8(0, 0x52);
  bd.setUint8(1, 0x49);
  bd.setUint8(2, 0x46);
  bd.setUint8(3, 0x46);
  bd.setUint32(4, 22 + extra, Endian.little);
  bd.setUint8(8, 0x57);
  bd.setUint8(9, 0x45);
  bd.setUint8(10, 0x42);
  bd.setUint8(11, 0x50);
  var offset = 12;
  if (withPrecedingChunk) {
    // Unknown odd-sized chunk ('ICCP', size 1 -> padded to 2 bytes)
    bd.setUint8(offset, 0x49);
    bd.setUint8(offset + 1, 0x43);
    bd.setUint8(offset + 2, 0x43);
    bd.setUint8(offset + 3, 0x50);
    bd.setUint32(offset + 4, 1, Endian.little);
    offset += 10;
  }
  bd.setUint8(offset, 0x56);
  bd.setUint8(offset + 1, 0x50);
  bd.setUint8(offset + 2, 0x38);
  bd.setUint8(offset + 3, 0x58);
  bd.setUint32(offset + 4, 10, Endian.little);
  final w = width - 1;
  final h = height - 1;
  bd.setUint8(offset + 12, w & 0xFF);
  bd.setUint8(offset + 13, (w >> 8) & 0xFF);
  bd.setUint8(offset + 14, (w >> 16) & 0xFF);
  bd.setUint8(offset + 15, h & 0xFF);
  bd.setUint8(offset + 16, (h >> 8) & 0xFF);
  bd.setUint8(offset + 17, (h >> 16) & 0xFF);
  return bd.buffer.asUint8List();
}

Uint8List _fakeBmp(int width, int height, {bool coreHeader12 = false}) {
  if (coreHeader12) {
    final bd = ByteData(26);
    bd.setUint8(0, 0x42);
    bd.setUint8(1, 0x4D);
    bd.setUint32(14, 12, Endian.little);
    bd.setUint16(18, width, Endian.little);
    bd.setUint16(20, height, Endian.little);
    return bd.buffer.asUint8List();
  }
  final bd = ByteData(54);
  bd.setUint8(0, 0x42);
  bd.setUint8(1, 0x4D);
  bd.setUint32(14, 40, Endian.little);
  bd.setInt32(18, width, Endian.little);
  bd.setInt32(22, height, Endian.little);
  return bd.buffer.asUint8List();
}

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('pureread_epub_images_');
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('InlineImageMarker', () {
    test('roundtrips encoded markers including special characters and padding', () {
      final encoded = InlineImageMarker.encode(
        archivePath: r'/OEBPS\Images\插图 01|a%b.jpg',
        width: 1024,
        height: 768,
        alt: '第一张\n插图 | 100%',
      );

      expect(encoded.startsWith(InlineImageMarker.prefix), isTrue);
      expect(encoded.endsWith(InlineImageMarker.suffix), isTrue);
      expect(encoded.contains('\n'), isFalse);

      final parsed = InlineImageMarker.tryParseLine('  $encoded\r\n');
      expect(
        parsed,
        const InlineImageRef(
          archivePath: 'OEBPS/Images/插图 01|a%b.jpg',
          width: 1024,
          height: 768,
          alt: '第一张 插图 | 100%',
        ),
      );
      expect(InlineImageMarker.isImageLine(encoded), isTrue);

      final unknownDims = InlineImageMarker.encode(
        archivePath: 'images/cover.png',
        width: -5,
        height: -1,
      );
      expect(
        InlineImageMarker.tryParseLine(unknownDims),
        const InlineImageRef(
          archivePath: 'images/cover.png',
          width: 0,
          height: 0,
          alt: '',
        ),
      );
    });

    test('rejects plain text, malformed payloads, and concatenated markers', () {
      expect(InlineImageMarker.tryParseLine('plain text'), isNull);
      expect(InlineImageMarker.tryParseLine('${InlineImageMarker.prefix}${InlineImageMarker.suffix}'), isNull);
      expect(InlineImageMarker.tryParseLine('\uFFFCprimg:v1:a.png|10x20\uFFFC'), isNull);
      expect(InlineImageMarker.tryParseLine('\uFFFCprimg:v1:|10x20|\uFFFC'), isNull);
      expect(InlineImageMarker.tryParseLine('\uFFFCprimg:v1:a.png|-1x20|\uFFFC'), isNull);
      expect(InlineImageMarker.tryParseLine('\uFFFCprimg:v1:a.png|axb|\uFFFC'), isNull);
      expect(InlineImageMarker.tryParseLine('\uFFFCprimg:v1:%ZZ|10x20|\uFFFC'), isNull);

      final single = InlineImageMarker.encode(archivePath: 'a.png', width: 10, height: 10);
      expect(InlineImageMarker.tryParseLine('$single$single'), isNull);
      expect(InlineImageMarker.isImageLine('hello $single'), isFalse);
    });

    test('stripMarkers removes marker lines and collapses extra blank lines cleanly', () {
      final m1 = InlineImageMarker.encode(archivePath: 'OEBPS/1.png', width: 800, height: 600);
      final m2 = InlineImageMarker.encode(archivePath: 'OEBPS/2.jpg', width: 400, height: 300);

      expect(
        InlineImageMarker.stripMarkers('第一段\n$m1\n第二段'),
        '第一段\n第二段',
      );
      expect(
        InlineImageMarker.stripMarkers('$m1\n\n第一段\n\n$m2\n\n第二段\n\n$m1'),
        '第一段\n\n第二段',
      );
      expect(InlineImageMarker.stripMarkers('$m1\n$m2'), '');
      expect(InlineImageMarker.stripMarkers('无图文本\n\n第二段'), '无图文本\n\n第二段');
    });
  });

  group('EpubImageProbe', () {
    test('parses PNG, JPEG (all SOF markers + EXIF skip), GIF, WebP, and BMP headers', () {
      expect(
        EpubImageProbe.probeDimensions(_fakePngHeader(1280, 720)),
        (width: 1280, height: 720),
      );
      expect(
        EpubImageProbe.probeDimensions(_fakeGifHeader(320, 240, gif87a: true)),
        (width: 320, height: 240),
      );
      expect(
        EpubImageProbe.probeDimensions(_fakeGifHeader(640, 480)),
        (width: 640, height: 480),
      );

      for (final sof in const <int>[
        0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
        0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
      ]) {
        expect(
          EpubImageProbe.probeDimensions(
            _fakeJpegWithSof(1024, 1536, sofMarker: sof, includeExifThumbnail: true),
          ),
          (width: 1024, height: 1536),
          reason: 'SOF marker 0x${sof.toRadixString(16)}',
        );
      }

      expect(
        EpubImageProbe.probeDimensions(_fakeWebpVp8(640, 480)),
        (width: 640, height: 480),
      );
      expect(
        EpubImageProbe.probeDimensions(_fakeWebpVp8L(512, 256)),
        (width: 512, height: 256),
      );
      expect(
        EpubImageProbe.probeDimensions(
          _fakeWebpVp8X(1920, 1080, withPrecedingChunk: true),
        ),
        (width: 1920, height: 1080),
      );

      expect(
        EpubImageProbe.probeDimensions(_fakeBmp(800, 600)),
        (width: 800, height: 600),
      );
      expect(
        EpubImageProbe.probeDimensions(_fakeBmp(800, -600)),
        (width: 800, height: 600),
      );
      expect(
        EpubImageProbe.probeDimensions(_fakeBmp(256, 128, coreHeader12: true)),
        (width: 256, height: 128),
      );
    });

    test('guards short, zero-dimension, and malformed buffers safely', () {
      expect(EpubImageProbe.probeDimensions(Uint8List(0)), isNull);
      expect(EpubImageProbe.probeDimensions(Uint8List(9)), isNull);
      expect(EpubImageProbe.probeDimensions(_fakePngHeader(0, 100)), isNull);
      expect(EpubImageProbe.probeDimensions(_fakePngHeader(100, 100).sublist(0, 20)), isNull);
      expect(EpubImageProbe.probeDimensions(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x02])), isNull);
      expect(EpubImageProbe.probeDimensions(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xC0])), isNull);
      expect(EpubImageProbe.probeDimensions(_fakeWebpVp8(640, 480).sublist(0, 22)), isNull);
      expect(EpubImageProbe.probeDimensions(_fakeBmp(100, 100).sublist(0, 20)), isNull);
      expect(EpubImageProbe.probeDimensions(_utf8Bytes('not an image payload')), isNull);
    });
  });

  group('EpubXhtmlExtractor inline image extraction', () {
    test('emits markers only when onImage is provided and suppresses SVG text noise', () {
      const html = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:xlink="http://www.w3.org/1999/xlink">
  <body>
    <svg viewBox="0 0 100 100">
      <text>SVG Noise</text>
      <g><image xlink:href="../images/svg_pic.jpg" alt="SVG Fig"/></g>
    </svg>
    <p>Lead text <img src="images/inline.png" alt="Inline"/> trail text</p>
    <p><img src="data:image/gif;base64,R0lGODlh" data-src="images/lazy.webp" alt="Lazy"/></p>
    <p>Keep <img src="https://skip.example.com/a.png"/> unbroken</p>
  </body>
</html>
''';

      final withoutCallback = EpubXhtmlExtractor.extractTextFromHtml(html);
      expect(withoutCallback, isNot(contains('SVG Noise')));
      expect(withoutCallback, isNot(contains(InlineImageMarker.prefix)));
      expect(
        withoutCallback,
        'Lead text trail text\nKeep unbroken',
      );

      final withCallback = EpubXhtmlExtractor.extractTextFromHtml(
        html,
        onImage: (rawSrc, alt) {
          if (rawSrc.startsWith('https://')) return null;
          return InlineImageMarker.encode(
            archivePath: rawSrc,
            width: 100,
            height: 80,
            alt: alt,
          );
        },
      );
      expect(withCallback, isNot(contains('SVG Noise')));
      final lines = withCallback.split('\n');
      expect(lines.length, 6);
      expect(
        InlineImageMarker.tryParseLine(lines[0]),
        const InlineImageRef(
          archivePath: '../images/svg_pic.jpg',
          width: 100,
          height: 80,
          alt: 'SVG Fig',
        ),
      );
      expect(lines[1], 'Lead text');
      expect(
        InlineImageMarker.tryParseLine(lines[2]),
        const InlineImageRef(
          archivePath: 'images/inline.png',
          width: 100,
          height: 80,
          alt: 'Inline',
        ),
      );
      expect(lines[3], 'trail text');
      expect(
        InlineImageMarker.tryParseLine(lines[4]),
        const InlineImageRef(
          archivePath: 'images/lazy.webp',
          width: 100,
          height: 80,
          alt: 'Lazy',
        ),
      );
      expect(lines[5], 'Keep unbroken');
    });

    test('respects multi-anchor fragment slicing for images too', () {
      const html = '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <h1 id="s1">S1</h1>
    <p><img src="s1.png" alt="First"/></p>
    <h1 id="s2">S2</h1>
    <p><img src="s2.png" alt="Second"/></p>
  </body>
</html>
''';
      final slice = EpubXhtmlExtractor.extractTextFromHtml(
        html,
        fragment: 's1',
        stopFragment: 's2',
        onImage: (src, alt) => InlineImageMarker.encode(archivePath: src, alt: alt),
      );
      expect(slice, contains('s1.png'));
      expect(slice, isNot(contains('s2.png')));
    });
  });

  group('EpubContainerParser & LocalEpubProvider inline image pipeline', () {
    test('extracts relative images with probed dimensions, skips external/missing/svg, and reads entry bytes', () async {
      final pngBytes = _fakePngHeader(800, 600);
      final jpgBytes = _fakeJpegWithSof(1024, 1536, sofMarker: 0xC2);
      final svgBytes = _utf8Bytes('<svg xmlns="http://www.w3.org/2000/svg"/>');

      final epubBytes = _buildZipBytes(<String, List<int>>{
        'META-INF/container.xml': _utf8Bytes('''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
        'OEBPS/content.opf': _utf8Bytes('''
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Illustrated EPUB</dc:title>
  </metadata>
  <manifest>
    <item id="c1" href="Text/ch%201.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>
'''),
        'OEBPS/Text/ch 1.xhtml': _utf8Bytes('''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:xlink="http://www.w3.org/1999/xlink">
  <body>
    <h1>Chapter 1</h1>
    <p><img src="../Images/fig%201.png" alt="Diagram 1"/></p>
    <svg><text>SVG Noise</text><image xlink:href="../Images/plate.jpg"/></svg>
    <p><img src="../Images/vector.svg" alt="Skip SVG"/></p>
    <p><img src="../Images/missing.jpg" alt="Skip Missing"/></p>
    <p><img src="https://example.com/a.jpg" alt="Skip HTTP"/></p>
    <p><img src="data:image/png;base64,AAAA" alt="Skip Data"/></p>
    <p>Closing paragraph.</p>
  </body>
</html>
'''),
        'OEBPS/Images/fig 1.png': pngBytes,
        'OEBPS/Images/plate.jpg': jpgBytes,
        'OEBPS/Images/vector.svg': svgBytes,
      });

      final epubFile = File('${tmpDir.path}${Platform.pathSeparator}illustrated.epub');
      await epubFile.writeAsBytes(epubBytes);

      final provider = LocalEpubProvider();
      final imported = await provider.importEpubFile(epubFile.path);
      final chapterText = await provider.readChapterText(
        filePath: epubFile.path,
        chapter: imported.chapters.single,
      );

      final lines = chapterText.split('\n');
      expect(lines.length, 4);
      expect(lines[0], 'Chapter 1');
      expect(
        InlineImageMarker.tryParseLine(lines[1]),
        const InlineImageRef(
          archivePath: 'OEBPS/Images/fig 1.png',
          width: 800,
          height: 600,
          alt: 'Diagram 1',
        ),
      );
      expect(
        InlineImageMarker.tryParseLine(lines[2]),
        const InlineImageRef(
          archivePath: 'OEBPS/Images/plate.jpg',
          width: 1024,
          height: 1536,
          alt: '',
        ),
      );
      expect(lines[3], 'Closing paragraph.');
      expect(chapterText, isNot(contains('SVG Noise')));
      expect(chapterText, isNot(contains('vector.svg')));
      expect(chapterText, isNot(contains('missing.jpg')));

      // ContentSanitizerImpl preserves inline image marker lines intact.
      final sanitized = await ContentSanitizerImpl().sanitize(
        chapterText,
        SanitizeContext(
          bookId: imported.book.id,
          chapterTitle: imported.chapters.single.title,
        ),
      );
      expect(sanitized, chapterText);

      // Direct entry byte readers (bytes, sync file, async isolate, provider).
      expect(
        EpubContainerParser.readEntryBytesFromBytes(
          epubBytes,
          archivePath: 'OEBPS/Images/fig 1.png',
        ),
        pngBytes,
      );
      expect(
        EpubContainerParser.readEntryBytesFromBytes(
          epubBytes,
          archivePath: 'OEBPS/Images/nope.png',
        ),
        isNull,
      );
      expect(
        EpubContainerParser.readEntryBytesFromFileSync(
          filePath: epubFile.path,
          archivePath: 'OEBPS/Images/plate.jpg',
        ),
        jpgBytes,
      );
      expect(
        await const EpubContainerParser().readEntryBytesFromFile(
          filePath: epubFile.path,
          archivePath: 'OEBPS/Images/fig 1.png',
        ),
        pngBytes,
      );
      expect(
        await provider.readImageBytes(
          filePath: epubFile.path,
          archivePath: 'OEBPS/Images/plate.jpg',
        ),
        jpgBytes,
      );
      expect(
        await provider.readImageBytes(
          filePath: epubFile.path,
          archivePath: '',
        ),
        isNull,
      );

      final cancelled = CancellationToken()..cancel();
      await expectLater(
        () => provider.readImageBytes(
          filePath: epubFile.path,
          archivePath: 'OEBPS/Images/plate.jpg',
          cancelToken: cancelled,
        ),
        throwsA(isA<CancelledFailure>()),
      );
      await expectLater(
        () => provider.readImageBytes(
          filePath: '${tmpDir.path}${Platform.pathSeparator}missing.epub',
          archivePath: 'OEBPS/Images/plate.jpg',
        ),
        throwsA(isA<FileAccessFailure>()),
      );
    });
  });
}
