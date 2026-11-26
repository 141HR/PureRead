import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../core_providers.dart';
import 'auto_read_state.dart';

const String _kAutoReadModeKey = 'auto_read_mode';
const String _kAutoReadScrollSecondsKey = 'auto_read_scroll_seconds';
const String _kLegacyAutoReadCurtainSecondsKey = 'auto_read_curtain_seconds';
const String _kAutoReadTurnSecondsKey = 'auto_read_turn_seconds';

final autoReadControllerProvider =
    NotifierProvider<AutoReadController, AutoReadState>(AutoReadController.new);

/// Manages dual-mode Auto-Read playback state (`scroll` vs `timedTurn`),
/// control bar visibility, and persistent speed/mode preferences stored via
/// [themeRepositoryProvider].
class AutoReadController extends Notifier<AutoReadState> {
  bool _disposed = false;
  bool _initialLoadScheduled = false;
  int _modeRevision = 0;
  int _scrollRevision = 0;
  int _turnRevision = 0;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  AutoReadState build() {
    _disposed = false;
    _initialLoadScheduled = false;
    _modeRevision = 0;
    _scrollRevision = 0;
    _turnRevision = 0;

    ref.onDispose(() {
      _disposed = true;
    });

    Future<void>.microtask(_loadInitialSettings);

    return const AutoReadState();
  }

  Future<void> _loadInitialSettings() async {
    if (!_isAlive || _initialLoadScheduled) return;
    await loadSettings();
  }

  /// Loads persisted Auto-Read mode and per-mode durations from
  /// [themeRepositoryProvider], migrating legacy `'curtain'` preferences to
  /// [AutoReadMode.scroll] while ignoring malformed entries and preserving
  /// active playback state.
  Future<void> loadSettings() async {
    if (!_isAlive) return;
    _initialLoadScheduled = true;

    final themeRepo = ref.read(themeRepositoryProvider);
    final modeRevBefore = _modeRevision;
    final scrollRevBefore = _scrollRevision;
    final turnRevBefore = _turnRevision;

    AutoReadMode? loadedMode;
    int? loadedScroll;
    int? loadedTurn;

    try {
      final modeSetting = await themeRepo.getSetting(_kAutoReadModeKey);
      if (!_isAlive) return;
      if (modeSetting != null) {
        if (modeSetting.value == 'curtain') {
          loadedMode = AutoReadMode.scroll;
        } else {
          for (final candidate in AutoReadMode.values) {
            if (candidate.name == modeSetting.value) {
              loadedMode = candidate;
              break;
            }
          }
        }
      }

      var scrollSetting = await themeRepo.getSetting(_kAutoReadScrollSecondsKey);
      if (!_isAlive) return;
      scrollSetting ??= await themeRepo.getSetting(
        _kLegacyAutoReadCurtainSecondsKey,
      );
      if (!_isAlive) return;
      if (scrollSetting != null) {
        final parsed = int.tryParse(scrollSetting.value);
        if (parsed != null) {
          loadedScroll = AutoReadState.clampScrollSeconds(parsed);
        }
      }

      final turnSetting = await themeRepo.getSetting(_kAutoReadTurnSecondsKey);
      if (!_isAlive) return;
      if (turnSetting != null) {
        final parsed = int.tryParse(turnSetting.value);
        if (parsed != null) {
          loadedTurn = AutoReadState.clampTurnSeconds(parsed);
        }
      }
    } catch (_) {
      // Fall back safely to current/default Auto-Read preferences on error.
      return;
    }

    if (!_isAlive) return;
    state = state.copyWith(
      mode: _modeRevision == modeRevBefore ? loadedMode : null,
      scrollSeconds: _scrollRevision == scrollRevBefore ? loadedScroll : null,
      turnSeconds: _turnRevision == turnRevBefore ? loadedTurn : null,
    );
  }

  /// Starts Auto-Read immediately, optionally switching to [mode].
  void start({AutoReadMode? mode}) {
    if (!_isAlive) return;
    var nextMode = state.mode;
    if (mode != null) {
      _modeRevision++;
      nextMode = mode;
    }
    state = state.copyWith(
      mode: nextMode,
      status: AutoReadStatus.running,
      showControls: true,
    );
    if (mode != null) {
      unawaited(_saveSetting(_kAutoReadModeKey, mode.name));
    }
  }

  /// Stops Auto-Read and returns to [AutoReadStatus.idle].
  void stop() {
    if (!_isAlive) return;
    if (state.status == AutoReadStatus.idle && state.showControls) return;
    state = state.copyWith(
      status: AutoReadStatus.idle,
      showControls: true,
    );
  }

  /// Toggles between [AutoReadStatus.running] and [AutoReadStatus.paused]
  /// when Auto-Read is active.
  void togglePause() {
    if (!_isAlive) return;
    if (state.isRunning) {
      pause();
    } else if (state.isPaused) {
      resume();
    }
  }

  /// Freezes Auto-Read in place if currently running.
  void pause() {
    if (!_isAlive || !state.isRunning) return;
    state = state.copyWith(status: AutoReadStatus.paused);
  }

  /// Resumes Auto-Read from the paused state.
  void resume() {
    if (!_isAlive || !state.isPaused) return;
    state = state.copyWith(status: AutoReadStatus.running);
  }

  /// Switches the active Auto-Read mode and persists it.
  Future<void> setMode(AutoReadMode mode) async {
    if (!_isAlive) return;
    _modeRevision++;
    if (state.mode != mode) {
      state = state.copyWith(mode: mode);
    }
    await _saveSetting(_kAutoReadModeKey, mode.name);
  }

  /// Updates the smooth vertical scroll duration (clamped to `6..60` seconds)
  /// and persists it.
  Future<void> setScrollSeconds(int seconds) async {
    if (!_isAlive) return;
    _scrollRevision++;
    final clamped = AutoReadState.clampScrollSeconds(seconds);
    if (state.scrollSeconds != clamped) {
      state = state.copyWith(scrollSeconds: clamped);
    }
    await _saveSetting(_kAutoReadScrollSecondsKey, clamped.toString());
  }

  /// Updates the timed page-turn interval (clamped to `3..60` seconds) and
  /// persists it.
  Future<void> setTurnSeconds(int seconds) async {
    if (!_isAlive) return;
    _turnRevision++;
    final clamped = AutoReadState.clampTurnSeconds(seconds);
    if (state.turnSeconds != clamped) {
      state = state.copyWith(turnSeconds: clamped);
    }
    await _saveSetting(_kAutoReadTurnSecondsKey, clamped.toString());
  }

  /// Toggles floating control bar visibility while Auto-Read is active.
  void toggleControls() {
    if (!_isAlive) return;
    state = state.copyWith(showControls: !state.showControls);
  }

  /// Explicitly sets floating control bar visibility.
  void setControlsVisible(bool visible) {
    if (!_isAlive || state.showControls == visible) return;
    state = state.copyWith(showControls: visible);
  }

  Future<void> _saveSetting(String key, String value) async {
    if (!_isAlive) return;
    final themeRepo = ref.read(themeRepositoryProvider);
    try {
      await themeRepo.saveSetting(
        AppSetting(key: key, value: value, updatedAt: DateTime.now()),
      );
    } catch (_) {
      // Non-critical preference persistence error.
    }
  }
}
