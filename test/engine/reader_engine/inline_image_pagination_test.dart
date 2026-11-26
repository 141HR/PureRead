import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/reader/epub_image_cache.dart';
import 'package:pureread/application/reader/local_epub_reader_provider.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/reader_engine.dart';

void _assertCharacterConservation(String chapterText, List<PageSlice> pages) {
  expect(pages, isNotEmpty);
  expect(pages.first.startCharOffset, equals(0));
  expect(pages.last.endCharOffset, equals(chapterText.length));

  final pageJoin = StringBuffer();
  final lineJoin = StringBuffer();

  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    expect(page.pageIndex, equals(i));
    if (i + 1 < pages.length) {
      expect(page.endCharOffset, equals(pages[i + 1].startCharOffset));
    }
    pageJoin.write(
      chapterText.substring(page.startCharOffset, page.endCharOffset),
    );
    if (page.lines.isNotEmpty) {
      expect(page.lines.first.startCharOffset, equals(page.startCharOffset));
      expect(page.lines.last.endCharOffset, equals(page.endCharOffset));
      for (var j = 0; j < page.lines.length; j++) {
        final line = page.lines[j];
        expect(
          line.text,
          equals(
            chapterText.substring(line.startCharOffset, line.endCharOffset),
          ),
        );
        if (j + 1 < page.lines.length) {
          expect(line.endCharOffset, equals(page.lines[j + 1].startCharOffset));
        }
        lineJoin.write(line.text);
      }
    }
  }

  expect(pageJoin.toString(), equals(chapterText));
  expect(lineJoin.toString(), equals(chapterText));
}

Uint8List _buildValidPng(int width, int height) {
  final rawScanlines = BytesBuilder(copy: false);
  final rowBytes = 1 + width * 4;
  final row = Uint8List(rowBytes);
  row[0] = 0; // Filter type 0 (None)
  for (var x = 0; x < width; x++) {
    row[1 + x * 4] = 0x40;
    row[1 + x * 4 + 1] = 0x80;
    row[1 + x * 4 + 2] = 0xC0;
    row[1 + x * 4 + 3] = 0xFF;
  }
  for (var y = 0; y < height; y++) {
    rawScanlines.add(row);
  }
  final idatData = Uint8List.fromList(zlib.encode(rawScanlines.toBytes()));

  final ihdr = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // RGBA
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);

  final out = BytesBuilder(copy: false)
    ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_pngChunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_pngChunk('IDAT', idatData))
    ..add(_pngChunk('IEND', Uint8List(0)));
  return out.toBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = type.codeUnits;
  final crcInput = BytesBuilder(copy: false)
    ..add(typeBytes)
    ..add(data);
  final crc = _crc32(crcInput.toBytes());

  final header = ByteData(8)
    ..setUint32(0, data.length, Endian.big)
    ..setUint8(4, typeBytes[0])
    ..setUint8(5, typeBytes[1])
    ..setUint8(6, typeBytes[2])
    ..setUint8(7, typeBytes[3]);
  final footer = ByteData(4)..setUint32(0, crc, Endian.big);

  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(data)
        ..add(footer.buffer.asUint8List()))
      .toBytes();
}

int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      if ((crc & 1) != 0) {
        crc = (crc >>> 1) ^ 0xEDB88320;
      } else {
        crc >>>= 1;
      }
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Book _sampleBook(String id) {
  final now = DateTime.utc(2026, 11, 25);
  return Book(
    id: id,
    providerType: ProviderType.localEpub,
    title: 'Test EPUB',
    localFilePath: '/tmp/test.epub',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IncrementalTextPaginator inline image layout', () {
    test('lays out small icons, large illustrations, tall clamping, and 0x0 fallback with 100% char conservation', () async {
      final paginator = IncrementalTextPaginator();
      const config = PaginationConfig(
        columnWidth: 340,
        columnHeight: 600,
        fontSize: 18,
        paragraphSpacing: 12,
      );

      final iconMarker = InlineImageMarker.encode(
        archivePath: 'OEBPS/Images/ornament.png',
        width: 80,
        height: 40,
        alt: 'divider',
      );
      final wideMarker = InlineImageMarker.encode(
        archivePath: 'OEBPS/Images/wide.jpg',
        width: 1200,
        height: 800,
      );
      final tallMarker = InlineImageMarker.encode(
        archivePath: 'OEBPS/Images/tall.jpg',
        width: 600,
        height: 2000,
      );
      final unknownMarker = InlineImageMarker.encode(
        archivePath: 'OEBPS/Images/unknown.png',
      );

      final chapter =
          '第一章 启程\n'
          '$iconMarker\n'
          '中间正文段落，包含充足的文字用于验证分页和字符偏移守恒。\n'
          '$wideMarker\n\n'
          '$tallMarker\n'
          '$unknownMarker\n'
          '末尾段落。\n';

      final syncPages = paginator.paginateChapterSync(
        chapterIndex: 0,
        sanitizedText: chapter,
        config: config,
      );
      _assertCharacterConservation(chapter, syncPages);

      final incResult = await paginator.paginateChapterIncremental(
        chapterIndex: 0,
        sanitizedText: chapter,
        config: config,
        priorityCharOffset: chapter.indexOf(unknownMarker),
      );
      _assertCharacterConservation(chapter, incResult.allPages);

      final allLines = syncPages.expand((p) => p.lines).toList();
      final iconLine = allLines.firstWhere((l) => l.text.contains('ornament.png'));
      expect(iconLine.charXOffsets, isNull);
      expect(iconLine.isParagraphStart, isTrue);
      expect(iconLine.isParagraphEnd, isTrue);
      expect(iconLine.isChapterTitle, isFalse);
      expect(iconLine.width, closeTo(80.0, 1e-6));
      expect(iconLine.height, closeTo(40.0 + 12.0, 1e-6));
      expect(iconLine.x, closeTo((340.0 - 80.0) * 0.5, 1e-6));

      final wideLine = allLines.firstWhere((l) => l.text.contains('wide.jpg'));
      expect(wideLine.charXOffsets, isNull);
      expect(wideLine.width, closeTo(340.0, 1e-6));
      expect(wideLine.height, closeTo(340.0 * 800.0 / 1200.0 + 12.0, 1e-3));
      expect(wideLine.x, closeTo(0.0, 1e-6));

      final tallLine = allLines.firstWhere((l) => l.text.contains('tall.jpg'));
      const expectedTallH = 600.0 * 0.86;
      const expectedTallW = expectedTallH * (600.0 / 2000.0);
      expect(tallLine.charXOffsets, isNull);
      expect(tallLine.width, closeTo(expectedTallW, 1e-3));
      expect(tallLine.height, closeTo(expectedTallH + 12.0, 1e-3));
      expect(tallLine.height, lessThanOrEqualTo(config.columnHeight));
      expect(tallLine.x, closeTo((340.0 - expectedTallW) * 0.5, 1e-3));

      final unknownLine = allLines.firstWhere((l) => l.text.contains('unknown.png'));
      expect(unknownLine.charXOffsets, isNull);
      expect(unknownLine.width, closeTo(340.0, 1e-6));
      expect(unknownLine.height, closeTo(340.0 * 3.0 / 4.0 + 12.0, 1e-3));
      expect(unknownLine.x, closeTo(0.0, 1e-6));

      // Every page respects columnHeight bounds even when images trigger breaks.
      for (final page in syncPages) {
        for (final line in page.lines) {
          expect(line.y + line.height, lessThanOrEqualTo(config.columnHeight + 0.01));
        }
      }
    });

    test('clamps small icons when columnWidth is narrower than natural icon width and handles deep anchored window', () async {
      final paginator = IncrementalTextPaginator();
      final smallAtNarrowCol = InlineImageMarker.encode(
        archivePath: 'OEBPS/small.png',
        width: 160,
        height: 120,
      );
      const narrowConfig = PaginationConfig(
        columnWidth: 100,
        columnHeight: 300,
        fontSize: 16,
      );

      final narrowPages = paginator.paginateChapterSync(
        chapterIndex: 0,
        sanitizedText: smallAtNarrowCol,
        config: narrowConfig,
      );
      _assertCharacterConservation(smallAtNarrowCol, narrowPages);
      final narrowLine = narrowPages.single.lines.single;
      expect(narrowLine.width, closeTo(100.0, 1e-6));
      expect(narrowLine.height, closeTo(75.0 + 12.0, 1e-6));
      expect(narrowLine.x, closeTo(0.0, 1e-6));

      // Deep anchored window (> 1200 chars) containing an image marker.
      final leadText = '这是一段用于填充字符偏移超过一千二百字的测试文本，排版引擎应当准确锚定图片位置。\n' * 40;
      final marker = InlineImageMarker.encode(
        archivePath: 'OEBPS/deep.png',
        width: 800,
        height: 600,
      );
      final longChapter = '$leadText$marker\n收尾段落。\n';
      final deepOffset = longChapter.indexOf(marker);
      expect(deepOffset, greaterThan(1200));

      FirstScreenResult? firstScreen;
      final res = await paginator.paginateChapterIncremental(
        chapterIndex: 1,
        sanitizedText: longChapter,
        config: const PaginationConfig(columnWidth: 320, columnHeight: 560),
        priorityCharOffset: deepOffset,
        onFirstScreen: (fs) => firstScreen = fs,
      );
      expect(firstScreen, isNotNull);
      expect(firstScreen!.isApproximateWindow, isTrue);
      _assertCharacterConservation(longChapter, res.allPages);

      final targetPageIdx = AnchorMapper.findPageIndexByCharOffset(
        res.allPages,
        deepOffset,
      );
      expect(
        res.allPages[targetPageIdx].lines.any((l) => l.text.contains('deep.png')),
        isTrue,
      );
    });
  });

  group('EpubImageCache & localEpubImageReaderProvider', () {
    test('deduplicates concurrent loads, downscales oversized images, tracks failures, evicts LRU, and disposes ui.Image', () async {
      final smallPng = _buildValidPng(40, 20);
      final largePng = _buildValidPng(2000, 100);
      final secondPng = _buildValidPng(32, 32);
      final thirdPng = _buildValidPng(24, 24);
      final fourthPng = _buildValidPng(16, 16);
      final corruptBytes = Uint8List.fromList(const <int>[1, 2, 3, 4, 5]);

      final loadCounts = <String, int>{};
      final smallGate = Completer<void>();

      final cache = EpubImageCache(
        maxEntries: 3,
        maxTargetWidth: 1600,
        imageReader: (book, archivePath) async {
          loadCounts[archivePath] = (loadCounts[archivePath] ?? 0) + 1;
          switch (archivePath) {
            case 'img/small.png':
              await smallGate.future;
              return smallPng;
            case 'img/large.png':
              return largePng;
            case 'img/second.png':
              return secondPng;
            case 'img/third.png':
              return thirdPng;
            case 'img/fourth.png':
              return fourthPng;
            case 'img/corrupt.png':
              return corruptBytes;
            default:
              return null;
          }
        },
      );

      var notifications = 0;
      cache.addListener(() => notifications++);

      final book = _sampleBook('book-1');

      // 1. Concurrent deduplication
      expect(cache.getCached(book.id, 'img/small.png'), isNull);
      final f1 = cache.loadImage(book, 'img/small.png');
      final f2 = cache.loadImage(book, 'img/small.png');
      expect(cache.isLoading(book.id, 'img/small.png'), isTrue);
      smallGate.complete();
      final results = await Future.wait(<Future<ui.Image?>>[f1, f2]);
      expect(results[0], isNotNull);
      expect(identical(results[0], results[1]), isTrue);
      expect(loadCounts['img/small.png'], 1);
      expect(results[0]!.width, 40); // allowUpscaling: false keeps 40px
      expect(results[0]!.height, 20);
      expect(cache.getCached(book.id, 'img/small.png'), same(results[0]));
      expect(notifications, 1);

      // 2. Bounded decode caps oversized width at 1600px
      final largeImg = await cache.loadImage(book, 'img/large.png');
      expect(largeImg, isNotNull);
      expect(largeImg!.width, 1600);
      expect(largeImg.height, 80);

      // 3. Failure tracking prevents infinite retries on corrupt or missing assets
      final corruptImg = await cache.loadImage(book, 'img/corrupt.png');
      expect(corruptImg, isNull);
      expect(cache.isFailed(book.id, 'img/corrupt.png'), isTrue);
      expect(await cache.loadImage(book, 'img/corrupt.png'), isNull);
      expect(loadCounts['img/corrupt.png'], 1);

      final missingImg = await cache.loadImage(book, 'img/missing.png');
      expect(missingImg, isNull);
      expect(cache.isFailed(book.id, 'img/missing.png'), isTrue);
      expect(await cache.loadImage(book, 'img/missing.png'), isNull);
      expect(loadCounts['img/missing.png'], 1);

      // 4. LRU eviction: cache currently holds [small, large] (maxEntries = 3).
      // Load second -> [small, large, second]. Touch small -> [large, second, small].
      // Load third -> evicts large and disposes it!
      final secondImg = await cache.loadImage(book, 'img/second.png');
      expect(secondImg, isNotNull);
      expect(cache.getCached(book.id, 'img/small.png'), same(results[0]));
      final thirdImg = await cache.loadImage(book, 'img/third.png');
      expect(thirdImg, isNotNull);

      expect(cache.cachedCount, 3);
      expect(largeImg.debugDisposed, isTrue);
      expect(results[0]!.debugDisposed, isFalse);
      expect(cache.getCached(book.id, 'img/large.png'), isNull);

      // 5. clear() disposes all cached images and resets failed keys
      cache.clear();
      expect(cache.cachedCount, 0);
      expect(cache.failedCount, 0);
      expect(results[0]!.debugDisposed, isTrue);
      expect(secondImg!.debugDisposed, isTrue);
      expect(thirdImg!.debugDisposed, isTrue);

      // 6. dispose() disposes remaining cached images and blocks subsequent loads
      final fourthImg = await cache.loadImage(book, 'img/fourth.png');
      expect(fourthImg, isNotNull);
      cache.dispose();
      expect(fourthImg!.debugDisposed, isTrue);
      expect(await cache.loadImage(book, 'img/small.png'), isNull);
      expect(cache.getCached(book.id, 'img/fourth.png'), isNull);
    });

    test('Riverpod providers expose safe defaults and dispose cache on container disposal', () async {
      final container = ProviderContainer();
      final reader = container.read(localEpubImageReaderProvider);
      expect(await reader(_sampleBook('b1'), 'OEBPS/1.png'), isNull);

      final cache = container.read(epubImageCacheProvider);
      expect(cache.maxEntries, 12);
      container.dispose();
      expect(await cache.loadImage(_sampleBook('b1'), 'OEBPS/1.png'), isNull);
    });
  });
}
