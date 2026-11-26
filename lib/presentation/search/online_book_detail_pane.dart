import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/search/book_detail_controller.dart';
import '../../application/search/book_detail_state.dart';
import 'change_source_sheet.dart';

/// Reusable right/detail pane for inspecting an online book, switching active
/// sources, saving to bookshelf, launching the reader, and previewing TOC.
class OnlineBookDetailPane extends ConsumerWidget {
  /// Optional provider override so callers (e.g. SearchPage vs ExplorePage)
  /// can isolate detail state in separate [BookDetailController] instances.
  final NotifierProvider<BookDetailController, BookDetailState>? detailProvider;

  /// Callback invoked when the user starts reading or taps a TOC chapter.
  final Future<void> Function({int? initialChapterIndex}) onOpenReader;

  /// Placeholder text displayed when no book is currently selected.
  final String emptyPlaceholderText;

  const OnlineBookDetailPane({
    super.key,
    this.detailProvider,
    required this.onOpenReader,
    this.emptyPlaceholderText = '选择左侧书籍查看详情与目录预览',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = detailProvider ?? bookDetailControllerProvider;
    final state = ref.watch(provider);
    final theme = Theme.of(context);
    final book = state.aggregatedBook;
    if (book == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyPlaceholderText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final controller = ref.read(provider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeaderSection(context, ref, theme, provider, controller, state),
        if (state.statusMessage != null)
          _DetailBanner(
            message: state.statusMessage!,
            backgroundColor: theme.colorScheme.secondaryContainer,
            foregroundColor: theme.colorScheme.onSecondaryContainer,
          ),
        if (state.errorMessage != null)
          _DetailBanner(
            message: state.errorMessage!,
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
          ),
        const Divider(height: 1),
        _buildTocHeader(theme, state),
        Expanded(child: _buildTocList(theme, state)),
      ],
    );
  }

  Widget _buildHeaderSection(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    NotifierProvider<BookDetailController, BookDetailState> provider,
    BookDetailController controller,
    BookDetailState state,
  ) {
    final book = state.aggregatedBook!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnlineBookCover(
                title: state.displayTitle,
                coverUrl: state.displayCoverUrl,
                large: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.displayAuthor.isEmpty
                          ? '未知作者'
                          : '作者：${state.displayAuthor}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (state.detail?.latestChapterTitle.isNotEmpty ??
                        false) ...[
                      const SizedBox(height: 4),
                      Text(
                        '最新章节：${state.detail!.latestChapterTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (state.displayIntro.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              state.displayIntro,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < book.sources.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(book.sources[i].sourceName),
                      selected: state.selectedSourceIndex == i,
                      onSelected: (_) {
                        unawaited(controller.selectSourceIndex(i));
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: state.isSavingToShelf
                    ? null
                    : () => unawaited(controller.addToBookshelf()),
                icon: Icon(
                  state.isOnBookshelf
                      ? Icons.bookmark_added
                      : Icons.bookmark_add_outlined,
                  size: 18,
                ),
                label: Text(state.isOnBookshelf ? '已在书架' : '加入书架'),
              ),
              FilledButton.icon(
                onPressed: state.isSavingToShelf
                    ? null
                    : () => unawaited(onOpenReader()),
                icon: const Icon(Icons.menu_book, size: 18),
                label: Text(state.isOnBookshelf ? '继续阅读' : '开始阅读'),
              ),
              if (state.existingBookshelfBook != null)
                OutlinedButton.icon(
                  onPressed: () => unawaited(
                    _openChangeSourceSheet(context, ref, provider, state),
                  ),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('换源对比'),
                ),
              IconButton(
                tooltip: '刷新详情与目录',
                onPressed: () => unawaited(controller.reload()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openChangeSourceSheet(
    BuildContext context,
    WidgetRef ref,
    NotifierProvider<BookDetailController, BookDetailState> provider,
    BookDetailState state,
  ) async {
    final currentBook = state.existingBookshelfBook;
    if (currentBook == null) return;
    final result = await ChangeSourceSheet.show(
      context,
      book: currentBook,
      currentChapterIndex: 0,
      currentChapterTitle: state.chapters.isNotEmpty
          ? state.chapters.first.title
          : currentBook.lastChapterTitle,
    );
    if (result != null && context.mounted) {
      await ref.read(provider.notifier).reload();
    }
  }

  Widget _buildTocHeader(ThemeData theme, BookDetailState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Text(
            '目录预览 (${state.chapters.length} 章)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (state.isLoadingDetail || state.isLoadingToc) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTocList(ThemeData theme, BookDetailState state) {
    if (state.chapters.isEmpty) {
      return Center(
        child: Text(
          state.isLoadingToc ? '正在加载章节目录...' : '暂无章节预览',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: state.chapters.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final chapter = state.chapters[index];
        return ListTile(
          dense: true,
          title: Text(
            chapter.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            '第 ${index + 1} 章',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => unawaited(onOpenReader(initialChapterIndex: index)),
        );
      },
    );
  }
}

class _DetailBanner extends StatelessWidget {
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;

  const _DetailBanner({
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: foregroundColor),
        ),
      ),
    );
  }
}

/// Book cover thumbnail for online search and explore results, rendering an
/// HTTP/HTTPS [coverUrl] when valid and seamlessly falling back to a gradient
/// monogram cover on missing, invalid, or failed image loads.
class OnlineBookCover extends StatelessWidget {
  final String title;
  final String? coverUrl;
  final bool large;

  const OnlineBookCover({
    super.key,
    required this.title,
    this.coverUrl,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = large ? 72.0 : 52.0;
    final height = large ? 96.0 : 70.0;
    final fallback = _buildFallbackCover(width: width, height: height);
    final validUrl = _validHttpUrl(coverUrl);
    if (validUrl == null) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          validUrl,
          width: width,
          height: height,
          fit: BoxFit.cover,
          // Show monogram cover while loading and whenever network/decode fails
          // so offline environments and widget tests never surface image errors.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            return fallback;
          },
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }

  Widget _buildFallbackCover({required double width, required double height}) {
    final trimmedTitle = title.trim();
    final firstChar = trimmedTitle.isEmpty
        ? '书'
        : String.fromCharCode(trimmedTitle.runes.first);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF4A6B53), Color(0xFF2D4433)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        firstChar,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: large ? 24 : 18,
        ),
      ),
    );
  }

  static String? _validHttpUrl(String? rawUrl) {
    final trimmed = rawUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (!uri.hasAuthority || uri.host.trim().isEmpty) return null;
    return uri.toString();
  }
}
