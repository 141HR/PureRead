import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/reader/epub_image_cache.dart';
import '../../domain/domain.dart';
import '../../engine/reader_engine/inline_image_marker.dart';

/// Fullscreen dark-backdrop modal viewer for inline EPUB illustrations with
/// pinch-to-zoom (`1.0x..5.0x`), double-tap zoom toggle, caption, and Esc/tap close.
class EpubImageViewerDialog extends StatefulWidget {
  const EpubImageViewerDialog({
    super.key,
    required this.imageRef,
    required this.imageCache,
    required this.book,
  });

  final InlineImageRef imageRef;
  final EpubImageCache imageCache;
  final Book book;

  /// Presents [EpubImageViewerDialog] as a fullscreen modal dialog.
  static Future<void> show(
    BuildContext context, {
    required InlineImageRef imageRef,
    required EpubImageCache imageCache,
    required Book book,
  }) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black87,
      builder: (_) => EpubImageViewerDialog(
        imageRef: imageRef,
        imageCache: imageCache,
        book: book,
      ),
    );
  }

  @override
  State<EpubImageViewerDialog> createState() => _EpubImageViewerDialogState();
}

class _EpubImageViewerDialogState extends State<EpubImageViewerDialog> {
  final TransformationController _transformationController =
      TransformationController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'EpubImageViewerFocus');

  ui.Image? _displayImage;
  Offset? _doubleTapLocalPosition;
  bool _hasFailed = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant EpubImageViewerDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageRef != widget.imageRef ||
        oldWidget.book.id != widget.book.id ||
        !identical(oldWidget.imageCache, widget.imageCache)) {
      _transformationController.value = Matrix4.identity();
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _displayImage?.dispose();
    _displayImage = null;
    _transformationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _resolveImage() {
    final cached = widget.imageCache.getCached(
      widget.book.id,
      widget.imageRef.archivePath,
    );
    if (cached != null) {
      _displayImage?.dispose();
      _displayImage = cached.clone();
      _hasFailed = false;
      return;
    }

    if (widget.imageCache.isFailed(
      widget.book.id,
      widget.imageRef.archivePath,
    )) {
      _displayImage?.dispose();
      _displayImage = null;
      _hasFailed = true;
      return;
    }

    _displayImage?.dispose();
    _displayImage = null;
    _hasFailed = false;

    unawaited(
      widget.imageCache
          .loadImage(widget.book, widget.imageRef.archivePath)
          .then((loaded) {
            if (!mounted) return;
            setState(() {
              if (loaded != null) {
                _displayImage?.dispose();
                _displayImage = loaded.clone();
                _hasFailed = false;
              } else {
                _hasFailed = true;
              }
            });
          }),
    );
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _transformationController.value = Matrix4.identity();
      return;
    }
    const targetScale = 2.5;
    final pos = _doubleTapLocalPosition ?? Offset.zero;
    _transformationController.value = Matrix4(
      targetScale,
      0.0,
      0.0,
      0.0,
      0.0,
      targetScale,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
      -pos.dx * (targetScale - 1.0),
      -pos.dy * (targetScale - 1.0),
      0.0,
      1.0,
    );
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.imageRef.alt.trim();
    final image = _displayImage;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: Material(
        color: Colors.black.withAlpha(240),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: (details) =>
                      _doubleTapLocalPosition = details.localPosition,
                  onDoubleTap: _handleDoubleTap,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 5.0,
                    boundaryMargin: const EdgeInsets.all(48),
                    child: Center(
                      child: image != null
                          ? RawImage(
                              image: image,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                            )
                          : _hasFailed
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white54,
                                  size: 48,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  '图片加载失败',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            )
                          : const CircularProgressIndicator(
                              color: Colors.white70,
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
              if (caption.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(170),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          caption,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
