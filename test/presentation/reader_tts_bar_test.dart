import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/application/reader/tts_sentence_splitter.dart';
import 'package:pureread/application/reader/tts_state.dart';
import 'package:pureread/infrastructure/tts/tts.dart';
import 'package:pureread/presentation/reader/reader_tts_bar.dart';
import 'package:pureread/presentation/reader/reader_tts_settings_sheet.dart';

void main() {
  group('ReaderTtsBar', () {
    TtsState buildActiveState({
      TtsStatus status = TtsStatus.playing,
      bool isDetached = false,
      bool isBarCollapsed = false,
      TtsSleepTimerMode sleepTimerMode = TtsSleepTimerMode.off,
      int? sleepRemainingSeconds,
      double speechRate = 1.0,
    }) {
      return TtsState(
        bookId: 'b1',
        bookTitle: '雪中悍刀行',
        status: status,
        utterances: const <TtsUtterance>[
          TtsUtterance(
            index: 0,
            startCharOffset: 0,
            endCharOffset: 10,
            text: '第一句测试内容。',
          ),
          TtsUtterance(
            index: 1,
            startCharOffset: 10,
            endCharOffset: 20,
            text: '第二句测试内容。',
          ),
        ],
        currentUtteranceIndex: 0,
        speakingChapterIndex: 0,
        speakingChapterTitle: '第一章 一个很长的章节标题用于验证窄屏不溢出',
        isDetached: isDetached,
        isBarCollapsed: isBarCollapsed,
        speechRate: speechRate,
        sleepTimerMode: sleepTimerMode,
        sleepRemainingSeconds: sleepRemainingSeconds,
      );
    }

    testWidgets('renders nothing when idle and triggers controls when expanded', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderTtsBar(
              state: const TtsState(),
              onTogglePlayPause: () {},
              onPrevSentence: () {},
              onNextSentence: () {},
              onOpenSettings: () {},
              onStop: () {},
            ),
          ),
        ),
      );
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

      var toggleCount = 0;
      var prevCount = 0;
      var nextCount = 0;
      var settingsCount = 0;
      var stopCount = 0;
      var jumpBackCount = 0;
      var collapseCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ReaderTtsBar(
                state: buildActiveState(
                  isDetached: true,
                  speechRate: 1.25,
                  sleepTimerMode: TtsSleepTimerMode.minutes15,
                  sleepRemainingSeconds: 895,
                ),
                readerTheme: buildDefaultReaderThemes().first,
                onTogglePlayPause: () => toggleCount++,
                onPrevSentence: () => prevCount++,
                onNextSentence: () => nextCount++,
                onOpenSettings: () => settingsCount++,
                onStop: () => stopCount++,
                onJumpBack: () => jumpBackCount++,
                onToggleCollapse: () => collapseCount++,
              ),
            ),
          ),
        ),
      );

      expect(find.text('1.25x'), findsOneWidget);
      expect(find.text('14:55'), findsOneWidget);
      expect(find.text('回到朗读处'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.tap(find.text('回到朗读处'));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pump();

      expect(toggleCount, 1);
      expect(prevCount, 1);
      expect(nextCount, 1);
      expect(settingsCount, 1);
      expect(stopCount, 1);
      expect(jumpBackCount, 1);
      expect(collapseCount, 1);
    });

    testWidgets('fits comfortably on 360dp narrow viewport in both expanded and collapsed modes', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      final darkTheme = buildDefaultReaderThemes().last;

      // Expanded with detached chip + countdown at 360dp.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ReaderTtsBar(
                state: buildActiveState(
                  isDetached: true,
                  sleepTimerMode: TtsSleepTimerMode.minutes30,
                  sleepRemainingSeconds: 1800,
                ),
                readerTheme: darkTheme,
                onTogglePlayPause: () {},
                onPrevSentence: () {},
                onNextSentence: () {},
                onOpenSettings: () {},
                onStop: () {},
                onJumpBack: () {},
                onToggleCollapse: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('回到朗读处'), findsOneWidget);

      // Collapsed floating pill with detached chip at 360dp.
      var expandedCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ReaderTtsBar(
                state: buildActiveState(
                  status: TtsStatus.paused,
                  isDetached: true,
                  isBarCollapsed: true,
                  sleepTimerMode: TtsSleepTimerMode.endOfChapter,
                ),
                readerTheme: darkTheme,
                onTogglePlayPause: () {},
                onPrevSentence: () {},
                onNextSentence: () {},
                onOpenSettings: () {},
                onStop: () {},
                onJumpBack: () {},
                onToggleCollapse: () => expandedCount++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('已暂停'), findsOneWidget);
      expect(find.text('回到朗读处'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
      expect(expandedCount, 1);
    });
  });

  group('ReaderTtsSettingsSheet', () {
    testWidgets('hides engine section when empty, sorts zh voices first, filters voices, and fires callbacks', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.reset);

      String? pickedEngine;
      String? pickedVoice;
      TtsSleepTimerMode? pickedTimer;
      double? pickedRate;
      double? pickedPitch;

      const voices = <TtsVoiceInfo>[
        TtsVoiceInfo(id: 'en_1', name: 'Samantha', locale: 'en-US'),
        TtsVoiceInfo(id: 'zh_1', name: '晓晓', locale: 'zh-CN'),
        TtsVoiceInfo(id: 'ja_1', name: 'Kyoko', locale: 'ja-JP'),
        TtsVoiceInfo(id: 'zh_2', name: '云希', locale: 'zh-CN'),
      ];

      // 1. No engines -> '朗读引擎' hidden.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderTtsSettingsSheet(
              state: const TtsState(voices: voices, voiceId: 'zh_1'),
              onSpeechRateChanged: (v) => pickedRate = v,
              onPitchChanged: (v) => pickedPitch = v,
              onSelectEngine: (id) => pickedEngine = id,
              onSelectVoice: (id) => pickedVoice = id,
              onSelectSleepTimer: (m) => pickedTimer = m,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('朗读引擎'), findsNothing);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('15分'), findsOneWidget);
      expect(find.text('30分'), findsOneWidget);
      expect(find.text('60分'), findsOneWidget);
      expect(find.text('读完本章'), findsOneWidget);

      // Verify zh voices appear before en/ja voices.
      final zhTop = tester.getTopLeft(find.text('晓晓')).dy;
      final enTop = tester.getTopLeft(find.text('Samantha')).dy;
      expect(zhTop, lessThan(enTop));

      // 2. With engines -> '朗读引擎' visible and interactive.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderTtsSettingsSheet(
              state: const TtsState(
                engines: <TtsEngineInfo>[
                  TtsEngineInfo(
                    id: 'sys',
                    label: '系统语音',
                    isDefault: true,
                  ),
                  TtsEngineInfo(id: 'multi', label: 'MultiTTS'),
                ],
                engineId: 'sys',
                voices: voices,
                voiceId: 'zh_1',
              ),
              onSpeechRateChanged: (v) => pickedRate = v,
              onPitchChanged: (v) => pickedPitch = v,
              onSelectEngine: (id) => pickedEngine = id,
              onSelectVoice: (id) => pickedVoice = id,
              onSelectSleepTimer: (m) => pickedTimer = m,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('朗读引擎'), findsOneWidget);

      await tester.tap(find.text('MultiTTS'));
      await tester.tap(find.text('读完本章'));
      await tester.pump();
      expect(pickedEngine, 'multi');
      expect(pickedTimer, TtsSleepTimerMode.endOfChapter);

      // Filter voices by '云希'.
      await tester.enterText(find.byType(TextField), '云希');
      await tester.pump();
      final filteredTileText = find.descendant(
        of: find.byType(ListTile),
        matching: find.text('云希'),
      );
      expect(filteredTileText, findsOneWidget);
      expect(find.text('Samantha'), findsNothing);

      await tester.ensureVisible(filteredTileText);
      await tester.pumpAndSettle();
      await tester.tap(filteredTileText);
      expect(pickedVoice, 'zh_2');

      // Drag rate & pitch sliders to verify callbacks.
      final sliders = find.byType(Slider);
      await tester.drag(sliders.at(0), const Offset(80, 0));
      await tester.drag(sliders.at(1), const Offset(-60, 0));
      await tester.pump();
      expect(pickedRate, isNotNull);
      expect(pickedPitch, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}
