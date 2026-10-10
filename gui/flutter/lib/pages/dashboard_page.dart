import 'package:flutter/material.dart';

import '../ffi/wordcard.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../widgets/memory_curve.dart';
import '../widgets/task_bar_chart.dart';

/// 首页：记忆数据面板（总览 + 任务完成度 + 遗忘曲线 + 开始今日记忆）。
/// 排版遵循 Kami：暖米纸感底、单一油墨蓝强调、衬线标题、留白、细线。
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

  TextStyle _serif(double size, FontWeight w, Color c) => TextStyle(
      fontFamily: AppFonts.tsangerJinKai,
      fontSize: size,
      fontWeight: w,
      color: c,
      height: 1.4);

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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      children: [
        Text('记忆数据', style: _serif(30, FontWeight.w500, Kami.ink)),
        const SizedBox(height: 6),
        Container(width: 48, height: 3, color: Kami.inkBlue),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _stat('任务数', tasks.length),
            _stat('总词数', total),
            _stat('已记住', mastered, accent: true),
            _stat('未记住', notMemorized),
            _stat('完成度', completion, suffix: '%', accent: true),
            _stat('待复习', due),
          ],
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Kami.inkBlue,
              foregroundColor: Kami.parchment,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: onStartReview,
            icon: const Icon(Icons.play_arrow),
            label: Text('开始今日记忆（$due）'),
          ),
        ),
        const SizedBox(height: 40),
        _section(theme, '任务完成度'),
        const SizedBox(height: 12),
        TaskBarChart(
          bars: [
            for (final t in tasks)
              TaskBar(
                t.name,
                engine
                    .itemsByTag(t.tag)
                    .where((e) => status[e.id] == 2)
                    .length,
                t.count,
              ),
          ],
        ),
        const SizedBox(height: 40),
        _section(theme, '任务进度'),
        const SizedBox(height: 4),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('暂无任务：去「导入」添加电子书 / 词表 / 图片',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Kami.muted)),
          ),
        for (final t in tasks) _taskRow(context, theme, t, status),
        const SizedBox(height: 28),
        Text('引擎 libwordcard.so · v${engine.version}',
            style: theme.textTheme.bodySmall?.copyWith(color: Kami.faint)),
      ],
    );
  }

  Widget _section(ThemeData theme, String title) => Row(
        children: [
          Container(width: 3, height: 16, color: Kami.inkBlue),
          const SizedBox(width: 8),
          Text(title, style: _serif(18, FontWeight.w500, Kami.ink)),
        ],
      );

  Widget _stat(String label, int value,
      {String suffix = '', bool accent = false}) {
    return Container(
      width: 158,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Kami.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Kami.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value$suffix',
              style: _serif(30, FontWeight.w500,
                  accent ? Kami.inkBlue : Kami.ink)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Kami.muted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _taskRow(BuildContext context, ThemeData theme, TaskInfo t,
      Map<int, int> status) {
    final items = engine.itemsByTag(t.tag);
    final done = items.where((e) => status[e.id] == 2).length;
    final frac = items.isEmpty ? 0.0 : done / items.length;
    final curve = forgettingCurve(engine, userId, items, days: 30);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onOpenTask(t),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(t.name,
                        style: _serif(16, FontWeight.w500, Kami.ink)),
                  ),
                  Text('$done / ${items.length}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Kami.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 5,
              backgroundColor: Kami.hairline,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Kami.inkBlue),
            ),
          ),
          if (curve.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('遗忘曲线',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Kami.faint)),
                const SizedBox(width: 10),
                Expanded(
                  child: MemoryCurve(
                      values: curve, height: 34, color: Kami.inkBlue),
                ),
              ],
            ),
          ],
          const Divider(color: Kami.hairline, height: 20),
        ],
      ),
    );
  }
}
