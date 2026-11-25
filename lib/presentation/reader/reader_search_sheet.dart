import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/reader/in_book_search_service.dart';
import '../../application/reader/reader_search_controller.dart';
import '../../application/reader/reader_search_state.dart';
import '../../application/reader/reader_session_controller.dart';

/// Modal bottom sheet for in-book full-text keyword search, supporting
/// `当前章` / `全书已缓存章节` scope switching, highlighted snippet previews,
/// 500-match cap warning, and one-tap jump to the matched anchor.
class ReaderSearchSheet extends ConsumerStatefulWidget {
  const ReaderSearchSheet({
    super.key,
    required this.bookId,
    required this.onJumpToMatch,
  });

  final String bookId;
  final Future<void> Function(int chapterIndex, int charOffset) onJumpToMatch;

  /// Opens [ReaderSearchSheet] as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String bookId,
    required Future<void> Function(int chapterIndex, int charOffset)
    onJumpToMatch,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.82,
        child: ReaderSearchSheet(
          bookId: bookId,
          onJumpToMatch: onJumpToMatch,
        ),
      ),
    );
  }

  @override
  ConsumerState<ReaderSearchSheet> createState() => _ReaderSearchSheetState();
}

class _ReaderSearchSheetState extends ConsumerState<ReaderSearchSheet> {
  late final TextEditingController _queryController;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final initialQuery = ref
        .read(readerSearchControllerProvider(widget.bookId))
        .query;
    _queryController = TextEditingController(text: initialQuery);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value, ReaderSearchController controller) {
    setState(() {});
    _debounceTimer?.cancel();
    if (value.trim().isEmpty) {
      controller.clear();
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      unawaited(controller.search(value));
    });
  }

  void _submitQuery(String value, ReaderSearchController controller) {
    _debounceTimer?.cancel();
    unawaited(controller.search(value));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      readerSessionControllerProvider(widget.bookId).select((s) => s.book != null),
    );
    final state = ref.watch(readerSearchControllerProvider(widget.bookId));
    final controller = ref.read(
      readerSearchControllerProvider(widget.bookId).notifier,
    );
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, theme, state, controller),
            const SizedBox(height: 8),
            _buildSearchInput(controller),
            const SizedBox(height: 10),
            _buildScopeToggle(state, controller),
            if (state.isSearching) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (state.hasSearched || state.isSearching) ...[
              const SizedBox(height: 8),
              _buildStatusSummary(theme, state),
            ],
            if (state.isCapped) ...[
              const SizedBox(height: 6),
              _buildCapIndicator(theme),
            ],
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: _buildResultsBody(context, theme, state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ReaderSearchState state,
    ReaderSearchController controller,
  ) {
    return Row(
      children: [
        const Icon(Icons.search, size: 20),
        const SizedBox(width: 8),
        Text(
          '书内搜索',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (state.isSearching)
          TextButton(
            onPressed: controller.cancelSearch,
            child: const Text('停止'),
          ),
        IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _buildSearchInput(ReaderSearchController controller) {
    return TextField(
      controller: _queryController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '输入关键词搜索正文...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _queryController.text.isNotEmpty
            ? IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _debounceTimer?.cancel();
                  _queryController.clear();
                  setState(() {});
                  controller.clear();
                },
              )
            : null,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => _onQueryChanged(value, controller),
      onSubmitted: (value) => _submitQuery(value, controller),
    );
  }

  Widget _buildScopeToggle(
    ReaderSearchState state,
    ReaderSearchController controller,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('当前章'),
          selected: state.scope == InBookSearchScope.currentChapter,
          onSelected: (_) {
            _debounceTimer?.cancel();
            unawaited(controller.setScope(InBookSearchScope.currentChapter));
          },
        ),
        ChoiceChip(
          label: const Text('全书已缓存章节'),
          selected: state.scope == InBookSearchScope.wholeBook,
          onSelected: (_) {
            _debounceTimer?.cancel();
            unawaited(controller.setScope(InBookSearchScope.wholeBook));
          },
        ),
      ],
    );
  }

  Widget _buildStatusSummary(ThemeData theme, ReaderSearchState state) {
    final summaryText = state.isSearching
        ? '正在搜索 (${state.scannedChapters}/${state.totalCandidateChapters} 章) · 已找到 ${state.matches.length} 处'
        : '共找到 ${state.matches.length} 处匹配'
            '${state.skippedUncachedChapters > 0 ? '（跳过 ${state.skippedUncachedChapters} 个未缓存章节）' : ''}';
    return Text(
      summaryText,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildCapIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '匹配结果已达 ${InBookSearchService.defaultMaxMatches} 条上限，仅展示前 ${InBookSearchService.defaultMaxMatches} 条',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsBody(
    BuildContext context,
    ThemeData theme,
    ReaderSearchState state,
  ) {
    if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            state.errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }

    if (!state.hasSearched && state.query.isEmpty) {
      return Center(
        child: Text(
          '输入关键词搜索当前章或全书已缓存章节',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (state.isSearching && state.matches.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在搜索章节内容...'),
          ],
        ),
      );
    }

    if (state.matches.isEmpty) {
      final emptyHint = state.skippedUncachedChapters > 0
          ? '未找到包含“${state.query}”的内容\n（当前有 ${state.skippedUncachedChapters} 个在线章节未缓存）'
          : '未找到包含“${state.query}”的内容';
      return Center(
        child: Text(
          emptyHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: state.matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final match = state.matches[index];
        return _SearchMatchTile(
          match: match,
          onTap: () async {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            await widget.onJumpToMatch(match.chapterIndex, match.charOffset);
          },
        );
      },
    );
  }
}

class _SearchMatchTile extends StatelessWidget {
  const _SearchMatchTile({
    required this.match,
    required this.onTap,
  });

  final InBookSearchMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snippet = match.snippet;
    final start = match.matchStartInSnippet.clamp(0, snippet.length);
    final end = (start + match.matchLength).clamp(start, snippet.length);
    final before = snippet.substring(0, start);
    final hit = snippet.substring(start, end);
    final after = snippet.substring(end);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      title: Text(
        match.chapterTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            children: [
              if (before.isNotEmpty) TextSpan(text: before),
              if (hit.isNotEmpty)
                TextSpan(
                  text: hit,
                  style: TextStyle(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (after.isNotEmpty) TextSpan(text: after),
            ],
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: onTap,
    );
  }
}
