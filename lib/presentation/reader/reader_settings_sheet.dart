import 'package:flutter/material.dart';

import '../../application/reader/reader_session_state.dart';
import '../../application/reader/reader_theme_x.dart';
import '../../domain/domain.dart';

/// Typography, theme, layout, and platform hardware settings sheet.
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.state,
    required this.onSelectTheme,
    required this.onUpdateTheme,
    required this.onImportCustomFont,
    required this.onToggleKeepScreenOn,
    required this.onToggleVolumeKeyPaging,
    required this.onToggleSafeArea,
    required this.onToggleImmersive,
  });

  final ReaderSessionState state;
  final Future<void> Function(String themeId) onSelectTheme;
  final Future<void> Function(ReaderTheme updated) onUpdateTheme;
  final Future<void> Function() onImportCustomFont;
  final Future<void> Function() onToggleKeepScreenOn;
  final Future<void> Function() onToggleVolumeKeyPaging;
  final Future<void> Function() onToggleSafeArea;
  final Future<void> Function() onToggleImmersive;

  @override
  Widget build(BuildContext context) {
    final active = state.activeTheme;
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '排版与主题设置',
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
              const SizedBox(height: 12),
              Text('阅读主题', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in state.availableThemes)
                    ChoiceChip(
                      selected: item.id == active.id,
                      avatar: CircleAvatar(
                        backgroundColor: Color(item.bgColor),
                        radius: 9,
                      ),
                      label: Text(item.name),
                      onSelected: (_) => onSelectTheme(item.id),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.palette_outlined, size: 16),
                    label: const Text('自定义配色'),
                    onPressed: () => _showCustomColorDialog(context, active),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSliderRow(
                context,
                label: '字号',
                valueText: active.fontSize.toStringAsFixed(0),
                value: active.fontSize.clamp(12.0, 36.0),
                min: 12.0,
                max: 36.0,
                divisions: 24,
                onChanged: (v) =>
                    onUpdateTheme(active.copyWith(fontSize: v.roundToDouble())),
              ),
              _buildSliderRow(
                context,
                label: '行高倍率',
                valueText: active.lineHeight.toStringAsFixed(2),
                value: active.lineHeight.clamp(1.2, 2.4),
                min: 1.2,
                max: 2.4,
                divisions: 24,
                onChanged: (v) => onUpdateTheme(
                  active.copyWith(
                    lineHeight: double.parse(v.toStringAsFixed(2)),
                  ),
                ),
              ),
              _buildSliderRow(
                context,
                label: '段间距',
                valueText: active.paragraphSpacing.toStringAsFixed(0),
                value: active.paragraphSpacing.clamp(0.0, 32.0),
                min: 0.0,
                max: 32.0,
                divisions: 16,
                onChanged: (v) => onUpdateTheme(
                  active.copyWith(paragraphSpacing: v.roundToDouble()),
                ),
              ),
              _buildSliderRow(
                context,
                label: '字间距',
                valueText: active.letterSpacing.toStringAsFixed(1),
                value: active.letterSpacing.clamp(-0.5, 4.0),
                min: -0.5,
                max: 4.0,
                divisions: 18,
                onChanged: (v) => onUpdateTheme(
                  active.copyWith(
                    letterSpacing: double.parse(v.toStringAsFixed(1)),
                  ),
                ),
              ),
              _buildSliderRow(
                context,
                label: '左右边距',
                valueText: active.marginHorizontal.toStringAsFixed(0),
                value: active.marginHorizontal.clamp(8.0, 64.0),
                min: 8.0,
                max: 64.0,
                divisions: 14,
                onChanged: (v) => onUpdateTheme(
                  active.copyWith(marginHorizontal: v.roundToDouble()),
                ),
              ),
              _buildSliderRow(
                context,
                label: '上下边距',
                valueText: active.marginVertical.toStringAsFixed(0),
                value: active.marginVertical.clamp(8.0, 64.0),
                min: 8.0,
                max: 64.0,
                divisions: 14,
                onChanged: (v) => onUpdateTheme(
                  active.copyWith(marginVertical: v.roundToDouble()),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('字重', style: theme.textTheme.labelLarge),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 300, label: Text('细')),
                        ButtonSegment<int>(value: 400, label: Text('标准')),
                        ButtonSegment<int>(value: 500, label: Text('中')),
                        ButtonSegment<int>(value: 700, label: Text('粗')),
                      ],
                      selected: <int>{
                        const <int>[300, 400, 500, 700].contains(active.fontWeight)
                            ? active.fontWeight
                            : 400,
                      },
                      onSelectionChanged: (values) {
                        if (values.isNotEmpty) {
                          onUpdateTheme(
                            active.copyWith(fontWeight: values.first),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('分栏布局', style: theme.textTheme.labelLarge),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<ColumnMode>(
                      segments: const <ButtonSegment<ColumnMode>>[
                        ButtonSegment<ColumnMode>(
                          value: ColumnMode.auto,
                          label: Text('自动'),
                        ),
                        ButtonSegment<ColumnMode>(
                          value: ColumnMode.single,
                          label: Text('单栏'),
                        ),
                        ButtonSegment<ColumnMode>(
                          value: ColumnMode.double,
                          label: Text('双栏'),
                        ),
                      ],
                      selected: <ColumnMode>{active.columnMode},
                      onSelectionChanged: (values) {
                        if (values.isNotEmpty) {
                          onUpdateTheme(
                            active.copyWith(columnMode: values.first),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('翻页模式', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<PageTurnMode>(
                      showSelectedIcon: false,
                      segments: const <ButtonSegment<PageTurnMode>>[
                        ButtonSegment<PageTurnMode>(
                          value: PageTurnMode.none,
                          label: Text('无'),
                        ),
                        ButtonSegment<PageTurnMode>(
                          value: PageTurnMode.slide,
                          label: Text('平移'),
                        ),
                        ButtonSegment<PageTurnMode>(
                          value: PageTurnMode.cover,
                          label: Text('覆盖'),
                        ),
                        ButtonSegment<PageTurnMode>(
                          value: PageTurnMode.simulation,
                          label: Text('仿真'),
                        ),
                        ButtonSegment<PageTurnMode>(
                          value: PageTurnMode.scroll,
                          label: Text('滚动'),
                        ),
                      ],
                      selected: <PageTurnMode>{active.pageTurnMode},
                      onSelectionChanged: (values) {
                        if (values.isNotEmpty) {
                          onUpdateTheme(
                            active.copyWith(pageTurnMode: values.first),
                          );
                        }
                      },
                    ),
                  ),
                  if (active.pageTurnMode == PageTurnMode.simulation) ...[
                    const SizedBox(height: 6),
                    Text(
                      '仿真卷页：支持随指尖弯曲卷起、光泽折痕阴影与高帧率物理回弹',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '当前字体：${active.fontFamily == 'system' ? '系统默认' : active.fontFamily}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (active.fontFamily != 'system')
                    TextButton(
                      onPressed: () => onUpdateTheme(
                        active.copyWith(
                          fontFamily: 'system',
                          clearFontPath: true,
                        ),
                      ),
                      child: const Text('恢复默认'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onImportCustomFont,
                    icon: const Icon(Icons.font_download_outlined, size: 16),
                    label: const Text('导入 .ttf/.otf'),
                  ),
                ],
              ),
              const Divider(height: 24),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('段首双字缩进'),
                value: active.paragraphIndentChars > 0,
                onChanged: (enabled) => onUpdateTheme(
                  active.copyWith(paragraphIndentChars: enabled ? 2 : 0),
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('中文行尾标点避头尾禁则'),
                value: active.enablePunctuationHanging,
                onChanged: (enabled) => onUpdateTheme(
                  active.copyWith(enablePunctuationHanging: enabled),
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('中英文与数字混排微距'),
                value: active.enableCjkSpacing,
                onChanged: (enabled) => onUpdateTheme(
                  active.copyWith(enableCjkSpacing: enabled),
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('音量键翻页 (Android)'),
                value: state.volumeKeyPaging,
                onChanged: (_) => onToggleVolumeKeyPaging(),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('阅读时保持屏幕常亮'),
                value: state.keepScreenOn,
                onChanged: (_) => onToggleKeepScreenOn(),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('全面屏安全区边距'),
                value: state.safeAreaEnabled,
                onChanged: (_) => onToggleSafeArea(),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('全屏沉浸模式 (F11)'),
                value: state.isImmersive,
                onChanged: (_) => onToggleImmersive(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow(
    BuildContext context, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            valueText,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomColorDialog(
    BuildContext context,
    ReaderTheme active,
  ) async {
    const bgSwatches = <int>[
      0xFFF7F4EC,
      0xFFF2E6CE,
      0xFFE3EDCD,
      0xFFDCE7EE,
      0xFF1E2022,
      0xFF000000,
    ];
    const fgSwatches = <int>[
      0xFF2C2A26,
      0xFF3A2F23,
      0xFF1D3324,
      0xFFCFCFCF,
      0xFFB8B8B8,
      0xFFEAEAEA,
    ];
    var pickedBg = active.bgColor;
    var pickedFg = active.textColor;
    var pickedDark = active.isDark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('自定义阅读配色'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('背景颜色'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in bgSwatches)
                        InkWell(
                          onTap: () => setDialogState(() {
                            pickedBg = c;
                            pickedDark = Color(c).computeLuminance() < 0.3;
                          }),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: pickedBg == c ? 3 : 1,
                                color: pickedBg == c
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('文字颜色'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in fgSwatches)
                        InkWell(
                          onTap: () => setDialogState(() => pickedFg = c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: pickedFg == c ? 3 : 1,
                                color: pickedFg == c
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('深色主题模式'),
                    value: pickedDark,
                    onChanged: (v) => setDialogState(() => pickedDark = v),
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
                  child: const Text('应用'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      await onUpdateTheme(
        active.copyWith(
          id: active.isBuiltin ? 'custom_theme' : active.id,
          name: active.isBuiltin ? '自定义主题' : active.name,
          isBuiltin: false,
          isDark: pickedDark,
          bgColor: pickedBg,
          textColor: pickedFg,
          secondaryTextColor: pickedDark ? 0xFF8C9299 : 0xFF78736A,
        ),
      );
    }
  }
}
