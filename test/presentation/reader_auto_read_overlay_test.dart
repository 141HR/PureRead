import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/reader/auto_read_state.dart';
import 'package:pureread/presentation/reader/reader_auto_read_bar.dart';
import 'package:pureread/presentation/reader/reader_auto_read_overlay.dart';

void _setOverlayViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.reset);
}

double _translationYForKey(WidgetTester tester, String key) {
  final transform = tester.widget<Transform>(find.byKey(ValueKey<String>(key)));
  return transform.transform.getTranslation().y;
}

Widget _wrapOverlay({
  required AutoReadState state,
  required bool canGoNext,
  required Future<void> Function() onAdvancePage,
  required VoidCallback onToggleControls,
  VoidCallback? onReachedBookEnd,
  Widget? currentPageChild,
  Widget? nextPageChild,
  Object? pageKey,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 800,
        child: ReaderAutoReadOverlay(
          currentPageChild:
              currentPageChild ??
              const ColoredBox(
                key: ValueKey<String>('current_page'),
                color: Color(0xFFF7F4EC),
                child: Center(child: Text('当前页正文')),
              ),
          nextPageChild: nextPageChild,
          state: state,
          canGoNext: canGoNext,
          accentColor: const Color(0xFF4A6B53),
          dividerColor: const Color(0xFF78736A),
          onAdvancePage: onAdvancePage,
          onToggleControls: onToggleControls,
          onReachedBookEnd: onReachedBookEnd,
          pageKey: pageKey,
        ),
      ),
    ),
  );
}

void main() {
  group('ReaderAutoReadOverlay', () {
    testWidgets('scroll mode translates current upward and next from bottom seamlessly', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      var advances = 0;
      var toggleCalls = 0;

      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.scroll,
            status: AutoReadStatus.running,
            scrollSeconds: 10,
          ),
          canGoNext: true,
          nextPageChild: const ColoredBox(
            key: ValueKey<String>('next_page'),
            color: Color(0xFFEFECE4),
            child: Center(child: Text('下一页正文')),
          ),
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () => toggleCalls++,
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('auto_read_curtain_scan_line')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('auto_read_scroll_page_seam')),
        findsOneWidget,
      );
      expect(
        _translationYForKey(tester, 'auto_read_scroll_current_page'),
        closeTo(0.0, 0.5),
      );
      expect(
        _translationYForKey(tester, 'auto_read_scroll_next_page'),
        closeTo(800.0, 0.5),
      );

      await tester.pump(const Duration(seconds: 5));
      expect(
        _translationYForKey(tester, 'auto_read_scroll_current_page'),
        closeTo(-400.0, 2.0),
      );
      expect(
        _translationYForKey(tester, 'auto_read_scroll_next_page'),
        closeTo(400.0, 2.0),
      );
      expect(advances, 0);

      // Single-tap toggles controls.
      await tester.tap(find.byType(ReaderAutoReadOverlay));
      await tester.pump();
      expect(toggleCalls, 1);

      // Complete first scroll cycle -> calls onAdvancePage and restarts from 0.0.
      await tester.pump(const Duration(seconds: 5, milliseconds: 16));
      await tester.pump();
      expect(advances, 1);

      // Halfway through the next page scroll.
      await tester.pump(const Duration(seconds: 5));
      expect(
        _translationYForKey(tester, 'auto_read_scroll_current_page'),
        closeTo(-400.0, 4.0),
      );
      expect(
        _translationYForKey(tester, 'auto_read_scroll_next_page'),
        closeTo(400.0, 4.0),
      );

      await tester.pump(const Duration(seconds: 5, milliseconds: 16));
      await tester.pump();
      expect(advances, 2);
    });

    testWidgets('scroll mode safely falls back when nextPageChild is null', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.scroll,
            status: AutoReadStatus.running,
            scrollSeconds: 8,
          ),
          canGoNext: true,
          nextPageChild: null,
          onAdvancePage: () async {},
          onToggleControls: () {},
        ),
      );

      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
      expect(
        _translationYForKey(tester, 'auto_read_scroll_next_page'),
        closeTo(400.0, 2.0),
      );
    });

    testWidgets('scroll mode supports manual vertical drag scrubbing and resumes cleanly', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      var advances = 0;

      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.scroll,
            status: AutoReadStatus.running,
            scrollSeconds: 10,
          ),
          canGoNext: true,
          nextPageChild: const ColoredBox(
            key: ValueKey<String>('next_page'),
            color: Color(0xFFEFECE4),
            child: Center(child: Text('下一页正文')),
          ),
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );

      // Drag upward by 400px (delta.dy = -400) -> progress jumps by ~0.5.
      await tester.drag(
        find.byType(ReaderAutoReadOverlay),
        const Offset(0, -400),
      );
      await tester.pump();

      final midY = _translationYForKey(tester, 'auto_read_scroll_next_page');
      expect(midY, lessThan(600.0));
      expect(advances, 0);

      // Resumes forward from the scrubbed offset and finishes within 6s.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(advances, 1);
    });

    testWidgets('timedTurn mode shows unobstructed currentPage with 2.5px bottom progress and turns on completion', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      var advances = 0;

      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.timedTurn,
            status: AutoReadStatus.running,
            turnSeconds: 8,
          ),
          canGoNext: true,
          nextPageChild: const Text(
            '隐藏下一页',
            key: ValueKey<String>('next_page'),
          ),
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );

      expect(find.byKey(const ValueKey<String>('next_page')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('auto_read_scroll_page_seam')),
        findsNothing,
      );

      final barFinder = find.byKey(
        const ValueKey<String>('auto_read_timed_progress'),
      );
      expect(barFinder, findsOneWidget);
      expect(tester.getSize(barFinder).height, 2.5);

      await tester.pump(const Duration(seconds: 4));
      final fractionBox = tester.widget<FractionallySizedBox>(
        find.descendant(
          of: barFinder,
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(fractionBox.widthFactor, closeTo(0.5, 0.02));
      expect(advances, 0);

      await tester.pump(const Duration(seconds: 4, milliseconds: 16));
      await tester.pump();
      expect(advances, 1);

      // Restarts cleanly for next interval.
      await tester.pump(const Duration(seconds: 4));
      final restartedBox = tester.widget<FractionallySizedBox>(
        find.descendant(
          of: barFinder,
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(restartedBox.widthFactor, closeTo(0.5, 0.02));
    });

    testWidgets('pause and resume freeze and continue from preserved progress', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      var advances = 0;
      const runningState = AutoReadState(
        mode: AutoReadMode.scroll,
        status: AutoReadStatus.running,
        scrollSeconds: 10,
      );
      const pausedState = AutoReadState(
        mode: AutoReadMode.scroll,
        status: AutoReadStatus.paused,
        scrollSeconds: 10,
      );

      await tester.pumpWidget(
        _wrapOverlay(
          state: runningState,
          canGoNext: true,
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );

      await tester.pump(const Duration(seconds: 4));
      final pausedOffset = _translationYForKey(
        tester,
        'auto_read_scroll_current_page',
      );
      expect(pausedOffset, closeTo(-320.0, 2.0));

      // Pause and let significant time elapse -> frozen in place.
      await tester.pumpWidget(
        _wrapOverlay(
          state: pausedState,
          canGoNext: true,
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );
      await tester.pump(const Duration(seconds: 12));
      expect(
        _translationYForKey(tester, 'auto_read_scroll_current_page'),
        closeTo(pausedOffset, 0.5),
      );
      expect(advances, 0);

      // Resume -> needs remaining 6 seconds to complete.
      await tester.pumpWidget(
        _wrapOverlay(
          state: runningState,
          canGoNext: true,
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(advances, 0);
      expect(
        _translationYForKey(tester, 'auto_read_scroll_current_page'),
        closeTo(-720.0, 4.0),
      );

      await tester.pump(const Duration(seconds: 1, milliseconds: 16));
      await tester.pump();
      expect(advances, 1);
    });

    testWidgets('live speed change preserves normalized progress and adjusts remaining time', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      var advances = 0;

      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.scroll,
            status: AutoReadStatus.running,
            scrollSeconds: 20,
          ),
          canGoNext: true,
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );

      // Advance 5s out of 20s => p = 0.25 (offsetY = 200).
      await tester.pump(const Duration(seconds: 5));
      expect(
        _translationYForKey(tester, 'auto_read_scroll_current_page'),
        closeTo(-200.0, 2.0),
      );

      // Speed up live to 8s/page -> progress stays at 0.25; remaining 0.75 * 8s = 6s.
      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.scroll,
            status: AutoReadStatus.running,
            scrollSeconds: 8,
          ),
          canGoNext: true,
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );

      expect(
        _translationYForKey(tester, 'auto_read_scroll_current_page'),
        closeTo(-200.0, 2.0),
      );

      await tester.pump(const Duration(seconds: 5));
      expect(advances, 0);
      await tester.pump(const Duration(seconds: 1, milliseconds: 16));
      await tester.pump();
      expect(advances, 1);
    });

    testWidgets('mode switching resets cleanly and updates overlay mode', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      var advances = 0;

      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.scroll,
            status: AutoReadStatus.running,
            scrollSeconds: 10,
            turnSeconds: 6,
          ),
          canGoNext: true,
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );

      await tester.pump(const Duration(seconds: 5));
      expect(
        find.byKey(const ValueKey<String>('auto_read_scroll_page_seam')),
        findsOneWidget,
      );

      // Switch to timedTurn -> scroll layer disappears, 2.5px bar starts from 0 over 6s.
      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.timedTurn,
            status: AutoReadStatus.running,
            scrollSeconds: 10,
            turnSeconds: 6,
          ),
          canGoNext: true,
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('auto_read_scroll_page_seam')),
        findsNothing,
      );
      final barFinder = find.byKey(
        const ValueKey<String>('auto_read_timed_progress'),
      );
      expect(barFinder, findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      final box = tester.widget<FractionallySizedBox>(
        find.descendant(
          of: barFinder,
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(box.widthFactor, closeTo(0.5, 0.05));
      expect(advances, 0);

      await tester.pump(const Duration(seconds: 3, milliseconds: 16));
      await tester.pump();
      expect(advances, 1);
    });

    testWidgets('invokes onReachedBookEnd once when canGoNext is false', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      var advances = 0;
      var bookEndCalls = 0;

      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(
            mode: AutoReadMode.scroll,
            status: AutoReadStatus.running,
            scrollSeconds: 6,
          ),
          canGoNext: false,
          onAdvancePage: () async {
            advances++;
          },
          onToggleControls: () {},
          onReachedBookEnd: () => bookEndCalls++,
        ),
      );

      await tester.pump(const Duration(seconds: 6, milliseconds: 16));
      await tester.pump(const Duration(seconds: 4));

      expect(advances, 0);
      expect(bookEndCalls, 1);
    });

    testWidgets('renders unobstructed currentPageChild when idle', (
      tester,
    ) async {
      _setOverlayViewport(tester);
      await tester.pumpWidget(
        _wrapOverlay(
          state: const AutoReadState(status: AutoReadStatus.idle),
          canGoNext: true,
          onAdvancePage: () async {},
          onToggleControls: () {},
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('auto_read_scroll_page_seam')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('auto_read_timed_progress')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('current_page')), findsOneWidget);
    });
  });

  group('ReaderAutoReadBar', () {
    testWidgets('fits comfortably inside 360dp narrow phones without overflow and wires all actions', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      var state = const AutoReadState(
        mode: AutoReadMode.scroll,
        status: AutoReadStatus.running,
        scrollSeconds: 18,
        turnSeconds: 12,
        showControls: true,
      );
      var stopCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: ReaderAutoReadBar(
                    state: state,
                    onTogglePause: () => setState(() {
                      state = state.copyWith(
                        status: state.isRunning
                            ? AutoReadStatus.paused
                            : AutoReadStatus.running,
                      );
                    }),
                    onModeChanged: (mode) => setState(() {
                      state = state.copyWith(mode: mode);
                    }),
                    onScrollSecondsChanged: (seconds) => setState(() {
                      state = state.copyWith(scrollSeconds: seconds);
                    }),
                    onTurnSecondsChanged: (seconds) => setState(() {
                      state = state.copyWith(turnSeconds: seconds);
                    }),
                    onStop: () => stopCalls++,
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('18s/页'), findsOneWidget);
      expect(find.text('平滑滚屏'), findsOneWidget);
      expect(find.text('定时翻页'), findsOneWidget);
      expect(find.text('停止'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      // Stepper + / -
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(state.scrollSeconds, 19);
      expect(find.text('19s/页'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      expect(state.scrollSeconds, 18);

      // Pause toggle
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(state.isPaused, isTrue);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Mode toggle -> timedTurn updates readout to 12s/页
      await tester.tap(find.text('定时翻页'));
      await tester.pump();
      expect(state.mode, AutoReadMode.timedTurn);
      expect(find.text('12s/页'), findsOneWidget);

      // Stepper in timedTurn adjusts turnSeconds
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      expect(state.turnSeconds, 11);
      expect(find.text('11s/页'), findsOneWidget);

      // Stop button
      await tester.tap(find.text('停止'));
      await tester.pump();
      expect(stopCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides cleanly when idle or showControls is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderAutoReadBar(
              state: const AutoReadState(
                status: AutoReadStatus.running,
                showControls: false,
              ),
              onTogglePause: () {},
              onModeChanged: (_) {},
              onScrollSecondsChanged: (_) {},
              onTurnSecondsChanged: (_) {},
              onStop: () {},
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('auto_read_control_bar')),
        findsNothing,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderAutoReadBar(
              state: const AutoReadState(
                status: AutoReadStatus.idle,
                showControls: true,
              ),
              onTogglePause: () {},
              onModeChanged: (_) {},
              onScrollSecondsChanged: (_) {},
              onTurnSecondsChanged: (_) {},
              onStop: () {},
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('auto_read_control_bar')),
        findsNothing,
      );
    });
  });
}
