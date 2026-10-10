import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 记忆曲线：把一串数值画成平滑面积折线（无第三方依赖）。
class MemoryCurve extends StatelessWidget {
  const MemoryCurve({
    super.key,
    required this.values,
    this.height = 40,
    this.color = ChinaColors.daiLan,
  });

  final List<int> values;
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

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.values, this.color);

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final n = values.length;

    Offset pt(int i) {
      final x = n == 1 ? size.width / 2 : size.width * i / (n - 1);
      final norm = maxV == 0 ? 0.0 : values[i] / maxV;
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
      Paint()..color = color.withValues(alpha: 0.15)..style = PaintingStyle.fill,
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
