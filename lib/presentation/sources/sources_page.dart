import 'package:flutter/material.dart';

import '../shells/section_placeholder.dart';

/// Placeholder book sources & sanitization workbench view.
class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: '书源',
      icon: Icons.extension_outlined,
      subtitle: 'JS 插件书源、Legado 兼容源与正文净化规则管理工作台。',
    );
  }
}
