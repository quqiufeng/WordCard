import 'package:flutter/material.dart';

import '../reader_library.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';

class ReaderChapterList extends StatelessWidget {
  const ReaderChapterList({
    super.key,
    required this.chapters,
    required this.selectedIndex,
    required this.onSelect,
    required this.onHide,
  });

  final List<ReaderChapter> chapters;
  final int selectedIndex;
  final void Function(int index) onSelect;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '目录 · ${chapters.length} 章',
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Kami.muted),
                ),
              ),
              IconButton(
                tooltip: '隐藏目录',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.keyboard_double_arrow_left),
                onPressed: onHide,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Kami.hairline),
        Expanded(
          child: ListView.builder(
            primary: false,
            itemCount: chapters.length,
            itemBuilder: (context, i) {
              final c = chapters[i];
              final selected = i == selectedIndex;
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: Kami.tint,
                leading: SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? Kami.inkBlue : Kami.faint,
                    ),
                  ),
                ),
                title: Text(
                  c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.tsangerJinKai,
                    fontSize: 14,
                    height: 1.35,
                    color: selected ? Kami.inkBlue : Kami.ink,
                  ),
                ),
                subtitle: Text('${c.pages.length} 页',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Kami.faint)),
                onTap: () => onSelect(i),
              );
            },
          ),
        ),
      ],
    );
  }
}
