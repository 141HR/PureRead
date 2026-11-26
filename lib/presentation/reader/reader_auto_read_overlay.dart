import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/reader/auto_read_state.dart';

/// Dual-mode Auto-Read canvas overlay supporting:
/// - [AutoReadMode.scroll]: smoothly translates `currentPageChild` upward and
///   brings `nextPageChild` in continuously from the bottom (like continuous
///   scroll page-turn), supporting vertical drag scrubbing and natural 0.5px
///   page-seam separation across single-column and dual-column layouts.
/// - [AutoReadMode.timedTurn]: displays `currentPageChild` unobstructed with a
///   thin 2.5px bottom progress bar and turns pages automatically on completion.
class ReaderAutoReadOverlay extends StatefulWidget {
  const ReaderAutoReadOverlay({
    super.key,
    required this.currentPageChild,
    required this.nextPageChild,
    required this.state,
    required this.canGoNext,
    required this.accentColor,
    required this.dividerColor,
    required this.onAdvancePage,
    required this.onToggleControls,
    this.onReachedBookEnd,
    this.pageKey,
  });

  final Widget currentPageChild;
  final Widget? nextPageChild;
  final AutoReadState state;
  final bool canGoNext;
  final Color accentColor;
  final Color dividerColor;
  final Future<void> Function() onAdvancePage;
  final VoidCallback onToggleControls;
  final VoidCallback? onReachedBookEnd;
  final Object? pageKey;

  @override
  State<ReaderAutoReadOverlay> createState() => _ReaderAutoReadOverlayState();
}

class _ReaderAutoReadOverlayState extends State<ReaderAutoReadOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isAdvancing = false;
  bool _isDraggingScroll = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.state.activeDuration,
    )..addStatusListener(_handleAnimationStatus);

    if (widget.state.isRunning) {
      unawaited(_controller.forward(from: 0.0));
    }
  }

  @override
  void didUpdateWidget(covariant ReaderAutoReadOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldState = oldWidget.state;
    final newState = widget.state;
    final modeChanged = oldState.mode != newState.mode;
    final durationChanged = oldState.activeDuration != newState.activeDuration;
    final statusChanged = oldState.status != newState.status;
    final pageKeyChanged = oldWidget.pageKey != widget.pageKey;

    if (!newState.isActive) {
      if (oldState.isActive) {
        _epoch++;
        _isAdvancing = false;
        _isDraggingScroll = false;
        _controller.stop();
        _controller.value = 0.0;
      }
      _controller.duration = newState.activeDuration;
      return;
    }

    if (modeChanged || oldState.status == AutoReadStatus.idle) {
      _epoch++;
      _isAdvancing = false;
      _isDraggingScroll = false;
      _controller.stop();
      _controller.duration = newState.activeDuration;
      _controller.value = 0.0;
      if (newState.isRunning) {
        unawaited(_controller.forward(from: 0.0));
      }
      return;
    }

    if (pageKeyChanged &&
        newState.isActive &&
        !_isAdvancing &&
        !_isDraggingScroll &&
        _controller.value > 0.05) {
      _controller.stop();
      _controller.value = 0.0;
      if (newState.isRunning) {
        unawaited(_controller.forward(from: 0.0));
      }
      return;
    }

    if (durationChanged) {
      final preservedProgress = _controller.value.clamp(0.0, 1.0);
      _controller.duration = newState.activeDuration;
      if (newState.isRunning && !_isAdvancing && !_isDraggingScroll) {
        _controller.stop(canceled: false);
        if (preservedProgress >= 1.0) {
          unawaited(_handleSweepCompleted());
        } else {
          unawaited(_controller.forward(from: preservedProgress));
        }
      } else if (newState.isPaused) {
        _controller.stop(canceled: false);
      }
      return;
    }

    if (statusChanged) {
      if (newState.isPaused) {
        _controller.stop(canceled: false);
      } else if (newState.isRunning && !_isDraggingScroll) {
        final current = _controller.value.clamp(0.0, 1.0);
        if (!_isAdvancing) {
          if (current >= 1.0) {
            unawaited(_handleSweepCompleted());
          } else {
            unawaited(_controller.forward(from: current));
          }
        }
      }
    } else if (newState.isRunning &&
        !oldWidget.canGoNext &&
        widget.canGoNext &&
        !_isAdvancing &&
        !_isDraggingScroll &&
        _controller.isCompleted) {
      unawaited(_controller.forward(from: 0.0));
    }
  }

  @override
  void dispose() {
    _epoch++;
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_isDraggingScroll) {
      unawaited(_handleSweepCompleted());
    }
  }

  Future<void> _handleSweepCompleted() async {
    if (!mounted || !widget.state.isRunning || _isAdvancing) return;
    if (!widget.canGoNext) {
      widget.onReachedBookEnd?.call();
      return;
    }

    _isAdvancing = true;
    final epoch = _epoch;
    try {
      await widget.onAdvancePage();
    } finally {
      if (mounted && epoch == _epoch) {
        _isAdvancing = false;
      }
    }

    if (!mounted || epoch != _epoch) return;
    _controller.value = 0.0;
    if (widget.state.isRunning && !_isDraggingScroll) {
      unawaited(_controller.forward(from: 0.0));
    }
  }

  void _onScrollDragStart(DragStartDetails details) {
    _isDraggingScroll = true;
    _controller.stop(canceled: false);
  }

  void _onScrollDragUpdate(DragUpdateDetails details, double viewportHeight) {
    if (!_isDraggingScroll || viewportHeight <= 0.0) return;
    final nextValue =
        (_controller.value - details.delta.dy / viewportHeight).clamp(0.0, 1.0);
    _controller.value = nextValue;
  }

  void _onScrollDragEnd() {
    if (!_isDraggingScroll) return;
    _isDraggingScroll = false;
    if (!mounted || _isAdvancing || !widget.state.isRunning) return;

    final current = _controller.value.clamp(0.0, 1.0);
    if (current >= 1.0) {
      unawaited(_handleSweepCompleted());
    } else {
      unawaited(_controller.forward(from: current));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.state.isActive) {
      return widget.currentPageChild;
    }

    final currentLayer = IgnorePointer(child: widget.currentPageChild);

    if (widget.state.mode == AutoReadMode.timedTurn) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            currentLayer,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 2.5,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final progress = _controller.value.clamp(0.0, 1.0);
                  return ColoredBox(
                    key: const ValueKey<String>('auto_read_timed_progress'),
                    color: widget.dividerColor.withAlpha(64),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        heightFactor: 1.0,
                        child: ColoredBox(color: widget.accentColor),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    final nextLayer = IgnorePointer(
      child: widget.nextPageChild ?? widget.currentPageChild,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(1.0, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggleControls,
          onVerticalDragStart: _onScrollDragStart,
          onVerticalDragUpdate: (details) =>
              _onScrollDragUpdate(details, height),
          onVerticalDragEnd: (_) => _onScrollDragEnd(),
          onVerticalDragCancel: _onScrollDragEnd,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final progress = _controller.value.clamp(0.0, 1.0);
                final offsetY = progress * height;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.translate(
                      key: const ValueKey<String>(
                        'auto_read_scroll_current_page',
                      ),
                      offset: Offset(0.0, -offsetY),
                      child: SizedBox.expand(child: currentLayer),
                    ),
                    Transform.translate(
                      key: const ValueKey<String>(
                        'auto_read_scroll_next_page',
                      ),
                      offset: Offset(0.0, height - offsetY),
                      child: SizedBox.expand(child: nextLayer),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: height - offsetY,
                      height: 0.5,
                      child: IgnorePointer(
                        child: ColoredBox(
                          key: const ValueKey<String>(
                            'auto_read_scroll_page_seam',
                          ),
                          color: widget.dividerColor.withAlpha(72),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
