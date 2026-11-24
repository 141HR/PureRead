import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/reader/reader_session_state.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/presentation/reader/reader_page_painter.dart';
import 'package:pureread/presentation/reader/reader_page_turn_view.dart';
import 'package:pureread/presentation/reader/reader_settings_sheet.dart';
import 'package:pureread/presentation/reader/simulation_page_curl.dart';

void _expectFiniteOffset(Offset offset, String label) {
  expect(offset.dx.isFinite, isTrue, reason: '$label.dx must be finite');
  expect(offset.dy.isFinite, isTrue, reason: '$label.dy must be finite');
}

void _expectFiniteRect(Rect rect, String label) {
  expect(rect.left.isFinite, isTrue, reason: '$label.left must be finite');
  expect(rect.top.isFinite, isTrue, reason: '$label.top must be finite');
  expect(rect.right.isFinite, isTrue, reason: '$label.right must be finite');
  expect(rect.bottom.isFinite, isTrue, reason: '$label.bottom must be finite');
}

List<PageSlice> _buildSamplePages({int count = 6}) {
  return List<PageSlice>.generate(count, (idx) {
    final start = idx * 20;
    return PageSlice(
      chapterIndex: 0,
      pageIndex: idx,
      startCharOffset: start,
      endCharOffset: start + 20,
      lines: <LayoutLine>[
        LayoutLine(
          text: '第${idx + 1}页正文内容测试 PureRead 仿真卷页。\n',
          startCharOffset: start,
          endCharOffset: start + 20,
          x: 0,
          y: 0,
          width: 220,
          height: 28,
        ),
      ],
    );
  });
}

void main() {
  group('PageCurlGeometry invariants', () {
    const sizes = <Size>[
      Size(390, 844), // Portrait 1-col mobile
      Size(1280, 760), // Landscape 2-col desktop/tablet
    ];
    const progressSamples = <double>[0.0, 0.25, 0.5, 0.9, 1.0];

    test('maintains finite coordinates and path invariants across portrait & landscape', () {
      for (final size in sizes) {
        for (final direction in CurlDirection.values) {
          double? prevAnchorX;
          for (final t in progressSamples) {
            final g = computeCurl(
              size: size,
              progress: t,
              direction: direction,
            );

            expect(g.progress, closeTo(t, 1e-6));
            expect(g.curlRadius.isFinite, isTrue);
            expect(g.curlRadius, greaterThanOrEqualTo(0.0));

            _expectFiniteOffset(g.creaseAnchor, 'creaseAnchor');
            _expectFiniteOffset(g.creaseNormal, 'creaseNormal');
            _expectFiniteOffset(g.creaseStart, 'creaseStart');
            _expectFiniteOffset(g.creaseEnd, 'creaseEnd');
            _expectFiniteOffset(g.foldPoint, 'foldPoint');
            _expectFiniteOffset(g.highlightStart, 'highlightStart');
            _expectFiniteOffset(g.highlightEnd, 'highlightEnd');
            _expectFiniteOffset(g.shadowStart, 'shadowStart');
            _expectFiniteOffset(g.shadowEnd, 'shadowEnd');

            expect(g.creaseNormal.distance, closeTo(1.0, 1e-4));
            if (direction == CurlDirection.forward) {
              expect(g.creaseNormal.dx, greaterThan(0.0));
            } else {
              expect(g.creaseNormal.dx, lessThan(0.0));
            }

            expect(g.foldPoint.dx, inInclusiveRange(0.0, size.width));
            expect(g.foldPoint.dy, inInclusiveRange(0.0, size.height));

            final frontBounds = g.frontPageClipPath.getBounds();
            final flapBounds = g.backFlapPath.getBounds();
            final shadowBounds = g.dropShadowPath.getBounds();
            _expectFiniteRect(frontBounds, 'frontBounds');
            _expectFiniteRect(flapBounds, 'flapBounds');
            _expectFiniteRect(shadowBounds, 'shadowBounds');

            if (t == 0.0) {
              expect(g.isFlat, isTrue);
              expect(frontBounds, Offset.zero & size);
              expect(flapBounds.isEmpty, isTrue);
              expect(shadowBounds.isEmpty, isTrue);
            } else if (t == 1.0) {
              expect(g.isFlat, isTrue);
              expect(frontBounds.isEmpty, isTrue);
              expect(flapBounds.isEmpty, isTrue);
              expect(shadowBounds.isEmpty, isTrue);
            } else {
              expect(g.isFlat, isFalse);
              expect(frontBounds.width, greaterThan(0.0));
              expect(frontBounds.height, greaterThan(0.0));
              expect(flapBounds.width, greaterThan(0.0));
              expect(flapBounds.height, greaterThan(0.0));
              expect(shadowBounds.width, greaterThan(0.0));
              expect(shadowBounds.height, greaterThan(0.0));
              expect(
                (g.highlightEnd - g.highlightStart).distance,
                greaterThan(0.0),
              );

              if (prevAnchorX != null) {
                if (direction == CurlDirection.forward) {
                  expect(g.creaseAnchor.dx, lessThan(prevAnchorX));
                } else {
                  expect(g.creaseAnchor.dx, greaterThan(prevAnchorX));
                }
              }
              prevAnchorX = g.creaseAnchor.dx;
            }
          }
        }
      }
    });

    test('clamps out-of-range progress, NaN inputs, and degenerate sizes safely', () {
      final nanProgress = PageCurlGeometry.compute(
        size: const Size(400, 800),
        progress: double.nan,
      );
      expect(nanProgress.isFlat, isTrue);
      _expectFiniteOffset(nanProgress.creaseAnchor, 'nanProgress.anchor');

      final overProgress = PageCurlGeometry.compute(
        size: const Size(400, 800),
        progress: 2.5,
      );
      expect(overProgress.progress, 1.0);
      expect(overProgress.isFlat, isTrue);

      final underProgress = PageCurlGeometry.compute(
        size: const Size(400, 800),
        progress: -0.4,
      );
      expect(underProgress.progress, 0.0);
      expect(underProgress.isFlat, isTrue);

      for (final badSize in const <Size>[
        Size.zero,
        Size(-50, 400),
        Size(double.nan, 500),
      ]) {
        final degenerate = PageCurlGeometry.compute(
          size: badSize,
          progress: 0.5,
        );
        expect(degenerate.isFlat, isTrue);
        _expectFiniteOffset(degenerate.creaseAnchor, 'degenerate.anchor');
        _expectFiniteOffset(degenerate.creaseNormal, 'degenerate.normal');
      }
    });

    test('responds to top vs bottom touch origin with opposite crease tilt', () {
      final bottomCurl = computeCurl(
        size: const Size(400, 800),
        progress: 0.35,
        touchYNormalized: 0.85,
      );
      final topCurl = computeCurl(
        size: const Size(400, 800),
        progress: 0.35,
        touchYNormalized: 0.15,
      );
      expect(bottomCurl.creaseNormal.dy, greaterThan(0.0));
      expect(topCurl.creaseNormal.dy, lessThan(0.0));
    });
  });

  group('SimulationPageCurlView & ReaderPageTurnView integration', () {
    testWidgets('interactive drag commits forward/backward and short drag springs back', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 760);
      addTearDown(tester.view.reset);

      final pages = _buildSamplePages(count: 4);
      var currentPage = 0;
      var overlayToggles = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: ReaderPageTurnView(
                  mode: PageTurnMode.simulation,
                  columnCount: 1,
                  config: const PaginationConfig(
                    columnWidth: 380,
                    columnHeight: 700,
                    columnCount: 1,
                  ),
                  pages: pages,
                  currentPageIndex: currentPage,
                  currentChapterIndex: 0,
                  canGoPrev: currentPage > 0,
                  canGoNext: currentPage < pages.length - 1,
                  backgroundColor: const Color(0xFFF7F4EC),
                  textColor: const Color(0xFF2C2A26),
                  secondaryTextColor: const Color(0xFF78736A),
                  showOverlay: false,
                  onNextPage: () async {
                    if (currentPage < pages.length - 1) {
                      setState(() => currentPage++);
                    }
                  },
                  onPrevPage: () async {
                    if (currentPage > 0) {
                      setState(() => currentPage--);
                    }
                  },
                  onToggleOverlay: () => overlayToggles++,
                  onScrollOffsetChanged: (_) {},
                ),
              );
            },
          ),
        ),
      );

      expect(find.byType(SimulationPageCurlView), findsOneWidget);

      // Short forward drag (< 22% width) cancels and springs back to page 0.
      final gesture = await tester.startGesture(const Offset(360, 500));
      await gesture.moveBy(const Offset(-45, 0));
      await tester.pump();
      expect(find.byType(ClipPath), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(currentPage, 0);
      expect(find.byType(ClipPath), findsNothing);

      // Long forward drag (> 22% width) commits turn to page 1.
      await tester.drag(find.byType(ReaderPageTurnView), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(currentPage, 1);
      expect(find.byType(ClipPath), findsNothing);

      // Short backward drag cancels and stays at page 1.
      await tester.drag(find.byType(ReaderPageTurnView), const Offset(45, 0));
      await tester.pumpAndSettle();
      expect(currentPage, 1);

      // Long backward drag commits turn back to page 0.
      await tester.drag(find.byType(ReaderPageTurnView), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(currentPage, 0);

      // Tap zones preserved: right zone -> next, center -> overlay, left -> prev.
      await tester.tapAt(const Offset(380, 380));
      await tester.pumpAndSettle();
      expect(currentPage, 1);

      await tester.tapAt(const Offset(210, 380));
      await tester.pumpAndSettle();
      expect(overlayToggles, 1);

      await tester.tapAt(const Offset(40, 380));
      await tester.pumpAndSettle();
      expect(currentPage, 0);
    });

    testWidgets('animates programmatic didUpdateWidget page turns smoothly in 2-column mode', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1100, 760);
      addTearDown(tester.view.reset);

      final pages = _buildSamplePages(count: 6);
      var currentPage = 0;
      late void Function(VoidCallback) triggerSetState;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              triggerSetState = setState;
              return Scaffold(
                body: ReaderPageTurnView(
                  mode: PageTurnMode.simulation,
                  columnCount: 2,
                  config: const PaginationConfig(
                    columnWidth: 460,
                    columnHeight: 700,
                    columnCount: 2,
                    columnGap: 32,
                  ),
                  pages: pages,
                  currentPageIndex: currentPage,
                  currentChapterIndex: 0,
                  canGoPrev: currentPage > 0,
                  canGoNext: currentPage + 2 < pages.length,
                  backgroundColor: const Color(0xFFF2E6CE),
                  textColor: const Color(0xFF3A2F23),
                  secondaryTextColor: const Color(0xFF7D6E5C),
                  showOverlay: false,
                  onNextPage: () async {},
                  onPrevPage: () async {},
                  onToggleOverlay: () {},
                  onScrollOffsetChanged: (_) {},
                ),
              );
            },
          ),
        ),
      );

      expect(find.byType(ClipPath), findsNothing);

      // Programmatic forward spread advance (0 -> 2).
      triggerSetState(() => currentPage = 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(ClipPath), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(ClipPath), findsNothing);

      // Programmatic backward spread step (2 -> 0).
      triggerSetState(() => currentPage = 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(ClipPath), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(ClipPath), findsNothing);
    });
  });

  group('ReaderPagePainter grain & 2-column spine shadow', () {
    test('paints procedural paper grain and 2-column spine shadow across light & dark themes', () {
      const config = PaginationConfig(
        columnWidth: 420,
        columnHeight: 620,
        columnCount: 2,
        columnGap: 32,
        fontSize: 18,
      );
      final pages = _buildSamplePages(count: 2);

      for (final palette in const <(Color bg, Color fg, Color sec)>[
        (Color(0xFFF7F4EC), Color(0xFF2C2A26), Color(0xFF78736A)),
        (Color(0xFF1E2022), Color(0xFFCFCFCF), Color(0xFF8C9299)),
        (Color(0xFF000000), Color(0xFFB8B8B8), Color(0xFF6E6E6E)),
      ]) {
        final enhancedPainter = ReaderPagePainter(
          config: config,
          leftPage: pages[0],
          rightPage: pages[1],
          backgroundColor: palette.$1,
          textColor: palette.$2,
          secondaryTextColor: palette.$3,
          enablePaperGrain: true,
          enableSpineShadow: true,
        );
        final plainPainter = ReaderPagePainter(
          config: config,
          leftPage: pages[0],
          rightPage: pages[1],
          backgroundColor: palette.$1,
          textColor: palette.$2,
          secondaryTextColor: palette.$3,
          enablePaperGrain: false,
          enableSpineShadow: false,
        );

        expect(enhancedPainter.shouldRepaint(plainPainter), isTrue);
        expect(enhancedPainter.shouldRepaint(enhancedPainter), isFalse);

        final recEnhanced = ui.PictureRecorder();
        enhancedPainter.paint(Canvas(recEnhanced), const Size(1000, 700));
        final picEnhanced = recEnhanced.endRecording();

        final recPlain = ui.PictureRecorder();
        plainPainter.paint(Canvas(recPlain), const Size(1000, 700));
        final picPlain = recPlain.endRecording();

        expect(
          picEnhanced.approximateBytesUsed,
          greaterThan(picPlain.approximateBytesUsed),
        );

        picEnhanced.dispose();
        picPlain.dispose();
      }
    });
  });

  group('ReaderSettingsSheet simulation mode selection', () {
    testWidgets('displays and selects PageTurnMode.simulation cleanly on narrow viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 780);
      addTearDown(tester.view.reset);

      final themes = buildDefaultReaderThemes();
      var activeTheme = themes.first;
      ReaderTheme? updated;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ReaderSettingsSheet(
                  state: ReaderSessionState(
                    bookId: 'book-1',
                    isLoading: false,
                    availableThemes: themes,
                    activeTheme: activeTheme,
                  ),
                  onSelectTheme: (_) async {},
                  onUpdateTheme: (next) async {
                    updated = next;
                    setState(() => activeTheme = next);
                  },
                  onImportCustomFont: () async {},
                  onToggleKeepScreenOn: () async {},
                  onToggleVolumeKeyPaging: () async {},
                  onToggleSafeArea: () async {},
                  onToggleImmersive: () async {},
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('仿真'), findsOneWidget);
      expect(find.text('滚动'), findsOneWidget);
      expect(find.text('覆盖'), findsOneWidget);

      await tester.ensureVisible(find.text('仿真'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仿真'));
      await tester.pumpAndSettle();

      expect(updated?.pageTurnMode, PageTurnMode.simulation);
      expect(find.textContaining('仿真卷页'), findsOneWidget);
    });
  });
}
