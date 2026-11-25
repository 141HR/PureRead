import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../application/bookshelf/bookshelf_controller.dart';
import '../../application/bookshelf/bookshelf_state.dart';
import '../../application/bookshelf/local_epub_providers.dart';
import '../../domain/domain.dart';

/// Adaptive PureRead bookshelf supporting list/grid toggle, sorting, F1.3
/// custom group filtering & management, pinning, single/batch deletion with
/// optional chapter cache cleanup, cover art rendering, and unified local
/// TXT / EPUB import.
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
      appBar: state.isSelectionMode
          ? _buildSelectionAppBar(context, state, controller)
          : _buildDefaultAppBar(context, state, controller),
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
          if (state.books.isNotEmpty || state.groups.isNotEmpty)
            _GroupFilterBar(
              state: state,
              onSelectGroup: controller.selectGroup,
              onCreateGroup: () => _showCreateGroupDialog(context, controller),
              onManageGroups: () =>
                  _showManageGroupsDialog(context, controller),
              onToggleSelectionMode: state.books.isNotEmpty
                  ? controller.toggleSelectionMode
                  : null,
            ),
          Expanded(
            child: _buildBody(context, theme, state, books, controller),
          ),
        ],
      ),
    );
  }

  AppBar _buildDefaultAppBar(
    BuildContext context,
    BookshelfState state,
    BookshelfController controller,
  ) {
    return AppBar(
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
                      : controller.importLocalBookFiles,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('导入 TXT / EPUB'),
                )
              : IconButton(
                  tooltip: '导入 TXT / EPUB',
                  onPressed: state.isImporting
                      ? null
                      : controller.importLocalBookFiles,
                  icon: const Icon(Icons.file_upload_outlined),
                ),
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar(
    BuildContext context,
    BookshelfState state,
    BookshelfController controller,
  ) {
    final selectedBooks = state.books
        .where((b) => state.selectedBookIds.contains(b.id))
        .toList(growable: false);
    return AppBar(
      leading: IconButton(
        tooltip: '退出批量管理',
        onPressed: controller.clearSelection,
        icon: const Icon(Icons.close),
      ),
      title: Text('已选择 ${state.selectedBookIds.length} 本'),
      actions: [
        IconButton(
          tooltip: '全选',
          onPressed: controller.selectAllVisible,
          icon: const Icon(Icons.select_all),
        ),
        IconButton(
          tooltip: '批量移动分组',
          onPressed: selectedBooks.isEmpty
              ? null
              : () => _showMoveBooksToGroupDialog(
                    context,
                    controller,
                    state.groups,
                    selectedBooks.map((b) => b.id),
                  ),
          icon: const Icon(Icons.drive_file_move_outlined),
        ),
        IconButton(
          tooltip: '批量移除书籍',
          onPressed: selectedBooks.isEmpty
              ? null
              : () => _confirmDeleteBooks(context, selectedBooks, controller),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
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
        onImportBooks:
            state.isImporting ? null : controller.importLocalBookFiles,
      );
    }

    if (books.isEmpty) {
      final hasQuery = state.searchQuery.trim().isNotEmpty;
      return Center(
        child: Text(
          hasQuery ? '未找到匹配“${state.searchQuery}”的书籍' : '该分组暂无书籍',
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
          final isSelected = state.selectedBookIds.contains(book.id);
          return _BookGridCard(
            book: book,
            progress: progress,
            isSelectionMode: state.isSelectionMode,
            isSelected: isSelected,
            onOpen: state.isSelectionMode
                ? () => controller.toggleBookSelection(book.id)
                : () => _openReader(context, book.id),
            onLongPress: () => controller.toggleBookSelection(book.id),
            onTogglePin: () => controller.togglePin(book.id),
            onMoveToGroup: () => _showMoveBooksToGroupDialog(
              context,
              controller,
              state.groups,
              <String>[book.id],
              currentGroupId: book.groupId,
            ),
            onDelete: () =>
                _confirmDeleteBooks(context, <Book>[book], controller),
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
        final isSelected = state.selectedBookIds.contains(book.id);
        return _BookListTile(
          book: book,
          progress: progress,
          isSelectionMode: state.isSelectionMode,
          isSelected: isSelected,
          onOpen: state.isSelectionMode
              ? () => controller.toggleBookSelection(book.id)
              : () => _openReader(context, book.id),
          onLongPress: () => controller.toggleBookSelection(book.id),
          onTogglePin: () => controller.togglePin(book.id),
          onMoveToGroup: () => _showMoveBooksToGroupDialog(
            context,
            controller,
            state.groups,
            <String>[book.id],
            currentGroupId: book.groupId,
          ),
          onDelete: () =>
              _confirmDeleteBooks(context, <Book>[book], controller),
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

  Future<void> _confirmDeleteBooks(
    BuildContext context,
    List<Book> books,
    BookshelfController controller,
  ) async {
    if (books.isEmpty) return;
    var deleteCachedChapters = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final prompt = books.length == 1
              ? '确定从书架移除《${books.single.title}》吗？'
              : '确定从书架移除选中的 ${books.length} 本书籍吗？';
          return AlertDialog(
            title: const Text('移除书籍'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prompt),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: deleteCachedChapters,
                  onChanged: (value) {
                    setDialogState(() {
                      deleteCachedChapters = value ?? false;
                    });
                  },
                  title: const Text('同时清理已缓存章节'),
                  subtitle: const Text('仅清理本地缓存文本，不影响本地原文件'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
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
          );
        },
      ),
    );
    if (confirmed == true) {
      await controller.deleteBooks(
        books.map((b) => b.id),
        deleteCachedChapters: deleteCachedChapters,
      );
    }
  }

  Future<BookGroup?> _showCreateGroupDialog(
    BuildContext context,
    BookshelfController controller,
  ) async {
    final groupName = await showDialog<String>(
      context: context,
      builder: (_) => const _GroupNameDialog(
        title: '新建分组',
        confirmLabel: '创建',
        hintText: '例如：追更中、完本、EPUB',
      ),
    );
    if (groupName == null || groupName.isEmpty) return null;
    return controller.createGroup(groupName);
  }

  Future<void> _showRenameGroupDialog(
    BuildContext context,
    BookshelfController controller,
    BookGroup group,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _GroupNameDialog(
        title: '重命名分组',
        confirmLabel: '保存',
        initialName: group.name,
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await controller.renameGroup(group.id, newName);
  }

  Future<void> _confirmDeleteGroup(
    BuildContext context,
    BookshelfController controller,
    BookGroup group,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('确定删除分组“${group.name}”吗？该分组下的书籍将保留并转为未分组。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteGroup(group.id);
    }
  }

  Future<void> _showManageGroupsDialog(
    BuildContext context,
    BookshelfController controller,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, dialogRef, _) {
          final latest = dialogRef.watch(bookshelfControllerProvider);
          return AlertDialog(
            title: const Text('管理分组'),
            content: SizedBox(
              width: 360,
              child: latest.groups.isEmpty
                  ? const Text('暂无自定义分组，点击下方按钮新建。')
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final group in latest.groups)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    group.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '重命名分组',
                                  onPressed: () => _showRenameGroupDialog(
                                    context,
                                    controller,
                                    group,
                                  ),
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                ),
                                IconButton(
                                  tooltip: '删除分组',
                                  onPressed: () => _confirmDeleteGroup(
                                    context,
                                    controller,
                                    group,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => _showCreateGroupDialog(context, controller),
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('新建分组'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMoveBooksToGroupDialog(
    BuildContext context,
    BookshelfController controller,
    List<BookGroup> groups,
    Iterable<String> bookIds, {
    String? currentGroupId,
  }) async {
    final ids = bookIds.toList(growable: false);
    if (ids.isEmpty) return;

    final result = await showDialog<_MoveGroupChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移动到分组'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => Navigator.of(
                    dialogContext,
                  ).pop(const _MoveGroupChoice(groupId: null)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          currentGroupId == null
                              ? Icons.check
                              : Icons.folder_off_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('未分组')),
                      ],
                    ),
                  ),
                ),
                for (final group in groups)
                  InkWell(
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(_MoveGroupChoice(groupId: group.id)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            currentGroupId == group.id
                                ? Icons.check
                                : Icons.folder_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 16),
                InkWell(
                  onTap: () => Navigator.of(
                    dialogContext,
                  ).pop(const _MoveGroupChoice(createNew: true)),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.create_new_folder_outlined, size: 18),
                        SizedBox(width: 12),
                        Expanded(child: Text('新建分组并移入')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (result == null || !context.mounted) return;
    if (result.createNew) {
      final created = await _showCreateGroupDialog(context, controller);
      if (created != null) {
        await controller.moveBooksToGroup(ids, created.id);
      }
      return;
    }
    await controller.moveBooksToGroup(ids, result.groupId);
  }
}

class _MoveGroupChoice {
  final String? groupId;
  final bool createNew;

  const _MoveGroupChoice({this.groupId, this.createNew = false});
}

class _GroupNameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String initialName;
  final String? hintText;

  const _GroupNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialName = '',
    this.hintText,
  });

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '分组名称',
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _GroupFilterBar extends StatelessWidget {
  final BookshelfState state;
  final ValueChanged<String?> onSelectGroup;
  final VoidCallback onCreateGroup;
  final VoidCallback onManageGroups;
  final VoidCallback? onToggleSelectionMode;

  const _GroupFilterBar({
    required this.state,
    required this.onSelectGroup,
    required this.onCreateGroup,
    required this.onManageGroups,
    this.onToggleSelectionMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(120),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: state.selectedGroupId == null,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => onSelectGroup(null),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('未分组'),
                      selected:
                          state.selectedGroupId == kUngroupedBookGroupFilterId,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          onSelectGroup(kUngroupedBookGroupFilterId),
                    ),
                    for (final group in state.groups) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(group.name),
                        selected: state.selectedGroupId == group.id,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => onSelectGroup(group.id),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '新建分组',
              onPressed: onCreateGroup,
              icon: const Icon(Icons.create_new_folder_outlined, size: 20),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: '管理分组',
              onPressed: onManageGroups,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
              visualDensity: VisualDensity.compact,
            ),
            if (onToggleSelectionMode != null)
              IconButton(
                tooltip: state.isSelectionMode ? '退出批量管理' : '批量管理',
                onPressed: onToggleSelectionMode,
                icon: Icon(
                  state.isSelectionMode
                      ? Icons.checklist_rtl
                      : Icons.checklist_outlined,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
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
              '正在导入本地书籍 ($done / $total)...',
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
  final VoidCallback? onImportBooks;

  const _BookshelfEmptyView({
    required this.onImportBooks,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
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
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onImportBooks,
                    icon: const Icon(Icons.add),
                    label: const Text('导入本地 TXT'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onImportBooks,
                    icon: const Icon(Icons.book_outlined),
                    label: const Text('导入 EPUB'),
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
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onTogglePin;
  final VoidCallback onMoveToGroup;
  final VoidCallback onDelete;

  const _BookGridCard({
    required this.book,
    required this.progress,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onOpen,
    required this.onLongPress,
    required this.onTogglePin,
    required this.onMoveToGroup,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
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
                  if (book.unreadCount > 0 && !isSelectionMode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Badge(label: Text('${book.unreadCount}')),
                    ),
                  if (isSelectionMode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: isSelected
                            ? theme.colorScheme.primary
                            : Colors.black54,
                        child: Icon(
                          isSelected ? Icons.check : Icons.circle_outlined,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
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
                      if (!isSelectionMode)
                        _BookActionMenu(
                          isPinned: book.isPinned,
                          onTogglePin: onTogglePin,
                          onMoveToGroup: onMoveToGroup,
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
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onTogglePin;
  final VoidCallback onMoveToGroup;
  final VoidCallback onDelete;

  const _BookListTile({
    required this.book,
    required this.progress,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onOpen,
    required this.onLongPress,
    required this.onTogglePin,
    required this.onMoveToGroup,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress?.progressPercent ?? 0.0).clamp(0.0, 1.0);
    final subtitleText = _chapterSubtitle(book, progress);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      selected: isSelected,
      onTap: onOpen,
      onLongPress: onLongPress,
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
          if (book.unreadCount > 0 && !isSelectionMode) ...[
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
      trailing: isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onOpen(),
            )
          : Row(
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
                  tooltip: '移动到分组',
                  onPressed: onMoveToGroup,
                  icon: const Icon(Icons.drive_file_move_outlined, size: 20),
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
  final VoidCallback onMoveToGroup;
  final VoidCallback onDelete;

  const _BookActionMenu({
    required this.isPinned,
    required this.onTogglePin,
    required this.onMoveToGroup,
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
        } else if (value == 'move_group') {
          onMoveToGroup();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'pin',
          child: Text(isPinned ? '取消置顶' : '置顶书籍'),
        ),
        const PopupMenuItem<String>(
          value: 'move_group',
          child: Text('移动到分组'),
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
    final coverProvider = resolveLocalCoverImageProvider(book.coverPath);
    final placeholder = _buildPlaceholder();
    if (coverProvider == null) {
      return placeholder;
    }
    return Image(
      image: coverProvider,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }

  Widget _buildPlaceholder() {
    const palettes = <(Color, Color)>[
      (Color(0xFF4A6B53), Color(0xFF2D4433)),
      (Color(0xFF5D534A), Color(0xFF39322C)),
      (Color(0xFF3E5A70), Color(0xFF233645)),
      (Color(0xFF6B4C57), Color(0xFF422D35)),
      (Color(0xFF5C6B42), Color(0xFF384227)),
    ];
    final idx = book.title.hashCode.abs() % palettes.length;
    final (topColor, bottomColor) = palettes[idx];

    final typeTag = switch (book.providerType) {
      ProviderType.localTxt => 'TXT',
      ProviderType.localEpub => 'EPUB',
      ProviderType.jsPlugin || ProviderType.legado => 'BOOK',
    };
    final fallbackAuthor = switch (book.providerType) {
      ProviderType.localTxt => '本地导入',
      ProviderType.localEpub => '本地 EPUB',
      ProviderType.jsPlugin || ProviderType.legado => '在线书籍',
    };

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
                  typeTag,
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
                  book.author.isEmpty ? fallbackAuthor : book.author,
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
  if (book.author.isNotEmpty) {
    return book.author;
  }
  return book.providerType == ProviderType.localEpub ? '本地 EPUB' : '本地文本';
}
