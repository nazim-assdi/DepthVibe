import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/depthvibe_settings.dart';

import '../data/audio_preset_catalog.dart';
import '../data/motion_preset_catalog.dart';

enum CreativePresetPreviewKind { motion, audio, title, sticker }

/// Compact, hover-to-play preview card for non-effect creative assets.
class CreativePresetPreviewTile extends StatefulWidget {
  const CreativePresetPreviewTile({
    super.key,
    required this.title,
    required this.category,
    required this.description,
    required this.kind,
    required this.onApply,
    this.motionPreset,
    this.audioPreset,
    this.sampleText = '',
    this.sampleColor = const Color(0xFFFFFFFF),
    this.metric = '',
  });

  final String title;
  final String category;
  final String description;
  final CreativePresetPreviewKind kind;
  final VoidCallback? onApply;
  final MotionPresetDefinition? motionPreset;
  final AudioPresetDefinition? audioPreset;
  final String sampleText;
  final Color sampleColor;
  final String metric;

  @override
  State<CreativePresetPreviewTile> createState() =>
      _CreativePresetPreviewTileState();
}

class _CreativePresetPreviewTileState extends State<CreativePresetPreviewTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _preview;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _preview = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  void _start() {
    if (_hovered) return;
    setState(() => _hovered = true);
    _preview.repeat(reverse: true);
  }

  void _stop() {
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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return MouseRegion(
      onEnter: (_) => _start(),
      onExit: (_) => _stop(),
      child: AnimatedBuilder(
        animation: _preview,
        builder: (context, child) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: palette.panelRaised,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: _hovered ? palette.accent : palette.border,
              width: _hovered ? 1.2 : 0.8,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _hovered ? _stop : _start,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CustomPaint(
                    size: const Size(104, 60),
                    painter: _CreativePresetPainter(
                      kind: widget.kind,
                      progress: _preview.value,
                      motionPreset: widget.motionPreset,
                      audioPreset: widget.audioPreset,
                      sampleText: widget.sampleText,
                      sampleColor: widget.sampleColor,
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
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: palette.primaryText,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.category.toUpperCase() +
                          (widget.metric.isEmpty ? '' : ' · ${widget.metric}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: palette.secondaryText,
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7E91AD),
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hovered ? 'LIVE SAMPLE' : 'HOVER TO PREVIEW',
                      style: TextStyle(
                        color: _hovered
                            ? palette.accent
                            : palette.secondaryText,
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
                tooltip: 'Apply ${widget.title}',
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

class _CreativePresetPainter extends CustomPainter {
  const _CreativePresetPainter({
    required this.kind,
    required this.progress,
    required this.motionPreset,
    required this.audioPreset,
    required this.sampleText,
    required this.sampleColor,
  });

  final CreativePresetPreviewKind kind;
  final double progress;
  final MotionPresetDefinition? motionPreset;
  final AudioPresetDefinition? audioPreset;
  final String sampleText;
  final Color sampleColor;

  double _sample(String property, double progress, double fallback) {
    final track = motionPreset?.tracks
        .where((item) => item.property == property)
        .firstOrNull;
    if (track == null || track.frames.isEmpty) return fallback;
    final frames = [...track.frames]
      ..sort((a, b) => a.progress.compareTo(b.progress));
    if (progress <= frames.first.progress) return frames.first.value;
    if (progress >= frames.last.progress) return frames.last.value;
    for (var index = 0; index < frames.length - 1; index++) {
      final a = frames[index];
      final b = frames[index + 1];
      if (progress < a.progress || progress > b.progress) continue;
      final span = (b.progress - a.progress).abs();
      final t = span <= 0.000001
          ? 1.0
          : ((progress - a.progress) / span).clamp(0.0, 1.0);
      return a.value + (b.value - a.value) * t;
    }
    return fallback;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF243F64), Color(0xFF343052)],
        ).createShader(bounds),
    );

    switch (kind) {
      case CreativePresetPreviewKind.motion:
        _paintMotion(canvas, size);
        break;
      case CreativePresetPreviewKind.audio:
        _paintAudio(canvas, size);
        break;
      case CreativePresetPreviewKind.title:
      case CreativePresetPreviewKind.sticker:
        _paintTitle(canvas, size);
        break;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(5)),
      Paint()
        ..color = const Color(0x669FB3D0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
  }

  void _paintMotion(Canvas canvas, Size size) {
    final p = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final dx = _sample('position.x', p, 0);
    final dy = _sample('position.y', p, 0);
    final sx = _sample('scale.x', p, 1).clamp(0.08, 2.5).toDouble();
    final sy = _sample('scale.y', p, 1).clamp(0.08, 2.5).toDouble();
    final rotation = _sample('rotation.z', p, 0) * math.pi / 180;
    final opacity = (_sample('opacity', p, 100) / 100).clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(size.width * (0.5 + dx * 0.42), size.height * (0.5 + dy * 0.42));
    canvas.rotate(rotation);
    canvas.scale(sx, sy);
    final card = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 0.48,
      height: size.height * 0.50,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(6)),
      Paint()..color = Color.fromRGBO(116, 132, 255, opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card.deflate(4), const Radius.circular(4)),
      Paint()..color = Color.fromRGBO(231, 238, 255, opacity * 0.92),
    );
    canvas.drawCircle(
      Offset(0, -size.height * 0.04),
      size.height * 0.075,
      Paint()..color = Color.fromRGBO(45, 94, 142, opacity),
    );
    final line = Paint()
      ..color = Color.fromRGBO(68, 89, 132, opacity)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(-size.width * 0.12, size.height * 0.10),
      Offset(size.width * 0.12, size.height * 0.10),
      line,
    );
    canvas.restore();
  }

  void _paintAudio(Canvas canvas, Size size) {
    final preset = audioPreset;
    final gain = preset?.gainDb ?? 0;
    final low = preset?.lowEqDb ?? 0;
    final mid = preset?.midEqDb ?? 0;
    final high = preset?.highEqDb ?? 0;
    final fade = (preset?.fadeInMs ?? 0) > 0 || (preset?.fadeOutMs ?? 0) > 0;
    final center = size.height * 0.55;
    final barWidth = 2.0;
    final gap = 1.45;
    final count = (size.width / (barWidth + gap)).floor();
    for (var index = 0; index < count; index++) {
      final x = 5 + index * (barWidth + gap);
      final normalized = index / math.max(1, count - 1);
      final band = normalized < 0.34
          ? low
          : normalized < 0.68
              ? mid
              : high;
      final envelope = fade
          ? (normalized < 0.2 ? normalized / 0.2 : normalized > 0.8 ? (1-normalized)/0.2 : 1.0)
          : 1.0;
      final wave = (math.sin(index * 0.75 + progress * 4) * 0.18 + 0.60).abs();
      final height = (8 + wave * 24) *
          (1 + gain / 30).clamp(0.2, 1.8) *
          (1 + band / 24).clamp(0.25, 1.6) *
          (0.4 + envelope * 0.6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, center - height / 2, barWidth, height),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFF7FE1D1),
      );
    }
    final playheadX = size.width * (0.12 + progress * 0.76);
    canvas.drawLine(
      Offset(playheadX, 5),
      Offset(playheadX, size.height - 5),
      Paint()
        ..color = const Color(0xFFFFD78B)
        ..strokeWidth = 1.4,
    );
  }

  void _paintTitle(Canvas canvas, Size size) {
    final p = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final offsetY = (1 - p) * size.height * 0.18;
    final scale = 0.82 + p * 0.18;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + offsetY);
    canvas.scale(scale);
    final text = TextPainter(
      text: TextSpan(
        text: sampleText.isEmpty ? 'YOUR TITLE' : sampleText,
        style: TextStyle(
          fontSize: sampleText.length > 12 ? 9 : 12,
          color: sampleColor,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          shadows: const [
            Shadow(color: Color(0x88000000), blurRadius: 4, offset: Offset(1, 2)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      textAlign: TextAlign.center,
      ellipsis: '…',
    )..layout(maxWidth: size.width - 10);
    text.paint(canvas, Offset(-text.width/2, -text.height/2));
    canvas.restore();
    final progressWidth = size.width * p;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 3, progressWidth, 3),
      Paint()..color = sampleColor.withOpacity(0.75),
    );
  }

  @override
  bool shouldRepaint(covariant _CreativePresetPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.kind != kind ||
      oldDelegate.motionPreset != motionPreset ||
      oldDelegate.audioPreset != audioPreset ||
      oldDelegate.sampleText != sampleText ||
      oldDelegate.sampleColor != sampleColor;
}
