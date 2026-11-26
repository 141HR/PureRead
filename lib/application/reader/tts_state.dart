import '../../infrastructure/tts/tts.dart';
import 'tts_sentence_splitter.dart';

/// Lifecycle status of the TTS playback session.
enum TtsStatus { idle, playing, paused, loading, error }

/// Sleep timer mode for automatic TTS shutdown.
enum TtsSleepTimerMode {
  off,
  minutes15,
  minutes30,
  minutes60,
  endOfChapter;

  /// Human-readable label for UI chips.
  String get label => switch (this) {
    TtsSleepTimerMode.off => '关闭',
    TtsSleepTimerMode.minutes15 => '15分',
    TtsSleepTimerMode.minutes30 => '30分',
    TtsSleepTimerMode.minutes60 => '60分',
    TtsSleepTimerMode.endOfChapter => '读完本章',
  };

  /// Fixed countdown duration in minutes, or `null` for [off] / [endOfChapter].
  int? get durationMinutes => switch (this) {
    TtsSleepTimerMode.off => null,
    TtsSleepTimerMode.minutes15 => 15,
    TtsSleepTimerMode.minutes30 => 30,
    TtsSleepTimerMode.minutes60 => 60,
    TtsSleepTimerMode.endOfChapter => null,
  };
}

/// Immutable state exposed by `TtsController`.
class TtsState {
  static const double minSpeechRate = 0.5;
  static const double maxSpeechRate = 2.5;
  static const double defaultSpeechRate = 1.0;

  static const double minPitch = 0.5;
  static const double maxPitch = 2.0;
  static const double defaultPitch = 1.0;

  final String? bookId;
  final String? bookTitle;
  final TtsStatus status;
  final List<TtsUtterance> utterances;
  final int currentUtteranceIndex;
  final int speakingChapterIndex;
  final String speakingChapterTitle;
  final bool isDetached;
  final bool isBarCollapsed;
  final double speechRate;
  final double pitch;
  final String? engineId;
  final String? voiceId;
  final List<TtsEngineInfo> engines;
  final List<TtsVoiceInfo> voices;
  final TtsSleepTimerMode sleepTimerMode;
  final int? sleepRemainingSeconds;
  final String? errorMessage;

  const TtsState({
    this.bookId,
    this.bookTitle,
    this.status = TtsStatus.idle,
    this.utterances = const <TtsUtterance>[],
    this.currentUtteranceIndex = 0,
    this.speakingChapterIndex = 0,
    this.speakingChapterTitle = '',
    this.isDetached = false,
    this.isBarCollapsed = false,
    this.speechRate = defaultSpeechRate,
    this.pitch = defaultPitch,
    this.engineId,
    this.voiceId,
    this.engines = const <TtsEngineInfo>[],
    this.voices = const <TtsVoiceInfo>[],
    this.sleepTimerMode = TtsSleepTimerMode.off,
    this.sleepRemainingSeconds,
    this.errorMessage,
  });

  /// Whether a TTS session is actively running, paused, or loading a chapter.
  bool get isActive =>
      status == TtsStatus.playing ||
      status == TtsStatus.paused ||
      status == TtsStatus.loading;

  bool get isPlaying => status == TtsStatus.playing;

  bool get isPaused => status == TtsStatus.paused;

  /// Currently targeted utterance in [utterances], or `null` when unavailable.
  TtsUtterance? get currentUtterance {
    if (currentUtteranceIndex < 0 ||
        currentUtteranceIndex >= utterances.length) {
      return null;
    }
    return utterances[currentUtteranceIndex];
  }

  /// Active UTF-16 character range `(start, end)` in the speaking chapter for
  /// reader text highlighting, or `null` when no utterance is active.
  (int start, int end)? get activeHighlightRange {
    if (status != TtsStatus.playing && status != TtsStatus.paused) {
      return null;
    }
    final utterance = currentUtterance;
    if (utterance == null) return null;
    return (utterance.startCharOffset, utterance.endCharOffset);
  }

  TtsState copyWith({
    String? bookId,
    bool clearBookId = false,
    String? bookTitle,
    bool clearBookTitle = false,
    TtsStatus? status,
    List<TtsUtterance>? utterances,
    int? currentUtteranceIndex,
    int? speakingChapterIndex,
    String? speakingChapterTitle,
    bool? isDetached,
    bool? isBarCollapsed,
    double? speechRate,
    double? pitch,
    String? engineId,
    bool clearEngineId = false,
    String? voiceId,
    bool clearVoiceId = false,
    List<TtsEngineInfo>? engines,
    List<TtsVoiceInfo>? voices,
    TtsSleepTimerMode? sleepTimerMode,
    int? sleepRemainingSeconds,
    bool clearSleepRemainingSeconds = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return TtsState(
      bookId: clearBookId ? null : (bookId ?? this.bookId),
      bookTitle: clearBookTitle ? null : (bookTitle ?? this.bookTitle),
      status: status ?? this.status,
      utterances: utterances ?? this.utterances,
      currentUtteranceIndex:
          currentUtteranceIndex ?? this.currentUtteranceIndex,
      speakingChapterIndex: speakingChapterIndex ?? this.speakingChapterIndex,
      speakingChapterTitle: speakingChapterTitle ?? this.speakingChapterTitle,
      isDetached: isDetached ?? this.isDetached,
      isBarCollapsed: isBarCollapsed ?? this.isBarCollapsed,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      engineId: clearEngineId ? null : (engineId ?? this.engineId),
      voiceId: clearVoiceId ? null : (voiceId ?? this.voiceId),
      engines: engines ?? this.engines,
      voices: voices ?? this.voices,
      sleepTimerMode: sleepTimerMode ?? this.sleepTimerMode,
      sleepRemainingSeconds: clearSleepRemainingSeconds
          ? null
          : (sleepRemainingSeconds ?? this.sleepRemainingSeconds),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}
