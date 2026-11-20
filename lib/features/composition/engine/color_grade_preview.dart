import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../domain/composition_models.dart';

class ColorGradePreview {
  const ColorGradePreview._();
  static double value(EffectInstance grade, String parameter, int timeMs, {double fallback = 0}) =>
      grade.parameterAt(parameter, timeMs, fallback: fallback);
  static ColorFilter? filterFor(EffectInstance? grade, int timeMs) {
    if (grade == null || !grade.enabled) return null;
    final lift = <double>[
      value(grade, 'lift_r', timeMs) * .14 + value(grade, 'offset_r', timeMs) * .16 + value(grade, 'temperature', timeMs) * .055 - value(grade, 'tint', timeMs) * .02,
      value(grade, 'lift_g', timeMs) * .14 + value(grade, 'offset_g', timeMs) * .16 + value(grade, 'tint', timeMs) * .055,
      value(grade, 'lift_b', timeMs) * .14 + value(grade, 'offset_b', timeMs) * .16 - value(grade, 'temperature', timeMs) * .055 - value(grade, 'tint', timeMs) * .02,
    ];
    final masterGamma = value(grade, 'master_gamma', timeMs, fallback: 1).clamp(.1, 3).toDouble();
    final channelScale = <double>[
      for (final channel in const ['r', 'g', 'b'])
        ((1 + value(grade, 'gain_$channel', timeMs) * .5 + value(grade, 'gamma_$channel', timeMs) * .28) / masterGamma).clamp(.05, 4).toDouble(),
    ];
    final contrast = value(grade, 'contrast', timeMs, fallback: 1).clamp(0, 3).toDouble();
    final brightness = value(grade, 'brightness', timeMs).clamp(-1, 1).toDouble();
    final saturation = value(grade, 'saturation', timeMs, fallback: 1).clamp(0, 3).toDouble();
    const luma = <double>[.2126, .7152, .0722];
    final matrix = <double>[];
    for (var output = 0; output < 3; output++) {
      var bias = .5 * (1 - contrast) + brightness;
      for (var input = 0; input < 3; input++) {
        final mix = saturation * (output == input ? 1.0 : 0.0) + (1 - saturation) * luma[input];
        matrix.add(mix * contrast * channelScale[input]);
        bias += mix * contrast * lift[input];
      }
      matrix..add(0)..add(bias);
    }
    matrix.addAll(const [0, 0, 0, 1, 0]);
    return ColorFilter.matrix(matrix);
  }
}
