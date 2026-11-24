import 'package:flutter/material.dart';

import '../shells/section_placeholder.dart';

/// Placeholder multi-source search view for Phase 3 foundation.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: '搜索',
      icon: Icons.search_outlined,
      subtitle: '多源聚合搜索与一键换源入口（将在 Phase 4 M2 接入）。',
    );
  }
}
