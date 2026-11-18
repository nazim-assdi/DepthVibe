import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/composition_models.dart';
import 'ffmpeg_animation_compiler.dart';
import 'ffmpeg_filter_compiler.dart';

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
  });

  final FfmpegFilterCompiler filterCompiler;
  final FfmpegAnimationCompiler animationCompiler;

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
    final anySolo = document.layers.any((layer) => layer.enabled && layer.solo);
    final enabled = document.layers.where(
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
      } else if (layer.kind == LayerKind.audio) {
        if (layer.audioSettings.muted) continue;
        final path = layer.sourceUri;
        if (path == null || path.isEmpty || !await File(path).exists()) {
          skipped.add(layer.name);
        } else {
          audioLayers.add(layer);
        }
      } else if (layer.kind != LayerKind.nullObject) {
        skipped.add(layer.name);
      }
    }

    if (visualLayers.isEmpty && audioLayers.isEmpty) {
      throw StateError('Import at least one video, image, Photoshop raster or audio layer.');
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

    for (var index = 0; index < visualLayers.length; index++) {
      final layer = visualLayers[index];
      if (layer.kind != LayerKind.video ||
          layer.audioSettings.muted ||
          !await _hasAudioStream(layer.sourceUri!)) {
        continue;
      }
      audioSources.add(_AudioSource(
        layer: layer,
        inputIndex: index + 1,
        streamSpecifier: 'a:0',
      ));
    }
    for (var index = 0; index < audioLayers.length; index++) {
      audioSources.add(_AudioSource(
        layer: audioLayers[index],
        inputIndex: visualLayers.length + index + 1,
        streamSpecifier: 'a:0',
      ));
    }

    buffer.write('-y -f lavfi -i ');
    buffer.write(_quote(
      'color=c=black:s=' + width.toString() + 'x' + height.toString() +
      ':r=' + document.frameRate.toString() + ':d=' + total,
    ));
    buffer.write(' ');

    for (final layer in visualLayers) {
      final duration = (layer.durationMs / 1000).toStringAsFixed(3);
      final source = _quote(layer.sourceUri!);
      if (layer.kind == LayerKind.image || layer.kind == LayerKind.photoshopLayer) {
        buffer.write('-loop 1 -t ' + duration + ' -i ' + source + ' ');
      } else {
        final sourceIn = (layer.sourceInMs / 1000).toStringAsFixed(3);
        buffer.write('-ss ' + sourceIn + ' -t ' + duration + ' -i ' + source + ' ');
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
      final inputIndex = index + 1;
      final start = (layer.startMs / 1000).toStringAsFixed(3);
      final duration = (layer.durationMs / 1000).toStringAsFixed(3);
      final sxBase = animationCompiler.scalarExpression(
        layer: layer, property: 'scale.x',
        fallback: layer.transform.scale.x,
      );
      final syBase = animationCompiler.scalarExpression(
        layer: layer, property: 'scale.y',
        fallback: layer.transform.scale.y,
      );
      final sx = animationCompiler.transitionScaleExpression(
        layer: layer, transitions: document.transitions,
        baseExpression: sxBase,
      );
      final sy = animationCompiler.transitionScaleExpression(
        layer: layer, transitions: document.transitions,
        baseExpression: syBase,
      );
      final rotation = animationCompiler.scalarExpression(
        layer: layer, property: 'rotation.z',
        fallback: layer.transform.rotation.z,
      );
      final opacity = animationCompiler.scalarExpression(
        layer: layer, property: 'opacity',
        fallback: layer.transform.opacity, timeVariable: 'T',
      );
      final posXBase = animationCompiler.scalarExpression(
        layer: layer, property: 'position.x',
        fallback: layer.transform.position.x,
      );
      final posYBase = animationCompiler.scalarExpression(
        layer: layer, property: 'position.y',
        fallback: layer.transform.position.y,
      );
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
      final mask = animationCompiler.maskAlphaExpression(layer.masks);
      final transition = animationCompiler.transitionAlphaExpression(
        layer: layer, transitions: document.transitions,
      );
      final alpha = '((' + mask + ')*(' + transition + ')*(' + opacity + ')/100)';
      final effects = filterCompiler.compileEffects(
        layer, timeMs: document.playheadMs,
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
      final layerLabel = 'layer' + index.toString();
      filters.add('[' + inputIndex.toString() + ':v]' +
          chain.join(',') + '[' + layerLabel + ']');
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
      final pan = settings.pan.clamp(-1, 1);
      final left = (1 - (pan > 0 ? pan : 0)).toStringAsFixed(4);
      final right = (1 + (pan < 0 ? pan : 0)).toStringAsFixed(4);
      final chain = <String>[
        'atrim=duration=' + (layer.durationMs / 1000).toStringAsFixed(3),
        'asetpts=PTS-STARTPTS+' + start.toStringAsFixed(3) + '/TB',
        'aformat=channel_layouts=stereo',
        "volume='pow(10,(" + gain + ")/20)':eval=frame",
        'pan=stereo|c0=c0*' + left + '|c1=c1*' + right,
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
      final triggerInputs = triggers.map((index) => '[aud' + index.toString() + ']').join();
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

    final labels = <String>[
      for (var index = 0; index < audioSources.length; index++)
        '[' + (replacements[index] ?? 'aud' + index.toString()) + ']',
    ];
    if (labels.length == 1) {
      filters.add(labels.first + 'apad=whole_dur=' + total +
          ',atrim=duration=' + total + '[aout]');
    } else {
      filters.add(labels.join() + 'amix=inputs=' + labels.length.toString() +
          ':duration=longest:dropout_transition=0:normalize=0,' +
          'apad=whole_dur=' + total + ',atrim=duration=' + total +
          ',alimiter=limit=0.95[aout]');
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
