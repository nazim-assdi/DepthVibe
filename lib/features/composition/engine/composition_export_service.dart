import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../data/effect_catalog.dart';
import '../domain/composition_models.dart';
import 'audio_bus_compiler.dart';
import 'audio_equalizer_compiler.dart';
import 'ffmpeg_animation_compiler.dart';
import 'ffmpeg_filter_compiler.dart';
import 'parent_transform_expression_resolver.dart';
import 'camera_projection_resolver.dart';

typedef CompositionExportProgress = void Function(double value);

class CompositionExportResult {
  const CompositionExportResult({
    required this.file,
    required this.renderedLayerCount,
    required this.skippedLayerNames,
  });

  final File file;
  final int renderedLayerCount;
  final List<String> skippedLayerNames;
}

/// Local FFmpeg compositor with per-frame transform curves, layer alpha masks,
/// blend compositing and a multi-track audio mix.
class CompositionExportService {
  const CompositionExportService({
    this.filterCompiler = const FfmpegFilterCompiler(),
    this.animationCompiler = const FfmpegAnimationCompiler(),
    this.audioEqualizerCompiler = const AudioEqualizerCompiler(),
    this.audioBusCompiler = const AudioBusCompiler(),
    this.parentTransformResolver = const ParentTransformExpressionResolver(),
    this.cameraProjectionResolver = const CameraProjectionResolver(),
  });

  final FfmpegFilterCompiler filterCompiler;
  final FfmpegAnimationCompiler animationCompiler;
  final AudioEqualizerCompiler audioEqualizerCompiler;
  final AudioBusCompiler audioBusCompiler;
  final ParentTransformExpressionResolver parentTransformResolver;
  final CameraProjectionResolver cameraProjectionResolver;

  Future<CompositionExportResult> export(
    CompositionDocument document, {
    CompositionExportProgress? onProgress,
  }) async {
    if (document.width <= 0 || document.height <= 0 ||
        document.durationMs <= 0 || document.frameRate <= 0) {
      throw StateError('Composition size, frame rate and duration must be valid.');
    }

    const visualKinds = {
      LayerKind.video,
      LayerKind.image,
      LayerKind.photoshopLayer,
    };
    final anySolo = document.layers.any((layer) =>
        layer.enabled &&
        layer.solo &&
        (visualKinds.contains(layer.kind) ||
            layer.kind == LayerKind.adjustment ||
            layer.kind == LayerKind.audio));
    // The workspace paints the reversed layer list: the first item in the
    // document stack is the top layer. Export composites bottom-to-top too.
    final enabled = document.layers.reversed.where(
      (layer) => layer.enabled && (!anySolo || layer.solo),
    );
    final visualLayers = <CompositionLayer>[];
    final audioLayers = <CompositionLayer>[];
    final skipped = <String>[];

    for (final layer in enabled) {
      if (visualKinds.contains(layer.kind)) {
        final path = layer.sourceUri;
        if (path == null || path.isEmpty || !await File(path).exists()) {
          skipped.add(layer.name);
        } else {
          visualLayers.add(layer);
        }
      } else if (layer.kind == LayerKind.adjustment) {
        visualLayers.add(layer);
      } else if (layer.kind == LayerKind.audio) {
        if (layer.audioSettings.muted) continue;
        final path = layer.sourceUri;
        if (path == null || path.isEmpty || !await File(path).exists()) {
          skipped.add(layer.name);
        } else {
          audioLayers.add(layer);
        }
      } else if (layer.kind != LayerKind.nullObject &&
          layer.kind != LayerKind.precomposition &&
          layer.kind != LayerKind.camera &&
          layer.kind != LayerKind.light) {
        skipped.add(layer.name);
      }
    }

    final hasVisualMedia = visualLayers.any(
      (layer) => visualKinds.contains(layer.kind),
    );
    if (!hasVisualMedia && audioLayers.isEmpty) {
      throw StateError(
        'Import at least one video, image, Photoshop raster or audio layer.',
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final outputDirectory = Directory(
      directory.path + Platform.pathSeparator + 'DepthVibe' +
      Platform.pathSeparator + 'Compositions',
    );
    await outputDirectory.create(recursive: true);
    final name = 'Composition_' +
        DateTime.now().toIso8601String().replaceAll(':', '-');
    final output = File(
      outputDirectory.path + Platform.pathSeparator + name + '.mp4',
    );
    final command = await _buildCommand(
      document,
      visualLayers,
      audioLayers,
      output.path,
    );
    final completion = Completer<void>();

    try {
      final start = FFmpegKit.executeAsync(
        command,
        onStatistics: (statistics) {
          onProgress?.call(
            (statistics.time / document.durationMs).clamp(0, 0.99).toDouble(),
          );
        },
        onComplete: (session) {
          if (ReturnCode.isSuccess(session.getReturnCode())) {
            if (!completion.isCompleted) completion.complete();
          } else if (!completion.isCompleted) {
            completion.completeError(
              StateError(session.getFailStackTrace() ?? 'Composition render failed.'),
            );
          }
        },
      );
      unawaited(start.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) completion.completeError(error, stackTrace);
        },
      ));
      await completion.future.timeout(const Duration(hours: 3));
      if (!await output.exists() || await output.length() == 0) {
        throw StateError('FFmpeg completed without producing an MP4 file.');
      }
      onProgress?.call(1);
      return CompositionExportResult(
        file: output,
        renderedLayerCount: visualLayers.length + audioLayers.length,
        skippedLayerNames: List.unmodifiable(skipped),
      );
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  Future<String> _buildCommand(
    CompositionDocument document,
    List<CompositionLayer> visualLayers,
    List<CompositionLayer> audioLayers,
    String outputPath,
  ) async {
    final total = (document.durationMs / 1000).toStringAsFixed(3);
    final width = document.width;
    final height = document.height;
    final buffer = StringBuffer();
    final filters = <String>[];
    final audioSources = <_AudioSource>[];
    final mediaLayers = visualLayers
        .where((layer) =>
            layer.kind == LayerKind.video ||
            layer.kind == LayerKind.image ||
            layer.kind == LayerKind.photoshopLayer)
        .toList();
    final mediaInputIndices = <String, int>{
      for (var index = 0; index < mediaLayers.length; index++)
        mediaLayers[index].id: index + 1,
    };
    final cameraLayer = document.layers
        .where((item) => item.kind == LayerKind.camera && item.enabled)
        .firstOrNull;
    final resolvedCamera = cameraLayer == null
        ? null
        : parentTransformResolver.resolve(
            layer: cameraLayer,
            layers: document.layers,
          );


    for (final layer in mediaLayers) {
      if (layer.kind != LayerKind.video ||
          layer.audioSettings.muted ||
          !await _hasAudioStream(layer.sourceUri!)) {
        continue;
      }
      audioSources.add(_AudioSource(
        layer: layer,
        inputIndex: mediaInputIndices[layer.id]!,
        streamSpecifier: 'a:0',
      ));
    }
    for (var index = 0; index < audioLayers.length; index++) {
      audioSources.add(_AudioSource(
        layer: audioLayers[index],
        inputIndex: mediaLayers.length + index + 1,
        streamSpecifier: 'a:0',
      ));
    }

    buffer.write('-y -f lavfi -i ');
    buffer.write(_quote(
      'color=c=black:s=' + width.toString() + 'x' + height.toString() +
      ':r=' + document.frameRate.toString() + ':d=' + total,
    ));
    buffer.write(' ');

    for (final layer in mediaLayers) {
      final duration = (layer.durationMs / 1000).toStringAsFixed(3);
      final source = _quote(layer.sourceUri!);
      if (layer.kind == LayerKind.image ||
          layer.kind == LayerKind.photoshopLayer) {
        buffer.write('-loop 1 -t ' + duration + ' -i ' + source + ' ');
      } else {
        final sourceIn = (layer.sourceInMs / 1000).toStringAsFixed(3);
        buffer.write('-ss ' + sourceIn + ' -t ' + duration +
            ' -i ' + source + ' ');
      }
    }
    for (final layer in audioLayers) {
      final sourceIn = (layer.sourceInMs / 1000).toStringAsFixed(3);
      final duration = (layer.durationMs / 1000).toStringAsFixed(3);
      buffer.write('-ss ' + sourceIn + ' -t ' + duration +
          ' -i ' + _quote(layer.sourceUri!) + ' ');
    }

    filters.add('[0:v]format=rgba[base0]');
    var previous = 'base0';

    for (var index = 0; index < visualLayers.length; index++) {
      final layer = visualLayers[index];
      if (layer.kind == LayerKind.adjustment) {
        final adjustmentEffects = filterCompiler.compileEffects(
          layer,
          timeMs: document.playheadMs,
          animationCompiler: animationCompiler,
        );
        var adjusted = previous;
        for (var effectIndex = 0;
            effectIndex < adjustmentEffects.length;
            effectIndex++) {
          final outputLabel =
              'adjustment' + index.toString() + '_' + effectIndex.toString();
          filters.add(
            '[' + adjusted + ']' + adjustmentEffects[effectIndex] +
                ',format=rgba[' + outputLabel + ']',
          );
          adjusted = outputLabel;
        }
        previous = adjusted;
        continue;
      }
      final inputIndex = mediaInputIndices[layer.id]!;
      final start = (layer.startMs / 1000).toStringAsFixed(3);
      final duration = (layer.durationMs / 1000).toStringAsFixed(3);
      final localTransform = parentTransformResolver.resolve(
        layer: layer,
        layers: document.layers,
      );
      if (!localTransform.enabled) continue;
      final cameraSettings = cameraLayer?.camera;
      final projectedTransform = cameraLayer != null &&
              resolvedCamera != null &&
              resolvedCamera.enabled &&
              cameraSettings != null &&
              layer.kind != LayerKind.camera &&
              layer.kind != LayerKind.light
          ? cameraProjectionResolver.compile(
              layer: localTransform,
              camera: resolvedCamera,
              settings: cameraSettings,
            )
          : null;
      final resolvedTransform = projectedTransform;
      final sxBase = resolvedTransform?.scaleX ?? localTransform.scaleX;
      final syBase = resolvedTransform?.scaleY ?? localTransform.scaleY;
      final sx = animationCompiler.transitionScaleExpression(
        layer: layer, transitions: document.transitions,
        baseExpression: sxBase,
      );
      final sy = animationCompiler.transitionScaleExpression(
        layer: layer, transitions: document.transitions,
        baseExpression: syBase,
      );
      final rotation = resolvedTransform?.rotationZ ?? localTransform.rotationZ;
      final opacity = resolvedTransform?.opacity ?? localTransform.opacity;
      final posXBase =
          resolvedTransform?.positionX ?? localTransform.positionX;
      final posYBase =
          resolvedTransform?.positionY ?? localTransform.positionY;
      final posX = animationCompiler.transitionPositionExpression(
        layer: layer, transitions: document.transitions,
        baseExpression: posXBase, axis: 'x',
        compositionWidth: document.width,
        compositionHeight: document.height,
      );
      final posY = animationCompiler.transitionPositionExpression(
        layer: layer, transitions: document.transitions,
        baseExpression: posYBase, axis: 'y',
        compositionWidth: document.width,
        compositionHeight: document.height,
      );
      final mask = animationCompiler.maskAlphaExpression(
        layer.masks,
        timeVariable: 'T',
      );
      final transition = animationCompiler.transitionAlphaExpression(
        layer: layer, transitions: document.transitions,
      );
      final alpha = '((' + mask + ')*(' + transition + ')*(' + opacity + ')/100)';
      final effects = filterCompiler.compileEffects(
        layer,
        timeMs: document.playheadMs,
        animationCompiler: animationCompiler,
      );
      final chain = <String>[
        'trim=duration=' + duration,
        'setpts=PTS-STARTPTS+' + start + '/TB',
        "scale=w='max(1,iw*(" + sx + ")/100)':h='max(1,ih*(" + sy + ")/100)':eval=frame",
        "rotate=angle='(" + rotation + ")*PI/180':ow='rotw(a)':oh='roth(a)':c=none",
        ...effects,
        'format=rgba',
        "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*(" + alpha + ")'",
      ];
      final sourceLayerLabel = 'layerSource' + index.toString();
      filters.add('[' + inputIndex.toString() + ':v]' +
          chain.join(',') + '[' + sourceLayerLabel + ']');
      final layerLabel = _appendCompositingEffects(
        filters: filters,
        inputLabel: sourceLayerLabel,
        layer: layer,
        index: index,
        timeMs: document.playheadMs,
      );
      final x = '(' + posX + '-w/2)';
      final y = '(' + posY + '-h/2)';

      if (layer.blendMode == LayerBlendMode.normal) {
        final next = 'base' + (index + 1).toString();
        filters.add(
          '[' + previous + '][' + layerLabel +
          "]overlay=x='" + x + "':y='" + y +
          "':eval=frame:format=auto:eof_action=pass:shortest=0:repeatlast=0[" +
          next + ']',
        );
        previous = next;
      } else {
        _appendBlendPass(
          filters: filters,
          previous: previous,
          layerLabel: layerLabel,
          next: 'base' + (index + 1).toString(),
          layer: layer,
          x: x,
          y: y,
          width: width,
          height: height,
          frameRate: document.frameRate,
          total: total,
          index: index,
        );
        previous = 'base' + (index + 1).toString();
      }
    }

    filters.add('[' + previous + ']format=yuv420p[vout]');
    if (audioSources.isNotEmpty) {
      _appendAudioMix(
        filters: filters,
        audioSources: audioSources,
        durationMs: document.durationMs,
        audioBuses: document.audioBuses,
      );
    }

    buffer.write('-filter_complex ' + _quote(filters.join(';')) + ' ');
    buffer.write('-map "[vout]" ');
    if (audioSources.isEmpty) {
      buffer.write('-an ');
    } else {
      buffer.write('-map "[aout]" -c:a aac -b:a 192k ');
    }
    buffer.write('-t ' + total + ' -r ' + document.frameRate.toString() + ' ');
    buffer.write('-c:v mpeg4 -q:v 3 -pix_fmt yuv420p -movflags +faststart ');
    buffer.write(_quote(outputPath));
    return buffer.toString();
  }

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
    required int timeMs,
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
              ? effect.parameterAt(property, timeMs, fallback: fallback)
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

  String _appendCompositingEffects({
    required List<String> filters,
    required String inputLabel,
    required CompositionLayer layer,
    required int index,
    required int timeMs,
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
          timeMs: timeMs,
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
          timeMs: timeMs,
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
          '[' + shadowCanvas + ']overlay=x=' + pad + '+(' + offset +
          '):y=' + pad + '+(' + offset +
          '):eval=frame:shortest=1:format=auto[' + placed + ']',
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


  void _appendBlendPass({
    required List<String> filters,
    required String previous,
    required String layerLabel,
    required String next,
    required CompositionLayer layer,
    required String x,
    required String y,
    required int width,
    required int height,
    required double frameRate,
    required String total,
    required int index,
  }) {
    final transparent = 'transparent' + index.toString();
    final full = 'full' + index.toString();
    final top = 'top' + index.toString();
    final topAlpha = 'topAlpha' + index.toString();
    final baseRgb = 'baseRgb' + index.toString();
    final blendSrc = 'blendSrc' + index.toString();
    final blendRgb = 'blendRgb' + index.toString();
    final alphaMask = 'alphaMask' + index.toString();
    final blended = 'blended' + index.toString();
    final mode = _blendFilterMode(layer.blendMode);

    filters.add(
      'color=c=black@0:s=' + width.toString() + 'x' + height.toString() +
      ':r=' + frameRate.toString() + ':d=' + total +
      ',format=rgba[' + transparent + ']',
    );
    filters.add(
      '[' + transparent + '][' + layerLabel + "]overlay=x='" + x +
      "':y='" + y +
      "':eval=frame:format=auto:eof_action=pass:shortest=0:repeatlast=0[" +
      full + ']',
    );
    filters.add('[' + previous + ']format=rgb24[' + baseRgb + ']');
    filters.add('[' + full + ']split=2[' + top + '][' + topAlpha + ']');
    filters.add('[' + top + ']format=rgb24[' + blendSrc + ']');
    filters.add('[' + blendSrc + '][' + baseRgb +
      ']blend=all_mode=' + mode + ':all_opacity=1[' + blendRgb + ']');
    filters.add('[' + topAlpha + ']alphaextract,format=gray[' + alphaMask + ']');
    filters.add('[' + baseRgb + '][' + blendRgb + '][' + alphaMask +
      ']maskedmerge[' + blended + ']');
    filters.add('[' + blended + ']format=rgba[' + next + ']');
  }

  String _blendFilterMode(LayerBlendMode mode) => switch (mode) {
    LayerBlendMode.multiply => 'multiply',
    LayerBlendMode.screen => 'screen',
    LayerBlendMode.overlay => 'overlay',
    LayerBlendMode.softLight => 'softlight',
    LayerBlendMode.hardLight => 'hardlight',
    LayerBlendMode.colorDodge => 'dodge',
    LayerBlendMode.colorBurn => 'burn',
    LayerBlendMode.difference => 'difference',
    LayerBlendMode.exclusion => 'exclusion',
    LayerBlendMode.add => 'addition',
    LayerBlendMode.lighten => 'lighten',
    LayerBlendMode.darken => 'darken',
    LayerBlendMode.normal => 'normal',
  };

  Future<bool> _hasAudioStream(String path) async {
    try {
      final command = "-v error -select_streams a:0 -show_entries "
          "stream=index -of csv=p=0 " + _quote(path);
      final session = await FFprobeKit.executeAsync(command);
      return ReturnCode.isSuccess(session.getReturnCode()) &&
          (session.getOutput() ?? '').trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _appendAudioMix({
    required List<String> filters,
    required List<_AudioSource> audioSources,
    required List<AudioBus> audioBuses,
    required int durationMs,
  }) {
    final total = (durationMs / 1000).toStringAsFixed(3);
    for (var index = 0; index < audioSources.length; index++) {
      final source = audioSources[index];
      final layer = source.layer;
      final settings = layer.audioSettings;
      final start = layer.startMs / 1000;
      final end = (layer.startMs + layer.durationMs) / 1000;
      final gain = animationCompiler.scalarExpression(
        layer: layer, property: 'audio.gainDb',
        fallback: settings.gainDb,
      );
      final pan = animationCompiler.scalarExpression(
        layer: layer,
        property: 'audio.pan',
        fallback: settings.pan,
      );
      final boundedPan = 'max(-1,min(1,' + pan + '))';
      final leftPan = '1-max(0,' + boundedPan + ')';
      final rightPan = '1+min(0,' + boundedPan + ')';
      final chain = <String>[
        'atrim=duration=' + (layer.durationMs / 1000).toStringAsFixed(3),
        'asetpts=PTS-STARTPTS+' + start.toStringAsFixed(3) + '/TB',
        'aformat=channel_layouts=stereo',
        ...audioEqualizerCompiler.compile(settings),
        "volume='pow(10,(" + gain + ")/20)':eval=frame",
        "aeval=exprs='val(0)*(" + leftPan + ")|val(1)*(" + rightPan +
            ")':channel_layout=stereo",
        if (settings.fadeInMs > 0)
          'afade=t=in:st=' + start.toStringAsFixed(3) +
          ':d=' + (settings.fadeInMs / 1000).toStringAsFixed(3),
        if (settings.fadeOutMs > 0)
          'afade=t=out:st=' +
          (end - settings.fadeOutMs / 1000).clamp(0, end).toStringAsFixed(3) +
          ':d=' + (settings.fadeOutMs / 1000).toStringAsFixed(3),
      ];
      filters.add('[' + source.inputIndex.toString() + ':' +
          source.streamSpecifier + ']' +
          chain.join(',') + '[aud' + index.toString() + ']');
    }

    final triggers = <int>[];
    final backgrounds = <int>[];
    for (var index = 0; index < audioSources.length; index++) {
      switch (audioSources[index].layer.audioSettings.duckingRole) {
        case AudioDuckingRole.trigger:
          triggers.add(index);
          break;
        case AudioDuckingRole.background:
          backgrounds.add(index);
          break;
        case AudioDuckingRole.none:
          break;
      }
    }

    final replacements = <int, String>{};
    if (triggers.isNotEmpty && backgrounds.isNotEmpty) {
      final triggerInputs = triggers.map((index) {
        final triggerLabel = 'audTrigger' + index.toString();
        final busLabel = 'audBus' + index.toString();
        filters.add(
          '[aud' + index.toString() + ']asplit=2[' +
              triggerLabel + '][' + busLabel + ']',
        );
        return '[' + triggerLabel + ']';
      }).join();
      filters.add(triggerInputs + 'amix=inputs=' + triggers.length.toString() +
          ':duration=longest:normalize=0[ducksideRaw]');
      filters.add('[ducksideRaw]asplit=' + backgrounds.length.toString() +
          List.generate(backgrounds.length, (index) => '[duckside' + index.toString() + ']').join());
      for (var index = 0; index < backgrounds.length; index++) {
        final backgroundIndex = backgrounds[index];
        final settings = audioSources[backgroundIndex].layer.audioSettings;
        final ducked = 'audDucked' + backgroundIndex.toString();
        filters.add(
          '[aud' + backgroundIndex.toString() + '][duckside' + index.toString() +
          ']sidechaincompress=threshold=' + settings.duckingThreshold.toStringAsFixed(3) +
          ':ratio=' + settings.duckingRatio.toStringAsFixed(2) +
          ':attack=' + settings.duckingAttackMs.toStringAsFixed(1) +
          ':release=' + settings.duckingReleaseMs.toStringAsFixed(1) +
          '[' + ducked + ']',
        );
        replacements[backgroundIndex] = ducked;
      }
    }

    final buses = audioBuses.isEmpty
        ? <AudioBus>[
            const AudioBus(
              id: 'master',
              name: 'Master',
              isMaster: true,
              limiterEnabled: true,
            ),
          ]
        : audioBuses;
    AudioBus? masterBus;
    for (final bus in buses) {
      if (bus.isMaster) {
        masterBus = bus;
        break;
      }
    }
    masterBus ??= buses.first;

    final validBusIds = buses.map((bus) => bus.id).toSet();
    final effectiveBusIds = <String>[
      for (final source in audioSources)
        source.layer.audioSettings.busId != null &&
                validBusIds.contains(source.layer.audioSettings.busId)
            ? source.layer.audioSettings.busId!
            : masterBus.id,
    ];

    final busOutputs = <String>[];
    var busOutputIndex = 0;
    for (final bus in buses) {
      if (bus.muted) continue;
      final sourceIndices = <int>[
        for (var index = 0; index < audioSources.length; index++)
          if (effectiveBusIds[index] == bus.id) index,
      ];
      if (sourceIndices.isEmpty) continue;

      final inputLabels = sourceIndices.map((index) {
        final replacement = replacements[index];
        if (replacement != null) return '[' + replacement + ']';
        if (triggers.contains(index)) {
          return '[audBus' + index.toString() + ']';
        }
        return '[aud' + index.toString() + ']';
      }).join();
      final mixLabel = 'busMix' + busOutputIndex.toString();
      final outputLabel = 'busOut' + busOutputIndex.toString();
      if (sourceIndices.length == 1) {
        filters.add(inputLabels + 'anull[' + mixLabel + ']');
      } else {
        filters.add(
          inputLabels + 'amix=inputs=' + sourceIndices.length.toString() +
          ':duration=longest:normalize=0[' + mixLabel + ']',
        );
      }

      final busFilters = audioBusCompiler.compile(bus);
      if (busFilters.isEmpty) {
        filters.add('[' + mixLabel + ']anull[' + outputLabel + ']');
      } else {
        filters.add(
          '[' + mixLabel + ']' + busFilters.join(',') + '[' + outputLabel + ']',
        );
      }
      busOutputs.add('[' + outputLabel + ']');
      busOutputIndex++;
    }

    if (masterBus.muted || busOutputs.isEmpty) {
      filters.add(
        'anullsrc=channel_layout=stereo:sample_rate=48000:d=' +
            total + '[aout]',
      );
    } else if (busOutputs.length == 1) {
      filters.add(
        busOutputs.single + 'apad=whole_dur=' + total +
            ',atrim=duration=' + total + '[aout]',
      );
    } else {
      filters.add(
        busOutputs.join() + 'amix=inputs=' + busOutputs.length.toString() +
            ':duration=longest:dropout_transition=0:normalize=0,' +
            'apad=whole_dur=' + total + ',atrim=duration=' + total +
            ',alimiter=limit=0.95[aout]',
      );
    }
  }

  String _quote(String value) =>
      "'" + value.replaceAll("'", "'\\''") + "'";
}


class _AudioSource {
  const _AudioSource({
    required this.layer,
    required this.inputIndex,
    required this.streamSpecifier,
  });

  final CompositionLayer layer;
  final int inputIndex;
  final String streamSpecifier;
}
