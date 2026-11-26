/// Reading automation mode supported by PureRead Auto-Read.
enum AutoReadMode {
  /// Smoothly scrolls content continuously upward like scroll page-turn,
  /// bringing the next page up seamlessly beneath the current page.
  scroll,

  /// Keeps the current page unobstructed with a thin bottom progress bar and
  /// automatically advances when the configured interval completes.
  timedTurn,
}

/// Lifecycle status of the Auto-Read session.
enum AutoReadStatus {
  /// Auto-Read is inactive.
  idle,

  /// Auto-Read is actively advancing progress.
  running,

  /// Auto-Read is paused in place while preserving progress.
  paused,
}

/// Immutable state exposed by `AutoReadController`.
class AutoReadState {
  static const int minScrollSeconds = 6;
  static const int maxScrollSeconds = 60;
  static const int defaultScrollSeconds = 18;

  static const int minTurnSeconds = 3;
  static const int maxTurnSeconds = 60;
  static const int defaultTurnSeconds = 12;

  const AutoReadState({
    this.mode = AutoReadMode.scroll,
    this.status = AutoReadStatus.idle,
    this.scrollSeconds = defaultScrollSeconds,
    this.turnSeconds = defaultTurnSeconds,
    this.showControls = true,
  });

  final AutoReadMode mode;
  final AutoReadStatus status;
  final int scrollSeconds;
  final int turnSeconds;
  final bool showControls;

  bool get isActive => status != AutoReadStatus.idle;

  bool get isRunning => status == AutoReadStatus.running;

  bool get isPaused => status == AutoReadStatus.paused;

  int get activeSeconds =>
      mode == AutoReadMode.scroll ? scrollSeconds : turnSeconds;

  int get minActiveSeconds =>
      mode == AutoReadMode.scroll ? minScrollSeconds : minTurnSeconds;

  int get maxActiveSeconds =>
      mode == AutoReadMode.scroll ? maxScrollSeconds : maxTurnSeconds;

  Duration get activeDuration => Duration(seconds: activeSeconds);

  /// Clamps [seconds] to the valid range for [AutoReadMode.scroll].
  static int clampScrollSeconds(int seconds) =>
      seconds.clamp(minScrollSeconds, maxScrollSeconds);

  /// Clamps [seconds] to the valid range for [AutoReadMode.timedTurn].
  static int clampTurnSeconds(int seconds) =>
      seconds.clamp(minTurnSeconds, maxTurnSeconds);

  AutoReadState copyWith({
    AutoReadMode? mode,
    AutoReadStatus? status,
    int? scrollSeconds,
    int? turnSeconds,
    bool? showControls,
  }) {
    return AutoReadState(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      scrollSeconds: scrollSeconds == null
          ? this.scrollSeconds
          : clampScrollSeconds(scrollSeconds),
      turnSeconds: turnSeconds == null
          ? this.turnSeconds
          : clampTurnSeconds(turnSeconds),
      showControls: showControls ?? this.showControls,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoReadState &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          status == other.status &&
          scrollSeconds == other.scrollSeconds &&
          turnSeconds == other.turnSeconds &&
          showControls == other.showControls;

  @override
  int get hashCode => Object.hash(
    mode,
    status,
    scrollSeconds,
    turnSeconds,
    showControls,
  );
}
