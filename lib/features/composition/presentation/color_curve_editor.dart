import 'package:flutter/material.dart';

class ColorCurveEditor extends StatelessWidget {
  const ColorCurveEditor({
    super.key,
    required this.values,
    required this.onChanged,
  });

  final List<double> values;
  final ValueChanged<List<double>> onChanged;

  void _update(Offset local, Size size) {
    if (values.length != 5 || size.isEmpty) return;
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    final index = (x * 4).round().clamp(0, 4);
    final next = [...values];
    next[index] = (1 - local.dy / size.height)
        .clamp(0.0, 1.0)
        .toDouble();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 172);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => _update(details.localPosition, size),
          onPanUpdate: (details) => _update(details.localPosition, size),
          onTapDown: (details) => _update(details.localPosition, size),
          child: CustomPaint(
            size: size,
            painter: _ColorCurvePainter(values: values),
          ),
        );
      },
    );
  }
}

class _ColorCurvePainter extends CustomPainter {
  const _ColorCurvePainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF34445A)
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = const Color(0x665D718E)
        ..strokeWidth = 1,
    );
    if (values.length != 5) return;
    final points = <Offset>[
      for (var i = 0; i < 5; i++)
        Offset(
          size.width * i / 4,
          size.height * (1 - values[i].clamp(0.0, 1.0).toDouble()),
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final left = points[i];
      final right = points[i + 1];
      final mid = (left.dx + right.dx) / 2;
      path.cubicTo(
        left.dx + (mid - left.dx) * 0.65,
        left.dy,
        right.dx - (right.dx - mid) * 0.65,
        right.dy,
        right.dx,
        right.dy,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF84C9FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    for (final point in points) {
      canvas.drawCircle(point, 5.2, Paint()..color = const Color(0xFFEAF5FF));
      canvas.drawCircle(point, 3.1, Paint()..color = const Color(0xFF395C83));
    }
  }

  @override
  bool shouldRepaint(covariant _ColorCurvePainter oldDelegate) {
    if (oldDelegate.values.length != values.length) return true;
    for (var i = 0; i < values.length; i++) {
      if ((oldDelegate.values[i] - values[i]).abs() > 0.00001) {
        return true;
      }
    }
    return false;
  }
}
