import '../data/effect_catalog.dart';
import '../domain/composition_models.dart';
import 'ffmpeg_animation_compiler.dart';

/// Compiles multi-pass Glow and Drop Shadow effects for the FFmpeg renderer.
class FfmpegCompositingEffectCompiler {
  const FfmpegCompositingEffectCompiler({
    this.animationCompiler = const FfmpegAnimationCompiler(),
  });

  final FfmpegAnimationCompiler animationCompiler;

  String _effectParameterExpression(
    EffectInstance effect,
    String property,
    double fallback, {
    double min = -100000,
    double max = 100000,
  }) {
    final base = (effect.parameters[property] ?? fallback)
        .clamp(min, max)
        .toDouble();
    final tracks = effect.keyframeTracks.where(
      (track) => track.property == property && track.enabled,
    );
    final expression = animationCompiler.keyframeExpression(
      tracks.isEmpty ? null : tracks.first,
      fallback: base,
      timeVariable: 'T',
    );
    return 'max(' + min.toStringAsFixed(4) + ',min(' +
        max.toStringAsFixed(4) + ',(' + expression + ')))';
  }

  double _effectParameterMaximum(
    EffectInstance effect,
    String property,
    double fallback, {
    double min = -100000,
    double max = 100000,
    bool absolute = false,
  }) {
    var maximum = (effect.parameters[property] ?? fallback)
        .clamp(min, max)
        .toDouble();
    for (final track in effect.keyframeTracks.where(
      (item) => item.property == property && item.enabled,
    )) {
      for (final frame in track.keyframes) {
        final value = frame.value.clamp(min, max).toDouble();
        final candidate = absolute ? value.abs() : value;
        if (candidate > (absolute ? maximum.abs() : maximum)) {
          maximum = value;
        }
      }
    }
    return absolute ? maximum.abs() : maximum;
  }

  String _appendAnimatedBlur({
    required List<String> filters,
    required String input,
    required EffectInstance effect,
    required String property,
    required double fallback,
    required int index,
    required int passIndex,
    required String prefix,
    double min = 0.5,
    double max = 50,
  }) {
    final matching = effect.keyframeTracks.where(
      (track) => track.property == property && track.enabled,
    );
    final track = matching.isEmpty ? null : matching.first;
    final frames = track == null
        ? <ScalarKeyframe>[]
        : [...track.keyframes]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final suffix = index.toString() + '_' + passIndex.toString();

    if (frames.length < 2) {
      final radius = (frames.isEmpty
              ? (effect.parameters[property] ?? fallback)
              : frames.single.value)
          .clamp(min, max)
          .toStringAsFixed(3);
      final output = prefix + 'Blur' + suffix;
      filters.add('[' + input + ']gblur=sigma=' + radius + '[' + output + ']');
      return output;
    }

    final sourceLabels = <String>[
      for (var frameIndex = 0; frameIndex < frames.length; frameIndex++)
        prefix + 'BlurSource' + suffix + '_' + frameIndex.toString(),
    ];
    filters.add(
      '[' + input + ']split=' + frames.length.toString() +
          sourceLabels.map((label) => '[' + label + ']').join(),
    );

    final blurredLabels = <String>[];
    for (var frameIndex = 0; frameIndex < frames.length; frameIndex++) {
      final label = prefix + 'BlurRadius' + suffix + '_' +
          frameIndex.toString();
      final radius = frames[frameIndex].value
          .clamp(min, max)
          .toStringAsFixed(3);
      filters.add(
        '[' + sourceLabels[frameIndex] + ']gblur=sigma=' +
            radius + '[' + label + ']',
      );
      blurredLabels.add(label);
    }

    final radiusExpression = animationCompiler.keyframeExpression(
      track,
      fallback: effect.parameters[property] ?? fallback,
      timeVariable: 'T',
    );
    var current = blurredLabels.first;
    for (var frameIndex = 0; frameIndex < frames.length - 1; frameIndex++) {
      final left = frames[frameIndex];
      final right = frames[frameIndex + 1];
      final from = left.value.clamp(min, max).toDouble();
      final to = right.value.clamp(min, max).toDouble();
      final start = (left.timeMs / 1000).toStringAsFixed(5);
      final end = (right.timeMs / 1000).toStringAsFixed(5);
      final progress = (to - from).abs() < 0.000001
          ? '0'
          : 'clip(((' + radiusExpression + ')-' +
              from.toStringAsFixed(5) + ')/' +
              (to - from).toStringAsFixed(5) + ',0,1)';
      final output = prefix + 'BlurMix' + suffix + '_' +
          frameIndex.toString();
      final expression = 'if(lt(T,' + start + '),A,if(gt(T,' + end +
          '),B,A*(1-(' + progress + '))+B*(' + progress + ')))';
      filters.add(
        '[' + current + '][' + blurredLabels[frameIndex + 1] +
            "]blend=all_expr='" + expression + "':shortest=1[" +
            output + ']',
      );
      current = output;
    }
    return current;
  }

  String compile({
    required List<String> filters,
    required String inputLabel,
    required CompositionLayer layer,
    required int index,
  }) {
    var current = inputLabel;
    var passIndex = 0;
    for (final effect in layer.effects.where((item) =>
        item.enabled &&
        (item.effectId == 'glow' || item.effectId == 'drop_shadow'))) {
      final definition = EffectCatalog.find(effect.effectId);
      if (definition == null) continue;
      if (effect.effectId == 'glow') {
        final threshold = _effectParameterExpression(
          effect, 'threshold', 0.75, min: 0, max: 1,
        );
        final intensity = _effectParameterExpression(
          effect, 'intensity', 1, min: 0, max: 3,
        );
        final radiusMaximum = _effectParameterMaximum(
          effect, 'radius', 12, min: 0.5, max: 50,
        );
        final padding = (radiusMaximum * 3).ceil().toString();
        final suffix = index.toString() + '_' + passIndex.toString();
        final body = 'glowBody' + suffix;
        final source = 'glowSource' + suffix;
        final padded = 'glowPadded' + suffix;
        final cut = 'glowCut' + suffix;
        final gained = 'glowGain' + suffix;
        final output = 'glowOutput' + suffix;

        filters.add(
          '[' + current + ']pad=w=iw+2*' + padding +
          ':h=ih+2*' + padding + ':x=' + padding + ':y=' + padding +
          ':color=black@0,format=rgba[' + padded + ']',
        );
        filters.add('[' + padded + ']split=2[' + body + '][' + source + ']');
        filters.add(
          '[' + source + "]format=rgba,geq="
          "r='if(gte(r(X,Y),(" + threshold + ")*255),r(X,Y),0)':"
          "g='if(gte(g(X,Y),(" + threshold + ")*255),g(X,Y),0)':"
          "b='if(gte(b(X,Y),(" + threshold + ")*255),b(X,Y),0)':"
          "a='alpha(X,Y)'[" + cut + ']',
        );
        final blurred = _appendAnimatedBlur(
          filters: filters,
          input: cut,
          effect: effect,
          property: 'radius',
          fallback: 12,
          index: index,
          passIndex: passIndex,
          prefix: 'glow',
          min: 0.5,
          max: 50,
        );
        filters.add(
          '[' + blurred + "]format=rgba,geq="
          "r='min(255,r(X,Y)*(" + intensity + "))':"
          "g='min(255,g(X,Y)*(" + intensity + "))':"
          "b='min(255,b(X,Y)*(" + intensity + "))':"
          "a='alpha(X,Y)'[" + gained + ']',
        );
        filters.add(
          '[' + body + '][' + gained +
          ']blend=all_mode=screen:all_opacity=1[' + output + ']',
        );
        current = output;
      } else {
        final opacity = _effectParameterExpression(
          effect, 'opacity', 0.6, min: 0, max: 1,
        );
        final offset = _effectParameterExpression(
          effect, 'offset', 8, min: -100, max: 100,
        );
        final blurMaximum = _effectParameterMaximum(
          effect, 'blur', 8, min: 0, max: 40,
        );
        final offsetMaximum = _effectParameterMaximum(
          effect,
          'offset',
          8,
          min: -100,
          max: 100,
          absolute: true,
        );
        final padding =
            (blurMaximum * 3 + offsetMaximum + 4).ceil();
        final pad = padding.toString();
        final suffix = index.toString() + '_' + passIndex.toString();
        final body = 'shadowBody' + suffix;
        final source = 'shadowSource' + suffix;
        final shadowAlpha = 'shadowAlpha' + suffix;
        final shadowCanvas = 'shadowCanvas' + suffix;
        final bodyCanvas = 'shadowBodyCanvas' + suffix;
        final placed = 'shadowPlaced' + suffix;
        final output = 'shadowOutput' + suffix;

        filters.add('[' + current + ']split=2[' + body + '][' + source + ']');
        filters.add(
          '[' + source + "]format=rgba,geq="
          "r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':"
          "a='alpha(X,Y)*(" + opacity + ")'[" + shadowAlpha + ']',
        );
        final blurred = _appendAnimatedBlur(
          filters: filters,
          input: shadowAlpha,
          effect: effect,
          property: 'blur',
          fallback: 8,
          index: index,
          passIndex: passIndex,
          prefix: 'shadow',
          min: 0,
          max: 40,
        );
        filters.add(
          '[' + blurred + ']pad=w=iw+2*' + pad +
          ':h=ih+2*' + pad + ':x=' + pad + ':y=' + pad +
          ':color=black@0,format=rgba[' + shadowCanvas + ']',
        );
        filters.add(
          '[' + body + ']pad=w=iw+2*' + pad +
          ':h=ih+2*' + pad + ':x=' + pad + ':y=' + pad +
          ':color=black@0,format=rgba[' + bodyCanvas + ']',
        );
        filters.add(
          '[' + shadowCanvas + "]overlay=x='" + pad + '+(' + offset +
          ")':y='" + pad + '+(' + offset +
          ")':eval=frame:shortest=1:format=auto[" + placed + ']',
        );
        filters.add(
          '[' + placed + '][' + bodyCanvas + ']overlay=x=' + pad +
          ':y=' + pad + ':shortest=1:format=auto[' + output + ']',
        );
        current = output;
      }
      passIndex++;
    }
    return current;
  }


}
