import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../application/source_lab/replace_rules_controller.dart';
import '../../application/source_lab/replace_rules_state.dart';
import '../../application/source_lab/source_debug_controller.dart';
import '../../application/source_lab/source_debug_state.dart';
import '../../application/source_lab/sources_controller.dart';
import '../../application/source_lab/sources_state.dart';
import '../../domain/domain.dart';

/// Adaptive book source management, visual debugger, and content sanitization
/// workbench organized into 3 tabs:
/// 书源管理 / 书源调试台 / 正文净化规则.
class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openDebugForSource(String sourceId) {
    ref.read(sourceDebugControllerProvider.notifier).selectSource(sourceId);
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书源工作台'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Tab>[
            Tab(text: '书源管理'),
            Tab(text: '书源调试台'),
            Tab(text: '正文净化规则'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _SourcesManageTab(onDebugSource: _openDebugForSource),
          const _SourceDebugTab(),
          const _ReplaceRulesTab(),
        ],
      ),
    );
  }
}

class _SourcesManageTab extends ConsumerStatefulWidget {
  final void Function(String sourceId) onDebugSource;

  const _SourcesManageTab({required this.onDebugSource});

  @override
  ConsumerState<_SourcesManageTab> createState() => _SourcesManageTabState();
}

class _SourcesManageTabState extends ConsumerState<_SourcesManageTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sourcesControllerProvider);
    final controller = ref.read(sourcesControllerProvider.notifier);
    final theme = Theme.of(context);
    final visibleSources = state.filteredSources;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索书源名称、域名或分组...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            tooltip: '清空',
                            onPressed: () {
                              _searchController.clear();
                              controller.setSearchQuery('');
                              setState(() {});
                            },
                            icon: const Icon(Icons.close, size: 16),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    controller.setSearchQuery(value);
                    setState(() {});
                  },
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: state.isImporting
                    ? null
                    : () => unawaited(controller.importFromFiles()),
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('导入文件'),
              ),
              OutlinedButton.icon(
                onPressed: state.isImporting ? null : _showPasteImportDialog,
                icon: const Icon(Icons.content_paste_outlined, size: 18),
                label: const Text('粘贴导入'),
              ),
              OutlinedButton.icon(
                onPressed: visibleSources.isEmpty ? null : _showExportDialog,
                icon: const Icon(Icons.ios_share_outlined, size: 18),
                label: const Text('导出'),
              ),
            ],
          ),
        ),
        if (state.isImporting) const LinearProgressIndicator(minHeight: 2),
        if (state.statusMessage != null || state.errorMessage != null)
          _InlineBanner(
            errorMessage: state.errorMessage,
            statusMessage: state.statusMessage,
            onDismiss: controller.clearBanner,
          ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: state.groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final group = state.groups[index];
              final count = state.countForGroup(group);
              return ChoiceChip(
                label: Text('$group ($count)'),
                selected: state.selectedGroup == group,
                onSelected: (_) => controller.selectGroup(group),
              );
            },
          ),
        ),
        if (state.selectedIds.isNotEmpty)
          Material(
            color: theme.colorScheme.primaryContainer.withAlpha(110),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '已选 ${state.selectedIds.length} 项',
                    style: theme.textTheme.labelLarge,
                  ),
                  TextButton(
                    onPressed: controller.toggleSelectAllVisible,
                    child: const Text('全选/反选'),
                  ),
                  TextButton(
                    onPressed: () =>
                        unawaited(controller.setSelectedEnabled(true)),
                    child: const Text('批量启用'),
                  ),
                  TextButton(
                    onPressed: () =>
                        unawaited(controller.setSelectedEnabled(false)),
                    child: const Text('批量禁用'),
                  ),
                  TextButton(
                    onPressed: () => unawaited(controller.deleteSelected()),
                    child: Text(
                      '批量删除',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _buildSourceList(
            context,
            theme,
            state,
            controller,
            visibleSources,
          ),
        ),
      ],
    );
  }

  Widget _buildSourceList(
    BuildContext context,
    ThemeData theme,
    SourcesState state,
    SourcesController controller,
    List<BookSource> visibleSources,
  ) {
    if (state.isLoading && state.sources.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.sources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.extension_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                '暂无在线书源',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '支持批量导入 Legado JSON 书源集合或轻量化 JS 插件书源 (.json / .js)。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => unawaited(controller.importFromFiles()),
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('导入本地书源'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showPasteImportDialog,
                    icon: const Icon(Icons.content_paste_outlined, size: 18),
                    label: const Text('粘贴规则文本'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (visibleSources.isEmpty) {
      return Center(
        child: Text(
          '当前筛选条件下无匹配书源',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: visibleSources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final source = visibleSources[index];
        final isSelected = state.selectedIds.contains(source.id);
        return Card(
          elevation: 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => controller.toggleSelection(source.id),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                source.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              _TagChip(
                                label:
                                    source.engineType ==
                                        SourceEngineType.jsPlugin
                                    ? 'JS'
                                    : 'Legado',
                                color: theme.colorScheme.secondaryContainer,
                              ),
                              _TagChip(
                                label: source.groupName,
                                color: theme.colorScheme.surfaceContainerHighest,
                              ),
                              _CheckStatusChip(status: source.lastCheckStatus),
                            ],
                          ),
                          if (source.baseUrl.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              source.baseUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Switch(
                      value: source.enabled,
                      onChanged: (_) =>
                          unawaited(controller.toggleEnabled(source.id)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChip(
                      label: Text('权重 ${source.weight}'),
                      onPressed: () => _showWeightDialog(source),
                    ),
                    TextButton.icon(
                      onPressed: () => widget.onDebugSource(source.id),
                      icon: const Icon(Icons.bug_report_outlined, size: 16),
                      label: const Text('调试'),
                    ),
                    IconButton(
                      tooltip: '删除书源',
                      onPressed: () =>
                          unawaited(controller.deleteSource(source.id)),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPasteImportDialog() async {
    final submitted = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteImportDialog(),
    );
    if (submitted != null && mounted) {
      await ref
          .read(sourcesControllerProvider.notifier)
          .importFromText(submitted);
    }
  }

  Future<void> _showWeightDialog(BookSource source) async {
    final parsed = await showDialog<int>(
      context: context,
      builder: (_) => _WeightEditDialog(source: source),
    );
    if (parsed != null && mounted) {
      await ref
          .read(sourcesControllerProvider.notifier)
          .updateWeight(source.id, parsed);
    }
  }

  Future<void> _showExportDialog() async {
    final exported = await ref
        .read(sourcesControllerProvider.notifier)
        .exportSources();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导出书源内容'),
        content: SizedBox(
          width: 520,
          height: 320,
          child: SingleChildScrollView(
            child: SelectableText(
              exported,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: exported));
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制'),
          ),
        ],
      ),
    );
  }
}

class _PasteImportDialog extends StatefulWidget {
  const _PasteImportDialog();

  @override
  State<_PasteImportDialog> createState() => _PasteImportDialogState();
}

class _PasteImportDialogState extends State<_PasteImportDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('粘贴导入书源'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: '粘贴 Legado JSON 数组/对象 或 JS 插件代码...',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('导入'),
        ),
      ],
    );
  }
}

class _WeightEditDialog extends StatefulWidget {
  final BookSource source;

  const _WeightEditDialog({required this.source});

  @override
  State<_WeightEditDialog> createState() => _WeightEditDialogState();
}

class _WeightEditDialogState extends State<_WeightEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.source.weight}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('调整权重 · ${widget.source.name}'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: '优先级权重（整数越大越靠前）',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final value = int.tryParse(_controller.text.trim());
            Navigator.of(context).pop(value);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SourceDebugTab extends ConsumerStatefulWidget {
  const _SourceDebugTab();

  @override
  ConsumerState<_SourceDebugTab> createState() => _SourceDebugTabState();
}

class _SourceDebugTabState extends ConsumerState<_SourceDebugTab> {
  final TextEditingController _keywordController = TextEditingController(
    text: '凡人修仙传',
  );

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourcesState = ref.watch(sourcesControllerProvider);
    final debugState = ref.watch(sourceDebugControllerProvider);
    final debugController = ref.read(sourceDebugControllerProvider.notifier);
    final theme = Theme.of(context);

    final availableSources = sourcesState.sources;
    final hasSelected =
        debugState.selectedSourceId != null &&
        availableSources.any((s) => s.id == debugState.selectedSourceId);
    final effectiveSourceId = hasSelected
        ? debugState.selectedSourceId
        : (availableSources.isNotEmpty ? availableSources.first.id : null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final controlsPanel = _buildControlsAndSteps(
          theme: theme,
          sources: availableSources,
          effectiveSourceId: effectiveSourceId,
          debugState: debugState,
          debugController: debugController,
        );
        final inspectorPanel = _buildOutputInspector(
          theme: theme,
          debugState: debugState,
          debugController: debugController,
        );

        if (constraints.maxWidth >= kDesktopLayoutBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 440, child: controlsPanel),
              const VerticalDivider(width: 1),
              Expanded(child: inspectorPanel),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildControlsHeader(
              theme: theme,
              sources: availableSources,
              effectiveSourceId: effectiveSourceId,
              debugState: debugState,
              debugController: debugController,
            ),
            const SizedBox(height: 12),
            ...DebugStepKind.values.map(
              (kind) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _StepTraceCard(report: debugState.steps[kind]!),
              ),
            ),
            const SizedBox(height: 8),
            _buildInspectorContents(
              theme: theme,
              debugState: debugState,
              debugController: debugController,
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlsAndSteps({
    required ThemeData theme,
    required List<BookSource> sources,
    required String? effectiveSourceId,
    required SourceDebugState debugState,
    required SourceDebugController debugController,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildControlsHeader(
          theme: theme,
          sources: sources,
          effectiveSourceId: effectiveSourceId,
          debugState: debugState,
          debugController: debugController,
        ),
        const SizedBox(height: 14),
        ...DebugStepKind.values.map(
          (kind) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _StepTraceCard(report: debugState.steps[kind]!),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsHeader({
    required ThemeData theme,
    required List<BookSource> sources,
    required String? effectiveSourceId,
    required SourceDebugState debugState,
    required SourceDebugController debugController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey<String?>('debug_src_$effectiveSourceId'),
          initialValue: effectiveSourceId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '选择调试书源',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: sources
              .map(
                (s) => DropdownMenuItem<String>(
                  value: s.id,
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: debugController.selectSource,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _keywordController,
                decoration: const InputDecoration(
                  labelText: '测试搜索词',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: debugController.setKeyword,
              ),
            ),
            const SizedBox(width: 8),
            if (debugState.isRunning)
              OutlinedButton.icon(
                onPressed: debugController.cancelDebug,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('取消'),
              )
            else
              FilledButton.icon(
                onPressed: effectiveSourceId == null
                    ? null
                    : () => unawaited(
                        debugController.startDebug(
                          sourceId: effectiveSourceId,
                          keyword: _keywordController.text,
                        ),
                      ),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('开始调试'),
              ),
          ],
        ),
        if (debugState.errorMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              debugState.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOutputInspector({
    required ThemeData theme,
    required SourceDebugState debugState,
    required SourceDebugController debugController,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInspectorContents(
          theme: theme,
          debugState: debugState,
          debugController: debugController,
        ),
      ],
    );
  }

  Widget _buildInspectorContents({
    required ThemeData theme,
    required SourceDebugState debugState,
    required SourceDebugController debugController,
  }) {
    final selectedChapterIdx = debugState.chapters.isEmpty
        ? 0
        : debugState.selectedChapterIndex.clamp(
            0,
            debugState.chapters.length - 1,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (debugState.chapters.isNotEmpty) ...[
          Row(
            children: [
              Text(
                '章节抽检 (${debugState.chapters.length} 章)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey<int>(selectedChapterIdx),
                  initialValue: selectedChapterIdx,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: debugState.chapters
                      .take(50)
                      .map(
                        (ch) => DropdownMenuItem<int>(
                          value: ch.chapterIndex,
                          child: Text(
                            ch.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: debugState.isRunning
                      ? null
                      : (idx) {
                          if (idx != null) {
                            unawaited(debugController.debugChapter(idx));
                          }
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Card(
          elevation: 0.5,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '原始正文快照',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  debugState.rawContent?.rawText ?? '运行调试后将在此展示抓取到的原始正文。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 0.5,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '净化后正文预览 (ContentSanitizer)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  debugState.sanitizedContent ?? '等待正文净化结果...',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepTraceCard extends StatelessWidget {
  final DebugStepReport report;

  const _StepTraceCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (report.step) {
      DebugStepKind.search => '1. 搜索 (search)',
      DebugStepKind.detail => '2. 详情 (detail)',
      DebugStepKind.toc => '3. 目录 (toc)',
      DebugStepKind.content => '4. 正文 (content)',
    };
    final statusLabel = switch (report.status) {
      DebugStepStatus.idle => '待执行',
      DebugStepStatus.running => '执行中',
      DebugStepStatus.success => '成功',
      DebugStepStatus.failed => '失败',
      DebugStepStatus.cancelled => '已取消',
      DebugStepStatus.skipped => '跳过',
    };
    final trace = report.trace;

    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trace?.httpStatus != null) ...[
                  _TagChip(
                    label: 'HTTP ${trace!.httpStatus}',
                    color: theme.colorScheme.secondaryContainer,
                  ),
                  const SizedBox(width: 6),
                ],
                if (trace != null) ...[
                  Text(
                    '${trace.elapsedMs}ms',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                _TagChip(
                  label: statusLabel,
                  color: switch (report.status) {
                    DebugStepStatus.success =>
                      theme.colorScheme.primaryContainer,
                    DebugStepStatus.failed => theme.colorScheme.errorContainer,
                    _ => theme.colorScheme.surfaceContainerHighest,
                  },
                ),
              ],
            ),
            if (report.summary != null) ...[
              const SizedBox(height: 4),
              Text(report.summary!, style: theme.textTheme.bodySmall),
            ],
            if (trace?.requestUrl != null && trace!.requestUrl!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'URL: ${trace.requestUrl}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (trace?.matchedPreview != null &&
                trace!.matchedPreview!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '命中预览: ${trace.matchedPreview}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (trace != null && trace.logs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                trace.logs.join(' | '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (report.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                report.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (report.stackPreview != null &&
                report.stackPreview!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                report.stackPreview!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReplaceRulesTab extends ConsumerStatefulWidget {
  const _ReplaceRulesTab();

  @override
  ConsumerState<_ReplaceRulesTab> createState() => _ReplaceRulesTabState();
}

class _ReplaceRulesTabState extends ConsumerState<_ReplaceRulesTab> {
  final TextEditingController _searchController = TextEditingController();
  late final TextEditingController _previewInputController;

  @override
  void initState() {
    super.initState();
    _previewInputController = TextEditingController(
      text: kDefaultSanitizePreviewSample,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _previewInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(replaceRulesControllerProvider);
    final controller = ref.read(replaceRulesControllerProvider.notifier);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopLayoutBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _buildRulesColumn(context, theme, state, controller),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildLivePreviewPanel(theme, state, controller),
                ),
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildRulesToolbar(context, state, controller),
            if (state.statusMessage != null || state.errorMessage != null) ...[
              const SizedBox(height: 8),
              _InlineBanner(
                errorMessage: state.errorMessage,
                statusMessage: state.statusMessage,
                onDismiss: controller.clearBanner,
              ),
            ],
            const SizedBox(height: 10),
            ..._buildRuleCards(context, theme, state, controller),
            const SizedBox(height: 16),
            _buildLivePreviewPanel(theme, state, controller),
          ],
        );
      },
    );
  }

  Widget _buildRulesColumn(
    BuildContext context,
    ThemeData theme,
    ReplaceRulesState state,
    ReplaceRulesController controller,
  ) {
    final rules = state.filteredRules;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildRulesToolbar(context, state, controller),
        ),
        if (state.statusMessage != null || state.errorMessage != null)
          _InlineBanner(
            errorMessage: state.errorMessage,
            statusMessage: state.statusMessage,
            onDismiss: controller.clearBanner,
          ),
        Expanded(
          child: rules.isEmpty
              ? Center(
                  child: Text(
                    '暂无匹配的净化规则',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _RuleCard(
                    rule: rules[index],
                    onToggle: () =>
                        unawaited(controller.toggleRuleEnabled(rules[index].id)),
                    onEdit: () => _showRuleEditorDialog(existing: rules[index]),
                    onDelete: () =>
                        unawaited(controller.deleteRule(rules[index].id)),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRulesToolbar(
    BuildContext context,
    ReplaceRulesState state,
    ReplaceRulesController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索规则名称或正则...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                ),
                onChanged: controller.setSearchQuery,
              ),
            ),
            FilledButton.icon(
              onPressed: _showRuleEditorDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增规则'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('全部作用域'),
              selected: state.scopeFilter == null,
              onSelected: (_) => controller.setScopeFilter(null),
            ),
            ChoiceChip(
              label: const Text('全局'),
              selected: state.scopeFilter == RuleScopeType.global,
              onSelected: (_) => controller.setScopeFilter(RuleScopeType.global),
            ),
            ChoiceChip(
              label: const Text('指定书源'),
              selected: state.scopeFilter == RuleScopeType.source,
              onSelected: (_) => controller.setScopeFilter(RuleScopeType.source),
            ),
            ChoiceChip(
              label: const Text('指定书籍'),
              selected: state.scopeFilter == RuleScopeType.book,
              onSelected: (_) => controller.setScopeFilter(RuleScopeType.book),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildRuleCards(
    BuildContext context,
    ThemeData theme,
    ReplaceRulesState state,
    ReplaceRulesController controller,
  ) {
    final rules = state.filteredRules;
    if (rules.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              '暂无匹配的净化规则',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ];
    }
    return rules
        .map(
          (rule) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RuleCard(
              rule: rule,
              onToggle: () => unawaited(controller.toggleRuleEnabled(rule.id)),
              onEdit: () => _showRuleEditorDialog(existing: rule),
              onDelete: () => unawaited(controller.deleteRule(rule.id)),
            ),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildLivePreviewPanel(
    ThemeData theme,
    ReplaceRulesState state,
    ReplaceRulesController controller,
  ) {
    final validSourceIds = state.availableSources.map((s) => s.id).toSet();
    final validBookIds = state.availableBooks.map((b) => b.id).toSet();
    final selectedSourceId =
        state.previewSourceId != null &&
            validSourceIds.contains(state.previewSourceId)
        ? state.previewSourceId
        : null;
    final selectedBookId =
        state.previewBookId != null &&
            validBookIds.contains(state.previewBookId)
        ? state.previewBookId
        : null;

    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '实时净化预览 (ContentSanitizer)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(controller.runPreview()),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: const Text('运行净化'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey<String?>('preview_src_$selectedSourceId'),
                    initialValue: selectedSourceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '模拟书源作用域',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('仅全局 / 不限书源'),
                      ),
                      ...state.availableSources.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      unawaited(
                        controller.updatePreviewContext(
                          sourceId: value,
                          clearSourceId: value == null,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey<String?>('preview_book_$selectedBookId'),
                    initialValue: selectedBookId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '模拟书籍作用域',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('不限书籍'),
                      ),
                      ...state.availableBooks.map(
                        (b) => DropdownMenuItem<String?>(
                          value: b.id,
                          child: Text(b.title, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      unawaited(
                        controller.updatePreviewContext(
                          bookId: value,
                          clearBookId: value == null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _previewInputController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '待净化原始文本',
                border: OutlineInputBorder(),
              ),
              onChanged: (text) =>
                  unawaited(controller.updatePreviewContext(rawText: text)),
            ),
            const SizedBox(height: 12),
            Text(
              '净化输出预览',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                state.previewSanitizedText,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRuleEditorDialog({ReplaceRule? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RuleEditorDialog(existing: existing),
    );
    if (saved == true && mounted) {
      await ref.read(replaceRulesControllerProvider.notifier).runPreview();
    }
  }
}

class _RuleEditorDialog extends ConsumerStatefulWidget {
  final ReplaceRule? existing;

  const _RuleEditorDialog({this.existing});

  @override
  ConsumerState<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends ConsumerState<_RuleEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _replaceCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _orderCtrl;

  late bool _isRegex;
  late RuleScopeType _scopeType;
  late bool _enabled;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _groupCtrl = TextEditingController(text: existing?.groupName ?? '通用');
    _patternCtrl = TextEditingController(text: existing?.pattern ?? '');
    _replaceCtrl = TextEditingController(text: existing?.replacement ?? '');
    _targetCtrl = TextEditingController(text: existing?.scopeTargetId ?? '');
    _orderCtrl = TextEditingController(text: '${existing?.sortOrder ?? 0}');
    _isRegex = existing?.isRegex ?? true;
    _scopeType = existing?.scopeType ?? RuleScopeType.global;
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _groupCtrl.dispose();
    _patternCtrl.dispose();
    _replaceCtrl.dispose();
    _targetCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? '新增净化规则' : '编辑净化规则'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '规则名称',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _patternCtrl,
                decoration: const InputDecoration(
                  labelText: '匹配模式（正则或纯文本）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _replaceCtrl,
                decoration: const InputDecoration(
                  labelText: '替换为（留空即删除）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<RuleScopeType>(
                      initialValue: _scopeType,
                      decoration: const InputDecoration(
                        labelText: '作用域',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const <DropdownMenuItem<RuleScopeType>>[
                        DropdownMenuItem(
                          value: RuleScopeType.global,
                          child: Text('全局 (global)'),
                        ),
                        DropdownMenuItem(
                          value: RuleScopeType.source,
                          child: Text('指定书源 (source)'),
                        ),
                        DropdownMenuItem(
                          value: RuleScopeType.book,
                          child: Text('指定书籍 (book)'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _scopeType = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _orderCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '排序权重',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              if (_scopeType != RuleScopeType.global) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _targetCtrl,
                  decoration: InputDecoration(
                    labelText: _scopeType == RuleScopeType.source
                        ? '目标书源 ID'
                        : '目标书籍 ID',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('正则表达式模式'),
                value: _isRegex,
                onChanged: (v) => setState(() => _isRegex = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('启用该规则'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              if (_validationError != null)
                Text(
                  _validationError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final err = ReplaceRulesController.validatePattern(
              _patternCtrl.text,
              isRegex: _isRegex,
            );
            if (_nameCtrl.text.trim().isEmpty) {
              setState(() => _validationError = '规则名称不能为空');
              return;
            }
            if (err != null) {
              setState(() => _validationError = err);
              return;
            }
            if (_scopeType != RuleScopeType.global &&
                _targetCtrl.text.trim().isEmpty) {
              setState(() => _validationError = '请输入目标作用域 ID');
              return;
            }
            final ok = await ref
                .read(replaceRulesControllerProvider.notifier)
                .saveRule(
                  id: existing?.id,
                  name: _nameCtrl.text,
                  groupName: _groupCtrl.text,
                  pattern: _patternCtrl.text,
                  replacement: _replaceCtrl.text,
                  isRegex: _isRegex,
                  scopeType: _scopeType,
                  scopeTargetId: _targetCtrl.text,
                  enabled: _enabled,
                  sortOrder: int.tryParse(_orderCtrl.text.trim()) ?? 0,
                );
            if (ok && context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  final ReplaceRule rule;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleCard({
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scopeText = switch (rule.scopeType) {
      RuleScopeType.global => '全局',
      RuleScopeType.source => '书源:${rule.scopeTargetId ?? ''}',
      RuleScopeType.book => '书籍:${rule.scopeTargetId ?? ''}',
    };

    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        rule.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _TagChip(
                        label: scopeText,
                        color: theme.colorScheme.secondaryContainer,
                      ),
                      _TagChip(
                        label: rule.isRegex ? '正则' : '文本',
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${rule.pattern}  ->  ${rule.replacement.isEmpty ? "<删除>" : rule.replacement}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: rule.enabled, onChanged: (_) => onToggle()),
            IconButton(
              tooltip: '编辑规则',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
            IconButton(
              tooltip: '删除规则',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TagChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _CheckStatusChip extends StatelessWidget {
  final SourceCheckStatus status;

  const _CheckStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      SourceCheckStatus.ok => ('正常', theme.colorScheme.primaryContainer),
      SourceCheckStatus.error => ('异常', theme.colorScheme.errorContainer),
      SourceCheckStatus.unsupported => (
        '暂不支持',
        theme.colorScheme.tertiaryContainer,
      ),
      SourceCheckStatus.unknown => (
        '未测',
        theme.colorScheme.surfaceContainerHighest,
      ),
    };
    return _TagChip(label: label, color: color);
  }
}

class _InlineBanner extends StatelessWidget {
  final String? errorMessage;
  final String? statusMessage;
  final VoidCallback onDismiss;

  const _InlineBanner({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: fgColor,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: fgColor),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: fgColor, size: 16),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
