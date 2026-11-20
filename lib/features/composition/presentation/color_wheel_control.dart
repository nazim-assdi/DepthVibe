import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Three-channel colour-balance vector used by the primary grading wheels.
class ColorWheelValue {
  const ColorWheelValue(this.red, this.green, this.blue);

  final double red;
  final double green;
  final double blue;
}

/// Compact hue/saturation wheel for Lift, Gamma, Gain and Offset controls.
///
/// The wheel emits RGB channel offsets in [-1, 1]. Dragging toward the rim
/// increases the colour cast; dragging toward the centre reduces it.
class ColorWheelControl extends StatelessWidget {
  const ColorWheelControl({
    super.key,
    required this.red,
    required this.green,
    required this.blue,
    required this.onChanged,
    this.diameter = 112,
  });

  final double red;
  final double green;
  final double blue;
  final ValueChanged<ColorWheelValue> onChanged;
  final double diameter;

  Offset _normalizedMarker() {
    final x = (2 * red - green - blue) / 3;
    final y = (green - blue) / math.sqrt(3);
    final length = math.sqrt(x * x + y * y);
    if (!length.isFinite || length <= 0.0001) return Offset.zero;
    final scale = length > 1 ? 1 / length : 1.0;
    return Offset(x * scale, y * scale);
  }

  void _update(Offset localPosition) {
    final center = diameter / 2;
    final radius = center - 5;
    final vector = Offset(
      (localPosition.dx - center) / radius,
      (center - localPosition.dy) / radius,
    );
    final distance = math.min(1.0, vector.distance).toDouble();
    if (distance <= 0.015) {
      onChanged(const ColorWheelValue(0, 0, 0));
      return;
    }
    final angle = math.atan2(vector.dy, vector.dx);
    onChanged(ColorWheelValue(
      distance * math.cos(angle),
      distance * math.cos(angle - 2 * math.pi / 3),
      distance * math.cos(angle + 2 * math.pi / 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final marker = _normalizedMarker();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: diameter,
          height: diameter,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _update(details.localPosition),
            onPanUpdate: (details) => _update(details.localPosition),
            onTapDown: (details) => _update(details.localPosition),
            child: CustomPaint(
              painter: _ColorWheelPainter(marker),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'R ${red.toStringAsFixed(2)}  G ${green.toStringAsFixed(2)}  B ${blue.toStringAsFixed(2)}',
          style: const TextStyle(
            color: Color(0xFF9DABC3),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  const _ColorWheelPainter(this.marker);

  final Offset marker;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2 - 5).toDouble();
    final rect = Rect.fromCircle(center: center, radius: radius);
    final wheelPaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF4C4C),
          Color(0xFFFFD84A),
          Color(0xFF63DD70),
          Color(0xFF42DBD4),
          Color(0xFF4C8CFF),
          Color(0xFFB56BFF),
          Color(0xFFFF4C4C),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, wheelPaint);

    final blendPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFFFFF).withValues(alpha: 0.96),
          const Color(0xFFFFFFFF).withValues(alpha: 0.72),
          const Color(0xFFFFFFFF).withValues(alpha: 0),
        ],
        stops: const [0, 0.48, 1],
      ).createShader(rect);
    canvas.drawCircle(center, radius, blendPaint);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF07101D),
    );

    final markerPoint = Offset(
      center.dx + marker.dx * radius,
      center.dy - marker.dy * radius,
    );
    canvas.drawCircle(
      markerPoint,
      6,
      Paint()
        ..color = const Color(0xFF101722)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      markerPoint,
      4,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      2,
      Paint()..color = const Color(0xFF29354A),
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) =>
      oldDelegate.marker != marker;
}
