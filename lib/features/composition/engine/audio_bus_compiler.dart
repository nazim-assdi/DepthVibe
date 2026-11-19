import 'dart:math' as math;

import '../domain/composition_models.dart';

/// Compiles bus gain, stereo placement and dynamics into native FFmpeg filters.
class AudioBusCompiler {
  const AudioBusCompiler();

  List<String> compile(AudioBus bus) {
    final filters = <String>[];
    final gain = bus.gainDb.clamp(-60.0, 24.0).toDouble();
    if (gain.abs() >= 0.01) {
      filters.add('volume=' + _linear(gain));
    }

    final pan = bus.pan.clamp(-1.0, 1.0).toDouble();
    if (pan.abs() >= 0.001) {
      final left = (1 - math.max(0, pan)).toStringAsFixed(4);
      final right = (1 + math.min(0, pan)).toStringAsFixed(4);
      filters.add('pan=stereo|c0=c0*$left|c1=c1*$right');
    }

    if (bus.compressorEnabled) {
      final thresholdDb =
          bus.compressorThresholdDb.clamp(-60.0, 0.0).toDouble();
      final threshold = _linear(thresholdDb);
      final ratio = bus.compressorRatio.clamp(1.0, 20.0).toStringAsFixed(2);
      final attack = bus.compressorAttackMs.clamp(0.1, 200.0)
          .toStringAsFixed(1);
      final release = bus.compressorReleaseMs.clamp(10.0, 2000.0)
          .toStringAsFixed(1);
      final makeup = _linear(
        bus.makeupGainDb.clamp(-12.0, 24.0).toDouble(),
      );
      filters.add(
        'acompressor=threshold=$threshold:ratio=$ratio:'
        'attack=$attack:release=$release:makeup=$makeup',
      );
    }

    if (bus.limiterEnabled) {
      final ceiling = _linear(
        bus.limiterCeilingDb.clamp(-24.0, 0.0).toDouble(),
      );
      filters.add('alimiter=limit=$ceiling');
    }
    return List.unmodifiable(filters);
  }

  String _linear(double decibels) =>
      math.pow(10, decibels / 20).toStringAsFixed(6);
}
