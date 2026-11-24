import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/reader_engine.dart';

String _buildLongChapter() {
  const para =
      '夜色微凉，沈砚合上桌上的《山海残卷》，抬头望向窗外闪烁的霓虹灯光。'
      '终端屏幕上的 PureRead v3.13 引擎仍在静默运行，记录着字节偏移与锚点刻度。'
      '「你确定要在今晚测试这套双栏分页与缩放往返逻辑吗？」林清音笑着问。\n';
  final buf = StringBuffer();
  for (var i = 0; i < 42; i++) {
    buf.write(para);
  }
  return buf.toString();
}

PageSlice _dummySlice(int chapterIndex, int pageIndex, int start, int end) {
  return PageSlice(
    chapterIndex: chapterIndex,
    pageIndex: pageIndex,
    startCharOffset: start,
    endCharOffset: end,
    lines: const <LayoutLine>[],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnchorMapper & spread pairing', () {
    test('pairSpread handles single-column, even two-column, and odd two-column', () {
      final evenPages = <PageSlice>[
        _dummySlice(1, 0, 0, 100),
        _dummySlice(1, 1, 100, 200),
        _dummySlice(1, 2, 200, 300),
        _dummySlice(1, 3, 300, 400),
      ];

      expect(AnchorMapper.spreadCount(evenPages, 1), equals(4));
      expect(AnchorMapper.spreadCount(evenPages, 2), equals(2));

      final (s0Left, s0Right) = AnchorMapper.pairSpread(evenPages, 0, 2);
      expect(s0Left, same(evenPages[0]));
      expect(s0Right, same(evenPages[1]));

      final (s1Left, s1Right) = AnchorMapper.pairSpread(evenPages, 1, 2);
      expect(s1Left, same(evenPages[2]));
      expect(s1Right, same(evenPages[3]));

      final (singleLeft, singleRight) = AnchorMapper.pairSpread(evenPages, 2, 1);
      expect(singleLeft, same(evenPages[2]));
      expect(singleRight, isNull);

      // Odd page count: final right page is null
      final oddPages = <PageSlice>[
        ...evenPages,
        _dummySlice(1, 4, 400, 480),
      ];
      expect(AnchorMapper.spreadCount(oddPages, 2), equals(3));
      final (lastLeft, lastRight) = AnchorMapper.pairSpread(oddPages, 2, 2);
      expect(lastLeft, same(oddPages[4]));
      expect(lastRight, isNull);

      expect(
        () => AnchorMapper.pairSpread(oddPages, 3, 2),
        throwsRangeError,
      );
      expect(
        () => AnchorMapper.pairSpread(const <PageSlice>[], 0, 1),
        throwsRangeError,
      );
    });

    test('findPageIndexByCharOffset, findSpreadIndexByCharOffset & getAnchorForPage', () {
      final pages = <PageSlice>[
        _dummySlice(3, 0, 0, 100),
        _dummySlice(3, 1, 100, 220),
        _dummySlice(3, 2, 220, 350),
        _dummySlice(3, 3, 350, 500),
        _dummySlice(3, 4, 500, 620),
      ];

      expect(AnchorMapper.findPageIndexByCharOffset(pages, -10), equals(0));
      expect(AnchorMapper.findPageIndexByCharOffset(pages, 0), equals(0));
      expect(AnchorMapper.findPageIndexByCharOffset(pages, 99), equals(0));
      expect(AnchorMapper.findPageIndexByCharOffset(pages, 100), equals(1));
      expect(AnchorMapper.findPageIndexByCharOffset(pages, 350), equals(3));
      expect(AnchorMapper.findPageIndexByCharOffset(pages, 619), equals(4));
      expect(AnchorMapper.findPageIndexByCharOffset(pages, 999), equals(4));

      expect(
        AnchorMapper.findSpreadIndexByCharOffset(pages, 350, columnCount: 2),
        equals(1),
      );
      expect(
        AnchorMapper.findSpreadIndexByCharOffset(pages, 520, columnCount: 2),
        equals(2),
      );
      expect(
        AnchorMapper.findSpreadIndexByCharOffset(pages, 350, columnCount: 1),
        equals(3),
      );

      final anchor = AnchorMapper.getAnchorForPage(
        pages[2],
        chapterTitleSnapshot: '第三章',
      );
      expect(
        anchor,
        equals(
          const ReadingAnchor(
            chapterIndex: 3,
            charOffset: 220,
            chapterTitleSnapshot: '第三章',
          ),
        ),
      );
    });

    test('charOffset round-trip resize stability across 1-col, 2-col & font changes', () {
      final paginator = IncrementalTextPaginator();
      final chapter = _buildLongChapter();
      final now = DateTime.utc(2026, 11, 24);

      final mobileTheme = ReaderTheme(
        id: 'mobile',
        name: 'Mobile',
        bgColor: 0xFFFFFFFF,
        textColor: 0xFF111111,
        secondaryTextColor: 0xFF666666,
        fontSize: 18,
        columnMode: ColumnMode.auto,
        updatedAt: now,
      );
      final desktop2ColTheme = ReaderTheme(
        id: 'desktop2col',
        name: 'Desktop 2-Col',
        bgColor: 0xFFFFFFFF,
        textColor: 0xFF111111,
        secondaryTextColor: 0xFF666666,
        fontSize: 22,
        columnMode: ColumnMode.auto,
        updatedAt: now,
      );
      final narrowTheme = ReaderTheme(
        id: 'narrow',
        name: 'Narrow',
        bgColor: 0xFFFFFFFF,
        textColor: 0xFF111111,
        secondaryTextColor: 0xFF666666,
        fontSize: 15,
        columnMode: ColumnMode.single,
        updatedAt: now,
      );

      final mobileCfg = PaginationGeometryResolver.resolve(
        viewportWidth: 390,
        viewportHeight: 760,
        theme: mobileTheme,
      );
      final desktopCfg = PaginationGeometryResolver.resolve(
        viewportWidth: 1100,
        viewportHeight: 760,
        theme: desktop2ColTheme,
      );
      final narrowCfg = PaginationGeometryResolver.resolve(
        viewportWidth: 320,
        viewportHeight: 620,
        theme: narrowTheme,
      );

      expect(mobileCfg.columnCount, equals(1));
      expect(desktopCfg.columnCount, equals(2));
      expect(narrowCfg.columnCount, equals(1));

      final mobilePages = paginator.paginateChapterSync(
        chapterIndex: 5,
        sanitizedText: chapter,
        config: mobileCfg,
      );
      final desktopPages = paginator.paginateChapterSync(
        chapterIndex: 5,
        sanitizedText: chapter,
        config: desktopCfg,
      );
      final narrowPages = paginator.paginateChapterSync(
        chapterIndex: 5,
        sanitizedText: chapter,
        config: narrowCfg,
      );

      for (final sourcePageIdx in <int>[
        0,
        1,
        mobilePages.length ~/ 2,
        mobilePages.length - 1,
      ]) {
        final anchor = AnchorMapper.getAnchorForPage(
          mobilePages[sourcePageIdx],
          chapterTitleSnapshot: '第5章',
        );

        // Resize A -> B (desktop 2-col 22pt)
        final bPageIdx = AnchorMapper.findPageIndexByCharOffset(
          desktopPages,
          anchor.charOffset,
        );
        final bSpreadIdx = AnchorMapper.findSpreadIndexByCharOffset(
          desktopPages,
          anchor.charOffset,
          columnCount: desktopCfg.columnCount,
        );
        expect(desktopPages[bPageIdx].containsOffset(anchor.charOffset), isTrue);
        final (left, right) = AnchorMapper.pairSpread(
          desktopPages,
          bSpreadIdx,
          desktopCfg.columnCount,
        );
        final spreadEnd = right?.endCharOffset ?? left.endCharOffset;
        expect(anchor.charOffset >= left.startCharOffset, isTrue);
        expect(anchor.charOffset < spreadEnd, isTrue);

        // Resize B -> C (narrow 1-col 15pt)
        final cPageIdx = AnchorMapper.findPageIndexByCharOffset(
          narrowPages,
          anchor.charOffset,
        );
        expect(narrowPages[cPageIdx].containsOffset(anchor.charOffset), isTrue);

        // Resize C -> A (back to original mobile config): 0-char drift!
        final restoredPages = paginator.paginateChapterSync(
          chapterIndex: 5,
          sanitizedText: chapter,
          config: mobileCfg,
        );
        final restoredIdx = AnchorMapper.findPageIndexByCharOffset(
          restoredPages,
          anchor.charOffset,
        );
        expect(restoredIdx, equals(sourcePageIdx));
        expect(
          restoredPages[restoredIdx].startCharOffset,
          equals(mobilePages[sourcePageIdx].startCharOffset),
        );
      }
    });
  });

  group('PageCacheRing', () {
    const cfgA = PaginationConfig(
      columnWidth: 350,
      columnHeight: 700,
      fontSize: 18,
    );
    final cfgB = cfgA.copyWith(fontSize: 20);

    test('maintains 3-chapter window {c - 1, c, c + 1} and evicts out-of-window chapters', () {
      final ring = PageCacheRing();

      ring.focusChapter(bookId: 'book-1', chapterIndex: 5, config: cfgA);
      ring.put(
        bookId: 'book-1',
        chapterIndex: 5,
        config: cfgA,
        pages: <PageSlice>[_dummySlice(5, 0, 0, 100)],
      );
      ring.put(
        bookId: 'book-1',
        chapterIndex: 4,
        config: cfgA,
        pages: <PageSlice>[_dummySlice(4, 0, 0, 80)],
      );
      ring.put(
        bookId: 'book-1',
        chapterIndex: 6,
        config: cfgA,
        pages: <PageSlice>[_dummySlice(6, 0, 0, 120)],
      );

      expect(ring.length, equals(3));
      expect(ring.cachedChapterIndices, equals(<int>{4, 5, 6}));
      expect(
        ring.get(bookId: 'book-1', chapterIndex: 4, config: cfgA),
        isNotNull,
      );

      // Advance active chapter from 5 -> 6: chapter 4 is auto-evicted
      ring.focusChapter(bookId: 'book-1', chapterIndex: 6, config: cfgA);
      expect(ring.contains(bookId: 'book-1', chapterIndex: 4, config: cfgA), isFalse);
      expect(ring.cachedChapterIndices, equals(<int>{5, 6}));

      ring.put(
        bookId: 'book-1',
        chapterIndex: 7,
        config: cfgA,
        pages: <PageSlice>[_dummySlice(7, 0, 0, 90)],
      );
      expect(ring.cachedChapterIndices, equals(<int>{5, 6, 7}));
    });

    test('slides window smoothly on sequential put and clears on config or book changes', () {
      final ring = PageCacheRing();
      for (var ch = 0; ch < 5; ch++) {
        ring.put(
          bookId: 'book-1',
          chapterIndex: ch,
          config: cfgA,
          pages: <PageSlice>[_dummySlice(ch, 0, 0, 50)],
        );
        expect(ring.length, lessThanOrEqualTo(3));
      }
      expect(ring.cachedChapterIndices, equals(<int>{2, 3, 4}));

      // Config change clears prior slices
      ring.invalidateOnConfigChange(cfgB);
      expect(ring.length, equals(0));

      ring.put(
        bookId: 'book-1',
        chapterIndex: 3,
        config: cfgA,
        pages: <PageSlice>[_dummySlice(3, 0, 0, 50)],
      );
      expect(ring.length, equals(1));

      // Putting with different config auto-clears old config's slices
      ring.put(
        bookId: 'book-1',
        chapterIndex: 3,
        config: cfgB,
        pages: <PageSlice>[_dummySlice(3, 0, 0, 60)],
      );
      expect(ring.get(bookId: 'book-1', chapterIndex: 3, config: cfgA), isNull);
      expect(ring.get(bookId: 'book-1', chapterIndex: 3, config: cfgB), isNotNull);

      // Switching bookId auto-clears old book's slices
      ring.put(
        bookId: 'book-2',
        chapterIndex: 0,
        config: cfgB,
        pages: <PageSlice>[_dummySlice(0, 0, 0, 40)],
      );
      expect(ring.get(bookId: 'book-1', chapterIndex: 3, config: cfgB), isNull);
      expect(ring.get(bookId: 'book-2', chapterIndex: 0, config: cfgB), isNotNull);

      expect(ring.invalidateChapter(0), isTrue);
      expect(ring.length, equals(0));
    });
  });
}
