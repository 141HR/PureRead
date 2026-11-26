import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../application/reader/auto_read_state.dart';
import '../../application/reader/epub_image_cache.dart';
import '../../domain/domain.dart';
import '../../engine/reader_engine/inline_image_marker.dart';
import 'reader_auto_read_overlay.dart';
import 'reader_page_painter.dart';
import 'simulation_page_curl.dart';

/// Renders paginated reader pages across `none`, `slide`, `cover`, `simulation`,
/// and `scroll` page-turn modes, supporting tap zones, inline EPUB image taps,
/// TTS sentence highlights, optional Auto-Read overlay wrapping, interactive
/// drag with cancel spring-back, and throttled mouse-wheel paging.
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
    this.dividerColor,
    this.epubImageCache,
    this.book,
    this.ttsHighlightChapterIndex,
    this.ttsHighlightStartOffset,
    this.ttsHighlightEndOffset,
    this.ttsHighlightColor,
    this.onTapImage,
    this.autoReadState,
    this.onAutoReadAdvance,
    this.onAutoReadToggleControls,
    this.onAutoReadReachedEnd,
    this.nextChapterTitle,
    this.autoReadAccentColor,
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
  final Color? dividerColor;
  final EpubImageCache? epubImageCache;
  final Book? book;
  final int? ttsHighlightChapterIndex;
  final int? ttsHighlightStartOffset;
  final int? ttsHighlightEndOffset;
  final Color? ttsHighlightColor;
  final ValueChanged<InlineImageRef>? onTapImage;
  final AutoReadState? autoReadState;
  final Future<void> Function()? onAutoReadAdvance;
  final VoidCallback? onAutoReadToggleControls;
  final VoidCallback? onAutoReadReachedEnd;
  final String? nextChapterTitle;
  final Color? autoReadAccentColor;

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
  int _gestureEpoch = 0;

  PageSlice? _outgoingLeft;
  PageSlice? _outgoingRight;
  int _externalAnimDirection = 0; // -1: forward, 1: backward, 0: none
  bool _lastSimulationForward = true;

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

    final modeChanged = oldWidget.mode != widget.mode;
    if (modeChanged) {
      _gestureEpoch++;
      _animController.stop();
      _outgoingLeft = null;
      _outgoingRight = null;
      _externalAnimDirection = 0;
      _dragDirection = 0;
      _dragOffset = 0.0;
      _isDragging = false;
      _pendingTurnHandled = false;
    }

    final pageChanged =
        oldWidget.currentPageIndex != widget.currentPageIndex ||
        oldWidget.currentChapterIndex != widget.currentChapterIndex;

    final inCurtainAutoRead =
        widget.autoReadState?.isActive == true &&
        widget.autoReadState?.mode == AutoReadMode.curtain;
    if (inCurtainAutoRead) {
      _outgoingLeft = null;
      _outgoingRight = null;
      _externalAnimDirection = 0;
      _pendingTurnHandled = false;
      return;
    }

    if (widget.mode == PageTurnMode.simulation) {
      if (pageChanged) {
        _lastSimulationForward =
            widget.currentChapterIndex > oldWidget.currentChapterIndex ||
            (widget.currentChapterIndex == oldWidget.currentChapterIndex &&
                widget.currentPageIndex > oldWidget.currentPageIndex);
      }
      _pendingTurnHandled = false;
      return;
    }

    if (pageChanged && !_pendingTurnHandled) {
      final supportsAnimatedTurn =
          widget.mode == PageTurnMode.slide ||
          widget.mode == PageTurnMode.cover;
      if (supportsAnimatedTurn && oldWidget.pages.isNotEmpty) {
        final oldLeft = _sliceAt(oldWidget.pages, oldWidget.currentPageIndex);
        final oldRight = oldWidget.columnCount == 2
            ? _sliceAt(oldWidget.pages, oldWidget.currentPageIndex + 1)
            : null;
        final isForward =
            widget.currentChapterIndex > oldWidget.currentChapterIndex ||
            (widget.currentChapterIndex == oldWidget.currentChapterIndex &&
                widget.currentPageIndex > oldWidget.currentPageIndex);
        _gestureEpoch++;
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
    _gestureEpoch++;
    _animController.removeListener(_onAnimTick);
    _animController.stop();
    _animController.dispose();
    _scrollController.dispose();
    _outgoingLeft = null;
    _outgoingRight = null;
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
    final currLeft = _sliceAt(widget.pages, widget.currentPageIndex);
    final currRight = widget.columnCount == 2
        ? _sliceAt(widget.pages, widget.currentPageIndex + 1)
        : null;

    final autoRead = widget.autoReadState;
    if (autoRead != null && autoRead.isActive) {
      final isCurtain = autoRead.mode == AutoReadMode.curtain;
      final Widget currentLayer = isCurtain
          ? _paintCanvas(currLeft, currRight)
          : _buildReadingBody(context, currLeft, currRight);
      Widget? nextLayer;
      if (isCurtain) {
        final nextOffset = widget.currentPageIndex + widget.columnCount;
        final nextLeft = _sliceAt(widget.pages, nextOffset);
        final nextRight = widget.columnCount == 2
            ? _sliceAt(widget.pages, nextOffset + 1)
            : null;
        if (nextLeft != null) {
          nextLayer = _paintCanvas(nextLeft, nextRight);
        } else if (widget.canGoNext) {
          nextLayer = _buildNextChapterPreviewCard();
        }
      }

      return ReaderAutoReadOverlay(
        currentPageChild: currentLayer,
        nextPageChild: nextLayer,
        state: autoRead,
        canGoNext: widget.canGoNext,
        accentColor:
            widget.autoReadAccentColor ?? Theme.of(context).colorScheme.primary,
        dividerColor:
            widget.dividerColor ?? widget.secondaryTextColor.withAlpha(70),
        onAdvancePage: widget.onAutoReadAdvance ?? widget.onNextPage,
        onToggleControls:
            widget.onAutoReadToggleControls ?? widget.onToggleOverlay,
        onReachedBookEnd: widget.onAutoReadReachedEnd,
      );
    }

    return _buildReadingBody(context, currLeft, currRight);
  }

  Widget _buildReadingBody(
    BuildContext context,
    PageSlice? currLeft,
    PageSlice? currRight,
  ) {
    if (widget.mode == PageTurnMode.scroll) {
      return _buildScrollMode(context);
    }

    if (widget.mode == PageTurnMode.simulation) {
      return Listener(
        onPointerSignal: _handlePointerSignal,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(
              math.max(1.0, constraints.maxWidth),
              math.max(1.0, constraints.maxHeight),
            );
            return SimulationPageCurlView(
              pageKey: ValueKey<String>(
                '${widget.currentChapterIndex}:${widget.currentPageIndex}',
              ),
              currentChild: _paintCanvas(currLeft, currRight),
              nextChildBuilder: () {
                final nextOffset = widget.currentPageIndex + widget.columnCount;
                final nextLeft = _sliceAt(widget.pages, nextOffset);
                final nextRight = widget.columnCount == 2
                    ? _sliceAt(widget.pages, nextOffset + 1)
                    : null;
                return _paintCanvas(nextLeft, nextRight);
              },
              prevChildBuilder: () {
                final hasPrevInChapter = widget.currentPageIndex > 0;
                final prevOffset = math.max(
                  0,
                  widget.currentPageIndex - widget.columnCount,
                );
                final prevLeft = hasPrevInChapter
                    ? _sliceAt(widget.pages, prevOffset)
                    : null;
                final prevRight = (hasPrevInChapter && widget.columnCount == 2)
                    ? _sliceAt(widget.pages, prevOffset + 1)
                    : null;
                return _paintCanvas(prevLeft, prevRight);
              },
              canGoPrev: widget.canGoPrev,
              canGoNext: widget.canGoNext,
              paperColor: widget.backgroundColor,
              showOverlay: widget.showOverlay,
              onNextPage: widget.onNextPage,
              onPrevPage: widget.onPrevPage,
              onToggleOverlay: widget.onToggleOverlay,
              onInterceptTap: widget.onTapImage == null
                  ? null
                  : (localPos) {
                      if (widget.showOverlay) return false;
                      return _tryHandleImageTap(localPos, viewportSize);
                    },
              lastTurnDirection: _lastSimulationForward
                  ? CurlDirection.forward
                  : CurlDirection.backward,
            );
          },
        ),
      );
    }

    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(1.0, constraints.maxWidth);
          final height = math.max(1.0, constraints.maxHeight);
          final viewportSize = Size(width, height);
          return buildEdgeGuardedPageTurnDetector(
            context: context,
            viewportWidth: width,
            enableHorizontalDrag: _supportsHorizontalDrag,
            dragStartBehavior: DragStartBehavior.start,
            onTapUp: (details) => _handleTapUp(details, viewportSize),
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

  Widget _buildNextChapterPreviewCard() {
    final title = widget.nextChapterTitle?.trim() ?? '';
    return ColoredBox(
      color: widget.backgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 32,
                color: widget.secondaryTextColor,
              ),
              const SizedBox(height: 12),
              Text(
                '即将进入下一章',
                style: TextStyle(
                  color: widget.secondaryTextColor,
                  fontSize: 13,
                ),
              ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _supportsHorizontalDrag =>
      widget.mode == PageTurnMode.slide || widget.mode == PageTurnMode.cover;

  Widget _buildPagedStack({
    required double width,
    required PageSlice? currLeft,
    required PageSlice? currRight,
  }) {
    if (widget.mode == PageTurnMode.none) {
      return _paintCanvas(currLeft, currRight);
    }

    final isCoverMode = widget.mode == PageTurnMode.cover;

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
        dividerColor: widget.dividerColor,
        epubImageCache: widget.epubImageCache,
        book: widget.book,
        ttsHighlightChapterIndex: widget.ttsHighlightChapterIndex,
        ttsHighlightStartOffset: widget.ttsHighlightStartOffset,
        ttsHighlightEndOffset: widget.ttsHighlightEndOffset,
        ttsHighlightColor: widget.ttsHighlightColor,
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
              final scrollConfig = widget.config.copyWith(columnCount: 1);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: widget.config.columnHeight,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (itemContext, itemConstraints) {
                        final itemSize = Size(
                          math.max(1.0, itemConstraints.maxWidth),
                          widget.config.columnHeight,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            if (widget.showOverlay) {
                              widget.onToggleOverlay();
                              return;
                            }
                            if (widget.onTapImage != null) {
                              final hit = ReaderPagePainter.hitTestImage(
                                localPosition: details.localPosition,
                                size: itemSize,
                                config: scrollConfig,
                                leftPage: slice,
                                rightPage: null,
                              );
                              if (hit != null) {
                                widget.onTapImage!(hit.ref);
                                return;
                              }
                            }
                            widget.onToggleOverlay();
                          },
                          child: CustomPaint(
                            painter: ReaderPagePainter(
                              config: scrollConfig,
                              leftPage: slice,
                              backgroundColor: widget.backgroundColor,
                              textColor: widget.textColor,
                              secondaryTextColor: widget.secondaryTextColor,
                              dividerColor: widget.dividerColor,
                              epubImageCache: widget.epubImageCache,
                              book: widget.book,
                              ttsHighlightChapterIndex:
                                  widget.ttsHighlightChapterIndex,
                              ttsHighlightStartOffset:
                                  widget.ttsHighlightStartOffset,
                              ttsHighlightEndOffset:
                                  widget.ttsHighlightEndOffset,
                              ttsHighlightColor: widget.ttsHighlightColor,
                            ),
                          ),
                        );
                      },
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

  bool _tryHandleImageTap(Offset localPosition, Size viewportSize) {
    final onTapImage = widget.onTapImage;
    if (onTapImage == null) return false;
    final currLeft = _sliceAt(widget.pages, widget.currentPageIndex);
    final currRight = widget.columnCount == 2
        ? _sliceAt(widget.pages, widget.currentPageIndex + 1)
        : null;
    final hit = ReaderPagePainter.hitTestImage(
      localPosition: localPosition,
      size: viewportSize,
      config: widget.config,
      leftPage: currLeft,
      rightPage: currRight,
    );
    if (hit == null) return false;
    onTapImage(hit.ref);
    return true;
  }

  void _handleTapUp(TapUpDetails details, Size viewportSize) {
    if (widget.showOverlay) {
      widget.onToggleOverlay();
      return;
    }
    if (_tryHandleImageTap(details.localPosition, viewportSize)) {
      return;
    }
    final x = details.localPosition.dx;
    final width = viewportSize.width;
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
    _gestureEpoch++;
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

    final epoch = _gestureEpoch;
    _animStartOffset = _dragOffset;
    _animEndOffset = shouldComplete ? dir * width : 0.0;
    await _animController.forward(from: 0.0);
    if (!mounted || epoch != _gestureEpoch) return;

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
    if (_dragOffset == 0.0 || _dragDirection == 0) {
      setState(() {
        _dragOffset = 0.0;
        _dragDirection = 0;
      });
      return;
    }
    final epoch = _gestureEpoch;
    _animStartOffset = _dragOffset;
    _animEndOffset = 0.0;
    _animController.forward(from: 0.0).whenComplete(() {
      if (mounted && epoch == _gestureEpoch) {
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
