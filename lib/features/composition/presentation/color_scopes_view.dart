import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../domain/composition_models.dart';
import '../engine/color_grade_preview.dart';

enum ColorScopeMode { waveform, rgbParade, vectorscope }

class ColorScopesView extends StatelessWidget {
  const ColorScopesView({
    super.key,
    required this.image,
    required this.mode,
    required this.grade,
    required this.timeMs,
  });

  final img.Image image;
  final ColorScopeMode mode;
  final EffectInstance? grade;
  final int timeMs;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF080D14),
        border: Border.all(color: const Color(0xFF2A3548)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        painter: _ColorScopePainter(
          image: image,
          mode: mode,
          grade: grade,
          timeMs: timeMs,
        ),
        child: const SizedBox(height: 112, width: double.infinity),
      ),
    );
  }
}

class _ColorScopePainter extends CustomPainter {
  const _ColorScopePainter({
    required this.image,
    required this.mode,
    required this.grade,
    required this.timeMs,
  });

  final img.Image image;
  final ColorScopeMode mode;
  final EffectInstance? grade;
  final int timeMs;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    final grid = Paint()
      ..color = const Color(0xFF263446)
      ..strokeWidth = 0.7;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (mode == ColorScopeMode.vectorscope) {
      final center = Offset(size.width / 2, size.height / 2);
      final radius = math.min(size.width, size.height).toDouble() * 0.43;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xFF40546C)
          ..style = PaintingStyle.stroke,
      );
      canvas.drawLine(
        Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy),
        grid,
      );
      canvas.drawLine(
        Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius),
        grid,
      );
    }

    final points = <Color, List<Offset>>{};
    final paradeColors = const [
      Color(0xFFFF7777),
      Color(0xFF70E49A),
      Color(0xFF79AFFF),
    ];
    final stepX = math.max(1, image.width ~/ 150).toInt();
    final stepY = math.max(1, image.height ~/ 90).toInt();
    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        final pixel = image.getPixel(x, y);
        final rgb = ColorGradePreview.applyRgb(
          [
            (pixel.r.toDouble() / 255).clamp(0, 1).toDouble(),
            (pixel.g.toDouble() / 255).clamp(0, 1).toDouble(),
            (pixel.b.toDouble() / 255).clamp(0, 1).toDouble(),
          ],
          grade,
          timeMs,
        );
        final red = rgb[0];
        final green = rgb[1];
        final blue = rgb[2];
        final nx = image.width <= 1 ? 0.5 : x / (image.width - 1);
        final luma = red * 0.2126 + green * 0.7152 + blue * 0.0722;

        switch (mode) {
          case ColorScopeMode.waveform:
            (points[const Color(0xFFB8F2D4)] ??= <Offset>[]).add(
              Offset(nx * size.width, (1 - luma) * size.height),
            );
            break;
          case ColorScopeMode.rgbParade:
            final bandWidth = size.width / 3;
            final values = [red, green, blue];
            for (var channel = 0; channel < 3; channel++) {
              (points[paradeColors[channel]] ??= <Offset>[]).add(
                Offset(
                  (channel + nx) * bandWidth,
                  (1 - values[channel]) * size.height,
                ),
              );
            }
            break;
          case ColorScopeMode.vectorscope:
            final cb = (blue - luma) * 0.564;
            final cr = (red - luma) * 0.713;
            final radius = math.min(size.width, size.height) * 0.43;
            final center = Offset(size.width / 2, size.height / 2);
            (points[const Color(0xFF8DDCF4)] ??= <Offset>[]).add(
              Offset(
                center.dx + cr * radius * 2,
                center.dy - cb * radius * 2,
              ),
            );
            break;
        }
      }
    }

    for (final entry in points.entries) {
      canvas.drawPoints(
        ui.PointMode.points,
        entry.value,
        Paint()
          ..color = entry.key.withValues(alpha: 0.72)
          ..strokeWidth = mode == ColorScopeMode.vectorscope ? 1.6 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    final label = switch (mode) {
      ColorScopeMode.waveform => 'LUMA WAVEFORM',
      ColorScopeMode.rgbParade => 'RGB PARADE',
      ColorScopeMode.vectorscope => 'VECTORSCOPE',
    };
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF9AAAC0),
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, const Offset(6, 5));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ColorScopePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.mode != mode ||
      oldDelegate.grade != grade ||
      oldDelegate.timeMs != timeMs;
}
