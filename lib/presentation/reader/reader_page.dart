import 'package:flutter/material.dart';

import '../../app/providers.dart';

/// Placeholder adaptive reader canvas demonstrating narrow single-column and
/// wide two-column layout switching.
class ReaderPage extends StatelessWidget {
  final String bookId;

  const ReaderPage({
    super.key,
    required this.bookId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('阅读器 ($bookId)'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTwoColumn = constraints.maxWidth >= kDesktopLayoutBreakpoint;
          if (!isTwoColumn) {
            return _buildReaderColumn(
              theme,
              label: '单栏阅读画布占位区域（基于 charOffset 锚点与中文避头尾排版）',
            );
          }
          return Row(
            children: [
              Expanded(
                child: _buildReaderColumn(
                  theme,
                  label: '左栏逻辑页 P(2k)',
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _buildReaderColumn(
                  theme,
                  label: '右栏逻辑页 P(2k+1)',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReaderColumn(ThemeData theme, {required String label}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          label,
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
