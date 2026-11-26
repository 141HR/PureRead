import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/application/reader/tts_controller.dart';
import 'package:pureread/application/reader/tts_state.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/tts/tts.dart';

class _FakeTtsEngine implements TtsEngine {
  final StreamController<TtsEvent> _events =
      StreamController<TtsEvent>.broadcast();

  TtsInitResult initResult = const TtsInitResult(
    available: true,
    engine: 'engine_a',
  );
  List<TtsEngineInfo> availableEngines = const <TtsEngineInfo>[
    TtsEngineInfo(id: 'engine_a', label: '默认引擎', isDefault: true),
    TtsEngineInfo(id: 'engine_b', label: '离线引擎'),
  ];
  List<TtsVoiceInfo> availableVoices = const <TtsVoiceInfo>[
    TtsVoiceInfo(id: 'en_us', name: 'English Voice', locale: 'en-US'),
    TtsVoiceInfo(id: 'zh_cn_1', name: '晓晓', locale: 'zh-CN'),
    TtsVoiceInfo(id: 'zh_tw_1', name: '曉臻', locale: 'zh-TW'),
  ];

  final List<String> spokenTexts = <String>[];
  final List<String> spokenUtteranceIds = <String>[];
  final List<double> setRateCalls = <double>[];
  final List<double> setPitchCalls = <double>[];
  final List<String> setEngineCalls = <String>[];
  final List<String> setVoiceCalls = <String>[];
  int stopCalls = 0;
  int pauseNotificationCalls = 0;
  int updateMetadataCalls = 0;
  int shutdownCalls = 0;
  bool nextSpeakResult = true;

  void emit(TtsEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  @override
  Future<TtsInitResult> initialize() async => initResult;

  @override
  Future<List<TtsEngineInfo>> getEngines() async => availableEngines;

  @override
  Future<bool> setEngine(String engineId) async {
    setEngineCalls.add(engineId);
    return availableEngines.any((e) => e.id == engineId);
  }

  @override
  Future<List<TtsVoiceInfo>> getVoices() async => availableVoices;

  @override
  Future<bool> setVoice(String voiceId) async {
    setVoiceCalls.add(voiceId);
    return availableVoices.any((v) => v.id == voiceId);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    setRateCalls.add(rate);
  }

  @override
  Future<void> setPitch(double pitch) async {
    setPitchCalls.add(pitch);
  }

  @override
  Future<bool> speak({
    required String text,
    required String utteranceId,
    String? bookTitle,
    String? chapterTitle,
  }) async {
    spokenTexts.add(text);
    spokenUtteranceIds.add(utteranceId);
    return nextSpeakResult;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> pauseNotification({
    String? bookTitle,
    String? chapterTitle,
  }) async {
    pauseNotificationCalls++;
  }

  @override
  Future<void> updateMetadata({
    String? bookTitle,
    String? chapterTitle,
    required bool isPlaying,
  }) async {
    updateMetadataCalls++;
  }

  @override
  Future<void> shutdown() async {
    shutdownCalls++;
  }

  @override
  Stream<TtsEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

class _FakeThemeRepository implements ThemeRepository {
  final Map<String, ReaderTheme> _themes = <String, ReaderTheme>{
    for (final t in buildDefaultReaderThemes()) t.id: t,
  };
  final Map<String, AppSetting> settings = <String, AppSetting>{};

  @override
  Stream<List<ReaderTheme>> watchThemes() =>
      Stream<List<ReaderTheme>>.value(_themes.values.toList(growable: false));

  @override
  Future<List<ReaderTheme>> listThemes() async =>
      _themes.values.toList(growable: false);

  @override
  Future<ReaderTheme?> getThemeById(String themeId) async => _themes[themeId];

  @override
  Future<void> saveTheme(ReaderTheme theme) async => _themes[theme.id] = theme;

  @override
  Future<void> deleteTheme(String themeId) async => _themes.remove(themeId);

  @override
  Future<AppSetting?> getSetting(String key) async => settings[key];

  @override
  Future<List<AppSetting>> listSettings() async =>
      settings.values.toList(growable: false);

  @override
  Future<void> saveSetting(AppSetting setting) async {
    settings[setting.key] = setting;
  }
}

Future<void> _pumpMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelTtsEngine', () {
    const channel = MethodChannel(MethodChannelTtsEngine.channelName);
    const eventsChannelName = MethodChannelTtsEngine.eventsChannelName;

    late MethodChannelTtsEngine engine;
    final recordedCalls = <MethodCall>[];

    setUp(() {
      recordedCalls.clear();
      engine = MethodChannelTtsEngine();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            recordedCalls.add(call);
            return switch (call.method) {
              'initialize' => <String, Object?>{
                'available': true,
                'engine': 'com.google.android.tts',
                'error': null,
              },
              'getEngines' => <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'com.google.android.tts',
                  'label': 'Google TTS',
                  'isDefault': true,
                },
              ],
              'getVoices' => <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'zh-cn-x',
                  'name': '普通话女声',
                  'locale': 'zh-CN',
                },
              ],
              'setEngine' || 'setVoice' || 'speak' => true,
              _ => null,
            };
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(eventsChannelName),
            null,
          );
      await engine.dispose();
    });

    test('invokes Contract B methods and clamps rate and pitch', () async {
      final init = await engine.initialize();
      expect(init.available, isTrue);
      expect(init.engine, 'com.google.android.tts');

      final engines = await engine.getEngines();
      expect(engines.single.id, 'com.google.android.tts');
      expect(engines.single.isDefault, isTrue);

      expect(await engine.setEngine('com.google.android.tts'), isTrue);
      final voices = await engine.getVoices();
      expect(voices.single.id, 'zh-cn-x');
      expect(await engine.setVoice('zh-cn-x'), isTrue);

      await engine.setSpeechRate(5.0);
      await engine.setPitch(0.1);
      expect(
        await engine.speak(
          text: '你好世界',
          utteranceId: 'u1',
          bookTitle: '测试书',
          chapterTitle: '第一章',
        ),
        isTrue,
      );
      await engine.pauseNotification(bookTitle: '测试书', chapterTitle: '第一章');
      await engine.updateMetadata(
        bookTitle: '测试书',
        chapterTitle: '第一章',
        isPlaying: false,
      );
      await engine.stop();
      await engine.shutdown();

      final rateCall = recordedCalls.firstWhere(
        (c) => c.method == 'setSpeechRate',
      );
      expect(rateCall.arguments, equals(<String, Object>{'rate': 2.5}));

      final pitchCall = recordedCalls.firstWhere(
        (c) => c.method == 'setPitch',
      );
      expect(pitchCall.arguments, equals(<String, Object>{'pitch': 0.5}));
    });

    test('parses EventChannel events including mediaAction', () async {
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel(eventsChannelName),
        (call) async => null,
      );

      final received = <TtsEvent>[];
      final sub = engine.events.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      Future<void> dispatch(Map<String, Object?> payload) {
        return messenger.handlePlatformMessage(
          eventsChannelName,
          codec.encodeSuccessEnvelope(payload),
          (_) {},
        );
      }

      await dispatch(<String, Object?>{'type': 'start', 'utteranceId': 'u1'});
      await dispatch(<String, Object?>{
        'type': 'progress',
        'utteranceId': 'u1',
        'start': 1,
        'end': 4,
      });
      await dispatch(<String, Object?>{'type': 'complete', 'utteranceId': 'u1'});
      await dispatch(<String, Object?>{
        'type': 'mediaAction',
        'action': 'resumeFromFocus',
      });
      await dispatch(<String, Object?>{
        'type': 'error',
        'utteranceId': 'u2',
        'message': 'synthesis failed',
      });
      await _pumpMicrotasks();

      expect(
        received,
        equals(<TtsEvent>[
          const TtsStartEvent(utteranceId: 'u1'),
          const TtsProgressEvent(utteranceId: 'u1', start: 1, end: 4),
          const TtsCompleteEvent(utteranceId: 'u1'),
          const TtsMediaActionEvent(action: TtsMediaAction.resumeFromFocus),
          const TtsErrorEvent(utteranceId: 'u2', message: 'synthesis failed'),
        ]),
      );
      await sub.cancel();
    });

    test('handles MissingPluginException gracefully without throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      final init = await engine.initialize();
      expect(init.available, isFalse);
      expect(await engine.getEngines(), isEmpty);
      expect(await engine.getVoices(), isEmpty);
      expect(await engine.setEngine('x'), isFalse);
      expect(await engine.setVoice('y'), isFalse);
      expect(await engine.speak(text: 'a', utteranceId: 'u'), isFalse);
      await engine.setSpeechRate(1.2);
      await engine.setPitch(1.0);
      await engine.pauseNotification();
      await engine.updateMetadata(isPlaying: true);
      await engine.stop();
      await engine.shutdown();
    });
  });

  group('TtsController', () {
    late _FakeTtsEngine fakeEngine;
    late _FakeThemeRepository fakeThemeRepo;
    late ProviderContainer container;
    late Map<int, String> chapters;
    late List<(int, int)> navigatedPositions;
    late List<int> loadedChapters;
    late TtsReaderHost host;

    setUp(() {
      fakeEngine = _FakeTtsEngine();
      fakeThemeRepo = _FakeThemeRepository();
      chapters = <int, String>{
        0: '第一句开始了。\n\uFFFCprimg:v1:img%2F01.jpg|800x600|插画\uFFFC\n第二句紧随其后！第三句收尾。',
        1: '第二章第一句。第二章第二句。',
        2: '第三章内容。',
      };
      navigatedPositions = <(int, int)>[];
      loadedChapters = <int>[];
      host = TtsReaderHost(
        loadChapterText: (index) async {
          loadedChapters.add(index);
          return chapters[index];
        },
        navigateToPosition: (chapterIndex, charOffset) async {
          navigatedPositions.add((chapterIndex, charOffset));
        },
        getChapterTitle: (index) => '第${index + 1}章',
        getChapterCount: () => chapters.length,
      );
      container = ProviderContainer(
        overrides: [
          ttsEngineProvider.overrideWithValue(fakeEngine),
          themeRepositoryProvider.overrideWithValue(fakeThemeRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('splits chapter skipping image markers, sorts zh voices, and auto-follows pages', () async {
      final controller = container.read(ttsControllerProvider.notifier);
      await controller.start(
        bookId: 'book-1',
        bookTitle: '测试小说',
        host: host,
        chapterIndex: 0,
        chapterText: chapters[0]!,
        startCharOffset: 0,
      );

      final state = container.read(ttsControllerProvider);
      expect(state.status, TtsStatus.playing);
      expect(state.utterances.map((u) => u.text), equals(<String>[
        '第一句开始了。',
        '第二句紧随其后！',
        '第三句收尾。',
      ]));
      // Chinese voices sorted ahead of English voice.
      expect(
        state.voices.map((v) => v.locale).toList(),
        equals(<String>['zh-CN', 'zh-TW', 'en-US']),
      );
      expect(state.currentUtteranceIndex, 0);
      expect(state.activeHighlightRange, (0, 7));

      // Report viewport showing only sentence 0 (0..10).
      final u1 = state.utterances[1];
      controller.onViewportLocationChanged(0, 0, u1.startCharOffset);
      expect(container.read(ttsControllerProvider).isDetached, isFalse);

      // Complete utterance 0 -> advances to utterance 1 outside [0, u1.start),
      // triggering auto-follow navigateToPosition.
      fakeEngine.emit(
        TtsCompleteEvent(utteranceId: fakeEngine.spokenUtteranceIds.last),
      );
      await _pumpMicrotasks();

      final afterAdvance = container.read(ttsControllerProvider);
      expect(afterAdvance.currentUtteranceIndex, 1);
      expect(afterAdvance.activeHighlightRange, (u1.startCharOffset, u1.endCharOffset));
      expect(navigatedPositions, equals(<(int, int)>[(0, u1.startCharOffset)]));
    });

    test('supports detached browsing, silent cross-chapter transition, and jumpBackToSpeakingPosition', () async {
      final controller = container.read(ttsControllerProvider.notifier);
      await controller.start(
        bookId: 'book-1',
        bookTitle: '测试小说',
        host: host,
        chapterIndex: 0,
        chapterText: chapters[0]!,
      );
      controller.onViewportLocationChanged(0, 0, 20);

      // User scrolls far away inside chapter 0 -> detached without stopping.
      controller.onViewportLocationChanged(0, 200, 300);
      var state = container.read(ttsControllerProvider);
      expect(state.isDetached, isTrue);
      expect(state.status, TtsStatus.playing);
      expect(fakeEngine.stopCalls, 0);

      // Complete utterance 0, 1, 2 -> crosses into chapter 1 SILENTLY.
      for (var i = 0; i < 3; i++) {
        fakeEngine.emit(
          TtsCompleteEvent(utteranceId: fakeEngine.spokenUtteranceIds.last),
        );
        await _pumpMicrotasks();
      }

      state = container.read(ttsControllerProvider);
      expect(state.speakingChapterIndex, 1);
      expect(state.speakingChapterTitle, '第2章');
      expect(state.currentUtterance?.text, '第二章第一句。');
      expect(state.isDetached, isTrue);
      expect(loadedChapters, equals(<int>[1]));
      // Viewport was NEVER pulled while detached!
      expect(navigatedPositions, isEmpty);

      // User taps 回到朗读处 -> clears isDetached and navigates to chapter 1 offset 0.
      await controller.jumpBackToSpeakingPosition();
      state = container.read(ttsControllerProvider);
      expect(state.isDetached, isFalse);
      expect(navigatedPositions, equals(<(int, int)>[(1, 0)]));
    });

    test('guards stale and duplicate utterance completion events', () async {
      final controller = container.read(ttsControllerProvider.notifier);
      await controller.start(
        bookId: 'book-1',
        bookTitle: '测试小说',
        host: host,
        chapterIndex: 0,
        chapterText: chapters[0]!,
      );
      final firstId = fakeEngine.spokenUtteranceIds.last;

      // Pause invalidates firstId.
      await controller.pause();
      expect(fakeEngine.pauseNotificationCalls, 1);
      expect(container.read(ttsControllerProvider).status, TtsStatus.paused);

      // Stale complete event arriving after pause must be ignored.
      fakeEngine.emit(TtsCompleteEvent(utteranceId: firstId));
      await _pumpMicrotasks();
      expect(container.read(ttsControllerProvider).currentUtteranceIndex, 0);
      expect(container.read(ttsControllerProvider).status, TtsStatus.paused);

      // Resume gets a new utteranceId; duplicate completion of newId advances once only.
      await controller.resume();
      final resumedId = fakeEngine.spokenUtteranceIds.last;
      expect(resumedId, isNot(firstId));

      fakeEngine.emit(TtsCompleteEvent(utteranceId: resumedId));
      fakeEngine.emit(TtsCompleteEvent(utteranceId: resumedId));
      await _pumpMicrotasks();

      expect(container.read(ttsControllerProvider).currentUtteranceIndex, 1);
      expect(
        container.read(ttsControllerProvider).currentUtterance?.text,
        '第二句紧随其后！',
      );
    });

    test('handles prev/next sentences across chapters and media actions', () async {
      final controller = container.read(ttsControllerProvider.notifier);
      await controller.start(
        bookId: 'book-1',
        bookTitle: '测试小说',
        host: host,
        chapterIndex: 1,
        chapterText: chapters[1]!,
      );
      expect(container.read(ttsControllerProvider).currentUtterance?.text, '第二章第一句。');

      // prevSentence at index 0 loads last utterance of chapter 0.
      await controller.prevSentence();
      var state = container.read(ttsControllerProvider);
      expect(state.speakingChapterIndex, 0);
      expect(state.currentUtterance?.text, '第三句收尾。');

      // Media actions: pause -> resumeFromFocus -> next -> stop.
      fakeEngine.emit(const TtsMediaActionEvent(action: TtsMediaAction.pause));
      await _pumpMicrotasks();
      expect(container.read(ttsControllerProvider).status, TtsStatus.paused);

      fakeEngine.emit(
        const TtsMediaActionEvent(action: TtsMediaAction.resumeFromFocus),
      );
      await _pumpMicrotasks();
      expect(container.read(ttsControllerProvider).status, TtsStatus.playing);

      fakeEngine.emit(const TtsMediaActionEvent(action: TtsMediaAction.next));
      await _pumpMicrotasks();
      state = container.read(ttsControllerProvider);
      expect(state.speakingChapterIndex, 1);
      expect(state.currentUtterance?.text, '第二章第一句。');

      fakeEngine.emit(const TtsMediaActionEvent(action: TtsMediaAction.stop));
      await _pumpMicrotasks();
      state = container.read(ttsControllerProvider);
      expect(state.status, TtsStatus.idle);
      expect(state.activeHighlightRange, isNull);
    });

    test('persists and restores rate, pitch, engine, and voice via themeRepositoryProvider', () async {
      final controller = container.read(ttsControllerProvider.notifier);
      await controller.start(
        bookId: 'book-1',
        bookTitle: '测试小说',
        host: host,
        chapterIndex: 0,
        chapterText: chapters[0]!,
      );

      await controller.setSpeechRate(1.5);
      await controller.setPitch(1.25);
      expect(await controller.setEngine('engine_b'), isTrue);
      expect(await controller.setVoice('zh_tw_1'), isTrue);

      expect(fakeThemeRepo.settings['tts_speech_rate']?.value, '1.5');
      expect(fakeThemeRepo.settings['tts_pitch']?.value, '1.25');
      expect(fakeThemeRepo.settings['tts_engine_id']?.value, 'engine_b');
      expect(fakeThemeRepo.settings['tts_voice_id']?.value, 'zh_tw_1');

      // Restore in a fresh container using the same ThemeRepository.
      final engine2 = _FakeTtsEngine();
      final container2 = ProviderContainer(
        overrides: [
          ttsEngineProvider.overrideWithValue(engine2),
          themeRepositoryProvider.overrideWithValue(fakeThemeRepo),
        ],
      );
      addTearDown(container2.dispose);

      final controller2 = container2.read(ttsControllerProvider.notifier);
      await controller2.start(
        bookId: 'book-1',
        bookTitle: '测试小说',
        host: host,
        chapterIndex: 0,
        chapterText: chapters[0]!,
      );

      final restored = container2.read(ttsControllerProvider);
      expect(restored.speechRate, 1.5);
      expect(restored.pitch, 1.25);
      expect(restored.engineId, 'engine_b');
      expect(restored.voiceId, 'zh_tw_1');
      expect(engine2.setEngineCalls, contains('engine_b'));
      expect(engine2.setVoiceCalls, contains('zh_tw_1'));
      expect(engine2.setRateCalls, contains(1.5));
      expect(engine2.setPitchCalls, contains(1.25));
    });

    test('stops before next chapter in endOfChapter sleep mode', () async {
      final controller = container.read(ttsControllerProvider.notifier);
      await controller.start(
        bookId: 'book-1',
        bookTitle: '测试小说',
        host: host,
        chapterIndex: 1,
        chapterText: chapters[1]!,
      );

      controller.setSleepTimer(TtsSleepTimerMode.endOfChapter);
      expect(
        container.read(ttsControllerProvider).sleepTimerMode,
        TtsSleepTimerMode.endOfChapter,
      );

      // Utterance 0 -> Utterance 1 (still same chapter).
      fakeEngine.emit(
        TtsCompleteEvent(utteranceId: fakeEngine.spokenUtteranceIds.last),
      );
      await _pumpMicrotasks();
      expect(container.read(ttsControllerProvider).status, TtsStatus.playing);
      expect(container.read(ttsControllerProvider).currentUtteranceIndex, 1);

      // Utterance 1 (last in chapter 1) completes -> stops before loading chapter 2!
      fakeEngine.emit(
        TtsCompleteEvent(utteranceId: fakeEngine.spokenUtteranceIds.last),
      );
      await _pumpMicrotasks();

      final stopped = container.read(ttsControllerProvider);
      expect(stopped.status, TtsStatus.idle);
      expect(stopped.sleepTimerMode, TtsSleepTimerMode.off);
      expect(loadedChapters, isEmpty);
      expect(fakeEngine.stopCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('counts down timed sleep timer per second and stops on zero', (
      tester,
    ) async {
      final controller = container.read(ttsControllerProvider.notifier);
      await controller.start(
        bookId: 'book-1',
        bookTitle: '测试小说',
        host: host,
        chapterIndex: 0,
        chapterText: chapters[0]!,
      );

      controller.setSleepTimer(TtsSleepTimerMode.minutes15);
      expect(container.read(ttsControllerProvider).sleepRemainingSeconds, 900);

      await tester.pump(const Duration(seconds: 3));
      expect(container.read(ttsControllerProvider).sleepRemainingSeconds, 897);
      expect(container.read(ttsControllerProvider).status, TtsStatus.playing);

      await tester.pump(const Duration(seconds: 897));
      await tester.pump();
      expect(container.read(ttsControllerProvider).status, TtsStatus.idle);
      expect(
        container.read(ttsControllerProvider).sleepTimerMode,
        TtsSleepTimerMode.off,
      );
      expect(
        container.read(ttsControllerProvider).sleepRemainingSeconds,
        isNull,
      );
    });
  });
}
