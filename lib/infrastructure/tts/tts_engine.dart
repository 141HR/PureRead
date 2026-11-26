/// Media playback action emitted by system notification, lockscreen,
/// Bluetooth controls, or audio-focus changes on mobile platforms.
enum TtsMediaAction {
  play,
  pause,
  toggle,
  next,
  prev,
  stop,
  resumeFromFocus;

  /// Parses a wire string (e.g. `'resumeFromFocus'`) into a [TtsMediaAction],
  /// returning `null` if unknown.
  static TtsMediaAction? fromWire(String? raw) {
    return switch (raw) {
      'play' => TtsMediaAction.play,
      'pause' => TtsMediaAction.pause,
      'toggle' => TtsMediaAction.toggle,
      'next' => TtsMediaAction.next,
      'prev' => TtsMediaAction.prev,
      'stop' => TtsMediaAction.stop,
      'resumeFromFocus' => TtsMediaAction.resumeFromFocus,
      _ => null,
    };
  }
}

/// Result returned by [TtsEngine.initialize].
class TtsInitResult {
  final bool available;
  final String? engine;
  final String? error;

  const TtsInitResult({
    required this.available,
    this.engine,
    this.error,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsInitResult &&
          runtimeType == other.runtimeType &&
          available == other.available &&
          engine == other.engine &&
          error == other.error;

  @override
  int get hashCode => Object.hash(available, engine, error);

  @override
  String toString() =>
      'TtsInitResult(available: $available, engine: $engine, error: $error)';
}

/// Metadata describing an installed native TTS engine.
class TtsEngineInfo {
  final String id;
  final String label;
  final bool isDefault;

  const TtsEngineInfo({
    required this.id,
    required this.label,
    this.isDefault = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsEngineInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          isDefault == other.isDefault;

  @override
  int get hashCode => Object.hash(id, label, isDefault);

  @override
  String toString() =>
      'TtsEngineInfo(id: $id, label: $label, isDefault: $isDefault)';
}

/// Metadata describing a native TTS voice.
class TtsVoiceInfo {
  final String id;
  final String name;
  final String locale;

  const TtsVoiceInfo({
    required this.id,
    required this.name,
    required this.locale,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsVoiceInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          locale == other.locale;

  @override
  int get hashCode => Object.hash(id, name, locale);

  @override
  String toString() =>
      'TtsVoiceInfo(id: $id, name: $name, locale: $locale)';
}

/// Typed event stream emitted by a [TtsEngine].
sealed class TtsEvent {
  const TtsEvent();
}

/// Fired when playback begins for [utteranceId].
final class TtsStartEvent extends TtsEvent {
  final String utteranceId;

  const TtsStartEvent({required this.utteranceId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsStartEvent &&
          runtimeType == other.runtimeType &&
          utteranceId == other.utteranceId;

  @override
  int get hashCode => utteranceId.hashCode;

  @override
  String toString() => 'TtsStartEvent(utteranceId: $utteranceId)';
}

/// Fired when playback completes naturally for [utteranceId].
final class TtsCompleteEvent extends TtsEvent {
  final String utteranceId;

  const TtsCompleteEvent({required this.utteranceId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsCompleteEvent &&
          runtimeType == other.runtimeType &&
          utteranceId == other.utteranceId;

  @override
  int get hashCode => utteranceId.hashCode;

  @override
  String toString() => 'TtsCompleteEvent(utteranceId: $utteranceId)';
}

/// Fired when native synthesis fails for [utteranceId] (or engine-wide).
final class TtsErrorEvent extends TtsEvent {
  final String? utteranceId;
  final String message;

  const TtsErrorEvent({
    this.utteranceId,
    required this.message,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsErrorEvent &&
          runtimeType == other.runtimeType &&
          utteranceId == other.utteranceId &&
          message == other.message;

  @override
  int get hashCode => Object.hash(utteranceId, message);

  @override
  String toString() =>
      'TtsErrorEvent(utteranceId: $utteranceId, message: $message)';
}

/// Fired while speaking [utteranceId] to report UTF-16 range progress.
final class TtsProgressEvent extends TtsEvent {
  final String utteranceId;
  final int start;
  final int end;

  const TtsProgressEvent({
    required this.utteranceId,
    required this.start,
    required this.end,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsProgressEvent &&
          runtimeType == other.runtimeType &&
          utteranceId == other.utteranceId &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(utteranceId, start, end);

  @override
  String toString() =>
      'TtsProgressEvent(utteranceId: $utteranceId, start: $start, end: $end)';
}

/// Fired when an external media button, notification, or audio-focus event
/// triggers a playback command.
final class TtsMediaActionEvent extends TtsEvent {
  final TtsMediaAction action;

  const TtsMediaActionEvent({required this.action});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsMediaActionEvent &&
          runtimeType == other.runtimeType &&
          action == other.action;

  @override
  int get hashCode => action.hashCode;

  @override
  String toString() => 'TtsMediaActionEvent(action: $action)';
}

/// Abstract platform TTS synthesis and media-notification interface.
abstract interface class TtsEngine {
  /// Initializes the native TTS engine and reports availability.
  Future<TtsInitResult> initialize();

  /// Lists available native TTS engines (empty if not selectable).
  Future<List<TtsEngineInfo>> getEngines();

  /// Selects a native engine by [engineId].
  Future<bool> setEngine(String engineId);

  /// Lists available voices for the active engine.
  Future<List<TtsVoiceInfo>> getVoices();

  /// Selects a voice by [voiceId].
  Future<bool> setVoice(String voiceId);

  /// Sets speech rate (`0.5..2.5`, default `1.0`).
  Future<void> setSpeechRate(double rate);

  /// Sets voice pitch (`0.5..2.0`, default `1.0`).
  Future<void> setPitch(double pitch);

  /// Starts speaking [text] tagged with [utteranceId].
  Future<bool> speak({
    required String text,
    required String utteranceId,
    String? bookTitle,
    String? chapterTitle,
  });

  /// Stops speech and tears down foreground notification / media session.
  Future<void> stop();

  /// Halts active speech while keeping media notification paused for resume.
  Future<void> pauseNotification({
    String? bookTitle,
    String? chapterTitle,
  });

  /// Updates media notification metadata without restarting playback.
  Future<void> updateMetadata({
    String? bookTitle,
    String? chapterTitle,
    required bool isPlaying,
  });

  /// Releases native TTS engine resources.
  Future<void> shutdown();

  /// Broadcast stream of synthesis and media-action events.
  Stream<TtsEvent> get events;

  /// Disposes Dart-side subscriptions and stream controllers.
  Future<void> dispose();
}
