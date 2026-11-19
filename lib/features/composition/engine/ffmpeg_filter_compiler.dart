import '../data/effect_catalog.dart';
import '../domain/composition_models.dart';
import 'ffmpeg_animation_compiler.dart';

class FfmpegFilterCompiler {
  const FfmpegFilterCompiler();

  List<String> compileEffects(
    CompositionLayer layer, {
    required int timeMs,
    FfmpegAnimationCompiler animationCompiler =
        const FfmpegAnimationCompiler(),
  }) {
    final filters = <String>[];
    for (final effect in layer.effects.where((item) => item.enabled)) {
      final definition = EffectCatalog.find(effect.effectId);
      if (definition == null) continue;
      final values = {
        for (final parameter in definition.parameters)
          parameter.id: effect.parameterAt(
            parameter.id,
            timeMs,
            fallback: parameter.defaultValue,
          ),
      };
      final filter = _compileAnimatedColorEffect(
            definition.id,
            effect,
            definition,
            animationCompiler,
          ) ??
          _compileEffect(definition.id, values);
      if (filter != null && filter.isNotEmpty) filters.add(filter);
    }
    return filters;
  }

  String? _compileAnimatedColorEffect(
    String id,
    EffectInstance effect,
    EffectDefinition definition,
    FfmpegAnimationCompiler animationCompiler,
  ) {
    String parameterExpression(String parameterId) {
      final definitionForParameter = definition.parameters.firstWhere(
        (parameter) => parameter.id == parameterId,
      );
      final tracks = effect.keyframeTracks.where(
        (track) => track.property == parameterId && track.enabled,
      );
      return animationCompiler.keyframeExpression(
        tracks.isEmpty ? null : tracks.first,
        fallback: effect.parameters[parameterId] ??
            definitionForParameter.defaultValue,
        timeVariable: 'T',
      );
    }

    if (id == 'displacement') {
      final amount = parameterExpression('amount');
      final wavelength = parameterExpression('wavelength');
      final speed = parameterExpression('speed');
      final dx = '(' + amount +
          ')*sin(Y/max(1,(' + wavelength + '))+T*(' + speed + '))';
      final dy = '(' + amount +
          ')*cos(X/max(1,(' + wavelength + '))+T*(' + speed + '))';
      final sampleX = '(X+(' + dx + '))';
      final sampleY = '(Y+(' + dy + '))';
      return 'format=rgba,geq='
          "r='r(" + sampleX + ',' + sampleY + ")':"
          "g='g(" + sampleX + ',' + sampleY + ")':"
          "b='b(" + sampleX + ',' + sampleY + ")':"
          "a='alpha(X,Y)'";
    }

    if (id == 'particle_dust') {
      final spacing = parameterExpression('spacing');
      final size = parameterExpression('size');
      final intensity = parameterExpression('intensity');
      final speed = parameterExpression('speed');
      final cellSize = 'max(16,(' + spacing + '))';
      final cellX = 'mod(X+T*(' + speed + ')*17,' + cellSize + ')';
      final cellY = 'mod(Y+T*(' + speed + ')*11,' + cellSize + ')';
      final distance = 'hypot(' + cellX + ',' + cellY + ')';
      final particle = 'if(lt(' + distance + ',(' + size + ')),(' +
          intensity + ')*(1-(' + distance + ')/max(1,(' + size + '))),0)';
      final lifted = '255*(' + particle + ')';
      return 'format=rgba,geq='
          "r='min(255,r(X,Y)+" + lifted + ")':"
          "g='min(255,g(X,Y)+" + lifted + ")':"
          "b='min(255,b(X,Y)+" + lifted + ")':"
          "a='alpha(X,Y)'";
    }

    const supported = {'brightness', 'contrast', 'saturation', 'gamma'};
    if (!supported.contains(id)) return null;
    final parameter = definition.parameters.first;
    final tracks = effect.keyframeTracks.where(
      (track) => track.property == parameter.id && track.enabled,
    );
    if (tracks.isEmpty || tracks.first.keyframes.isEmpty) return null;
    final expression = animationCompiler.keyframeExpression(
      tracks.first,
      fallback: effect.parameters[parameter.id] ?? parameter.defaultValue,
    );
    final option = id == 'saturation' ? 'saturation' : id;
    return "eq=" + option + "='" + expression + "':eval=frame";
  }

  String? _compileEffect(String id, Map<String, double> p) {
    String number(double value) => value.toStringAsFixed(3);
    return switch (id) {
      'brightness' => 'eq=brightness=${number(p['value'] ?? 0)}',
      'contrast' => 'eq=contrast=${number(p['value'] ?? 1)}',
      'saturation' => 'hue=s=${number(p['value'] ?? 1)}',
      'gamma' => 'eq=gamma=${number(p['value'] ?? 1)}',
      'gaussian_blur' => 'gblur=sigma=${number(p['sigma'] ?? 2)}',
      'box_blur' => 'boxblur=${number(p['radius'] ?? 2)}',
      'sharpen' => 'unsharp=5:5:${number(p['amount'] ?? 1)}',
      'vignette' => 'vignette=angle=${number(p['angle'] ?? 0.8)}',
      'film_grain' => 'noise=alls=${number(p['amount'] ?? 12)}:allf=t+u',
      'pixelate' => 'pixelize=width=${(p['size'] ?? 12).round()}:height=${(p['size'] ?? 12).round()}',
      'invert' => 'negate',
      'grayscale' => 'hue=s=0',
      'chromatic_aberration' => 'chromashift=cbh=${number(p['shift'] ?? 2)}:crh=-${number(p['shift'] ?? 2)}',
      'edge_detect' => 'edgedetect=mode=colormix',
      'mirror' => 'hflip',
      'flip' => 'vflip',
      'color_curves' => "curves=all='0/0 0.25/0.25 0.5/0.5 0.75/0.75 1/1'",
      'motion_blur' => 'tmix=frames=${(p['frames'] ?? 5).round()}',
      'lens_distortion' => 'lenscorrection=k1=${number(p['strength'] ?? 0.1)}:k2=0',
      'chroma_key' => 'chromakey=0x00FF00:${number(p['similarity'] ?? 0.3)}:${number(p['blend'] ?? 0.1)}',
      'luma_key' => 'lumakey=${number(p['threshold'] ?? 0.5)}:${number(p['tolerance'] ?? 0.1)}',
      'stabilize' => 'deshake',
      'posterize' => 'posterize=levels=${(p['levels'] ?? 6).round()}',
      'color_balance' => 'colorbalance=rs=${number(p['red'] ?? 0)}:gs=${number(p['green'] ?? 0)}:bs=${number(p['blue'] ?? 0)}',
      _ => null,
    };
  }

  String? compileTransition(CompositionTransition transition) {
    final duration = (transition.durationMs / 1000).toStringAsFixed(3);
    final offset = (transition.startMs / 1000).toStringAsFixed(3);
    final name = switch (transition.kind) {
      TransitionKind.dissolve => 'fade',
      TransitionKind.fadeThroughColor => 'fade',
      TransitionKind.wipeLeft => 'wipeleft',
      TransitionKind.wipeRight => 'wiperight',
      TransitionKind.wipeUp => 'wipeup',
      TransitionKind.wipeDown => 'wipedown',
      TransitionKind.slideLeft => 'slideleft',
      TransitionKind.slideRight => 'slideright',
      TransitionKind.zoomIn => 'zoomin',
      TransitionKind.zoomOut => 'smoothleft',
      TransitionKind.blur => 'fadeblack',
      TransitionKind.luma => 'circleopen',
    };
    return 'xfade=transition=$name:duration=$duration:offset=$offset';
  }
}
