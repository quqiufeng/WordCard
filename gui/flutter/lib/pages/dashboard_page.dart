import 'package:flutter/material.dart';

import '../ffi/wordcard.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_curve.dart';

/// 首页：记忆数据面板（总览 + 任务进度 + 开始今日记忆）。
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.engine,
    required this.userId,
    required this.onStartReview,
    required this.onOpenTask,
  });

  final WordCardEngine engine;
  final int userId;
  final VoidCallback onStartReview;
  final void Function(TaskInfo task) onOpenTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = engine.allItems();
    final now = engine.now();

    var mastered = 0, due = 0;
    final status = <int, int>{};
    for (final it in items) {
      final m = engine.mastery(userId: userId, itemId: it.id);
      final st = m?.status ?? 0;
      status[it.id] = st;
      if (st == 2) mastered++;
      final nr = m?.nextReview ?? 0;
      if (st != 2 && (nr == 0 || nr <= now)) due++;
    }
    final tasks = engine.tasks();
    final total = items.length;
    final notMemorized = total - mastered;
    final completion = total == 0 ? 0 : (mastered * 100 / total).round();

    return ListView(
      primary: false,
      padding: const EdgeInsets.all(24),
      children: [
        Text('记忆数据', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _stat(theme, '任务数', tasks.length, ChinaColors.daiLan),
            _stat(theme, '总词数', total, ChinaColors.ink),
            _stat(theme, '已记住', mastered, ChinaColors.qinglv),
            _stat(theme, '未记住', notMemorized, ChinaColors.zhusha),
            _stat(theme, '完成度', completion, ChinaColors.warn, suffix: '%'),
            _stat(theme, '待复习', due, ChinaColors.muted),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStartReview,
            icon: const Icon(Icons.play_arrow),
            label: Text('开始今日记忆（$due）'),
          ),
        ),
        const SizedBox(height: 32),
        Text('任务进度', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('暂无任务：去「导入」添加电子书 / 词表 / 图片',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: ChinaColors.muted)),
          ),
        for (final t in tasks) _taskRow(context, theme, t, status),
        const SizedBox(height: 24),
        Text('引擎 libwordcard.so · v${engine.version}',
            style: theme.textTheme.bodySmall?.copyWith(color: ChinaColors.dim)),
      ],
    );
  }

  Widget _stat(ThemeData theme, String label, int value, Color color,
      {String suffix = ''}) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ChinaColors.shuangdi,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChinaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value$suffix',
              style: theme.textTheme.headlineMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: ChinaColors.muted)),
        ],
      ),
    );
  }

  Widget _taskRow(BuildContext context, ThemeData theme, TaskInfo t,
      Map<int, int> status) {
    final items = engine.itemsByTag(t.tag);
    final done = items.where((e) => status[e.id] == 2).length;
    final frac = items.isEmpty ? 0.0 : done / items.length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(t.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: ChinaColors.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(ChinaColors.qinglv),
            ),
          ),
          const SizedBox(height: 4),
          Text('掌握 $done / ${items.length} · 记忆曲线（未来10天）',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: ChinaColors.muted)),
          const SizedBox(height: 2),
          MemoryCurve(values: _dueCurve(items, 10), height: 38),
        ],
      ),
      onTap: () => onOpenTask(t),
    );
  }

  /// 未来 N 天的复习量（用于记忆曲线）。
  List<int> _dueCurve(List<ItemEntry> items, int days) {
    final now = engine.now();
    final v = List<int>.filled(days, 0);
    for (final it in items) {
      final m = engine.mastery(userId: userId, itemId: it.id);
      final nr = m?.nextReview ?? 0;
      int d;
      if (nr == 0 || nr <= now) {
        d = 0;
      } else {
        d = ((nr - now) / 86400).ceil().clamp(0, days - 1);
      }
      v[d]++;
    }
    return v;
  }
}
