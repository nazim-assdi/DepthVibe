import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../domain/composition_models.dart';

/// Fast Flutter-side preview counterparts for common native effects.
///
/// The native filter graph remains authoritative for export; values here are
/// sampled from the same editable effect/keyframe model at the current time.
class LiveEffectPreview {
  const LiveEffectPreview._();

  static const _sepiaMatrix = <double>[
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static bool supports(String effectId) => const {
    'brightness', 'contrast', 'saturation', 'gamma', 'grayscale',
    'invert', 'sepia', 'color_balance', 'color_contrast', 'camera_flash',
    'gaussian_blur', 'box_blur', 'vignette', 'letterbox', 'frame_border',
    'transform', 'film_gate_weave', 'bleach_bypass', 'old_film',
  }.contains(effectId);

  static List<double>? colorMatrixFor(EffectInstance effect, int timeMs) {
    double value(String id, double fallback) =>
        effect.parameterAt(id, timeMs, fallback: fallback);

    switch (effect.effectId) {
      case 'brightness':
        final lift = value('value', 0).clamp(-1.0, 1.0) * 255;
        return _matrix(1, 0, 0, 0, lift, 0, 1, 0, 0, lift, 0, 0, 1, 0, lift);
      case 'contrast':
        final factor = value('value', 1).clamp(0.0, 3.0);
        final offset = 128 * (1 - factor);
        return _matrix(factor, 0, 0, 0, offset, 0, factor, 0, 0, offset, 0, 0, factor, 0, offset);
      case 'gamma':
        // Preview approximation. Native export uses FFmpeg's nonlinear gamma.
        final factor = (1 / value('value', 1).clamp(0.2, 3.0)).clamp(0.333, 5.0);
        final offset = 128 * (1 - factor);
        return _matrix(factor, 0, 0, 0, offset, 0, factor, 0, 0, offset, 0, 0, factor, 0, offset);
      case 'saturation':
        return _saturation(value('value', 1).clamp(0.0, 3.0));
      case 'grayscale':
        return _saturation(0);
      case 'invert':
        return _matrix(-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255);
      case 'sepia':
      case 'old_film':
        return List<double>.unmodifiable(_sepiaMatrix);
      case 'color_balance':
        return _matrix(
          1, 0, 0, 0, value('red', 0) * 96,
          0, 1, 0, 0, value('green', 0) * 96,
          0, 0, 1, 0, value('blue', 0) * 96,
        );
      case 'color_contrast':
        final red = 1 + value('red', 0);
        final green = 1 + value('green', 0);
        final blue = 1 + value('blue', 0);
        return _matrix(
          red, 0, 0, 0, 128 * (1 - red),
          0, green, 0, 0, 128 * (1 - green),
          0, 0, blue, 0, 128 * (1 - blue),
        );
      case 'camera_flash':
        final lift = value('brightness', 0.35).clamp(0.0, 2.0) * 90;
        return _matrix(1, 0, 0, 0, lift, 0, 1, 0, 0, lift, 0, 0, 1, 0, lift);
      case 'bleach_bypass':
        final saturation = value('saturation', 0.45).clamp(0.0, 1.0);
        final contrast = value('contrast', 1.35).clamp(0.5, 2.5);
        return _compose(
          _saturation(saturation),
          _matrix(
            contrast, 0, 0, 0, 128 * (1 - contrast),
            0, contrast, 0, 0, 128 * (1 - contrast),
            0, 0, contrast, 0, 128 * (1 - contrast),
          ),
        );
      default:
        return null;
    }
  }

  static Widget apply({
    required Widget child,
    required List<EffectInstance> effects,
    required int timeMs,
    required Size canvasSize,
  }) {
    Widget result = child;
    for (final effect in effects.where((item) => item.enabled)) {
      double value(String id, double fallback) =>
          effect.parameterAt(id, timeMs, fallback: fallback);

      final matrix = colorMatrixFor(effect, timeMs);
      if (matrix != null) {
        result = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: result);
      }
      switch (effect.effectId) {
        case 'gaussian_blur':
          final sigma = value('sigma', 2).clamp(0.0, 30.0);
          if (sigma > 0.01) {
            result = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: result,
            );
          }
          break;
        case 'box_blur':
          final sigma = value('radius', 2).clamp(0.0, 20.0) * 0.62;
          if (sigma > 0.01) {
            result = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: result,
            );
          }
          break;
        case 'vignette':
          final strength = (value('angle', 0.8) / 1.5).clamp(0.0, 1.0);
          result = Stack(fit: StackFit.passthrough, children: [
            result,
            Positioned.fill(child: IgnorePointer(child: DecoratedBox(
              decoration: BoxDecoration(gradient: RadialGradient(
                radius: 0.88,
                colors: [const Color(0x00000000), Color.fromRGBO(0, 0, 0, strength * 0.78)],
                stops: const [0.42, 1],
              )),
            ))),
          ]);
          break;
        case 'letterbox':
          final ratio = value('ratio', 0.1).clamp(0.02, 0.2);
          result = Stack(fit: StackFit.passthrough, children: [
            result,
            Positioned(left: 0, right: 0, top: 0, height: canvasSize.height * ratio,
              child: const IgnorePointer(child: ColoredBox(color: Color(0xFF000000)))),
            Positioned(left: 0, right: 0, bottom: 0, height: canvasSize.height * ratio,
              child: const IgnorePointer(child: ColoredBox(color: Color(0xFF000000)))),
          ]);
          break;
        case 'frame_border':
          final thickness = value('thickness', 6).clamp(1.0, 30.0);
          final opacity = value('opacity', 0.8).clamp(0.0, 1.0);
          result = Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: Color.fromRGBO(255, 255, 255, opacity), width: thickness),
            ),
            child: result,
          );
          break;
        case 'transform':
          final scale = value('scale', 100).clamp(0.0, 400.0) / 100;
          final rotation = value('rotation', 0) * math.pi / 180;
          result = Transform.rotate(angle: rotation, child: Transform.scale(scale: scale, child: result));
          break;
        case 'film_gate_weave':
          final amplitude = value('amplitude', 0.45).clamp(0.0, 3.0);
          final speed = value('speed', 2).clamp(0.1, 10.0);
          final angle = amplitude * math.sin(timeMs / 1000 * speed * math.pi * 2) * math.pi / 180;
          result = Transform.rotate(angle: angle, child: result);
          break;
        case 'old_film':
          final vignette = value('vignette', 0.7).clamp(0.1, 1.5);
          result = Stack(fit: StackFit.passthrough, children: [
            result,
            Positioned.fill(child: IgnorePointer(child: DecoratedBox(
              decoration: BoxDecoration(gradient: RadialGradient(
                radius: 0.88,
                colors: [const Color(0x00000000), Color.fromRGBO(28, 15, 2, vignette / 1.5 * 0.72)],
                stops: const [0.4, 1],
              )),
            ))),
          ]);
          break;
      }
    }
    return result;
  }

  static List<double> _saturation(double amount) {
    const red = 0.213, green = 0.715, blue = 0.072;
    final inverse = 1 - amount;
    return _matrix(
      red * inverse + amount, green * inverse, blue * inverse, 0, 0,
      red * inverse, green * inverse + amount, blue * inverse, 0, 0,
      red * inverse, green * inverse, blue * inverse + amount, 0, 0,
    );
  }

  static List<double> _matrix(
    double r0, double r1, double r2, double r3, double r4,
    double g0, double g1, double g2, double g3, double g4,
    double b0, double b1, double b2, double b3, double b4,
  ) => [
    r0, r1, r2, r3, r4, g0, g1, g2, g3, g4,
    b0, b1, b2, b3, b4, 0, 0, 0, 1, 0,
  ];

  static List<double> _compose(List<double> first, List<double> second) {
    final output = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 5; column++) {
        var sum = 0.0;
        for (var inner = 0; inner < 4; inner++) {
          sum += second[row * 5 + inner] * first[inner * 5 + column];
        }
        if (column == 4) sum += second[row * 5 + 4];
        output[row * 5 + column] = sum;
      }
    }
    return output;
  }
}
