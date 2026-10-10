import 'package:flutter/material.dart';

/// 电子书导入面板（占位，待接入 `importer`）。
class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('电子书导入', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'PDF / MOBI / AZW3 / EPUB / MD → 选词 → 复习',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
