import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';

void main() {
  group('Domain value objects & entities', () {
    test('ReadingAnchor supports value equality and copyWith', () {
      const anchor = ReadingAnchor(
        chapterIndex: 12,
        charOffset: 345,
        chapterTitleSnapshot: '第十二章 初入江湖',
      );

      final updated = anchor.copyWith(charOffset: 512);
      expect(updated.chapterIndex, 12);
      expect(updated.charOffset, 512);
      expect(updated.chapterTitleSnapshot, '第十二章 初入江湖');
      expect(
        anchor,
        equals(
          const ReadingAnchor(
            chapterIndex: 12,
            charOffset: 345,
            chapterTitleSnapshot: '第十二章 初入江湖',
          ),
        ),
      );
      expect(updated, isNot(equals(anchor)));
    });

    test('ReaderTheme converts to PaginationConfig preserving typography', () {
      final now = DateTime.utc(2026, 11, 24);
      final theme = ReaderTheme(
        id: 'parchment',
        name: '羊皮纸护眼',
        isBuiltin: true,
        bgColor: 0xFFF5F0E6,
        textColor: 0xFF2B2620,
        secondaryTextColor: 0xFF7A7063,
        fontSize: 20.0,
        lineHeight: 1.75,
        updatedAt: now,
      );

      final config = theme.toPaginationConfig(
        columnWidth: 380,
        columnHeight: 680,
        columnCount: 2,
      );

      expect(config.columnWidth, 380);
      expect(config.columnHeight, 680);
      expect(config.columnCount, 2);
      expect(config.fontSize, 20.0);
      expect(config.lineHeightMultiplier, 1.75);
      expect(config.enablePunctuationHanging, isTrue);
      expect(config.enableCjkSpacing, isTrue);
    });

    test('PageSlice checks half-open range and contiguous char conservation', () {
      const text = '第一段正文。\n第二段正文。';
      const first = PageSlice(
        chapterIndex: 0,
        pageIndex: 0,
        startCharOffset: 0,
        endCharOffset: 7,
        lines: [
          LayoutLine(
            text: '第一段正文。\n',
            startCharOffset: 0,
            endCharOffset: 7,
            x: 0,
            y: 0,
            width: 120,
            height: 24,
            isParagraphStart: true,
            isParagraphEnd: true,
          ),
        ],
      );
      const second = PageSlice(
        chapterIndex: 0,
        pageIndex: 1,
        startCharOffset: 7,
        endCharOffset: 13,
        lines: [
          LayoutLine(
            text: '第二段正文。',
            startCharOffset: 7,
            endCharOffset: 13,
            x: 0,
            y: 0,
            width: 120,
            height: 24,
            isParagraphStart: true,
            isParagraphEnd: true,
          ),
        ],
      );

      expect(first.containsOffset(0), isTrue);
      expect(first.containsOffset(6), isTrue);
      expect(first.containsOffset(7), isFalse);
      expect(second.containsOffset(7), isTrue);
      expect(first.endCharOffset, second.startCharOffset);

      final rejoined = [first, second]
          .expand((slice) => slice.lines)
          .map((line) => line.text)
          .join();
      expect(rejoined, text);
    });

    test('ReadingProgress converts cleanly to ReadingAnchor', () {
      final progress = ReadingProgress(
        bookId: 'book-1',
        chapterIndex: 3,
        charOffset: 1024,
        chapterTitleSnapshot: '第三章 启程',
        progressPercent: 0.25,
        updatedAt: DateTime.utc(2026, 11, 24),
      );

      final anchor = progress.toAnchor();
      expect(anchor.chapterIndex, 3);
      expect(anchor.charOffset, 1024);
      expect(anchor.chapterTitleSnapshot, '第三章 启程');
    });

    test('CancellationToken notifies listeners and throws CancelledFailure', () {
      final token = CancellationToken();
      var listenerCalls = 0;
      token.addListener(() => listenerCalls++);

      expect(token.isCancelled, isFalse);
      token.throwIfCancelled();

      token.cancel();
      expect(token.isCancelled, isTrue);
      expect(listenerCalls, 1);
      expect(token.throwIfCancelled, throwsA(isA<CancelledFailure>()));

      // Calling cancel again is idempotent.
      token.cancel();
      expect(listenerCalls, 1);
    });

    test('AppFailure sealed hierarchy supports exhaustive switching', () {
      const failures = <AppFailure>[
        NetworkFailure(message: 'timeout', isTimeout: true),
        SourceParseFailure(message: 'missing title', step: 'detail'),
        UnsupportedLegadoRuleFailure(
          message: 'webView unsupported',
          feature: 'webView',
        ),
        JsExecutionFailure(message: 'syntax error'),
        EncodingFailure(message: 'unknown charset'),
        FileAccessFailure(message: 'not found'),
        DatabaseFailure(message: 'migration failed'),
        CancelledFailure(),
      ];

      final labels = failures.map((failure) {
        return switch (failure) {
          NetworkFailure() => 'network',
          SourceParseFailure() => 'parse',
          UnsupportedLegadoRuleFailure() => 'unsupported',
          JsExecutionFailure() => 'js',
          EncodingFailure() => 'encoding',
          FileAccessFailure() => 'file',
          DatabaseFailure() => 'database',
          CancelledFailure() => 'cancelled',
        };
      }).toList();

      expect(
        labels,
        equals([
          'network',
          'parse',
          'unsupported',
          'js',
          'encoding',
          'file',
          'database',
          'cancelled',
        ]),
      );
    });
  });
}
