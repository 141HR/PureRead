import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../application/explore/explore_controller.dart';
import '../../application/explore/explore_state.dart';
import '../../domain/domain.dart';
import '../search/online_book_detail_pane.dart';

/// Adaptive online source discovery and rankings workspace (发现与排行榜).
///
/// Selects between a 3-pane desktop layout (`maxWidth >= 1000`), a 2-pane
/// medium layout (`600 <= maxWidth < 1000`) with modal detail preview, and a
/// mobile drill-down layout (`maxWidth < 600`).
class ExplorePage extends ConsumerStatefulWidget {
  /// Optional callback invoked instead of `GoRouter.go(AppRoutes.sources)` when
  /// navigating to the source workbench in standalone widget tests.
  final VoidCallback? onNavigateToSources;

  const ExplorePage({super.key, this.onNavigateToSources});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  static const String _emptyDetailPlaceholder = '选择排行榜中的书籍查看详情与目录预览';
  static const double _desktopThreePaneBreakpoint = 1000.0;
  static const double _mediumTwoPaneBreakpoint = 600.0;
  static const double _scrollLoadMoreThreshold = 160.0;

  final TextEditingController _sourceFilterController = TextEditingController();
  final ScrollController _booksScrollController = ScrollController();

  bool _mobileShowDetail = false;
  bool _showMobileSourceFilter = false;
  bool _categoriesExpanded = true;

  @override
  void initState() {
    super.initState();
    _booksScrollController.addListener(_onBooksScroll);
    Future.microtask(() {
      if (!mounted) return;
      unawaited(
        ref.read(exploreControllerProvider.notifier).loadExploreSources(),
      );
    });
  }

  @override
  void dispose() {
    _booksScrollController.removeListener(_onBooksScroll);
    _booksScrollController.dispose();
    _sourceFilterController.dispose();
    super.dispose();
  }

  void _onBooksScroll() {
    if (!_booksScrollController.hasClients) return;
    final position = _booksScrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent - _scrollLoadMoreThreshold) {
      unawaited(ref.read(exploreControllerProvider.notifier).loadNextPage());
    }
  }

  void _closeMobileDetail() {
    if (!_mobileShowDetail) return;
    setState(() {
      _mobileShowDetail = false;
    });
  }

  void _goToSources() {
    final override = widget.onNavigateToSources;
    if (override != null) {
      override();
      return;
    }
    GoRouter.maybeOf(context)?.go(AppRoutes.sources);
  }

  void _selectSource(String sourceId) {
    if (_mobileShowDetail) {
      setState(() {
        _mobileShowDetail = false;
      });
    }
    unawaited(
      ref.read(exploreControllerProvider.notifier).selectSource(sourceId),
    );
  }

  void _selectCategory(ExploreCategory category) {
    if (category.isGroupHeader) return;
    if (_mobileShowDetail) {
      setState(() {
        _mobileShowDetail = false;
      });
    }
    unawaited(
      ref.read(exploreControllerProvider.notifier).selectCategory(category),
    );
  }

  void _onBookTap(
    BookSearchItem item, {
    required bool isMobile,
    required bool opensSheetOnTap,
  }) {
    unawaited(
      ref.read(exploreControllerProvider.notifier).selectBookForDetail(item),
    );
    if (isMobile) {
      setState(() {
        _mobileShowDetail = true;
      });
      return;
    }
    if (opensSheetOnTap) {
      unawaited(_showMediumDetailSheet());
    }
  }

  Future<void> _showMediumDetailSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.84;
        return SizedBox(
          height: sheetHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '书籍详情与目录预览',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭详情',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: OnlineBookDetailPane(
                  detailProvider: exploreBookDetailControllerProvider,
                  emptyPlaceholderText: _emptyDetailPlaceholder,
                  onOpenReader: ({int? initialChapterIndex}) async {
                    final detailController = ref.read(
                      exploreBookDetailControllerProvider.notifier,
                    );
                    final bookId = await detailController.prepareForReader(
                      initialChapterIndex: initialChapterIndex,
                    );
                    if (bookId == null) return;
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                    if (mounted) {
                      await _pushReader(bookId);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openReader({int? initialChapterIndex}) async {
    final detailController = ref.read(
      exploreBookDetailControllerProvider.notifier,
    );
    final bookId = await detailController.prepareForReader(
      initialChapterIndex: initialChapterIndex,
    );
    if (bookId != null && mounted) {
      await _pushReader(bookId);
    }
  }

  Future<void> _pushReader(String bookId) async {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push(AppRoutes.readerForBook(bookId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exploreControllerProvider);
    final detailState = ref.watch(exploreBookDetailControllerProvider);
    final controller = ref.read(exploreControllerProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final isMobile = maxWidth < _mediumTwoPaneBreakpoint;
        final isDesktopThreePane = maxWidth >= _desktopThreePaneBreakpoint;
        final showingMobileDetail =
            isMobile &&
            _mobileShowDetail &&
            detailState.aggregatedBook != null;
        final isLoadingAny =
            state.isLoadingSources ||
            state.isLoadingCategories ||
            state.isLoadingBooks;

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
                      tooltip: '返回榜单',
                      onPressed: _closeMobileDetail,
                      icon: const Icon(Icons.arrow_back),
                    )
                  : null,
              title: const Text('发现与排行榜'),
              actions: [
                if (!showingMobileDetail)
                  IconButton(
                    tooltip: '刷新发现书源',
                    onPressed: state.isLoadingSources
                        ? null
                        : () => unawaited(
                            controller.loadExploreSources(forceRefresh: true),
                          ),
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isLoadingAny) const LinearProgressIndicator(minHeight: 2),
                if (state.errorMessage != null &&
                    state.errorMessage!.isNotEmpty)
                  _ExploreErrorBanner(
                    message: state.errorMessage!,
                    onDismiss: controller.clearError,
                  ),
                Expanded(
                  child: _buildBody(
                    state: state,
                    isMobile: isMobile,
                    isDesktopThreePane: isDesktopThreePane,
                    showingMobileDetail: showingMobileDetail,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody({
    required ExploreState state,
    required bool isMobile,
    required bool isDesktopThreePane,
    required bool showingMobileDetail,
  }) {
    if (state.isLoadingSources && state.exploreSources.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在加载支持发现功能的书源...'),
            ],
          ),
        ),
      );
    }

    if (!state.isLoadingSources && state.exploreSources.isEmpty) {
      return _ExploreEmptySourcesView(onGoToSources: _goToSources);
    }

    if (showingMobileDetail) {
      return OnlineBookDetailPane(
        detailProvider: exploreBookDetailControllerProvider,
        onOpenReader: _openReader,
        emptyPlaceholderText: _emptyDetailPlaceholder,
      );
    }

    if (isDesktopThreePane) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 220,
            child: _buildSourceSidebar(state),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _buildRankingWorkspace(
              state,
              isMobile: false,
              opensSheetOnTap: false,
            ),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 360,
            child: OnlineBookDetailPane(
              detailProvider: exploreBookDetailControllerProvider,
              onOpenReader: _openReader,
              emptyPlaceholderText: _emptyDetailPlaceholder,
            ),
          ),
        ],
      );
    }

    if (!isMobile) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 200,
            child: _buildSourceSidebar(state),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _buildRankingWorkspace(
              state,
              isMobile: false,
              opensSheetOnTap: true,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMobileSourceStrip(state),
        const Divider(height: 1),
        Expanded(
          child: _buildRankingWorkspace(
            state,
            isMobile: true,
            opensSheetOnTap: false,
          ),
        ),
      ],
    );
  }

  Widget _buildSourceFilterField({required bool compact}) {
    final controller = ref.read(exploreControllerProvider.notifier);
    return TextField(
      controller: _sourceFilterController,
      decoration: InputDecoration(
        hintText: '筛选书源...',
        prefixIcon: const Icon(Icons.search, size: 18),
        isDense: true,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : null,
        border: const OutlineInputBorder(),
        suffixIcon: _sourceFilterController.text.isNotEmpty
            ? IconButton(
                tooltip: '清空筛选',
                onPressed: () {
                  _sourceFilterController.clear();
                  controller.setSourceFilterQuery('');
                  setState(() {});
                },
                icon: const Icon(Icons.close, size: 18),
              )
            : null,
      ),
      onChanged: (value) {
        controller.setSourceFilterQuery(value);
        setState(() {});
      },
    );
  }

  Widget _buildSourceSidebar(ExploreState state) {
    final theme = Theme.of(context);
    final sources = state.filteredSources;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSourceFilterField(compact: false),
              const SizedBox(height: 8),
              Text(
                '发现书源 (${sources.length}/${state.exploreSources.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: sources.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '没有匹配的书源',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  itemCount: sources.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final source = sources[index];
                    final isSelected = source.id == state.selectedSourceId;
                    return Material(
                      color: isSelected
                          ? theme.colorScheme.primaryContainer.withAlpha(140)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _selectSource(source.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                source.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimaryContainer
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      source.groupName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '权重 ${source.weight}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMobileSourceStrip(ExploreState state) {
    final theme = Theme.of(context);
    final sources = state.filteredSources;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '筛选发现书源',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _showMobileSourceFilter = !_showMobileSourceFilter;
                  });
                },
                icon: Icon(
                  _showMobileSourceFilter || state.sourceFilterQuery.isNotEmpty
                      ? Icons.filter_list_off
                      : Icons.filter_list,
                  size: 20,
                ),
              ),
              Expanded(
                child: sources.isEmpty
                    ? Text(
                        '没有匹配的发现书源',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: sources.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final source = sources[index];
                            final selected =
                                source.id == state.selectedSourceId;
                            return ChoiceChip(
                              label: Text(source.name),
                              selected: selected,
                              onSelected: (_) => _selectSource(source.id),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          if (_showMobileSourceFilter || state.sourceFilterQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSourceFilterField(compact: true),
          ],
        ],
      ),
    );
  }

  Widget _buildRankingWorkspace(
    ExploreState state, {
    required bool isMobile,
    required bool opensSheetOnTap,
  }) {
    final controller = ref.read(exploreControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildWorkspaceHeader(state),
        if (_categoriesExpanded)
          _ExploreCategoryPanel(
            categories: state.categories,
            selectedCategory: state.selectedCategory,
            isLoadingCategories: state.isLoadingCategories,
            maxHeight: isMobile ? 168 : 210,
            onSelectCategory: _selectCategory,
          ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.refreshCurrentCategory,
            child: _buildBooksArea(
              state,
              isMobile: isMobile,
              opensSheetOnTap: opensSheetOnTap,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceHeader(ExploreState state) {
    final theme = Theme.of(context);
    final controller = ref.read(exploreControllerProvider.notifier);
    final sourceName = state.selectedSource?.name ?? '发现榜单';
    final categoryTitle = state.selectedCategory?.title ?? '未选择分类';
    final traceSummary = _formatTraceSummary(state.lastTrace);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$sourceName · $categoryTitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (traceSummary != null)
                  Tooltip(
                    message:
                        state.lastTrace?.matchedPreview ??
                        state.lastTrace?.requestUrl ??
                        traceSummary,
                    child: Text(
                      traceSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '刷新当前榜单',
            visualDensity: VisualDensity.compact,
            onPressed: state.isLoadingBooks || state.selectedCategory == null
                ? null
                : () => unawaited(controller.refreshCurrentCategory()),
            icon: const Icon(Icons.refresh, size: 19),
          ),
          if (state.categories.isNotEmpty)
            IconButton(
              tooltip: _categoriesExpanded ? '收起分类' : '展开分类',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  _categoriesExpanded = !_categoriesExpanded;
                });
              },
              icon: Icon(
                _categoriesExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBooksArea(
    ExploreState state, {
    required bool isMobile,
    required bool opensSheetOnTap,
  }) {
    final theme = Theme.of(context);
    final controller = ref.read(exploreControllerProvider.notifier);

    if (state.items.isEmpty) {
      final Widget emptyContent;
      if (state.isLoadingCategories || state.isLoadingBooks) {
        emptyContent = const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载榜单书籍...'),
          ],
        );
      } else if (state.selectedCategory != null) {
        emptyContent = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              '当前榜单暂无书籍',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => unawaited(controller.refreshCurrentCategory()),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新加载'),
            ),
          ],
        );
      } else {
        emptyContent = Text(
          state.clickableCategories.isEmpty
              ? '当前书源没有可浏览的排行榜分类'
              : '请选择上方分类查看排行榜',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: emptyContent,
                ),
              ),
            ),
          );
        },
      );
    }

    return ListView.separated(
      controller: _booksScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: state.items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return _ExplorePaginationFooter(
            itemCount: state.items.length,
            currentPage: state.currentPage,
            hasMore: state.hasMore,
            isLoadingMore: state.isLoadingMore,
            onLoadMore: () => unawaited(controller.loadNextPage()),
          );
        }

        final item = state.items[index];
        final isSelected = !isMobile && state.selectedBookUrl == item.bookUrl;
        return _ExploreBookCard(
          rank: index + 1,
          item: item,
          isSelected: isSelected,
          onTap: () => _onBookTap(
            item,
            isMobile: isMobile,
            opensSheetOnTap: opensSheetOnTap,
          ),
        );
      },
    );
  }

  String? _formatTraceSummary(SourceDebugTrace? trace) {
    if (trace == null) return null;
    final parts = <String>[trace.step];
    if (trace.httpStatus != null) {
      parts.add('HTTP ${trace.httpStatus}');
    }
    parts.add('${trace.elapsedMs}ms');
    return parts.join(' · ');
  }
}

class _ExploreErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ExploreErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 18,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              tooltip: '关闭错误提示',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                size: 18,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreEmptySourcesView extends StatelessWidget {
  final VoidCallback onGoToSources;

  const _ExploreEmptySourcesView({required this.onGoToSources});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_off_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                '暂无支持发现与排行榜的书源',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前已启用书源均未配置有效的 exploreUrl 发现规则或插件发现接口。请前往书源工作台导入或启用支持发现功能的书源。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onGoToSources,
                icon: const Icon(Icons.extension_outlined, size: 18),
                label: const Text('前往书源管理'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySection {
  final String? header;
  final List<ExploreCategory> items;

  const _CategorySection({
    required this.header,
    required this.items,
  });
}

class _ExploreCategoryPanel extends StatelessWidget {
  final List<ExploreCategory> categories;
  final ExploreCategory? selectedCategory;
  final bool isLoadingCategories;
  final double maxHeight;
  final ValueChanged<ExploreCategory> onSelectCategory;

  const _ExploreCategoryPanel({
    required this.categories,
    required this.selectedCategory,
    required this.isLoadingCategories,
    required this.maxHeight,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (categories.isEmpty) {
      if (isLoadingCategories) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Text(
          '该书源未解析出发现分类',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final sections = _groupCategories(categories);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              if (sections[i].header != null) ...[
                Text(
                  sections[i].header!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (sections[i].items.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final category in sections[i].items)
                      ChoiceChip(
                        label: Text(category.title),
                        selected: selectedCategory == category,
                        onSelected: (_) => onSelectCategory(category),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  static List<_CategorySection> _groupCategories(
    List<ExploreCategory> categories,
  ) {
    final sections = <_CategorySection>[];
    String? currentHeader;
    var currentItems = <ExploreCategory>[];

    void flush() {
      if (currentHeader != null || currentItems.isNotEmpty) {
        sections.add(
          _CategorySection(
            header: currentHeader,
            items: List<ExploreCategory>.unmodifiable(currentItems),
          ),
        );
      }
      currentHeader = null;
      currentItems = <ExploreCategory>[];
    }

    for (final category in categories) {
      if (category.isGroupHeader) {
        flush();
        final trimmed = category.title.trim();
        currentHeader = trimmed.isEmpty ? null : trimmed;
        continue;
      }

      final itemGroup = category.group?.trim();
      if (itemGroup != null && itemGroup.isNotEmpty) {
        if (currentHeader == null && currentItems.isEmpty) {
          currentHeader = itemGroup;
        } else if (currentHeader != itemGroup && currentItems.isNotEmpty) {
          flush();
          currentHeader = itemGroup;
        } else {
          currentHeader ??= itemGroup;
        }
      }
      currentItems.add(category);
    }
    flush();

    return sections;
  }
}

class _ExploreBookCard extends StatelessWidget {
  final int rank;
  final BookSearchItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExploreBookCard({
    required this.rank,
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = item.kind?.trim() ?? '';

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
              OnlineBookCover(title: item.title, coverUrl: item.coverUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _RankBadge(rank: rank),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (kind.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                kind,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.author.isEmpty ? '未知作者' : item.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (item.latestChapterTitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '最新：${item.latestChapterTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    if (item.intro.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.intro,
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

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color bg, Color fg) = switch (rank) {
      1 => (const Color(0xFFD97706), Colors.white),
      2 => (const Color(0xFF5C6B7A), Colors.white),
      3 => (const Color(0xFFA0522D), Colors.white),
      _ => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$rank',
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: rank <= 3 ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _ExplorePaginationFooter extends StatelessWidget {
  final int itemCount;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  const _ExplorePaginationFooter({
    required this.itemCount,
    required this.currentPage,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              '正在加载第 ${currentPage + 1} 页...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.expand_more, size: 18),
            label: const Text('加载更多'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          '已加载全部 $itemCount 本（第 $currentPage 页）',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
