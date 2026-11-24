import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/reader/reader_session_controller.dart';
import '../../application/reader/reader_session_state.dart';
import 'reader_bookmarks_sheet.dart';
import 'reader_page_turn_view.dart';
import 'reader_settings_sheet.dart';
import 'reader_toc_drawer.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final state = ref.watch(readerSessionControllerProvider(widget.bookId));
    final controller = ref.read(
      readerSessionControllerProvider(widget.bookId).notifier,
    );
    final activeTheme = state.activeTheme;
    final bgColor = Color(activeTheme.bgColor);
    final fgColor = Color(activeTheme.textColor);
    final secondaryColor = Color(activeTheme.secondaryTextColor);

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
            bgColor: bgColor,
            fgColor: fgColor,
            secondaryColor: secondaryColor,
          ),
          if (state.showOverlay) ...[
            _buildTopOverlay(context, state, controller),
            _buildBottomOverlay(context, state, controller),
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
                showOverlay: state.showOverlay,
                onNextPage: controller.nextPage,
                onPrevPage: controller.prevPage,
                onToggleOverlay: controller.toggleOverlay,
                onScrollOffsetChanged: controller.updateScrollAnchor,
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
          if (state.isDemoPreview) ...[
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                bookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: secondaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              state.isDemoPreview
                  ? chapterTitle
                  : (bookTitle.isNotEmpty && chapterTitle != bookTitle
                        ? '$bookTitle · $chapterTitle'
                        : chapterTitle),
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
              child: Row(
                children: [
                  if (state.isDemoPreview) ...[
                    Flexible(
                      child: Text(
                        '左栏逻辑页 P(2k)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      totalPages > 0 ? '第 $leftIdx / $totalPages 页' : '0/0',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondaryColor, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (state.isDemoPreview) ...[
                          Flexible(
                            child: Text(
                              '右栏逻辑页 P(2k+1)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: secondaryColor,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (rightIdx != null)
                          Flexible(
                            child: Text(
                              '第 $rightIdx 页',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: secondaryColor,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
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
    ReaderSessionController controller,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final sliderValue =
        (_pendingSeekRatio ?? state.overallProgressPercent).clamp(0.0, 1.0);

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
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _OverlayActionButton(
                        icon: Icons.format_list_bulleted,
                        label: '目录',
                        onTap: () {
                          controller.setOverlayVisible(false);
                          _scaffoldKey.currentState?.openDrawer();
                        },
                      ),
                      _OverlayActionButton(
                        icon: state.activeTheme.isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        label: state.activeTheme.isDark ? '日间' : '夜间',
                        onTap: controller.toggleDayNightTheme,
                      ),
                      _OverlayActionButton(
                        icon: Icons.bookmark_add_outlined,
                        label: '书签',
                        onTap: () =>
                            _openBookmarksSheet(context, state, controller),
                      ),
                      _OverlayActionButton(
                        icon: Icons.tune,
                        label: '设置',
                        onTap: () => _openSettingsSheet(context, controller),
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
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space ||
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
    await controller.flushProgress();
    if (context.mounted) {
      Navigator.of(context).pop();
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
              isDemoPreview: latest.isDemoPreview,
              onAddBookmark: (note) => controller.addBookmark(note: note),
              onSelectBookmark: controller.jumpToBookmark,
              onDeleteBookmark: controller.deleteBookmark,
            );
          },
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

  const _OverlayActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
