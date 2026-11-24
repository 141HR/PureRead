import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/search/change_source_controller.dart';
import '../../application/search/change_source_state.dart';
import '../../domain/domain.dart';

/// Reusable modal sheet for comparing alternative online sources, aligning
/// chapters via normalized title similarity, and falling back to a manual
/// chapter picker when similarity confidence is low.
class ChangeSourceSheet extends ConsumerStatefulWidget {
  final Book book;
  final int currentChapterIndex;
  final String currentChapterTitle;

  const ChangeSourceSheet({
    super.key,
    required this.book,
    required this.currentChapterIndex,
    required this.currentChapterTitle,
  });

  /// Opens [ChangeSourceSheet] as a modal bottom sheet and returns a
  /// [ChangeSourceSwitchResult] if the user confirms switching sources.
  static Future<ChangeSourceSwitchResult?> show(
    BuildContext context, {
    required Book book,
    required int currentChapterIndex,
    required String currentChapterTitle,
  }) {
    return showModalBottomSheet<ChangeSourceSwitchResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 920),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: ChangeSourceSheet(
          book: book,
          currentChapterIndex: currentChapterIndex,
          currentChapterTitle: currentChapterTitle,
        ),
      ),
    );
  }

  @override
  ConsumerState<ChangeSourceSheet> createState() => _ChangeSourceSheetState();
}

class _ChangeSourceSheetState extends ConsumerState<ChangeSourceSheet> {
  final TextEditingController _chapterFilterController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (!mounted) return;
      unawaited(
        ref.read(changeSourceControllerProvider.notifier).loadCandidates(
          book: widget.book,
          currentChapterIndex: widget.currentChapterIndex,
          currentChapterTitle: widget.currentChapterTitle,
        ),
      );
    });
  }

  @override
  void dispose() {
    _chapterFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(changeSourceControllerProvider);
    final controller = ref.read(changeSourceControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, theme, state, controller),
          if (state.isSearching) const LinearProgressIndicator(minHeight: 2),
          if (state.errorMessage != null && state.errorMessage!.isNotEmpty)
            _SheetErrorBanner(message: state.errorMessage!),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 680) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildCandidateList(state, controller, theme),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 6,
                        child: _buildMatchPanel(
                          context,
                          state,
                          controller,
                          theme,
                        ),
                      ),
                    ],
                  );
                }

                final candidateHeight = math.min(
                  constraints.maxHeight *
                      (state.showManualPicker ? 0.25 : 0.36),
                  state.showManualPicker ? 130.0 : 200.0,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: candidateHeight,
                      child: _buildCandidateList(state, controller, theme),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _buildMatchPanel(
                        context,
                        state,
                        controller,
                        theme,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ChangeSourceState state,
    ChangeSourceController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '换源对比 · ${widget.book.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.isSearching
                      ? '正在搜索可用书源 (${state.completedSources}/${state.totalSources}) · 当前：${widget.currentChapterTitle}'
                      : '当前章节：${widget.currentChapterTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (state.isSearching)
            TextButton(
              onPressed: controller.cancelSearch,
              child: const Text('停止'),
            )
          else
            IconButton(
              tooltip: '重新搜索候选源',
              onPressed: () {
                unawaited(
                  controller.loadCandidates(
                    book: widget.book,
                    currentChapterIndex: widget.currentChapterIndex,
                    currentChapterTitle: widget.currentChapterTitle,
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateList(
    ChangeSourceState state,
    ChangeSourceController controller,
    ThemeData theme,
  ) {
    if (state.candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            state.isSearching ? '正在从已启用书源搜寻同名书籍...' : '暂未找到其他匹配书源',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: state.candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final candidate = state.candidates[index];
        final isSelected = state.selectedCandidateIndex == index;
        return Material(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withAlpha(150)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              _chapterFilterController.clear();
              unawaited(controller.selectCandidate(index));
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          candidate.source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (candidate.isCurrentSource)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '当前源',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '最新：${candidate.latestChapterDisplay}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (candidate.chapters != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '共 ${candidate.chapters!.length} 章',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMatchPanel(
    BuildContext context,
    ChangeSourceState state,
    ChangeSourceController controller,
    ThemeData theme,
  ) {
    final selected = state.selectedCandidate;
    if (selected == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '选择任意候选书源以比对最新章节并匹配当前进度',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    if (selected.isLoadingToc) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在解析目录并匹配章节...'),
          ],
        ),
      );
    }

    final chapters = selected.chapters;
    if (chapters == null || chapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selected.errorMessage ?? '该书源未返回可用目录',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  final idx = state.selectedCandidateIndex;
                  if (idx != null) {
                    unawaited(controller.selectCandidate(idx));
                  }
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final match = selected.matchResult;
    final targetIdx = state.selectedTargetChapterIndex;
    final selectedChapter =
        (targetIdx != null && targetIdx >= 0 && targetIdx < chapters.length)
        ? chapters[targetIdx]
        : null;
    final filteredChapters = state.filteredSelectedChapters;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (match?.isConfident ?? false)
                  ? theme.colorScheme.primaryContainer.withAlpha(110)
                  : theme.colorScheme.tertiaryContainer.withAlpha(140),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (match?.isConfident ?? false)
                      ? '自动匹配成功（相似度 ${((match?.score ?? 0) * 100).round()}%）'
                      : '未精确命中，请手动确认目标章节',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedChapter != null
                      ? '目标章节：${selectedChapter.title}（第 ${selectedChapter.chapterIndex + 1} 章）'
                      : '尚未选择目标章节',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => controller.toggleManualPicker(),
                icon: Icon(
                  state.showManualPicker
                      ? Icons.expand_less
                      : Icons.list_alt_outlined,
                  size: 18,
                ),
                label: Text(state.showManualPicker ? '收起章节列表' : '手动选择章节'),
              ),
              FilledButton.icon(
                onPressed: (state.isSwitching || selectedChapter == null)
                    ? null
                    : () async {
                        final result = await controller.confirmSwitch();
                        if (result != null && context.mounted) {
                          Navigator.of(context).pop(result);
                        }
                      },
                icon: state.isSwitching
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.swap_horiz, size: 18),
                label: const Text('确认切换'),
              ),
            ],
          ),
          if (state.showManualPicker) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _chapterFilterController,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: '搜索目标书源章节名称...',
                border: OutlineInputBorder(),
              ),
              onChanged: controller.setChapterFilterQuery,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filteredChapters.length,
                itemBuilder: (context, i) {
                  final ch = filteredChapters[i];
                  final isChosen = ch.chapterIndex == targetIdx;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    selected: isChosen,
                    leading: Icon(
                      isChosen
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: isChosen
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      ch.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('第 ${ch.chapterIndex + 1} 章'),
                    onTap: () =>
                        controller.selectManualChapter(ch.chapterIndex),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetErrorBanner extends StatelessWidget {
  final String message;

  const _SheetErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
