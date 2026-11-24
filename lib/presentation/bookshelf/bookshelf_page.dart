import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../application/bookshelf/bookshelf_controller.dart';
import '../../application/bookshelf/bookshelf_state.dart';
import '../../domain/domain.dart';

/// Adaptive PureRead bookshelf supporting list/grid toggle, sorting, pinning,
/// deletion, reading progress display, and multi-file local TXT import.
class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookshelfControllerProvider);
    final controller = ref.read(bookshelfControllerProvider.notifier);
    final theme = Theme.of(context);
    final books = state.filteredBooks;

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索书名或作者...',
                  border: InputBorder.none,
                ),
                onChanged: controller.setSearchQuery,
              )
            : Text(
                state.books.isEmpty ? '书架' : '书架 (${state.books.length})',
              ),
        actions: [
          if (state.books.isNotEmpty)
            IconButton(
              tooltip: _showSearch ? '关闭搜索' : '筛选书架',
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchController.clear();
                    controller.setSearchQuery('');
                  }
                });
              },
              icon: Icon(_showSearch ? Icons.close : Icons.search),
            ),
          IconButton(
            tooltip: state.viewMode == BookshelfViewMode.grid
                ? '切换列表视图'
                : '切换网格视图',
            onPressed: controller.toggleViewMode,
            icon: Icon(
              state.viewMode == BookshelfViewMode.grid
                  ? Icons.view_list_outlined
                  : Icons.grid_view_outlined,
            ),
          ),
          PopupMenuButton<BookshelfSortMode>(
            tooltip: '排序方式',
            icon: const Icon(Icons.sort),
            initialValue: state.sortMode,
            onSelected: controller.setSortMode,
            itemBuilder: (context) => [
              _buildSortMenuItem(
                mode: BookshelfSortMode.recentRead,
                label: '最近阅读',
                current: state.sortMode,
              ),
              _buildSortMenuItem(
                mode: BookshelfSortMode.updatedAt,
                label: '更新时间',
                current: state.sortMode,
              ),
              _buildSortMenuItem(
                mode: BookshelfSortMode.title,
                label: '书名',
                current: state.sortMode,
              ),
            ],
          ),
          MediaQuery.sizeOf(context).width >= 600
              ? Tooltip(
                  message: '检查更新',
                  child: TextButton.icon(
                    onPressed: state.isCheckingUpdates
                        ? null
                        : controller.checkUpdates,
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('检查更新'),
                  ),
                )
              : IconButton(
                  tooltip: '检查更新',
                  onPressed: state.isCheckingUpdates
                      ? null
                      : controller.checkUpdates,
                  icon: const Icon(Icons.sync),
                ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MediaQuery.sizeOf(context).width >= 520
                ? FilledButton.tonalIcon(
                    onPressed: state.isImporting
                        ? null
                        : controller.importLocalTxtFiles,
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: const Text('导入 TXT'),
                  )
                : IconButton(
                    tooltip: '导入 TXT',
                    onPressed: state.isImporting
                        ? null
                        : controller.importLocalTxtFiles,
                    icon: const Icon(Icons.file_upload_outlined),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.isCheckingUpdates)
            const LinearProgressIndicator(minHeight: 2),
          if (state.isImporting)
            _ImportProgressBar(
              done: state.importDoneCount,
              total: state.importTotalCount,
            ),
          if (state.errorMessage != null ||
              state.importStatusMessage != null ||
              state.updateStatusMessage != null)
            _StatusBanner(
              errorMessage: state.errorMessage,
              statusMessage:
                  state.updateStatusMessage ?? state.importStatusMessage,
              onDismiss: controller.clearBanner,
            ),
          Expanded(
            child: _buildBody(context, theme, state, books, controller),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<BookshelfSortMode> _buildSortMenuItem({
    required BookshelfSortMode mode,
    required String label,
    required BookshelfSortMode current,
  }) {
    final selected = mode == current;
    return PopupMenuItem<BookshelfSortMode>(
      value: mode,
      child: Row(
        children: [
          Icon(
            selected ? Icons.check : Icons.circle_outlined,
            size: 16,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    BookshelfState state,
    List<Book> books,
    BookshelfController controller,
  ) {
    if (state.isLoading && state.books.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.books.isEmpty) {
      return _BookshelfEmptyView(
        onImportTxt: state.isImporting ? null : controller.importLocalTxtFiles,
        onPreviewReader: () => _openReader(context, 'demo'),
      );
    }

    if (books.isEmpty) {
      return Center(
        child: Text(
          '未找到匹配“${state.searchQuery}”的书籍',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (state.viewMode == BookshelfViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.60,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          final progress = state.progressByBookId[book.id];
          return _BookGridCard(
            book: book,
            progress: progress,
            onOpen: () => _openReader(context, book.id),
            onTogglePin: () => controller.togglePin(book.id),
            onDelete: () => _confirmDelete(context, book, controller),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: books.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final book = books[index];
        final progress = state.progressByBookId[book.id];
        return _BookListTile(
          book: book,
          progress: progress,
          onOpen: () => _openReader(context, book.id),
          onTogglePin: () => controller.togglePin(book.id),
          onDelete: () => _confirmDelete(context, book, controller),
        );
      },
    );
  }

  Future<void> _openReader(BuildContext context, String bookId) async {
    await context.push(AppRoutes.readerForBook(bookId));
    if (mounted) {
      await ref.read(bookshelfControllerProvider.notifier).refresh();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Book book,
    BookshelfController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除书籍'),
        content: Text('确定从书架移除《${book.title}》吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteBook(book.id);
    }
  }
}

class _ImportProgressBar extends StatelessWidget {
  final int done;
  final int total;

  const _ImportProgressBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? done / total : null;
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(140),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '正在导入本地 TXT ($done / $total)...',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: ratio),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String? errorMessage;
  final String? statusMessage;
  final VoidCallback onDismiss;

  const _StatusBanner({
    this.errorMessage,
    this.statusMessage,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isError = errorMessage != null && errorMessage!.isNotEmpty;
    final theme = Theme.of(context);
    final bgColor = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final fgColor = isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;
    final text = isError ? errorMessage! : (statusMessage ?? '');

    return Material(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: fgColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: fgColor),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: fgColor, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookshelfEmptyView extends StatelessWidget {
  final VoidCallback? onImportTxt;
  final VoidCallback onPreviewReader;

  const _BookshelfEmptyView({
    required this.onImportTxt,
    required this.onPreviewReader,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(140),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '书架暂无书籍',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'PureRead 净读支持导入本地 UTF-8 / GB18030 / UTF-16 TXT 小说，支持精准 charOffset 锚点与考究中文排版。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onImportTxt,
                    icon: const Icon(Icons.add),
                    label: const Text('导入本地 TXT'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPreviewReader,
                    icon: const Icon(Icons.chrome_reader_mode_outlined),
                    label: const Text('预览阅读器占位页'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookGridCard extends StatelessWidget {
  final Book book;
  final ReadingProgress? progress;
  final VoidCallback onOpen;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  const _BookGridCard({
    required this.book,
    required this.progress,
    required this.onOpen,
    required this.onTogglePin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress?.progressPercent ?? 0.0).clamp(0.0, 1.0);
    final chapterLabel = _chapterSubtitle(book, progress);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _BookCoverArt(book: book),
                  if (book.isPinned)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.push_pin,
                              size: 12,
                              color: theme.colorScheme.onPrimary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '置顶',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (book.unreadCount > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Badge(label: Text('${book.unreadCount}')),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _BookActionMenu(
                        isPinned: book.isPinned,
                        onTogglePin: onTogglePin,
                        onDelete: onDelete,
                      ),
                    ],
                  ),
                  Text(
                    chapterLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: percent,
                            minHeight: 3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        progress == null
                            ? '未读'
                            : '${(percent * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookListTile extends StatelessWidget {
  final Book book;
  final ReadingProgress? progress;
  final VoidCallback onOpen;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  const _BookListTile({
    required this.book,
    required this.progress,
    required this.onOpen,
    required this.onTogglePin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress?.progressPercent ?? 0.0).clamp(0.0, 1.0);
    final subtitleText = _chapterSubtitle(book, progress);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      onTap: onOpen,
      leading: SizedBox(
        width: 48,
        height: 68,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _BookCoverArt(book: book, compact: true),
        ),
      ),
      title: Row(
        children: [
          if (book.isPinned) ...[
            Icon(Icons.push_pin, size: 15, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (book.unreadCount > 0) ...[
            const SizedBox(width: 8),
            Badge(label: Text('${book.unreadCount}')),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            book.author.isEmpty ? subtitleText : '${book.author} · $subtitleText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            progress == null
                ? '尚未开始阅读 · 共 ${book.totalChapters} 章'
                : '已读 ${(percent * 100).toStringAsFixed(1)}% · 共 ${book.totalChapters} 章',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: book.isPinned ? '取消置顶' : '置顶',
            onPressed: onTogglePin,
            icon: Icon(
              book.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: '删除书籍',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

class _BookActionMenu extends StatelessWidget {
  final bool isPinned;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  const _BookActionMenu({
    required this.isPinned,
    required this.onTogglePin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 18,
      onSelected: (value) {
        if (value == 'pin') {
          onTogglePin();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'pin',
          child: Text(isPinned ? '取消置顶' : '置顶书籍'),
        ),
        const PopupMenuItem<String>(value: 'delete', child: Text('删除书籍')),
      ],
    );
  }
}

class _BookCoverArt extends StatelessWidget {
  final Book book;
  final bool compact;

  const _BookCoverArt({required this.book, this.compact = false});

  @override
  Widget build(BuildContext context) {
    const palettes = <(Color, Color)>[
      (Color(0xFF4A6B53), Color(0xFF2D4433)),
      (Color(0xFF5D534A), Color(0xFF39322C)),
      (Color(0xFF3E5A70), Color(0xFF233645)),
      (Color(0xFF6B4C57), Color(0xFF422D35)),
      (Color(0xFF5C6B42), Color(0xFF384227)),
    ];
    final idx = book.title.hashCode.abs() % palettes.length;
    final (topColor, bottomColor) = palettes[idx];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [topColor, bottomColor],
        ),
      ),
      padding: EdgeInsets.all(compact ? 4 : 12),
      child: compact
          ? Center(
              child: Text(
                book.title.isEmpty ? '书' : book.title.substring(0, 1),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  book.providerType == ProviderType.localTxt ? 'TXT' : 'BOOK',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  book.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                Text(
                  book.author.isEmpty
                      ? (book.providerType == ProviderType.localTxt
                            ? '本地导入'
                            : '在线书籍')
                      : book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
    );
  }
}

String _chapterSubtitle(Book book, ReadingProgress? progress) {
  if (progress != null && progress.chapterTitleSnapshot.isNotEmpty) {
    return progress.chapterTitleSnapshot;
  }
  if (book.lastChapterTitle.isNotEmpty) {
    return book.lastChapterTitle;
  }
  if (book.totalChapters > 0) {
    return '共 ${book.totalChapters} 章';
  }
  return book.author.isEmpty ? '本地文本' : book.author;
}
