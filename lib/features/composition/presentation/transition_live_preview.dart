import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../data/transition_catalog.dart';
import '../domain/composition_models.dart';
import '../engine/live_effect_preview.dart';

/// Playhead-driven transition compositor. The incoming clip uses the growing
/// mask while the outgoing clip uses its complement, so the two clips do not
/// reveal the same half of the frame.
class TransitionLivePreview {
  const TransitionLivePreview._();

  static Widget apply({
    required Widget child,
    required TransitionKind kind,
    required double progress,
    required bool incoming,
    required Size size,
  }) {
    final p = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final name = TransitionCatalog.xfadeName(kind).toLowerCase();

    if (name == 'fade') {
      return Opacity(opacity: incoming ? p : 1 - p, child: child);
    }
    if (name == 'fadeblack' || name == 'fadewhite' || name == 'fadegrays') {
      final strength = (1 - (2 * p - 1).abs()).clamp(0.0, 1.0);
      final color = name == 'fadewhite'
          ? const Color(0xFFFFFFFF)
          : name == 'fadegrays'
              ? const Color(0xFF777777)
              : const Color(0xFF000000);
      return Stack(
        fit: StackFit.passthrough,
        children: [
          Opacity(opacity: incoming ? p : 1 - p, child: child),
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: color.withOpacity(strength)),
            ),
          ),
        ],
      );
    }

    if (name.startsWith('slide') || name.startsWith('smooth')) {
      final horizontal = !name.endsWith('up') && !name.endsWith('down');
      final reverse = name.endsWith('right') || name.endsWith('down');
      final direction = reverse ? -1.0 : 1.0;
      final distance = (1 - p) * (horizontal ? size.width : size.height);
      final offset = horizontal
          ? Offset((incoming ? direction : -direction) * distance, 0)
          : Offset(0, (incoming ? direction : -direction) * distance);
      return ClipRect(
        child: Transform.translate(offset: offset, child: child),
      );
    }

    if (name == 'zoomin' || name == 'smoothright') {
      final scale = incoming ? 0.72 + 0.28 * p : 1.0 + 0.10 * p;
      return ClipRect(child: Transform.scale(scale: scale, child: child));
    }
    if (name == 'squeezeh' || name == 'squeezev') {
      final factor = incoming ? p : 1 - p;
      return ClipRect(
        child: Transform.scale(
          scaleX: name == 'squeezeh' ? factor : 1,
          scaleY: name == 'squeezev' ? factor : 1,
          child: child,
        ),
      );
    }
    if (name == 'hblur' || name == 'vblur') {
      final sigma = math.sin(p * math.pi) * 8;
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: name == 'hblur' ? sigma : 0,
          sigmaY: name == 'vblur' ? sigma : 0,
        ),
        child: Opacity(opacity: incoming ? p : 1 - p, child: child),
      );
    }
    if (name == 'pixelize') {
      final amount = incoming ? 16 * (1 - p) : 16 * p;
      final pixelated = LiveEffectPreview.apply(
        child: child,
        effects: [
          EffectInstance(
            id: incoming ? 'transition-pixel-in' : 'transition-pixel-out',
            effectId: 'pixelate',
            name: 'Pixelize transition',
            parameters: {'size': amount.clamp(2.0, 80.0)},
          ),
        ],
        timeMs: 0,
        canvasSize: size,
      );
      return incoming
          ? ClipPath(clipper: _TransitionMaskClipper(name, p, true), child: pixelated)
          : ClipPath(clipper: _TransitionMaskClipper(name, p, false), child: pixelated);
    }

    final maskNames = <String>{
      'wipeleft','wiperight','wipeup','wipedown',
      'wipetl','wipetr','wipebl','wipebr',
      'circleopen','circleclose','circlecrop','radial','rectcrop','distance',
      'vertopen','vertclose','horzopen','horzclose',
      'diagtl','diagtr','diagbl','diagbr',
      'hlslice','hrslice','vuslice','vdslice',
      'hlwind','hrwind','vuwind','vdwind',
      'coverleft','coverright','coverup','coverdown',
      'revealleft','revealright','revealup','revealdown',
    };
    if (maskNames.contains(name)) {
      return ClipPath(
        clipper: _TransitionMaskClipper(name, p, incoming),
        child: child,
      );
    }

    // Less common directional transitions still get a visible, continuous
    // frame preview instead of an inert/static tile.
    return Opacity(opacity: incoming ? p : 1 - p, child: child);
  }
}

class _TransitionMaskClipper extends CustomClipper<Path> {
  const _TransitionMaskClipper(this.name, this.progress, this.incoming);

  final String name;
  final double progress;
  final bool incoming;

  @override
  Path getClip(Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final p = progress.clamp(0.0, 1.0).toDouble();
    Path shape;

    if (name == 'circleopen' || name == 'circlecrop' || name == 'distance') {
      final radius = math.sqrt(size.width * size.width + size.height * size.height) * p;
      shape = Path()
        ..addOval(Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: radius,
        ));
    } else if (name == 'circleclose') {
      final radius = math.sqrt(size.width * size.width + size.height * size.height) * (1 - p);
      shape = Path()
        ..addOval(Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: radius,
        ));
    } else if (name == 'rectcrop') {
      final inset = (1 - p) * math.min(size.width, size.height) * 0.5;
      shape = Path()..addRect(Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset));
    } else if (name == 'vertopen' || name == 'vertclose') {
      final width = size.width * (name == 'vertopen' ? p : 1 - p);
      shape = Path()..addRect(Rect.fromLTRB(
        (size.width - width) / 2, 0, (size.width + width) / 2, size.height,
      ));
    } else if (name == 'horzopen' || name == 'horzclose') {
      final height = size.height * (name == 'horzopen' ? p : 1 - p);
      shape = Path()..addRect(Rect.fromLTRB(
        0, (size.height - height) / 2, size.width, (size.height + height) / 2,
      ));
    } else if (name == 'radial') {
      final rect = Offset.zero & size;
      final sweep = 2 * math.pi * p;
      shape = Path()
        ..moveTo(size.width / 2, size.height / 2)
        ..arcTo(rect, -math.pi / 2, sweep, false)
        ..close();
    } else if (name.startsWith('diag')) {
      shape = _diagonal(size, p);
    } else if (name.endsWith('slice') || name.endsWith('wind')) {
      shape = _stripes(size, p, vertical: name.startsWith('v'));
    } else {
      shape = _directional(size, p, name);
    }

    if (incoming) return shape;
    final inverse = Path()..fillType = PathFillType.evenOdd;
    inverse
      ..addPath(full, Offset.zero)
      ..addPath(shape, Offset.zero);
    return inverse;
  }

  Path _directional(Size size, double p, String name) {
    final w = size.width;
    final h = size.height;
    if (name.endsWith('right')) {
      return Path()..addRect(Rect.fromLTRB(w * (1-p), 0, w, h));
    }
    if (name.endsWith('up')) {
      return Path()..addRect(Rect.fromLTRB(0, h * (1-p), w, h));
    }
    if (name.endsWith('down')) {
      return Path()..addRect(Rect.fromLTRB(0, 0, w, h*p));
    }
    return Path()..addRect(Rect.fromLTRB(0, 0, w*p, h));
  }

  Path _diagonal(Size size, double p) {
    final w = size.width;
    final h = size.height;
    final top = name.contains('tl') || name.contains('tr');
    final left = name.contains('tl') || name.contains('bl');
    final corner = Offset(left ? 0 : w, top ? 0 : h);
    final a = Offset(left ? w : 0, top ? 0 : h);
    final b = Offset(left ? 0 : w, top ? h : 0);
    final tip = Offset(left ? w*p : w*(1-p), top ? h*p : h*(1-p));
    return Path()
      ..moveTo(corner.dx, corner.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
  }

  Path _stripes(Size size, double p, {required bool vertical}) {
    final path = Path();
    const count = 8;
    for (var index = 0; index < count; index++) {
      final stagger = (index % 2) * 0.035;
      final local = ((p - stagger) / (1 - stagger)).clamp(0.0, 1.0);
      if (vertical) {
        final top = size.height * index / count;
        final bottom = size.height * (index + 1) / count;
        final width = size.width * local;
        final fromRight = name.startsWith('hr') || name.startsWith('vd');
        path.addRect(fromRight
            ? Rect.fromLTRB(size.width-width, top, size.width, bottom)
            : Rect.fromLTRB(0, top, width, bottom));
      } else {
        final left = size.width * index / count;
        final right = size.width * (index + 1) / count;
        final height = size.height * local;
        final fromBottom = name.startsWith('vu') || name.startsWith('vd');
        path.addRect(fromBottom
            ? Rect.fromLTRB(left, size.height-height, right, size.height)
            : Rect.fromLTRB(left, 0, right, height));
      }
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _TransitionMaskClipper oldClipper) =>
      oldClipper.name != name ||
      oldClipper.progress != progress ||
      oldClipper.incoming != incoming;
}
