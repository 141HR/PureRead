import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../application/search/book_detail_controller.dart';
import '../../application/search/book_detail_state.dart';
import '../../application/search/search_controller.dart';
import '../../application/search/search_state.dart';
import 'change_source_sheet.dart';

/// Adaptive multi-source aggregated search page.
///
/// Renders a Desktop 2-pane workspace (`>= kDesktopLayoutBreakpoint`) with
/// live detail/TOC preview on the right, and a Mobile search-to-detail flow
/// on narrow screens.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _queryController = TextEditingController();
  bool _mobileShowDetail = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final keyword = _queryController.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _mobileShowDetail = false;
    });
    ref.read(searchControllerProvider.notifier).selectBook(null);
    unawaited(ref.read(searchControllerProvider.notifier).search(keyword));
  }

  void _selectResult(AggregatedSearchBook book, {required bool isDesktop}) {
    ref.read(searchControllerProvider.notifier).selectBook(book.groupKey);
    unawaited(
      ref.read(bookDetailControllerProvider.notifier).loadAggregatedBook(book),
    );
    if (!isDesktop) {
      setState(() {
        _mobileShowDetail = true;
      });
    }
  }

  void _closeMobileDetail() {
    setState(() {
      _mobileShowDetail = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchControllerProvider);
    final detailState = ref.watch(bookDetailControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= kDesktopLayoutBreakpoint;
        final showingMobileDetail =
            !isDesktop &&
            _mobileShowDetail &&
            detailState.aggregatedBook != null;

        return PopScope(
          canPop: !showingMobileDetail,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && showingMobileDetail) {
              _closeMobileDetail();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: showingMobileDetail
                  ? IconButton(
                      tooltip: '返回搜索结果',
                      onPressed: _closeMobileDetail,
                      icon: const Icon(Icons.arrow_back),
                    )
                  : null,
              // Keep '多源聚合搜索' visible once on SearchPage (test/widget_test.dart).
              title: const Text('多源聚合搜索'),
              actions: [
                if (searchState.results.isNotEmpty ||
                    searchState.query.isNotEmpty)
                  IconButton(
                    tooltip: '清空搜索',
                    onPressed: () {
                      _queryController.clear();
                      setState(() {
                        _mobileShowDetail = false;
                      });
                      ref
                          .read(searchControllerProvider.notifier)
                          .clearResults();
                    },
                    icon: const Icon(Icons.clear_all),
                  ),
              ],
            ),
            body: isDesktop
                ? _buildDesktopBody(searchState, detailState)
                : (showingMobileDetail
                      ? _BookDetailPane(
                          state: detailState,
                          onOpenReader: _openReader,
                        )
                      : _buildSearchPane(searchState, isDesktop: false)),
          ),
        );
      },
    );
  }

  Widget _buildDesktopBody(
    SearchState searchState,
    BookDetailState detailState,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 400,
          child: _buildSearchPane(searchState, isDesktop: true),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _BookDetailPane(
            state: detailState,
            onOpenReader: _openReader,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchPane(SearchState state, {required bool isDesktop}) {
    final controller = ref.read(searchControllerProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '输入书名或作者...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _queryController.text.isNotEmpty
                        ? IconButton(
                            tooltip: '清空输入',
                            onPressed: () {
                              _queryController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close, size: 18),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitSearch(),
                ),
              ),
              const SizedBox(width: 8),
              if (state.isSearching)
                OutlinedButton(
                  onPressed: controller.cancelSearch,
                  child: const Text('取消'),
                )
              else
                FilledButton(
                  onPressed: _submitSearch,
                  child: const Text('搜索'),
                ),
            ],
          ),
        ),
        if (state.isSearching) const LinearProgressIndicator(minHeight: 2),
        if (state.totalSources > 0 || state.query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.isSearching
                        ? '正在检索 (${state.completedSources}/${state.totalSources} 源) · 已聚合 ${state.results.length} 本'
                        : '已完成 ${state.completedSources}/${state.totalSources} 个书源 · 共 ${state.results.length} 本结果',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (state.sourceErrors.isNotEmpty)
                  Tooltip(
                    message: state.sourceErrors.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                    child: Text(
                      '${state.sourceErrors.length} 源异常',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (state.errorMessage != null && state.errorMessage!.isNotEmpty)
          Material(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                state.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        Expanded(child: _buildResultsList(state, theme, isDesktop: isDesktop)),
      ],
    );
  }

  Widget _buildResultsList(
    SearchState state,
    ThemeData theme, {
    required bool isDesktop,
  }) {
    if (state.query.isEmpty && state.results.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore_outlined,
                size: 52,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                '输入书名或作者，跨已启用书源实时聚合搜书',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state.results.isEmpty && !state.isSearching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '未找到与“${state.query}”相关的书籍',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: state.results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final book = state.results[index];
        final isSelected = isDesktop && state.selectedGroupKey == book.groupKey;
        return _AggregatedSearchCard(
          book: book,
          isSelected: isSelected,
          onTap: () => _selectResult(book, isDesktop: isDesktop),
        );
      },
    );
  }

  Future<void> _openReader({int? initialChapterIndex}) async {
    final detailController = ref.read(bookDetailControllerProvider.notifier);
    final bookId = await detailController.prepareForReader(
      initialChapterIndex: initialChapterIndex,
    );
    if (bookId != null && mounted) {
      await context.push(AppRoutes.readerForBook(bookId));
    }
  }
}

class _AggregatedSearchCard extends StatelessWidget {
  final AggregatedSearchBook book;
  final bool isSelected;
  final VoidCallback onTap;

  const _AggregatedSearchCard({
    required this.book,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: isSelected ? 2 : 0.5,
      color: isSelected
          ? theme.colorScheme.primaryContainer.withAlpha(110)
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniBookCover(title: book.title),
              const SizedBox(width: 12),
              Expanded(
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
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${book.sourceCount} 个书源',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author.isEmpty ? '未知作者' : book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (book.latestChapterTitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '最新：${book.latestChapterTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    if (book.intro.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        book.intro,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookDetailPane extends ConsumerWidget {
  final BookDetailState state;
  final Future<void> Function({int? initialChapterIndex}) onOpenReader;

  const _BookDetailPane({
    required this.state,
    required this.onOpenReader,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final book = state.aggregatedBook;
    if (book == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '选择左侧任意书籍以预览详情与章节目录',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final controller = ref.read(bookDetailControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MiniBookCover(title: state.displayTitle, large: true),
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
                      onPressed: () async {
                        final currentBook = state.existingBookshelfBook!;
                        final result = await ChangeSourceSheet.show(
                          context,
                          book: currentBook,
                          currentChapterIndex: 0,
                          currentChapterTitle: state.chapters.isNotEmpty
                              ? state.chapters.first.title
                              : currentBook.lastChapterTitle,
                        );
                        if (result != null && context.mounted) {
                          await controller.reload();
                        }
                      },
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
        ),
        if (state.statusMessage != null)
          Material(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                state.statusMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        if (state.errorMessage != null)
          Material(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                state.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        const Divider(height: 1),
        Padding(
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
        ),
        Expanded(
          child: state.chapters.isEmpty
              ? Center(
                  child: Text(
                    state.isLoadingToc ? '正在加载章节目录...' : '暂无章节预览',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
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
                      onTap: () =>
                          unawaited(onOpenReader(initialChapterIndex: index)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MiniBookCover extends StatelessWidget {
  final String title;
  final bool large;

  const _MiniBookCover({required this.title, this.large = false});

  @override
  Widget build(BuildContext context) {
    final firstChar = title.trim().isEmpty ? '书' : title.trim().substring(0, 1);
    return Container(
      width: large ? 72 : 52,
      height: large ? 96 : 70,
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
}
