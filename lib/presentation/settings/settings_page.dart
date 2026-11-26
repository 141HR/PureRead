import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../application/backup/backup.dart';
import '../../domain/domain.dart';

const double _kSettingsTwoColumnBreakpoint = 820.0;

String _displayFileName(String rawPath) {
  final normalized = rawPath.replaceAll(r'\', '/');
  return p.posix.basename(normalized);
}

/// Adaptive PureRead settings, local `.pureread.zip` backup/restore, database
/// snapshot viewer, cache manager, theme/font entry, and MIT About page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(backupControllerProvider);
    final controller = ref.read(backupControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置与备份'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: state.isBusy ? null : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.isLoading || state.isBusy) const LinearProgressIndicator(),
          if (state.errorMessage != null || state.statusMessage != null)
            _SettingsBanner(
              errorMessage: state.errorMessage,
              statusMessage: state.statusMessage,
              onDismiss: controller.clearBanner,
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final backupCard = _BackupSectionCard(
                        state: state,
                        onToggleIncludeFonts: controller.setIncludeCustomFonts,
                        onExport: controller.exportBackup,
                        onExportToPath: () =>
                            _showCustomExportPathDialog(context, ref),
                        onPickAndInspect: () =>
                            _handlePickAndInspect(context, ref),
                      );
                      final snapshotsCard = _SnapshotsSectionCard(
                        snapshots: state.databaseSnapshots,
                      );
                      final cacheCard = _CacheSectionCard(
                        cacheStats: state.cacheStats,
                        isBusy: state.isBusy,
                        onClearCache: controller.clearChapterCache,
                      );
                      final themeFontCard = _ThemeAndFontCard(
                        state: state,
                        onSelectTheme: controller.selectTheme,
                        onImportFont: controller.importCustomFont,
                        onResetFont: controller.resetCustomFont,
                      );
                      const aboutCard = _AboutSectionCard();

                      if (constraints.maxWidth >=
                          _kSettingsTwoColumnBreakpoint) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  backupCard,
                                  const SizedBox(height: 16),
                                  snapshotsCard,
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                children: [
                                  cacheCard,
                                  const SizedBox(height: 16),
                                  themeFontCard,
                                  const SizedBox(height: 16),
                                  aboutCard,
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          backupCard,
                          const SizedBox(height: 16),
                          snapshotsCard,
                          const SizedBox(height: 16),
                          cacheCard,
                          const SizedBox(height: 16),
                          themeFontCard,
                          const SizedBox(height: 16),
                          aboutCard,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePickAndInspect(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = ref.read(backupControllerProvider.notifier);
    final manifest = await controller.pickAndInspectBackup();
    if (manifest == null || !context.mounted) return;

    final archivePath = ref.read(backupControllerProvider).inspectedArchivePath;
    if (archivePath == null) return;

    final mode = await showDialog<BackupRestoreMode>(
      context: context,
      builder: (dialogContext) => _RestorePreviewDialog(
        archivePath: archivePath,
        manifest: manifest,
      ),
    );

    if (!context.mounted) return;
    if (mode == null) {
      controller.clearInspectedBackup();
      return;
    }

    await controller.restoreBackup(mode: mode, archivePath: archivePath);
  }

  Future<void> _showCustomExportPathDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final pathResolver = ref.read(backupExportPathResolverProvider);
    final defaultPath = await pathResolver(DateTime.now().toUtc());
    if (!context.mounted) return;

    final textController = TextEditingController(text: defaultPath);
    String? chosenPath;
    try {
      chosenPath = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('指定备份导出路径'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(
              labelText: '目标归档文件路径',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(textController.text.trim()),
              child: const Text('开始导出'),
            ),
          ],
        ),
      );
    } finally {
      textController.dispose();
    }

    if (chosenPath == null || chosenPath.isEmpty || !context.mounted) return;
    await ref
        .read(backupControllerProvider.notifier)
        .exportBackup(targetArchivePath: chosenPath);
  }
}

class _SettingsBanner extends StatelessWidget {
  final String? errorMessage;
  final String? statusMessage;
  final VoidCallback onDismiss;

  const _SettingsBanner({
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

class _SectionCardShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCardShell({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
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
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _BackupSectionCard extends StatelessWidget {
  final BackupState state;
  final ValueChanged<bool> onToggleIncludeFonts;
  final Future<String?> Function() onExport;
  final VoidCallback onExportToPath;
  final VoidCallback onPickAndInspect;

  const _BackupSectionCard({
    required this.state,
    required this.onToggleIncludeFonts,
    required this.onExport,
    required this.onExportToPath,
    required this.onPickAndInspect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SectionCardShell(
      icon: Icons.archive_outlined,
      title: '本地整库备份与恢复',
      subtitle: '导出或校验导入 .pureread.zip 本地整库备份包',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '备份范围说明',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '包含：书架元数据、分组、阅读进度 (charOffset)、书签、书源、净化规则、阅读主题与设置。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '不包含：在线章节正文缓存及本地超大 TXT / EPUB 原始文件本身；恢复后若原本地路径变更，可在书架重新关联源文件，原阅读进度与书签完整保留。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('导出时打包自定义字体 (.ttf / .otf)'),
            value: state.includeCustomFonts,
            onChanged: state.isBusy ? null : onToggleIncludeFonts,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: state.isBusy ? null : onExport,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('导出备份'),
              ),
              OutlinedButton.icon(
                onPressed: state.isBusy ? null : onPickAndInspect,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导入并校验'),
              ),
              TextButton.icon(
                onPressed: state.isBusy ? null : onExportToPath,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('指定路径导出'),
              ),
            ],
          ),
          if (state.lastExportedPath != null) ...[
            const SizedBox(height: 12),
            Text(
              '最近导出：${state.lastExportedPath}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SnapshotsSectionCard extends StatelessWidget {
  final List<String> snapshots;

  const _SnapshotsSectionCard({required this.snapshots});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCardShell(
      icon: Icons.history_outlined,
      title: '数据库自动快照',
      subtitle: '升级迁移或执行备份恢复前自动生成，滚动保留最近 3 份安全快照',
      child: snapshots.isEmpty
          ? Text(
              '暂无历史快照（执行数据库升级或备份恢复前将自动生成）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < snapshots.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.storage_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      _displayFileName(snapshots[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      snapshots[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: i == 0
                        ? Chip(
                            label: const Text('最新'),
                            visualDensity: VisualDensity.compact,
                            labelStyle: theme.textTheme.labelSmall,
                          )
                        : null,
                  ),
              ],
            ),
    );
  }
}

class _CacheSectionCard extends StatelessWidget {
  final CacheStats cacheStats;
  final bool isBusy;
  final VoidCallback onClearCache;

  const _CacheSectionCard({
    required this.cacheStats,
    required this.isBusy,
    required this.onClearCache,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeLabel = formatByteSize(cacheStats.totalBytes);

    return _SectionCardShell(
      icon: Icons.cleaning_services_outlined,
      title: '章节缓存管理',
      subtitle: '清理在线章节正文缓存与临时文件，不影响书架、阅读进度与书签',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sizeLabel,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '已缓存 ${cacheStats.cachedFileCount} 个在线章节文件',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: isBusy ? null : onClearCache,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('清理章节缓存'),
          ),
        ],
      ),
    );
  }
}

class _ThemeAndFontCard extends StatelessWidget {
  final BackupState state;
  final ValueChanged<String> onSelectTheme;
  final VoidCallback onImportFont;
  final VoidCallback onResetFont;

  const _ThemeAndFontCard({
    required this.state,
    required this.onSelectTheme,
    required this.onImportFont,
    required this.onResetFont,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = state.activeTheme;
    final currentFontLabel = (active == null || active.fontFamily == 'system')
        ? '系统默认字体'
        : active.fontFamily;

    return _SectionCardShell(
      icon: Icons.palette_outlined,
      title: '阅读主题与字体',
      subtitle: '预设阅读配色、排版主题切换与本地自定义字体管理',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.availableThemes.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in state.availableThemes)
                  ChoiceChip(
                    selected: item.id == active?.id,
                    avatar: CircleAvatar(
                      backgroundColor: Color(item.bgColor),
                      radius: 9,
                    ),
                    label: Text(item.name),
                    onSelected: state.isBusy
                        ? null
                        : (_) => onSelectTheme(item.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前主题：${active?.name ?? '米白护眼'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '当前字体：$currentFontLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: state.isBusy ? null : onImportFont,
                    icon: const Icon(Icons.font_download_outlined, size: 18),
                    label: const Text('导入字体'),
                  ),
                  if (active != null && active.fontFamily != 'system')
                    TextButton(
                      onPressed: state.isBusy ? null : onResetFont,
                      child: const Text('恢复默认'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutSectionCard extends StatelessWidget {
  const _AboutSectionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCardShell(
      icon: Icons.verified_user_outlined,
      title: '关于 PureRead（净读）',
      subtitle: '专注纯本地极致单机阅读与安全可控数据主权',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoKeyValueRow(label: '应用版本', value: 'v0.5.0+5'),
          const SizedBox(height: 6),
          const _InfoKeyValueRow(
            label: '开源协议',
            value: 'MIT License',
          ),
          const SizedBox(height: 10),
          Text(
            '零遥测与隐私承诺：PureRead 100% 本地运行，内置零第三方统计或遥测上报；除您自行配置并主动触发的在线书源请求外，绝不主动发起任何外部联网通信。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '合规声明：本软件为纯本地阅读与规则解析工具，不内置任何小说内容与默认书源。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoKeyValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoKeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _RestorePreviewDialog extends StatelessWidget {
  final String archivePath;
  final BackupManifest manifest;

  const _RestorePreviewDialog({
    required this.archivePath,
    required this.manifest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = manifest.recordCounts;
    final exportedLocal = manifest.exportedAt.toLocal();
    final exportedText =
        '${exportedLocal.year.toString().padLeft(4, '0')}-'
        '${exportedLocal.month.toString().padLeft(2, '0')}-'
        '${exportedLocal.day.toString().padLeft(2, '0')} '
        '${exportedLocal.hour.toString().padLeft(2, '0')}:'
        '${exportedLocal.minute.toString().padLeft(2, '0')}:'
        '${exportedLocal.second.toString().padLeft(2, '0')}';

    final summaryEntries = <(String, int)>[
      ('书架分组', counts['book_groups'] ?? 0),
      ('书籍', counts['books'] ?? 0),
      ('阅读进度', counts['reading_progress'] ?? 0),
      ('书签', counts['bookmarks'] ?? 0),
      ('书源', counts['book_sources'] ?? 0),
      ('净化规则', counts['replace_rules'] ?? 0),
      ('阅读主题', counts['reader_themes'] ?? 0),
      ('全局设置', counts['app_settings'] ?? 0),
      ('自定义字体', counts['fonts'] ?? 0),
    ];

    return AlertDialog(
      title: const Text('备份包校验通过'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayFileName(archivePath),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _InfoKeyValueRow(
                label: '格式版本',
                value: 'v${manifest.formatVersion}',
              ),
              const SizedBox(height: 4),
              _InfoKeyValueRow(label: '应用版本', value: manifest.appVersion),
              const SizedBox(height: 4),
              _InfoKeyValueRow(
                label: 'Schema',
                value: 'v${manifest.schemaVersion}',
              ),
              const SizedBox(height: 4),
              _InfoKeyValueRow(label: '导出时间', value: exportedText),
              const Divider(height: 20),
              Text(
                '包含记录统计',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in summaryEntries)
                    Chip(
                      label: Text('${entry.$1}: ${entry.$2}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '提示：执行恢复前将自动生成当前数据库的安全快照；覆盖恢复会清空本地现有书架与配置并替换为备份内容，合并恢复会保留本地其余记录并合并导入。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(BackupRestoreMode.merge),
          child: const Text('合并恢复'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(BackupRestoreMode.overwrite),
          child: const Text('覆盖恢复'),
        ),
      ],
    );
  }
}
