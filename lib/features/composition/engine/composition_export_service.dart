import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/composition_models.dart';
import '../../fonts/data/font_manager_service.dart';
import 'audio_bus_compiler.dart';
import 'audio_equalizer_compiler.dart';
import 'ffmpeg_animation_compiler.dart';
import 'ffmpeg_filter_compiler.dart';
import 'ffmpeg_compositing_effect_compiler.dart';
import 'ffmpeg_blend_mode_compiler.dart';
import 'parent_transform_expression_resolver.dart';
import 'camera_projection_resolver.dart';
import 'parent_transform_resolver.dart';
import 'obj_mesh_loader.dart';
import 'scene_mesh_loader.dart';
import 'software_3d_renderer.dart';
import 'software_3d_png_encoder.dart';
import 'shape_layer_rasterizer.dart';
import 'text_plane_mesh_builder.dart';

typedef CompositionExportProgress = void Function(double value);

/// Signals that a local composition render should stop.
class CompositionExportCancelled implements Exception {
  const CompositionExportCancelled();

  @override
  String toString() => 'Composition render cancelled.';
}

/// Cooperative cancellation shared by frame preparation and FFmpeg sessions.
class CompositionExportCancellation {
  bool _cancelled = false;
  void Function()? _cancelHandler;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelHandler?.call();
  }

  void attachCancelHandler(void Function() handler) {
    _cancelHandler = handler;
    if (_cancelled) handler();
  }

  void clearCancelHandler() {
    _cancelHandler = null;
  }

  void throwIfCancelled() {
    if (_cancelled) throw const CompositionExportCancelled();
  }
}

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
    this.compositingEffectCompiler = const FfmpegCompositingEffectCompiler(),
    this.blendModeCompiler = const FfmpegBlendModeCompiler(),
  });

  final FfmpegFilterCompiler filterCompiler;
  final FfmpegAnimationCompiler animationCompiler;
  final AudioEqualizerCompiler audioEqualizerCompiler;
  final AudioBusCompiler audioBusCompiler;
  final ParentTransformExpressionResolver parentTransformResolver;
  final CameraProjectionResolver cameraProjectionResolver;
  final FfmpegCompositingEffectCompiler compositingEffectCompiler;
  final FfmpegBlendModeCompiler blendModeCompiler;

  Future<CompositionExportResult> export(
    CompositionDocument document, {
    CompositionExportProgress? onProgress,
    CompositionExportCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (document.width <= 0 || document.height <= 0 ||
        document.durationMs <= 0 || document.frameRate <= 0) {
      throw StateError('Composition size, frame rate and duration must be valid.');
    }

    const visualKinds = {
      LayerKind.video,
      LayerKind.image,
      LayerKind.photoshopLayer,
      LayerKind.threeDModel,
      LayerKind.text,
      LayerKind.shape,
    };
    final anySolo = document.layers.any((layer) =>
        layer.enabled &&
        !layer.guideLayer &&
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
      cancellation?.throwIfCancelled();
      if (layer.guideLayer) continue;
      if (layer.kind == LayerKind.text || layer.kind == LayerKind.shape) {
        visualLayers.add(layer);
      } else if (visualKinds.contains(layer.kind)) {
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
    final outputExtension = document.colorOutputProfile == ColorOutputProfile.rec709
        ? '.mp4'
        : '.mov';
    final output = File(
      outputDirectory.path + Platform.pathSeparator + name + outputExtension,
    );
    final meshTempDirectory = Directory(
      outputDirectory.path + Platform.pathSeparator + '.mesh-render-' +
      DateTime.now().microsecondsSinceEpoch.toString(),
    );
    final textTempDirectory = Directory(
      outputDirectory.path + Platform.pathSeparator + '.text-render-' +
      DateTime.now().microsecondsSinceEpoch.toString(),
    );
    final shapeTempDirectory = Directory(
      outputDirectory.path + Platform.pathSeparator + '.shape-render-' +
      DateTime.now().microsecondsSinceEpoch.toString(),
    );

    try {
      final textImagePaths = await _prepareTextLayerImages(
        document,
        visualLayers.where((layer) => layer.kind == LayerKind.text).toList(),
        textTempDirectory,
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      final threeDTextLayers = visualLayers.where(
        (layer) => layer.kind == LayerKind.text && layer.is3dText,
      ).toList();
      final textPlaneMeshes = await _prepareTextPlaneMeshes(
        threeDTextLayers,
        textImagePaths,
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      final meshRenderLayers = visualLayers.where(
        (layer) =>
            layer.kind == LayerKind.threeDModel ||
            (layer.kind == LayerKind.text && layer.is3dText),
      ).toList();
      final meshVideoPaths = await _prepareMeshLayerVideos(
        document,
        meshRenderLayers,
        meshTempDirectory,
        preloadedMeshes: textPlaneMeshes,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      final shapeImagePaths = await _prepareShapeLayerImages(
        document,
        visualLayers.where((layer) => layer.kind == LayerKind.shape).toList(),
        shapeTempDirectory,
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      final command = await _buildCommand(
        document,
        visualLayers,
        audioLayers,
        output.path,
        meshVideoPaths: meshVideoPaths,
        textImagePaths: textImagePaths,
        shapeImagePaths: shapeImagePaths,
      );
      final completion = Completer<void>();
      final start = FFmpegKit.executeAsync(
        command,
        onStatistics: (statistics) {
          final encodeProgress =
              (statistics.time / document.durationMs).clamp(0, 0.99).toDouble();
          onProgress?.call(0.2 + encodeProgress * 0.8);
        },
        onComplete: (session) {
          if (cancellation?.isCancelled ?? false) {
            if (!completion.isCompleted) {
              completion.completeError(const CompositionExportCancelled());
            }
          } else if (ReturnCode.isSuccess(session.getReturnCode())) {
            if (!completion.isCompleted) completion.complete();
          } else if (!completion.isCompleted) {
            completion.completeError(
              StateError(session.getFailStackTrace() ?? 'Composition render failed.'),
            );
          }
        },
      );
      unawaited(start.then<void>(
        (session) {
          cancellation?.attachCancelHandler(() {
            session.cancel();
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) completion.completeError(error, stackTrace);
        },
      ));
      await completion.future.timeout(const Duration(hours: 3));
      cancellation?.throwIfCancelled();
      if (!await output.exists() || await output.length() == 0) {
        throw StateError('FFmpeg completed without producing an output file.');
      }
      if (await meshTempDirectory.exists()) {
        await meshTempDirectory.delete(recursive: true);
      }
      if (await textTempDirectory.exists()) {
        await textTempDirectory.delete(recursive: true);
      }
      if (await shapeTempDirectory.exists()) {
        await shapeTempDirectory.delete(recursive: true);
      }
      onProgress?.call(1);
      return CompositionExportResult(
        file: output,
        renderedLayerCount: visualLayers.length + audioLayers.length,
        skippedLayerNames: List.unmodifiable(skipped),
      );
    } catch (_) {
      if (await output.exists()) await output.delete();
      if (await meshTempDirectory.exists()) {
        await meshTempDirectory.delete(recursive: true);
      }
      if (await textTempDirectory.exists()) {
        await textTempDirectory.delete(recursive: true);
      }
      if (await shapeTempDirectory.exists()) {
        await shapeTempDirectory.delete(recursive: true);
      }
      rethrow;
    } finally {
      cancellation?.clearCancelHandler();
    }
  }

  Future<Map<String, String>> _prepareMeshLayerVideos(
    CompositionDocument document,
    List<CompositionLayer> meshLayers,
    Directory tempDirectory, {
    CompositionExportProgress? onProgress,
    CompositionExportCancellation? cancellation,
    Map<String, ObjMesh> preloadedMeshes = const {},
  }) async {
    if (meshLayers.isEmpty) return const {};
    await tempDirectory.create(recursive: true);
    final result = <String, String>{};
    final cameraLayer = document.layers
        .where((layer) => layer.kind == LayerKind.camera && layer.enabled)
        .firstOrNull;
    final parentResolver = const ParentTransformResolver();
    const renderer = Software3dRenderer();
    const encoder = Software3dPngEncoder();

    for (var layerIndex = 0; layerIndex < meshLayers.length; layerIndex++) {
      cancellation?.throwIfCancelled();
      final layer = meshLayers[layerIndex];
      final sourcePath = layer.sourceUri;
      final preloadedMesh = preloadedMeshes[layer.id];
      if (preloadedMesh == null && (sourcePath == null || sourcePath.isEmpty)) {
        throw StateError('3D layer has no local mesh source.');
      }
      final mesh = preloadedMesh ??
          await const SceneMeshLoader().load(sourcePath!);
      cancellation?.throwIfCancelled();
      final frameDirectory = Directory(
        tempDirectory.path + Platform.pathSeparator + layer.id,
      );
      await frameDirectory.create(recursive: true);
      final frameCount = math.max(
        1,
        (layer.durationMs * document.frameRate / 1000).ceil(),
      ).toInt();
      final frameRate = document.frameRate;
      for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        cancellation?.throwIfCancelled();
        final localTimeMs = (frameIndex * 1000 / frameRate).round();
        final compositionTimeMs = layer.startMs + localTimeMs;
        final fileName = 'frame_' + frameIndex.toString().padLeft(6, '0') + '.png';
        final frameFile = File(
          frameDirectory.path + Platform.pathSeparator + fileName,
        );

        var rgbaFrame;
        final isInsideLayer = localTimeMs < layer.durationMs;
        final modelTransform = parentResolver.resolve(
          layer: layer,
          timeMs: compositionTimeMs,
          layers: document.layers,
        );
        if (isInsideLayer && modelTransform.enabled) {
          final cameraTransform = cameraLayer == null
              ? const ResolvedLayerTransform(
                  position: Vector3(0, 0, 0),
                  scale: Vector3(100, 100, 100),
                  rotation: Vector3(0, 0, 0),
                  opacity: 100,
                  enabled: true,
                )
              : parentResolver.resolve(
                  layer: cameraLayer,
                  timeMs: compositionTimeMs,
                  layers: document.layers,
                );
          final lights = <SceneLight>[
            for (final item in document.layers.where(
              (candidate) =>
                  candidate.kind == LayerKind.light && candidate.enabled,
            ))
              SceneLight(
                transform: parentResolver.resolve(
                  layer: item,
                  timeMs: compositionTimeMs,
                  layers: document.layers,
                ),
                settings: item.light ?? const LightSettings(),
              ),
          ];
          rgbaFrame = renderer.rasterizeFrame(
            mesh: mesh,
            width: document.width,
            height: document.height,
            compositionWidth: document.width.toDouble(),
            compositionHeight: document.height.toDouble(),
            modelTransform: modelTransform,
            cameraTransform: cameraTransform,
            cameraSettings: cameraLayer?.camera ?? const CameraSettings(),
            lights: lights,
            centerOnModel: false,
            timeMs: localTimeMs,
            animationIndex: layer.modelAnimationIndex,
          );
        } else {
          rgbaFrame = renderer.rasterizeFrame(
            mesh: const ObjMesh(
              vertices: [],
              triangles: [],
              materials: {},
              boundsMin: Vector3(0, 0, 0),
              boundsMax: Vector3(0, 0, 0),
            ),
            width: document.width,
            height: document.height,
            compositionWidth: document.width.toDouble(),
            compositionHeight: document.height.toDouble(),
            modelTransform: const ResolvedLayerTransform(
              position: Vector3(0, 0, 0),
              scale: Vector3(100, 100, 100),
              rotation: Vector3(0, 0, 0),
              opacity: 0,
              enabled: false,
            ),
            cameraTransform: const ResolvedLayerTransform(
              position: Vector3(0, 0, 0),
              scale: Vector3(100, 100, 100),
              rotation: Vector3(0, 0, 0),
              opacity: 100,
              enabled: true,
            ),
            cameraSettings: const CameraSettings(),
          );
        }
        final png = encoder.encodeRgba(
          width: rgbaFrame.width,
          height: rgbaFrame.height,
          rgba: rgbaFrame.rgba,
        );
        await frameFile.writeAsBytes(png, flush: false);
        onProgress?.call(
          0.2 *
              (layerIndex + (frameIndex + 1) / frameCount) /
              meshLayers.length,
        );
      }

      final duration = (layer.durationMs / 1000).toStringAsFixed(3);
      final videoPath = tempDirectory.path +
          Platform.pathSeparator +
          layer.id +
          '.mov';
      final pattern = frameDirectory.path +
          Platform.pathSeparator +
          'frame_%06d.png';
      final command = '-y -framerate ' + frameRate.toString() +
          ' -start_number 0 -i ' + _quote(pattern) +
          ' -frames:v ' + frameCount.toString() +
          ' -an -c:v qtrle -pix_fmt argb -t ' + duration +
          ' -r ' + frameRate.toString() + ' ' + _quote(videoPath);
      cancellation?.throwIfCancelled();
      await _executeFfmpeg(command, cancellation: cancellation);
      cancellation?.throwIfCancelled();
      result[layer.id] = videoPath;
    }
    return Map.unmodifiable(result);
  }

  Future<void> _executeFfmpeg(
    String command, {
    CompositionExportCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final completion = Completer<void>();
    final start = FFmpegKit.executeAsync(
      command,
      onComplete: (session) {
        if (cancellation?.isCancelled ?? false) {
          if (!completion.isCompleted) {
            completion.completeError(const CompositionExportCancelled());
          }
        } else if (ReturnCode.isSuccess(session.getReturnCode())) {
          if (!completion.isCompleted) completion.complete();
        } else if (!completion.isCompleted) {
          completion.completeError(
            StateError(session.getFailStackTrace() ?? '3D frame encoding failed.'),
          );
        }
      },
    );
    unawaited(start.then<void>(
      (session) {
        cancellation?.attachCancelHandler(() {
          session.cancel();
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completion.isCompleted) completion.completeError(error, stackTrace);
      },
    ));
    try {
      await completion.future.timeout(const Duration(hours: 3));
      cancellation?.throwIfCancelled();
    } finally {
      cancellation?.clearCancelHandler();
    }
  }


  Future<Map<String, ObjMesh>> _prepareTextPlaneMeshes(
    List<CompositionLayer> layers,
    Map<String, String> textImagePaths, {
    CompositionExportCancellation? cancellation,
  }) async {
    if (layers.isEmpty) return const <String, ObjMesh>{};
    const builder = TextPlaneMeshBuilder();
    final result = <String, ObjMesh>{};
    for (final layer in layers) {
      cancellation?.throwIfCancelled();
      final path = textImagePaths[layer.id];
      if (path == null) {
        throw StateError('3D text layer has no rasterized text image.');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw StateError('3D text raster is missing.');
      }
      result[layer.id] = await builder.fromPngBytes(
        await file.readAsBytes(),
        extrusionDepth: layer.textExtrusionDepth / 100,
        sideColor: layer.textColor,
      );
    }
    return Map.unmodifiable(result);
  }

  Future<Map<String, String>> _prepareShapeLayerImages(
    CompositionDocument document,
    List<CompositionLayer> shapeLayers,
    Directory directory, {
    CompositionExportCancellation? cancellation,
  }) async {
    if (shapeLayers.isEmpty) return const <String, String>{};
    await directory.create(recursive: true);
    const rasterizer = ShapeLayerRasterizer();
    final result = <String, String>{};

    for (var index = 0; index < shapeLayers.length; index++) {
      cancellation?.throwIfCancelled();
      final layer = shapeLayers[index];
      final style = layer.shapeStyle ?? const ShapeStyle();
      // Primitive shapes use the same 160x120 local canvas as the editor.
      // Pen paths occupy composition space, matching their preview bounds.
      final width = style.primitive == ShapePrimitive.path ? document.width : 160;
      final height = style.primitive == ShapePrimitive.path ? document.height : 120;
      final hasAnimatedPath = layer.keyframeTracks.any(
        (track) => track.enabled && track.property.startsWith('shape.vertex.'),
      );
      final layerDirectory = Directory(
        directory.path + Platform.pathSeparator +
            'shape_' + index.toString().padLeft(4, '0'),
      );

      if (hasAnimatedPath) {
        final frameCount = math.max(
          1,
          (layer.durationMs * document.frameRate / 1000).ceil(),
        ).toInt();
        if (frameCount > 36000) {
          throw StateError(
            'Animated shape layer ${layer.name} exceeds the 36,000-frame export limit.',
          );
        }
        await layerDirectory.create(recursive: true);
        for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
          cancellation?.throwIfCancelled();
          final compositionTimeMs = layer.startMs +
              (frameIndex * 1000 / document.frameRate).round();
          final png = await rasterizer.rasterize(
            layer,
            width: width,
            height: height,
            timeMs: compositionTimeMs,
          );
          final frameFile = File(
            layerDirectory.path + Platform.pathSeparator +
                'frame_' + frameIndex.toString().padLeft(6, '0') + '.png',
          );
          await frameFile.writeAsBytes(png, flush: true);
        }
        result[layer.id] = layerDirectory.path +
            Platform.pathSeparator + 'frame_%06d.png';
      } else {
        final png = await rasterizer.rasterize(
          layer,
          width: width,
          height: height,
          timeMs: layer.startMs,
        );
        final file = File(
          directory.path + Platform.pathSeparator +
              'shape_' + index.toString().padLeft(4, '0') + '.png',
        );
        await file.writeAsBytes(png, flush: true);
        result[layer.id] = file.path;
      }
    }
    return result;
  }

  Future<Map<String, String>> _prepareTextLayerImages(
    CompositionDocument document,
    List<CompositionLayer> textLayers,
    Directory directory, {
    CompositionExportCancellation? cancellation,
  }) async {
    if (textLayers.isEmpty) return const <String, String>{};
    await directory.create(recursive: true);
    final result = <String, String>{};
    final fontManager = FontManagerService.instance;

    for (var index = 0; index < textLayers.length; index++) {
      cancellation?.throwIfCancelled();
      final layer = textLayers[index];
      final family = layer.textFontFamily ?? fontManager.activeFamily;
      final fontPath = layer.textFontAssetUri ??
          (layer.textFontFamily == null ? fontManager.activeFontPath : null);
      try {
        await fontManager.ensureFontsLoaded(
          family: family,
          path: fontPath,
          fallbackFamilies: [
            ...layer.textFontFallback,
            ...fontManager.fallbackFamilies,
          ],
        );
      } catch (_) {
        // Continue with the saved fallback list and OS font fallback.
      }

      final content = layer.textContent ?? layer.name;
      final rawColor = layer.textColor.replaceFirst('#', '');
      final parsedColor = int.tryParse(rawColor, radix: 16);
      final color = parsedColor == null
          ? const Color(0xFFFFFFFF)
          : Color(rawColor.length == 6 ? 0xFF000000 | parsedColor : parsedColor);
      final weightIndex = ((layer.textFontWeight.clamp(100, 900) / 100)
                  .round() - 1)
              .clamp(0, 8)
              .toInt();
      final maxWidth = layer.textBoxWidth
          .clamp(1.0, math.max(1.0, document.width * 4.0))
          .toDouble();
      final direction = RegExp(r'[\u0590-\u08FF\uFB1D-\uFEFF]')
              .hasMatch(content)
          ? TextDirection.rtl
          : TextDirection.ltr;
      final alignment = switch (layer.textAlign) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        _ => TextAlign.left,
      };
      final painter = TextPainter(
        text: TextSpan(
          text: content,
          style: TextStyle(
            color: color,
            fontFamily: family,
            fontFamilyFallback: [
              ...layer.textFontFallback,
              ...fontManager.fallbackFamilies,
            ],
            fontSize: layer.textFontSize.clamp(1.0, 2000.0).toDouble(),
            fontWeight: FontWeight.values[weightIndex],
            fontStyle: layer.textItalic ? FontStyle.italic : FontStyle.normal,
            letterSpacing: layer.textLetterSpacing.clamp(-100.0, 500.0).toDouble(),
            height: layer.textLineHeight.clamp(0.1, 10.0).toDouble(),
            shadows: layer.is3dText
                ? const []
                : const [Shadow(color: Color(0xDD000000), blurRadius: 8)],
          ),
        ),
        textAlign: alignment,
        textDirection: direction,
      );
      painter.layout(maxWidth: maxWidth);
      if (painter.computeLineMetrics().length > 4000) {
        painter.dispose();
        throw StateError('Text layer ' + layer.name + ' exceeds the 4000-line render limit.');
      }

      const padding = 8;
      final imageWidth = math.max(1, painter.width.ceil() + padding * 2).toInt();
      final imageHeight = math.max(1, painter.height.ceil() + padding * 2).toInt();
      if (imageWidth > 16384 ||
          imageHeight > 16384 ||
          imageWidth * imageHeight > 16 * 1024 * 1024) {
        painter.dispose();
        throw StateError(
          'Text layer ' + layer.name +
              ' exceeds the safe 16-megapixel raster limit. Reduce font size or text-box dimensions.',
        );
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
      );
      painter.paint(canvas, const ui.Offset(8, 8));
      final picture = recorder.endRecording();
      final image = await picture.toImage(imageWidth, imageHeight);
      picture.dispose();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      painter.dispose();
      if (byteData == null) {
        throw StateError('Could not encode text layer ' + layer.name + ' as PNG.');
      }

      final png = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final file = File(
        directory.path + Platform.pathSeparator +
            'text_' + index.toString().padLeft(4, '0') + '.png',
      );
      await file.writeAsBytes(png, flush: true);
      result[layer.id] = file.path;
    }
    return result;
  }

  Future<String> _buildCommand(
    CompositionDocument document,
    List<CompositionLayer> visualLayers,
    List<CompositionLayer> audioLayers,
    String outputPath, {
    required Map<String, String> meshVideoPaths,
    required Map<String, String> textImagePaths,
    required Map<String, String> shapeImagePaths,
  }) async {
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
            layer.kind == LayerKind.photoshopLayer ||
            layer.kind == LayerKind.threeDModel ||
            layer.kind == LayerKind.text ||
            layer.kind == LayerKind.shape)
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
      if (layer.kind == LayerKind.threeDModel ||
          (layer.kind == LayerKind.text && layer.is3dText)) {
        final meshVideo = meshVideoPaths[layer.id];
        if (meshVideo == null) {
          throw StateError('3D layer has no rendered frame source.');
        }
        buffer.write('-i ' + _quote(meshVideo) + ' ');
        continue;
      }
      final duration = (layer.durationMs / 1000).toStringAsFixed(3);
      if (layer.kind == LayerKind.shape) {
        final shapeImage = shapeImagePaths[layer.id];
        if (shapeImage == null) {
          throw StateError('Shape layer ' + layer.name + ' has no rasterized shape image.');
        }
        final hasAnimatedPath = layer.keyframeTracks.any(
          (track) => track.enabled && track.property.startsWith('shape.vertex.'),
        );
        if (hasAnimatedPath) {
          buffer.write('-framerate ' + document.frameRate.toString() +
              ' -start_number 0 -i ' + _quote(shapeImage) + ' ');
        } else {
          buffer.write('-loop 1 -t ' + duration + ' -i ' + _quote(shapeImage) + ' ');
        }
        continue;
      }
      if (layer.kind == LayerKind.text) {
        final textImage = textImagePaths[layer.id];
        if (textImage == null) {
          throw StateError('Text layer ' + layer.name + ' has no rasterized text image.');
        }
        buffer.write('-loop 1 -t ' + duration + ' -i ' + _quote(textImage) + ' ');
        continue;
      }
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
        final adjustmentTransform = parentTransformResolver.resolve(
          layer: layer,
          layers: document.layers,
        );
        if (!adjustmentTransform.enabled) continue;
        final adjustmentEffects = filterCompiler.compileEffects(
          layer,
          timeMs: document.playheadMs,
          animationCompiler: animationCompiler,
        );
        if (adjustmentEffects.isEmpty) continue;

        final baseLabel = 'adjustmentBase' + index.toString();
        var adjusted = 'adjustmentWork' + index.toString();
        filters.add(
          '[' + previous + ']split=2[' + baseLabel + '][' + adjusted + ']',
        );
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

        final start = (layer.startMs / 1000).toStringAsFixed(6);
        final end = (layer.endMs / 1000).toStringAsFixed(6);
        final opacity = adjustmentTransform.opacity;
        final maskAlpha = animationCompiler.maskAlphaExpression(
          layer.masks,
          timeVariable: 'T',
        );
        final mixAlpha = '(min(1,max(0,(' + opacity + ')/100))*(' +
            maskAlpha + '))';
        final mix = 'if(gte(T,' + start + ')*lt(T,' + end +
            '),A*(1-' + mixAlpha + ')+B*' + mixAlpha + ',A)';
        final next = 'base' + (index + 1).toString();
        filters.add(
          '[' + baseLabel + '][' + adjusted + ']blend=all_expr=' +
              _quote(mix) + ':shortest=1,format=rgba[' + next + ']',
        );
        previous = next;
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
      final isMeshLayer = layer.kind == LayerKind.threeDModel ||
          (layer.kind == LayerKind.text && layer.is3dText);
      final projectedTransform = !isMeshLayer &&
              cameraLayer != null &&
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
      final sxBase = isMeshLayer
          ? '100'
          : resolvedTransform?.scaleX ?? localTransform.scaleX;
      final syBase = isMeshLayer
          ? '100'
          : resolvedTransform?.scaleY ?? localTransform.scaleY;
      final sx = animationCompiler.transitionScaleExpression(
        layer: layer, transitions: document.transitions,
        baseExpression: sxBase,
      );
      final sy = animationCompiler.transitionScaleExpression(
        layer: layer, transitions: document.transitions,
        baseExpression: syBase,
      );
      final rotation = isMeshLayer
          ? '0'
          : resolvedTransform?.rotationZ ?? localTransform.rotationZ;
      final opacity = resolvedTransform?.opacity ?? localTransform.opacity;
      final posXBase = isMeshLayer
          ? (width / 2).toStringAsFixed(3)
          : resolvedTransform?.positionX ?? localTransform.positionX;
      final posYBase = isMeshLayer
          ? (height / 2).toStringAsFixed(3)
          : resolvedTransform?.positionY ?? localTransform.positionY;
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
      final layerLabel = compositingEffectCompiler.compile(
        filters: filters,
        inputLabel: sourceLayerLabel,
        layer: layer,
        index: index,
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

    final outputProfile = document.colorOutputProfile;
    if (outputProfile == ColorOutputProfile.rec709) {
      filters.add('[' + previous + ']format=yuv420p[vout]');
    } else {
      final transfer = outputProfile == ColorOutputProfile.hdr10Pq
          ? 'smpte2084'
          : 'arib-std-b67';
      filters.add(
        '[' + previous + ']zscale='
        'primariesin=bt709:transferin=bt709:matrixin=bt709:'
        'primaries=bt2020:transfer=' + transfer +
        ':matrix=bt2020nc:range=limited:npl=1000,'
        'format=yuv422p10le[vout]',
      );
    }
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
    if (outputProfile == ColorOutputProfile.rec709) {
      buffer.write('-c:v mpeg4 -q:v 3 -pix_fmt yuv420p -movflags +faststart ');
    } else {
      final transfer = outputProfile == ColorOutputProfile.hdr10Pq
          ? 'smpte2084'
          : 'arib-std-b67';
      buffer.write(
        '-c:v prores_ks -profile:v 3 -vendor apl0 -pix_fmt yuv422p10le '
        '-color_primaries bt2020 -color_trc ' + transfer +
        ' -colorspace bt2020nc ',
      );
    }
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
    final mode = blendModeCompiler.filterMode(layer.blendMode);

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
