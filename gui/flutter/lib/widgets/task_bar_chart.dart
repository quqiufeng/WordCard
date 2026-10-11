import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TaskBar {
  const TaskBar(this.name, this.done, this.total);
  final String name;
  final int done;
  final int total;
  double get frac => total == 0 ? 0 : done / total;
}

/// 任务完成度柱状图：每个任务一根**窄竖柱**，高度 = 已掌握 / 总数。
/// 任务多时横向滚动。
class TaskBarChart extends StatelessWidget {
  const TaskBarChart({super.key, required this.bars, this.height = 170});

  final List<TaskBar> bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final maxBar = height - 66;

    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final b in bars)
              SizedBox(
                width: 84,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${(b.frac * 100).round()}%',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Kami.inkBlue)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: maxBar,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: 34,
                            height: 8 + b.frac * (maxBar - 8),
                            decoration: const BoxDecoration(
                              color: Kami.inkBlue,
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 32,
                        child: Text(
                          b.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Kami.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
