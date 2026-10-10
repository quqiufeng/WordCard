import 'package:flutter/material.dart';

import '../state/study_session.dart';
import '../theme/app_theme.dart';

/// 学习统计看板：进度 / 剩余 / 最近一次评分结果。
class StatsWidget extends StatelessWidget {
  const StatsWidget({super.key, required this.session});

  final StudySession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = session.lastResult;
    final percent = session.total == 0 ? 0.0 : session.done / session.total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _metric(theme, '已复习', '${session.done}')),
            Expanded(child: _metric(theme, '剩余', '${session.total - session.done}')),
            Expanded(child: _metric(theme, '总计', '${session.total}')),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 6,
            backgroundColor: ChinaColors.border,
            valueColor:
                const AlwaysStoppedAnimation<Color>(ChinaColors.daiLan),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(theme, '综合', '${result.overall}%', ChinaColors.daiLan),
              _chip(theme, '识别', '${result.recognition}%', ChinaColors.muted),
              _chip(theme, '记忆', '${result.recall}%', ChinaColors.muted),
              _chip(theme, '间隔', '${result.intervalDays}天', ChinaColors.qinglv),
            ],
          ),
        ],
      ],
    );
  }

  Widget _metric(ThemeData theme, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: ChinaColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: ChinaColors.muted),
        ),
      ],
    );
  }

  Widget _chip(ThemeData theme, String label, String value, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ChinaColors.shuangdi,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ChinaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '$label $value',
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}
