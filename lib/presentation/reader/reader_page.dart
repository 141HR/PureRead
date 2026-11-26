import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/core_providers.dart';
import '../../application/reader/auto_read_controller.dart';
import '../../application/reader/auto_read_state.dart';
import '../../application/reader/epub_image_cache.dart';
import '../../application/reader/reader_search_controller.dart';
import '../../application/reader/reader_search_state.dart';
import '../../application/reader/reader_session_controller.dart';
import '../../application/reader/reader_session_state.dart';
import '../../application/reader/tts_controller.dart';
import '../../application/reader/tts_state.dart';
import '../../domain/domain.dart';
import '../../infrastructure/platform/platform_bridge.dart';
import '../search/change_source_sheet.dart';
import 'epub_image_viewer_dialog.dart';
import 'reader_auto_read_bar.dart';
import 'reader_bookmarks_sheet.dart';
import 'reader_page_turn_view.dart';
import 'reader_search_sheet.dart';
import 'reader_settings_sheet.dart';
import 'reader_toc_drawer.dart';
import 'reader_tts_bar.dart';
import 'reader_tts_settings_sheet.dart';

/// Adaptive single/dual-column reader screen supporting `charOffset` stable
/// repagination, 4 page-turn modes, keyboard/mouse/volume interactions, TOC,
/// jump-undo, bookmarks, and live typography/theme customization.
class ReaderPage extends ConsumerStatefulWidget {
  final String bookId;

  const ReaderPage({
    super.key,
    required this.bookId,
  });

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FocusNode _focusNode = FocusNode(debugLabel: 'ReaderCanvasFocus');

  Size? _lastReportedCanvasSize;
  double? _pendingSeekRatio;
  bool _isSearchSheetOpen = false;

  EpubImageCache? _epubImageCache;
  AutoReadController? _autoReadController;
  TtsController? _ttsController;
  TtsReaderHost? _ttsHost;
  PlatformBridge? _platformBridge;
  bool _lastSessionKeepScreenOn = false;
  bool _autoReadKeepScreenOnApplied = false;
  ({int chapterIndex, int start, int end})? _lastViewportLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platformBridge = ref.read(platformBridgeProvider);
    _autoReadController = ref.read(autoReadControllerProvider.notifier);
    _ttsController = ref.read(ttsControllerProvider.notifier);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoReadController?.stop();
    if (_autoReadKeepScreenOnApplied) {
      _autoReadKeepScreenOnApplied = false;
      unawaited(_platformBridge?.setKeepScreenOn(_lastSessionKeepScreenOn));
    }
    _ttsController?.detachHost(_ttsHost);
    _epubImageCache?.dispose();
    _epubImageCache = null;
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(
        ref
            .read(readerSessionControllerProvider(widget.bookId).notifier)
            .flushProgress(),
      );
    }
  }

  void _scheduleViewportSync(Size size) {
    if (_lastReportedCanvasSize != null &&
        (_lastReportedCanvasSize!.width - size.width).abs() < 0.5 &&
        (_lastReportedCanvasSize!.height - size.height).abs() < 0.5) {
      return;
    }
    _lastReportedCanvasSize = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(readerSessionControllerProvider(widget.bookId).notifier)
          .updateViewportSize(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ReaderSearchState>(
      readerSearchControllerProvider(widget.bookId),
      (_, _) {},
    );
    ref.listen<ReaderSessionState>(
      readerSessionControllerProvider(widget.bookId),
      (prev, next) {
        _lastSessionKeepScreenOn = next.keepScreenOn;
        _syncAutoReadKeepScreenOn(
          autoReadRunning: ref.read(autoReadControllerProvider).isRunning,
          sessionKeepScreenOn: next.keepScreenOn,
        );
        _notifyTtsViewportIfSettled(next);
      },
    );
    ref.listen<AutoReadState>(autoReadControllerProvider, (prev, next) {
      if (!(prev?.isActive ?? false) && next.isActive) {
        final ttsState = ref.read(ttsControllerProvider);
        if (ttsState.status != TtsStatus.idle) {
          unawaited(ref.read(ttsControllerProvider.notifier).stop());
        }
      }
      _syncAutoReadKeepScreenOn(
        autoReadRunning: next.isRunning,
        sessionKeepScreenOn: _lastSessionKeepScreenOn,
      );
    });
    ref.listen<TtsState>(ttsControllerProvider, (prev, next) {
      if (!(prev?.isActive ?? false) && next.isActive) {
        if (ref.read(autoReadControllerProvider).isActive) {
          ref.read(autoReadControllerProvider.notifier).stop();
        }
      }
    });

    final state = ref.watch(readerSessionControllerProvider(widget.bookId));
    final controller = ref.read(
      readerSessionControllerProvider(widget.bookId).notifier,
    );
    final ttsState = ref.watch(ttsControllerProvider);
    final ttsController = ref.read(ttsControllerProvider.notifier);
    final autoReadState = ref.watch(autoReadControllerProvider);
    final autoReadController = ref.read(autoReadControllerProvider.notifier);
    final imageCache = ref.watch(epubImageCacheProvider);

    _epubImageCache = imageCache;
    _autoReadController = autoReadController;
    _ttsController = ttsController;
    _platformBridge = ref.read(platformBridgeProvider);
    _lastSessionKeepScreenOn = state.keepScreenOn;

    final activeTheme = state.activeTheme;
    final bgColor = Color(activeTheme.bgColor);
    final fgColor = Color(activeTheme.textColor);
    final secondaryColor = Color(activeTheme.secondaryTextColor);
    final colorScheme = Theme.of(context).colorScheme;
    final showTtsBar =
        !state.showOverlay &&
        ttsState.status != TtsStatus.idle &&
        (ttsState.bookId == null || ttsState.bookId == widget.bookId);
    final showAutoReadBar =
        !state.showOverlay &&
        autoReadState.isActive &&
        autoReadState.showControls;

    final Widget canvasShell = Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _handleKeyEvent(event, state, controller),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildReadingFrame(
            context,
            state: state,
            controller: controller,
            ttsState: ttsState,
            autoReadState: autoReadState,
            autoReadController: autoReadController,
            imageCache: imageCache,
            bgColor: bgColor,
            fgColor: fgColor,
            secondaryColor: secondaryColor,
          ),
          if (showTtsBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ReaderTtsBar(
                state: ttsState,
                readerTheme: activeTheme,
                onTogglePlayPause: () =>
                    unawaited(ttsController.togglePlayPause()),
                onPrevSentence: () => unawaited(ttsController.prevSentence()),
                onNextSentence: () => unawaited(ttsController.nextSentence()),
                onOpenSettings: () {
                  unawaited(ttsController.refreshEnginesAndVoices());
                  unawaited(ReaderTtsSettingsSheet.show(context));
                },
                onStop: () => unawaited(ttsController.stop()),
                onJumpBack: () =>
                    unawaited(ttsController.jumpBackToSpeakingPosition()),
                onToggleCollapse: ttsController.toggleBarCollapsed,
                onSpeedTap: () {
                  unawaited(ttsController.refreshEnginesAndVoices());
                  unawaited(ReaderTtsSettingsSheet.show(context));
                },
              ),
            )
          else if (showAutoReadBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ReaderAutoReadBar(
                  state: autoReadState,
                  backgroundColor: activeTheme.isDark
                      ? Color.alphaBlend(
                          Colors.white.withAlpha(20),
                          bgColor,
                        ).withAlpha(245)
                      : Color.alphaBlend(
                          Colors.black.withAlpha(10),
                          bgColor,
                        ).withAlpha(245),
                  textColor: fgColor,
                  accentColor: colorScheme.primary,
                  borderColor: activeTheme.isDark
                      ? Colors.white.withAlpha(36)
                      : Colors.black.withAlpha(28),
                  onTogglePause: autoReadController.togglePause,
                  onModeChanged: (mode) =>
                      unawaited(autoReadController.setMode(mode)),
                  onScrollSecondsChanged: (sec) =>
                      unawaited(autoReadController.setScrollSeconds(sec)),
                  onTurnSecondsChanged: (sec) =>
                      unawaited(autoReadController.setTurnSeconds(sec)),
                  onStop: autoReadController.stop,
                ),
              ),
            ),
          if (state.showOverlay) ...[
            _buildTopOverlay(context, state, controller),
            _buildBottomOverlay(
              context,
              state,
              controller,
              ttsState: ttsState,
              autoReadState: autoReadState,
            ),
          ],
        ],
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      drawer: ReaderTocDrawer(
        bookTitle: state.book?.title ?? '目录',
        chapters: state.chapters,
        currentChapterIndex: state.currentChapterIndex,
        isReversed: state.isTocReversed,
        onToggleReverse: controller.toggleTocReversed,
        onSelectChapter: (chapterIdx) async {
          Navigator.of(context).pop();
          await controller.jumpToChapter(chapterIdx);
        },
      ),
      body: state.safeAreaEnabled
          ? SafeArea(child: canvasShell)
          : canvasShell,
    );
  }

  Widget _buildReadingFrame(
    BuildContext context, {
    required ReaderSessionState state,
    required ReaderSessionController controller,
    required TtsState ttsState,
    required AutoReadState autoReadState,
    required AutoReadController autoReadController,
    required EpubImageCache imageCache,
    required Color bgColor,
    required Color fgColor,
    required Color secondaryColor,
  }) {
    if (state.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: fgColor),
      );
    }

    if (state.errorMessage != null && state.currentPages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 42, color: secondaryColor),
              const SizedBox(height: 12),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: fgColor, fontSize: 16),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _exitReader(context, controller),
                child: const Text('返回书架'),
              ),
            ],
          ),
        ),
      );
    }

    final highlightRange = ttsState.bookId == widget.bookId
        ? ttsState.activeHighlightRange
        : null;
    final colorScheme = Theme.of(context).colorScheme;
    final ttsHighlightColor = colorScheme.primary.withAlpha(
      state.activeTheme.isDark ? 72 : 44,
    );
    final nextChapterTitle =
        (state.currentChapterIndex + 1 < state.chapters.length)
        ? state.chapters[state.currentChapterIndex + 1].title
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeaderLine(state, secondaryColor),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canvasSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              _scheduleViewportSync(canvasSize);
              final config =
                  state.paginationConfig ??
                  ReaderSessionController.resolveLayoutConfig(
                    canvasSize,
                    state.activeTheme,
                  ).config;

              return ListenableBuilder(
                listenable: imageCache,
                builder: (context, _) {
                  return ReaderPageTurnView(
                    mode: state.activeTheme.pageTurnMode,
                    columnCount: state.columnCount,
                    config: config,
                    pages: state.currentPages,
                    currentPageIndex: state.currentPageIndex,
                    currentChapterIndex: state.currentChapterIndex,
                    canGoPrev: state.canGoPrev,
                    canGoNext: state.canGoNext,
                    backgroundColor: bgColor,
                    textColor: fgColor,
                    secondaryTextColor: secondaryColor,
                    dividerColor: secondaryColor.withAlpha(46),
                    showOverlay: state.showOverlay,
                    onNextPage: controller.nextPage,
                    onPrevPage: controller.prevPage,
                    onToggleOverlay: controller.toggleOverlay,
                    onScrollOffsetChanged: controller.updateScrollAnchor,
                    epubImageCache: imageCache,
                    book: state.book,
                    ttsHighlightChapterIndex: highlightRange != null
                        ? ttsState.speakingChapterIndex
                        : null,
                    ttsHighlightStartOffset: highlightRange?.$1,
                    ttsHighlightEndOffset: highlightRange?.$2,
                    ttsHighlightColor: ttsHighlightColor,
                    onTapImage: state.book == null
                        ? null
                        : (imageRef) {
                            unawaited(
                              EpubImageViewerDialog.show(
                                context,
                                imageRef: imageRef,
                                imageCache: imageCache,
                                book: state.book!,
                              ),
                            );
                          },
                    autoReadState: autoReadState,
                    onAutoReadAdvance: () async {
                      if (!mounted) return;
                      final latest = ref.read(
                        readerSessionControllerProvider(widget.bookId),
                      );
                      if (latest.canGoNext) {
                        await controller.nextPage();
                      }
                    },
                    onAutoReadToggleControls: autoReadController.toggleControls,
                    onAutoReadReachedEnd: () {
                      autoReadController.stop();
                      if (mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(content: Text('已自动阅读至全书末尾')),
                        );
                      }
                    },
                    nextChapterTitle: nextChapterTitle,
                    autoReadAccentColor: colorScheme.primary,
                  );
                },
              );
            },
          ),
        ),
        _buildFooterLine(state, secondaryColor),
      ],
    );
  }

  Widget _buildHeaderLine(ReaderSessionState state, Color secondaryColor) {
    final horizontalPad = state.activeTheme.marginHorizontal.clamp(12.0, 48.0);
    final bookTitle = state.book?.title ?? '';
    final chapterTitle = state.currentChapterTitle;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              bookTitle.isNotEmpty && chapterTitle != bookTitle
                  ? '$bookTitle · $chapterTitle'
                  : chapterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondaryColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLine(ReaderSessionState state, Color secondaryColor) {
    final horizontalPad = state.activeTheme.marginHorizontal.clamp(12.0, 48.0);
    final totalPages = state.currentPages.length;
    final leftIdx = state.leftPage != null ? state.leftPage!.pageIndex + 1 : 0;
    final rightIdx = state.rightPage != null
        ? state.rightPage!.pageIndex + 1
        : null;
    final percentText =
        '${(state.overallProgressPercent * 100).toStringAsFixed(1)}%';
    final timeText = _formatClock(DateTime.now());

    if (state.columnCount == 2) {
      return Padding(
        padding: EdgeInsets.fromLTRB(horizontalPad, 2, horizontalPad, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                totalPages > 0 ? '第 $leftIdx / $totalPages 页' : '0/0',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: secondaryColor, fontSize: 11),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: rightIdx != null
                        ? Text(
                            '第 $rightIdx 页',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 11,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '$percentText  $timeText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: secondaryColor, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, 2, horizontalPad, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              totalPages > 0 ? '$leftIdx / $totalPages' : '0 / 0',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondaryColor, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$percentText  $timeText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondaryColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopOverlay(
    BuildContext context,
    ReaderSessionState state,
    ReaderSessionController controller,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        elevation: 4,
        color: colorScheme.surface.withAlpha(242),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回书架',
                onPressed: () => _exitReader(context, controller),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.book?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      state.currentChapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_isOnlineBook(state)) ...[
                IconButton(
                  tooltip: '换源',
                  onPressed: () =>
                      _openChangeSourceSheet(context, state, controller),
                  icon: const Icon(Icons.swap_horiz),
                ),
                PopupMenuButton<int>(
                  tooltip: '缓存章节',
                  icon: const Icon(Icons.download_outlined),
                  onSelected: (count) =>
                      _startCacheAhead(context, controller, count),
                  itemBuilder: (context) => const <PopupMenuEntry<int>>[
                    PopupMenuItem<int>(
                      value: 50,
                      child: Text('缓存后续 50 章'),
                    ),
                    PopupMenuItem<int>(
                      value: 100,
                      child: Text('缓存后续 100 章'),
                    ),
                  ],
                ),
              ],
              IconButton(
                tooltip: '书内搜索 (Ctrl+F)',
                onPressed: state.book == null
                    ? null
                    : () => _openSearchSheet(context, controller),
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: '书签',
                onPressed: () => _openBookmarksSheet(context, state, controller),
                icon: const Icon(Icons.bookmark_border),
              ),
              IconButton(
                tooltip: state.isImmersive ? '退出全屏 (F11)' : '全屏沉浸 (F11)',
                onPressed: controller.toggleImmersive,
                icon: Icon(
                  state.isImmersive
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                ),
              ),
              IconButton(
                tooltip: '老板键隐藏 (Ctrl+H)',
                onPressed: controller.triggerBossKeyHide,
                icon: const Icon(Icons.visibility_off_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay(
    BuildContext context,
    ReaderSessionState state,
    ReaderSessionController controller, {
    required TtsState ttsState,
    required AutoReadState autoReadState,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final sliderValue =
        (_pendingSeekRatio ?? state.overallProgressPercent).clamp(0.0, 1.0);
    final isTtsActiveForBook =
        ttsState.isActive && ttsState.bookId == widget.bookId;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.canUndoJump)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.tonalIcon(
                onPressed: controller.undoLastJump,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('撤回跳转'),
              ),
            ),
          Material(
            elevation: 6,
            color: colorScheme.surface.withAlpha(245),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: state.currentChapterIndex > 0
                            ? () => controller.jumpToChapter(
                                state.currentChapterIndex - 1,
                              )
                            : null,
                        child: const Text('上一章'),
                      ),
                      Expanded(
                        child: Slider(
                          value: sliderValue,
                          onChanged: (value) {
                            setState(() => _pendingSeekRatio = value);
                          },
                          onChangeEnd: (value) {
                            setState(() => _pendingSeekRatio = null);
                            unawaited(controller.jumpToProgressRatio(value));
                          },
                        ),
                      ),
                      TextButton(
                        onPressed:
                            state.currentChapterIndex + 1 < state.chapters.length
                            ? () => controller.jumpToChapter(
                                state.currentChapterIndex + 1,
                              )
                            : null,
                        child: const Text('下一章'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _OverlayActionButton(
                          icon: Icons.format_list_bulleted,
                          label: '目录',
                          onTap: () {
                            controller.setOverlayVisible(false);
                            _scaffoldKey.currentState?.openDrawer();
                          },
                        ),
                      ),
                      Expanded(
                        child: _OverlayActionButton(
                          icon: state.activeTheme.isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          label: state.activeTheme.isDark ? '日间' : '夜间',
                          onTap: controller.toggleDayNightTheme,
                        ),
                      ),
                      Expanded(
                        child: _OverlayActionButton(
                          icon: isTtsActiveForBook
                              ? Icons.headphones
                              : Icons.headphones_outlined,
                          label: '听书',
                          isSelected: isTtsActiveForBook,
                          onTap: () => unawaited(
                            _startOrResumeTts(state, controller),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _OverlayActionButton(
                          icon: autoReadState.isActive
                              ? Icons.auto_stories
                              : Icons.auto_stories_outlined,
                          label: '自动',
                          isSelected: autoReadState.isActive,
                          onTap: () => unawaited(
                            _startOrStopAutoRead(controller),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _OverlayActionButton(
                          icon: Icons.bookmark_add_outlined,
                          label: '书签',
                          onTap: () =>
                              _openBookmarksSheet(context, state, controller),
                        ),
                      ),
                      Expanded(
                        child: _OverlayActionButton(
                          icon: Icons.tune,
                          label: '设置',
                          onTap: () => _openSettingsSheet(context, controller),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(
    KeyEvent event,
    ReaderSessionState state,
    ReaderSessionController controller,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isEditableTextFocused()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;

    if (isCtrl && key == LogicalKeyboardKey.keyH) {
      unawaited(controller.triggerBossKeyHide());
      return KeyEventResult.handled;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyF) {
      if (!state.isLoading && state.book != null) {
        unawaited(_openSearchSheet(context, controller));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f11) {
      unawaited(controller.toggleImmersive());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (state.showOverlay) {
        controller.setOverlayVisible(false);
        return KeyEventResult.handled;
      }
      if (state.isImmersive) {
        unawaited(controller.setImmersive(false));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.keyT) {
      controller.setOverlayVisible(false);
      _scaffoldKey.currentState?.openDrawer();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      _openSettingsSheet(context, controller);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      final ttsState = ref.read(ttsControllerProvider);
      if (ttsState.isActive && ttsState.bookId == widget.bookId) {
        unawaited(ref.read(ttsControllerProvider.notifier).togglePlayPause());
        return KeyEventResult.handled;
      }
      final autoReadState = ref.read(autoReadControllerProvider);
      if (autoReadState.isActive) {
        ref.read(autoReadControllerProvider.notifier).togglePause();
        return KeyEventResult.handled;
      }
      unawaited(controller.nextPage());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      unawaited(controller.nextPage());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      unawaited(controller.prevPage());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isEditableTextFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<void> _exitReader(
    BuildContext context,
    ReaderSessionController controller,
  ) async {
    ref.read(autoReadControllerProvider.notifier).stop();
    await ref.read(ttsControllerProvider.notifier).stop();
    _syncAutoReadKeepScreenOn(
      autoReadRunning: false,
      sessionKeepScreenOn: _lastSessionKeepScreenOn,
    );
    await controller.flushProgress();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  TtsReaderHost _createTtsHost(ReaderSessionController sessionController) {
    return TtsReaderHost(
      loadChapterText: sessionController.readChapterTextForTts,
      navigateToPosition: sessionController.jumpToTtsAnchor,
      getChapterTitle: (chapterIndex) {
        final latest = ref.read(
          readerSessionControllerProvider(widget.bookId),
        );
        if (chapterIndex >= 0 && chapterIndex < latest.chapters.length) {
          return latest.chapters[chapterIndex].title;
        }
        return latest.book?.title ?? '';
      },
      getChapterCount: () {
        final latest = ref.read(
          readerSessionControllerProvider(widget.bookId),
        );
        return latest.chapters.length;
      },
    );
  }

  void _notifyTtsViewportIfSettled(ReaderSessionState sessionState) {
    if (sessionState.isLoading ||
        sessionState.isPaginating ||
        sessionState.currentPages.isEmpty) {
      return;
    }
    final visibleStart =
        sessionState.leftPage?.startCharOffset ?? sessionState.anchorOffset;
    final visibleEnd =
        (sessionState.rightPage ?? sessionState.leftPage)?.endCharOffset ??
        sessionState.anchorOffset;
    final loc = (
      chapterIndex: sessionState.currentChapterIndex,
      start: visibleStart,
      end: visibleEnd,
    );
    if (_lastViewportLocation == loc) return;
    _lastViewportLocation = loc;
    ref
        .read(ttsControllerProvider.notifier)
        .onViewportLocationChanged(loc.chapterIndex, loc.start, loc.end);
  }

  void _syncAutoReadKeepScreenOn({
    required bool autoReadRunning,
    required bool sessionKeepScreenOn,
  }) {
    final platform = _platformBridge;
    if (platform == null) return;
    if (autoReadRunning) {
      if (!_autoReadKeepScreenOnApplied) {
        _autoReadKeepScreenOnApplied = true;
        unawaited(platform.setKeepScreenOn(true));
      }
    } else if (_autoReadKeepScreenOnApplied) {
      _autoReadKeepScreenOnApplied = false;
      unawaited(platform.setKeepScreenOn(sessionKeepScreenOn));
    }
  }

  Future<void> _startOrResumeTts(
    ReaderSessionState sessionState,
    ReaderSessionController sessionController,
  ) async {
    sessionController.setOverlayVisible(false);
    ref.read(autoReadControllerProvider.notifier).stop();

    final ttsController = ref.read(ttsControllerProvider.notifier);
    final ttsState = ref.read(ttsControllerProvider);
    final host = _ttsHost ??= _createTtsHost(sessionController);
    ttsController.attachHost(host);

    if (ttsState.isActive && ttsState.bookId == widget.bookId) {
      if (ttsState.isBarCollapsed) {
        ttsController.setBarCollapsed(false);
      }
      if (ttsState.isPaused) {
        await ttsController.resume();
      }
      return;
    }

    final book = sessionState.book;
    if (book == null || sessionState.chapters.isEmpty) return;

    final visibleStart =
        sessionState.leftPage?.startCharOffset ?? sessionState.anchorOffset;
    final visibleEnd =
        (sessionState.rightPage ?? sessionState.leftPage)?.endCharOffset ??
        sessionState.anchorOffset;
    final chapterText = sessionState.currentChapterText.isNotEmpty
        ? sessionState.currentChapterText
        : (await sessionController.readChapterTextForTts(
                sessionState.currentChapterIndex,
              ) ??
              '');
    if (!mounted) return;

    await ttsController.start(
      bookId: widget.bookId,
      bookTitle: book.title,
      host: host,
      chapterIndex: sessionState.currentChapterIndex,
      chapterText: chapterText,
      startCharOffset: visibleStart,
      chapterTitle: sessionState.currentChapterTitle,
    );
    if (!mounted) return;
    final latestTts = ref.read(ttsControllerProvider);
    if (latestTts.isActive &&
        latestTts.speakingChapterIndex == sessionState.currentChapterIndex) {
      _lastViewportLocation = (
        chapterIndex: sessionState.currentChapterIndex,
        start: visibleStart,
        end: visibleEnd,
      );
      ttsController.onViewportLocationChanged(
        sessionState.currentChapterIndex,
        visibleStart,
        visibleEnd,
      );
    }
  }

  Future<void> _startOrStopAutoRead(
    ReaderSessionController sessionController,
  ) async {
    sessionController.setOverlayVisible(false);
    final ttsState = ref.read(ttsControllerProvider);
    if (ttsState.status != TtsStatus.idle) {
      await ref.read(ttsControllerProvider.notifier).stop();
    }
    if (!mounted) return;
    final autoReadController = ref.read(autoReadControllerProvider.notifier);
    if (ref.read(autoReadControllerProvider).isActive) {
      autoReadController.stop();
    } else {
      autoReadController.start();
    }
  }

  void _openSettingsSheet(
    BuildContext context,
    ReaderSessionController controller,
  ) {
    controller.setOverlayVisible(false);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => Consumer(
          builder: (sheetContext, sheetRef, _) {
            final latest = sheetRef.watch(
              readerSessionControllerProvider(widget.bookId),
            );
            return ReaderSettingsSheet(
              state: latest,
              onSelectTheme: controller.selectTheme,
              onUpdateTheme: controller.updateTheme,
              onImportCustomFont: controller.importCustomFont,
              onToggleKeepScreenOn: controller.toggleKeepScreenOn,
              onToggleVolumeKeyPaging: controller.toggleVolumeKeyPaging,
              onToggleSafeArea: controller.toggleSafeArea,
              onToggleImmersive: controller.toggleImmersive,
            );
          },
        ),
      ),
    );
  }

  Future<void> _openSearchSheet(
    BuildContext context,
    ReaderSessionController controller,
  ) async {
    if (_isSearchSheetOpen) return;
    _isSearchSheetOpen = true;
    controller.setOverlayVisible(false);
    try {
      await ReaderSearchSheet.show(
        context,
        bookId: widget.bookId,
        onJumpToMatch: controller.jumpToSearchAnchor,
      );
    } finally {
      _isSearchSheetOpen = false;
    }
  }

  void _openBookmarksSheet(
    BuildContext context,
    ReaderSessionState state,
    ReaderSessionController controller,
  ) {
    controller.setOverlayVisible(false);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => Consumer(
          builder: (sheetContext, sheetRef, _) {
            final latest = sheetRef.watch(
              readerSessionControllerProvider(widget.bookId),
            );
            return ReaderBookmarksSheet(
              bookmarks: latest.bookmarks,
              chapters: latest.chapters,
              onAddBookmark: (note) => controller.addBookmark(note: note),
              onSelectBookmark: controller.jumpToBookmark,
              onDeleteBookmark: controller.deleteBookmark,
            );
          },
        ),
      ),
    );
  }

  bool _isOnlineBook(ReaderSessionState state) {
    final book = state.book;
    if (book == null) return false;
    return book.providerType == ProviderType.jsPlugin ||
        book.providerType == ProviderType.legado;
  }

  Future<void> _openChangeSourceSheet(
    BuildContext context,
    ReaderSessionState state,
    ReaderSessionController controller,
  ) async {
    final book = state.book;
    if (book == null) return;
    controller.setOverlayVisible(false);
    final result = await ChangeSourceSheet.show(
      context,
      book: book,
      currentChapterIndex: state.currentChapterIndex,
      currentChapterTitle: state.currentChapterTitle,
    );
    if (!mounted || result == null) return;
    setState(() => _pendingSeekRatio = null);
    ref.read(readerSearchControllerProvider(widget.bookId).notifier).clear();
    await controller.applyChangeSourceResult(result);
  }

  Future<void> _startCacheAhead(
    BuildContext context,
    ReaderSessionController controller,
    int count,
  ) async {
    controller.setOverlayVisible(false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await controller.cacheChaptersAhead(count);
    if (!mounted || result == null) return;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '缓存完成：新增 ${result.cachedCount} 章，已缓存 ${result.skippedCachedCount} 章'
          '${result.failedCount > 0 ? '，失败 ${result.failedCount} 章' : ''}',
        ),
      ),
    );
  }

  String _formatClock(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _OverlayActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  const _OverlayActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: activeColor),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: activeColor,
                fontWeight: isSelected ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
