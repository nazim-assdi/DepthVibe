import 'dart:math' as math;

import '../domain/composition_models.dart';

enum AdjustmentPreviewKind {
  colorMatrix,
  gaussianBlur,
  boxBlur,
  horizontalFlip,
  verticalFlip,
  vignette,
}

class AdjustmentPreviewOperation {
  const AdjustmentPreviewOperation({
    required this.kind,
    this.colorMatrix = const [],
    this.amount = 0,
  });

  final AdjustmentPreviewKind kind;
  final List<double> colorMatrix;
  final double amount;
}

/// Fast interactive approximations for a subset of the final FFmpeg effects.
/// Unsupported operations return null instead of displaying a misleading result.
class AdjustmentPreviewCompiler {
  const AdjustmentPreviewCompiler();

  static const List<double> identity = [
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  double _value(EffectInstance effect, String key, int timeMs, double fallback) {
    final value = effect.parameterAt(key, timeMs, fallback: fallback);
    return value.isFinite ? value : fallback;
  }

  List<double> _contrast(double value) {
    final amount = value.clamp(0.0, 3.0).toDouble();
    final bias = 128 * (1 - amount);
    return [
      amount, 0, 0, 0, bias,
      0, amount, 0, 0, bias,
      0, 0, amount, 0, bias,
      0, 0, 0, 1, 0,
    ];
  }

  List<double> _saturation(double value) {
    final amount = value.clamp(0.0, 3.0).toDouble();
    const red = 0.2126;
    const green = 0.7152;
    const blue = 0.0722;
    final inverse = 1 - amount;
    return [
      red * inverse + amount, green * inverse, blue * inverse, 0, 0,
      red * inverse, green * inverse + amount, blue * inverse, 0, 0,
      red * inverse, green * inverse, blue * inverse + amount, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  List<double> _hue(double degrees) {
    final angle = degrees * math.pi / 180;
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    return [
      0.213 + cosine * 0.787 - sine * 0.213,
      0.715 - cosine * 0.715 - sine * 0.715,
      0.072 - cosine * 0.072 + sine * 0.928,
      0, 0,
      0.213 - cosine * 0.213 + sine * 0.143,
      0.715 + cosine * 0.285 + sine * 0.140,
      0.072 - cosine * 0.072 - sine * 0.283,
      0, 0,
      0.213 - cosine * 0.213 - sine * 0.787,
      0.715 - cosine * 0.715 + sine * 0.715,
      0.072 + cosine * 0.928 + sine * 0.072,
      0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  AdjustmentPreviewOperation? compile(EffectInstance effect, int timeMs) {
    if (!effect.enabled) return null;
    switch (effect.effectId) {
      case 'brightness':
        final value = _value(effect, 'value', timeMs, 0).clamp(-1.0, 1.0);
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.colorMatrix,
          colorMatrix: [
            1, 0, 0, 0, value * 255,
            0, 1, 0, 0, value * 255,
            0, 0, 1, 0, value * 255,
            0, 0, 0, 1, 0,
          ],
        );
      case 'contrast':
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.colorMatrix,
          colorMatrix: _contrast(_value(effect, 'value', timeMs, 1)),
        );
      case 'saturation':
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.colorMatrix,
          colorMatrix: _saturation(_value(effect, 'value', timeMs, 1)),
        );
      case 'grayscale':
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.colorMatrix,
          colorMatrix: _saturation(0),
        );
      case 'invert':
        return const AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.colorMatrix,
          colorMatrix: [
            -1, 0, 0, 0, 255,
            0, -1, 0, 0, 255,
            0, 0, -1, 0, 255,
            0, 0, 0, 1, 0,
          ],
        );
      case 'exposure':
        final exposure = _value(effect, 'value', timeMs, 0).clamp(-8.0, 8.0);
        final multiplier = math.pow(2, exposure).toDouble();
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.colorMatrix,
          colorMatrix: [
            multiplier, 0, 0, 0, 0,
            0, multiplier, 0, 0, 0,
            0, 0, multiplier, 0, 0,
            0, 0, 0, 1, 0,
          ],
        );
      case 'hue_rotate':
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.colorMatrix,
          colorMatrix: _hue(_value(effect, 'degrees', timeMs, 0)),
        );
      case 'color_balance':
        final red = _value(effect, 'red', timeMs, 0).clamp(-1.0, 1.0);
        final green = _value(effect, 'green', timeMs, 0).clamp(-1.0, 1.0);
        final blue = _value(effect, 'blue', timeMs, 0).clamp(-1.0, 1.0);
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.colorMatrix,
          colorMatrix: [
            1, 0, 0, 0, red * 64,
            0, 1, 0, 0, green * 64,
            0, 0, 1, 0, blue * 64,
            0, 0, 0, 1, 0,
          ],
        );
      case 'gaussian_blur':
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.gaussianBlur,
          amount: _value(effect, 'sigma', timeMs, 2).clamp(0.0, 30.0),
        );
      case 'box_blur':
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.boxBlur,
          amount: _value(effect, 'radius', timeMs, 2).clamp(0.0, 20.0),
        );
      case 'mirror':
        return const AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.horizontalFlip,
        );
      case 'flip':
        return const AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.verticalFlip,
        );
      case 'vignette':
        return AdjustmentPreviewOperation(
          kind: AdjustmentPreviewKind.vignette,
          amount: _value(effect, 'angle', timeMs, 0.8).clamp(0.1, 1.5),
        );
      default:
        return null;
    }
  }
}
