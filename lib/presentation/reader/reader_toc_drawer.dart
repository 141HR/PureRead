import 'package:flutter/material.dart';

import '../../domain/domain.dart';

/// Slide-in Table of Contents drawer supporting chapter search filtering,
/// ascending/descending order toggle, and one-tap jump to the current chapter.
class ReaderTocDrawer extends StatefulWidget {
  const ReaderTocDrawer({
    super.key,
    required this.bookTitle,
    required this.chapters,
    required this.currentChapterIndex,
    required this.isReversed,
    required this.onToggleReverse,
    required this.onSelectChapter,
  });

  final String bookTitle;
  final List<ChapterMeta> chapters;
  final int currentChapterIndex;
  final bool isReversed;
  final VoidCallback onToggleReverse;
  final ValueChanged<int> onSelectChapter;

  @override
  State<ReaderTocDrawer> createState() => _ReaderTocDrawerState();
}

class _ReaderTocDrawerState extends State<ReaderTocDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ChapterMeta> get _filteredChapters {
    final base = widget.isReversed
        ? widget.chapters.reversed.toList(growable: false)
        : widget.chapters;
    final trimmed = _query.trim().toLowerCase();
    if (trimmed.isEmpty) return base;
    return base
        .where((c) => c.title.toLowerCase().contains(trimmed))
        .toList(growable: false);
  }

  void _locateCurrentChapter(List<ChapterMeta> visible) {
    final pos = visible.indexWhere(
      (c) => c.chapterIndex == widget.currentChapterIndex,
    );
    if (pos < 0 || !_scrollController.hasClients) return;
    const estimatedExtent = 52.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final target = (pos * estimatedExtent).clamp(0.0, maxScroll);
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _filteredChapters;

    return Drawer(
      width: 340,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.bookTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '共 ${widget.chapters.length} 章',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _locateCurrentChapter(visible),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('定位当前'),
                  ),
                  IconButton(
                    tooltip: widget.isReversed ? '切换正序' : '切换倒序',
                    onPressed: widget.onToggleReverse,
                    icon: Icon(
                      widget.isReversed
                          ? Icons.vertical_align_top
                          : Icons.vertical_align_bottom,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索章节名称...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的章节',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemExtent: 52,
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final chapter = visible[index];
                        final isCurrent =
                            chapter.chapterIndex == widget.currentChapterIndex;
                        return ListTile(
                          dense: true,
                          selected: isCurrent,
                          title: Text(
                            chapter.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: isCurrent
                              ? Icon(
                                  Icons.bookmark,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () =>
                              widget.onSelectChapter(chapter.chapterIndex),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
