import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/domain.dart';
import 'reader_page_painter.dart';

/// Renders paginated reader pages across `none`, `slide`, `cover`, and `scroll`
/// page-turn modes, supporting tap zones, interactive drag with cancel
/// spring-back, and throttled mouse-wheel paging.
class ReaderPageTurnView extends StatefulWidget {
  const ReaderPageTurnView({
    super.key,
    required this.mode,
    required this.columnCount,
    required this.config,
    required this.pages,
    required this.currentPageIndex,
    required this.currentChapterIndex,
    required this.canGoPrev,
    required this.canGoNext,
    required this.backgroundColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.showOverlay,
    required this.onNextPage,
    required this.onPrevPage,
    required this.onToggleOverlay,
    required this.onScrollOffsetChanged,
  });

  final PageTurnMode mode;
  final int columnCount;
  final PaginationConfig config;
  final List<PageSlice> pages;
  final int currentPageIndex;
  final int currentChapterIndex;
  final bool canGoPrev;
  final bool canGoNext;
  final Color backgroundColor;
  final Color textColor;
  final Color secondaryTextColor;
  final bool showOverlay;
  final Future<void> Function() onNextPage;
  final Future<void> Function() onPrevPage;
  final VoidCallback onToggleOverlay;
  final ValueChanged<int> onScrollOffsetChanged;

  @override
  State<ReaderPageTurnView> createState() => _ReaderPageTurnViewState();
}

class _ReaderPageTurnViewState extends State<ReaderPageTurnView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final ScrollController _scrollController = ScrollController();

  double _dragOffset = 0.0;
  double _animStartOffset = 0.0;
  double _animEndOffset = 0.0;
  bool _isDragging = false;
  int _dragDirection = 0; // -1: next, 1: prev, 0: none
  bool _pendingTurnHandled = false;

  PageSlice? _outgoingLeft;
  PageSlice? _outgoingRight;
  int _externalAnimDirection = 0; // -1: forward, 1: backward, 0: none

  DateTime _lastWheelTurnAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_onAnimTick);
  }

  @override
  void didUpdateWidget(covariant ReaderPageTurnView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final pageChanged =
        oldWidget.currentPageIndex != widget.currentPageIndex ||
        oldWidget.currentChapterIndex != widget.currentChapterIndex;

    if (pageChanged && !_pendingTurnHandled) {
      final supportsAnimatedTurn =
          widget.mode == PageTurnMode.slide ||
          widget.mode == PageTurnMode.cover ||
          widget.mode == PageTurnMode.simulation;
      if (supportsAnimatedTurn && oldWidget.pages.isNotEmpty) {
        final oldLeft = _sliceAt(oldWidget.pages, oldWidget.currentPageIndex);
        final oldRight = oldWidget.columnCount == 2
            ? _sliceAt(oldWidget.pages, oldWidget.currentPageIndex + 1)
            : null;
        final isForward =
            widget.currentChapterIndex > oldWidget.currentChapterIndex ||
            (widget.currentChapterIndex == oldWidget.currentChapterIndex &&
                widget.currentPageIndex > oldWidget.currentPageIndex);
        _outgoingLeft = oldLeft;
        _outgoingRight = oldRight;
        _externalAnimDirection = isForward ? -1 : 1;
        _dragDirection = 0;
        _dragOffset = 0;
        _animController.forward(from: 0.0);
      }
    }
    _pendingTurnHandled = false;
  }

  @override
  void dispose() {
    _animController.removeListener(_onAnimTick);
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onAnimTick() {
    if (!mounted) return;
    if (_externalAnimDirection == 0 && _dragDirection != 0) {
      setState(() {
        final t = Curves.easeOutCubic.transform(_animController.value);
        _dragOffset = _animStartOffset + (_animEndOffset - _animStartOffset) * t;
      });
    } else if (_externalAnimDirection != 0) {
      setState(() {});
      if (_animController.isCompleted) {
        setState(() {
          _outgoingLeft = null;
          _outgoingRight = null;
          _externalAnimDirection = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == PageTurnMode.scroll) {
      return _buildScrollMode(context);
    }

    final currLeft = _sliceAt(widget.pages, widget.currentPageIndex);
    final currRight = widget.columnCount == 2
        ? _sliceAt(widget.pages, widget.currentPageIndex + 1)
        : null;

    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(1.0, constraints.maxWidth);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTapUp(details, width),
            onHorizontalDragStart: _supportsHorizontalDrag
                ? (details) => _onDragStart(details, width)
                : null,
            onHorizontalDragUpdate: _supportsHorizontalDrag
                ? (details) => _onDragUpdate(details, width)
                : null,
            onHorizontalDragEnd: _supportsHorizontalDrag
                ? (details) => _onDragEnd(details, width)
                : null,
            onHorizontalDragCancel: _supportsHorizontalDrag ? _cancelDrag : null,
            child: ClipRect(
              child: _buildPagedStack(
                width: width,
                currLeft: currLeft,
                currRight: currRight,
              ),
            ),
          );
        },
      ),
    );
  }

  bool get _supportsHorizontalDrag =>
      widget.mode == PageTurnMode.slide ||
      widget.mode == PageTurnMode.cover ||
      widget.mode == PageTurnMode.simulation;

  Widget _buildPagedStack({
    required double width,
    required PageSlice? currLeft,
    required PageSlice? currRight,
  }) {
    if (widget.mode == PageTurnMode.none) {
      return _paintCanvas(currLeft, currRight);
    }

    final isCoverMode =
        widget.mode == PageTurnMode.cover ||
        widget.mode == PageTurnMode.simulation;

    // External non-drag animated page transition (tap, keyboard, wheel, volume).
    if (_externalAnimDirection != 0 && _outgoingLeft != null) {
      final t = Curves.easeOutCubic.transform(_animController.value);
      if (isCoverMode) {
        if (_externalAnimDirection < 0) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _paintCanvas(currLeft, currRight),
              Transform.translate(
                offset: Offset(-width * t, 0),
                child: _withPageShadow(
                  _paintCanvas(_outgoingLeft, _outgoingRight),
                ),
              ),
            ],
          );
        } else {
          return Stack(
            fit: StackFit.expand,
            children: [
              _paintCanvas(_outgoingLeft, _outgoingRight),
              Transform.translate(
                offset: Offset(-width * (1.0 - t), 0),
                child: _withPageShadow(_paintCanvas(currLeft, currRight)),
              ),
            ],
          );
        }
      } else {
        // Slide mode.
        final sign = _externalAnimDirection;
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset(sign * width * t, 0),
              child: _paintCanvas(_outgoingLeft, _outgoingRight),
            ),
            Transform.translate(
              offset: Offset(sign * width * (t - 1.0), 0),
              child: _paintCanvas(currLeft, currRight),
            ),
          ],
        );
      }
    }

    // Interactive horizontal drag in progress or settling.
    if (_dragDirection != 0 && _dragOffset != 0.0) {
      final targetOffset = _dragDirection < 0
          ? widget.currentPageIndex + widget.columnCount
          : math.max(0, widget.currentPageIndex - widget.columnCount);
      final targetLeft = _sliceAt(widget.pages, targetOffset);
      final targetRight = widget.columnCount == 2
          ? _sliceAt(widget.pages, targetOffset + 1)
          : null;

      if (isCoverMode) {
        if (_dragDirection < 0) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _paintCanvas(targetLeft, targetRight),
              Transform.translate(
                offset: Offset(_dragOffset, 0),
                child: _withPageShadow(_paintCanvas(currLeft, currRight)),
              ),
            ],
          );
        } else {
          return Stack(
            fit: StackFit.expand,
            children: [
              _paintCanvas(currLeft, currRight),
              Transform.translate(
                offset: Offset(-width + _dragOffset, 0),
                child: _withPageShadow(_paintCanvas(targetLeft, targetRight)),
              ),
            ],
          );
        }
      } else {
        // Slide mode.
        final incomingOffset = _dragDirection < 0
            ? width + _dragOffset
            : -width + _dragOffset;
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: _paintCanvas(currLeft, currRight),
            ),
            Transform.translate(
              offset: Offset(incomingOffset, 0),
              child: _paintCanvas(targetLeft, targetRight),
            ),
          ],
        );
      }
    }

    return _paintCanvas(currLeft, currRight);
  }

  Widget _paintCanvas(PageSlice? left, PageSlice? right) {
    return CustomPaint(
      size: Size.infinite,
      painter: ReaderPagePainter(
        config: widget.config,
        leftPage: left,
        rightPage: right,
        backgroundColor: widget.backgroundColor,
        textColor: widget.textColor,
        secondaryTextColor: widget.secondaryTextColor,
      ),
    );
  }

  Widget _withPageShadow(Widget child) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 16,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildScrollMode(BuildContext context) {
    final pages = widget.pages;
    if (pages.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleOverlay,
        child: Container(color: widget.backgroundColor),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification && _scrollController.hasClients) {
          final sliceHeight = widget.config.columnHeight + 24.0;
          final approxPage = (_scrollController.offset / sliceHeight)
              .round()
              .clamp(0, pages.length - 1);
          widget.onScrollOffsetChanged(pages[approxPage].startCharOffset);
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onToggleOverlay,
        child: Container(
          color: widget.backgroundColor,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: pages.length + 1,
            itemBuilder: (context, index) {
              if (index == pages.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.canGoPrev)
                        OutlinedButton(
                          onPressed: widget.onPrevPage,
                          child: const Text('上一章'),
                        ),
                      if (widget.canGoPrev && widget.canGoNext)
                        const SizedBox(width: 16),
                      if (widget.canGoNext)
                        FilledButton.tonal(
                          onPressed: widget.onNextPage,
                          child: const Text('下一章'),
                        ),
                    ],
                  ),
                );
              }

              final slice = pages[index];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: widget.config.columnHeight,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: ReaderPagePainter(
                        config: widget.config.copyWith(columnCount: 1),
                        leftPage: slice,
                        backgroundColor: widget.backgroundColor,
                        textColor: widget.textColor,
                        secondaryTextColor: widget.secondaryTextColor,
                      ),
                    ),
                  ),
                  Divider(
                    height: 24,
                    thickness: 0.5,
                    color: widget.secondaryTextColor.withAlpha(40),
                    indent: 24,
                    endIndent: 24,
                  ),
                ],
              );
            },
          ),
        ),
      ),
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
        widget.onPrevPage();
      }
    } else if (x > width * 0.70) {
      if (widget.canGoNext) {
        widget.onNextPage();
      }
    } else {
      widget.onToggleOverlay();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheelTurnAt) < const Duration(milliseconds: 140)) {
      return;
    }
    _lastWheelTurnAt = now;
    if (event.scrollDelta.dy > 0) {
      if (widget.canGoNext) widget.onNextPage();
    } else if (event.scrollDelta.dy < 0) {
      if (widget.canGoPrev) widget.onPrevPage();
    }
  }

  void _onDragStart(DragStartDetails details, double width) {
    _animController.stop();
    _externalAnimDirection = 0;
    _outgoingLeft = null;
    _outgoingRight = null;
    setState(() {
      _isDragging = true;
      _dragOffset = 0.0;
      _dragDirection = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (!_isDragging) return;
    final nextOffset = _dragOffset + details.delta.dx;
    if (nextOffset < 0 && !widget.canGoNext) return;
    if (nextOffset > 0 && !widget.canGoPrev) return;

    setState(() {
      _dragOffset = nextOffset.clamp(-width, width);
      _dragDirection = _dragOffset < 0 ? -1 : (_dragOffset > 0 ? 1 : 0);
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
      });
      return;
    }

    final shouldComplete =
        (_dragOffset.abs() > width * 0.22) ||
        (dir < 0 && velocityX < -380) ||
        (dir > 0 && velocityX > 380);

    _animStartOffset = _dragOffset;
    _animEndOffset = shouldComplete ? dir * width : 0.0;
    await _animController.forward(from: 0.0);
    if (!mounted) return;

    if (shouldComplete) {
      _pendingTurnHandled = true;
      setState(() {
        _dragOffset = 0.0;
        _dragDirection = 0;
      });
      if (dir < 0) {
        await widget.onNextPage();
      } else {
        await widget.onPrevPage();
      }
    } else {
      setState(() {
        _dragOffset = 0.0;
        _dragDirection = 0;
      });
    }
  }

  void _cancelDrag() {
    if (!_isDragging) return;
    _isDragging = false;
    _animStartOffset = _dragOffset;
    _animEndOffset = 0.0;
    _animController.forward(from: 0.0).whenComplete(() {
      if (mounted) {
        setState(() {
          _dragOffset = 0.0;
          _dragDirection = 0;
        });
      }
    });
  }

  PageSlice? _sliceAt(List<PageSlice> pages, int index) {
    if (index < 0 || index >= pages.length) return null;
    return pages[index];
  }
}
