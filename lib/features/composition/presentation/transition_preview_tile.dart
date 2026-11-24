
import 'package:flutter/material.dart';

import '../../../app/depthvibe_settings.dart';

import '../data/transition_catalog.dart';
import '../domain/composition_models.dart';
import 'transition_live_preview.dart';

/// A lightweight, generated A/B motion sample. Hover to animate; apply the
/// transition from the same card. The sample is illustrative; final export
/// remains rendered by DepthVibe's FFmpeg xfade pipeline.
class TransitionPreviewTile extends StatefulWidget {
  const TransitionPreviewTile({
    super.key,
    required this.kind,
    required this.onApply,
    this.titleOverride,
    this.subtitleOverride,
  });

  final TransitionKind kind;
  final VoidCallback? onApply;
  final String? titleOverride;
  final String? subtitleOverride;

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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;

    return MouseRegion(
      onEnter: (_) => _startPreview(),
      onExit: (_) => _stopPreview(),
      child: AnimatedBuilder(
        animation: _preview,
        builder: (context, child) => Container(
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
          padding: const EdgeInsets.all(7),
          child: Row(
            children: [
              GestureDetector(
                onTap: _hovered ? _stopPreview : _startPreview,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 104,
                    height: 60,
                    child: _TransitionSampleWidget(
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
                      widget.titleOverride ?? title,
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
                      widget.subtitleOverride ?? ('FFmpeg · ' + nativeName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: palette.secondaryText,
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hovered ? 'LIVE PREVIEW' : 'HOVER TO PREVIEW',
                      style: TextStyle(
                        color: _hovered
                            ? palette.accent
                            : palette.secondaryText,
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
                tooltip: 'Apply ' + (widget.titleOverride ?? title),
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

class _TransitionSampleWidget extends StatelessWidget {
  const _TransitionSampleWidget({
    required this.kind,
    required this.progress,
  });

  final TransitionKind kind;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const size = Size(104, 60);
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Stack(
        fit: StackFit.expand,
        children: [
          TransitionLivePreview.apply(
            child: const CustomPaint(
              painter: _TransitionScenePainter(second: false),
            ),
            kind: kind,
            progress: progress,
            incoming: false,
            size: size,
          ),
          TransitionLivePreview.apply(
            child: const CustomPaint(
              painter: _TransitionScenePainter(second: true),
            ),
            kind: kind,
            progress: progress,
            incoming: true,
            size: size,
          ),
          Positioned(
            left: 5,
            top: 4,
            child: _transitionTag('A'),
          ),
          Positioned(
            right: 5,
            bottom: 4,
            child: _transitionTag('B'),
          ),
        ],
      ),
    );
  }

  Widget _transitionTag(String label) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x990A1421),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: Text(label, style: const TextStyle(
        color: Colors.white,
        fontSize: 7,
        fontWeight: FontWeight.w900,
      )),
    ),
  );
}

class _TransitionScenePainter extends CustomPainter {
  const _TransitionScenePainter({required this.second});

  final bool second;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = second
        ? const [Color(0xFF0C6257), Color(0xFFB96847)]
        : const [Color(0xFF183D68), Color(0xFF70466F)];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * (second ? 0.72 : 0.28), size.height * 0.34),
      size.height * 0.14,
      Paint()..color = second
          ? const Color(0xFFFFD08A)
          : const Color(0xFFFFE0A0),
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

  @override
  bool shouldRepaint(covariant _TransitionScenePainter oldDelegate) =>
      oldDelegate.second != second;
}

