import 'package:flutter/material.dart';

import '../shells/section_placeholder.dart';

/// Placeholder settings and local backup view.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: '设置',
      icon: Icons.settings_outlined,
      subtitle: '阅读主题预设、自定义字体导入与 .pureread.zip 本地整库备份。',
    );
  }
}
