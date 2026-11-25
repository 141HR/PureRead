/// Reading automation mode supported by PureRead Auto-Read.
enum AutoReadMode {
  /// Sweeps the next page cleanly from top to bottom over the current page,
  /// separated by a crisp horizontal scan-line divider.
  curtain,

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
  static const int minCurtainSeconds = 6;
  static const int maxCurtainSeconds = 60;
  static const int defaultCurtainSeconds = 18;

  static const int minTurnSeconds = 3;
  static const int maxTurnSeconds = 60;
  static const int defaultTurnSeconds = 12;

  const AutoReadState({
    this.mode = AutoReadMode.curtain,
    this.status = AutoReadStatus.idle,
    this.curtainSeconds = defaultCurtainSeconds,
    this.turnSeconds = defaultTurnSeconds,
    this.showControls = true,
  });

  final AutoReadMode mode;
  final AutoReadStatus status;
  final int curtainSeconds;
  final int turnSeconds;
  final bool showControls;

  bool get isActive => status != AutoReadStatus.idle;

  bool get isRunning => status == AutoReadStatus.running;

  bool get isPaused => status == AutoReadStatus.paused;

  int get activeSeconds =>
      mode == AutoReadMode.curtain ? curtainSeconds : turnSeconds;

  int get minActiveSeconds =>
      mode == AutoReadMode.curtain ? minCurtainSeconds : minTurnSeconds;

  int get maxActiveSeconds =>
      mode == AutoReadMode.curtain ? maxCurtainSeconds : maxTurnSeconds;

  Duration get activeDuration => Duration(seconds: activeSeconds);

  /// Clamps [seconds] to the valid range for [AutoReadMode.curtain].
  static int clampCurtainSeconds(int seconds) =>
      seconds.clamp(minCurtainSeconds, maxCurtainSeconds);

  /// Clamps [seconds] to the valid range for [AutoReadMode.timedTurn].
  static int clampTurnSeconds(int seconds) =>
      seconds.clamp(minTurnSeconds, maxTurnSeconds);

  AutoReadState copyWith({
    AutoReadMode? mode,
    AutoReadStatus? status,
    int? curtainSeconds,
    int? turnSeconds,
    bool? showControls,
  }) {
    return AutoReadState(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      curtainSeconds: curtainSeconds == null
          ? this.curtainSeconds
          : clampCurtainSeconds(curtainSeconds),
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
          curtainSeconds == other.curtainSeconds &&
          turnSeconds == other.turnSeconds &&
          showControls == other.showControls;

  @override
  int get hashCode => Object.hash(
    mode,
    status,
    curtainSeconds,
    turnSeconds,
    showControls,
  );
}
