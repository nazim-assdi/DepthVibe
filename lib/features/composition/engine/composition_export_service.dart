import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/composition_models.dart';
import 'ffmpeg_filter_compiler.dart';
import 'parent_transform_resolver.dart';

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

/// First CPU/native FFmpeg compositor pass for video and raster image layers.
/// Camera/light/3D models, masks, non-normal blend modes, transition timing
/// and GPU-only effects remain on the shared-renderer roadmap.
class CompositionExportService {
  const CompositionExportService({
    this.filterCompiler = const FfmpegFilterCompiler(),
  });

  final FfmpegFilterCompiler filterCompiler;

  Future<CompositionExportResult> export(
    CompositionDocument document, {
    CompositionExportProgress? onProgress,
  }) async {
    if (document.width <= 0 || document.height <= 0 || document.durationMs <= 0) {
      throw StateError('Composition size and duration must be valid.');
    }

    final candidates = document.layers.where((layer) =>
        layer.enabled &&
        (layer.kind == LayerKind.video ||
            layer.kind == LayerKind.image ||
            layer.kind == LayerKind.photoshopLayer) &&
        layer.sourceUri != null &&
        layer.sourceUri!.isNotEmpty);

    final renderable = <CompositionLayer>[];
    final supportedKinds = {
      LayerKind.video,
      LayerKind.image,
      LayerKind.photoshopLayer,
    };
    final skipped = document.layers
        .where((layer) =>
            layer.enabled &&
            (!supportedKinds.contains(layer.kind) ||
                layer.sourceUri == null ||
                layer.sourceUri!.isEmpty))
        .map((layer) => layer.name)
        .toList();
    for (final layer in candidates) {
      if (layer.blendMode != LayerBlendMode.normal ||
          layer.masks.any((mask) => mask.enabled)) {
        skipped.add(layer.name);
        continue;
      }
      final file = File(layer.sourceUri!);
      if (!await file.exists()) {
        skipped.add(layer.name);
        continue;
      }
      renderable.add(layer);
    }

    if (renderable.isEmpty) {
      throw StateError('Add at least one video, image or Photoshop raster layer.');
    }

    final directory = await getApplicationDocumentsDirectory();
    final outputDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}DepthVibe${Platform.pathSeparator}Compositions',
    );
    await outputDirectory.create(recursive: true);
    final name = 'Composition_${DateTime.now().toIso8601String().replaceAll(':', '-')}';
    final output = File(
      '${outputDirectory.path}${Platform.pathSeparator}$name.mp4',
    );
    final command = _buildCommand(document, renderable, output.path);
    final completion = Completer<void>();

    try {
      final start = FFmpegKit.executeAsync(
        command,
        onStatistics: (statistics) {
          final duration = document.durationMs;
          if (duration > 0) {
            onProgress?.call(
              (statistics.time / duration).clamp(0, 0.99).toDouble(),
            );
          }
        },
        onComplete: (session) {
          if (ReturnCode.isSuccess(session.getReturnCode())) {
            if (!completion.isCompleted) completion.complete();
          } else if (!completion.isCompleted) {
            completion.completeError(
              StateError(
                session.getFailStackTrace() ?? 'Composition render failed.',
              ),
            );
          }
        },
      );
      unawaited(start.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) {
            completion.completeError(error, stackTrace);
          }
        },
      ));
      await completion.future.timeout(const Duration(hours: 3));
      if (!await output.exists() || await output.length() == 0) {
        throw StateError('FFmpeg completed without producing an MP4 file.');
      }
      onProgress?.call(1);
      return CompositionExportResult(
        file: output,
        renderedLayerCount: renderable.length,
        skippedLayerNames: List.unmodifiable(skipped),
      );
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  String _buildCommand(
    CompositionDocument document,
    List<CompositionLayer> layers,
    String outputPath,
  ) {
    final totalSeconds = (document.durationMs / 1000).toStringAsFixed(3);
    final buffer = StringBuffer();
    final filters = <String>[];

    buffer.write('-y -f lavfi -i ');
    buffer.write(_quote(
      'color=c=black:s=${document.width}x${document.height}:r=${document.frameRate}:d=$totalSeconds',
    ));
    buffer.write(' ');

    for (final layer in layers) {
      final source = layer.sourceUri!;
      final duration = (layer.durationMs / 1000).toStringAsFixed(3);
      if (layer.kind == LayerKind.photoshopLayer || layer.kind == LayerKind.image) {
        buffer.write('-loop 1 -t $totalSeconds -i ${_quote(source)} ');
      } else {
        buffer.write('-ss 0 -t $duration -i ${_quote(source)} ');
      }
    }

    filters.add('[0:v]format=rgba[base0]');
    var previous = 'base0';

    for (var index = 0; index < layers.length; index++) {
      final layer = layers[index];
      final inputIndex = index + 1;
      final sourceWidth =
          layer.sourceWidth > 0 ? layer.sourceWidth : document.width;
      final sourceHeight =
          layer.sourceHeight > 0 ? layer.sourceHeight : document.height;
      final resolved = const ParentTransformResolver().resolve(
        layer: layer,
        timeMs: document.playheadMs,
        layers: document.layers,
      );
      final width = (sourceWidth * resolved.scale.x / 100)
          .abs()
          .round()
          .clamp(1, document.width * 4)
          .toInt();
      final height = (sourceHeight * resolved.scale.y / 100)
          .abs()
          .round()
          .clamp(1, document.height * 4)
          .toInt();
      final x = resolved.position.x - width / 2;
      final y = resolved.position.y - height / 2;
      final start = (layer.startMs / 1000).toStringAsFixed(3);
      final layerDuration = (layer.durationMs / 1000).toStringAsFixed(3);
      final effectFilters = filterCompiler.compileEffects(
        layer,
        timeMs: document.playheadMs,
      );
      final chain = <String>[
        'trim=duration=$layerDuration',
        'setpts=PTS-STARTPTS+$start/TB',
        'scale=$width:$height',
        if (resolved.rotation.z != 0)
          'rotate=${(resolved.rotation.z * 3.141592653589793 / 180).toStringAsFixed(6)}:ow=rotw(iw):oh=roth(ih):c=none',
        ...effectFilters,
        'format=rgba',
        'colorchannelmixer=aa=${(resolved.opacity / 100).clamp(0, 1).toStringAsFixed(3)}',
      ];
      final label = 'layer$index';
      filters.add('[$inputIndex:v]${chain.join(',')}[$label]');
      final next = 'base${index + 1}';
      filters.add(
        '[$previous][$label]overlay=x=${x.toStringAsFixed(2)}:y=${y.toStringAsFixed(2)}:eof_action=pass:shortest=0[$next]',
      );
      previous = next;

    }

    filters.add('[$previous]format=yuv420p[vout]');
    buffer.write('-filter_complex ${_quote(filters.join(';'))} ');
    buffer.write('-map "[vout]" ');
    // Audio tracks and source-video audio are deliberately not mixed in this
    // first shared compositor pass. The Video Studio export retains its audio.
    buffer.write('-an ');
    buffer.write('-t $totalSeconds ');
    buffer.write('-r ${document.frameRate} ');
    buffer.write('-c:v mpeg4 -q:v 3 -pix_fmt yuv420p -movflags +faststart ');
    buffer.write(_quote(outputPath));
    return buffer.toString();
  }

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
