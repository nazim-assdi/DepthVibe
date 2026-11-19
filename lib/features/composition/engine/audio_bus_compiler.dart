import 'dart:math' as math;

import '../domain/composition_models.dart';
import 'ffmpeg_animation_compiler.dart';

/// Compiles bus gain, stereo placement and dynamics into native FFmpeg filters.
class AudioBusCompiler {
  const AudioBusCompiler({
    this.animationCompiler = const FfmpegAnimationCompiler(),
  });

  final FfmpegAnimationCompiler animationCompiler;

  List<String> compile(AudioBus bus) {
    final filters = <String>[];
    final gainTracks = bus.keyframeTracks.where(
      (track) => track.property == 'gainDb' && track.enabled,
    );
    if (gainTracks.isNotEmpty && gainTracks.first.keyframes.isNotEmpty) {
      final gain = animationCompiler.keyframeExpression(
        gainTracks.first,
        fallback: bus.gainDb,
        timeVariable: 't',
      );
      filters.add("volume='pow(10,($gain)/20)':eval=frame");
    } else {
      final gain = bus.gainDb.clamp(-60.0, 24.0).toDouble();
      if (gain.abs() >= 0.01) {
        filters.add('volume=' + _linear(gain));
      }
    }

    final panTracks = bus.keyframeTracks.where(
      (track) => track.property == 'pan' && track.enabled,
    );
    if (panTracks.isNotEmpty && panTracks.first.keyframes.isNotEmpty) {
      final pan = animationCompiler.keyframeExpression(
        panTracks.first,
        fallback: bus.pan,
        timeVariable: 't',
      );
      final bounded = 'max(-1,min(1,$pan))';
      filters.add(
        "aeval=exprs='val(0)*(1-max(0,$bounded))|"
        "val(1)*(1+min(0,$bounded))':channel_layout=stereo",
      );
    } else {
      final pan = bus.pan.clamp(-1.0, 1.0).toDouble();
      if (pan.abs() >= 0.001) {
        final left = (1 - math.max(0, pan)).toStringAsFixed(4);
        final right = (1 + math.min(0, pan)).toStringAsFixed(4);
        filters.add('pan=stereo|c0=$left*c0|c1=$right*c1');
      }
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
        bus.makeupGainDb.clamp(0.0, 24.0).toDouble(),
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
