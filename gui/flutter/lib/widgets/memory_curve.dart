import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ffi/wordcard.dart';
import '../theme/app_theme.dart';

/// 遗忘曲线：把一串数值（0..1）画成平滑面积折线（无第三方依赖）。
class MemoryCurve extends StatelessWidget {
  const MemoryCurve({
    super.key,
    required this.values,
    this.height = 40,
    this.color = Kami.inkBlue,
  });

  final List<double> values;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _CurvePainter(values, color)),
    );
  }
}

/// 计算某任务「遗忘曲线」：对每个已复习的词，按 R=exp(-t/S)（S≈间隔天数）
/// 求未来 days 天的记忆保持率均值。返回空表示**没有记忆数据**（不显示）。
List<double> forgettingCurve(
  WordCardEngine engine,
  int userId,
  List<ItemEntry> items, {
  int days = 30,
}) {
  final now = engine.now();
  final sums = List<double>.filled(days, 0);
  var n = 0;
  for (final it in items) {
    final m = engine.mastery(userId: userId, itemId: it.id);
    if (m == null || m.totalReviews == 0) continue;
    n++;
    final s = m.intervalDays <= 0 ? 1.0 : m.intervalDays.toDouble();
    final last = m.lastReview == 0 ? now : m.lastReview;
    for (var d = 0; d < days; d++) {
      final elapsed = (now - last) / 86400.0 + d;
      sums[d] += math.exp(-elapsed / s);
    }
  }
  if (n == 0) return const [];
  return [for (var d = 0; d < days; d++) sums[d] / n];
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0) return;
    final maxV = values.reduce(math.max);
    final max = maxV <= 0 ? 1.0 : maxV;
    final n = values.length;

    Offset pt(int i) {
      final x = n == 1 ? size.width / 2 : size.width * i / (n - 1);
      final norm = values[i] / max;
      final y = size.height - norm * (size.height - 4) - 2;
      return Offset(x, y);
    }

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 0; i < n - 1; i++) {
      final p0 = pt(i);
      final p1 = pt(i + 1);
      final midX = (p0.dx + p1.dx) / 2;
      line.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.values != values || old.color != color;
}
