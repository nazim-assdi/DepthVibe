import 'package:flutter/widgets.dart';

import '../domain/composition_models.dart';

/// A fast matrix approximation used by the interactive compositor viewer.
/// Final exports continue to use the native FFmpeg color pipeline.
class ColorGradePreview {
  const ColorGradePreview._();

  static double value(
    EffectInstance grade,
    String parameter,
    int timeMs, {
    double fallback = 0,
  }) =>
      grade.parameterAt(parameter, timeMs, fallback: fallback);

  static List<double> applyRgb(
    List<double> rgb,
    EffectInstance? grade,
    int timeMs,
  ) {
    if (grade == null || !grade.enabled || rgb.length < 3) return rgb;
    final red = rgb[0];
    final green = rgb[1];
    final blue = rgb[2];
    final masterGamma =
        value(grade, 'master_gamma', timeMs, fallback: 1).clamp(0.1, 3);
    final channels = <double>[red, green, blue];
    final names = const ['r', 'g', 'b'];
    final temperature = value(grade, 'temperature', timeMs);
    final tint = value(grade, 'tint', timeMs);

    for (var index = 0; index < 3; index++) {
      final channel = names[index];
      final scale = ((1 +
                  value(grade, 'gain_$channel', timeMs) * 0.5 +
                  value(grade, 'gamma_$channel', timeMs) * 0.28) /
              masterGamma)
          .clamp(0.05, 4);
      final lift = value(grade, 'lift_$channel', timeMs) * 0.14 +
          value(grade, 'offset_$channel', timeMs) * 0.16;
      final whiteBalance = switch (channel) {
        'r' => temperature * 0.055 - tint * 0.02,
        'g' => tint * 0.055,
        _ => -temperature * 0.055 - tint * 0.02,
      };
      channels[index] = (channels[index] * scale + lift + whiteBalance)
          .clamp(0.0, 1.0);
    }

    final luma = channels[0] * 0.2126 +
        channels[1] * 0.7152 +
        channels[2] * 0.0722;
    final contrast =
        value(grade, 'contrast', timeMs, fallback: 1).clamp(0, 3);
    final brightness = value(grade, 'brightness', timeMs).clamp(-1, 1);
    final saturation =
        value(grade, 'saturation', timeMs, fallback: 1).clamp(0, 3);
    return <double>[
      for (final channelValue in channels)
        ((luma + (channelValue - luma) * saturation - 0.5) * contrast +
                0.5 +
                brightness)
            .clamp(0.0, 1.0),
    ];
  }

  static ColorFilter? filterFor(EffectInstance? grade, int timeMs) {
    if (grade == null || !grade.enabled) return null;
    final masterGamma =
        value(grade, 'master_gamma', timeMs, fallback: 1).clamp(0.1, 3);
    final names = const ['r', 'g', 'b'];
    final scales = <double>[];
    final biases = <double>[];
    final temperature = value(grade, 'temperature', timeMs);
    final tint = value(grade, 'tint', timeMs);
    for (final channel in names) {
      scales.add(
        ((1 +
                    value(grade, 'gain_$channel', timeMs) * 0.5 +
                    value(grade, 'gamma_$channel', timeMs) * 0.28) /
                masterGamma)
            .clamp(0.05, 4),
      );
      biases.add(
        value(grade, 'lift_$channel', timeMs) * 0.14 +
            value(grade, 'offset_$channel', timeMs) * 0.16 +
            switch (channel) {
              'r' => temperature * 0.055 - tint * 0.02,
              'g' => tint * 0.055,
              _ => -temperature * 0.055 - tint * 0.02,
            },
      );
    }

    final contrast =
        value(grade, 'contrast', timeMs, fallback: 1).clamp(0, 3);
    final brightness = value(grade, 'brightness', timeMs).clamp(-1, 1);
    final saturation =
        value(grade, 'saturation', timeMs, fallback: 1).clamp(0, 3);
    const luma = <double>[0.2126, 0.7152, 0.0722];
    final matrix = <double>[];
    for (var output = 0; output < 3; output++) {
      var bias = 0.5 * (1 - contrast) + brightness;
      for (var input = 0; input < 3; input++) {
        final mix = saturation * (output == input ? 1.0 : 0.0) +
            (1 - saturation) * luma[input];
        matrix.add(mix * contrast * scales[input]);
        bias += mix * contrast * biases[input];
      }
      matrix
        ..add(0)
        ..add(bias);
    }
    matrix.addAll(const [0, 0, 0, 1, 0]);
    return ColorFilter.matrix(matrix);
  }
}
