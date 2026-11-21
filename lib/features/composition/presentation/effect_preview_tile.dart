import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/effect_catalog.dart';

/// Animated, generated visual thumbnail for an effect. It demonstrates the
/// character of an effect; the final image is still rendered by the native
/// DepthVibe filter pipeline.
class EffectPreviewTile extends StatefulWidget {
  const EffectPreviewTile({
    super.key,
    required this.effect,
    required this.onApply,
    this.titleOverride,
    this.subtitleOverride,
  });

  final EffectDefinition effect;
  final VoidCallback? onApply;
  final String? titleOverride;
  final String? subtitleOverride;

  @override
  State<EffectPreviewTile> createState() => _EffectPreviewTileState();
}

class _EffectPreviewTileState extends State<EffectPreviewTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  void _startPreview() {
    if (_hovered) return;
    setState(() => _hovered = true);
    _animation.repeat(reverse: true);
  }

  void _stopPreview() {
    if (!_hovered) return;
    setState(() => _hovered = false);
    _animation
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.effect;
    return MouseRegion(
      onEnter: (_) => _startPreview(),
      onExit: (_) => _stopPreview(),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFF172234),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF927BFF)
                  : const Color(0xFF34445D),
              width: _hovered ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _hovered ? _stopPreview : _startPreview,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CustomPaint(
                    size: const Size(104, 60),
                    painter: _EffectSamplePainter(
                      effectId: effect.id,
                      progress: _animation.value,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.titleOverride ?? effect.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE9EFFA),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitleOverride ?? (effect.category + ' · ' + effect.ffmpegFilter),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF93A5C0),
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hovered ? 'LIVE EFFECT PREVIEW' : 'HOVER TO PREVIEW',
                      style: TextStyle(
                        color: _hovered
                            ? const Color(0xFFBBAEFF)
                            : const Color(0xFF7185A3),
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.55,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Add ' + (widget.titleOverride ?? effect.name),
                onPressed: widget.onApply,
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Color(0xFFBBAEFF),
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EffectSamplePainter extends CustomPainter {
  const _EffectSamplePainter({
    required this.effectId,
    required this.progress,
  });

  final String effectId;
  final double progress;

  static const _grayscaleMatrix = <double>[
    0.213, 0.715, 0.072, 0, 0,
    0.213, 0.715, 0.072, 0, 0,
    0.213, 0.715, 0.072, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static const _sepiaMatrix = <double>[
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static const _invertMatrix = <double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final p = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final bounds = Offset.zero & size;
    final id = effectId.toLowerCase();

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(5)),
    );

    final mirrored = id == 'mirror';
    final flipped = id == 'flip';
    if (mirrored || flipped) {
      canvas.translate(mirrored ? size.width : 0, flipped ? size.height : 0);
      canvas.scale(mirrored ? -1 : 1, flipped ? -1 : 1);
    }

    ui.ColorFilter? filter;
    if (id == 'grayscale') {
      filter = const ui.ColorFilter.matrix(_grayscaleMatrix);
    } else if (id == 'sepia' || id == 'old_film') {
      filter = const ui.ColorFilter.matrix(_sepiaMatrix);
    } else if (id == 'invert') {
      filter = const ui.ColorFilter.matrix(_invertMatrix);
    }

    if (filter == null) {
      _paintScene(canvas, size, id, p);
    } else {
      canvas.saveLayer(bounds, Paint()..colorFilter = filter);
      _paintScene(canvas, size, id, p);
      canvas.restore();
    }

    if (id == 'pixelate') _paintPixelGrid(canvas, size, p);
    if (id == 'scanlines' || id == 'vhs_warp' || id == 'analog_glitch') {
      _paintScanlines(canvas, size, p);
    }
    if (id == 'film_grain' || id == 'old_film' || id == 'analog_glitch') {
      _paintGrain(canvas, size, p);
    }
    if (id == 'vignette' || id == 'old_film') {
      _paintVignette(canvas, size, p);
    }
    if (id == 'letterbox') {
      final bar = size.height * 0.13;
      final paint = Paint()..color = Colors.black;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, bar), paint);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - bar, size.width, bar),
        paint,
      );
    }
    if (id == 'frame_border') {
      canvas.drawRect(
        Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
        Paint()
          ..color = Colors.white.withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (id == 'camera_flash' || id == 'exposure' || id == 'brightness') {
      canvas.drawRect(
        bounds,
        Paint()
          ..color = Colors.white.withOpacity(
            id == 'camera_flash' ? 0.1 + p * 0.55 : 0.12,
          ),
      );
    }
    if (id == 'chromatic_aberration' || id == 'rgb_split' ||
        id == 'analog_glitch') {
      _paintChannelFringe(canvas, size, p);
    }
    if (id == 'wave_distortion' || id == 'heat_haze' ||
        id == 'displacement') {
      _paintWaveGuides(canvas, size, p);
    }
    if (id == 'glow' || id == 'edge_glow') {
      canvas.drawCircle(
        Offset(size.width * 0.28, size.height * 0.32),
        size.height * (0.17 + p * 0.08),
        Paint()
          ..color = const Color(0x99FFE4A3)
          ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.normal,
            3 + p * 5,
          ),
      );
    }
    if (id == 'fisheye' || id == 'lens_distortion') {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: size.width * (0.70 + p * 0.08),
          height: size.height * (0.64 + p * 0.1),
        ),
        Paint()
          ..color = Colors.white.withOpacity(0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    final border = Paint()
      ..color = const Color(0x669FB3D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(5)),
      border,
    );
    canvas.restore();
  }

  void _paintScene(Canvas canvas, Size size, String id, double p) {
    final rect = Offset.zero & size;
    final isWarm = id == 'old_film' || id == 'sepia' || id == 'bleach_bypass';
    final colors = isWarm
        ? const [Color(0xFF9D633F), Color(0xFF523A39)]
        : const [Color(0xFF183D68), Color(0xFF70466F)];
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final blur = id.contains('blur') || id == 'soften' || id == 'glow';
    final sunColor = id == 'camera_flash'
        ? Colors.white
        : const Color(0xFFFFD58B);
    canvas.drawCircle(
      Offset(size.width * 0.29, size.height * 0.34),
      size.height * (0.14 + (id == 'pulse' ? p * 0.03 : 0)),
      Paint()
        ..color = sunColor
        ..maskFilter = blur
            ? const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.5)
            : null,
    );

    final back = Path()
      ..moveTo(0, size.height * 0.77)
      ..lineTo(size.width * 0.28, size.height * (0.41 - p * 0.025))
      ..lineTo(size.width * 0.49, size.height * 0.78)
      ..lineTo(size.width * 0.74, size.height * 0.48)
      ..lineTo(size.width, size.height * 0.78)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      back,
      Paint()
        ..color = id == 'edge_detect'
            ? Colors.white
            : const Color(0xFF243B59),
        ..style = id == 'edge_detect' ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1.2,
    );

    final front = Path()
      ..moveTo(0, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.52,
        size.height * (0.60 + p * 0.025),
        size.width,
        size.height * 0.90,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      front,
      Paint()..color = const Color(0xFF102A43),
    );

    if (id == 'contrast' || id == 'bleach_bypass' || id == 'threshold') {
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.black.withOpacity(0.16 + p * 0.08)
          ..blendMode = BlendMode.softLight,
      );
    }
  }

  void _paintPixelGrid(Canvas canvas, Size size, double p) {
    final step = 5.0 + p * 4;
    final paint = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 0.45;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintScanlines(Canvas canvas, Size size, double p) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.32 + p * 0.12)
      ..strokeWidth = 0.7;
    for (double y = 2; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintGrain(Canvas canvas, Size size, double p) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.18 + p * 0.15);
    for (var i = 0; i < 42; i++) {
      final x = ((i * 37 + (p * 17).round()) % 101) / 101 * size.width;
      final y = ((i * 61 + (p * 11).round()) % 97) / 97 * size.height;
      canvas.drawCircle(Offset(x, y), i % 3 == 0 ? 0.8 : 0.45, paint);
    }
  }

  void _paintVignette(Canvas canvas, Size size, double p) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.42 + p * 0.22),
          ],
          stops: const [0.48, 1],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width / 2, size.height / 2),
            radius: size.width * 0.68,
          ),
        ),
    );
  }

  void _paintChannelFringe(Canvas canvas, Size size, double p) {
    final shift = 1.0 + p * 2.4;
    final paint = Paint()..color = const Color(0x7771DFFF);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.68 + shift, 0, 2, size.height),
      paint,
    );
    paint.color = const Color(0x77FF6D9B);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.68 - shift, 0, 2, size.height),
      paint,
    );
    if (effectId == 'analog_glitch') {
      paint.color = Colors.white.withOpacity(0.34);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * (0.30 + p * 0.2), size.width, 2),
        paint,
      );
    }
  }

  void _paintWaveGuides(Canvas canvas, Size size, double p) {
    final path = Path();
    final offset = p * 5;
    for (double x = 0; x <= size.width; x += 2) {
      final y = size.height * 0.55 +
          math.sin(x / 12 + offset) * (2 + p * 3);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x99A9EDFF)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _EffectSamplePainter oldDelegate) =>
      oldDelegate.effectId != effectId || oldDelegate.progress != progress;
}
