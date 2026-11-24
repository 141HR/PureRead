import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Page-curl travel direction.
enum CurlDirection {
  /// Turns from the right edge toward the left edge (advancing forward).
  forward,

  /// Turns from the left edge toward the right edge (stepping backward).
  backward,
}

/// Immutable geometric solution for a single frame of a simulated page curl.
///
/// Coordinates are guaranteed finite across all `progress` values in `[0, 1]`
/// and across both portrait single-column and landscape dual-column viewports.
class PageCurlGeometry {
  const PageCurlGeometry({
    required this.size,
    required this.progress,
    required this.direction,
    required this.creaseAnchor,
    required this.creaseNormal,
    required this.creaseStart,
    required this.creaseEnd,
    required this.foldPoint,
    required this.frontPageClipPath,
    required this.backFlapPath,
    required this.dropShadowPath,
    required this.highlightStart,
    required this.highlightEnd,
    required this.shadowStart,
    required this.shadowEnd,
    required this.curlRadius,
    required this.isFlat,
  });

  /// Page bounds used to compute this curl geometry.
  final Size size;

  /// Normalized curl completion progress clamped to `[0.0, 1.0]`.
  final double progress;

  /// Travel direction (`forward` = right-to-left, `backward` = left-to-right).
  final CurlDirection direction;

  /// Midpoint anchor along the crease segment inside page bounds.
  final Offset creaseAnchor;

  /// Unit normal vector pointing from the visible front page into the revealed
  /// underneath region (`dx > 0` for forward, `dx < 0` for backward).
  final Offset creaseNormal;

  /// First endpoint of the crease segment on the page boundary.
  final Offset creaseStart;

  /// Second endpoint of the crease segment on the page boundary.
  final Offset creaseEnd;

  /// Clamped fold tip point of the lifted corner.
  final Offset foldPoint;

  /// Visible front-page region clip path.
  final Path frontPageClipPath;

  /// Curled back-flap outline with cylindrical fold lip curvature.
  final Path backFlapPath;

  /// Soft drop-shadow polygon cast onto the revealed underneath page.
  final Path dropShadowPath;

  /// Start coordinate of the specular highlight gradient axis across the crease.
  final Offset highlightStart;

  /// End coordinate of the specular highlight gradient axis across the crease.
  final Offset highlightEnd;

  /// Start coordinate (on the crease) of the cast drop-shadow gradient.
  final Offset shadowStart;

  /// End coordinate (into the revealed page) of the cast drop-shadow gradient.
  final Offset shadowEnd;

  /// Effective cylindrical curl radius for shading and highlight falloff.
  final double curlRadius;

  /// True when the page is resting flat (`progress <= 0` or `progress >= 1`)
  /// or the viewport size is degenerate.
  final bool isFlat;

  /// Computes a finite [PageCurlGeometry] for [size], normalized [progress],
  /// [direction], and optional normalized [dragVector] / [touchYNormalized].
  static PageCurlGeometry compute({
    required Size size,
    required double progress,
    CurlDirection direction = CurlDirection.forward,
    Offset dragVector = Offset.zero,
    double touchYNormalized = 0.68,
  }) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0.0 ||
        size.height <= 0.0) {
      final normal = direction == CurlDirection.forward
          ? const Offset(1.0, 0.0)
          : const Offset(-1.0, 0.0);
      return PageCurlGeometry(
        size: Size.zero,
        progress: 0.0,
        direction: direction,
        creaseAnchor: Offset.zero,
        creaseNormal: normal,
        creaseStart: Offset.zero,
        creaseEnd: Offset.zero,
        foldPoint: Offset.zero,
        frontPageClipPath: Path(),
        backFlapPath: Path(),
        dropShadowPath: Path(),
        highlightStart: Offset.zero,
        highlightEnd: normal,
        shadowStart: Offset.zero,
        shadowEnd: normal,
        curlRadius: 0.0,
        isFlat: true,
      );
    }

    final w = size.width;
    final h = size.height;
    final t = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final safeTouchY =
        touchYNormalized.isFinite ? touchYNormalized.clamp(0.0, 1.0) : 0.68;
    final safeDragY =
        dragVector.dy.isFinite ? dragVector.dy.clamp(-1.0, 1.0) : 0.0;

    // Combine touch vertical origin and vertical drag momentum into a gentle
    // corner-lift tilt bias, decaying smoothly near spine completion (t -> 1).
    final touchBias = (safeTouchY - 0.5) * 2.0;
    final combinedBias = (touchBias * 0.72 - safeDragY * 0.28).clamp(-1.0, 1.0);
    final effectiveBias = combinedBias.abs() < 0.06 ? 0.28 : combinedBias;
    const maxAngleRad = 0.22;
    final theta = effectiveBias * maxAngleRad * (1.0 - 0.65 * t);

    final canonicalNormal = Offset(math.cos(theta), math.sin(theta));
    final normal = direction == CurlDirection.forward
        ? canonicalNormal
        : Offset(-canonicalNormal.dx, canonicalNormal.dy);

    final canonicalAnchorY = (h * safeTouchY).clamp(0.0, h);
    if (t <= 1e-4) {
      final edgeX = direction == CurlDirection.forward ? w : 0.0;
      final anchor = Offset(edgeX, canonicalAnchorY);
      return PageCurlGeometry(
        size: size,
        progress: 0.0,
        direction: direction,
        creaseAnchor: anchor,
        creaseNormal: normal,
        creaseStart: Offset(edgeX, 0.0),
        creaseEnd: Offset(edgeX, h),
        foldPoint: anchor,
        frontPageClipPath: Path()..addRect(Offset.zero & size),
        backFlapPath: Path(),
        dropShadowPath: Path(),
        highlightStart: anchor - normal,
        highlightEnd: anchor + normal,
        shadowStart: anchor,
        shadowEnd: anchor + normal,
        curlRadius: 0.0,
        isFlat: true,
      );
    }

    if (t >= 1.0 - 1e-4) {
      final edgeX = direction == CurlDirection.forward ? 0.0 : w;
      final anchor = Offset(edgeX, canonicalAnchorY);
      return PageCurlGeometry(
        size: size,
        progress: 1.0,
        direction: direction,
        creaseAnchor: anchor,
        creaseNormal: normal,
        creaseStart: Offset(edgeX, 0.0),
        creaseEnd: Offset(edgeX, h),
        foldPoint: anchor,
        frontPageClipPath: Path(),
        backFlapPath: Path(),
        dropShadowPath: Path(),
        highlightStart: anchor - normal,
        highlightEnd: anchor + normal,
        shadowStart: anchor,
        shadowEnd: anchor + normal,
        curlRadius: 0.0,
        isFlat: true,
      );
    }

    final corners = <Offset>[
      Offset.zero,
      Offset(w, 0.0),
      Offset(w, h),
      Offset(0.0, h),
    ];

    var dMin = double.infinity;
    var dMax = double.negativeInfinity;
    for (final c in corners) {
      final d = _dot(c, canonicalNormal);
      if (d < dMin) dMin = d;
      if (d > dMax) dMax = d;
    }

    final span = math.max(1e-4, dMax - dMin);
    final s = dMax - span * t;

    final canonicalFront = _clipPolygonHalfPlane(
      corners,
      canonicalNormal,
      s,
      keepLessOrEqual: true,
    );
    final canonicalPeeled = _clipPolygonHalfPlane(
      corners,
      canonicalNormal,
      s,
      keepLessOrEqual: false,
    );

    final creasePoints = <Offset>[];
    for (final p in canonicalFront) {
      if ((_dot(p, canonicalNormal) - s).abs() <= 1e-2) {
        creasePoints.add(p);
      }
    }

    final Offset cCreaseA;
    final Offset cCreaseB;
    if (creasePoints.length >= 2) {
      cCreaseA = creasePoints.first;
      cCreaseB = creasePoints.last;
    } else {
      final fallbackX = (w * (1.0 - t)).clamp(0.0, w);
      cCreaseA = Offset(fallbackX, 0.0);
      cCreaseB = Offset(fallbackX, h);
    }

    final cAnchor = Offset(
      (cCreaseA.dx + cCreaseB.dx) * 0.5,
      (cCreaseA.dy + cCreaseB.dy) * 0.5,
    );

    final minDim = math.min(w, h);
    final archFactor = math.sin(math.pi * t);
    final curlRadius = (minDim * 0.065 * archFactor).clamp(3.0, 30.0);
    final lipBulge = (curlRadius * 0.34).clamp(1.5, 11.0);
    final shadowWidth = (minDim * 0.14 * archFactor).clamp(4.0, 44.0);

    final liftedCorner = Offset(w, theta >= 0.0 ? h : 0.0);
    final liftedDist = math.max(0.0, _dot(liftedCorner, canonicalNormal) - s);
    final rawFold = liftedCorner - canonicalNormal * (1.88 * liftedDist);
    final cFoldPoint = Offset(
      rawFold.dx.clamp(0.0, w),
      rawFold.dy.clamp(0.0, h),
    );

    // Reflect the peeled polygon across the crease with cylindrical arch
    // shortening and clip cleanly into the page rectangle.
    final reflectedRaw = <Offset>[
      for (final p in canonicalPeeled)
        p -
            canonicalNormal *
                (1.88 * math.max(0.0, _dot(p, canonicalNormal) - s)),
    ];
    final cFlapVertices = _clipPolygonRect(reflectedRaw, w, h);

    // Build cast shadow quad on the revealed side adjacent to the crease.
    final shadowQuad = <Offset>[
      cCreaseA,
      cCreaseB,
      cCreaseB + canonicalNormal * shadowWidth,
      cCreaseA + canonicalNormal * shadowWidth,
    ];
    final cShadowVertices = _clipPolygonRect(shadowQuad, w, h);

    Offset mapPoint(Offset p) =>
        direction == CurlDirection.forward ? p : Offset(w - p.dx, p.dy);

    final creaseStart = mapPoint(cCreaseA);
    final creaseEnd = mapPoint(cCreaseB);
    final creaseAnchor = mapPoint(cAnchor);
    final foldPoint = mapPoint(cFoldPoint);

    final bandHalf = (curlRadius * 1.15).clamp(6.0, 38.0);
    final highlightStart = creaseAnchor - normal * bandHalf;
    final highlightEnd = creaseAnchor + normal * bandHalf;
    final shadowStart = creaseAnchor;
    final shadowEnd = creaseAnchor + normal * shadowWidth;

    final frontPath = _buildPolygonPath(canonicalFront, mapPoint);
    final shadowPath = _buildPolygonPath(cShadowVertices, mapPoint);
    final backFlapPath = _buildBackFlapPath(
      clippedReflected: cFlapVertices,
      creaseA: cCreaseA,
      creaseB: cCreaseB,
      creaseAnchor: cAnchor,
      canonicalNormal: canonicalNormal,
      s: s,
      lipBulge: lipBulge,
      width: w,
      height: h,
      mapPoint: mapPoint,
    );

    return PageCurlGeometry(
      size: size,
      progress: t,
      direction: direction,
      creaseAnchor: creaseAnchor,
      creaseNormal: normal,
      creaseStart: creaseStart,
      creaseEnd: creaseEnd,
      foldPoint: foldPoint,
      frontPageClipPath: frontPath,
      backFlapPath: backFlapPath,
      dropShadowPath: shadowPath,
      highlightStart: highlightStart,
      highlightEnd: highlightEnd,
      shadowStart: shadowStart,
      shadowEnd: shadowEnd,
      curlRadius: curlRadius,
      isFlat: false,
    );
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  static Path _buildPolygonPath(
    List<Offset> vertices,
    Offset Function(Offset) mapPoint,
  ) {
    final path = Path();
    if (vertices.length < 3) return path;
    final p0 = mapPoint(vertices.first);
    path.moveTo(p0.dx, p0.dy);
    for (var i = 1; i < vertices.length; i++) {
      final p = mapPoint(vertices[i]);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  static Path _buildBackFlapPath({
    required List<Offset> clippedReflected,
    required Offset creaseA,
    required Offset creaseB,
    required Offset creaseAnchor,
    required Offset canonicalNormal,
    required double s,
    required double lipBulge,
    required double width,
    required double height,
    required Offset Function(Offset) mapPoint,
  }) {
    final path = Path();
    if (clippedReflected.length >= 3) {
      final n = clippedReflected.length;
      final first = mapPoint(clippedReflected.first);
      path.moveTo(first.dx, first.dy);

      for (var i = 0; i < n; i++) {
        final a = clippedReflected[i];
        final b = clippedReflected[(i + 1) % n];
        final aOnCrease = (_dot(a, canonicalNormal) - s).abs() <= 0.5;
        final bOnCrease = (_dot(b, canonicalNormal) - s).abs() <= 0.5;
        final endMapped = mapPoint(b);

        if (aOnCrease && bOnCrease && (b - a).distance > 2.0) {
          final mid = Offset(
            ((a.dx + b.dx) * 0.5 + canonicalNormal.dx * lipBulge).clamp(
              0.0,
              width,
            ),
            ((a.dy + b.dy) * 0.5 + canonicalNormal.dy * lipBulge).clamp(
              0.0,
              height,
            ),
          );
          final ctrl = mapPoint(mid);
          path.quadraticBezierTo(ctrl.dx, ctrl.dy, endMapped.dx, endMapped.dy);
        } else {
          final mid = Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);
          final onViewportBorder =
              (a.dx <= 0.5 && b.dx <= 0.5) ||
              (a.dx >= width - 0.5 && b.dx >= width - 0.5) ||
              (a.dy <= 0.5 && b.dy <= 0.5) ||
              (a.dy >= height - 0.5 && b.dy >= height - 0.5);
          if (!aOnCrease &&
              !bOnCrease &&
              !onViewportBorder &&
              (b - a).distance > 12.0) {
            // Gentle paper arch bow along the trailing outer flap edge.
            final bow = lipBulge * 0.45;
            final ctrlCanonical = Offset(
              (mid.dx + canonicalNormal.dx * bow).clamp(0.0, width),
              (mid.dy + canonicalNormal.dy * bow).clamp(0.0, height),
            );
            final ctrl = mapPoint(ctrlCanonical);
            path.quadraticBezierTo(
              ctrl.dx,
              ctrl.dy,
              endMapped.dx,
              endMapped.dy,
            );
          } else {
            path.lineTo(endMapped.dx, endMapped.dy);
          }
        }
      }
      path.close();
      return path;
    }

    // Degenerate extreme-progress fallback: thin curved lip crescent along crease.
    final start = mapPoint(creaseA);
    final end = mapPoint(creaseB);
    final crest = mapPoint(
      Offset(
        (creaseAnchor.dx + canonicalNormal.dx * lipBulge).clamp(0.0, width),
        (creaseAnchor.dy + canonicalNormal.dy * lipBulge).clamp(0.0, height),
      ),
    );
    final back = mapPoint(
      Offset(
        (creaseAnchor.dx - canonicalNormal.dx * lipBulge).clamp(0.0, width),
        (creaseAnchor.dy - canonicalNormal.dy * lipBulge).clamp(0.0, height),
      ),
    );
    path.moveTo(start.dx, start.dy);
    path.quadraticBezierTo(crest.dx, crest.dy, end.dx, end.dy);
    path.quadraticBezierTo(back.dx, back.dy, start.dx, start.dy);
    path.close();
    return path;
  }

  static List<Offset> _clipPolygonRect(
    List<Offset> poly,
    double width,
    double height,
  ) {
    var result = _clipPolygonHalfPlane(
      poly,
      const Offset(-1.0, 0.0),
      0.0,
      keepLessOrEqual: true,
    );
    result = _clipPolygonHalfPlane(
      result,
      const Offset(1.0, 0.0),
      width,
      keepLessOrEqual: true,
    );
    result = _clipPolygonHalfPlane(
      result,
      const Offset(0.0, -1.0),
      0.0,
      keepLessOrEqual: true,
    );
    result = _clipPolygonHalfPlane(
      result,
      const Offset(0.0, 1.0),
      height,
      keepLessOrEqual: true,
    );
    return result;
  }

  static List<Offset> _clipPolygonHalfPlane(
    List<Offset> poly,
    Offset normal,
    double threshold, {
    required bool keepLessOrEqual,
  }) {
    if (poly.isEmpty) return const <Offset>[];
    final out = <Offset>[];
    final count = poly.length;

    double signedDist(Offset p) {
      final raw = _dot(p, normal) - threshold;
      return keepLessOrEqual ? raw : -raw;
    }

    for (var i = 0; i < count; i++) {
      final curr = poly[i];
      final prev = poly[(i + count - 1) % count];
      final dCurr = signedDist(curr);
      final dPrev = signedDist(prev);
      final currIn = dCurr <= 1e-6;
      final prevIn = dPrev <= 1e-6;

      if (currIn) {
        if (!prevIn) {
          final denom = dPrev - dCurr;
          if (denom.abs() > 1e-9) {
            final ratio = (dPrev / denom).clamp(0.0, 1.0);
            out.add(Offset.lerp(prev, curr, ratio)!);
          }
        }
        out.add(curr);
      } else if (prevIn) {
        final denom = dPrev - dCurr;
        if (denom.abs() > 1e-9) {
          final ratio = (dPrev / denom).clamp(0.0, 1.0);
          out.add(Offset.lerp(prev, curr, ratio)!);
        }
      }
    }
    return out;
  }
}

/// Convenience top-level entry point delegating to [PageCurlGeometry.compute].
PageCurlGeometry computeCurl({
  required Size size,
  required double progress,
  CurlDirection direction = CurlDirection.forward,
  Offset dragVector = Offset.zero,
  double touchYNormalized = 0.68,
}) {
  return PageCurlGeometry.compute(
    size: size,
    progress: progress,
    direction: direction,
    dragVector: dragVector,
    touchYNormalized: touchYNormalized,
  );
}

/// 60/120fps interactive 3-layer page-curl simulation view supporting touch drag,
/// spring-back cancellation, tap-zone preservation, and programmatic turns.
class SimulationPageCurlView extends StatefulWidget {
  const SimulationPageCurlView({
    super.key,
    required this.pageKey,
    required this.currentChild,
    required this.canGoPrev,
    required this.canGoNext,
    required this.paperColor,
    required this.showOverlay,
    required this.onNextPage,
    required this.onPrevPage,
    required this.onToggleOverlay,
    this.nextChildBuilder,
    this.prevChildBuilder,
    this.lastTurnDirection = CurlDirection.forward,
    this.turnDuration = const Duration(milliseconds: 260),
  });

  /// Identity key for the active page/spread; changing it without an active
  /// drag triggers an animated programmatic page-curl transition.
  final Object pageKey;

  /// Active page widget currently resting at the top of the reading stack.
  final Widget currentChild;

  /// Builder producing the underneath target page when dragging forward.
  final Widget Function()? nextChildBuilder;

  /// Builder producing the underneath target page when dragging backward.
  final Widget Function()? prevChildBuilder;

  /// Whether stepping backward is allowed.
  final bool canGoPrev;

  /// Whether stepping forward is allowed.
  final bool canGoNext;

  /// Paper background color used to derive curled back-flap shading.
  final Color paperColor;

  /// Whether the reader overlay is currently shown (tapping dismisses it).
  final bool showOverlay;

  /// Callback invoked to commit advancing to the next page/spread.
  final Future<void> Function() onNextPage;

  /// Callback invoked to commit stepping to the previous page/spread.
  final Future<void> Function() onPrevPage;

  /// Callback invoked when tapping the center zone or dismissing the overlay.
  final VoidCallback onToggleOverlay;

  /// Direction used for programmatic `didUpdateWidget` turns.
  final CurlDirection lastTurnDirection;

  /// Full page-curl animation duration.
  final Duration turnDuration;

  @override
  State<SimulationPageCurlView> createState() => _SimulationPageCurlViewState();
}

class _SimulationPageCurlViewState extends State<SimulationPageCurlView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  bool _isDragging = false;
  bool _isSettlingDrag = false;
  bool _holdingCommittedTurn = false;
  bool _suppressNextDidUpdate = false;

  double _dragOffset = 0.0;
  double _dragStartOffset = 0.0;
  double _dragEndOffset = 0.0;
  double _touchYNormalized = 0.68;
  double _dragDeltaY = 0.0;
  int _dragDirection = 0; // -1: forward, 1: backward, 0: none
  Widget? _cachedDragTarget;

  Widget? _programmaticOutgoing;
  CurlDirection _programmaticDirection = CurlDirection.forward;
  double _programmaticProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: widget.turnDuration,
    )..addListener(_onAnimTick);
  }

  @override
  void didUpdateWidget(covariant SimulationPageCurlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnDuration != widget.turnDuration) {
      _animController.duration = widget.turnDuration;
    }

    final pageChanged = oldWidget.pageKey != widget.pageKey;
    if (!pageChanged) return;

    if (_suppressNextDidUpdate) {
      _suppressNextDidUpdate = false;
      _holdingCommittedTurn = false;
      _isSettlingDrag = false;
      _dragOffset = 0.0;
      _dragDirection = 0;
      _cachedDragTarget = null;
      _programmaticOutgoing = null;
      _programmaticProgress = 0.0;
      return;
    }

    _animController.stop();
    _isDragging = false;
    _isSettlingDrag = false;
    _holdingCommittedTurn = false;
    _dragOffset = 0.0;
    _dragDirection = 0;
    _cachedDragTarget = null;
    _programmaticOutgoing = oldWidget.currentChild;
    _programmaticDirection = widget.lastTurnDirection;
    _programmaticProgress = 0.0;
    _animController.duration = widget.turnDuration;
    unawaited(_animController.forward(from: 0.0));
  }

  @override
  void dispose() {
    _animController.removeListener(_onAnimTick);
    _animController.dispose();
    super.dispose();
  }

  void _onAnimTick() {
    if (!mounted) return;
    if (_isSettlingDrag) {
      setState(() {
        final curved = Curves.easeOutCubic.transform(_animController.value);
        _dragOffset =
            _dragStartOffset + (_dragEndOffset - _dragStartOffset) * curved;
      });
      return;
    }

    if (_programmaticOutgoing != null) {
      setState(() {
        _programmaticProgress = Curves.easeOutCubic.transform(
          _animController.value,
        );
        if (_animController.isCompleted) {
          _programmaticOutgoing = null;
          _programmaticProgress = 0.0;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(1.0, constraints.maxWidth);
        final height = math.max(1.0, constraints.maxHeight);
        final size = Size(width, height);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: (details) => _handleTapUp(details, width),
          onHorizontalDragStart: (details) => _onDragStart(details, size),
          onHorizontalDragUpdate: (details) => _onDragUpdate(details, size),
          onHorizontalDragEnd: (details) => _onDragEnd(details, width),
          onHorizontalDragCancel: _cancelDrag,
          child: ClipRect(
            child: _buildCurlContent(size),
          ),
        );
      },
    );
  }

  Widget _buildCurlContent(Size size) {
    final isDark = widget.paperColor.computeLuminance() < 0.3;

    // 1. Programmatic turn via tap / keyboard / wheel.
    if (_programmaticOutgoing != null) {
      final geometry = PageCurlGeometry.compute(
        size: size,
        progress: _programmaticProgress,
        direction: _programmaticDirection,
        touchYNormalized: 0.68,
      );
      if (geometry.isFlat && geometry.progress >= 1.0 - 1e-4) {
        return widget.currentChild;
      }
      return _buildThreeLayerStack(
        geometry: geometry,
        frontPage: _programmaticOutgoing!,
        underneathPage: widget.currentChild,
        isDark: isDark,
      );
    }

    // 2. Interactive drag or spring settle / commit hold.
    if (_holdingCommittedTurn && _cachedDragTarget != null) {
      return _cachedDragTarget!;
    }

    if (_dragDirection != 0 && _dragOffset != 0.0) {
      final direction = _dragDirection < 0
          ? CurlDirection.forward
          : CurlDirection.backward;
      final progress = (_dragOffset.abs() / size.width).clamp(0.0, 1.0);
      final normalizedDrag = Offset(
        (_dragOffset / size.width).clamp(-1.0, 1.0),
        (_dragDeltaY / math.max(1.0, size.height)).clamp(-1.0, 1.0),
      );
      final geometry = PageCurlGeometry.compute(
        size: size,
        progress: progress,
        direction: direction,
        dragVector: normalizedDrag,
        touchYNormalized: _touchYNormalized,
      );
      final underneath = _cachedDragTarget ?? ColoredBox(color: widget.paperColor);

      if (geometry.isFlat && geometry.progress >= 1.0 - 1e-4) {
        return underneath;
      }
      if (!geometry.isFlat) {
        return _buildThreeLayerStack(
          geometry: geometry,
          frontPage: widget.currentChild,
          underneathPage: underneath,
          isDark: isDark,
        );
      }
    }

    return widget.currentChild;
  }

  Widget _buildThreeLayerStack({
    required PageCurlGeometry geometry,
    required Widget frontPage,
    required Widget underneathPage,
    required bool isDark,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: Revealed target page + cast drop shadow.
        RepaintBoundary(child: underneathPage),
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _CurlUnderneathShadowPainter(
              geometry: geometry,
              isDark: isDark,
            ),
          ),
        ),
        // Layer 2: Clipped front page.
        ClipPath(
          clipper: _CurlFrontPageClipper(geometry.frontPageClipPath),
          child: RepaintBoundary(child: frontPage),
        ),
        // Layer 3: Curved back-flap with paper tint + specular crease gradient.
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _CurlBackFlapPainter(
              geometry: geometry,
              paperColor: widget.paperColor,
              isDark: isDark,
            ),
          ),
        ),
      ],
    );
  }

  void _handleTapUp(TapUpDetails details, double width) {
    if (widget.showOverlay) {
      widget.onToggleOverlay();
      return;
    }
    final x = details.localPosition.dx;
    if (x < width * 0.30) {
      if (widget.canGoPrev) {
        unawaited(widget.onPrevPage());
      }
    } else if (x > width * 0.70) {
      if (widget.canGoNext) {
        unawaited(widget.onNextPage());
      }
    } else {
      widget.onToggleOverlay();
    }
  }

  void _onDragStart(DragStartDetails details, Size size) {
    _animController.stop();
    _programmaticOutgoing = null;
    _programmaticProgress = 0.0;
    _isSettlingDrag = false;
    _holdingCommittedTurn = false;
    _suppressNextDidUpdate = false;
    setState(() {
      _isDragging = true;
      _dragOffset = 0.0;
      _dragDeltaY = 0.0;
      _dragDirection = 0;
      _cachedDragTarget = null;
      _touchYNormalized = (details.localPosition.dy / size.height).clamp(
        0.05,
        0.95,
      );
    });
  }

  void _onDragUpdate(DragUpdateDetails details, Size size) {
    if (!_isDragging) return;
    final nextOffset = _dragOffset + details.delta.dx;
    if (nextOffset < 0 && !widget.canGoNext) return;
    if (nextOffset > 0 && !widget.canGoPrev) return;

    final nextDir = nextOffset < 0 ? -1 : (nextOffset > 0 ? 1 : 0);
    if (nextDir != 0 && nextDir != _dragDirection) {
      _cachedDragTarget = nextDir < 0
          ? widget.nextChildBuilder?.call()
          : widget.prevChildBuilder?.call();
    }

    setState(() {
      _dragOffset = nextOffset.clamp(-size.width, size.width);
      _dragDeltaY = (_dragDeltaY + details.delta.dy).clamp(
        -size.height * 0.5,
        size.height * 0.5,
      );
      _dragDirection = nextDir;
    });
  }

  Future<void> _onDragEnd(DragEndDetails details, double width) async {
    if (!_isDragging) return;
    _isDragging = false;

    final velocityX = details.velocity.pixelsPerSecond.dx;
    final dir = _dragDirection;
    if (dir == 0 || _dragOffset == 0.0) {
      setState(() {
        _dragOffset = 0.0;
        _dragDirection = 0;
        _cachedDragTarget = null;
      });
      return;
    }

    final shouldComplete =
        (_dragOffset.abs() > width * 0.22) ||
        (dir < 0 && velocityX < -380) ||
        (dir > 0 && velocityX > 380);

    _dragStartOffset = _dragOffset;
    _dragEndOffset = shouldComplete ? dir * width : 0.0;
    final remainingRatio = shouldComplete
        ? (1.0 - (_dragOffset.abs() / width).clamp(0.0, 1.0))
        : (_dragOffset.abs() / width).clamp(0.0, 1.0);
    final ms = (widget.turnDuration.inMilliseconds * remainingRatio)
        .round()
        .clamp(90, widget.turnDuration.inMilliseconds);

    _isSettlingDrag = true;
    _animController.duration = Duration(milliseconds: ms);
    await _animController.forward(from: 0.0);
    _isSettlingDrag = false;
    if (!mounted) return;

    if (shouldComplete) {
      _suppressNextDidUpdate = true;
      setState(() {
        _holdingCommittedTurn = true;
        _dragOffset = 0.0;
        _dragDirection = 0;
      });
      try {
        if (dir < 0) {
          await widget.onNextPage();
        } else {
          await widget.onPrevPage();
        }
      } finally {
        if (mounted && _suppressNextDidUpdate) {
          _suppressNextDidUpdate = false;
          setState(() {
            _holdingCommittedTurn = false;
            _cachedDragTarget = null;
          });
        }
      }
    } else {
      setState(() {
        _dragOffset = 0.0;
        _dragDirection = 0;
        _cachedDragTarget = null;
      });
    }
  }

  void _cancelDrag() {
    if (!_isDragging) return;
    _isDragging = false;
    _dragStartOffset = _dragOffset;
    _dragEndOffset = 0.0;
    _isSettlingDrag = true;
    _animController.duration = const Duration(milliseconds: 180);
    unawaited(
      _animController.forward(from: 0.0).whenComplete(() {
        _isSettlingDrag = false;
        if (mounted) {
          setState(() {
            _dragOffset = 0.0;
            _dragDirection = 0;
            _cachedDragTarget = null;
          });
        }
      }),
    );
  }
}

class _CurlFrontPageClipper extends CustomClipper<Path> {
  const _CurlFrontPageClipper(this.clipPath);

  final Path clipPath;

  @override
  Path getClip(Size size) => clipPath;

  @override
  bool shouldReclip(covariant _CurlFrontPageClipper oldClipper) =>
      oldClipper.clipPath != clipPath;
}

class _CurlUnderneathShadowPainter extends CustomPainter {
  const _CurlUnderneathShadowPainter({
    required this.geometry,
    required this.isDark,
  });

  final PageCurlGeometry geometry;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.isFlat || geometry.dropShadowPath.getBounds().isEmpty) {
      return;
    }

    final start = geometry.shadowStart;
    final end = geometry.shadowEnd;
    if ((end - start).distanceSquared < 1.0) return;

    final maxAlpha = isDark ? 150 : 94;
    final midAlpha = isDark ? 64 : 34;

    final shadowPaint = Paint()
      ..shader = ui.Gradient.linear(
        start,
        end,
        <Color>[
          Color.fromARGB(maxAlpha, 0, 0, 0),
          Color.fromARGB(midAlpha, 0, 0, 0),
          const Color(0x00000000),
        ],
        const <double>[0.0, 0.42, 1.0],
      );

    canvas.drawPath(geometry.dropShadowPath, shadowPaint);
  }

  @override
  bool shouldRepaint(covariant _CurlUnderneathShadowPainter oldDelegate) =>
      oldDelegate.geometry != geometry || oldDelegate.isDark != isDark;
}

class _CurlBackFlapPainter extends CustomPainter {
  const _CurlBackFlapPainter({
    required this.geometry,
    required this.paperColor,
    required this.isDark,
  });

  final PageCurlGeometry geometry;
  final Color paperColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.isFlat || geometry.backFlapPath.getBounds().isEmpty) {
      return;
    }

    // 1. Subtle soft contact shadow cast onto the front page beneath the flap.
    final liftOffset = geometry.creaseNormal * (-math.min(6.0, geometry.curlRadius * 0.25));
    canvas.save();
    canvas.translate(liftOffset.dx, liftOffset.dy);
    final underShadowPaint = Paint()
      ..color = Color.fromARGB(isDark ? 72 : 34, 0, 0, 0);
    canvas.drawPath(geometry.backFlapPath, underShadowPaint);
    canvas.restore();

    // 2. Curved back-flap paper body with subtle front/back paper tint.
    final backBase = isDark
        ? Color.lerp(paperColor, const Color(0xFF3A3E44), 0.34)!
        : Color.lerp(paperColor, const Color(0xFFD6CCB9), 0.28)!;
    final backMid = isDark
        ? Color.lerp(paperColor, const Color(0xFF282B30), 0.42)!
        : Color.lerp(paperColor, const Color(0xFFE7DEC9), 0.36)!;

    final baseFlapPaint = Paint()
      ..color = backBase
      ..style = PaintingStyle.fill;
    canvas.drawPath(geometry.backFlapPath, baseFlapPaint);

    // 3. Cylindrical specular crease highlight + curvature shading along normal.
    final hStart = geometry.highlightStart;
    final hEnd = geometry.highlightEnd;
    if ((hEnd - hStart).distanceSquared >= 1.0) {
      final specularPeak = isDark
          ? const Color(0x36FFFFFF)
          : const Color(0x66FFFFFF);
      final valleyShade = isDark
          ? const Color(0x44000000)
          : const Color(0x22000000);

      final creasePaint = Paint()
        ..shader = ui.Gradient.linear(
          hStart,
          hEnd,
          <Color>[
            backMid.withAlpha(180),
            valleyShade,
            specularPeak,
            backBase.withAlpha(230),
            valleyShade,
          ],
          const <double>[0.0, 0.26, 0.50, 0.78, 1.0],
        );
      canvas.drawPath(geometry.backFlapPath, creasePaint);
    }

    // 4. Crisp 0.75px outer paper lip edge.
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = isDark
          ? const Color(0x30FFFFFF)
          : const Color(0x24000000);
    canvas.drawPath(geometry.backFlapPath, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _CurlBackFlapPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.paperColor != paperColor ||
      oldDelegate.isDark != isDark;
}
