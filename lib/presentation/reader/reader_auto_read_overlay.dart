import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/reader/auto_read_state.dart';

/// Dual-mode Auto-Read canvas overlay supporting:
/// - [AutoReadMode.curtain]: sweeps `nextPageChild` from top to bottom over
///   `currentPageChild` with a crisp accent scan-line divider and soft drop
///   shadow, compatible with both single-column and dual-column layouts.
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

  @override
  State<ReaderAutoReadOverlay> createState() => _ReaderAutoReadOverlayState();
}

class _ReaderAutoReadOverlayState extends State<ReaderAutoReadOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isAdvancing = false;
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

    if (!newState.isActive) {
      if (oldState.isActive) {
        _epoch++;
        _isAdvancing = false;
        _controller.stop();
        _controller.value = 0.0;
      }
      _controller.duration = newState.activeDuration;
      return;
    }

    if (modeChanged || oldState.status == AutoReadStatus.idle) {
      _epoch++;
      _isAdvancing = false;
      _controller.stop();
      _controller.duration = newState.activeDuration;
      _controller.value = 0.0;
      if (newState.isRunning) {
        unawaited(_controller.forward(from: 0.0));
      }
      return;
    }

    if (durationChanged) {
      final preservedProgress = _controller.value.clamp(0.0, 1.0);
      _controller.duration = newState.activeDuration;
      if (newState.isRunning && !_isAdvancing) {
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
      } else if (newState.isRunning) {
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
    if (status == AnimationStatus.completed) {
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
    if (widget.state.isRunning) {
      unawaited(_controller.forward(from: 0.0));
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onToggleControls,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value.clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                key: const ValueKey<String>('auto_read_curtain_current_clip'),
                clipper: _CurtainRegionClipper(
                  progress: progress,
                  isTopRegion: false,
                ),
                child: currentLayer,
              ),
              ClipRect(
                key: const ValueKey<String>('auto_read_curtain_next_clip'),
                clipper: _CurtainRegionClipper(
                  progress: progress,
                  isTopRegion: true,
                ),
                child: nextLayer,
              ),
              CustomPaint(
                key: const ValueKey<String>('auto_read_curtain_scan_line'),
                size: Size.infinite,
                painter: _CurtainScanLinePainter(
                  progress: progress,
                  accentColor: widget.accentColor,
                  dividerColor: widget.dividerColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CurtainRegionClipper extends CustomClipper<Rect> {
  const _CurtainRegionClipper({
    required this.progress,
    required this.isTopRegion,
  });

  final double progress;
  final bool isTopRegion;

  @override
  Rect getClip(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0.0 ||
        size.height <= 0.0) {
      return Rect.zero;
    }
    final clamped = progress.clamp(0.0, 1.0);
    final y = clamped * size.height;
    if (isTopRegion) {
      return Rect.fromLTWH(0.0, 0.0, size.width, y);
    }
    return Rect.fromLTWH(0.0, y, size.width, math.max(0.0, size.height - y));
  }

  @override
  bool shouldReclip(covariant _CurtainRegionClipper oldClipper) {
    return oldClipper.progress != progress ||
        oldClipper.isTopRegion != isTopRegion;
  }
}

class _CurtainScanLinePainter extends CustomPainter {
  const _CurtainScanLinePainter({
    required this.progress,
    required this.accentColor,
    required this.dividerColor,
  });

  final double progress;
  final Color accentColor;
  final Color dividerColor;

  static const double _hairlineThickness = 1.5;
  static const double _shadowHeight = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0.0 ||
        size.height <= 0.0) {
      return;
    }

    final clamped = progress.clamp(0.0, 1.0);
    final y = clamped * size.height;
    final bounds = Offset.zero & size;

    canvas.save();
    canvas.clipRect(bounds);

    final shadowRect = Rect.fromLTWH(0.0, y, size.width, _shadowHeight);
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color.lerp(dividerColor, accentColor, 0.30)!.withAlpha(72),
          accentColor.withAlpha(24),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 0.35, 1.0],
      ).createShader(shadowRect);
    canvas.drawRect(shadowRect, shadowPaint);

    const halfStroke = _hairlineThickness * 0.5;
    final lineY = y
        .clamp(halfStroke, math.max(halfStroke, size.height - halfStroke))
        .toDouble();
    if (lineY >= 1.5) {
      final rimPaint = Paint()
        ..color = dividerColor.withAlpha(110)
        ..strokeWidth = 0.75;
      canvas.drawLine(
        Offset(0.0, lineY - 1.0),
        Offset(size.width, lineY - 1.0),
        rimPaint,
      );
    }

    final hairlinePaint = Paint()
      ..color = accentColor
      ..strokeWidth = _hairlineThickness;
    canvas.drawLine(
      Offset(0.0, lineY),
      Offset(size.width, lineY),
      hairlinePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CurtainScanLinePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.dividerColor != dividerColor;
  }
}
