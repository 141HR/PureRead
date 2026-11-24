import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/reader_engine.dart';

void main() {
  group('ChineseTypesetting', () {
    test('exposes kCjkAsciiSpacingRatio = 0.2 and gap calculation', () {
      expect(kCjkAsciiSpacingRatio, equals(0.2));
      expect(ChineseTypesetting.kCjkAsciiSpacingRatio, equals(0.2));
      expect(ChineseTypesetting.cjkAsciiGap(20.0), closeTo(4.0, 1e-9));
      expect(
        ChineseTypesetting.cjkAsciiGap(20.0, enabled: false),
        equals(0.0),
      );
    });

    test('classifies line-start and line-end prohibited punctuation', () {
      for (final rune in '，。！？、；：《》」』）】〕〉〗｝’”…—～·．％,.!?;:)]}>%'.runes) {
        if ('《「『（【〔〈〖｛‘“([{<'.runes.contains(rune)) continue;
        expect(
          ChineseTypesetting.isLineStartProhibited(rune),
          isTrue,
          reason: 'Expected line-start prohibited: ${String.fromCharCode(rune)}',
        );
      }
      for (final rune in '《「『（【〔〈〖｛‘“([{<'.runes) {
        expect(
          ChineseTypesetting.isLineEndProhibited(rune),
          isTrue,
          reason: 'Expected line-end prohibited: ${String.fromCharCode(rune)}',
        );
      }
      expect(ChineseTypesetting.isLineStartProhibited('汉'.runes.first), isFalse);
      expect(ChineseTypesetting.isLineEndProhibited('汉'.runes.first), isFalse);
    });

    test('detects CJK-ASCII boundaries excluding full-width punctuation', () {
      const exactSample = '使用Flutter框架2026版，在《PureRead》中运行v3。';
      final exactOffsets = ChineseTypesetting.findCjkAsciiGapOffsets(exactSample);
      expect(
        exactOffsets.map((i) => exactSample[i]).toList(),
        equals(<String>['用', 'r', '架', '6', '行']),
      );
    });

    test('handles UTF-16 surrogate pairs cleanly without splitting', () {
      const text = '生僻字𠮷和😀测试';
      final idxAfterJi = ChineseTypesetting.stepForward(text, 3);
      expect(idxAfterJi, equals(5));
      expect(ChineseTypesetting.codePointAt(text, 3), equals(0x20BB7));
      expect(ChineseTypesetting.codePointBefore(text, 5), equals(0x20BB7));
      expect(ChineseTypesetting.stepBackward(text, 5), equals(3));

      // Candidate ending in the middle of surrogate pair '𠮷' (index 4)
      final resolved = ChineseTypesetting.resolveLineBreakOffset(
        text: text,
        lineStart: 0,
        candidateEnd: 4,
        paragraphRenderEnd: text.length,
      );
      expect(resolved, equals(3));
    });

    test('protects ASCII tokens and terminates safely on all-punctuation runs', () {
      const text = '测试v3.13，继续';
      // Candidate right before '，' (index 7): must pull whole 'v3.13' token.
      final resolved = ChineseTypesetting.resolveLineBreakOffset(
        text: text,
        lineStart: 0,
        candidateEnd: 7,
        paragraphRenderEnd: text.length,
      );
      expect(resolved, equals(2));
      expect(text.substring(0, resolved), equals('测试'));
      expect(text.substring(resolved), equals('v3.13，继续'));

      // Pathological all-punctuation input must make forward progress.
      final allComma = '，' * 50;
      final commaBreak = ChineseTypesetting.resolveLineBreakOffset(
        text: allComma,
        lineStart: 0,
        candidateEnd: 12,
        paragraphRenderEnd: allComma.length,
      );
      expect(commaBreak, greaterThan(0));
      expect(commaBreak, lessThanOrEqualTo(12));
    });
  });

  group('PaginationGeometryResolver', () {
    final now = DateTime.utc(2026, 11, 24);

    ReaderTheme makeTheme({
      ColumnMode columnMode = ColumnMode.auto,
      double maxContentWidth = 760.0,
      double marginHorizontal = 20.0,
      double marginVertical = 24.0,
    }) {
      return ReaderTheme(
        id: 'test-theme',
        name: 'Test Theme',
        bgColor: 0xFFF5F0E6,
        textColor: 0xFF2B2620,
        secondaryTextColor: 0xFF7A7063,
        fontFamily: 'NotoSansSC',
        fontSize: 20.0,
        fontWeight: 500,
        lineHeight: 1.75,
        paragraphSpacing: 14.0,
        letterSpacing: 0.3,
        paragraphIndentChars: 2,
        marginHorizontal: marginHorizontal,
        marginVertical: marginVertical,
        columnMode: columnMode,
        maxContentWidth: maxContentWidth,
        enablePunctuationHanging: true,
        enableCjkSpacing: true,
        updatedAt: now,
      );
    }

    test('ColumnMode.auto switches at 840px and caps single-col at maxContentWidth', () {
      final theme = makeTheme(columnMode: ColumnMode.auto);

      // Narrow phone: 390px -> 1 column, width = 390 - 40 = 350
      final phone = PaginationGeometryResolver.resolveLayout(
        viewportWidth: 390,
        viewportHeight: 844,
        theme: theme,
      );
      expect(phone.columnCount, equals(1));
      expect(phone.columnWidth, closeTo(350.0, 1e-6));
      expect(phone.horizontalPadding, closeTo(20.0, 1e-6));
      expect(phone.columnHeight, closeTo(844.0 - 48.0, 1e-6));

      // Wide desktop in explicit single-column: 1280px -> capped at 760px, centered
      final singleWide = PaginationGeometryResolver.resolveLayout(
        viewportWidth: 1280,
        viewportHeight: 800,
        theme: makeTheme(columnMode: ColumnMode.single, maxContentWidth: 760),
      );
      expect(singleWide.columnCount, equals(1));
      expect(singleWide.columnWidth, closeTo(760.0, 1e-6));
      expect(singleWide.horizontalPadding, closeTo((1280.0 - 760.0) / 2, 1e-6));

      // Wide desktop in auto: 840px -> 2 columns with (contentWidth - gap) / 2
      final autoWide = PaginationGeometryResolver.resolveLayout(
        viewportWidth: 1200,
        viewportHeight: 800,
        theme: theme,
        columnGap: 32.0,
        headerHeight: 36.0,
        footerHeight: 28.0,
      );
      expect(autoWide.columnCount, equals(2));
      expect(autoWide.contentWidth, closeTo(1200.0 - 40.0, 1e-6));
      expect(autoWide.columnWidth, closeTo((1160.0 - 32.0) / 2, 1e-6));
      expect(autoWide.columnHeight, closeTo(800.0 - 48.0 - 36.0 - 28.0, 1e-6));
      expect(autoWide.topPadding, closeTo(24.0 + 36.0, 1e-6));
      expect(autoWide.bottomPadding, closeTo(24.0 + 28.0, 1e-6));
    });

    test('ColumnMode.double honors explicit 2-column mode and preserves theme typography', () {
      final theme = makeTheme(columnMode: ColumnMode.double);
      final cfg = PaginationGeometryResolver.resolve(
        viewportWidth: 760,
        viewportHeight: 680,
        theme: theme,
        columnGap: 24.0,
      );

      expect(cfg.columnCount, equals(2));
      expect(cfg.columnWidth, closeTo((720.0 - 24.0) / 2, 1e-6));
      expect(cfg.fontFamily, equals('NotoSansSC'));
      expect(cfg.fontSize, equals(20.0));
      expect(cfg.fontWeightValue, equals(500));
      expect(cfg.lineHeightMultiplier, equals(1.75));
      expect(cfg.paragraphSpacing, equals(14.0));
      expect(cfg.letterSpacing, equals(0.3));
      expect(cfg.paragraphIndentChars, equals(2));
      expect(cfg.enablePunctuationHanging, isTrue);
      expect(cfg.enableCjkSpacing, isTrue);
    });
  });
}
