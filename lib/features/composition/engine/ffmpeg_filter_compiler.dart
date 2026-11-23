import '../data/effect_catalog.dart';
import '../domain/composition_models.dart';
import '../data/transition_catalog.dart';
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
      final rendererId = definition.rendererId ?? definition.id;
      final filter = _compileAnimatedColorEffect(
            rendererId,
            effect,
            definition,
            animationCompiler,
          ) ??
          _compileEffect(rendererId, values);
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
    String parameterExpression(
      String parameterId, {
      String timeVariable = 'T',
    }) {
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
        timeVariable: timeVariable,
      );
    }

    if (id == 'transform') {
      final scale = parameterExpression('scale');
      final rotation = parameterExpression('rotation');
      final safeScale = 'max(0.001,min(400,(' + scale + ')))';
      final safeRotation = 'max(-360,min(360,(' + rotation + ')))';
      final angle = '(' + safeRotation + ')*PI/180';
      return 'scale=w='
          "'max(1,iw*(" + safeScale + ")/100)':"
          "h='max(1,ih*(" + safeScale + ")/100)':eval=frame,"
          'rotate=angle=' + "'" + angle + "'" +
          ":ow='rotw(" + angle + ")':"
          "oh='roth(" + angle + ")':c=black@0";
    }

    if (id == 'color_lut') {
      final path = effect.assetUri;
      if (path == null || path.trim().isEmpty) return null;
      final escaped = path
          .replaceAll('\\', '\\\\')
          .replaceAll(':', '\\:')
          .replaceAll("'", "\\'");
      const supportedInterpolations = {
        'nearest',
        'trilinear',
        'tetrahedral',
        'pyramid',
        'prism',
      };
      final interpolation = supportedInterpolations.contains(
        effect.assetInterpolation,
      )
          ? effect.assetInterpolation
          : 'trilinear';
      return "lut3d=file='$escaped':interp=$interpolation";
    }

    if (id == 'color_curves') {
      String curve(String channel) {
        final points = <String>[];
        for (var index = 0; index < 5; index++) {
          final parameterId = '${channel}_${index}';
          final parameter = definition.parameters.firstWhere(
            (item) => item.id == parameterId,
          );
          final value = (effect.parameters[parameterId] ??
                  parameter.defaultValue)
              .clamp(0.0, 1.0)
              .toDouble();
          points.add(
            '${(index * 0.25).toStringAsFixed(2)}/'
            '${value.toStringAsFixed(3)}',
          );
        }
        return points.join(' ');
      }

      return "curves=master='${curve('master')}':"
          "r='${curve('red')}':"
          "g='${curve('green')}':"
          "b='${curve('blue')}':interp=natural";
    }

    if (id == 'color_grade') {
      const wheelProperties = [
        'lift_r', 'lift_g', 'lift_b',
        'gamma_r', 'gamma_g', 'gamma_b',
        'gain_r', 'gain_g', 'gain_b',
        'offset_r', 'offset_g', 'offset_b',
      ];
      final animatedWheels = effect.keyframeTracks.any(
        (track) => wheelProperties.contains(track.property) &&
            track.enabled &&
            track.keyframes.isNotEmpty,
      );

      String number(double value) => value.toStringAsFixed(3);
      if (animatedWheels) {
        String expression(String key) =>
            parameterExpression(key, timeVariable: 'T');
        String channelExpression(String channel) {
          final luma =
              '((0.2126*r(X,Y)+0.7152*g(X,Y)+0.0722*b(X,Y))/255)';
          final lift = expression('lift_$channel');
          final gamma = expression('gamma_$channel');
          final gain = expression('gain_$channel');
          final offset = expression('offset_$channel');
          final temperature = expression('temperature');
          final tint = expression('tint');
          final whiteBalance = switch (channel) {
            'r' => '(($temperature)*0.35-($tint)*0.15)',
            'g' => '(($tint)*0.35)',
            _ => '(-($temperature)*0.35-($tint)*0.15)',
          };
          final adjustment =
              '(($lift*(1-$luma)+$gamma*4*$luma*(1-$luma)+'
              '$gain*$luma+$offset+$whiteBalance)*128)';
          return "clip($channel(X,Y)+$adjustment,0,255)";
        }

        final wheels = 'format=rgba,geq='
            "r='${channelExpression('r')}':"
            "g='${channelExpression('g')}':"
            "b='${channelExpression('b')}':"
            "a='alpha(X,Y)'";
        final eq = 'eq='
            "contrast='${parameterExpression('contrast', timeVariable: 't')}':"
            "brightness='${parameterExpression('brightness', timeVariable: 't')}':"
            "gamma='${parameterExpression('master_gamma', timeVariable: 't')}':"
            "saturation='${parameterExpression('saturation', timeVariable: 't')}':"
            'eval=frame';
        return wheels + ',' + eq;
      }

      double wheel(String band, String channel) {
        final bandValue = effect.parameters['${band}_$channel'] ?? 0;
        final offset = effect.parameters['offset_$channel'] ?? 0;
        final temperature = effect.parameters['temperature'] ?? 0;
        final tint = effect.parameters['tint'] ?? 0;
        final whiteBalance = switch (channel) {
          'r' => temperature * 0.35 - tint * 0.15,
          'g' => tint * 0.35,
          _ => -temperature * 0.35 - tint * 0.15,
        };
        return (bandValue + offset + whiteBalance)
            .clamp(-1.0, 1.0)
            .toDouble();
      }

      final colorBalance = 'colorbalance='
          'rs=${number(wheel('lift', 'r'))}:'
          'gs=${number(wheel('lift', 'g'))}:'
          'bs=${number(wheel('lift', 'b'))}:'
          'rm=${number(wheel('gamma', 'r'))}:'
          'gm=${number(wheel('gamma', 'g'))}:'
          'bm=${number(wheel('gamma', 'b'))}:'
          'rh=${number(wheel('gain', 'r'))}:'
          'gh=${number(wheel('gain', 'g'))}:'
          'bh=${number(wheel('gain', 'b'))}:pl=1';
      final eq = 'eq='
          "contrast='${parameterExpression('contrast', timeVariable: 't')}':"
          "brightness='${parameterExpression('brightness', timeVariable: 't')}':"
          "gamma='${parameterExpression('master_gamma', timeVariable: 't')}':"
          "saturation='${parameterExpression('saturation', timeVariable: 't')}':"
          'eval=frame';
      return colorBalance + ',' + eq;
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

    const supported = {
      'brightness', 'contrast', 'saturation', 'gamma', 'camera_flash',
    };
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
    final option = switch (id) {
      'camera_flash' => 'brightness',
      'saturation' => 'saturation',
      _ => id,
    };
    return "eq=" + option + "='" + expression + "':eval=frame";
  }

  String? _compileEffect(String id, Map<String, double> p) {
    String number(double value) => value.toStringAsFixed(3);
    if (id == 'wave_distortion') {
      final amount = number(p['amount'] ?? 8);
      final wavelength = number(p['wavelength'] ?? 72);
      final speed = number(p['speed'] ?? 1);
      final dx = '(sin(Y/max(1,$wavelength)+T*$speed)*$amount)';
      return 'format=rgba,geq='
          "r='r(X+$dx,Y)':g='g(X+$dx,Y)':"
          "b='b(X+$dx,Y)':a='alpha(X,Y)'";
    }
    if (id == 'heat_haze') {
      final amount = number(p['amount'] ?? 5);
      final scale = number(p['scale'] ?? 90);
      final speed = number(p['speed'] ?? 1.4);
      final dx = '(sin(Y/max(1,$scale)+T*$speed)*$amount)';
      final dy = '(cos(X/max(1,$scale)+T*$speed*0.73)*$amount*0.35)';
      return 'format=rgba,geq='
          "r='r(X+$dx,Y+$dy)':g='g(X+$dx,Y+$dy)':"
          "b='b(X+$dx,Y+$dy)':a='alpha(X,Y)'";
    }
    if (id == 'film_gate_weave') {
      final amplitude = number(p['amplitude'] ?? 0.45);
      final speed = number(p['speed'] ?? 2);
      return "rotate=angle='sin(t*$speed)*$amplitude*PI/180':"
          'ow=iw:oh=ih:c=black';
    }

    if (id == 'ripple_warp') {
      final amount=number(p['amount']??5), wavelength=number(p['wavelength']??84), speed=number(p['speed']??1.1);
      final dx='(sin(Y/max(1,$wavelength)+T*$speed)*$amount)';
      final dy='(cos(X/max(1,$wavelength)-T*$speed)*$amount*0.35)';
      return 'format=rgba,geq='
          "r='r(X+$dx,Y+$dy)':g='g(X+$dx,Y+$dy)':b='b(X+$dx,Y+$dy)':a='alpha(X,Y)'";
    }
    if (id == 'zoom_warp') {
      final amount=number((p['amount']??0.08).clamp(-0.45,0.45));
      final cx=number((p['center_x']??0.5).clamp(0,1)),cy=number((p['center_y']??0.5).clamp(0,1));
      final sx='($cx*W+(X-$cx*W)*(1+$amount))',sy='($cy*H+(Y-$cy*H)*(1+$amount))';
      return 'format=rgba,geq='
          "r='r($sx,$sy)':g='g($sx,$sy)':b='b($sx,$sy)':a='alpha(X,Y)'";
    }
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
      'threshold' => _compileThreshold(p['value'] ?? 128),
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
      'posterize' => _compilePosterize(p['levels'] ?? 6),
      'color_balance' => 'colorbalance=rs=${number(p['red'] ?? 0)}:gs=${number(p['green'] ?? 0)}:bs=${number(p['blue'] ?? 0)}',
      'exposure' => 'exposure=exposure=' + number(p['value'] ?? 0) + ':black=' + number(p['black'] ?? 0),
      'hue_rotate' => 'hue=h=' + number((p['degrees'] ?? 0) * 0.017453292519943295),
      'colorize' => 'colorize=hue=' + number(p['hue'] ?? 210) +
          ':saturation=' + number(p['saturation'] ?? 0.65) +
          ':lightness=' + number(p['lightness'] ?? 0) + ':mix=' + number(p['mix'] ?? 0.5),
      'directional_blur' || 'radial_blur' =>
          'dblur=angle=' + number(p['angle'] ?? 0) + ':radius=' + number(p['radius'] ?? 8),
      'average_blur' => 'avgblur=sizeX=' + (p['size'] ?? 5).round().toString() +
          ':sizeY=' + (p['size'] ?? 5).round().toString(),
      'chroma_denoise' => 'chromanr=thres=' + number(p['threshold'] ?? 0.08) +
          ':sizew=' + (p['window'] ?? 3).round().toString() +
          ':sizeh=' + (p['window'] ?? 3).round().toString(),
      'deband' => 'deband=1thr=' + number(p['threshold'] ?? 0.02) +
          ':2thr=' + number(p['threshold'] ?? 0.02) +
          ':3thr=' + number(p['threshold'] ?? 0.02) +
          ':4thr=' + number(p['threshold'] ?? 0.02) +
          ':range=' + (p['range'] ?? 16).round().toString(),
      'deflicker' => 'deflicker=mode=am:size=' + (p['size'] ?? 10).round().toString(),
      'scanlines' => 'drawgrid=w=iw:h=' + (p['spacing'] ?? 4).round().toString() +
          ':t=' + (p['thickness'] ?? 1).round().toString() + ':c=black@' + number(p['opacity'] ?? 0.25),
      'rgb_split' => 'chromashift=cbh=' + number(p['shift'] ?? 4) + ':crh=-' + number(p['shift'] ?? 4),
      'posterize_time' => 'fps=fps=' + number(p['fps'] ?? 12),
      'echo_trails' => 'tmix=frames=' + (p['frames'] ?? 4).round().toString(),
      'vhs_warp' => 'chromashift=cbh=' + number(p['shift'] ?? 3) +
          ':crh=-' + number(p['shift'] ?? 3) +
          ',noise=alls=' + number(p['noise'] ?? 18) + ':allf=t',
      'fisheye' => 'lenscorrection=k1=' + number(p['strength'] ?? 0.35) + ':k2=0',
      'noise_reduction' => 'hqdn3d=' + number(p['luma'] ?? 1.5) +
          ':' + number(p['chroma'] ?? 2) + ':' + number(p['temporal'] ?? 3) +
          ':' + number((p['temporal'] ?? 3) * 0.5),
      'vibrance' => 'vibrance=intensity=${number(p['intensity'] ?? 0.5)}',
      'color_contrast' => 'colorcontrast=rc=${number(p['red'] ?? 0)}:gm=${number(p['green'] ?? 0)}:by=${number(p['blue'] ?? 0)}',
      'auto_white_balance' => 'grayworld',
      'rgb_channel_mixer' => 'colorchannelmixer='
          'rr=${number(p['rr'] ?? 1)}:rg=${number(p['rg'] ?? 0)}:rb=${number(p['rb'] ?? 0)}:'
          'gr=${number(p['gr'] ?? 0)}:gg=${number(p['gg'] ?? 1)}:gb=${number(p['gb'] ?? 0)}:'
          'br=${number(p['br'] ?? 0)}:bg=${number(p['bg'] ?? 0)}:bb=${number(p['bb'] ?? 1)}',
      'adaptive_sharpen' => 'cas=strength=${number(p['strength'] ?? 0.5)}',
      'median_denoise' => 'median=radius=${(p['radius'] ?? 2).round()}:planes=7',
      'temporal_denoise' => 'tmedian=radius=${(p['radius'] ?? 3).round()}:planes=7',
      'nlmeans_denoise' => 'nlmeans=s=${number(p['strength'] ?? 1.2)}:p=7:r=15',
      'frame_blend' => 'tblend=all_mode=average',
      'camera_flash' => 'eq=brightness=${number(p['brightness'] ?? 0.35)}',
      'letterbox' => 'drawbox=x=0:y=0:w=iw:h=ih*${number(p['ratio'] ?? 0.1)}:color=black@1:t=fill,'
          'drawbox=x=0:y=ih-ih*${number(p['ratio'] ?? 0.1)}:w=iw:h=ih*${number(p['ratio'] ?? 0.1)}:color=black@1:t=fill',
      'frame_border' => 'drawbox=x=0:y=0:w=iw:h=ih:color=white@${number(p['opacity'] ?? 0.8)}:t=${(p['thickness'] ?? 6).round()}',
      'old_film' => 'noise=alls=${number(p['grain'] ?? 22)}:allf=t+u,'
          'vignette=angle=${number(p['vignette'] ?? 0.7)},'
          'colorbalance=rs=${number(p['warmth'] ?? 0.35)}:gs=${number((p['warmth'] ?? 0.35) * 0.18)}:bs=-${number((p['warmth'] ?? 0.35) * 0.35)}',
      'analog_glitch' => 'chromashift=cbh=${number(p['shift'] ?? 5)}:crh=-${number(p['shift'] ?? 5)},'
          'noise=alls=${number(p['noise'] ?? 24)}:allf=t,fps=fps=${number(p['fps'] ?? 18)}',
      'bleach_bypass' => 'hue=s=${number(p['saturation'] ?? 0.45)},eq=contrast=${number(p['contrast'] ?? 1.35)}',
      'sepia' => 'colorchannelmixer=rr=0.393:rg=0.769:rb=0.189:'
          'gr=0.349:gg=0.686:gb=0.168:br=0.272:bg=0.534:bb=0.131',
      'edge_glow' => 'edgedetect=mode=colormix,gblur=sigma=${number(p['radius'] ?? 8)},'
          'eq=brightness=${number(p['brightness'] ?? 0.4)}',

      'solarize' => 'format=rgba,lutrgb='
          "r='if(gte(val," + number(p['threshold']??128) + "),255-val,val)':"
          "g='if(gte(val," + number(p['threshold']??128) + "),255-val,val)':"
          "b='if(gte(val," + number(p['threshold']??128) + "),255-val,val)':a=val",
      'color_temperature' => 'colorbalance=rs=' + number((p['temperature']??0)*(p['intensity']??1)*0.6) +
          ':gs=' + number((p['tint']??0)*(p['intensity']??1)*0.3) +
          ':bs=' + number(-(p['temperature']??0)*(p['intensity']??1)*0.6) + ':pl=1',
      'soft_focus' => 'gblur=sigma=' + number(p['radius']??2) + ',eq=brightness=' + number(p['brightness']??0.03),
      'color_key' => 'colorkey=0x00FF00:' + number(p['similarity']??0.3) + ':' + number(p['blend']??0.1),
      'high_pass_sharpen' => 'unsharp=7:7:' + number(p['amount']??1.2) + ':5:5:0',
      'chroma_smear' => 'chromashift=cbh=' + number(p['shift']??3) + ':crh=-' + number(p['shift']??3),
      _ => null,
    };
  }

  String _compilePosterize(double levels) {
    final count = levels.clamp(2.0, 32.0).round();
    final steps = (count - 1).toString();
    final expression = "round(val*$steps/255)*255/$steps";
    return "format=rgba,lutrgb=r='$expression':g='$expression':"
        "b='$expression':a=val";
  }

  String _compileThreshold(double value) {
    final threshold = value.clamp(0.0, 255.0).toStringAsFixed(2);
    final expression = "if(gte(val,$threshold),255,0)";
    return "format=rgba,lutrgb=r='$expression':g='$expression':b='$expression':a=val";
  }

  String? compileTransition(CompositionTransition transition) {
    final duration = (transition.durationMs / 1000).toStringAsFixed(3);
    final offset = (transition.startMs / 1000).toStringAsFixed(3);
    final name = TransitionCatalog.xfadeName(transition.kind);
    return 'xfade=transition=$name:duration=$duration:offset=$offset';
  }
}
