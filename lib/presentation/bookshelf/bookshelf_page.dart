import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../shells/section_placeholder.dart';

/// Placeholder bookshelf view for Phase 3 foundation.
class BookshelfPage extends StatelessWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionPlaceholder(
      title: '书架',
      icon: Icons.menu_book_outlined,
      subtitle: 'PureRead 书架基础视图（支持本地 TXT 与统一 BookProvider 书源）。',
      action: FilledButton.icon(
        onPressed: () => context.push(AppRoutes.readerForBook('demo')),
        icon: const Icon(Icons.chrome_reader_mode_outlined),
        label: const Text('预览阅读器占位页'),
      ),
    );
  }
}
