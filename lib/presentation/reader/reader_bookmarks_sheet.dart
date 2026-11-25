import 'package:flutter/material.dart';

import '../../domain/domain.dart';

/// Modal bottom sheet for managing bookmarks at exact `charOffset` positions.
class ReaderBookmarksSheet extends StatefulWidget {
  const ReaderBookmarksSheet({
    super.key,
    required this.bookmarks,
    required this.chapters,
    required this.onAddBookmark,
    required this.onSelectBookmark,
    required this.onDeleteBookmark,
  });

  final List<Bookmark> bookmarks;
  final List<ChapterMeta> chapters;
  final Future<void> Function(String note) onAddBookmark;
  final Future<void> Function(Bookmark bookmark) onSelectBookmark;
  final Future<void> Function(String bookmarkId) onDeleteBookmark;

  @override
  State<ReaderBookmarksSheet> createState() => _ReaderBookmarksSheetState();
}

class _ReaderBookmarksSheetState extends State<ReaderBookmarksSheet> {
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '书签 (${widget.bookmarks.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        hintText: '可选备注...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final note = _noteController.text;
                      _noteController.clear();
                      await widget.onAddBookmark(note);
                    },
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('添加书签'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Expanded(
                child: widget.bookmarks.isEmpty
                    ? Center(
                        child: Text(
                          '暂无书签',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: widget.bookmarks.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final bm = widget.bookmarks[index];
                          final chapterTitle =
                              (bm.chapterIndex >= 0 &&
                                  bm.chapterIndex < widget.chapters.length)
                              ? widget.chapters[bm.chapterIndex].title
                              : '第 ${bm.chapterIndex + 1} 章';
                          return ListTile(
                            title: Text(
                              chapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bm.excerpt,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (bm.note.isNotEmpty)
                                  Text(
                                    '备注：${bm.note}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: '删除书签',
                              onPressed: () => widget.onDeleteBookmark(bm.id),
                              icon: const Icon(Icons.delete_outline, size: 20),
                            ),
                            onTap: () async {
                              Navigator.of(context).pop();
                              await widget.onSelectBookmark(bm);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
