import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../../infrastructure/tts/tts.dart';
import '../core_providers.dart';
import 'tts_sentence_splitter.dart';
import 'tts_state.dart';

const String _kTtsSpeechRateKey = 'tts_speech_rate';
const String _kTtsPitchKey = 'tts_pitch';
const String _kTtsEngineIdKey = 'tts_engine_id';
const String _kTtsVoiceIdKey = 'tts_voice_id';

/// Provides the platform [TtsEngine] implementation and disposes its streams
/// when the provider scope is torn down.
final ttsEngineProvider = Provider<TtsEngine>((ref) {
  final engine = MethodChannelTtsEngine();
  ref.onDispose(() {
    unawaited(engine.dispose());
  });
  return engine;
});

/// Reader session callbacks consumed by [TtsController] for chapter loading,
/// auto-follow navigation, and jump-back restoration.
class TtsReaderHost {
  const TtsReaderHost({
    required this.loadChapterText,
    required this.navigateToPosition,
    required this.getChapterTitle,
    required this.getChapterCount,
  });

  final Future<String?> Function(int chapterIndex) loadChapterText;
  final Future<void> Function(int chapterIndex, int charOffset)
  navigateToPosition;
  final String Function(int chapterIndex) getChapterTitle;
  final int Function() getChapterCount;
}

final ttsControllerProvider = NotifierProvider<TtsController, TtsState>(
  TtsController.new,
);

/// Orchestrates sentence-by-sentence TTS playback, detached browsing
/// (`分离浏览`), cross-chapter progression, sleep timers, media actions, and
/// persistent TTS settings.
class TtsController extends Notifier<TtsState> {
  bool _disposed = false;
  bool _settingsLoaded = false;
  bool _engineInitialized = false;
  bool _isAutoNavigating = false;

  int _playbackEpoch = 0;
  int _utteranceSequence = 0;
  String? _activeUtteranceId;

  bool _hasViewportLocation = false;
  int _viewportChapterIndex = 0;
  int _viewportVisibleStart = 0;
  int _viewportVisibleEnd = 0;

  TtsReaderHost? _host;
  Timer? _sleepTimer;
  StreamSubscription<TtsEvent>? _eventsSubscription;
  late TtsState _snapshot;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  TtsState build() {
    _disposed = false;
    _settingsLoaded = false;
    _engineInitialized = false;
    _isAutoNavigating = false;
    _playbackEpoch = 0;
    _utteranceSequence = 0;
    _activeUtteranceId = null;
    _hasViewportLocation = false;
    _host = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    unawaited(_eventsSubscription?.cancel());
    _eventsSubscription = null;

    final engine = ref.read(ttsEngineProvider);
    const initial = TtsState();
    _snapshot = initial;

    ref.onDispose(() {
      _disposed = true;
      _sleepTimer?.cancel();
      _sleepTimer = null;
      unawaited(_eventsSubscription?.cancel());
      _eventsSubscription = null;
      _host = null;
      _activeUtteranceId = null;

      if (_snapshot.isActive) {
        unawaited(engine.stop());
      }
    });

    return initial;
  }

  void _commit(TtsState next) {
    if (!_isAlive) return;
    _snapshot = next;
    state = next;
  }

  /// Attaches or replaces the active [TtsReaderHost] callbacks.
  void attachHost(TtsReaderHost host) {
    _host = host;
  }

  /// Detaches [host] when a reader screen disposes without stopping playback
  /// unless explicitly requested.
  void detachHost([TtsReaderHost? host]) {
    if (host == null || identical(_host, host)) {
      _host = null;
    }
  }

  /// Loads persisted TTS speech rate, pitch, engine, and voice preferences.
  Future<void> loadSettings() async {
    if (!_isAlive) return;
    final themeRepo = ref.read(themeRepositoryProvider);
    var rate = state.speechRate;
    var pitch = state.pitch;
    var engineId = state.engineId;
    var voiceId = state.voiceId;

    try {
      final rateSetting = await themeRepo.getSetting(_kTtsSpeechRateKey);
      if (!_isAlive) return;
      final parsedRate = double.tryParse(rateSetting?.value ?? '');
      if (parsedRate != null && parsedRate.isFinite) {
        rate = _normalizeRate(parsedRate);
      }

      final pitchSetting = await themeRepo.getSetting(_kTtsPitchKey);
      if (!_isAlive) return;
      final parsedPitch = double.tryParse(pitchSetting?.value ?? '');
      if (parsedPitch != null && parsedPitch.isFinite) {
        pitch = _normalizePitch(parsedPitch);
      }

      final engineSetting = await themeRepo.getSetting(_kTtsEngineIdKey);
      if (!_isAlive) return;
      if (engineSetting != null && engineSetting.value.trim().isNotEmpty) {
        engineId = engineSetting.value.trim();
      }

      final voiceSetting = await themeRepo.getSetting(_kTtsVoiceIdKey);
      if (!_isAlive) return;
      if (voiceSetting != null && voiceSetting.value.trim().isNotEmpty) {
        voiceId = voiceSetting.value.trim();
      }
    } catch (_) {
      // Fall back to default TTS settings on storage errors.
    }

    if (!_isAlive) return;
    _settingsLoaded = true;
    _commit(
      state.copyWith(
        speechRate: rate,
        pitch: pitch,
        engineId: engineId,
        voiceId: voiceId,
      ),
    );
  }

  /// Starts reading [chapterText] of [bookTitle] from [startCharOffset].
  Future<void> start({
    required String bookId,
    required String bookTitle,
    required TtsReaderHost host,
    required int chapterIndex,
    required String chapterText,
    int startCharOffset = 0,
    String? chapterTitle,
  }) async {
    if (!_isAlive) return;
    final epoch = ++_playbackEpoch;
    _activeUtteranceId = null;
    _host = host;

    if (_hasViewportLocation && _viewportChapterIndex != chapterIndex) {
      _hasViewportLocation = false;
    }

    final resolvedTitle =
        chapterTitle ?? _safeChapterTitle(host, chapterIndex, bookTitle);

    _commit(
      state.copyWith(
        bookId: bookId,
        bookTitle: bookTitle,
        status: TtsStatus.loading,
        speakingChapterIndex: chapterIndex,
        speakingChapterTitle: resolvedTitle,
        utterances: const <TtsUtterance>[],
        currentUtteranceIndex: 0,
        isDetached: false,
        clearErrorMessage: true,
      ),
    );

    if (!_settingsLoaded) {
      await loadSettings();
      if (!_isAlive || epoch != _playbackEpoch) return;
    }

    final ready = await _ensureInitialized(epoch);
    if (!_isAlive || epoch != _playbackEpoch || !ready) return;

    final utterances = TtsSentenceSplitter.split(chapterText);
    if (utterances.isNotEmpty) {
      final startIdx = TtsSentenceSplitter.findUtteranceIndexForOffset(
        utterances,
        startCharOffset,
      );
      _commit(
        state.copyWith(
          utterances: utterances,
          currentUtteranceIndex: startIdx,
          speakingChapterIndex: chapterIndex,
          speakingChapterTitle: resolvedTitle,
          isDetached: false,
          clearErrorMessage: true,
        ),
      );
      await _speakCurrentUtterance(epoch);
      return;
    }

    // Current chapter has no speakable text (e.g. cover/illustration-only page):
    // try advancing to the next speakable chapter automatically.
    final advanced = await _loadAndEnterNextSpeakableChapter(
      fromChapterIndex: chapterIndex,
      epoch: epoch,
      startPlaying: true,
    );
    if (!_isAlive || epoch != _playbackEpoch) return;
    if (!advanced) {
      await stop();
    }
  }

  /// Pauses speech while retaining the platform media notification for resume.
  Future<void> pause() async {
    if (!_isAlive) return;
    if (state.status != TtsStatus.playing && state.status != TtsStatus.loading) {
      return;
    }
    _playbackEpoch++;
    _activeUtteranceId = null;
    _commit(state.copyWith(status: TtsStatus.paused, clearErrorMessage: true));
    await ref
        .read(ttsEngineProvider)
        .pauseNotification(
          bookTitle: state.bookTitle,
          chapterTitle: state.speakingChapterTitle,
        );
  }

  /// Resumes speech from the current paused utterance.
  Future<void> resume() async {
    if (!_isAlive) return;
    if (state.status != TtsStatus.paused) return;
    if (state.currentUtterance == null) {
      await stop();
      return;
    }
    final epoch = ++_playbackEpoch;
    final ready = await _ensureInitialized(epoch);
    if (!_isAlive || epoch != _playbackEpoch || !ready) return;

    if (!state.isDetached && _shouldAutoNavigate(state.speakingChapterIndex, state.currentUtterance!)) {
      await _autoNavigateToUtterance(
        state.speakingChapterIndex,
        state.currentUtterance!,
      );
      if (!_isAlive || epoch != _playbackEpoch) return;
    }

    await _speakCurrentUtterance(epoch);
  }

  /// Toggles between playing and paused states.
  Future<void> togglePlayPause() async {
    if (!_isAlive) return;
    if (state.status == TtsStatus.playing || state.status == TtsStatus.loading) {
      await pause();
    } else if (state.status == TtsStatus.paused) {
      await resume();
    }
  }

  /// Stops speech completely, clears active playback state, and cancels sleep timer.
  Future<void> stop() async {
    if (!_isAlive) return;
    _playbackEpoch++;
    _activeUtteranceId = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;

    _commit(
      state.copyWith(
        clearBookId: true,
        clearBookTitle: true,
        status: TtsStatus.idle,
        utterances: const <TtsUtterance>[],
        currentUtteranceIndex: 0,
        speakingChapterIndex: 0,
        speakingChapterTitle: '',
        isDetached: false,
        isBarCollapsed: false,
        sleepTimerMode: TtsSleepTimerMode.off,
        clearSleepRemainingSeconds: true,
        clearErrorMessage: true,
      ),
    );

    await ref.read(ttsEngineProvider).stop();
  }

  /// Advances to the next sentence, crossing chapters if needed.
  Future<void> nextSentence() async {
    if (!_isAlive || !state.isActive) return;
    final epoch = ++_playbackEpoch;
    _activeUtteranceId = null;
    final shouldPlay = state.status != TtsStatus.paused;

    await _advanceToNextUtterance(
      epoch: epoch,
      startPlaying: shouldPlay,
      honorEndOfChapterTimer: false,
    );
  }

  /// Moves back to the previous sentence, crossing to the end of the previous
  /// chapter if needed.
  Future<void> prevSentence() async {
    if (!_isAlive || !state.isActive) return;
    final epoch = ++_playbackEpoch;
    _activeUtteranceId = null;
    final shouldPlay = state.status != TtsStatus.paused;

    if (state.currentUtteranceIndex > 0 && state.utterances.isNotEmpty) {
      final prevIdx = state.currentUtteranceIndex - 1;
      final prevUtterance = state.utterances[prevIdx];
      _commit(
        state.copyWith(
          currentUtteranceIndex: prevIdx,
          clearErrorMessage: true,
        ),
      );
      if (!state.isDetached &&
          _shouldAutoNavigate(state.speakingChapterIndex, prevUtterance)) {
        await _autoNavigateToUtterance(
          state.speakingChapterIndex,
          prevUtterance,
        );
        if (!_isAlive || epoch != _playbackEpoch) return;
      }
      if (shouldPlay) {
        await _speakCurrentUtterance(epoch);
      } else {
        await _syncPausedMetadata();
      }
      return;
    }

    final loadedPrev = await _loadAndEnterPreviousSpeakableChapter(
      fromChapterIndex: state.speakingChapterIndex,
      epoch: epoch,
      startPlaying: shouldPlay,
    );
    if (!_isAlive || epoch != _playbackEpoch) return;
    if (!loadedPrev && shouldPlay && state.currentUtterance != null) {
      await _speakCurrentUtterance(epoch);
    }
  }

  /// Updates the controller with the reader viewport's currently visible
  /// chapter and character range `[visibleStartOffset, visibleEndOffset)`.
  ///
  /// When TTS is active and the currently speaking sentence is outside the
  /// visible range (or on a different chapter), marks `isDetached = true`
  /// without interrupting playback.
  void onViewportLocationChanged(
    int viewportChapterIndex,
    int visibleStartOffset,
    int visibleEndOffset,
  ) {
    if (!_isAlive) return;
    _hasViewportLocation = true;
    _viewportChapterIndex = viewportChapterIndex;
    _viewportVisibleStart = visibleStartOffset;
    _viewportVisibleEnd = visibleEndOffset;

    if (_isAutoNavigating || !state.isActive || state.isDetached) {
      return;
    }

    final utterance = state.currentUtterance;
    if (viewportChapterIndex != state.speakingChapterIndex) {
      _commit(state.copyWith(isDetached: true));
      return;
    }
    if (utterance != null &&
        _isRangeDisjointFromViewport(
          utterance: utterance,
          visibleStart: visibleStartOffset,
          visibleEnd: visibleEndOffset,
        )) {
      _commit(state.copyWith(isDetached: true));
    }
  }

  /// Re-attaches the reader viewport to the currently speaking sentence.
  Future<void> jumpBackToSpeakingPosition() async {
    if (!_isAlive || !state.isActive) return;
    final utterance = state.currentUtterance;
    final targetChapter = state.speakingChapterIndex;
    final targetOffset = utterance?.startCharOffset ?? 0;

    _commit(state.copyWith(isDetached: false));
    await _navigateAuto(targetChapter, targetOffset);
  }

  /// Updates speech rate (`0.5..2.5`), sends to native engine, and persists it.
  Future<void> setSpeechRate(double rate) async {
    if (!_isAlive) return;
    final normalized = _normalizeRate(rate);
    _commit(state.copyWith(speechRate: normalized));
    await ref.read(ttsEngineProvider).setSpeechRate(normalized);
    await _persistSetting(_kTtsSpeechRateKey, normalized.toString());
  }

  /// Updates voice pitch (`0.5..2.0`), sends to native engine, and persists it.
  Future<void> setPitch(double pitch) async {
    if (!_isAlive) return;
    final normalized = _normalizePitch(pitch);
    _commit(state.copyWith(pitch: normalized));
    await ref.read(ttsEngineProvider).setPitch(normalized);
    await _persistSetting(_kTtsPitchKey, normalized.toString());
  }

  /// Switches the active native TTS engine and refreshes available voices.
  Future<bool> setEngine(String engineId) async {
    if (!_isAlive) return false;
    final engine = ref.read(ttsEngineProvider);
    final ok = await engine.setEngine(engineId);
    if (!_isAlive || !ok) return false;

    final rawVoices = await engine.getVoices();
    if (!_isAlive) return false;
    final voices = sortVoicesZhFirst(rawVoices);

    await engine.setSpeechRate(state.speechRate);
    await engine.setPitch(state.pitch);
    if (!_isAlive) return false;

    final nextVoiceId = voices.any((v) => v.id == state.voiceId)
        ? state.voiceId
        : (voices.isNotEmpty ? voices.first.id : null);
    if (nextVoiceId != null && nextVoiceId != state.voiceId) {
      await engine.setVoice(nextVoiceId);
      if (!_isAlive) return false;
    }

    _commit(
      state.copyWith(
        engineId: engineId,
        voices: voices,
        voiceId: nextVoiceId,
        clearVoiceId: nextVoiceId == null,
      ),
    );
    await _persistSetting(_kTtsEngineIdKey, engineId);
    if (nextVoiceId != null) {
      await _persistSetting(_kTtsVoiceIdKey, nextVoiceId);
    }

    if (state.status == TtsStatus.playing && state.currentUtterance != null) {
      final epoch = ++_playbackEpoch;
      _activeUtteranceId = null;
      await _speakCurrentUtterance(epoch);
    }
    return true;
  }

  /// Selects a voice by [voiceId], persists it, and applies it to playback.
  Future<bool> setVoice(String voiceId) async {
    if (!_isAlive) return false;
    final engine = ref.read(ttsEngineProvider);
    final ok = await engine.setVoice(voiceId);
    if (!_isAlive || !ok) return false;

    _commit(state.copyWith(voiceId: voiceId));
    await _persistSetting(_kTtsVoiceIdKey, voiceId);

    if (state.status == TtsStatus.playing && state.currentUtterance != null) {
      final epoch = ++_playbackEpoch;
      _activeUtteranceId = null;
      await _speakCurrentUtterance(epoch);
    }
    return true;
  }

  /// Refreshes available engines and voices from the native TTS engine.
  Future<void> refreshEnginesAndVoices() async {
    if (!_isAlive) return;
    final engine = ref.read(ttsEngineProvider);
    if (!_engineInitialized) {
      final ready = await _ensureInitialized(_playbackEpoch);
      if (!_isAlive || !ready) return;
    }
    final engines = await engine.getEngines();
    if (!_isAlive) return;
    final voices = sortVoicesZhFirst(await engine.getVoices());
    if (!_isAlive) return;
    _commit(state.copyWith(engines: engines, voices: voices));
  }

  /// Configures the sleep timer (`off`, `15/30/60 min`, or `endOfChapter`).
  void setSleepTimer(TtsSleepTimerMode mode) {
    if (!_isAlive) return;
    _sleepTimer?.cancel();
    _sleepTimer = null;

    final minutes = mode.durationMinutes;
    if (minutes == null) {
      _commit(
        state.copyWith(
          sleepTimerMode: mode,
          clearSleepRemainingSeconds: true,
        ),
      );
      return;
    }

    final totalSeconds = minutes * 60;
    _commit(
      state.copyWith(
        sleepTimerMode: mode,
        sleepRemainingSeconds: totalSeconds,
      ),
    );
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isAlive) {
        timer.cancel();
        return;
      }
      final currentRemaining = state.sleepRemainingSeconds;
      if (state.sleepTimerMode != mode || currentRemaining == null) {
        timer.cancel();
        if (identical(_sleepTimer, timer)) {
          _sleepTimer = null;
        }
        return;
      }
      if (currentRemaining <= 1) {
        timer.cancel();
        if (identical(_sleepTimer, timer)) {
          _sleepTimer = null;
        }
        unawaited(stop());
        return;
      }
      _commit(state.copyWith(sleepRemainingSeconds: currentRemaining - 1));
    });
  }

  /// Toggles the floating TTS bar between collapsed pill and expanded bar.
  void toggleBarCollapsed() {
    if (!_isAlive) return;
    _commit(state.copyWith(isBarCollapsed: !state.isBarCollapsed));
  }

  /// Explicitly sets whether the floating TTS bar is collapsed.
  void setBarCollapsed(bool collapsed) {
    if (!_isAlive || state.isBarCollapsed == collapsed) return;
    _commit(state.copyWith(isBarCollapsed: collapsed));
  }

  /// Sorts voices with `zh` locales first while preserving relative order.
  static List<TtsVoiceInfo> sortVoicesZhFirst(List<TtsVoiceInfo> voices) {
    if (voices.length <= 1) return List<TtsVoiceInfo>.unmodifiable(voices);
    final zh = <TtsVoiceInfo>[];
    final other = <TtsVoiceInfo>[];
    for (final voice in voices) {
      if (voice.locale.toLowerCase().startsWith('zh')) {
        zh.add(voice);
      } else {
        other.add(voice);
      }
    }
    return List<TtsVoiceInfo>.unmodifiable(<TtsVoiceInfo>[...zh, ...other]);
  }

  Future<bool> _ensureInitialized(int epoch) async {
    final engine = ref.read(ttsEngineProvider);
    _eventsSubscription ??= engine.events.listen(
      _handleEngineEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (!_isAlive || !state.isActive) return;
        _commit(
          state.copyWith(
            status: TtsStatus.error,
            errorMessage: '语音服务异常：$error',
          ),
        );
      },
    );

    if (_engineInitialized) {
      return true;
    }

    final init = await engine.initialize();
    if (!_isAlive || epoch != _playbackEpoch) return false;
    if (!init.available) {
      _commit(
        state.copyWith(
          status: TtsStatus.error,
          errorMessage: init.error ?? '当前设备没有可用的系统 TTS 引擎',
        ),
      );
      return false;
    }

    _engineInitialized = true;
    final engines = await engine.getEngines();
    if (!_isAlive || epoch != _playbackEpoch) return false;

    var activeEngineId = state.engineId;
    if (activeEngineId != null &&
        activeEngineId.isNotEmpty &&
        activeEngineId != init.engine &&
        engines.any((e) => e.id == activeEngineId)) {
      await engine.setEngine(activeEngineId);
      if (!_isAlive || epoch != _playbackEpoch) return false;
    } else if (init.engine != null && init.engine!.isNotEmpty) {
      activeEngineId = init.engine;
    } else if (engines.isNotEmpty) {
      final defaultEngine = engines.where((e) => e.isDefault).firstOrNull;
      activeEngineId = (defaultEngine ?? engines.first).id;
    }

    final voices = sortVoicesZhFirst(await engine.getVoices());
    if (!_isAlive || epoch != _playbackEpoch) return false;

    var activeVoiceId = state.voiceId;
    if (activeVoiceId != null &&
        activeVoiceId.isNotEmpty &&
        (voices.isEmpty || voices.any((v) => v.id == activeVoiceId))) {
      await engine.setVoice(activeVoiceId);
      if (!_isAlive || epoch != _playbackEpoch) return false;
    } else {
      activeVoiceId = null;
    }

    await engine.setSpeechRate(state.speechRate);
    await engine.setPitch(state.pitch);
    if (!_isAlive || epoch != _playbackEpoch) return false;

    _commit(
      state.copyWith(
        engines: engines,
        voices: voices,
        engineId: activeEngineId,
        clearEngineId: activeEngineId == null,
        voiceId: activeVoiceId,
        clearVoiceId: activeVoiceId == null,
      ),
    );
    return true;
  }

  Future<void> _speakCurrentUtterance(int epoch) async {
    if (!_isAlive || epoch != _playbackEpoch) return;
    final utterance = state.currentUtterance;
    if (utterance == null) {
      await stop();
      return;
    }

    final utteranceId = 'tts_${epoch}_${++_utteranceSequence}';
    _activeUtteranceId = utteranceId;
    _commit(
      state.copyWith(
        status: TtsStatus.playing,
        clearErrorMessage: true,
      ),
    );

    final ok = await ref
        .read(ttsEngineProvider)
        .speak(
          text: utterance.text,
          utteranceId: utteranceId,
          bookTitle: state.bookTitle,
          chapterTitle: state.speakingChapterTitle,
        );
    if (!_isAlive ||
        epoch != _playbackEpoch ||
        _activeUtteranceId != utteranceId) {
      return;
    }

    if (!ok) {
      _activeUtteranceId = null;
      _commit(
        state.copyWith(
          status: TtsStatus.error,
          errorMessage: '系统朗读启动失败，请检查语音引擎设置',
        ),
      );
    }
  }

  void _handleEngineEvent(TtsEvent event) {
    if (!_isAlive) return;
    switch (event) {
      case TtsStartEvent():
        // Only acknowledge active utterance start.
        if (event.utteranceId != _activeUtteranceId) return;
      case TtsCompleteEvent():
        if (state.status != TtsStatus.playing) return;
        if (_activeUtteranceId == null ||
            event.utteranceId != _activeUtteranceId) {
          return;
        }
        _activeUtteranceId = null;
        final epoch = ++_playbackEpoch;
        unawaited(
          _advanceToNextUtterance(
            epoch: epoch,
            startPlaying: true,
            honorEndOfChapterTimer: true,
          ),
        );
      case TtsErrorEvent():
        if (!state.isActive) return;
        if (event.utteranceId != null &&
            _activeUtteranceId != null &&
            event.utteranceId != _activeUtteranceId) {
          return;
        }
        _playbackEpoch++;
        _activeUtteranceId = null;
        _commit(
          state.copyWith(
            status: TtsStatus.error,
            errorMessage: event.message,
          ),
        );
      case TtsProgressEvent():
        break;
      case TtsMediaActionEvent():
        _handleMediaAction(event.action);
    }
  }

  void _handleMediaAction(TtsMediaAction action) {
    switch (action) {
      case TtsMediaAction.play:
      case TtsMediaAction.resumeFromFocus:
        if (state.status == TtsStatus.paused) {
          unawaited(resume());
        }
      case TtsMediaAction.pause:
        if (state.status == TtsStatus.playing ||
            state.status == TtsStatus.loading) {
          unawaited(pause());
        }
      case TtsMediaAction.toggle:
        unawaited(togglePlayPause());
      case TtsMediaAction.next:
        unawaited(nextSentence());
      case TtsMediaAction.prev:
        unawaited(prevSentence());
      case TtsMediaAction.stop:
        unawaited(stop());
    }
  }

  Future<void> _advanceToNextUtterance({
    required int epoch,
    required bool startPlaying,
    required bool honorEndOfChapterTimer,
  }) async {
    if (!_isAlive || epoch != _playbackEpoch) return;

    final nextIdx = state.currentUtteranceIndex + 1;
    if (nextIdx < state.utterances.length) {
      final nextUtterance = state.utterances[nextIdx];
      _commit(
        state.copyWith(
          currentUtteranceIndex: nextIdx,
          clearErrorMessage: true,
        ),
      );
      if (!state.isDetached &&
          _shouldAutoNavigate(state.speakingChapterIndex, nextUtterance)) {
        await _autoNavigateToUtterance(
          state.speakingChapterIndex,
          nextUtterance,
        );
        if (!_isAlive || epoch != _playbackEpoch) return;
      }
      if (startPlaying) {
        await _speakCurrentUtterance(epoch);
      } else {
        await _syncPausedMetadata();
      }
      return;
    }

    // Current chapter reached its end.
    if (honorEndOfChapterTimer &&
        state.sleepTimerMode == TtsSleepTimerMode.endOfChapter) {
      await stop();
      return;
    }

    final advanced = await _loadAndEnterNextSpeakableChapter(
      fromChapterIndex: state.speakingChapterIndex,
      epoch: epoch,
      startPlaying: startPlaying,
    );
    if (!_isAlive || epoch != _playbackEpoch) return;
    if (!advanced && state.status != TtsStatus.error) {
      await stop();
    }
  }

  Future<bool> _loadAndEnterNextSpeakableChapter({
    required int fromChapterIndex,
    required int epoch,
    required bool startPlaying,
  }) async {
    final host = _host;
    if (host == null) return false;
    final chapterCount = host.getChapterCount();
    var candidate = fromChapterIndex + 1;

    while (candidate < chapterCount) {
      if (!_isAlive || epoch != _playbackEpoch) return false;
      _commit(state.copyWith(status: TtsStatus.loading));

      final text = await host.loadChapterText(candidate);
      if (!_isAlive || epoch != _playbackEpoch) return false;
      if (text == null) {
        _commit(
          state.copyWith(
            status: TtsStatus.error,
            errorMessage: '无法加载下一章内容',
          ),
        );
        return false;
      }

      final nextUtterances = TtsSentenceSplitter.split(text);
      if (nextUtterances.isEmpty) {
        candidate++;
        continue;
      }

      final nextTitle = _safeChapterTitle(host, candidate, state.bookTitle ?? '');
      final firstUtterance = nextUtterances.first;
      _commit(
        state.copyWith(
          speakingChapterIndex: candidate,
          speakingChapterTitle: nextTitle,
          utterances: nextUtterances,
          currentUtteranceIndex: 0,
          status: startPlaying ? TtsStatus.playing : TtsStatus.paused,
          clearErrorMessage: true,
        ),
      );

      if (!state.isDetached) {
        await _autoNavigateToUtterance(candidate, firstUtterance);
        if (!_isAlive || epoch != _playbackEpoch) return false;
      }

      if (startPlaying) {
        await _speakCurrentUtterance(epoch);
      } else {
        await _syncPausedMetadata();
      }
      return true;
    }

    return false;
  }

  Future<bool> _loadAndEnterPreviousSpeakableChapter({
    required int fromChapterIndex,
    required int epoch,
    required bool startPlaying,
  }) async {
    final host = _host;
    if (host == null) return false;
    var candidate = fromChapterIndex - 1;

    while (candidate >= 0) {
      if (!_isAlive || epoch != _playbackEpoch) return false;
      _commit(state.copyWith(status: TtsStatus.loading));

      final text = await host.loadChapterText(candidate);
      if (!_isAlive || epoch != _playbackEpoch) return false;
      if (text == null) {
        _commit(
          state.copyWith(
            status: TtsStatus.error,
            errorMessage: '无法加载上一章内容',
          ),
        );
        return false;
      }

      final prevUtterances = TtsSentenceSplitter.split(text);
      if (prevUtterances.isEmpty) {
        candidate--;
        continue;
      }

      final prevTitle = _safeChapterTitle(host, candidate, state.bookTitle ?? '');
      final lastIndex = prevUtterances.length - 1;
      final lastUtterance = prevUtterances[lastIndex];
      _commit(
        state.copyWith(
          speakingChapterIndex: candidate,
          speakingChapterTitle: prevTitle,
          utterances: prevUtterances,
          currentUtteranceIndex: lastIndex,
          status: startPlaying ? TtsStatus.playing : TtsStatus.paused,
          clearErrorMessage: true,
        ),
      );

      if (!state.isDetached) {
        await _autoNavigateToUtterance(candidate, lastUtterance);
        if (!_isAlive || epoch != _playbackEpoch) return false;
      }

      if (startPlaying) {
        await _speakCurrentUtterance(epoch);
      } else {
        await _syncPausedMetadata();
      }
      return true;
    }

    return false;
  }

  bool _shouldAutoNavigate(int chapterIndex, TtsUtterance utterance) {
    if (!_hasViewportLocation) return false;
    if (_viewportChapterIndex != chapterIndex) return true;
    return utterance.startCharOffset < _viewportVisibleStart ||
        utterance.startCharOffset >= _viewportVisibleEnd;
  }

  bool _isRangeDisjointFromViewport({
    required TtsUtterance utterance,
    required int visibleStart,
    required int visibleEnd,
  }) {
    if (visibleEnd <= visibleStart) {
      return utterance.startCharOffset != visibleStart;
    }
    return utterance.endCharOffset <= visibleStart ||
        utterance.startCharOffset >= visibleEnd;
  }

  Future<void> _autoNavigateToUtterance(
    int chapterIndex,
    TtsUtterance utterance,
  ) {
    return _navigateAuto(chapterIndex, utterance.startCharOffset);
  }

  Future<void> _navigateAuto(int chapterIndex, int charOffset) async {
    final host = _host;
    if (host == null) return;
    _isAutoNavigating = true;
    try {
      await host.navigateToPosition(chapterIndex, charOffset);
    } finally {
      _isAutoNavigating = false;
    }
  }

  Future<void> _syncPausedMetadata() async {
    await ref
        .read(ttsEngineProvider)
        .updateMetadata(
          bookTitle: state.bookTitle,
          chapterTitle: state.speakingChapterTitle,
          isPlaying: false,
        );
  }

  Future<void> _persistSetting(String key, String value) async {
    if (!_isAlive) return;
    try {
      await ref
          .read(themeRepositoryProvider)
          .saveSetting(
            AppSetting(
              key: key,
              value: value,
              updatedAt: DateTime.now(),
            ),
          );
    } catch (_) {
      // Settings persistence failure must not interrupt playback.
    }
  }

  static String _safeChapterTitle(
    TtsReaderHost host,
    int chapterIndex,
    String fallback,
  ) {
    try {
      final title = host.getChapterTitle(chapterIndex);
      return title.isNotEmpty ? title : fallback;
    } catch (_) {
      return fallback;
    }
  }

  static double _normalizeRate(double rate) {
    final clamped = rate.clamp(
      TtsState.minSpeechRate,
      TtsState.maxSpeechRate,
    );
    return double.parse(clamped.toStringAsFixed(2));
  }

  static double _normalizePitch(double pitch) {
    final clamped = pitch.clamp(TtsState.minPitch, TtsState.maxPitch);
    return double.parse(clamped.toStringAsFixed(2));
  }
}
