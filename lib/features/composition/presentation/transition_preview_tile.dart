import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/transition_catalog.dart';
import '../domain/composition_models.dart';

/// A lightweight, generated A/B motion sample. Hover to animate; apply the
/// transition from the same card. The sample is illustrative; final export
/// remains rendered by DepthVibe's FFmpeg xfade pipeline.
class TransitionPreviewTile extends StatefulWidget {
  const TransitionPreviewTile({
    super.key,
    required this.kind,
    required this.onApply,
  });

  final TransitionKind kind;
  final VoidCallback onApply;

  @override
  State<TransitionPreviewTile> createState() => _TransitionPreviewTileState();
}

class _TransitionPreviewTileState extends State<TransitionPreviewTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _preview;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _preview = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
  }

  @override
  void didUpdateWidget(covariant TransitionPreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _preview.value = 0;
  }

  void _startPreview() {
    if (_hovered) return;
    setState(() => _hovered = true);
    _preview.repeat(reverse: true);
  }

  void _stopPreview() {
    if (!_hovered) return;
    setState(() => _hovered = false);
    _preview
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = TransitionCatalog.displayName(widget.kind);
    final nativeName = TransitionCatalog.xfadeName(widget.kind);

    return MouseRegion(
      onEnter: (_) => _startPreview(),
      onExit: (_) => _stopPreview(),
      child: AnimatedBuilder(
        animation: _preview,
        builder: (context, child) => Container(
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
          padding: const EdgeInsets.all(7),
          child: Row(
            children: [
              GestureDetector(
                onTap: _hovered ? _stopPreview : _startPreview,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CustomPaint(
                    size: const Size(104, 60),
                    painter: _TransitionSamplePainter(
                      kind: widget.kind,
                      progress: _preview.value,
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
                      title,
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
                      'FFmpeg · $nativeName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF93A5C0),
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hovered ? 'LIVE PREVIEW' : 'HOVER TO PREVIEW',
                      style: TextStyle(
                        color: _hovered
                            ? const Color(0xFFBBAEFF)
                            : const Color(0xFF7185A3),
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Apply $title',
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

class _TransitionSamplePainter extends CustomPainter {
  const _TransitionSamplePainter({
    required this.kind,
    required this.progress,
  });

  final TransitionKind kind;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final bounds = Offset.zero & size;

    _paintScene(canvas, size, second: false);
    final reveal = _revealPath(size, p);

    final isFade = kind == TransitionKind.dissolve ||
        kind == TransitionKind.fadeThroughColor ||
        kind == TransitionKind.fadeBlack ||
        kind == TransitionKind.fadeWhite ||
        kind == TransitionKind.fadeGrays ||
        kind == TransitionKind.fadeFast ||
        kind == TransitionKind.fadeSlow;
    canvas.saveLayer(
      bounds,
      Paint()..color = Colors.white.withOpacity(isFade ? p : 1),
    );
    canvas.clipPath(reveal);
    _paintScene(canvas, size, second: true);
    canvas.restore();

    if (kind == TransitionKind.pixelize && p > 0 && p < 1) {
      final grid = Paint()
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = 0.45;
      final cell = 7.0 + (1 - p) * 6;
      for (double x = 0; x < size.width; x += cell) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
      for (double y = 0; y < size.height; y += cell) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }

    final border = Paint()
      ..color = const Color(0x669FB3D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(5)),
      border,
    );
    _drawTag(canvas, 'A', const Offset(5, 4));
    _drawTag(canvas, 'B', Offset(size.width - 16, size.height - 15));
  }

  Path _revealPath(Size size, double p) {
    final w = size.width;
    final h = size.height;
    final name = kind.name.toLowerCase();

    Path rectangle(Rect rect) => Path()..addRect(rect);

    if (name.contains('circle')) {
      final closing = name.contains('close');
      final radius = math.sqrt(w * w + h * h) * (closing ? 1 - p : p);
      return Path()
        ..addOval(Rect.fromCircle(
          center: Offset(w / 2, h / 2),
          radius: radius,
        ));
    }

    if (name.contains('rectangle') || name.contains('rectcrop')) {
      final inset = (1 - p) * math.min(w, h) * 0.5;
      return rectangle(Rect.fromLTRB(inset, inset, w - inset, h - inset));
    }

    if (name.contains('verticalopen') || name.contains('vertopen')) {
      final width = w * p;
      return rectangle(Rect.fromLTRB(
        (w - width) / 2, 0, (w + width) / 2, h,
      ));
    }
    if (name.contains('verticalclose') || name.contains('vertclose')) {
      final width = w * (1 - p);
      return rectangle(Rect.fromLTRB(
        (w - width) / 2, 0, (w + width) / 2, h,
      ));
    }
    if (name.contains('horizontalopen') || name.contains('horzopen')) {
      final height = h * p;
      return rectangle(Rect.fromLTRB(
        0, (h - height) / 2, w, (h + height) / 2,
      ));
    }
    if (name.contains('horizontalclose') || name.contains('horzclose')) {
      final height = h * (1 - p);
      return rectangle(Rect.fromLTRB(
        0, (h - height) / 2, w, (h + height) / 2,
      ));
    }

    if (name.contains('wipe') || name.contains('slide') ||
        name.contains('cover') || name.contains('reveal')) {
      if (name.contains('right')) {
        return rectangle(Rect.fromLTRB(w * (1 - p), 0, w, h));
      }
      if (name.contains('up')) {
        return rectangle(Rect.fromLTRB(0, 0, w, h * p));
      }
      if (name.contains('down')) {
        return rectangle(Rect.fromLTRB(0, h * (1 - p), w, h));
      }
      return rectangle(Rect.fromLTRB(0, 0, w * p, h));
    }

    if (name.contains('diagonal') || name.contains('diag')) {
      final cornerTop = name.contains('top');
      final cornerLeft = name.contains('left');
      final tip = Offset(
        cornerLeft ? w * p : w * (1 - p),
        cornerTop ? h * p : h * (1 - p),
      );
      final corner = Offset(cornerLeft ? 0 : w, cornerTop ? 0 : h);
      final adjacentA = Offset(cornerLeft ? w : 0, cornerTop ? 0 : h);
      final adjacentB = Offset(cornerLeft ? 0 : w, cornerTop ? h : 0);
      return Path()
        ..moveTo(corner.dx, corner.dy)
        ..lineTo(adjacentA.dx, adjacentA.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(adjacentB.dx, adjacentB.dy)
        ..close();
    }

    if (name.contains('fade') || name == 'dissolve' || name == 'luma') {
      return rectangle(Offset.zero & size);
    }

    if (name.contains('smooth') || name.contains('blur') ||
        name.contains('distance') || name.contains('radial')) {
      final radius = math.sqrt(w * w + h * h) * p;
      return Path()
        ..addOval(Rect.fromCircle(
          center: Offset(w / 2, h / 2),
          radius: radius,
        ));
    }

    return Path()
      ..moveTo(0, 0)
      ..lineTo(w * p, 0)
      ..lineTo(w, h * p)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
  }

  void _paintScene(Canvas canvas, Size size, {required bool second}) {
    final rect = Offset.zero & size;
    final colors = second
        ? const [Color(0xFF0C6257), Color(0xFFB96847)]
        : const [Color(0xFF183D68), Color(0xFF70466F)];
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final sun = Paint()
      ..color = second ? const Color(0xFFFFD08A) : const Color(0xFFFFE0A0);
    canvas.drawCircle(
      Offset(size.width * (second ? 0.72 : 0.28), size.height * 0.34),
      size.height * 0.14,
      sun,
    );

    final mountain = Path()
      ..moveTo(0, size.height * 0.78)
      ..lineTo(size.width * 0.30, size.height * (second ? 0.36 : 0.48))
      ..lineTo(size.width * 0.52, size.height * 0.78)
      ..lineTo(size.width * 0.72, size.height * (second ? 0.44 : 0.56))
      ..lineTo(size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      mountain,
      Paint()..color = second
          ? const Color(0xFF124B4A)
          : const Color(0xFF243B59),
    );

    final foreground = Path()
      ..moveTo(0, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.60,
        size.width,
        size.height * 0.90,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      foreground,
      Paint()..color = second
          ? const Color(0xFF0C343C)
          : const Color(0xFF182B43),
    );
  }

  void _drawTag(Canvas canvas, String label, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 7,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TransitionSamplePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.kind != kind;
}
