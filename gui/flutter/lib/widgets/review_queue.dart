import 'package:flutter/material.dart';

import '../state/study_session.dart';
import '../theme/app_theme.dart';

/// 今日复习队列列表：已完成项淡化，当前项高亮。
class ReviewQueue extends StatelessWidget {
  const ReviewQueue({super.key, required this.session});

  final StudySession session;

  @override
  Widget build(BuildContext context) {
    final queue = session.engine.dailyQueue(userId: session.userId);
    final theme = Theme.of(context);

    return ListView.builder(
      primary: false,
      itemCount: queue.length,
      itemBuilder: (context, i) {
        final item = session.engine.itemById(queue[i].itemId);
        final isCurrent = i == session.done;
        final isDone = i < session.done;
        final color = isDone
            ? Kami.faint
            : (isCurrent ? Kami.inkBlue : Kami.ink);

        return ListTile(
          dense: true,
          selected: isCurrent,
          selectedTileColor: Kami.tint,
          leading: Text(
            '${i + 1}',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
          title: Text(
            item?.questionText ?? '(已删除)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              decoration: isDone ? TextDecoration.lineThrough : null,
            ),
          ),
          trailing: Text(
            queue[i].modeName,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        );
      },
    );
  }
}
