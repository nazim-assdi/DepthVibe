import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_svg/flutter_svg.dart' as vg;
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/depthvibe_brand_mark.dart';
import '../../../app/depthvibe_settings.dart';
import '../../../app/depthvibe_settings_dialog.dart';
import '../application/composition_controller.dart';
import '../../fonts/data/font_manager_service.dart';
import '../../fonts/presentation/font_manager_dialog.dart';
import '../../fonts/presentation/font_picker_dialog.dart';
import '../data/effect_catalog.dart';
import '../data/audio_preset_catalog.dart';
import '../data/color_preset_catalog.dart';
import '../data/creative_asset_pack_catalog.dart';
import '../data/creative_asset_pack_service.dart';
import '../data/effect_preset_catalog.dart';
import '../../extensions/data/extension_manager_service.dart';
import '../../extensions/data/adobe_bridge_service.dart';
import '../../extensions/presentation/extension_marketplace_screen.dart';
import '../data/photoshop_import_service.dart';
import '../domain/composition_models.dart';
import '../data/motion_preset_catalog.dart';
import '../data/title_preset_catalog.dart';
import '../data/overlay_sticker_catalog.dart';
import '../data/open_asset_source_catalog.dart';
import '../data/motion_preset_package.dart';
import '../data/motion_bro_pack_service.dart';
import '../data/transition_catalog.dart';
import '../data/transition_preset_catalog.dart';
import '../domain/color_grade_preset.dart';
import '../engine/parent_transform_resolver.dart';
import '../engine/camera_projection_resolver.dart';
import '../engine/composition_export_service.dart';
import '../engine/composition_project_service.dart';
import '../engine/composition_recovery_service.dart';
import '../engine/obj_mesh_loader.dart';
import '../engine/scene_mesh_loader.dart';
import '../engine/software_3d_renderer.dart';
import '../engine/gpu_3d_mesh_view.dart';
import '../engine/audio_waveform_service.dart';
import '../engine/color_grade_preview.dart';
import '../engine/cube_lut_validator.dart';
import '../engine/motion_tracking_service.dart';
import '../engine/transition_frame_validator.dart';
import '../engine/preview_frame_service.dart';
import '../engine/preview_proxy_service.dart';
import 'text_layer_content_editor.dart';
import 'color_wheel_control.dart';
import 'color_curve_editor.dart';
import 'color_scopes_view.dart';
import 'transition_preview_tile.dart';
import 'effect_preview_tile.dart';

class CompositionWorkspace extends StatefulWidget {
  const CompositionWorkspace({
    super.key,
    this.startupWarning,
    this.mediaProcessingAvailable = true,
  });

  final String? startupWarning;
  final bool mediaProcessingAvailable;

  @override
  State<CompositionWorkspace> createState() => _CompositionWorkspaceState();
}

class _CompositionWorkspaceState extends State<CompositionWorkspace>
    with WidgetsBindingObserver {
  final CompositionController _controller = CompositionController();
  final PhotoshopImportService _photoshop = const PhotoshopImportService();
  final CompositionExportService _exporter = const CompositionExportService();
  final MotionTrackingService _tracker = const MotionTrackingService();
  final AudioWaveformService _waveformService = const AudioWaveformService();
  final Map<String, Future<File?>> _waveformJobs = {};
  final LinkedHashMap<String, Future<File?>> _videoFrameJobs =
      LinkedHashMap<String, Future<File?>>();
  final Map<String, File> _lastVideoFrames = {};
  final Map<String, String> _latestRequestedFrameKey = {};
  final Map<String, String> _previewFrameErrors = {};
  final LinkedHashMap<String, Future<FileStat>> _sourceStatJobs =
      LinkedHashMap<String, Future<FileStat>>();
  final Map<String, Future<img.Image?>> _scopeImageJobs = {};
  final Map<String, Future<ObjMesh>> _meshJobs = {};
  final Map<String, Future<void>> _previewChunkJobs = {};
  Future<void> _previewChunkTail = Future<void>.value();
  final PreviewProxyService _previewProxyService = PreviewProxyService();
  final Set<String> _previewProxyRequests = {};
  final PreviewFrameService _previewFrameService = PreviewFrameService(
    maxConcurrentDecodes: DepthVibeSettingsService
        .instance.performanceMode.previewDecodeConcurrency,
    maxCachedFrames: DepthVibeSettingsService
        .instance.performanceMode.previewCacheFrameLimit,
  );
  Future<Directory>? _previewCacheDirectoryJob;
  bool _previewCacheJanitorRunning = false;
  int _previewFramesSinceTrim = 0;
  String _curveChannel = 'master';
  final CreativeAssetPackService _creativeAssetPacks =
      CreativeAssetPackService.instance;
  List<InstalledCreativeAssetPack> _installedCreativePacks = [];
  bool _creativePackBusy = false;
  int _creativePackReceived = 0;
  int _creativePackTotal = 0;
  final MotionBroPackService _motionBroService = MotionBroPackService.instance;
  List<MotionBroPresetPack> _motionBroPacks = [];
  bool _motionBroBusy = false;
  String _motionBroSearch = '';

  Future<File?> _waveformFor(String path) =>
      _waveformJobs.putIfAbsent(path, () => _waveformService.generate(path));

  Future<ObjMesh> _meshFor(String path) =>
      _meshJobs.putIfAbsent(path, () => const SceneMeshLoader().load(path));

  String _quoteFfmpeg(String value) =>
      "'" + value.replaceAll("'", "'\\''") + "'";

  Future<Directory> _previewCacheDirectory() {
    return _previewCacheDirectoryJob ??= getTemporaryDirectory().then((root) async {
      final directory = Directory(
        root.path + Platform.pathSeparator +
            'DepthVibe' + Platform.pathSeparator + 'PreviewFrames',
      );
      await directory.create(recursive: true);
      return directory;
    });
  }

  Future<void> _trimPreviewCacheIfNeeded() async {
    _previewFramesSinceTrim++;
    if (_previewFramesSinceTrim < 64 || _previewCacheJanitorRunning) return;
    _previewFramesSinceTrim = 0;
    _previewCacheJanitorRunning = true;
    try {
      final directory = await _previewCacheDirectory();
      final pinnedPaths = _lastVideoFrames.values
          .map((file) => file.path)
          .toSet();
      final entries = <({File file, int size, DateTime modified})>[];
      var totalBytes = 0;

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.jpg')) continue;
        try {
          final stat = await entity.stat();
          if (entity.path.contains('.part.jpg')) {
            // Partial FFmpeg outputs from a crash/timeout are never valid
            // cache entries. A live decode cannot last beyond the 10s timeout.
            if (DateTime.now().difference(stat.modified) >
                const Duration(minutes: 2)) {
              await entity.delete();
            }
            continue;
          }
          totalBytes += stat.size;
          entries.add((
            file: entity,
            size: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {}
      }

      const hardLimitBytes = 512 * 1024 * 1024;
      const targetBytes = 384 * 1024 * 1024;
      if (totalBytes <= hardLimitBytes) return;

      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        if (totalBytes <= targetBytes) break;
        if (pinnedPaths.contains(entry.file.path)) continue;
        try {
          if (await entry.file.exists()) {
            await entry.file.delete();
            totalBytes -= entry.size;
          }
        } catch (_) {}
      }
    } catch (error, stackTrace) {
      debugPrint('DepthVibe preview cache cleanup skipped: $error\\n$stackTrace');
    } finally {
      _previewCacheJanitorRunning = false;
    }
  }

  Future<FileStat> _sourceStatFor(String path) {
    return _sourceStatJobs.putIfAbsent(path, () => File(path).stat());
  }


  String _previewFrameDiskKey({
    required String fingerprint,
    required int frameIndex,
    required double frameRate,
    required int width,
  }) =>
      '${fingerprint}_${frameIndex}_${frameRate.toStringAsFixed(1)}_${width}';

  File _previewFrameFile(Directory directory, String diskKey) => File(
        directory.path + Platform.pathSeparator +
            'dvpreview_${diskKey.hashCode.toUnsigned(32).toRadixString(16)}.jpg',
      );

  Future<void> _ensurePreviewFrameChunk({
    required String path,
    required Directory cacheDirectory,
    required String fingerprint,
    required int chunkStartFrame,
    required int chunkFrameCount,
    required double frameRate,
    required int width,
    required int decodeThreads,
  }) {
    final chunkKey = '${fingerprint}_${chunkStartFrame}_'
        '${frameRate.toStringAsFixed(1)}_${width}';
    final existing = _previewChunkJobs[chunkKey];
    if (existing != null) return existing;

    final chunkDirectory = Directory(
      cacheDirectory.path + Platform.pathSeparator +
          'chunk_${chunkKey.hashCode.toUnsigned(32).toRadixString(16)}.part',
    );

    // Serialize expensive lookahead jobs across layers. The exact requested
    // frame is decoded first; these batches are only cache warmers.
    final job = _previewChunkTail.then((_) async {
      try {
        if (await chunkDirectory.exists()) {
          await chunkDirectory.delete(recursive: true);
        }
        await chunkDirectory.create(recursive: true);

        final startMs = (chunkStartFrame * 1000 / frameRate).round();
        final outputPattern = File(
          chunkDirectory.path + Platform.pathSeparator + 'frame_%06d.jpg',
        );
        final command = '-hide_banner -loglevel error -y '
            '-filter_threads 1 -threads $decodeThreads '
            '-ss ${(startMs / 1000).toStringAsFixed(3)} '
            '-i ${_quoteFfmpeg(path)} -map 0:v:0 -an -sn -dn '
            '-frames:v $chunkFrameCount '
            '-vf "fps=${frameRate.toStringAsFixed(3)},'
            'scale=$width:$width:force_original_aspect_ratio=decrease:'
            'flags=fast_bilinear" '
            '-q:v 5 ${_quoteFfmpeg(outputPattern.path)}';

        final session = await FFmpegKit.executeAsync(command).timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            final activeSessions = FFmpegKit.getFFmpegSessions()
                .where((running) =>
                    running.getCommand().contains(chunkDirectory.path))
                .toList();
            for (final running in activeSessions) {
              running.cancel();
            }
            throw TimeoutException(
              'Generating a realtime preview frame chunk exceeded 45 seconds.',
            );
          },
        );

        if (!ReturnCode.isSuccess(session.getReturnCode())) {
          final output = (session.getOutput() ?? '').trim();
          final details = output.length > 900
              ? output.substring(output.length - 900)
              : output;
          throw StateError(
            'FFmpeg batch decoder returned ${session.getReturnCode()}. '
            '${details.isEmpty ? 'No FFmpeg diagnostic was returned.' : details}',
          );
        }

        final frames = await chunkDirectory
            .list(followLinks: false)
            .where((entity) => entity is File)
            .cast<File>()
            .toList();
        frames.sort((a, b) => a.path.compareTo(b.path));

        for (var index = 0; index < frames.length; index++) {
          final frameIndex = chunkStartFrame + index;
          final diskKey = _previewFrameDiskKey(
            fingerprint: fingerprint,
            frameIndex: frameIndex,
            frameRate: frameRate,
            width: width,
          );
          final destination = _previewFrameFile(cacheDirectory, diskKey);
          try {
            if (await destination.exists() &&
                await destination.length() > 0) {
              continue;
            }
            final partial = File(destination.path + '.part.jpg');
            try {
              if (await partial.exists()) await partial.delete();
            } catch (_) {}
            await frames[index].copy(partial.path);
            if (await destination.exists()) await destination.delete();
            await partial.rename(destination.path);
          } catch (_) {
            try {
              final partial = File(destination.path + '.part.jpg');
              if (await partial.exists()) await partial.delete();
            } catch (_) {}
          }
        }
      } catch (error, stackTrace) {
        debugPrint(
          'DepthVibe preview chunk generation failed: $error\\n$stackTrace',
        );
        rethrow;
      } finally {
        try {
          if (await chunkDirectory.exists()) {
            await chunkDirectory.delete(recursive: true);
          }
        } catch (_) {}
      }
    });

    _previewChunkTail = job.catchError((_) {});
    _previewChunkJobs[chunkKey] = job;
    return job.whenComplete(() {
      if (identical(_previewChunkJobs[chunkKey], job)) {
        _previewChunkJobs.remove(chunkKey);
      }
    });
  }

  Future<File?> _decodeSinglePreviewFrame({
    required String path,
    required int seekMs,
    required File frame,
    required int width,
    required int decodeThreads,
  }) async {
    final partialFrame = File(frame.path + '.single.part.jpg');
    try {
      if (await partialFrame.exists()) await partialFrame.delete();
    } catch (_) {}

    final command = '-hide_banner -loglevel error -y '
        '-filter_threads 1 -threads $decodeThreads '
        '-ss ${(seekMs / 1000).toStringAsFixed(3)} '
        '-i ${_quoteFfmpeg(path)} -map 0:v:0 -an -sn -dn '
        '-frames:v 1 '
        '-vf "scale=$width:$width:force_original_aspect_ratio=decrease:'
        'flags=fast_bilinear" '
        '-q:v 5 ${_quoteFfmpeg(partialFrame.path)}';

    final session = await FFmpegKit.executeAsync(command).timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        final activeSessions = FFmpegKit.getFFmpegSessions()
            .where((running) =>
                running.getCommand().contains(partialFrame.path))
            .toList();
        for (final running in activeSessions) {
          running.cancel();
        }
        unawaited(
          partialFrame.delete().catchError((_) => partialFrame),
        );
        throw TimeoutException(
          'Realtime preview frame decode exceeded 12 seconds.',
        );
      },
    );

    if (!ReturnCode.isSuccess(session.getReturnCode()) ||
        !await partialFrame.exists() ||
        await partialFrame.length() == 0) {
      final output = (session.getOutput() ?? '').trim();
      final details = output.length > 900
          ? output.substring(output.length - 900)
          : output;
      try {
        if (await partialFrame.exists()) await partialFrame.delete();
      } catch (_) {}
      throw StateError(
        'FFmpeg could not decode a preview frame '
        '(exit code ${session.getReturnCode()}). '
        '${details.isEmpty ? 'No FFmpeg diagnostic was returned.' : details}',
      );
    }

    try {
      if (await frame.exists()) await frame.delete();
      return await partialFrame.rename(frame.path);
    } catch (_) {
      try {
        if (await partialFrame.exists()) await partialFrame.delete();
      } catch (_) {}
      return null;
    }
  }

  Future<File?> _decodePreviewFrame({
    required String path,
    required int frameIndex,
    required double previewFrameRate,
    required int seekMs,
    required String laneId,
    required int width,
    required int decodeThreads,
    required bool prefetch,
    required bool warmChunk,
  }) async {
    try {
      if (!await File(path).exists()) {
        if (!prefetch) {
          _previewFrameErrors[laneId] = 'Source video file was not found: $path';
        }
        return null;
      }
      final stat = await _sourceStatFor(path);
      final cacheDirectory = await _previewCacheDirectory();
      final fingerprint =
          '${path.hashCode.toUnsigned(32)}_${stat.size}_'
          '${stat.modified.microsecondsSinceEpoch}';
      final profile = DepthVibeSettingsService.instance.performanceMode;
      final proxy = await _previewProxyService.findCachedProxy(
        sourcePath: path,
        width: profile.previewFrameWidth,
        frameRate: profile.previewFrameRate,
      );
      final decodePath = proxy?.path ?? path;
      final decodeFingerprint = '${fingerprint}_${proxy == null ? 'source' : 'proxy'}';
      final diskKey = _previewFrameDiskKey(
        fingerprint: decodeFingerprint,
        frameIndex: frameIndex,
        frameRate: previewFrameRate,
        width: width,
      );
      final frame = _previewFrameFile(cacheDirectory, diskKey);
      final chunkFrameCount = math.max(1, previewFrameRate.round());
      final chunkStartFrame =
          (frameIndex ~/ chunkFrameCount) * chunkFrameCount;
      final chunkKey = '${decodeFingerprint}_${chunkStartFrame}_'
          '${previewFrameRate.toStringAsFixed(1)}_${width}';
      final pendingChunk = _previewChunkJobs[chunkKey];
      String? decodeFailure;

      final decodedFrame = await _previewFrameService.requestFrame(
        laneId: laneId,
        cacheKey: diskKey,
        cacheFile: frame,
        decodedFrameCount: pendingChunk == null ? 1 : chunkFrameCount,
        isPrefetch: prefetch,
        decode: () async {
          if (await frame.exists() && await frame.length() > 0) {
            return frame;
          }

          // If a batch is already warming this segment, join it and read its
          // frame. Otherwise decode the exact requested frame immediately.
          if (pendingChunk != null) {
            try {
              // Reuse an almost-finished lookahead batch, but never let a
              // background chunk hold the visible playhead for seconds.
              await pendingChunk.timeout(
                const Duration(milliseconds: 120),
              );
            } on TimeoutException {
              // Keep the batch running in the background and decode only the
              // requested visible frame below.
            } catch (error) {
              debugPrint('DepthVibe preview batch fallback: $error');
            }
            if (await frame.exists() && await frame.length() > 0) {
              return frame;
            }
          }

          final File? completedFrame;
          try {
            completedFrame = await _decodeSinglePreviewFrame(
              path: decodePath,
              seekMs: seekMs,
              frame: frame,
              width: width,
              decodeThreads: decodeThreads,
            );
          } catch (error) {
            // PreviewFrameService isolates native decoder exceptions and
            // resolves the request with null; retain the reason for the UI.
            decodeFailure = error.toString();
            rethrow;
          }

          // Never delay the first visible frame for an 18/24/30-frame batch.
          // Once it is on screen, predecode one second ahead in the background.
          if (completedFrame != null && warmChunk && _previewPlaying) {
            unawaited(
              Future<void>.delayed(const Duration(milliseconds: 24))
                  .then((_) => _ensurePreviewFrameChunk(
                        path: decodePath,
                        cacheDirectory: cacheDirectory,
                        fingerprint: decodeFingerprint,
                        chunkStartFrame: chunkStartFrame,
                        chunkFrameCount: chunkFrameCount,
                        frameRate: previewFrameRate,
                        width: width,
                        decodeThreads: decodeThreads,
                      ))
                  .catchError((error) {
                debugPrint('DepthVibe preview lookahead skipped: $error');
              }),
            );
          }
          return completedFrame;
        },
      );
      if (decodedFrame == null && !prefetch && decodeFailure != null) {
        _previewFrameErrors[laneId] = decodeFailure!;
      }
      return decodedFrame;
    } catch (error, stackTrace) {
      if (!prefetch) _previewFrameErrors[laneId] = error.toString();
      debugPrint(
        'DepthVibe preview frame decode failed'
        '${prefetch ? ' (prefetch)' : ''}: $error\\n$stackTrace',
      );
      return null;
    }
  }

  Future<File?> _videoFrameFor(
    CompositionLayer layer,
    int timelineTimeMs,
    double frameRate, {
    bool prefetch = false,
  }) {
    final path = layer.sourceUri;
    if (path == null || path.isEmpty || frameRate <= 0) {
      return Future<File?>.value(null);
    }
    final profile = DepthVibeSettingsService.instance.performanceMode;
    _previewFrameService
      ..maxConcurrentDecodes = profile.previewDecodeConcurrency
      ..configurePreviewProfile(
        width: profile.previewFrameWidth,
        frameRate: profile.previewFrameRate,
      );
    final previewFps = math.min(
      frameRate,
      _previewFrameService.effectivePreviewFrameRate.toDouble(),
    );
    final sourceTimeMs = math.max(
      0,
      layer.sourceInMs + timelineTimeMs - layer.startMs,
    );
    final frameIndex = (sourceTimeMs * previewFps / 1000).floor();
    final seekMs = (frameIndex * 1000 / previewFps).round();
    final width = _previewFrameService.effectivePreviewWidth;
    final requestKey =
        '${path.hashCode.toUnsigned(32)}_${layer.id}_'
        '${frameIndex}_${width}_${previewFps.toStringAsFixed(1)}';
    // A prefetch completion must not be reused as the visible job because the
    // visible consumer also updates the layer's last-known-good frame state.
    // The lower decode/cache layer still deduplicates the same source frame.
    final jobMapKey = prefetch ? '${requestKey}_prefetch' : requestKey;

    if (!prefetch) {
      _latestRequestedFrameKey[layer.id] = requestKey;
    }
    final existing = _videoFrameJobs.remove(jobMapKey);
    if (existing != null) {
      _videoFrameJobs[jobMapKey] = existing;
      return existing;
    }

    late final Future<File?> job;
    job = _decodePreviewFrame(
      path: path,
      frameIndex: frameIndex,
      previewFrameRate: previewFps,
      seekMs: seekMs,
      laneId: layer.id,
      width: width,
      decodeThreads: profile.previewDecodeConcurrency,
      prefetch: prefetch,
      warmChunk: _previewPlaying || prefetch,
    ).then((frame) {
      if (frame == null) {
        // A completed failed Future must never pin a layer to a blank preview.
        // A later rebuild or explicit Retry can start a clean decoder request.
        if (identical(_videoFrameJobs[requestKey], job)) {
          _videoFrameJobs.remove(requestKey);
        }
        return null;
      }

      final isLatestVisibleFrame =
          !prefetch && _latestRequestedFrameKey[layer.id] == requestKey;
      if (isLatestVisibleFrame) {
        _previewFrameErrors.remove(layer.id);
        if (_previewPlaying && _previewDecoderNeedsProxy()) {
          _schedulePreviewProxy(path);
        }
        // Keep every successfully decoded playhead frame as the visible
        // fallback while a later frame is loading or being retried.
        _lastVideoFrames[layer.id] = frame;
        unawaited(_trimPreviewCacheIfNeeded());
      }
      final chunkFrameCount = math.max(1, previewFps.round());
      if (isLatestVisibleFrame &&
          frameIndex % chunkFrameCount == 0) {
        // Prefetch one full batch ahead, but only once at the start of each
        // chunk; otherwise every visible frame would replace the pending job.
        final nextTimeMs = timelineTimeMs + 1000;
        unawaited(
          _videoFrameFor(
            layer,
            nextTimeMs,
            frameRate,
            prefetch: true,
          ).catchError((_) => null),
        );
      }
      return frame;
    });

    _videoFrameJobs[jobMapKey] = job;
    while (_videoFrameJobs.length > 96) {
      _videoFrameJobs.remove(_videoFrameJobs.keys.first);
    }
    while (_sourceStatJobs.length > 32) {
      _sourceStatJobs.remove(_sourceStatJobs.keys.first);
    }
    return job;
  }

  bool _previewDecoderNeedsProxy() {
    final profile = DepthVibeSettingsService.instance.performanceMode;
    final stats = _previewFrameService.stats;
    final frameBudgetMs = 1000 / profile.previewFrameRate;
    return (stats.lastDecodeMs > 0 &&
            stats.averageDecodeMs > frameBudgetMs * 1.2) ||
        stats.averageQueueWaitMs > frameBudgetMs * 1.2;
  }

  void _schedulePreviewProxy(String sourcePath) {
    final profile = DepthVibeSettingsService.instance.performanceMode;
    final requestKey =
        '$sourcePath|${profile.previewFrameWidth}|${profile.previewFrameRate}';
    if (!_previewProxyRequests.add(requestKey)) return;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2)).then((_) {
        if (!mounted || !_previewPlaying) {
          _previewProxyRequests.remove(requestKey);
          return null;
        }
        return _previewProxyService.queueProxy(
          sourcePath: sourcePath,
          width: profile.previewFrameWidth,
          frameRate: profile.previewFrameRate,
        );
      }).then((proxy) {
        if (proxy == null) {
          debugPrint('DepthVibe preview proxy unavailable; original source remains active.');
        } else {
          debugPrint('DepthVibe preview proxy ready: ${proxy.path}');
        }
      }).catchError((Object error) {
        debugPrint('DepthVibe preview proxy generation skipped: $error');
      }),
    );
  }

  void _retryVideoPreview(CompositionLayer layer) {
    final sourcePath = layer.sourceUri;
    if (sourcePath != null) {
      _previewProxyRequests.removeWhere((key) => key.startsWith('$sourcePath|'));
    }
    _previewFrameErrors.remove(layer.id);
    _latestRequestedFrameKey.remove(layer.id);
    final failedFrame = _lastVideoFrames.remove(layer.id);
    if (failedFrame != null) {
      unawaited(failedFrame.delete().catchError((_) => failedFrame));
    }
    final marker = '_${layer.id}_';
    _videoFrameJobs.removeWhere((key, _) => key.contains(marker));
    if (mounted) {
      setState(() => _notice = 'Retrying video preview for ${layer.name}…');
    }
  }

  Future<img.Image?> _scopeImageFor(
    CompositionLayer layer,
    int timelineTimeMs,
    double frameRate,
  ) {
    final path = layer.sourceUri;
    if (path == null || path.isEmpty) return Future<img.Image?>.value(null);
    final frame = layer.kind == LayerKind.video
        ? (timelineTimeMs < layer.startMs || timelineTimeMs >= layer.endMs
            ? -1
            : ((layer.sourceInMs + timelineTimeMs - layer.startMs) *
                    frameRate /
                    1000)
                .floor())
        : 0;
    final key = '${path}_scope_${frame}_${frameRate.toStringAsFixed(3)}';
    return _scopeImageJobs.putIfAbsent(key, () async {
      File? source;
      if (layer.kind == LayerKind.video) {
        if (frame < 0) return null;
        source = await _videoFrameFor(layer, timelineTimeMs, frameRate);
      } else {
        source = File(path);
      }
      if (source == null || !await source.exists()) return null;
      return img.decodeImage(await source.readAsBytes());
    });
  }

  bool _tracking = false;
  double _trackingLeft = 100;
  double _trackingTop = 100;
  double _trackingWidth = 100;
  double _trackingHeight = 100;
  double _trackingThreshold = 0.30;
  bool _stabilizeTracking = true;
  bool _rendering = false;
  bool _previewPlaying = false;
  Timer? _previewPlaybackTimer;
  double _renderProgress = 0;
  CompositionExportCancellation? _renderCancellation;
  String _panel = 'Transform';
  String _leftPanel = 'Project';
  String _leftEffectSearch = '';
  String _workspacePreset = 'After Effects';
  final List<String> _rightPanelOrder = [
    'Transform',
    'Effects',
    'Animation',
    'Layers',
    'Timing',
    'Typography',
    'Shape',
    'Color',
    'Masks',
    'Tracking',
    'Parent',
    '3D',
    'Audio',
    'Bus Mixer',
    'Transitions',
    'Library',
  ];
  String? _graphTrackLabel;
  bool _graphEditorVisible = false;
  bool _graphSpeedMode = false;
  int? _selectedGraphKeyframeMs;
  int? _draggingGraphKeyframeMs;
  _KeyframeGraphGeometry? _graphDragGeometry;
  bool _graphDragHistoryRecorded = false;
  bool _graphScrubbing = false;
  bool _showCanvasGrid = true;
  bool _autoKeyEnabled = false;
  bool _showLayerControls = true;
  bool _showMotionPaths = true;
  double _previewZoom = 1;
  Offset _previewPanOffset = Offset.zero;
  String _activePreviewTool = 'Select';
  String? _previewMoveLayerId;
  Offset _previewMoveLastGlobal = Offset.zero;
  bool _previewMoveHistoryRecorded = false;
  String? _previewResizeLayerId;
  double _previewResizeStartScaleX = 100;
  double _previewResizeStartScaleY = 100;
  Offset _previewResizeStartGlobal = Offset.zero;
  bool _previewResizeHistoryRecorded = false;
  String? _previewRotateLayerId;
  double _previewRotateStartDegrees = 0;
  double _previewRotateStartPointerRadians = 0;
  Offset _previewRotateCenterGlobal = Offset.zero;
  bool _previewRotateHistoryRecorded = false;
  String? _previewMotionLayerId;
  int? _previewMotionKeyTimeMs;
  Offset _previewMotionLastGlobal = Offset.zero;
  bool _previewMotionHistoryRecorded = false;
  double _leftPanelWidth = 270;
  double _rightPanelWidth = 340;
  final Set<String> _expandedTimelineLayers = {};
  String _effectCategory = 'All';
  String _effectSearch = '';
  String _transitionCategory = 'All';
  String _transitionSearch = '';
  String _libraryFilter = 'All';
  String _librarySearch = '';
  String? _notice;
  final CompositionProjectService _projectService = const CompositionProjectService();
  final CompositionRecoveryService _recoveryService = const CompositionRecoveryService();
  bool _projectBusy = false;
  bool _recoverySaving = false;
  bool _recoveryDirty = false;
  int _documentRevision = 0;
  Timer? _recoveryTimer;
  File? _currentProjectFile;
  String _autosaveStatus = 'Autosave ready';

  static const _layerButtons = <(LayerKind, String, IconData)>[
    (LayerKind.video, 'Video', Icons.movie_outlined),
    (LayerKind.image, 'Image', Icons.image_outlined),
    (LayerKind.shape, 'Shape', Icons.category_outlined),
    (LayerKind.text, 'Text', Icons.text_fields),
    (LayerKind.nullObject, 'Null', Icons.control_camera),
    (LayerKind.adjustment, 'Adjust', Icons.tune),
    (LayerKind.camera, 'Camera', Icons.videocam_outlined),
    (LayerKind.light, 'Light', Icons.lightbulb_outline),
    (LayerKind.threeDModel, '3D Model', Icons.view_in_ar),
    (LayerKind.audio, 'Audio', Icons.graphic_eq),
    (LayerKind.particle, 'Particles', Icons.auto_awesome),
    (LayerKind.precomposition, 'Precomp', Icons.layers_outlined),
  ];

  CompositionLayer? get _selected => _controller.selectedLayer;

  @override
  void initState() {
    super.initState();
    _notice = widget.startupWarning;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_onFlutterFrameTimings);
    _controller.addListener(_onCompositionChanged);
    ExtensionManagerService.instance.addListener(_onExtensionsChanged);
    _motionBroService.addListener(_onMotionBroPacksChanged);
    unawaited(_loadMotionBroPacks());
    _creativeAssetPacks.addListener(_onCreativeAssetPacksChanged);
    unawaited(_loadCreativeAssetPacks());
    AdobeBridgeService.instance.attachController(_controller);
    _recoveryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _autosaveIfNeeded(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForCrashRecovery());
    });
  }

  void _onFlutterFrameTimings(List<ui.FrameTiming> timings) {
    if (!_previewPlaying) return;
    for (final timing in timings) {
      _previewFrameService.recordUiFrameDuration(
        timing.buildDuration + timing.rasterDuration,
      );
    }
  }

  void _onExtensionsChanged() {
    if (mounted) setState(() {});
  }

  void _onMotionBroPacksChanged() {
    if (mounted) setState(() => _motionBroPacks = _motionBroService.packs);
  }

  void _onCreativeAssetPacksChanged() {
    if (!mounted) return;
    setState(() {
      _installedCreativePacks = _creativeAssetPacks.installed;
      _creativePackReceived = _creativeAssetPacks.receivedBytes;
      _creativePackTotal = _creativeAssetPacks.totalBytes;
    });
  }

  Future<void> _loadCreativeAssetPacks() async {
    try {
      await _creativeAssetPacks.initialize();
      if (mounted) {
        setState(() => _installedCreativePacks = _creativeAssetPacks.installed);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Offline asset library could not be opened: ' + error.toString());
      }
    }
  }

  Future<void> _loadMotionBroPacks() async {
    try {
      await _motionBroService.initialize();
      if (mounted) setState(() => _motionBroPacks = _motionBroService.packs);
    } catch (error) {
      if (mounted) setState(() => _notice = 'Motion Bro library could not be loaded: $error');
    }
  }

  Future<void> _importMotionBroPack() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['mbr', 'zip'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw StateError('The selected Motion Bro pack has no readable local path.');
      }
      if (mounted) setState(() => _motionBroBusy = true);
      final pack = await _motionBroService.importPackage(File(path));
      if (mounted) {
        setState(() {
          _motionBroPacks = _motionBroService.packs;
          _notice = 'Imported "' + pack.name + '" with ' +
              pack.assets.length.toString() + ' assets. Refresh the Adobe host panel to see compatible FFX/MOGRT files.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Motion Bro import failed: $error');
    } finally {
      if (mounted) setState(() => _motionBroBusy = false);
    }
  }

  Future<void> _exportMotionBroPack(MotionBroPresetPack pack) async {
    try {
      final temporary = await getTemporaryDirectory();
      final safeName = pack.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final output = File(
        temporary.path + Platform.pathSeparator +
            safeName + '_' + DateTime.now().microsecondsSinceEpoch.toString() + '.mbr',
      );
      await _motionBroService.exportPackage(pack.id, outputFile: output);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(output.path)],
        text: 'Motion Bro pack archive. Share only where the pack license permits.',
      ));
    } catch (error) {
      if (mounted) setState(() => _notice = 'Motion Bro export failed: $error');
    }
  }

  Future<void> _removeMotionBroPack(MotionBroPresetPack pack) async {
    await _motionBroService.uninstall(pack.id);
    if (mounted) {
      setState(() {
        _motionBroPacks = _motionBroService.packs;
        _notice = 'Removed imported pack "' + pack.name + '" from the local library.';
      });
    }
  }

  Widget _buildMotionBroPackBrowser() {
    final term = _motionBroSearch.trim().toLowerCase();
    final children = <Widget>[
      _panelHeader('MOTION BRO · IMPORTED PACKS', Icons.video_library_outlined),
      OutlinedButton.icon(
        onPressed: _motionBroBusy ? null : _importMotionBroPack,
        icon: _motionBroBusy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.folder_zip_outlined, size: 16),
        label: Text(_motionBroBusy ? 'IMPORTING PACK…' : 'IMPORT .MBR PACK'),
      ),
      TextField(
        decoration: const InputDecoration(
          labelText: 'Search imported preset packs/assets',
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 17),
        ),
        onChanged: (value) => setState(() => _motionBroSearch = value),
      ),
      const Text(
        'FFX assets are applied from the After Effects host panel; MOGRT assets are inserted from the Premiere host panel. JSX/JSXBIN files are catalogued but never auto-executed.',
        style: TextStyle(fontSize: 9, color: Color(0xFFE3C28D)),
      ),
    ];
    if (_motionBroPacks.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No Motion Bro packs imported yet. Choose a licensed .MBR pack to browse its presets.',
          style: TextStyle(fontSize: 10, color: Color(0xFF9DABC3))),
      ));
    }
    for (final pack in _motionBroPacks) {
      final matchingAssets = pack.assets.where((asset) {
        if (term.isEmpty) return true;
        return (pack.name + ' ' + asset.fileName + ' ' +
            asset.category + ' ' + asset.extension).toLowerCase().contains(term);
      }).toList();
      if (term.isNotEmpty && matchingAssets.isEmpty &&
          !pack.name.toLowerCase().contains(term)) continue;
      children.add(
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(pack.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          subtitle: Text(
            pack.author + ' · v' + pack.version + ' · ' +
                pack.assets.length.toString() + ' assets · ' +
                pack.afterEffectsPresetCount.toString() + ' FFX · ' +
                pack.premiereTemplateCount.toString() + ' MOGRT',
            style: const TextStyle(fontSize: 9),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'export') _exportMotionBroPack(pack);
              if (action == 'remove') _removeMotionBroPack(pack);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Export original .MBR archive')),
              PopupMenuItem(value: 'remove', child: Text('Remove imported pack')),
            ],
          ),
          children: [
            for (final asset in matchingAssets)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 8, right: 4),
                leading: Icon(
                  asset.isAfterEffectsPreset
                      ? Icons.auto_awesome
                      : asset.isPremiereMotionGraphicsTemplate
                          ? Icons.movie_filter_outlined
                          : asset.isScript
                              ? Icons.code
                              : Icons.insert_drive_file_outlined,
                  size: 16,
                ),
                title: Text(asset.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10)),
                subtitle: Text(
                  asset.category + ' · ' + asset.extension.toUpperCase() +
                      ' · ' + (asset.sizeBytes / (1024 * 1024)).toStringAsFixed(1) + ' MB' +
                      (asset.previewRelativePath == null ? '' : ' · preview available'),
                  style: const TextStyle(fontSize: 9),
                ),
                trailing: Text(
                  asset.isAfterEffectsPreset
                      ? 'AE'
                      : asset.isPremiereMotionGraphicsTemplate
                          ? 'PR'
                          : asset.isScript ? 'CODE' : 'ASSET',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF9DABC3)),
                ),
              ),
            if (matchingAssets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No matching assets in this pack.', style: TextStyle(fontSize: 9)),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Future<void> _openSettings() => DepthVibeSettingsDialog.show(context);

  Future<void> _openFontManager() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const FontManagerDialog(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _chooseLayerFont(CompositionLayer layer) async {
    final font = await FontPickerDialog.show(
      context,
      currentFamily: layer.textFontFamily,
    );
    if (!mounted || font == null) return;
    await _applyLayerFont(font);
  }

  int _fontWeightForStyle(String? style) =>
      FontManagerService.suggestedWeight(style);

  Future<void> _applyLayerFont(FontCatalogEntry? font) async {
    if (font == null) {
      _controller.updateTextLayer(clearTextFont: true);
      return;
    }
    try {
      if (font.isImported) {
        await FontManagerService.instance.ensureFontLoaded(
          family: font.family,
          path: font.path,
        );
      }
      final styleName = (font.styleName ?? '').toLowerCase();
      _controller.updateTextLayer(
        textFontFamily: font.family,
        textFontAssetUri: font.isImported ? font.path : null,
        clearTextFontAsset: !font.isImported,
        textFontWeight: _fontWeightForStyle(font.styleName),
        textItalic: FontManagerService.isItalicStyle(styleName),
      );
    } catch (error) {
      if (mounted) setState(() => _notice = 'Font could not be loaded: $error');
    }
  }

  void _onCompositionChanged() {
    _documentRevision++;
    _recoveryDirty = true;
    _autosaveStatus = 'Unsaved changes';
    final layer = _controller.selectedLayer;
    if (layer != null && layer.kind == LayerKind.text &&
        layer.textFontFamily != null && layer.textFontAssetUri != null) {
      unawaited(FontManagerService.instance.ensureFontsLoaded(
        family: layer.textFontFamily,
        path: layer.textFontAssetUri,
        fallbackFamilies: [
          ...layer.textFontFallback,
          ...FontManagerService.instance.fallbackFamilies,
        ],
      ).then<void>(
        (_) { if (mounted) setState(() {}); },
        onError: (Object _) {},
      ));
    }
  }

  Future<Directory> _recoveryDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      documents.path + Platform.pathSeparator +
          'DepthVibe' + Platform.pathSeparator + 'Recovery',
    );
  }

  Future<void> _autosaveIfNeeded() async {
    if (_recoverySaving ||
        !_recoveryDirty ||
        _projectBusy ||
        _rendering) {
      return;
    }
    _recoverySaving = true;
    final revision = _documentRevision;
    final snapshot = _controller.document;
    try {
      final directory = await _recoveryDirectory();
      await _recoveryService.save(snapshot, recoveryDirectory: directory);
      if (revision == _documentRevision) {
        _recoveryDirty = false;
        _autosaveStatus = 'Autosaved ' + DateTime.now().toLocal().toString();
        if (mounted) setState(() {});
      }
    } catch (error) {
      _autosaveStatus = 'Autosave failed';
      if (mounted) {
        setState(() => _notice = 'Autosave failed: ' + error.toString());
      }
    } finally {
      _recoverySaving = false;
    }
  }

  Future<void> _checkForCrashRecovery() async {
    try {
      final directory = await _recoveryDirectory();
      final snapshot = await _recoveryService.load(
        recoveryDirectory: directory,
      );
      if (snapshot == null || !mounted) return;
      final recover = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('RECOVER UNSAVED PROJECT?'),
          content: Text(
            'DepthVibe found an autosave from ' +
                snapshot.savedAt.toLocal().toString() +
                '. Restore ' + snapshot.document.name +
                ' with ' + snapshot.document.layers.length.toString() +
                ' layers?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('DISCARD'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('RECOVER PROJECT'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (recover == true) {
        _controller.replaceDocument(snapshot.document);
        _recoveryDirty = false;
        _currentProjectFile = null;
        _autosaveStatus = 'Recovered unsaved project';
        setState(() {
          _notice = 'Recovered "' + snapshot.document.name +
              '" from crash-recovery autosave. Save a .dvproj copy to keep it portable.';
        });
      } else {
        await _recoveryService.clear(recoveryDirectory: directory);
        _recoveryDirty = false;
        _autosaveStatus = 'Recovery discarded';
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Crash recovery could not be opened: ' +
            error.toString());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pausePreviewPlayback();
      unawaited(_autosaveIfNeeded());
    }
  }

  String _localAssetPath(String path) {
    if (path.toLowerCase().startsWith('file://')) {
      try {
        return Uri.parse(path).toFilePath();
      } on FormatException {
        return path;
      }
    }
    return path;
  }

  Future<List<String>> _missingMediaPaths() async {
    final candidates = <String>{};
    for (final layer in _controller.document.layers) {
      for (final path in [
        layer.sourceUri,
        layer.sourceDocumentUri,
        layer.smartObjectSourceUri,
        for (final effect in layer.effects) effect.assetUri,
      ]) {
        if (path != null &&
            path.isNotEmpty &&
            !path.startsWith('http://') &&
            !path.startsWith('https://')) {
          candidates.add(path);
        }
      }
    }
    final missing = <String>[];
    for (final path in candidates) {
      if (!await File(_localAssetPath(path)).exists()) missing.add(path);
    }
    missing.sort();
    return missing;
  }

  Future<void> _relinkMissingMedia() async {
    if (_projectBusy || _rendering) return;
    final missing = await _missingMediaPaths();
    if (missing.isEmpty) {
      if (mounted) setState(() => _notice = 'All local media references are available.');
      return;
    }

    var relinked = 0;
    try {
      for (final oldPath in missing) {
        if (!mounted) return;
        setState(() {
          _projectBusy = true;
          _notice = 'Relink ' + (relinked + 1).toString() +
              ' of ' + missing.length.toString() + ': ' + oldPath;
        });
        final picked = await FilePicker.pickFile(type: FileType.any);
        if (picked == null) break;
        final pickedPath = picked.path;
        if (pickedPath == null || pickedPath.isEmpty) {
          throw StateError('The selected replacement file has no local path.');
        }
        final source = File(pickedPath);
        if (!await source.exists()) {
          throw StateError('The selected replacement file does not exist.');
        }

        final documents = await getApplicationDocumentsDirectory();
        final targetDirectory = Directory(
          documents.path + Platform.pathSeparator +
              'DepthVibe' + Platform.pathSeparator + 'RelinkedAssets',
        );
        await targetDirectory.create(recursive: true);
        final originalName = picked.name.replaceAll(
          RegExp(r'[^A-Za-z0-9._-]'),
          '_',
        );
        final safeName = originalName.isEmpty ? 'media.bin' : originalName;
        final destination = File(
          targetDirectory.path + Platform.pathSeparator +
              DateTime.now().microsecondsSinceEpoch.toString() +
              '_' + safeName,
        );
        final copied = await source.copy(destination.path);
        _controller.relinkAssetReference(oldPath, copied.path);
        relinked++;
      }
      if (mounted) {
        setState(() {
          _notice = 'Relinked ' + relinked.toString() + ' of ' +
              missing.length.toString() + ' missing media references.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Media relink failed: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _projectBusy = false);
    }
  }

  Future<void> _showProjectVersionHistory() async {
    final projectFile = _currentProjectFile;
    if (projectFile == null) {
      setState(() => _notice = 'Save this composition as a .dvproj first to create version history.');
      return;
    }
    try {
      final versions = await _projectService.listProjectVersions(projectFile);
      if (!mounted) return;
      if (versions.isEmpty) {
        setState(() => _notice = 'No previous project versions have been saved yet.');
        return;
      }
      final selected = await showDialog<CompositionProjectVersion>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('PROJECT VERSION HISTORY'),
          content: SizedBox(
            width: 460,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final version in versions)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(version.modifiedAt.toLocal().toString()),
                    subtitle: Text(
                      (version.sizeBytes / (1024 * 1024)).toStringAsFixed(1) +
                          ' MB · ' + version.file.uri.pathSegments.last,
                    ),
                    onTap: () => Navigator.of(dialogContext).pop(version),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('RESTORE THIS VERSION?'),
          content: const Text(
            'The selected version will replace the current composition. Save the current state first if you need to keep it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('RESTORE'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() {
        _projectBusy = true;
        _notice = 'Restoring project version…';
      });
      final documents = await getApplicationDocumentsDirectory();
      final imported = await _projectService.importProject(
        selected.file,
        projectsDirectory: Directory(
          documents.path + Platform.pathSeparator +
              'DepthVibe' + Platform.pathSeparator + 'Projects' +
              Platform.pathSeparator + 'HistoryRestores',
        ),
      );
      _controller.replaceDocument(imported.document);
      final recovery = await _recoveryDirectory();
      await _recoveryService.clear(recoveryDirectory: recovery);
      _recoveryDirty = true;
      if (mounted) {
        setState(() {
          _currentProjectFile = projectFile;
          _notice = 'Restored version of "' + imported.document.name + '".';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Version restore failed: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _projectBusy = false);
    }
  }


  Future<void> _runMotionTracking() async {
    final layer = _selected;
    if (layer == null || layer.kind != LayerKind.video || layer.sourceUri == null) {
      setState(() => _notice = 'Select a video layer before running tracking.');
      return;
    }
    setState(() {
      _tracking = true;
      _notice = 'Extracting the tracking region and analysing the clip…';
    });
    try {
      final result = await _tracker.track(
        sourcePath: layer.sourceUri!,
        left: _trackingLeft.round(),
        top: _trackingTop.round(),
        width: _trackingWidth.round(),
        height: _trackingHeight.round(),
        threshold: _trackingThreshold,
      );
      _controller.applyMotionTrack(
        layerId: layer.id,
        samples: result.samples,
        sourceWidth: result.sourceWidth,
        sourceHeight: result.sourceHeight,
        stabilize: _stabilizeTracking,
      );
      if (!mounted) return;
      setState(() {
        _notice = 'Tracked ' + result.samples.length.toString() +
            ' samples. Position keyframes added to ' + layer.name + '.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _notice = 'Tracking failed: ' + error.toString());
    } finally {
      if (mounted) setState(() => _tracking = false);
    }
  }

  Widget _trackingField(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return SizedBox(
      width: 112,
      child: TextFormField(
        initialValue: value.toStringAsFixed(0),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (text) {
          final parsed = double.tryParse(text);
          if (parsed != null) onChanged(parsed);
        },
      ),
    );
  }

  Future<void> _importPhotoshop() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['psd', 'psb'],
      );
      if (picked == null) return;
      final sourcePath = picked.path;
      if (sourcePath == null) {
        setState(() => _notice = 'This provider did not expose a local PSD/PSB file path.');
        return;
      }
      setState(() => _notice = 'Reading Photoshop layer structure…');
      final document = await _photoshop.importDocument(sourcePath);
      _controller.addPhotoshopLayers(
        sourceDocumentUri: sourcePath,
        documentWidth: document.width,
        documentHeight: document.height,
        assets: document.layers,
      );
      setState(() {
        _notice =
            'Imported ${document.visibleLayerCount} Photoshop layers, '
            '${document.groupCount} groups, ${document.clippedLayerCount} clipping layers '
            'and ${document.smartObjectCount} Smart Objects from '
            '${document.width}×${document.height} document';
        _panel = 'Layers';
      });
    } catch (error) {
      setState(() => _notice = 'PSD/PSB import failed: $error');
    }
  }

  Future<void> _addLayer(LayerKind kind) async {
    if (kind == LayerKind.video ||
        kind == LayerKind.image ||
        kind == LayerKind.audio ||
        kind == LayerKind.threeDModel) {
      final file = kind == LayerKind.threeDModel
          ? await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: const ['obj', 'gltf', 'glb'],
            )
          : await FilePicker.pickFile(
              type: switch (kind) {
                LayerKind.video => FileType.video,
                LayerKind.audio => FileType.audio,
                _ => FileType.image,
              },
            );
      if (file == null) return;
      final sourcePath = file.path;
      if (sourcePath == null) {
        setState(() => _notice = 'This provider did not expose a local file path.');
        return;
      }
      var width = _controller.document.width;
      var height = _controller.document.height;
      if (kind == LayerKind.image) {
        final decoded = img.decodeImage(await File(sourcePath).readAsBytes());
        if (decoded != null) {
          width = decoded.width;
          height = decoded.height;
        }
      }
      _controller.addLayer(
        kind,
        name: file.name,
        sourceUri: sourcePath,
        sourceWidth: width,
        sourceHeight: height,
      );
    } else {
      _controller.addLayer(kind);
    }
    if (!mounted) return;
    setState(() {
      _panel = switch (kind) {
        LayerKind.text => 'Typography',
        LayerKind.shape => 'Shape',
        LayerKind.camera || LayerKind.light || LayerKind.threeDModel => '3D',
        LayerKind.nullObject => 'Parent',
        LayerKind.adjustment => 'Effects',
        _ => 'Layers',
      };
      _notice = '${kind.name} layer added. Animate its Transform or Effects.';
    });
  }

  void _pausePreviewPlayback() {
    _previewPlaybackTimer?.cancel();
    _previewPlaybackTimer = null;
    if (_previewPlaying && mounted) {
      setState(() => _previewPlaying = false);
    } else {
      _previewPlaying = false;
    }
  }

  void _togglePreviewPlayback() {
    if (_previewPlaybackTimer != null) {
      _pausePreviewPlayback();
      return;
    }
    final document = _controller.document;
    if (document.durationMs <= 0) return;

    final startTime = document.playheadMs >= document.durationMs - 1
        ? 0
        : document.playheadMs;
    final stopwatch = Stopwatch()..start();
    var lastTickMs = -1;

    setState(() {
      _previewPlaying = true;
      if (startTime == 0 && document.playheadMs >= document.durationMs - 1) {
        _controller.setPlayhead(0);
      }
    });

    // Poll cheaply, but move the playhead only at the scheduler's current
    // adaptive FPS. If decodes slow down, the transport cadence follows it;
    // when performance recovers, the adaptive controller raises it again.
    _previewPlaybackTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final currentDocument = _controller.document;
        final effectiveFps = math.min(
          currentDocument.frameRate,
          _previewFrameService.effectivePreviewFrameRate,
        );
        final frameIntervalMs = (1000 / math.max(1, effectiveFps)).round();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (lastTickMs >= 0 && elapsedMs - lastTickMs < frameIntervalMs) {
          return;
        }
        lastTickMs = elapsedMs;

        final duration = currentDocument.durationMs;
        final nextTime = startTime + elapsedMs;
        if (duration <= 0 || nextTime >= duration) {
          _controller.setPlayhead(math.max(0, duration - 1));
          _pausePreviewPlayback();
          return;
        }
        _controller.setPlayhead(nextTime);
      },
    );
  }

  void _cancelCompositionRender() {
    final cancellation = _renderCancellation;
    if (cancellation == null || cancellation.isCancelled) return;
    cancellation.cancel();
    if (mounted) {
      setState(() => _notice = 'Stopping render and cleaning temporary files…');
    }
  }

  Future<void> _exportComposition() async {
    if (_rendering) return;
    if (!widget.mediaProcessingAvailable) {
      setState(() {
        _notice =
            'The video processing engine is unavailable. Layer editing is ready; MP4 rendering will unlock when FFmpeg starts.';
      });
      return;
    }
    _pausePreviewPlayback();
    final cancellation = CompositionExportCancellation();
    _renderCancellation = cancellation;
    setState(() {
      _rendering = true;
      _renderProgress = 0;
      _notice = 'Preparing composition render…';
    });
    try {
      final result = await _exporter.export(
        _controller.document,
        cancellation: cancellation,
        onProgress: (value) {
          if (mounted) setState(() => _renderProgress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _notice = result.skippedLayerNames.isEmpty
            ? 'Rendered ${result.renderedLayerCount} layers (silent first-pass compositor): ${result.file.path}'
            : 'Rendered ${result.renderedLayerCount} layers (silent first-pass compositor). Skipped: ${result.skippedLayerNames.join(', ')}';
      });
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.file.path)],
          text: 'Composition rendered with DepthVibe by N Tech',
        ),
      );
    } on CompositionExportCancelled {
      if (mounted) {
        setState(() => _notice = 'Composition render cancelled. Temporary files cleaned.');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Composition render failed: $error');
    } finally {
      _renderCancellation = null;
      if (mounted) setState(() => _rendering = false);
    }
  }

  void _addKeyframe(String property) {
    _controller.addKeyframe(property);
    setState(() => _notice = 'Keyframe added at ${_time(_controller.document.playheadMs)}');
  }

  Future<void> _editBezierCurve(
    String property,
    BezierCurve initialCurve, {
    String? effectId,
    String? maskId,
    String? busId,
    int? timeMs,
  }) async {
    var draft = initialCurve;
    final result = await showDialog<BezierCurve>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('BEZIER GRAPH EDITOR'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Drag either control handle to shape the animation easing.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9AA8BD)),
                ),
                const SizedBox(height: 12),
                _BezierCurveEditor(
                  curve: draft,
                  onChanged: (curve) => setDialogState(() => draft = curve),
                ),
                const SizedBox(height: 8),
                Text(
                  'P1  ${draft.x1.toStringAsFixed(2)}, ${draft.y1.toStringAsFixed(2)}'
                  '     P2  ${draft.x2.toStringAsFixed(2)}, ${draft.y2.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFB7C3D5)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(draft),
              child: const Text('APPLY CURVE'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (maskId != null) {
      _controller.setMaskBezierCurve(
        maskId,
        property,
        result,
        timeMs: timeMs,
      );
    } else if (busId != null) {
      _controller.setAudioBusBezierCurve(
        busId,
        property,
        result,
        timeMs: timeMs,
      );
    } else {
      _controller.setBezierCurve(
        property,
        result,
        effectId: effectId,
        timeMs: timeMs,
      );
    }
    setState(() => _notice = 'Bezier curve updated for $property');
  }

  String _time(int ms) {
    final seconds = ms ~/ 1000;
    final frames = ((ms % 1000) / 1000 * _controller.document.frameRate).floor();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _recoveryTimer?.cancel();
    _previewPlaybackTimer?.cancel();
    _renderCancellation?.cancel();
    _controller.removeListener(_onCompositionChanged);
    ExtensionManagerService.instance.removeListener(_onExtensionsChanged);
    _motionBroService.removeListener(_onMotionBroPacksChanged);
    _creativeAssetPacks.removeListener(_onCreativeAssetPacksChanged);
    AdobeBridgeService.instance.detachController(_controller);
    WidgetsBinding.instance.removeTimingsCallback(_onFlutterFrameTimings);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_autosaveIfNeeded());
    _previewFrameService.dispose();
    _previewProxyService.dispose();
    _previewProxyRequests.clear();
    _videoFrameJobs.clear();
    _previewChunkJobs.clear();
    _lastVideoFrames.clear();
    _latestRequestedFrameKey.clear();
    _previewFrameErrors.clear();
    _sourceStatJobs.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final doc = _controller.document;
        final layer = _selected;
        final palette = Theme.of(context).extension<DepthVibePalette>()!;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 58,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DepthVibeBrandMark(size: 32),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DEPTHVIBE STUDIO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.15,
                      ),
                    ),
                    Text(
                      '${doc.name}  •  ${doc.width} × ${doc.height}  •  ${doc.frameRate.toStringAsFixed(0)} FPS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context)
                            .extension<DepthVibePalette>()!
                            .secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Settings · View and appearance',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              IconButton(
                tooltip: 'Undo',
                onPressed: _controller.canUndo ? _controller.undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: _controller.canRedo ? _controller.redo : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: 'Open .dvproj project',
                onPressed: _projectBusy || _rendering
                    ? null
                    : _openCompositionProject,
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                tooltip: 'Save complete .dvproj project',
                onPressed: _projectBusy || _rendering
                    ? null
                    : _saveCompositionProject,
                icon: const Icon(Icons.save_alt),
              ),
              IconButton(
                tooltip: 'Autosave now · $_autosaveStatus',
                onPressed: _projectBusy || _rendering
                    ? null
                    : () => _autosaveIfNeeded(),
                icon: const Icon(Icons.cloud_done_outlined),
              ),
              IconButton(
                tooltip: 'Project version history',
                onPressed: _projectBusy || _rendering
                    ? null
                    : _showProjectVersionHistory,
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'Relink missing media',
                onPressed: _projectBusy || _rendering
                    ? null
                    : _relinkMissingMedia,
                icon: const Icon(Icons.link),
              ),
              IconButton(
                tooltip: 'Open global Font Manager',
                onPressed: _openFontManager,
                icon: const Icon(Icons.font_download_outlined),
              ),
              IconButton(
                tooltip: 'Import Photoshop PSD / PSB layers',
                onPressed: _importPhotoshop,
                icon: const Icon(Icons.photo_library_outlined),
              ),
              IconButton(
                tooltip: 'Add null parent',
                onPressed: () => _addLayer(LayerKind.nullObject),
                icon: const Icon(Icons.control_camera),
              ),
              IconButton(
                tooltip: 'Add camera',
                onPressed: () => _addLayer(LayerKind.camera),
                icon: const Icon(Icons.videocam_outlined),
              ),
              IconButton(
                tooltip: 'Add light',
                onPressed: _rendering ? null : () => _addLayer(LayerKind.light),
                icon: const Icon(Icons.lightbulb_outline),
              ),
              IconButton(
                tooltip: _rendering
                    ? 'Cancel composition render'
                    : 'Render composition to MP4',
                onPressed: _rendering
                    ? _cancelCompositionRender
                    : _exportComposition,
                icon: Icon(
                  _rendering ? Icons.stop_circle_outlined : Icons.ios_share,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Column(
            children: [
              _buildWorkspaceMenuBar(),
              _buildLayerToolbar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 1050;
                    if (compact) {
                      return Column(
                        children: [
                          Expanded(child: _buildPlayheadAwareCanvas()),
                          SizedBox(height: 285, child: _buildActivePanel(layer)),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: _leftPanelWidth,
                          child: _buildLayerPanel(doc.layers),
                        ),
                        _buildWorkspaceSplitter(left: true),
                        Expanded(
                          child: _buildPlayheadAwareCanvas(),
                        ),
                        _buildWorkspaceSplitter(left: false),
                        SizedBox(
                          width: _rightPanelWidth,
                          child: _buildActivePanel(layer),
                        ),
                      ],
                    );
                  },
                ),
              ),
              _buildPlayheadAwareTimeline(),
              if (_rendering || _projectBusy)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _rendering && _renderProgress != 0
                              ? _renderProgress
                              : null,
                        ),
                      ),
                      if (_rendering) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${(_renderProgress * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 10,
                            fontFeatures: [ui.FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: _renderCancellation?.isCancelled == true
                              ? null
                              : _cancelCompositionRender,
                          child: Text(
                            _renderCancellation?.isCancelled == true
                                ? 'STOPPING…'
                                : 'CANCEL',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (_notice != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  color: palette.toolbar,
                  child: Text(_notice!, style: TextStyle(fontSize: 11, color: palette.secondaryText)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _workspaceMenuButton(
    String label,
    List<PopupMenuEntry<String>> items,
    ValueChanged<String> onSelected,
  ) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (_) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 0.85,
            fontWeight: FontWeight.w800,
            color: palette.primaryText,
          ),
        ),
      ),
    );
  }

  void _applyWorkspacePreset(String preset) {
    setState(() {
      _workspacePreset = preset;
      switch (preset) {
        case 'After Effects':
          _leftPanel = 'Project';
          _panel = 'Transform';
          _graphEditorVisible = false;
          _leftPanelWidth = 270;
          _rightPanelWidth = 340;
          _rightPanelOrder
            ..clear()
            ..addAll([
              'Transform',
              'Effects',
              'Animation',
              'Layers',
              'Timing',
              'Typography',
              'Shape',
              'Color',
              'Masks',
              'Tracking',
              'Parent',
              '3D',
              'Audio',
              'Bus Mixer',
              'Transitions',
              'Library',
            ]);
        case 'Standard':
          _leftPanel = 'Project';
          _panel = 'Layers';
          _graphEditorVisible = false;
        case 'Animation':
          _leftPanel = 'Project';
          _panel = 'Animation';
          _graphEditorVisible = true;
        case 'Editing':
          _leftPanel = 'Project';
          _panel = 'Timing';
          _graphEditorVisible = false;
        case 'Effects':
          _leftPanel = 'Effects & Presets';
          _panel = 'Effects';
          _graphEditorVisible = false;
        case 'Color':
          _leftPanel = 'Project';
          _panel = 'Color';
          _graphEditorVisible = false;
        case 'Audio':
          _leftPanel = 'Project';
          _panel = 'Audio';
          _graphEditorVisible = false;
        case '3D':
          _leftPanel = 'Project';
          _panel = '3D';
          _graphEditorVisible = false;
      }
    });
  }

  Widget _buildWorkspaceMenuBar() {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: palette.toolbar,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          _workspaceMenuButton(
            'File',
            const [
              PopupMenuItem(value: 'open', child: Text('Open Project…')),
              PopupMenuItem(value: 'save', child: Text('Save Project')),
              PopupMenuItem(value: 'versions', child: Text('Version History')),
              PopupMenuItem(value: 'relink', child: Text('Relink Missing Media')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'export', child: Text('Render / Export MP4')),
            ],
            (action) {
              switch (action) {
                case 'open':
                  unawaited(_openCompositionProject());
                case 'save':
                  unawaited(_saveCompositionProject());
                case 'versions':
                  unawaited(_showProjectVersionHistory());
                case 'relink':
                  unawaited(_relinkMissingMedia());
                case 'export':
                  unawaited(_exportComposition());
              }
            },
          ),
          _workspaceMenuButton(
            'Edit',
            const [
              PopupMenuItem(value: 'undo', child: Text('Undo')),
              PopupMenuItem(value: 'redo', child: Text('Redo')),
            ],
            (action) {
              if (action == 'undo' && _controller.canUndo) {
                _controller.undo();
              } else if (action == 'redo' && _controller.canRedo) {
                _controller.redo();
              }
            },
          ),
          _workspaceMenuButton(
            'Composition',
            const [
              PopupMenuItem(value: 'info', child: Text('Composition Information')),
              PopupMenuItem(value: 'transform', child: Text('Open Layer Properties')),
              PopupMenuItem(value: 'graph', child: Text('Open Graph Editor')),
            ],
            (action) {
              setState(() {
                switch (action) {
                  case 'info':
                    _leftPanel = 'Info';
                  case 'transform':
                    _panel = 'Transform';
                  case 'graph':
                    _panel = 'Animation';
                    _graphEditorVisible = true;
                }
              });
            },
          ),
          _workspaceMenuButton(
            'Layer',
            const [
              PopupMenuItem(value: 'video', child: Text('Import Video Layer…')),
              PopupMenuItem(value: 'audio', child: Text('Import Audio Layer…')),
              PopupMenuItem(value: 'image', child: Text('Import Image Layer…')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'text', child: Text('New Text Layer')),
              PopupMenuItem(value: 'shape', child: Text('New Shape Layer')),
              PopupMenuItem(value: 'adjustment', child: Text('New Adjustment Layer')),
              PopupMenuItem(value: 'null', child: Text('New Null Object')),
              PopupMenuItem(value: 'camera', child: Text('New Camera')),
              PopupMenuItem(value: 'light', child: Text('New Light')),
              PopupMenuItem(value: '3d', child: Text('Import 3D Model…')),
            ],
            (action) {
              final kind = switch (action) {
                'video' => LayerKind.video,
                'audio' => LayerKind.audio,
                'image' => LayerKind.image,
                'text' => LayerKind.text,
                'shape' => LayerKind.shape,
                'adjustment' => LayerKind.adjustment,
                'null' => LayerKind.nullObject,
                'camera' => LayerKind.camera,
                'light' => LayerKind.light,
                '3d' => LayerKind.threeDModel,
                _ => null,
              };
              if (kind != null) unawaited(_addLayer(kind));
            },
          ),
          _workspaceMenuButton(
            'Effect',
            const [
              PopupMenuItem(value: 'open', child: Text('Open Effect Library')),
            ],
            (_) => setState(() => _panel = 'Effects'),
          ),
          _workspaceMenuButton(
            'Animation',
            const [
              PopupMenuItem(value: 'open', child: Text('Keyframe / Graph Editor')),
              PopupMenuItem(value: 'add', child: Text('Add Position Keyframe')),
            ],
            (action) {
              if (action == 'add') _addKeyframe('position.x');
              setState(() => _panel = 'Animation');
            },
          ),
          _workspaceMenuButton(
            'View',
            const [
              PopupMenuItem(value: 'grid', child: Text('Toggle Transparency Grid')),
              PopupMenuItem(value: 'graph', child: Text('Toggle Graph Editor')),
              PopupMenuItem(value: 'reset', child: Text('Restore After Effects Workspace')),
            ],
            (action) {
              switch (action) {
                case 'grid':
                  setState(() => _showCanvasGrid = !_showCanvasGrid);
                case 'graph':
                  setState(() {
                    _graphEditorVisible = !_graphEditorVisible;
                    _panel = 'Animation';
                  });
                case 'reset':
                  _applyWorkspacePreset('After Effects');
              }
            },
          ),
          _workspaceMenuButton(
            'Window',
            const [
              PopupMenuItem(value: 'Layers', child: Text('Project / Layers')),
              PopupMenuItem(value: 'Transform', child: Text('Transform')),
              PopupMenuItem(value: 'Effects', child: Text('Effect Controls')),
              PopupMenuItem(value: 'Animation', child: Text('Graph / Keyframe Editor')),
              PopupMenuItem(value: 'Timing', child: Text('Timing')),
              PopupMenuItem(value: 'Typography', child: Text('Character / Typography')),
              PopupMenuItem(value: 'Shape', child: Text('Shape')),
              PopupMenuItem(value: 'Color', child: Text('Color')),
              PopupMenuItem(value: 'Audio', child: Text('Audio')),
              PopupMenuItem(value: 'Bus Mixer', child: Text('Audio Mixer')),
              PopupMenuItem(value: 'Masks', child: Text('Masks')),
              PopupMenuItem(value: 'Transitions', child: Text('Transitions')),
              PopupMenuItem(value: 'Library', child: Text('Asset Library')),
              PopupMenuItem(value: 'Tracking', child: Text('Tracker')),
              PopupMenuItem(value: 'Parent', child: Text('Parent & Link')),
              PopupMenuItem(value: '3D', child: Text('3D Controls')),
            ],
            (panel) => setState(() => _panel = panel),
          ),
          _workspaceMenuButton(
            'Workspace',
            const [
              PopupMenuItem(value: 'After Effects', child: Text('After Effects · Default')),
              PopupMenuItem(value: 'Standard', child: Text('Standard')),
              PopupMenuItem(value: 'Editing', child: Text('Editing')),
              PopupMenuItem(value: 'Animation', child: Text('Animation')),
              PopupMenuItem(value: 'Effects', child: Text('Effects')),
              PopupMenuItem(value: 'Color', child: Text('Color')),
              PopupMenuItem(value: 'Audio', child: Text('Audio')),
              PopupMenuItem(value: '3D', child: Text('3D')),
            ],
            _applyWorkspacePreset,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              '${_workspacePreset.toUpperCase()} WORKSPACE  •  ${_controller.document.layers.length} LAYERS',
              style: TextStyle(
                fontSize: 8,
                letterSpacing: 0.8,
                color: palette.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerToolbar() {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: palette.toolbar,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              children: [
                for (final entry in _layerButtons)
                  Tooltip(
                    message: 'Create ${entry.$2} layer',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      onPressed: _rendering ? null : () => _addLayer(entry.$1),
                      icon: Icon(entry.$3, size: 16),
                    ),
                  ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: palette.border),
          Tooltip(
            message: 'Import Photoshop PSD / PSB layers',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _importPhotoshop,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),
    );
  }

  Widget _buildCompositionViewerBar(
    CompositionDocument document,
    bool hasCamera,
  ) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.toolbar,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.movie_creation_outlined, size: 14),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Composition: ${document.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: palette.primaryText,
              ),
            ),
          ),
          Text(
            hasCamera ? 'ACTIVE CAMERA' : 'ACTIVE VIEW',
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 0.55,
              color: palette.secondaryText,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${document.width} × ${document.height}',
            style: TextStyle(fontSize: 8, color: palette.secondaryText),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: _autoKeyEnabled
                ? 'Auto-Key enabled · preview transforms create keyframes'
                : 'Auto-Key disabled · existing animated properties still update keys',
            onPressed: () => setState(() => _autoKeyEnabled = !_autoKeyEnabled),
            icon: Icon(
              Icons.diamond_outlined,
              size: 15,
              color: _autoKeyEnabled ? palette.accent : palette.secondaryText,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'AUTO KEY',
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w800,
              color: _autoKeyEnabled ? palette.accent : palette.secondaryText,
            ),
          ),
          PopupMenuButton<double>(
            tooltip: 'Composition magnification',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 26),
            initialValue: _previewZoom,
            onSelected: (value) => setState(() {
              _previewZoom = value;
              _previewPanOffset = Offset.zero;
            }),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 0.5, child: Text('50%')),
              PopupMenuItem(value: 0.75, child: Text('75%')),
              PopupMenuItem(value: 1, child: Text('Fit / 100%')),
              PopupMenuItem(value: 1.5, child: Text('150%')),
              PopupMenuItem(value: 2, child: Text('200%')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                _previewZoom == 1 ? 'FIT' : '${(_previewZoom * 100).round()}%',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: palette.accent,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Composition view options',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 26),
            icon: Icon(Icons.tune, size: 14, color: palette.secondaryText),
            onSelected: (value) {
              setState(() {
                if (value == 'controls') {
                  _showLayerControls = !_showLayerControls;
                } else if (value == 'motion') {
                  _showMotionPaths = !_showMotionPaths;
                } else if (value == 'reset') {
                  _previewZoom = 1;
                  _previewPanOffset = Offset.zero;
                }
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'controls',
                child: Text(
                  '${_showLayerControls ? '✓' : '　'} Show Layer Controls',
                ),
              ),
              PopupMenuItem(
                value: 'motion',
                child: Text(
                  '${_showMotionPaths ? '✓' : '　'} Show Motion Paths',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'reset', child: Text('Reset View')),
            ],
          ),
          const SizedBox(width: 5),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: _showCanvasGrid ? 'Hide transparency grid' : 'Show transparency grid',
            onPressed: () => setState(() => _showCanvasGrid = !_showCanvasGrid),
            icon: Icon(
              _showCanvasGrid ? Icons.grid_on : Icons.grid_off,
              size: 14,
              color: _showCanvasGrid ? palette.accent : palette.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceSplitter({required bool left}) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) {
          setState(() {
            if (left) {
              _leftPanelWidth = (_leftPanelWidth + details.delta.dx)
                  .clamp(205.0, 420.0)
                  .toDouble();
            } else {
              _rightPanelWidth = (_rightPanelWidth - details.delta.dx)
                  .clamp(300.0, 560.0)
                  .toDouble();
            }
          });
        },
        onDoubleTap: () {
          setState(() {
            _leftPanelWidth = 270;
            _rightPanelWidth = 340;
          });
        },
        child: SizedBox(
          width: 6,
          child: Center(
            child: Container(
              width: 1,
              color: palette.border,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayerPanel(List<CompositionLayer> layers) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final document = _controller.document;
    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: palette.toolbar,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                Icon(
                  _leftPanel == 'Project' ? Icons.folder_open : Icons.auto_awesome,
                  size: 15,
                  color: palette.accent,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _leftPanel == 'Project' ? 'PROJECT' : 'EFFECTS & PRESETS',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w900,
                      color: palette.primaryText,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Import video layer',
                  onPressed: () => _addLayer(LayerKind.video),
                  icon: const Icon(Icons.add, size: 17),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Choose left panel',
                  onSelected: (value) => setState(() => _leftPanel = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'Project', child: Text('Project')),
                    PopupMenuItem(value: 'Effects & Presets', child: Text('Effects & Presets')),
                    PopupMenuItem(value: 'Info', child: Text('Composition Info')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.more_vert, size: 17),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 34,
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                for (final tab in const ['Project', 'Effects & Presets', 'Info'])
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _leftPanel = tab),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _leftPanel == tab
                                  ? palette.accent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          tab == 'Effects & Presets' ? 'EFFECTS' : tab.toUpperCase(),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: _leftPanel == tab
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: _leftPanel == tab
                                ? palette.primaryText
                                : palette.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (_leftPanel) {
              'Effects & Presets' => _buildLeftEffectsPanel(),
              'Info' => _buildCompositionInfoPanel(document),
              _ => _buildProjectPanel(layers, document),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProjectPanel(
    List<CompositionLayer> layers,
    CompositionDocument document,
  ) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                document.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: palette.primaryText,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${document.width} × ${document.height}  ·  ${document.frameRate.toStringAsFixed(0)} fps  ·  ${_time(document.durationMs)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 8, color: palette.secondaryText),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
          child: Row(
            children: [
              Icon(Icons.layers_outlined, size: 13, color: palette.secondaryText),
              const SizedBox(width: 6),
              Text(
                'COMPOSITION LAYERS  (${layers.length})',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w900,
                  color: palette.secondaryText,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: layers.length,
            itemBuilder: (context, index) {
              final layer = layers[index];
              final selected = layer.id == document.selectedLayerId;
              var depth = 0;
              var ancestorId = layer.parentId;
              while (ancestorId != null && depth <= layers.length) {
                final parents = layers.where((item) => item.id == ancestorId);
                if (parents.isEmpty) break;
                ancestorId = parents.first.parentId;
                depth++;
              }
              final metadata = <String>[
                layer.kind == LayerKind.precomposition
                    ? 'PSD group'
                    : layer.kind.name,
                if (layer.photoshopClipped)
                  layer.clippingBaseLayerId == null
                      ? 'clipped layer'
                      : 'clipped to base',
                if (layer.smartObjectResourceId != null) 'Smart Object',
                if (layer.photoshopAdjustmentKey != null)
                  'Adjustment ${layer.photoshopAdjustmentKey}',
              ];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.only(
                  left: 8 + depth * 12,
                  right: 4,
                ),
                selected: selected,
                selectedTileColor: palette.accentSoft,
                leading: Icon(
                  layer.kind == LayerKind.precomposition
                      ? Icons.folder_open
                      : _iconFor(layer.kind),
                  size: 16,
                  color: selected ? palette.accent : palette.secondaryText,
                ),
                title: Text(
                  layer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
                subtitle: Text(
                  metadata.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8),
                ),
                trailing: SizedBox(
                  width: 54,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: layer.enabled ? 'Hide layer' : 'Show layer',
                        onPressed: () => _controller.setLayerEnabled(
                          layer.id,
                          !layer.enabled,
                        ),
                        icon: Icon(
                          layer.enabled ? Icons.visibility : Icons.visibility_off,
                          size: 14,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: layer.locked ? 'Unlock layer' : 'Lock layer',
                        onPressed: () => _controller.setLayerLocked(
                          layer.id,
                          !layer.locked,
                        ),
                        icon: Icon(
                          layer.locked ? Icons.lock : Icons.lock_open,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                onTap: () => _controller.selectLayer(layer.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLeftEffectsPanel() {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final query = _leftEffectSearch.trim().toLowerCase();
    final effects = EffectCatalog.all.where((effect) {
      return query.isEmpty ||
          (effect.name + ' ' + effect.category + ' ' + effect.description)
              .toLowerCase()
              .contains(query);
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            onChanged: (value) => setState(() => _leftEffectSearch = value),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 16),
              hintText: 'Search effects and presets…',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            children: [
              Text(
                '${effects.length} EFFECTS',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  color: palette.secondaryText,
                ),
              ),
              const Spacer(),
              Text(
                _selected == null ? 'SELECT A LAYER' : 'READY TO APPLY',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  color: _selected == null
                      ? palette.secondaryText
                      : palette.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            itemCount: effects.length,
            itemBuilder: (context, index) {
              final effect = effects[index];
              return EffectPreviewTile(
                effect: effect,
                onApply: _selected == null
                    ? () => setState(() {
                          _notice = 'Select a layer before adding ${effect.name}.';
                        })
                    : () {
                        _controller.addEffect(effect.id);
                        setState(() => _panel = 'Effects');
                      },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompositionInfoPanel(CompositionDocument document) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final selected = _selected;
    final video = document.layers.where((layer) => layer.kind == LayerKind.video).length;
    final audio = document.layers.where((layer) => layer.kind == LayerKind.audio).length;
    final image = document.layers.where((layer) =>
        layer.kind == LayerKind.image || layer.kind == LayerKind.photoshopLayer).length;
    Widget info(String label, String value, IconData icon) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
          child: Row(
            children: [
              Icon(icon, size: 15, color: palette.secondaryText),
              const SizedBox(width: 9),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 9, color: palette.secondaryText)),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: palette.primaryText,
                ),
              ),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _panelHeader('COMPOSITION INFO', Icons.info_outline),
        info('Frame size', '${document.width} × ${document.height}', Icons.aspect_ratio),
        info('Frame rate', '${document.frameRate.toStringAsFixed(3)} fps', Icons.speed),
        info('Duration', _time(document.durationMs), Icons.timer_outlined),
        info('Layers', document.layers.length.toString(), Icons.layers_outlined),
        info('Video tracks', video.toString(), Icons.movie_outlined),
        info('Audio tracks', audio.toString(), Icons.graphic_eq),
        info('Images / PSD', image.toString(), Icons.image_outlined),
        info('Transitions', document.transitions.length.toString(), Icons.compare_arrows),
        info('Audio buses', document.audioBuses.length.toString(), Icons.tune),
        const Divider(height: 22),
        _panelHeader('SELECTION INFO', Icons.ads_click),
        info('Selected', selected?.name ?? 'None', Icons.layers),
        info('Keyframe tracks', selected?.keyframeTracks.length.toString() ?? '—', Icons.key),
        info('Effects', selected?.effects.length.toString() ?? '—', Icons.auto_awesome),
        info('Masks', selected?.masks.length.toString() ?? '—', Icons.crop_free),
      ],
    );
  }

  void _addPreviewTransformKeyframes() {
    final layer = _controller.selectedLayer;
    if (layer == null || layer.locked) return;
    final timeMs = _controller.document.playheadMs;
    _controller.updateTransformValues(
      {
        'position.x': layer.valueAt('position.x', timeMs),
        'position.y': layer.valueAt('position.y', timeMs),
        'scale.x': layer.valueAt('scale.x', timeMs),
        'scale.y': layer.valueAt('scale.y', timeMs),
        'rotation.z': layer.valueAt('rotation.z', timeMs),
        'opacity': layer.valueAt('opacity', timeMs),
      },
      autoKey: true,
    );
    if (mounted) {
      setState(() => _notice = 'Transform keyframes added at the current time.');
    }
  }

  void _beginPreviewMove(CompositionLayer layer, Offset globalPosition) {
    if (layer.locked) return;
    _pausePreviewPlayback();
    _controller.selectLayer(layer.id);
    _previewMoveLayerId = layer.id;
    _previewMoveLastGlobal = globalPosition;
    _previewMoveHistoryRecorded = false;
  }

  void _updatePreviewMove(
    CompositionLayer layer,
    Offset globalPosition,
    Size canvasSize,
    CompositionDocument document,
  ) {
    if (_previewMoveLayerId != layer.id) return;
    final delta = globalPosition - _previewMoveLastGlobal;
    _previewMoveLastGlobal = globalPosition;
    final current = _controller.selectedLayer;
    if (current == null || current.id != layer.id) return;
    final timeMs = _controller.document.playheadMs;
    _controller.updateTransformValues({
      'position.x': current.valueAt('position.x', timeMs) +
          delta.dx / _previewZoom / canvasSize.width * document.width,
      'position.y': current.valueAt('position.y', timeMs) +
          delta.dy / _previewZoom / canvasSize.height * document.height,
    },
      autoKey: _autoKeyEnabled,
      recordHistory: !_previewMoveHistoryRecorded,
    );
    _previewMoveHistoryRecorded = true;
  }

  void _endPreviewMove() {
    _previewMoveLayerId = null;
    _previewMoveHistoryRecorded = false;
  }

  void _beginPreviewResize(CompositionLayer layer, Offset globalPosition) {
    if (layer.locked) return;
    _pausePreviewPlayback();
    _controller.selectLayer(layer.id);
    final timeMs = _controller.document.playheadMs;
    _previewResizeLayerId = layer.id;
    _previewResizeStartScaleX = layer.valueAt('scale.x', timeMs);
    _previewResizeStartScaleY = layer.valueAt('scale.y', timeMs);
    _previewResizeStartGlobal = globalPosition;
    _previewResizeHistoryRecorded = false;
  }

  void _updatePreviewResize(
    CompositionLayer layer,
    Offset globalPosition, {
    required double width,
    required double height,
    required double rotationRadians,
    required int horizontalSign,
    required int verticalSign,
  }) {
    if (_previewResizeLayerId != layer.id) return;
    final screenDelta = globalPosition - _previewResizeStartGlobal;
    final cosine = math.cos(rotationRadians);
    final sine = math.sin(rotationRadians);
    final localDelta = Offset(
      (screenDelta.dx * cosine + screenDelta.dy * sine) / _previewZoom,
      (-screenDelta.dx * sine + screenDelta.dy * cosine) / _previewZoom,
    );
    final scaleX = _previewResizeStartScaleX *
        (1 + horizontalSign * localDelta.dx / math.max(1, width));
    final scaleY = _previewResizeStartScaleY *
        (1 + verticalSign * localDelta.dy / math.max(1, height));
    final boundedX = scaleX.abs().clamp(2.0, 2000.0).toDouble() *
        (scaleX.isNegative ? -1.0 : 1.0);
    final boundedY = scaleY.abs().clamp(2.0, 2000.0).toDouble() *
        (scaleY.isNegative ? -1.0 : 1.0);
    _controller.updateTransformValues(
      {'scale.x': boundedX, 'scale.y': boundedY},
      autoKey: _autoKeyEnabled,
      recordHistory: !_previewResizeHistoryRecorded,
    );
    _previewResizeHistoryRecorded = true;
  }

  void _endPreviewResize() {
    _previewResizeLayerId = null;
    _previewResizeHistoryRecorded = false;
  }

  void _beginPreviewRotate(
    CompositionLayer layer,
    RenderBox overlayBox,
    Offset globalPosition,
  ) {
    if (layer.locked) return;
    _pausePreviewPlayback();
    _controller.selectLayer(layer.id);
    final center = overlayBox.localToGlobal(
      Offset(overlayBox.size.width / 2, overlayBox.size.height / 2),
    );
    final timeMs = _controller.document.playheadMs;
    _previewRotateLayerId = layer.id;
    _previewRotateCenterGlobal = center;
    _previewRotateStartDegrees = layer.valueAt('rotation.z', timeMs);
    _previewRotateStartPointerRadians = math.atan2(
      globalPosition.dy - center.dy,
      globalPosition.dx - center.dx,
    );
    _previewRotateHistoryRecorded = false;
  }

  void _updatePreviewRotate(CompositionLayer layer, Offset globalPosition) {
    if (_previewRotateLayerId != layer.id) return;
    final currentRadians = math.atan2(
      globalPosition.dy - _previewRotateCenterGlobal.dy,
      globalPosition.dx - _previewRotateCenterGlobal.dx,
    );
    var deltaRadians = currentRadians - _previewRotateStartPointerRadians;
    while (deltaRadians > math.pi) {
      deltaRadians -= math.pi * 2;
    }
    while (deltaRadians < -math.pi) {
      deltaRadians += math.pi * 2;
    }
    _controller.updateTransformValues({
      'rotation.z':
          _previewRotateStartDegrees + deltaRadians * 180 / math.pi,
    },
      autoKey: _autoKeyEnabled,
      recordHistory: !_previewRotateHistoryRecorded,
    );
    _previewRotateHistoryRecorded = true;
  }

  void _endPreviewRotate() {
    _previewRotateLayerId = null;
    _previewRotateHistoryRecorded = false;
  }

  Widget _previewScaleHandle(
    CompositionLayer layer, {
    required double left,
    required double top,
    required int horizontalSign,
    required int verticalSign,
    required double width,
    required double height,
    required double rotationRadians,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) =>
            _beginPreviewResize(layer, details.globalPosition),
        onPanUpdate: (details) => _updatePreviewResize(
          layer,
          details.globalPosition,
          width: width,
          height: height,
          rotationRadians: rotationRadians,
          horizontalSign: horizontalSign,
          verticalSign: verticalSign,
        ),
        onPanEnd: (_) => _endPreviewResize(),
        onPanCancel: _endPreviewResize,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6FF),
            border: Border.all(color: const Color(0xFF536DFF), width: 2),
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewSelectionOverlay(
    CompositionLayer layer, {
    required double width,
    required double height,
    required double rotationRadians,
  }) {
    return Builder(
      builder: (overlayContext) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: const _PreviewSelectionOutlinePainter(),
            ),
          ),
          if (!layer.locked && _activePreviewTool == 'Select') ...[
            _previewScaleHandle(
              layer,
              left: -6,
              top: -6,
              horizontalSign: -1,
              verticalSign: -1,
              width: width,
              height: height,
              rotationRadians: rotationRadians,
            ),
            _previewScaleHandle(
              layer,
              left: width - 6,
              top: -6,
              horizontalSign: 1,
              verticalSign: -1,
              width: width,
              height: height,
              rotationRadians: rotationRadians,
            ),
            _previewScaleHandle(
              layer,
              left: -6,
              top: height - 6,
              horizontalSign: -1,
              verticalSign: 1,
              width: width,
              height: height,
              rotationRadians: rotationRadians,
            ),
            _previewScaleHandle(
              layer,
              left: width - 6,
              top: height - 6,
              horizontalSign: 1,
              verticalSign: 1,
              width: width,
              height: height,
              rotationRadians: rotationRadians,
            ),
            Positioned(
              left: width / 2 - 6,
              top: -31,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) {
                  final renderObject = overlayContext.findRenderObject();
                  if (renderObject is RenderBox) {
                    _beginPreviewRotate(
                      layer,
                      renderObject,
                      details.globalPosition,
                    );
                  }
                },
                onPanUpdate: (details) =>
                    _updatePreviewRotate(layer, details.globalPosition),
                onPanEnd: (_) => _endPreviewRotate(),
                onPanCancel: _endPreviewRotate,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4FD5C4),
                    border: Border.all(color: Colors.white, width: 1.5),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Color(0x99000000), blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _beginPreviewMotionKeyframe(
    CompositionLayer layer,
    int timeMs,
    Offset globalPosition,
  ) {
    if (layer.locked) return;
    _pausePreviewPlayback();
    _controller.selectLayer(layer.id);
    _previewMotionLayerId = layer.id;
    _previewMotionKeyTimeMs = timeMs;
    _previewMotionLastGlobal = globalPosition;
    _previewMotionHistoryRecorded = false;
    _controller.setPlayhead(timeMs);
  }

  void _updatePreviewMotionKeyframe(
    CompositionLayer layer,
    Offset globalPosition,
    Size canvasSize,
    CompositionDocument document,
  ) {
    if (_previewMotionLayerId != layer.id ||
        _previewMotionKeyTimeMs == null) {
      return;
    }
    final delta = globalPosition - _previewMotionLastGlobal;
    _previewMotionLastGlobal = globalPosition;
    final timeMs = _previewMotionKeyTimeMs!;
    final current = _controller.selectedLayer;
    if (current == null || current.id != layer.id) return;
    _controller.updateTransformValues(
      {
        'position.x': current.valueAt('position.x', timeMs) +
            delta.dx / _previewZoom / math.max(1, canvasSize.width) * document.width,
        'position.y': current.valueAt('position.y', timeMs) +
            delta.dy / _previewZoom / math.max(1, canvasSize.height) * document.height,
      },
      autoKey: true,
      timeMs: timeMs,
      recordHistory: !_previewMotionHistoryRecorded,
    );
    _previewMotionHistoryRecorded = true;
  }

  void _endPreviewMotionKeyframe() {
    _previewMotionLayerId = null;
    _previewMotionKeyTimeMs = null;
    _previewMotionHistoryRecorded = false;
  }

  Widget _buildMotionPathOverlay(
    CompositionLayer? layer,
    CompositionDocument document,
    Size canvasSize,
  ) {
    if (layer == null) return const SizedBox.shrink();
    final xTrack = layer.keyframeTracks.where(
      (track) => track.property == 'position.x',
    );
    final yTrack = layer.keyframeTracks.where(
      (track) => track.property == 'position.y',
    );
    final times = <int>{
      if (xTrack.isNotEmpty)
        for (final key in xTrack.first.keyframes) key.timeMs,
      if (yTrack.isNotEmpty)
        for (final key in yTrack.first.keyframes) key.timeMs,
    }.toList()
      ..sort();
    if (times.length < 2) return const SizedBox.shrink();

    Offset pointAt(int timeMs) => Offset(
          layer.valueAt('position.x', timeMs) /
              math.max(1, document.width) * canvasSize.width,
          layer.valueAt('position.y', timeMs) /
              math.max(1, document.height) * canvasSize.height,
        );

    return SizedBox(
      width: canvasSize.width,
      height: canvasSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _PreviewMotionPathPainter(
                  layer: layer,
                  document: document,
                  color: Theme.of(context).extension<DepthVibePalette>()!.accent,
                ),
              ),
            ),
          ),
          for (final timeMs in times)
            Positioned(
              left: pointAt(timeMs).dx - 8,
              top: pointAt(timeMs).dy - 8,
              width: 16,
              height: 16,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _controller.setPlayhead(timeMs),
                onPanStart: (details) => _beginPreviewMotionKeyframe(
                  layer,
                  timeMs,
                  details.globalPosition,
                ),
                onPanUpdate: (details) => _updatePreviewMotionKeyframe(
                  layer,
                  details.globalPosition,
                  canvasSize,
                  document,
                ),
                onPanEnd: (_) => _endPreviewMotionKeyframe(),
                onPanCancel: _endPreviewMotionKeyframe,
                child: Center(
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: timeMs == document.playheadMs
                            ? const Color(0xFFFFA65C)
                            : const Color(0xFFF5D27E),
                        border: Border.all(
                          color: Colors.white,
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayheadAwareCanvas() {
    return AnimatedBuilder(
      animation: _controller.playhead,
      builder: (context, _) =>
          _buildCanvas(_controller.document, _controller.selectedLayer),
    );
  }

  Widget _buildCanvas(CompositionDocument doc, CompositionLayer? selected) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final resolvedTransforms = const ParentTransformResolver().resolveAll(
      timeMs: doc.playheadMs,
      layers: doc.layers,
    );
    final cameraLayer = doc.layers
        .where((item) => item.kind == LayerKind.camera && item.enabled)
        .firstOrNull;
    final cameraTransform = cameraLayer == null
        ? null
        : resolvedTransforms[cameraLayer.id];
    return Container(
      color: palette.appBackground,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _buildCompositionViewerBar(
            doc,
            cameraLayer != null,
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: doc.width / doc.height,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasWidth = constraints.maxWidth;
                    final canvasHeight = constraints.maxHeight;
                    final ordered = doc.layers.reversed.where((item) => item.enabled);
                    return Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFF151C2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF36445F)),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: _activePreviewTool == 'Hand'
                            ? (details) => setState(() {
                                  _previewPanOffset += details.delta;
                                })
                            : null,
                        child: Transform.translate(
                          offset: _previewPanOffset,
                          child: Transform.scale(
                            scale: _previewZoom,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_showCanvasGrid)
                            const CustomPaint(painter: _CanvasGridPainter()),
                          for (final layer in ordered)
                            _buildLayerVisual(
                              layer,
                              doc,
                              Size(canvasWidth, canvasHeight),
                              resolvedTransforms: resolvedTransforms,
                              cameraLayer: cameraLayer,
                              cameraTransform: cameraTransform,
                            ),
                          if (_showMotionPaths)
                            _buildMotionPathOverlay(
                              selected,
                              doc,
                              Size(canvasWidth, canvasHeight),
                            ),
                          if (selected != null)
                            Positioned(
                              right: 10,
                              top: 10,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xCC0A101C),
                                  border: Border.all(color: const Color(0xFF8293FF)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Text(
                                    selected.name,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: Text(
                              '${doc.width} × ${doc.height}  •  ${doc.frameRate.toStringAsFixed(0)} FPS',
                              style: const TextStyle(fontSize: 9, color: Color(0xFF8998AF)),
                            ),
                          ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _toolChip(
                'Select',
                Icons.mouse,
                _activePreviewTool == 'Select',
                onTap: () => setState(() => _activePreviewTool = 'Select'),
              ),
              _toolChip(
                'Hand',
                Icons.pan_tool_alt,
                _activePreviewTool == 'Hand',
                onTap: () => setState(() => _activePreviewTool = 'Hand'),
              ),
              _toolChip(
                'Mask',
                Icons.crop_free,
                _activePreviewTool == 'Mask',
                onTap: () {
                  _controller.addMask();
                  setState(() {
                    _panel = 'Masks';
                    _activePreviewTool = 'Select';
                  });
                },
              ),
              _toolChip(
                'Keyframe',
                Icons.key,
                false,
                onTap: _addPreviewTransformKeyframes,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayerVisual(
    CompositionLayer layer,
    CompositionDocument doc,
    Size canvasSize, {
    required Map<String, ResolvedLayerTransform> resolvedTransforms,
    required CompositionLayer? cameraLayer,
    required ResolvedLayerTransform? cameraTransform,
  }) {
    final timeMs = doc.playheadMs;
    if (layer.kind == LayerKind.video &&
        (timeMs < layer.startMs || timeMs >= layer.endMs)) {
      return const SizedBox.shrink();
    }
    final resolved = resolvedTransforms[layer.id];
    if (resolved == null || !resolved.enabled) {
      return const SizedBox.shrink();
    }
    final projected = cameraLayer != null &&
            cameraTransform != null &&
            cameraTransform.enabled &&
            cameraLayer.camera != null &&
            layer.kind != LayerKind.camera &&
            layer.kind != LayerKind.light &&
            layer.kind != LayerKind.precomposition
        ? const CameraProjectionResolver().project(
            layer: resolved,
            camera: cameraTransform,
            settings: cameraLayer.camera!,
          )
        : null;
    final displayPosition = projected?.position ?? resolved.position;
    final displayScale = projected?.scale ?? resolved.scale;
    final displayRotation = projected?.rotation ?? resolved.rotation;
    final displayOpacity = projected?.opacity ?? resolved.opacity;
    final x = displayPosition.x;
    final y = displayPosition.y;
    final scaleX = displayScale.x / 100;
    final scaleY = displayScale.y / 100;
    final rotation = displayRotation.z * math.pi / 180;
    final opacity = (displayOpacity / 100).clamp(0, 1).toDouble();

    double baseWidth = 160;
    double baseHeight = 120;
    Widget visual;

    switch (layer.kind) {
      case LayerKind.photoshopLayer:
      case LayerKind.image:
        baseWidth = layer.sourceWidth > 0 ? layer.sourceWidth.toDouble() : 320;
        baseHeight = layer.sourceHeight > 0 ? layer.sourceHeight.toDouble() : 180;
        visual = layer.sourceUri == null
            ? const Icon(Icons.perm_media_outlined, color: Color(0xFFB3BEFF))
            : Image.file(
                File(layer.sourceUri!),
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0x553E4D6C),
                  child: Icon(Icons.broken_image_outlined),
                ),
              );
        break;
      case LayerKind.video:
        baseWidth = doc.width.toDouble();
        baseHeight = doc.height.toDouble();
        visual = FutureBuilder<File?>(
          future: _videoFrameFor(layer, timeMs, doc.frameRate),
          initialData: _lastVideoFrames[layer.id],
          builder: (context, snapshot) {
            // Keep displaying the most recent decoded frame while the next
            // one is being fetched; never flash a spinner on every playhead tick.
            final frame = snapshot.data ?? _lastVideoFrames[layer.id];
            if (frame != null) {
              return Image.file(
                frame,
                fit: BoxFit.fill,
                cacheWidth: _previewFrameService.effectivePreviewWidth,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (_, error, ___) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.broken_image_outlined,
                          color: Color(0xFFFFA7A7),
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'CACHED PREVIEW FRAME COULD NOT BE DISPLAYED',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFFB4B4),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          error.toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFB8C3D5),
                            fontSize: 8,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _retryVideoPreview(layer),
                          icon: const Icon(Icons.refresh, size: 13),
                          label: const Text(
                            'RETRY FRAME',
                            style: TextStyle(fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final error = _previewFrameErrors[layer.id];
            if (error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFFFFA7A7),
                        size: 30,
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'VIDEO PREVIEW DECODE FAILED',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFFFB4B4),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        error,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB8C3D5),
                          fontSize: 8,
                        ),
                      ),
                      const SizedBox(height: 5),
                      TextButton.icon(
                        onPressed: () => _retryVideoPreview(layer),
                        icon: const Icon(Icons.refresh, size: 13),
                        label: const Text('RETRY', style: TextStyle(fontSize: 9)),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const Center(
              child: Icon(
                Icons.movie_outlined,
                color: Color(0xFFB3BEFF),
                size: 36,
              ),
            );
          },
        );
        break;
      case LayerKind.shape:
        visual = CustomPaint(
          painter: _ShapeLayerPainter(layer.shapeStyle ?? const ShapeStyle()),
        );
        break;
      case LayerKind.text:
        baseWidth = layer.textBoxWidth;
        final content = layer.textContent ?? layer.name;
        final approximateCharactersPerLine =
            (baseWidth / (layer.textFontSize * 0.52))
                .floor()
                .clamp(1, 5000)
                .toInt();
        final estimatedLines = content.split('\n').fold<int>(
          0,
          (count, line) => count +
              math.max(1, (line.length / approximateCharactersPerLine).ceil()).toInt(),
        );
        baseHeight = math.max(
          180.0,
          estimatedLines * layer.textFontSize * layer.textLineHeight + 24,
        ).toDouble();
        final fontScale = canvasSize.width / doc.width;
        final weightIndex = ((layer.textFontWeight.clamp(100, 900) / 100)
                    .round() - 1)
                .clamp(0, 8)
                .toInt();
        final rawColor = layer.textColor.replaceFirst('#', '');
        final parsedColor = int.tryParse(rawColor, radix: 16);
        final textColor = parsedColor == null
            ? Colors.white
            : Color(rawColor.length == 6 ? 0xFF000000 | parsedColor : parsedColor);
        final textAlign = switch (layer.textAlign) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          'justify' => TextAlign.justify,
          _ => TextAlign.left,
        };
        final textDirection = RegExp(r'[\u0590-\u08FF\uFB1D-\uFEFF]')
                .hasMatch(content)
            ? TextDirection.rtl
            : TextDirection.ltr;
        visual = Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: baseWidth * fontScale,
            child: Text(
              content,
              textAlign: textAlign,
              textDirection: textDirection,
              softWrap: true,
              style: TextStyle(
                color: textColor,
                fontFamily: layer.textFontFamily ?? FontManagerService.instance.activeFamily,
                fontFamilyFallback: [
                  ...layer.textFontFallback,
                  ...FontManagerService.instance.fallbackFamilies,
                ],
                fontSize: layer.textFontSize * fontScale,
                fontWeight: FontWeight.values[weightIndex],
                fontStyle: layer.textItalic ? FontStyle.italic : FontStyle.normal,
                letterSpacing: layer.textLetterSpacing * fontScale,
                height: layer.textLineHeight,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
            ),
          ),
        );
        break;
      case LayerKind.nullObject:
        visual = const Icon(Icons.control_camera, color: Color(0xFFB5A4FF), size: 30);
        break;
      case LayerKind.camera:
        visual = const Icon(Icons.videocam, color: Color(0xFF8EC5FF), size: 34);
        break;
      case LayerKind.light:
        visual = const Icon(Icons.lightbulb, color: Color(0xFFFFD78A), size: 34);
        break;
      case LayerKind.adjustment:
        visual = DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x337C8CFF),
            border: Border.all(color: const Color(0x997C8CFF)),
          ),
          child: const Center(
            child: Text('ADJUSTMENT', style: TextStyle(fontSize: 9, letterSpacing: 1)),
          ),
        );
        break;
      case LayerKind.threeDModel:
        baseWidth = 760;
        baseHeight = 760;
        if (layer.sourceUri == null) {
          visual = const Center(
            child: Icon(Icons.view_in_ar, color: Color(0xFF9DE1D3), size: 54),
          );
        } else {
          final meshCamera = cameraTransform != null && cameraTransform.enabled
              ? cameraTransform
              : const ResolvedLayerTransform(
                  position: Vector3(0, 0, 0),
                  scale: Vector3(100, 100, 100),
                  rotation: Vector3(0, 0, 0),
                  opacity: 100,
                  enabled: true,
                );
          final meshCameraSettings = cameraTransform != null && cameraTransform.enabled
              ? cameraLayer?.camera ?? const CameraSettings()
              : const CameraSettings();
          final meshLights = <SceneLight>[
            for (final item in doc.layers.where(
              (candidate) => candidate.kind == LayerKind.light && candidate.enabled,
            ))
              SceneLight(
                transform: resolvedTransforms[item.id]!,
                settings: item.light ?? const LightSettings(),
              ),
          ];
          visual = FutureBuilder<ObjMesh>(
            future: _meshFor(layer.sourceUri!),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Color(0xFFFF8E8E), size: 38),
                );
              }
              final mesh = snapshot.data;
              if (mesh == null) {
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Gpu3dMeshView(
                mesh: mesh,
                timeMs: math.max(0, timeMs - layer.startMs).toInt(),
                animationIndex: layer.modelAnimationIndex,
                baseWidth: baseWidth,
                baseHeight: baseHeight,
                modelTransform: resolved,
                cameraTransform: meshCamera,
                cameraSettings: meshCameraSettings,
                lights: meshLights,
                compositionWidth: doc.width.toDouble(),
                compositionHeight: doc.height.toDouble(),
              );
            },
          );
        }
        break;
      case LayerKind.audio:
        visual = const Icon(Icons.graphic_eq, color: Color(0xFF9DE1D3), size: 26);
        break;
      case LayerKind.particle:
        visual = const Icon(Icons.auto_awesome, color: Color(0xFFFFC98A), size: 32);
        break;
      case LayerKind.precomposition:
        visual = const SizedBox.shrink();
        break;
    }

    final isMeshLayer = layer.kind == LayerKind.threeDModel;
    final meshCameraScaleX = projected != null && resolved.scale.x.abs() > 0.0001
        ? projected.scale.x.abs() / resolved.scale.x.abs()
        : 1.0;
    final meshCameraScaleY = projected != null && resolved.scale.y.abs() > 0.0001
        ? projected.scale.y.abs() / resolved.scale.y.abs()
        : 1.0;
    final width = baseWidth *
        (isMeshLayer ? meshCameraScaleX : scaleX.abs()) /
        doc.width * canvasSize.width;
    final height = baseHeight *
        (isMeshLayer ? meshCameraScaleY : scaleY.abs()) /
        doc.height * canvasSize.height;
    final left = x / doc.width * canvasSize.width - width / 2;
    final top = y / doc.height * canvasSize.height - height / 2;

    final activeMasks = layer.masks.where((mask) => mask.enabled).toList();
    final maskedVisual = activeMasks.isEmpty
        ? visual
        : ClipPath(
            clipper: _AnimatedMaskClipper(
              masks: activeMasks,
              timeMs: timeMs,
            ),
            child: visual,
          );
    final gradeEffect = layer.effects
        .where((effect) => effect.effectId == 'color_grade')
        .firstOrNull;
    final gradeFilter = ColorGradePreview.filterFor(gradeEffect, timeMs);
    final gradedVisual = gradeFilter == null
        ? maskedVisual
        : ColorFiltered(colorFilter: gradeFilter, child: maskedVisual);

    final isSelected = doc.selectedLayerId == layer.id;
    final visualWidth = width.clamp(1, canvasSize.width * 4).toDouble();
    final visualHeight = height.clamp(1, canvasSize.height * 4).toDouble();
    final rotationRadians = isMeshLayer ? 0.0 : rotation;

    return Positioned(
      left: left,
      top: top,
      width: visualWidth,
      height: visualHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.rotate(
              angle: rotationRadians,
              child: Transform.scale(
                scaleX: isMeshLayer ? 1 : (scaleX.isNegative ? -1 : 1),
                scaleY: isMeshLayer ? 1 : (scaleY.isNegative ? -1 : 1),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _controller.selectLayer(layer.id),
                  onPanStart: layer.locked || _activePreviewTool == 'Hand'
                      ? null
                      : (details) => _beginPreviewMove(
                            layer,
                            details.globalPosition,
                          ),
                  onPanUpdate: layer.locked || _activePreviewTool == 'Hand'
                      ? null
                      : (details) => _updatePreviewMove(
                            layer,
                            details.globalPosition,
                            canvasSize,
                            doc,
                          ),
                  onPanEnd: layer.locked || _activePreviewTool == 'Hand'
                      ? null
                      : (_) => _endPreviewMove(),
                  onPanCancel: layer.locked || _activePreviewTool == 'Hand'
                      ? null
                      : _endPreviewMove,
                  child: RepaintBoundary(
                    child: Opacity(opacity: opacity, child: gradedVisual),
                  ),
                ),
              ),
            ),
          ),
          if (isSelected && _showLayerControls)
            Positioned.fill(
              child: Transform.rotate(
                angle: rotationRadians,
                child: _buildPreviewSelectionOverlay(
                  layer,
                  width: visualWidth,
                  height: visualHeight,
                  rotationRadians: rotationRadians,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _toolChip(String label, IconData icon, bool active, {VoidCallback? onTap}) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label),
      onPressed: onTap ?? () => setState(() => _notice = '$label tool selected'),
      backgroundColor: active ? palette.accentSoft : palette.panelRaised,
      side: BorderSide(color: active ? palette.accent : palette.border),
      labelStyle: TextStyle(color: palette.primaryText, fontWeight: FontWeight.w700),
    );
  }


  void _applyTransitionPreset(TransitionPresetDefinition preset) {
    final before = _controller.document.transitions.length;
    _controller.addTransition(preset.kind);
    final transitions = _controller.document.transitions;
    if (transitions.length <= before) {
      setState(() {
        _notice = 'Add at least two enabled video/image clips before applying a transition.';
      });
      return;
    }
    _controller.updateTransition(
      transitions.last.id,
      durationMs: preset.durationMs,
    );
    if (mounted) {
      setState(() => _notice = 'Applied ${preset.name} transition.');
    }
  }

  Color _libraryColor(String value) {
    final normalized = value.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return const Color(0xFFFFFFFF);
    return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
  }

  void _createLibraryTextLayer({
    required String name,
    required String text,
    required double fontSize,
    required int fontWeight,
    required String textColor,
    required double letterSpacing,
    required double positionX,
    required double positionY,
    required String motionPresetId,
    String textAlign = 'center',
    double lineHeight = 1.05,
  }) {
    final document = _controller.document;
    final id = _controller.addLayer(LayerKind.text, name: name);
    _controller.updateTextLayer(
      textContent: text,
      textFontSize: fontSize,
      textFontWeight: fontWeight,
      textColor: textColor,
      textLetterSpacing: letterSpacing,
      textLineHeight: lineHeight,
      textAlign: textAlign,
      textBoxWidth: document.width * 0.86,
    );
    _controller.setTransformValue(
      'position.x',
      (positionX / 1920 * document.width).clamp(0, document.width).toDouble(),
    );
    _controller.setTransformValue(
      'position.y',
      (positionY / 1080 * document.height).clamp(0, document.height).toDouble(),
    );
    _controller.selectLayer(id);
    if (MotionPresetCatalog.find(motionPresetId) != null) {
      _controller.applyMotionPreset(motionPresetId);
    }
    if (mounted) setState(() => _notice = 'Added editable "$name" text layer.');
  }

  void _applyOverlaySticker(OverlayStickerDefinition asset, CompositionLayer? layer) {
    final effectId = asset.effectId;
    if (effectId != null) {
      if (layer == null || layer.locked ||
          !{LayerKind.video, LayerKind.image, LayerKind.photoshopLayer,
            LayerKind.text, LayerKind.adjustment}.contains(layer.kind)) {
        setState(() => _notice = 'Select an unlocked visual layer to apply this overlay.');
        return;
      }
      _controller.addEffect(effectId);
      if (mounted) setState(() => _notice = 'Applied ${asset.name} overlay effect.');
      return;
    }
    _createLibraryTextLayer(
      name: asset.name,
      text: asset.textContent,
      fontSize: asset.fontSize,
      fontWeight: asset.fontWeight,
      textColor: asset.textColor,
      letterSpacing: asset.letterSpacing,
      positionX: asset.positionX,
      positionY: asset.positionY,
      motionPresetId: asset.motionPresetId,
    );
  }

  void _applyTitlePreset(TitlePresetDefinition preset) {
    _createLibraryTextLayer(
      name: preset.name,
      text: preset.sampleText,
      fontSize: preset.fontSize,
      fontWeight: preset.fontWeight,
      textColor: preset.textColor,
      letterSpacing: preset.letterSpacing,
      positionX: preset.positionX,
      positionY: preset.positionY,
      motionPresetId: preset.motionPresetId,
      textAlign: preset.textAlign,
      lineHeight: preset.lineHeight,
    );
  }

  void _applyAudioPreset(AudioPresetDefinition preset, CompositionLayer? layer) {
    if (layer == null || layer.locked ||
        (layer.kind != LayerKind.audio && layer.kind != LayerKind.video)) {
      setState(() => _notice = 'Select an audio or video layer to apply an audio preset.');
      return;
    }
    _controller.setAudioSettings(preset.applyTo(layer.audioSettings));
    if (mounted) setState(() => _notice = 'Applied ${preset.name} audio settings.');
  }

  void _applyColorPreset(ColorPresetDefinition preset, CompositionLayer? layer) {
    if (layer == null || layer.locked ||
        !{LayerKind.video, LayerKind.image, LayerKind.photoshopLayer,
          LayerKind.text, LayerKind.adjustment}.contains(layer.kind)) {
      setState(() => _notice = 'Select an unlocked visual layer to apply a color preset.');
      return;
    }
    _controller.applyColorGradePreset(
      ColorGradePreset(
        name: preset.name,
        outputProfile: _controller.document.colorOutputProfile,
        primary: ColorGradePresetEffect(
          enabled: true,
          parameters: preset.parameters,
        ),
      ),
    );
    if (mounted) setState(() => _notice = 'Applied ${preset.name} color grade.');
  }

  Future<void> _openAssetSource(OpenAssetSourceDefinition source) async {
    try {
      if (Platform.isWindows) {
        await Process.start(
          'explorer.exe',
          [source.url],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isMacOS) {
        await Process.start(
          'open',
          [source.url],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isLinux) {
        await Process.start(
          'xdg-open',
          [source.url],
          mode: ProcessStartMode.detached,
        );
      } else {
        await Share.share(source.url, subject: source.name);
      }
      if (mounted) setState(() => _notice = 'Opened ${source.name}. Check its item-level licence before import.');
    } catch (error) {
      if (mounted) setState(() => _notice = 'Could not open ${source.name}: $error');
    }
  }

  String _formatAssetBytes(int bytes) {
    const gb = 1000 * 1000 * 1000;
    const mb = 1000 * 1000;
    if (bytes >= gb) return (bytes / gb).toStringAsFixed(2) + ' GB';
    if (bytes >= mb) return (bytes / mb).toStringAsFixed(1) + ' MB';
    if (bytes >= 1000) return (bytes / 1000).toStringAsFixed(0) + ' KB';
    return bytes.toString() + ' B';
  }

  Future<bool> _confirmAssetPackDownload({
    required String title,
    required String detail,
    required String size,
    required String licence,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(detail),
              const SizedBox(height: 10),
              Text('Download size: ' + size,
                style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text('Licence: ' + licence,
                style: const TextStyle(fontSize: 11, color: Color(0xFFB7C4D8))),
              const SizedBox(height: 10),
              const Text(
                'Files will be extracted to DepthVibe local storage and remain available offline. The source archive licence and attribution notices are kept with the pack.',
                style: TextStyle(fontSize: 10, color: Color(0xFF9EADC4)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('DOWNLOAD & INSTALL'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _installCreativeAssetPack(
    CreativeAssetPackDefinition definition,
  ) async {
    if (_creativePackBusy || _creativeAssetPacks.isInstalled(definition.id)) return;
    final confirmed = await _confirmAssetPackDownload(
      title: 'Install ' + definition.name + '?',
      detail: definition.description,
      size: definition.sizeLabel,
      licence: definition.licenseLabel,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _creativePackBusy = true;
      _creativePackReceived = 0;
      _creativePackTotal = definition.exactBytes ?? definition.estimatedBytes;
      _notice = 'Downloading ' + definition.name + '…';
    });
    try {
      final installed = await _creativeAssetPacks.install(
        definition,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _creativePackReceived = received;
            if (total > 0) _creativePackTotal = total;
          });
        },
      );
      if (mounted) {
        setState(() {
          _installedCreativePacks = _creativeAssetPacks.installed;
          _notice = 'Installed ' + installed.name + ': ' +
              installed.fileCount.toString() + ' files · ' +
              _formatAssetBytes(installed.expandedBytes) +
              '. Files are ready offline.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Asset pack install stopped: ' + error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _creativePackBusy = false;
          _creativePackReceived = 0;
          _creativePackTotal = 0;
        });
      }
    }
  }

  Future<void> _installAllCreativeAssetPacks() async {
    if (_creativePackBusy) return;
    final missing = CreativeAssetPackCatalog.all
        .where((pack) => !_creativeAssetPacks.isInstalled(pack.id))
        .toList();
    if (missing.isEmpty) {
      setState(() => _notice = 'All downloadable packs are already installed.');
      return;
    }
    final totalBytes = missing.fold<int>(
      0,
      (total, pack) => total + pack.estimatedBytes,
    );
    final confirmed = await _confirmAssetPackDownload(
      title: 'Install all ' + missing.length.toString() + ' downloadable packs?',
      detail: 'This includes every catalogued DAEDAL CC0 pack and both complete CLR open-audio volumes. It is a large offline collection and needs several gigabytes of free disk space.',
      size: _formatAssetBytes(totalBytes),
      licence: 'DAEDAL: CC0 1.0 · CLR: mixed item-level public domain / CC BY / CC BY-SA',
    );
    if (!confirmed || !mounted) return;
    var installedCount = 0;
    setState(() {
      _creativePackBusy = true;
      _notice = 'Installing the full offline asset collection…';
    });
    try {
      for (final pack in missing) {
        if (_creativeAssetPacks.isInstalled(pack.id)) continue;
        if (mounted) {
          setState(() {
            _creativePackReceived = 0;
            _creativePackTotal = pack.exactBytes ?? pack.estimatedBytes;
            _notice = 'Downloading ' + pack.name + '…';
          });
        }
        final installed = await _creativeAssetPacks.install(
          pack,
          onProgress: (received, total) {
            if (!mounted) return;
            setState(() {
              _creativePackReceived = received;
              if (total > 0) _creativePackTotal = total;
            });
          },
        );
        installedCount++;
        if (mounted) {
          setState(() {
            _installedCreativePacks = _creativeAssetPacks.installed;
            _notice = 'Installed ' + installed.name + ' · ' +
                installed.fileCount.toString() +
                ' files. Continuing with the next pack…';
          });
        }
      }
      if (mounted) {
        setState(() => _notice = 'Offline asset installation complete: ' +
            installedCount.toString() + ' packs installed.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Installed ' + installedCount.toString() +
            ' packs. Remaining downloads can be resumed later. Error: ' +
            error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _creativePackBusy = false;
          _creativePackReceived = 0;
          _creativePackTotal = 0;
        });
      }
    }
  }

  Future<void> _importExternalAssetZip() async {
    if (_creativePackBusy) return;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw StateError('The selected ZIP has no readable local path.');
      }
      final confirmed = await _confirmAssetPackDownload(
        title: 'Import ' + picked.name + '?',
        detail: 'This imports a user-selected asset archive (for example, a selected AssetPolish CC0 ZIP). Its embedded licence file must be present.',
        size: _formatAssetBytes(await File(path).length()),
        licence: 'User supplied · archive licence is preserved',
      );
      if (!confirmed || !mounted) return;
      setState(() {
        _creativePackBusy = true;
        _notice = 'Importing the selected asset ZIP and checking its licence…';
      });
      final packName = picked.name.toLowerCase().endsWith('.zip')
          ? picked.name.substring(0, picked.name.length - 4)
          : picked.name;
      final imported = await _creativeAssetPacks.importArchive(
        File(path),
        name: packName,
        licenseLabel: 'User imported · licence retained from archive',
      );
      if (mounted) {
        setState(() {
          _installedCreativePacks = _creativeAssetPacks.installed;
          _notice = 'Imported ' + imported.name + ': ' +
              imported.fileCount.toString() +
              ' files. Licence/source file retained.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Asset ZIP import failed: ' + error.toString());
    } finally {
      if (mounted) setState(() => _creativePackBusy = false);
    }
  }

  Future<void> _addCreativeAssetFile(CreativeAssetFile asset) async {
    final path = asset.file.path;
    final extension = path.split('.').last.toLowerCase();
    try {
      switch (asset.kind) {
        case 'image':
          var imagePath = path;
          var width = 0;
          var height = 0;
          if (extension == 'svg') {
            final svg = await File(path).readAsString();
            if (svg.length > 12 * 1024 * 1024) {
              throw const FormatException('SVG exceeds the 12 MiB import limit.');
            }
            final picture = await vg.vg.loadPicture(vg.SvgStringLoader(svg), null);
            try {
              final natural = picture.size;
              if (natural.width <= 0 || natural.height <= 0 ||
                  !natural.width.isFinite || !natural.height.isFinite) {
                throw const FormatException('SVG has no valid intrinsic dimensions.');
              }
              final scale = math.min(1.0, 4096 / math.max(natural.width, natural.height));
              width = (natural.width * scale).round().clamp(1, 4096).toInt();
              height = (natural.height * scale).round().clamp(1, 4096).toInt();
              final rendered = await picture.picture.toImage(width, height);
              try {
                final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
                if (data == null) throw const FormatException('Could not rasterize SVG asset.');
                final support = await getApplicationSupportDirectory();
                final folder = Directory(
                  support.path + Platform.pathSeparator + 'DepthVibe' +
                  Platform.pathSeparator + 'ImportedOverlays',
                );
                await folder.create(recursive: true);
                imagePath = folder.path + Platform.pathSeparator +
                    DateTime.now().microsecondsSinceEpoch.toString() + '.png';
                await File(imagePath).writeAsBytes(data.buffer.asUint8List(), flush: true);
              } finally {
                rendered.dispose();
              }
            } finally {
              picture.picture.dispose();
            }
          } else {
            final decoded = img.decodeImage(await asset.file.readAsBytes());
            if (decoded == null) throw FormatException('Could not decode ' + path + '.');
            width = decoded.width;
            height = decoded.height;
          }
          _controller.addLayer(
            LayerKind.image,
            name: asset.name,
            sourceUri: imagePath,
            sourceWidth: width,
            sourceHeight: height,
          );
          break;
        case 'video':
          _controller.addLayer(
            LayerKind.video,
            name: asset.name,
            sourceUri: path,
          );
          break;
        case 'audio':
          _controller.addLayer(
            LayerKind.audio,
            name: asset.name,
            sourceUri: path,
          );
          break;
        case 'lut':
          final layer = _selected;
          if (layer == null || layer.locked ||
              !{LayerKind.video, LayerKind.image, LayerKind.photoshopLayer,
                LayerKind.adjustment}.contains(layer.kind)) {
            throw StateError('Select an unlocked visual layer before adding a LUT.');
          }
          final info = CubeLutValidator.parse(await asset.file.readAsString());
          var lut = layer.effects
              .where((item) => item.effectId == 'color_lut')
              .lastOrNull;
          if (lut == null) {
            _controller.addEffect('color_lut');
            lut = _selected?.effects
                .where((item) => item.effectId == 'color_lut')
                .lastOrNull;
          }
          if (lut == null) throw StateError('Could not create the 3D LUT effect.');
          _controller.setEffectAssetUri(lut.id, path);
          if (mounted) {
            setState(() => _notice = 'Applied ' + info.title + ' · ' +
                info.size.toString() + '³ LUT.');
          }
          return;
        default:
          return;
      }
      if (mounted) {
        setState(() => _notice = 'Added ' + asset.name + ' from the offline asset pack.');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Could not add ' + asset.name + ': ' + error.toString());
    }
  }

  Future<void> _uninstallCreativeAssetPack(InstalledCreativeAssetPack pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ' + pack.name + '?'),
        content: Text('This removes ' + pack.fileCount.toString() +
            ' local files (' + _formatAssetBytes(pack.expandedBytes) +
            ') from DepthVibe storage. Any project using these files will need the media to be relinked if the pack is removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('REMOVE PACK'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _creativeAssetPacks.uninstall(pack.id);
      if (mounted) {
        setState(() {
          _installedCreativePacks = _creativeAssetPacks.installed;
          _notice = 'Removed ' + pack.name + ' from local asset storage.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Could not remove asset pack: ' + error.toString());
    }
  }

  Future<void> _importLibraryOverlayImage() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'svg'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty || !await File(path).exists()) {
        throw StateError('The selected image has no readable local path.');
      }
      final source = File(path);
      final name = path.split(RegExp(r'[/\\]')).last;
      var storedPath = path;
      var sourceWidth = 0;
      var sourceHeight = 0;

      if (name.toLowerCase().endsWith('.svg')) {
        final svgSource = await source.readAsString();
        if (svgSource.length > 12 * 1024 * 1024) {
          throw const FormatException('The SVG file exceeds the 12 MiB import limit.');
        }
        final pictureInfo = await vg.vg.loadPicture(
          vg.SvgStringLoader(svgSource),
          null,
        );
        try {
          final natural = pictureInfo.size;
          if (!natural.width.isFinite ||
              !natural.height.isFinite ||
              natural.width <= 0 ||
              natural.height <= 0) {
            throw const FormatException('The SVG has no valid intrinsic size.');
          }
          final longestSide = math.max(natural.width, natural.height);
          final scale = math.min(1.0, 4096 / longestSide);
          sourceWidth = (natural.width * scale).round().clamp(1, 4096).toInt();
          sourceHeight = (natural.height * scale).round().clamp(1, 4096).toInt();
          final rendered = await pictureInfo.picture.toImage(
            sourceWidth,
            sourceHeight,
          );
          try {
            final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
            if (png == null) {
              throw const FormatException('Could not rasterize the SVG.');
            }
            final support = await getApplicationSupportDirectory();
            final folder = Directory(
              support.path + Platform.pathSeparator +
              'DepthVibe' + Platform.pathSeparator + 'ImportedOverlays',
            );
            await folder.create(recursive: true);
            final safeBaseName = name
                .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
                .replaceAll(RegExp(r'\.svg$', caseSensitive: false), '');
            storedPath = folder.path + Platform.pathSeparator +
                DateTime.now().microsecondsSinceEpoch.toString() +
                '_' + safeBaseName + '.png';
            await File(storedPath).writeAsBytes(
              png.buffer.asUint8List(),
              flush: true,
            );
          } finally {
            rendered.dispose();
          }
        } finally {
          pictureInfo.picture.dispose();
        }
      } else {
        final bytes = await source.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw const FormatException('The selected file is not a supported image.');
        }
        sourceWidth = decoded.width;
        sourceHeight = decoded.height;
      }

      _controller.addLayer(
        LayerKind.image,
        name: name,
        sourceUri: storedPath,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
      if (mounted) {
        setState(() => _notice = name.toLowerCase().endsWith('.svg')
            ? 'Imported $name as PNG. Embedded SVG animation is not retained.'
            : 'Imported $name as an editable overlay/image layer.');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Image import failed: $error');
    }
  }

  Future<void> _importLibraryVideoOverlay() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'gif'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty || !await File(path).exists()) {
        throw StateError('The selected video has no readable local path.');
      }
      final name = path.split(RegExp(r'[/\\]')).last;
      _controller.addLayer(
        LayerKind.video,
        name: name,
        sourceUri: path,
      );
      if (mounted) setState(() => _notice = 'Imported $name as a video overlay layer.');
    } catch (error) {
      if (mounted) setState(() => _notice = 'Video overlay import failed: $error');
    }
  }

  Future<void> _importLibraryAudio() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty || !await File(path).exists()) {
        throw StateError('The selected audio has no readable local file.');
      }
      final name = path.split(RegExp(r'[/\\]')).last;
      _controller.addLayer(
        LayerKind.audio,
        name: name,
        sourceUri: path,
      );
      if (mounted) setState(() => _notice = 'Imported $name as an audio layer.');
    } catch (error) {
      if (mounted) setState(() => _notice = 'Audio import failed: $error');
    }
  }

  Widget _buildAssetLibraryTile({
    required String title,
    required String category,
    required String description,
    required String countLabel,
    required IconData icon,
    required List<Color> colors,
    required String actionLabel,
    required VoidCallback? onApply,
    String? sampleText,
    Color? sampleColor,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
              child: sampleText == null
                  ? Icon(icon, size: 28, color: Colors.white)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        sampleText,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: sampleColor ?? Colors.white,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(category.toUpperCase() + ' · ' + countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF9FAFC9))),
                  const SizedBox(height: 4),
                  Text(description, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Color(0xFFB5C1D4))),
                ],
              ),
            ),
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              onPressed: onApply,
              icon: const Icon(Icons.add, size: 14),
              label: Text(actionLabel, style: const TextStyle(fontSize: 9)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerTile(
    OverlayStickerDefinition asset, {
    required VoidCallback? onApply,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3B4369), Color(0xFF20283D)],
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  asset.textContent,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: _libraryColor(asset.textColor),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset.name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                  Text(asset.category.toUpperCase(),
                    style: const TextStyle(fontSize: 8, color: Color(0xFF9FAFC9), fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(asset.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Color(0xFFB5C1D4))),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Add ${asset.name} sticker',
              onPressed: onApply,
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFFBBAEFF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitlePresetTile(
    TitlePresetDefinition preset, {
    required VoidCallback? onApply,
  }) {
    return _buildAssetLibraryTile(
      title: preset.name,
      category: preset.category,
      description: preset.description,
      countLabel: preset.motionPresetId,
      icon: Icons.title,
      colors: const [Color(0xFF574B83), Color(0xFF27314D)],
      actionLabel: 'ADD',
      onApply: onApply,
      sampleText: preset.sampleText,
      sampleColor: _libraryColor(preset.textColor),
    );
  }

  Widget _buildAssetLibraryPanel(CompositionLayer? layer) {
    const filters = [
      'All',
      'Overlays & Stickers',
      'Motion',
      'Audio Presets',
      'Titles & Lower Thirds',
      'Color Presets',
      'Video Effects & Filters',
      'Transitions',
    ];
    final query = _librarySearch.trim().toLowerCase();
    bool matches(Iterable<String> fields) =>
        query.isEmpty || fields.join(' ').toLowerCase().contains(query);
    final canApplyLayer = layer != null && !layer.locked;
    final isAudioTarget = layer != null && !layer.locked &&
        (layer.kind == LayerKind.audio || layer.kind == LayerKind.video);
    final isVisualTarget = layer != null && !layer.locked &&
        {LayerKind.video, LayerKind.image, LayerKind.photoshopLayer,
          LayerKind.text, LayerKind.adjustment}.contains(layer.kind);
    final visualCount = _controller.document.layers.where((item) =>
      item.enabled &&
      {LayerKind.video, LayerKind.image, LayerKind.photoshopLayer}.contains(item.kind)
    ).length;
    final canApplyTransition = visualCount >= 2;

    final overlays = OverlayStickerCatalog.all.where((item) =>
      matches([item.name, item.category, item.description, item.textContent])
    ).toList();
    final motion = MotionPresetCatalog.all.where((item) =>
      matches([item.name, item.category, item.description])
    ).toList();
    final audio = AudioPresetCatalog.all.where((item) =>
      matches([item.name, item.category, item.description])
    ).toList();
    final titles = TitlePresetCatalog.all.where((item) =>
      matches([item.name, item.category, item.description, item.sampleText])
    ).toList();
    final colors = ColorPresetCatalog.all.where((item) =>
      matches([item.name, item.category, item.description])
    ).toList();
    final looks = EffectPresetCatalog.all.where((item) =>
      matches([item.name, item.category, item.description])
    ).toList();
    final effects = EffectCatalog.allEffects.where((item) =>
      matches([item.name, item.category, item.description, item.ffmpegFilter])
    ).toList();
    final transitions = TransitionPresetCatalog.all.where((item) =>
      matches([item.name, item.category, item.description])
    ).toList();

    final showAll = _libraryFilter == 'All';
    final showOverlays = showAll || _libraryFilter == 'Overlays & Stickers';
    final showMotion = showAll || _libraryFilter == 'Motion';
    final showAudio = showAll || _libraryFilter == 'Audio Presets';
    final showTitles = showAll || _libraryFilter == 'Titles & Lower Thirds';
    final showColors = showAll || _libraryFilter == 'Color Presets';
    final showEffects = showAll || _libraryFilter == 'Video Effects & Filters';
    final showTransitions = showAll || _libraryFilter == 'Transitions';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('DEPTHVIBE CREATIVE ASSET LIBRARY', Icons.video_library_outlined),
        const Text(
          'A searchable collection of editable overlays, animated stickers, motion, audio, titles, color looks, effects and transitions. Built-in recipes work offline; external packs keep their own source and licence.',
          style: TextStyle(fontSize: 10, color: Color(0xFF9EADC4)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final filter in filters)
              ChoiceChip(
                label: Text(filter, style: const TextStyle(fontSize: 9)),
                selected: _libraryFilter == filter,
                onSelected: (_) => setState(() => _libraryFilter = filter),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: (value) => setState(() => _librarySearch = value),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 17),
            hintText: 'Search every category, preset and asset…',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _assetCountChip(Icons.layers_outlined, '${OverlayStickerCatalog.all.length} overlay/sticker assets'),
            _assetCountChip(Icons.animation, '${MotionPresetCatalog.all.length} motion recipes'),
            _assetCountChip(Icons.graphic_eq, '${AudioPresetCatalog.all.length} audio presets'),
            _assetCountChip(Icons.title, '${TitlePresetCatalog.all.length} title styles'),
            _assetCountChip(Icons.color_lens_outlined, '${ColorPresetCatalog.all.length + EffectPresetCatalog.all.length} color looks'),
            _assetCountChip(Icons.auto_awesome, '${EffectCatalog.all.length} built-in effects'),
            _assetCountChip(Icons.swap_horiz, '${TransitionPresetCatalog.all.length} transition recipes'),
            _assetCountChip(Icons.library_books_outlined, '399 built-in catalog entries'),
            _assetCountChip(Icons.public, '${OpenAssetSourceCatalog.all.length} open asset sources'),
          ],
        ),
        const SizedBox(height: 8),
        if (layer == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Select a visual layer for effect/color presets or an audio/video layer for audio presets. Titles and typographic stickers can be added as new editable text layers.',
              style: TextStyle(fontSize: 9, color: Color(0xFFE2C58E)),
            ),
          ),
        if (showOverlays) ...[
          _panelHeader('OVERLAYS & STICKERS', Icons.layers_outlined),
          for (final asset in overlays.where((item) => item.isEffectOverlay))
            EffectPreviewTile(
              effect: EffectCatalog.find(asset.effectId!)!,
              titleOverride: asset.name,
              subtitleOverride: '${asset.category} · native overlay effect',
              onApply: isVisualTarget ? () => _applyOverlaySticker(asset, layer) : null,
            ),
          for (final asset in overlays.where((item) => !item.isEffectOverlay))
            _buildStickerTile(
              asset,
              onApply: () => _applyOverlaySticker(asset, layer),
            ),
          if (overlays.isEmpty)
            const Text('No overlay or sticker assets match this search.', style: TextStyle(fontSize: 10)),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: _importLibraryOverlayImage,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 15),
                label: const Text('IMPORT IMAGE / SVG'),
              ),
              OutlinedButton.icon(
                onPressed: _importLibraryVideoOverlay,
                icon: const Icon(Icons.video_library_outlined, size: 15),
                label: const Text('IMPORT VIDEO / GIF OVERLAY'),
              ),
            ],
          ),
        ],
        if (showMotion) ...[
          const Divider(height: 20),
          _panelHeader('MOTION', Icons.animation),
          for (final preset in motion)
            _buildAssetLibraryTile(
              title: preset.name,
              category: preset.category,
              description: preset.description,
              countLabel: '${preset.tracks.length} tracks · ${preset.durationMs} ms',
              icon: Icons.motion_photos_on_outlined,
              colors: const [Color(0xFF3C927E), Color(0xFF174C57)],
              actionLabel: 'APPLY',
              onApply: canApplyLayer ? () {
                _controller.applyMotionPreset(preset.id);
                setState(() => _notice = 'Applied ${preset.name} keyframe animation.');
              } : null,
            ),
          if (motion.isEmpty)
            const Text('No motion recipes match this search.', style: TextStyle(fontSize: 10)),
        ],
        if (showAudio) ...[
          const Divider(height: 20),
          _panelHeader('AUDIO PRESETS', Icons.graphic_eq),
          for (final preset in audio)
            _buildAssetLibraryTile(
              title: preset.name,
              category: preset.category,
              description: preset.description,
              countLabel: 'EQ · gain · fades',
              icon: Icons.equalizer,
              colors: const [Color(0xFF287D87), Color(0xFF18384E)],
              actionLabel: 'APPLY',
              onApply: isAudioTarget ? () => _applyAudioPreset(preset, layer) : null,
              sampleText: 'L  ▂▅▃▆  R',
            ),
          if (!isAudioTarget)
            const Text('Select an audio or video layer before applying an audio preset.', style: TextStyle(fontSize: 9, color: Color(0xFFE2C58E))),
          if (audio.isEmpty)
            const Text('No audio presets match this search.', style: TextStyle(fontSize: 10)),
          OutlinedButton.icon(
            onPressed: _importLibraryAudio,
            icon: const Icon(Icons.audio_file_outlined, size: 15),
            label: const Text('IMPORT AUDIO FILE'),
          ),
        ],
        if (showTitles) ...[
          const Divider(height: 20),
          _panelHeader('TITLES & LOWER THIRDS', Icons.title),
          for (final preset in titles)
            _buildTitlePresetTile(
              preset,
              onApply: () => _applyTitlePreset(preset),
            ),
          if (titles.isEmpty)
            const Text('No title presets match this search.', style: TextStyle(fontSize: 10)),
        ],
        if (showColors) ...[
          const Divider(height: 20),
          _panelHeader('COLOR PRESETS', Icons.color_lens_outlined),
          for (final preset in colors)
            _buildAssetLibraryTile(
              title: preset.name,
              category: preset.category,
              description: preset.description,
              countLabel: 'primary grade',
              icon: Icons.palette_outlined,
              colors: const [Color(0xFFB66E4E), Color(0xFF4F557D)],
              actionLabel: 'APPLY',
              onApply: isVisualTarget ? () => _applyColorPreset(preset, layer) : null,
              sampleText: 'Aa',
            ),
          if (colors.isEmpty)
            const Text('No color presets match this search.', style: TextStyle(fontSize: 10)),
          OutlinedButton.icon(
            onPressed: _importColorLut,
            icon: const Icon(Icons.file_open_outlined, size: 15),
            label: const Text('IMPORT 3D .CUBE LUT'),
          ),
          const Divider(height: 12),
          _panelHeader('MULTI-EFFECT COLOR LOOKS', Icons.auto_awesome),
          for (final preset in looks)
            EffectPreviewTile(
              effect: EffectCatalog.find(preset.steps.first.effectId)!,
              titleOverride: preset.name,
              subtitleOverride: '${preset.category} · ${preset.steps.length} effects · first-effect preview',
              onApply: canApplyLayer ? () {
                _controller.applyEffectPreset(preset.id);
                setState(() => _notice = 'Applied ${preset.name} effect stack.');
              } : null,
            ),
          if (looks.isEmpty)
            const Text('No multi-effect looks match this search.', style: TextStyle(fontSize: 10)),
        ],
        if (showEffects) ...[
          const Divider(height: 20),
          _panelHeader('VIDEO EFFECTS & FILTERS', Icons.auto_awesome),
          for (final effect in effects)
            EffectPreviewTile(
              effect: effect,
              onApply: isVisualTarget ? () {
                _controller.addEffect(effect.id);
                setState(() => _notice = 'Added ${effect.name} effect.');
              } : null,
            ),
          if (!isVisualTarget)
            const Text('Select an unlocked video, image or text layer to apply a video effect.', style: TextStyle(fontSize: 9, color: Color(0xFFE2C58E))),
          if (effects.isEmpty)
            const Text('No video effects match this search.', style: TextStyle(fontSize: 10)),
        ],
        if (showTransitions) ...[
          const Divider(height: 20),
          _panelHeader('TRANSITIONS', Icons.swap_horiz),
          for (final preset in transitions)
            TransitionPreviewTile(
              kind: preset.kind,
              titleOverride: preset.name,
              subtitleOverride: '${preset.category} · ${preset.durationMs} ms',
              onApply: canApplyTransition ? () => _applyTransitionPreset(preset) : null,
            ),
          if (!canApplyTransition)
            const Text('Add or enable two video/image clips to use transition recipes.', style: TextStyle(fontSize: 9, color: Color(0xFFE2C58E))),
          if (transitions.isEmpty)
            const Text('No transition recipes match this search.', style: TextStyle(fontSize: 10)),
        ],
        const Divider(height: 20),
        _panelHeader('IMPORT & ONLINE LIBRARIES', Icons.cloud_download_outlined),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExtensionMarketplaceScreen()),
              ),
              icon: const Icon(Icons.storefront_outlined, size: 16),
              label: const Text('SIGNED ONLINE MARKETPLACE'),
            ),
            OutlinedButton.icon(
              onPressed: () => _importMotionPreset(),
              icon: const Icon(Icons.file_upload_outlined, size: 15),
              label: const Text('IMPORT .DVMPRESET'),
            ),
          ],
        ),
        const Divider(height: 16),
        _panelHeader('OPEN-LICENCE ONLINE SOURCES', Icons.public),
        const Text(
          'Browse large external collections. Downloads remain on their original sites; check the licence for each chosen file before using or redistributing it.',
          style: TextStyle(fontSize: 9, color: Color(0xFF9EADC4)),
        ),
        for (final source in OpenAssetSourceCatalog.all)
          _buildAssetLibraryTile(
            title: source.name,
            category: source.category,
            description: source.description,
            countLabel: source.licenseLabel + ' · ' + source.countLabel,
            icon: Icons.open_in_new,
            colors: const [Color(0xFF2F6377), Color(0xFF202F49)],
            actionLabel: 'OPEN',
            onApply: () => _openAssetSource(source),
          ),
        const SizedBox(height: 6),
        _buildCreativeAssetPackBrowser(),
        const SizedBox(height: 8),
        _buildMotionBroPackBrowser(),
      ],
    );
  }

  Widget _buildInstalledCreativeAssetPackTile(InstalledCreativeAssetPack pack) {
    return Card(
      margin: const EdgeInsets.only(bottom: 5),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Text(pack.name,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
        subtitle: Text(
          pack.fileCount.toString() + ' files · ' +
              _formatAssetBytes(pack.expandedBytes) + ' · ' + pack.licenseLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 8, color: Color(0xFF9EADC4)),
        ),
        leading: const Icon(Icons.inventory_2_outlined, color: Color(0xFF83D2B9)),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _creativePackBusy ? null : () => _uninstallCreativeAssetPack(pack),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('REMOVE LOCAL PACK'),
            ),
          ),
          FutureBuilder<List<CreativeAssetFile>>(
            future: _creativeAssetPacks.filesForPack(pack.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Could not index this pack: ' + snapshot.error.toString(),
                  style: const TextStyle(fontSize: 9, color: Color(0xFFE5A2A2)),
                );
              }
              final allFiles = snapshot.data ?? const <CreativeAssetFile>[];
              final term = _librarySearch.trim().toLowerCase();
              final visible = allFiles.where((asset) =>
                term.isEmpty || asset.relativePath.toLowerCase().contains(term)
              ).take(120).toList();
              if (allFiles.isEmpty) {
                return const Text(
                  'No directly importable image, video, audio or LUT files were found.',
                  style: TextStyle(fontSize: 9, color: Color(0xFF9EADC4)),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Browse local media · showing ' + visible.length.toString() +
                        ' of ' + allFiles.length.toString(),
                    style: const TextStyle(fontSize: 9, color: Color(0xFF9EADC4)),
                  ),
                  for (final asset in visible)
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        switch (asset.kind) {
                          'image' => Icons.image_outlined,
                          'video' => Icons.movie_outlined,
                          'audio' => Icons.graphic_eq,
                          'lut' => Icons.color_lens_outlined,
                          _ => Icons.insert_drive_file_outlined,
                        },
                        size: 17,
                        color: const Color(0xFFB8C9E6),
                      ),
                      title: Text(asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9)),
                      subtitle: Text(asset.kind.toUpperCase(),
                        style: const TextStyle(fontSize: 8, color: Color(0xFF9EADC4))),
                      trailing: IconButton(
                        tooltip: 'Add ' + asset.name + ' to the project',
                        icon: const Icon(Icons.add_circle_outline, size: 17),
                        onPressed: _creativePackBusy
                            ? null
                            : () => _addCreativeAssetFile(asset),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCreativeAssetPackBrowser() {
    final term = _librarySearch.trim().toLowerCase();
    final visiblePacks = CreativeAssetPackCatalog.all.where((pack) =>
      term.isEmpty ||
      (pack.name + ' ' + pack.category + ' ' + pack.description + ' ' +
          pack.licenseLabel).toLowerCase().contains(term)
    ).toList();
    final missing = CreativeAssetPackCatalog.all
        .where((pack) => !_creativeAssetPacks.isInstalled(pack.id))
        .toList();
    final busy = _creativePackBusy;
    final progressValue = _creativePackTotal > 0
        ? (_creativePackReceived / _creativePackTotal).clamp(0.0, 1.0).toDouble()
        : null;
    final missingBytes = missing.fold<int>(
      0,
      (sum, pack) => sum + pack.estimatedBytes,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 20),
        _panelHeader('LOCAL OFFLINE ASSET PACKS', Icons.offline_pin),
        const Text(
          'Download once, extract to DepthVibe storage, then use these files offline. Each pack keeps its original source and licence notice.',
          style: TextStyle(fontSize: 9, color: Color(0xFF9EADC4)),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _assetCountChip(Icons.cloud_download_outlined,
                CreativeAssetPackCatalog.all.length.toString() + ' downloadable packs'),
            _assetCountChip(Icons.offline_pin,
                _installedCreativePacks.length.toString() + ' installed'),
            _assetCountChip(Icons.storage,
                _formatAssetBytes(_creativeAssetPacks.installedBytes) + ' local storage'),
            _assetCountChip(Icons.download_done_outlined,
                _formatAssetBytes(CreativeAssetPackCatalog.totalEstimatedBytes) + ' total download'),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: busy || missing.isEmpty ? null : _installAllCreativeAssetPacks,
          icon: const Icon(Icons.download_for_offline_outlined, size: 17),
          label: Text(
            missing.isEmpty
                ? 'ALL DOWNLOADABLE PACKS INSTALLED'
                : 'INSTALL ALL ' + missing.length.toString() +
                    ' PACKS · ' + _formatAssetBytes(missingBytes),
          ),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : _importExternalAssetZip,
          icon: const Icon(Icons.folder_zip_outlined, size: 16),
          label: const Text('IMPORT ASSET ZIP · ASSET POLISH / OTHER'),
        ),
        const Text(
          'AssetPolish offers selected-assets ZIP downloads, not one whole-library archive. Download a CC0 selection from its original site and import the ZIP here; its licence file is required.',
          style: TextStyle(fontSize: 9, color: Color(0xFFE2C58E)),
        ),
        if (busy) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progressValue),
          const SizedBox(height: 4),
          Text(
            'Downloading ' + (_creativeAssetPacks.activePackId ?? 'asset pack') +
                ' · ' + _formatAssetBytes(_creativePackReceived) +
                (_creativePackTotal > 0
                    ? ' / ' + _formatAssetBytes(_creativePackTotal)
                    : ''),
            style: const TextStyle(fontSize: 9, color: Color(0xFFB9C8DE)),
          ),
        ],
        const Divider(height: 18),
        _panelHeader('INSTALLED PACKS', Icons.inventory_2_outlined),
        if (_installedCreativePacks.isEmpty)
          const Text(
            'No external media packs installed yet. Install a pack or import a licensed ZIP; downloaded files will remain available for offline editing.',
            style: TextStyle(fontSize: 9, color: Color(0xFF9EADC4)),
          ),
        for (final pack in _installedCreativePacks)
          _buildInstalledCreativeAssetPackTile(pack),
        const Divider(height: 16),
        _panelHeader('DOWNLOADABLE UPSTREAM PACKS', Icons.cloud_download_outlined),
        for (final pack in visiblePacks)
          _buildAssetLibraryTile(
            title: pack.name,
            category: pack.category,
            description: pack.description,
            countLabel: pack.sizeLabel + ' · ' + pack.licenseLabel,
            icon: Icons.archive_outlined,
            colors: const [Color(0xFF315D78), Color(0xFF1F3048)],
            actionLabel: _creativeAssetPacks.isInstalled(pack.id) ? 'INSTALLED' : 'INSTALL',
            onApply: busy || _creativeAssetPacks.isInstalled(pack.id)
                ? null
                : () => _installCreativeAssetPack(pack),
          ),
        if (visiblePacks.isEmpty)
          const Text('No downloadable asset packs match this search.',
            style: TextStyle(fontSize: 9, color: Color(0xFF9EADC4))),
      ],
    );
  }

  Widget _assetCountChip(IconData icon, String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF202B3C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF35445C)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: const Color(0xFFB8C9E6)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFFCFD9E8))),
          ],
        ),
      ),
    );
  }

  void _reorderRightPanels(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final panel = _rightPanelOrder.removeAt(oldIndex);
      _rightPanelOrder.insert(newIndex, panel);
    });
  }

  Widget _buildActivePanel(CompositionLayer? layer) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    const panels = <(String, String, IconData)>[
      ('Transform', 'Transform', Icons.transform),
      ('Effects', 'Effect Controls', Icons.auto_awesome),
      ('Animation', 'Graph Editor', Icons.show_chart),
      ('Layers', 'Layer Info', Icons.layers_outlined),
      ('Timing', 'Timing', Icons.schedule),
      ('Typography', 'Character', Icons.text_fields),
      ('Shape', 'Shape', Icons.category_outlined),
      ('Color', 'Color', Icons.color_lens_outlined),
      ('Masks', 'Masks', Icons.crop_free),
      ('Tracking', 'Tracker', Icons.track_changes),
      ('Parent', 'Parent & Link', Icons.account_tree_outlined),
      ('3D', '3D', Icons.view_in_ar),
      ('Audio', 'Audio', Icons.graphic_eq),
      ('Bus Mixer', 'Audio Mixer', Icons.tune),
      ('Transitions', 'Transitions', Icons.compare_arrows),
      ('Library', 'Libraries', Icons.video_library_outlined),
    ];
    final panelById = {for (final item in panels) item.$1: item};
    final orderedPanels = _rightPanelOrder
        .where(panelById.containsKey)
        .map((id) => panelById[id]!)
        .toList();
    final active = panelById[_panel] ?? panels.first;

    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 39,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: true,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              itemCount: orderedPanels.length,
              onReorder: _reorderRightPanels,
              itemBuilder: (context, index) {
                final item = orderedPanels[index];
                final selected = _panel == item.$1;
                return Tooltip(
                  key: ValueKey<String>('dock-${item.$1}'),
                  message: 'Drag to reorder · ${item.$2}',
                  child: InkWell(
                    onTap: () => setState(() => _panel = item.$1),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 76),
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: selected ? palette.accentSoft : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: selected ? palette.accent : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.$3,
                            size: 13,
                            color: selected
                                ? palette.accent
                                : palette.secondaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.$2.toUpperCase(),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 8,
                              letterSpacing: 0.25,
                              fontWeight: selected
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                              color: selected
                                  ? palette.primaryText
                                  : palette.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 39,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: palette.toolbar,
              border: Border(
                top: BorderSide(color: palette.border),
                bottom: BorderSide(color: palette.border),
              ),
            ),
            child: Row(
              children: [
                Icon(active.$3, size: 15, color: palette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.$2.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w900,
                      color: palette.primaryText,
                    ),
                  ),
                ),
                Text(
                  layer == null ? 'NO LAYER SELECTED' : layer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8,
                    color: palette.secondaryText,
                  ),
                ),
                const SizedBox(width: 5),
                PopupMenuButton<String>(
                  tooltip: 'Restore After Effects workspace',
                  onSelected: (_) => _applyWorkspacePreset('After Effects'),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'restore',
                      child: Text('Restore Default Panel Layout'),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      Icons.more_horiz,
                      size: 17,
                      color: palette.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: layer == null
                ? _panel == 'Bus Mixer'
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: _buildAudioBusPanel(null),
                      )
                    : _panel == 'Library'
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: _buildAssetLibraryPanel(null),
                          )
                        : const Center(
                            child: Text('Select a layer to edit'),
                          )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _panelContent(layer),
                  ),
          ),
        ],
      ),
    );
  }


  Widget _panelContent(CompositionLayer layer) {
    switch (_panel) {
      case 'Typography':
        return _buildTypographyPanel(layer);
      case 'Timing':
        return _buildTimingPanel(layer);
      case 'Transform':
        return _buildTransformPanel(layer);
      case 'Color':
        return _buildColorPanel(layer);
      case 'Animation':
        return _buildAnimationPanel(layer);
      case 'Shape':
        return _buildShapePanel(layer);
      case 'Effects':
        return _buildEffectsPanel(layer);
      case 'Library':
        return _buildAssetLibraryPanel(layer);
      case 'Masks':
        return _buildMasksPanel(layer);
      case 'Audio':
        return _buildAudioPanel(layer);
      case 'Bus Mixer':
        return _buildAudioBusPanel(layer);
      case 'Tracking':
        return _buildTrackingPanel(layer);
      case 'Transitions':
        return _buildTransitionsPanel(layer);
      case 'Parent':
        return _buildParentPanel(layer);
      case '3D':
        return _build3dPanel(layer);
      default:
        return _buildLayerInfo(layer);
    }
  }

  Widget _buildLayerInfo(CompositionLayer layer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('SELECTED LAYER', _iconFor(layer.kind)),
        Text(layer.textContent ?? layer.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(layer.kind.name, style: const TextStyle(fontSize: 11, color: Color(0xFF9DABC3))),
        const SizedBox(height: 12),
        Text('Keyframe tracks: ${layer.keyframeTracks.length}'),
        Text('Masks: ${layer.masks.length}'),
        Text('Effects: ${layer.effects.length}'),
        Text('Parent: ${layer.parentId ?? 'None'}'),
        if (layer.photoshopClipped)
          Text(
            'Clipped to base: ${layer.clippingBaseLayerId ?? 'unresolved'}',
            style: const TextStyle(fontSize: 10, color: Color(0xFFE4C38A)),
          ),
        if (layer.smartObjectResourceId != null)
          Text(
            'Smart Object ID: ${layer.smartObjectResourceId}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF9EDBCF)),
          ),
        if (layer.smartObjectSourceUri != null) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => Share.shareXFiles(
              [XFile(layer.smartObjectSourceUri!)],
              text: 'Embedded Photoshop Smart Object',
            ),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Share embedded Smart Object source'),
          ),
        ],
        if (layer.photoshopAdjustmentKey != null)
          Text(
            'PSD adjustment block: ${layer.photoshopAdjustmentKey}',
            style: const TextStyle(fontSize: 10, color: Color(0xFFB6A5FF)),
          ),
        const SizedBox(height: 8),
        DropdownButtonFormField<LayerBlendMode>(
          initialValue: layer.blendMode,
          decoration: const InputDecoration(labelText: 'Blend mode'),
          items: LayerBlendMode.values
              .map((mode) => DropdownMenuItem(value: mode, child: Text(mode.name)))
              .toList(),
          onChanged: (value) {
            if (value != null) _controller.setLayerBlendMode(value);
          },
        ),
        if (layer.blendMode != LayerBlendMode.normal) ...[
          const SizedBox(height: 5),
          const Text(
            'Selected blend mode is applied in FFmpeg export. Canvas preview still uses normal source-over compositing.',
            style: TextStyle(fontSize: 9, color: Color(0xFFE3C28D)),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _addKeyframe('position.x'),
          icon: const Icon(Icons.key, size: 16),
          label: const Text('Add Position Keyframe'),
        ),
      ],
    );
  }


  Widget _buildTypographyPanel(CompositionLayer layer) {
    if (layer.kind != LayerKind.text) {
      return const Center(
        child: Text('Select a Text layer to edit multilingual typography.'),
      );
    }
    final manager = FontManagerService.instance;
    final fonts = manager.fonts;
    final selectedFamily = layer.textFontFamily ?? '';
    final colorText = layer.textColor;
    final normalizedWeight = (layer.textFontWeight / 100).round()
        .clamp(1, 9).toInt() * 100;

    Widget numericField(
      String label,
      double value,
      ValueChanged<double> onSubmit, {
      bool integer = false,
    }) {
      return SizedBox(
        width: 140,
        child: TextFormField(
          key: ValueKey<String>(layer.id + label + value.toString()),
          initialValue: integer ? value.round().toString() : value.toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
          onFieldSubmitted: (raw) {
            final parsed = double.tryParse(raw);
            if (parsed != null && parsed.isFinite) onSubmit(parsed);
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('MULTILINGUAL TYPOGRAPHY', Icons.text_fields),
        TextLayerContentEditor(
          key: ValueKey<String>(layer.id),
          initialText: layer.textContent ?? '',
          onSave: (value) =>
              _controller.updateTextLayer(textContent: value),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _chooseLayerFont(layer),
          icon: const Icon(Icons.font_download_outlined, size: 17),
          label: Text(
            fonts.where((font) => font.family == selectedFamily).isNotEmpty
                ? fonts.firstWhere((font) => font.family == selectedFamily).displayName
                : (selectedFamily.isEmpty ? 'App default / automatic fallback' : selectedFamily),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openFontManager,
          icon: const Icon(Icons.library_books_outlined, size: 16),
          label: const Text('Browse, import and preview world fonts'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            numericField(
              'Font size',
              layer.textFontSize,
              (value) => _controller.updateTextLayer(
                textFontSize: value.clamp(1, 2000).toDouble(),
              ),
            ),
            numericField(
              'Letter spacing',
              layer.textLetterSpacing,
              (value) => _controller.updateTextLayer(
                textLetterSpacing: value.clamp(-100, 500).toDouble(),
              ),
            ),
            numericField(
              'Line height',
              layer.textLineHeight,
              (value) => _controller.updateTextLayer(
                textLineHeight: value.clamp(0.1, 10).toDouble(),
              ),
            ),
            numericField(
              'Text box width',
              layer.textBoxWidth,
              (value) => _controller.updateTextLayer(
                textBoxWidth: value.clamp(1, 20000).toDouble(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: normalizedWeight,
          decoration: const InputDecoration(labelText: 'Font weight'),
          items: [
            for (var weight = 100; weight <= 900; weight += 100)
              DropdownMenuItem(
                value: weight,
                child: Text(
                  weight.toString() +
                      (weight == 400 ? ' · Regular' : weight == 700 ? ' · Bold' : ''),
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              _controller.updateTextLayer(textFontWeight: value);
            }
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Italic'),
          value: layer.textItalic,
          onChanged: (value) =>
              _controller.updateTextLayer(textItalic: value),
        ),
        TextFormField(
          key: ValueKey<String>(layer.id + 'color' + colorText),
          initialValue: colorText,
          decoration: const InputDecoration(
            labelText: 'Text color · #AARRGGBB / #RRGGBB',
            isDense: true,
          ),
          onFieldSubmitted: (value) {
            final parsed = value.trim();
            if (RegExp(r'^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$')
                .hasMatch(parsed)) {
              _controller.updateTextLayer(textColor: parsed.toUpperCase());
            }
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: const {'left', 'center', 'right', 'justify'}
                  .contains(layer.textAlign)
              ? layer.textAlign
              : 'left',
          decoration: const InputDecoration(labelText: 'Text alignment'),
          items: const [
            DropdownMenuItem(value: 'left', child: Text('Left')),
            DropdownMenuItem(value: 'center', child: Text('Center')),
            DropdownMenuItem(value: 'right', child: Text('Right')),
            DropdownMenuItem(value: 'justify', child: Text('Justify')),
          ],
          onChanged: (value) {
            if (value != null) _controller.updateTextLayer(textAlign: value);
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey<String>(layer.id + 'fallback' + layer.textFontFallback.join(',')),
          initialValue: layer.textFontFallback.join(', '),
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Layer glyph fallback families',
            hintText: 'Noto Sans Bengali, Noto Naskh Arabic, Noto Sans CJK SC',
          ),
          onFieldSubmitted: (value) => _controller.updateTextLayer(
            textFontFallback: value
                .split(RegExp(r'[,;\n]'))
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .take(32)
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'TTF/OTF fonts can be imported and embedded in .dvproj. Missing glyphs are resolved through the selected fallback chain and then the operating system.',
          style: TextStyle(fontSize: 10, color: Color(0xFF91A2BA)),
        ),
      ],
    );
  }

  Widget _buildTimingPanel(CompositionLayer layer) {
    Widget field(String label, int value, ValueChanged<int> onSubmit) {
      return SizedBox(
        width: 135,
        child: TextFormField(
          key: ValueKey<String>(layer.id + label + value.toString()),
          initialValue: value.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onFieldSubmitted: (text) {
            final parsed = int.tryParse(text);
            if (parsed != null) onSubmit(parsed);
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('CLIP TIMING', Icons.content_cut),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            field('Timeline start (ms)', layer.startMs,
                (value) => _controller.setLayerTiming(layer.id, startMs: value)),
            field('Duration (ms)', layer.durationMs,
                (value) => _controller.setLayerTiming(layer.id, durationMs: value)),
            if (layer.kind == LayerKind.video || layer.kind == LayerKind.audio)
              field('Source In (ms)', layer.sourceInMs,
                  (value) => _controller.setLayerTiming(layer.id, sourceInMs: value)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Timeline out: ' + layer.endMs.toString() + ' ms',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9BAAC1)),
        ),
        const Text(
          'Drag the clip body in the timeline to move it. Drag its right edge to change duration. Source In trims the media before timeline placement.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
      ],
    );
  }

  Widget _buildShapePanel(CompositionLayer layer) {
    final style = layer.shapeStyle ?? const ShapeStyle();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('VECTOR SHAPE', Icons.category_outlined),
        DropdownButtonFormField<ShapePrimitive>(
          initialValue: style.primitive,
          decoration: const InputDecoration(labelText: 'Primitive'),
          items: ShapePrimitive.values
              .map((value) => DropdownMenuItem(value: value, child: Text(value.name)))
              .toList(),
          onChanged: (value) {
            if (value != null) _controller.setShapeStyle(style.copyWith(primitive: value));
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: style.fillColor,
          decoration: const InputDecoration(labelText: 'Fill color (hex)'),
          onChanged: (value) => _controller.setShapeStyle(style.copyWith(fillColor: value)),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: style.strokeColor,
          decoration: const InputDecoration(labelText: 'Stroke color (hex)'),
          onChanged: (value) => _controller.setShapeStyle(style.copyWith(strokeColor: value)),
        ),
        Text('Stroke width: ${style.strokeWidth.toStringAsFixed(1)} px'),
        Slider(
          min: 0,
          max: 30,
          value: style.strokeWidth.clamp(0, 30).toDouble(),
          onChanged: (value) => _controller.setShapeStyle(style.copyWith(strokeWidth: value)),
        ),
        Text('Corner radius: ${style.cornerRadius.toStringAsFixed(1)} px'),
        Slider(
          min: 0,
          max: 100,
          value: style.cornerRadius.clamp(0, 100).toDouble(),
          onChanged: (value) => _controller.setShapeStyle(style.copyWith(cornerRadius: value)),
        ),
      ],
    );
  }

  Widget _buildTransformPanel(CompositionLayer layer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('TRANSFORM', Icons.open_with),
        for (final item in const [
          ('Position X', 'position.x', 0.0, 1920.0),
          ('Position Y', 'position.y', 0.0, 1080.0),
          ('Position Z', 'position.z', -2000.0, 2000.0),
          ('Scale X', 'scale.x', 0.0, 400.0),
          ('Scale Y', 'scale.y', 0.0, 400.0),
          ('Rotation Z', 'rotation.z', -360.0, 360.0),
          ('Rotation X', 'rotation.x', -180.0, 180.0),
          ('Rotation Y', 'rotation.y', -180.0, 180.0),
          ('Opacity', 'opacity', 0.0, 100.0),
        ])
          _animatedPropertyRow(layer, item.$1, item.$2, item.$3, item.$4),
      ],
    );
  }

  Widget _animatedPropertyRow(
    CompositionLayer layer,
    String label,
    String property,
    double min,
    double max,
  ) {
    final value = layer.valueAt(property, _controller.document.playheadMs);
    final matchingTracks =
        layer.keyframeTracks.where((item) => item.property == property);
    final keyframes =
        matchingTracks.isEmpty ? 0 : matchingTracks.first.keyframes.length;
    ScalarKeyframe? activeKeyframe;
    if (matchingTracks.isNotEmpty) {
      for (final frame in matchingTracks.first.keyframes) {
        if (frame.timeMs == _controller.document.playheadMs) {
          activeKeyframe = frame;
          break;
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add keyframe at current playhead',
              onPressed: () => _addKeyframe(property),
              icon: Icon(
                Icons.diamond,
                size: 16,
                color: keyframes > 0
                    ? const Color(0xFFB6A5FF)
                    : const Color(0xFF8A98B0),
              ),
            ),
            if (keyframes > 0)
              PopupMenuButton<Interpolation>(
                tooltip: 'Set keyframe interpolation at playhead',
                icon: const Icon(Icons.linear_scale, size: 16),
                onSelected: (value) =>
                    _controller.setInterpolation(property, value),
                itemBuilder: (_) => Interpolation.values
                    .map((value) => PopupMenuItem(
                          value: value,
                          child: Text(value.name),
                        ))
                    .toList(),
              ),
            if (activeKeyframe?.interpolation == Interpolation.cubicBezier)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Edit Bezier graph',
                icon: const Icon(Icons.timeline, size: 16),
                onPressed: () => _editBezierCurve(
                  property,
                  activeKeyframe!.bezier,
                ),
              ),
            SizedBox(
              width: 54,
              child: Text(
                value.toStringAsFixed(1),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: (next) => _controller.setTransformValue(property, next),
          onChangeEnd: (next) {
            if (keyframes > 0) {
              _controller.setTransformValue(property, next, keyframe: true);
            }
          },
        ),
      ],
    );
  }

  Widget _buildAnimationPanel(CompositionLayer layer) {
    final trackCount = layer.keyframeTracks.length +
        layer.effects.fold<int>(
          0,
          (count, effect) => count + effect.keyframeTracks.length,
        ) +
        layer.masks.fold<int>(
          0,
          (count, mask) => count + mask.keyframeTracks.length,
        ) +
        _controller.document.audioBuses.fold<int>(
          0,
          (count, bus) => count + bus.keyframeTracks.length,
        );
    final cards = <Widget>[
      _panelHeader('UNIFIED GRAPH EDITOR', Icons.timeline),
      const Text(
        'Every animated property on this layer is listed here. Choose a keyframe to adjust its interpolation and open the same Bezier graph editor.',
        style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
      ),
      const SizedBox(height: 8),
      if (trackCount == 0)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No animated properties yet. Add keyframes in Transform, Effects or Audio.',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
    ];

    for (final track in layer.keyframeTracks) {
      cards.add(_buildUnifiedTrackCard(
        title: track.property,
        track: track,
      ));
    }
    for (final effect in layer.effects) {
      for (final track in effect.keyframeTracks) {
        cards.add(_buildUnifiedTrackCard(
          title: '${effect.name} · ${track.property}',
          track: track,
          effectId: effect.id,
        ));
      }
    }
    for (final mask in layer.masks) {
      for (final track in mask.keyframeTracks) {
        cards.add(_buildUnifiedTrackCard(
          title: 'Mask · ${mask.name} · ${track.property}',
          track: track,
          maskId: mask.id,
        ));
      }
    }
    for (final bus in _controller.document.audioBuses) {
      for (final track in bus.keyframeTracks) {
        cards.add(_buildUnifiedTrackCard(
          title: 'Audio Bus · ${bus.name} · ${track.property}',
          track: track,
          busId: bus.id,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cards,
    );
  }

  Widget _buildUnifiedTrackCard({
    required String title,
    required KeyframeTrack track,
    String? effectId,
    String? maskId,
    String? busId,
  }) {
    final frames = [...track.keyframes]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final first = frames.first;
    final active = frames.firstWhere(
      (frame) => frame.timeMs == _controller.document.playheadMs,
      orElse: () => first,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${frames.length} keys',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF9AA8BD),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Open keyframe in timeline',
                  onPressed: () => _controller.setPlayhead(active.timeMs),
                  icon: const Icon(Icons.my_location, size: 15),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Edit cubic Bezier graph',
                  onPressed: () => _editBezierCurve(
                    track.property,
                    active.bezier,
                    effectId: effectId,
                    maskId: maskId,
                    busId: busId,
                    timeMs: active.timeMs,
                  ),
                  icon: const Icon(Icons.timeline, size: 16),
                ),
              ],
            ),
            Row(
              children: [
                const Text(
                  'Interpolation',
                  style: TextStyle(fontSize: 9, color: Color(0xFF9AA8BD)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<Interpolation>(
                    isExpanded: true,
                    value: active.interpolation,
                    underline: const SizedBox.shrink(),
                    items: Interpolation.values
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value.name,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      if (maskId != null) {
                        _controller.setMaskInterpolation(
                          maskId,
                          track.property,
                          value,
                          timeMs: active.timeMs,
                        );
                      } else if (busId != null) {
                        _controller.setAudioBusInterpolation(
                          busId,
                          track.property,
                          value,
                          timeMs: active.timeMs,
                        );
                      } else {
                        _controller.setInterpolation(
                          track.property,
                          value,
                          effectId: effectId,
                          timeMs: active.timeMs,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativeEffectParameterControl(
    EffectInstance effect,
    Map<String, Object?> parameter,
  ) {
    final matchName = parameter['matchName']?.toString() ?? '';
    final label = parameter['displayName']?.toString() ??
        parameter['name']?.toString() ?? matchName;
    final value = parameter['value'];
    final rawPath = parameter['path'];
    final parameterPath = rawPath is List
        ? rawPath.map((part) => part.toString()).toList()
        : null;
    void update(Object? next) => _controller.setNativeEffectParameter(
      effect.id, matchName, next, parameterPath: parameterPath,
    );

    if (matchName.isEmpty) return const SizedBox.shrink();
    final rawFrames = parameter['keyframes'];
    final keyframeCount = rawFrames is List ? rawFrames.length : 0;
    final keyframeEditor = rawFrames is List && rawFrames.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(height: 10),
              Text('ANIMATED VALUES · ' + keyframeCount.toString() + ' KEYFRAME(S)',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  color: Color(0xFF91A6C4))),
              for (var i = 0; i < rawFrames.length && i < 32; i++)
                if (rawFrames[i] is Map)
                  _buildNativeParameterKeyframeRow(
                    effect: effect,
                    parameterMatchName: matchName,
                    parameterPath: parameterPath,
                    frame: Map<String, Object?>.from(rawFrames[i] as Map),
                  ),
              if (rawFrames.length > 32)
                Text('+ ' + (rawFrames.length - 32).toString() + ' more keyframes retained',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF91A6C4))),
            ],
          )
        : const SizedBox.shrink();
    Widget withFrames(Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [child, keyframeEditor],
    );

    if (value is Map && value['kind'] == 'mogrtText') {
      final data = Map<String, Object?>.from(value);
      final uniform = data['uniformStyling'] == true;
      return withFrames(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.title, size: 14),
            const SizedBox(width: 5),
            Expanded(child: Text('MOGRT SOURCE TEXT · ' + label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
            const Text('EDITABLE', style: TextStyle(fontSize: 8, color: Color(0xFF79C8B0))),
          ]),
          const SizedBox(height: 5),
          TextFormField(
            key: ValueKey<String>(effect.id + matchName + 'mogrt-text'),
            initialValue: data['text']?.toString() ?? '',
            minLines: 1, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Text content', isDense: true),
            onFieldSubmitted: (next) => update({...data, 'text': next}),
          ),
          if (data['fontNameEditable'] == true)
            TextFormField(
              key: ValueKey<String>(effect.id + matchName + 'mogrt-font'),
              initialValue: data['fontName']?.toString() ?? '',
              decoration: const InputDecoration(labelText: 'Font family', isDense: true),
              onFieldSubmitted: (next) => update({...data, 'fontName': next}),
            ),
          if (data['fontSizeEditable'] == true)
            TextFormField(
              key: ValueKey<String>(effect.id + matchName + 'mogrt-size'),
              initialValue: data['fontSize']?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Font size', isDense: true),
              onFieldSubmitted: (raw) {
                final next = double.tryParse(raw);
                if (next != null && next > 0 && next.isFinite) {
                  update({...data, 'fontSize': next});
                }
              },
            ),
          if (data['fauxStylesEditable'] == true && uniform)
            for (final setting in const [
              ('allCaps', 'All caps'), ('fauxBold', 'Bold'),
              ('fauxItalic', 'Italic'), ('smallCaps', 'Small caps'),
            ])
              SwitchListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                title: Text(setting.$2, style: const TextStyle(fontSize: 10)),
                value: data[setting.$1] == true,
                onChanged: (next) => update({...data, setting.$1: next}),
              ),
          if (!uniform)
            const Text('Mixed character styling is retained; per-run editing depends on the MOGRT author.',
              style: TextStyle(fontSize: 9, color: Color(0xFF91A6C4))),
        ],
      ));
    }
    if (value is Map && value['kind'] == 'mogrtComment') {
      return withFrames(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(label + ': ' + (value['text']?.toString() ?? '') + ' · Read-only MOGRT comment',
          style: const TextStyle(fontSize: 9, color: Color(0xFF91A6C4))),
      ));
    }
    if (value is Map && value['kind'] == 'color') {
      final data = Map<String, Object?>.from(value);
      return withFrames(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label + ' · RGBA', style: const TextStyle(fontSize: 10)),
          Wrap(spacing: 6, children: [
            for (final channel in const [
              ('red', 'R'), ('green', 'G'), ('blue', 'B'), ('alpha', 'A'),
            ])
              SizedBox(width: 66, height: 38, child: TextFormField(
                key: ValueKey<String>(effect.id + matchName + channel.$1),
                initialValue: ((data[channel.$1] as num?) ?? 1).toStringAsFixed(3),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: channel.$2, isDense: true),
                onFieldSubmitted: (raw) {
                  final parsed = double.tryParse(raw);
                  if (parsed != null && parsed.isFinite) {
                    update({...data, channel.$1: parsed.clamp(0, 1).toDouble()});
                  }
                },
              )),
          ]),
        ],
      ));
    }
    if (value is Map && value['kind'] == 'point') {
      final data = Map<String, Object?>.from(value);
      return withFrames(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label + ' · Point', style: const TextStyle(fontSize: 10)),
          Wrap(spacing: 6, children: [
            for (final axis in const [('x', 'X'), ('y', 'Y')])
              SizedBox(width: 76, height: 34, child: TextFormField(
                key: ValueKey<String>(effect.id + matchName + axis.$1),
                initialValue: ((data[axis.$1] as num?) ?? 0).toStringAsFixed(3),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: axis.$2, isDense: true),
                onFieldSubmitted: (raw) {
                  final parsed = double.tryParse(raw);
                  if (parsed != null && parsed.isFinite) update({...data, axis.$1: parsed});
                },
              )),
          ]),
        ],
      ));
    }
    if (value is bool) {
      return withFrames(SwitchListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 10)),
        value: value, onChanged: update,
      ));
    }
    final options = parameter['options'];
    if (options is List && options.isNotEmpty &&
        options.every((entry) => entry is String || entry is num || entry is bool) &&
        options.contains(value)) {
      return withFrames(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DropdownButtonFormField<Object?>(
          initialValue: value, isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: options.map((option) => DropdownMenuItem<Object?>(
            value: option,
            child: Text(option.toString(), overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10)),
          )).toList(),
          onChanged: (next) { if (next != null) update(next); },
        ),
      ));
    }
    if (value is num) {
      final min = (parameter['minValue'] as num?)?.toDouble();
      final max = (parameter['maxValue'] as num?)?.toDouble();
      if (min != null && max != null && max > min && min.isFinite && max.isFinite) {
        final safe = value.toDouble().clamp(min, max).toDouble();
        return withFrames(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label + '  ' + safe.toStringAsFixed(2) +
              (parameter['unitsText'] == null ? '' : ' ' + parameter['unitsText'].toString()),
              style: const TextStyle(fontSize: 10)),
            Slider(min: min, max: max, value: safe, onChanged: update),
          ],
        ));
      }
      return withFrames(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontSize: 10)),
          SizedBox(height: 34, child: TextFormField(
            key: ValueKey<String>(effect.id + matchName + value.toString()),
            initialValue: value.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
            onFieldSubmitted: (raw) {
              final parsed = double.tryParse(raw);
              if (parsed != null && parsed.isFinite) update(parsed);
            },
          )),
        ],
      ));
    }
    if (value is List && value.isNotEmpty && value.every((entry) => entry is num)) {
      final values = value.map((entry) => (entry as num).toDouble()).toList();
      return withFrames(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label + ' · ' + values.length.toString() + ' channels',
            style: const TextStyle(fontSize: 10)),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (var index = 0; index < values.length; index++)
              SizedBox(width: 76, height: 34, child: TextFormField(
                key: ValueKey<String>(effect.id + matchName + index.toString() + values[index].toString()),
                initialValue: values[index].toStringAsFixed(3),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: ['X', 'Y', 'Z', 'W'][index.clamp(0, 3).toInt()],
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                ),
                onFieldSubmitted: (raw) {
                  final parsed = double.tryParse(raw);
                  if (parsed == null || !parsed.isFinite) return;
                  final copy = [...values]..[index] = parsed;
                  update(copy);
                },
              )),
          ]),
        ],
      ));
    }
    return withFrames(Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(label + ': ' + (value?.toString() ?? 'Unsupported parameter type'),
        style: const TextStyle(fontSize: 9, color: Color(0xFF9DABC3))),
    ));
  }

  Widget _buildNativeParameterKeyframeRow({
    required EffectInstance effect,
    required String parameterMatchName,
    required List<String>? parameterPath,
    required Map<String, Object?> frame,
  }) {
    final time = (frame['timeSeconds'] as num?)?.toDouble();
    if (time == null || !time.isFinite || time < 0) return const SizedBox.shrink();
    final frameValue = frame['value'];
    const curves = ['linear', 'bezier', 'hold'];
    final rawCurve = frame['interpolation']?.toString().toLowerCase();
    final selectedCurve = curves.contains(rawCurve) ? rawCurve! : 'linear';
    Widget editor = Expanded(
      child: Text(frameValue?.toString() ?? 'Unsupported value',
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 9, color: Color(0xFF9DABC3))),
    );
    if (frameValue is num || frameValue is String ||
        (frameValue is Map && frameValue['kind'] == 'mogrtText')) {
      final initial = frameValue is Map
          ? frameValue['text']?.toString() ?? ''
          : frameValue?.toString() ?? '';
      editor = Expanded(child: SizedBox(height: 32, child: TextFormField(
        key: ValueKey<String>(effect.id + parameterMatchName + time.toString()),
        initialValue: initial,
        keyboardType: frameValue is num
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: const InputDecoration(isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
        onFieldSubmitted: (raw) {
          Object? next = raw;
          if (frameValue is num) {
            final parsed = double.tryParse(raw);
            if (parsed == null || !parsed.isFinite) return;
            next = parsed;
          } else if (frameValue is Map) {
            next = {...Map<String, Object?>.from(frameValue), 'text': raw};
          }
          _controller.setNativeEffectParameterKeyframe(
            effect.id, parameterMatchName, time, next, parameterPath: parameterPath,
          );
        },
      )));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 48, child: Text(time.toStringAsFixed(2) + 's',
          style: const TextStyle(fontSize: 9, color: Color(0xFF91A6C4)))),
        editor,
        const SizedBox(width: 4),
        SizedBox(width: 84, child: DropdownButtonFormField<String>(
          initialValue: selectedCurve,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 3, vertical: 2)),
          items: curves.map((curve) => DropdownMenuItem<String>(
            value: curve, child: Text(curve.toUpperCase(), style: const TextStyle(fontSize: 8)),
          )).toList(),
          onChanged: (next) {
            if (next == null) return;
            _controller.setNativeEffectParameterKeyframe(
              effect.id, parameterMatchName, time, frameValue,
              interpolation: next, parameterPath: parameterPath,
            );
          },
        )),
      ]),
    );
  }

  Widget _buildEffectsPanel(CompositionLayer layer) {
    final filtered = EffectCatalog.allEffects.where((effect) {
      final categoryMatches = _effectCategory == 'All' || effect.category == _effectCategory;
      final query = _effectSearch.trim().toLowerCase();
      final searchMatches = query.isEmpty ||
          (effect.name + ' ' + effect.category + ' ' + effect.description)
              .toLowerCase().contains(query);
      return categoryMatches && searchMatches;
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('EFFECT LIBRARY', Icons.auto_awesome),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportMotionPreset(layer),
                icon: const Icon(Icons.file_download_outlined, size: 15),
                label: const Text('EXPORT PRESET'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importMotionPreset,
                icon: const Icon(Icons.file_upload_outlined, size: 15),
                label: const Text('IMPORT PRESET'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildMotionBroPackBrowser(),
        const Divider(height: 16),
        PopupMenuButton<String>(
          tooltip: 'Apply an editable motion preset at the playhead',
          onSelected: _controller.applyMotionPreset,
          itemBuilder: (_) => MotionPresetCatalog.all.map((preset) =>
            PopupMenuItem<String>(
              value: preset.id,
              child: SizedBox(
                width: 230,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(preset.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    Text(preset.category + ' · ' + preset.description,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: Color(0xFF98A7C0))),
                  ],
                ),
              ),
            )).toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_motion, size: 16),
                const SizedBox(width: 7),
                Text('BROWSE ' + MotionPresetCatalog.all.length.toString() + ' MOTION PRESETS'),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more, size: 16),
              ],
            ),
          ),
        ),
        TextField(
          onChanged: (value) => setState(() => _effectSearch = value),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 17),
            hintText: 'Search native effects…',
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _effectCategory,
          items: ['All', ...EffectCatalog.categories]
              .map((category) => DropdownMenuItem(value: category, child: Text(category)))
              .toList(),
          onChanged: (value) => setState(() => _effectCategory = value ?? 'All'),
        ),
        const SizedBox(height: 8),
        for (final effect in filtered)
          EffectPreviewTile(
            effect: effect,
            onApply: () => _controller.addEffect(effect.id),
          ),
        const Divider(),
        _panelHeader('APPLIED EFFECTS', Icons.tune),
        if (layer.effects.isEmpty)
          const Text('No effects added to this layer.', style: TextStyle(fontSize: 10))
        else
          for (final effect in layer.effects)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(effect.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                        Switch(
                          value: effect.enabled,
                          onChanged: (value) => _controller.setEffectEnabled(effect.id, value),
                        ),
                      ],
                    ),
                    if (effect.nativeDescriptor.isNotEmpty) ...[
                      Text(
                        'NATIVE · ' +
                            (effect.nativeDescriptor['hostApp']?.toString() ?? 'Adobe host') +
                            ' · ' +
                            (effect.nativeDescriptor['matchName']?.toString() ?? ''),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF9DABC3),
                        ),
                      ),
                      for (final rawParameter in
                          (effect.nativeDescriptor['parameters'] as List? ?? const []))
                        if (rawParameter is Map)
                          _buildNativeEffectParameterControl(
                            effect,
                            Map<String, Object?>.from(rawParameter),
                          ),
                    ] else if (effect.effectId == 'color_grade')
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Edit Lift, Gamma, Gain, Offset and primary controls in the Color panel.',
                          style: TextStyle(fontSize: 10, color: Color(0xFF9DABC3)),
                        ),
                      )
                    else
                      for (final parameter in EffectCatalog.find(effect.effectId)?.parameters ?? const [])
                        Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${parameter.label}  ${effect.parameterAt(parameter.id, _controller.document.playheadMs, fallback: parameter.defaultValue).toStringAsFixed(2)}${parameter.unit}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Animate this effect parameter',
                                onPressed: () => _controller.addEffectKeyframe(effect.id, parameter.id),
                                icon: Icon(
                                  Icons.diamond,
                                  size: 15,
                                  color: effect.keyframeTracks.any((track) => track.property == parameter.id)
                                      ? const Color(0xFFB8A4FF)
                                      : const Color(0xFF8290A8),
                                ),
                              ),
                              if (effect.keyframeTracks.any((track) =>
                                  track.property == parameter.id))
                                PopupMenuButton<Interpolation>(
                                  tooltip: 'Set effect keyframe interpolation',
                                  icon: const Icon(Icons.linear_scale, size: 15),
                                  onSelected: (value) => _controller.setInterpolation(
                                    parameter.id,
                                    value,
                                    effectId: effect.id,
                                  ),
                                  itemBuilder: (_) => Interpolation.values
                                      .map((value) => PopupMenuItem(
                                            value: value,
                                            child: Text(value.name),
                                          ))
                                      .toList(),
                                ),
                            ],
                          ),
                          Slider(
                            min: parameter.min,
                            max: parameter.max,
                            value: effect.parameterAt(
                              parameter.id,
                              _controller.document.playheadMs,
                              fallback: parameter.defaultValue,
                            ).clamp(parameter.min, parameter.max).toDouble(),
                            onChanged: (value) => _controller.setEffectParameter(
                              effect.id,
                              parameter.id,
                              value,
                              keyframe: effect.keyframeTracks.any((track) => track.property == parameter.id),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }


  Future<void> _importColorLut() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['cube'],
      );
      if (picked == null) return;
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw StateError('The selected file has no readable local path.');
      }
      final source = File(sourcePath);
      final info = CubeLutValidator.parse(await source.readAsString());
      final documents = await getApplicationDocumentsDirectory();
      final lutDirectory = Directory(
        documents.path + Platform.pathSeparator +
            'DepthVibe' + Platform.pathSeparator + 'LUTs',
      );
      await lutDirectory.create(recursive: true);
      final safeName = picked.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final target = File(
        lutDirectory.path + Platform.pathSeparator +
            DateTime.now().millisecondsSinceEpoch.toString() + '_' + safeName,
      );
      final imported = await source.copy(target.path);

      var effect = _selected?.effects
          .where((item) => item.effectId == 'color_lut')
          .firstOrNull;
      if (effect == null) {
        _controller.addEffect('color_lut');
        effect = _selected?.effects
            .where((item) => item.effectId == 'color_lut')
            .lastOrNull;
      }
      if (effect == null) {
        throw StateError('Could not attach the LUT to the selected layer.');
      }
      _controller.setEffectAssetUri(effect.id, imported.path);
      if (mounted) {
        setState(() {
          _notice = 'Imported ' + info.title + ' · ' +
              info.size.toString() + '³ LUT · ' +
              info.entryCount.toString() + ' samples';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = '3D LUT import failed: ' + error.toString());
      }
    }
  }

  Future<void> _saveCompositionProject() async {
    if (_projectBusy || _rendering) return;
    setState(() {
      _projectBusy = true;
      _notice = 'Saving project and creating a version checkpoint…';
    });
    try {
      final document = _controller.document;
      final revision = _documentRevision;
      File output;
      if (_currentProjectFile != null) {
        output = _currentProjectFile!;
      } else {
        final documents = await getApplicationDocumentsDirectory();
        Directory targetDirectory;
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          final selectedDirectory = await FilePicker.pickDirectory();
          targetDirectory = selectedDirectory == null
              ? Directory(
                  documents.path + Platform.pathSeparator +
                      'DepthVibe' + Platform.pathSeparator +
                      'Projects' + Platform.pathSeparator + 'Exports',
                )
              : Directory(selectedDirectory.toFilePath());
        } else {
          targetDirectory = Directory(
            documents.path + Platform.pathSeparator +
                'DepthVibe' + Platform.pathSeparator +
                'Projects' + Platform.pathSeparator + 'Exports',
          );
        }
        final safeName = document.name
            .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
            .replaceAll(RegExp(r'\s+'), '_');
        final fileName = (safeName.isEmpty ? 'Untitled_Composition' : safeName) +
            '.dvproj';
        output = File(
          targetDirectory.path + Platform.pathSeparator + fileName,
        );
      }

      final result = await _projectService.exportVersionedProject(
        document,
        outputFile: output,
      );
      _currentProjectFile = output;
      var shared = false;
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
        try {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(result.file.path)],
              text: 'DepthVibe composition project',
            ),
          );
          shared = true;
        } catch (_) {
          // The package remains saved in the app's Projects folder.
        }
      }

      if (revision == _documentRevision) {
        final recovery = await _recoveryDirectory();
        await _recoveryService.clear(recoveryDirectory: recovery);
        _recoveryDirty = false;
        _autosaveStatus = 'Project saved';
      }
      if (!mounted) return;
      setState(() {
        final base = 'Project saved · ' +
            result.embeddedAssetCount.toString() + ' assets embedded.' +
            (result.assetCreditCount == 0
                ? ''
                : ' ' + result.embeddedLicenseFileCount.toString() +
                    ' licence files from ' + result.assetCreditCount.toString() +
                    ' asset packs included.') +
            (result.missingLicensePacks.isEmpty
                ? ''
                : ' Licence notices missing for: ' +
                    result.missingLicensePacks.join(', ') + '.') +
            ' Version history keeps up to ' +
            CompositionProjectService.maxVersionHistory.toString() +
            ' earlier saves.';
        final destination = shared
            ? ' Copied through the share sheet.'
            : ' File: ' + output.path;
        _notice = result.missingAssetPaths.isEmpty
            ? base + destination
            : base + ' ' + result.missingAssetPaths.length.toString() +
                ' linked files were missing and remain external.' + destination;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Project save failed: ' + error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _projectBusy = false);
        if (_recoveryDirty) unawaited(_autosaveIfNeeded());
      }
    }
  }

  Future<void> _openCompositionProject() async {
    if (_projectBusy || _rendering) return;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['dvproj'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw StateError('The selected project has no readable local path.');
      }
      if (!mounted) return;
      setState(() {
        _projectBusy = true;
        _notice = 'Verifying project archive and restoring assets…';
      });

      final documents = await getApplicationDocumentsDirectory();
      final projects = Directory(
        documents.path + Platform.pathSeparator +
            'DepthVibe' + Platform.pathSeparator + 'Projects',
      );
      final imported = await _projectService.importProject(
        File(path),
        projectsDirectory: projects,
      );
      _controller.replaceDocument(imported.document);
      final stableName = picked.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final stableBase = stableName.toLowerCase().endsWith('.dvproj')
          ? stableName.substring(0, stableName.length - 6)
          : stableName;
      final stableFileName =
          (stableBase.isEmpty ? 'Opened_Project' : stableBase) +
          '_local_' + DateTime.now().millisecondsSinceEpoch.toString() +
          '.dvproj';
      final stableCopy = File(
        projects.path + Platform.pathSeparator + stableFileName,
      );
      final sourceProject = File(path);
      if (sourceProject.absolute.path != stableCopy.absolute.path) {
        if (await stableCopy.exists()) await stableCopy.delete();
        await sourceProject.copy(stableCopy.path);
      }
      _currentProjectFile = stableCopy;
      final recoveryDirectory = await _recoveryDirectory();
      await _recoveryService.clear(recoveryDirectory: recoveryDirectory);
      _recoveryDirty = false;
      _autosaveStatus = 'Project opened';
      final missingAssets = await _missingMediaPaths();
      if (!mounted) return;
      setState(() {
        _notice = 'Opened "' + imported.document.name + '" · ' +
            imported.document.layers.length.toString() + ' layers · ' +
            imported.extractedAssetCount.toString() + ' restored media assets.' +
            (imported.assetCredits.isEmpty
                ? ''
                : ' ' + imported.licenseFileCount.toString() +
                    ' licence files from ' + imported.assetCredits.length.toString() +
                    ' asset packs restored.') +
            (missingAssets.isEmpty
                ? ''
                : ' ' + missingAssets.length.toString() +
                    ' external media references need relinking.');
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Project open failed: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _projectBusy = false);
    }
  }

  Future<void> _exportColorGradePreset(CompositionLayer layer) async {
    try {
      var preset = ColorGradePreset.fromLayer(
        layer,
        outputProfile: _controller.document.colorOutputProfile,
        name: layer.name,
      );
      var lutWasEmbedded = false;
      final lutPath = layer.effects
          .where((effect) => effect.effectId == 'color_lut')
          .firstOrNull
          ?.assetUri;
      if (preset.lut != null && lutPath != null) {
        final lutFile = File(lutPath);
        if (await lutFile.exists()) {
          final lutContent = await lutFile.readAsString();
          CubeLutValidator.parse(lutContent);
          preset = preset.withLutContent(lutContent);
          lutWasEmbedded = true;
        }
      }

      final safeName = preset.name
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final temporary = await getTemporaryDirectory();
      final output = File(
        temporary.path + Platform.pathSeparator +
            'DepthVibe_' +
            (safeName.isEmpty ? 'Color_Grade' : safeName) +
            '_' + DateTime.now().millisecondsSinceEpoch.toString() +
            '.dvgrade',
      );
      await output.writeAsString(preset.encode(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(output.path)],
          text: 'DepthVibe color grade preset',
        ),
      );
      if (!mounted) return;
      setState(() {
        _notice = preset.lut != null && !lutWasEmbedded
            ? 'Preset exported. Its LUT file was not available to embed; share the .cube file separately.'
            : 'Color preset exported with animated keyframes and LUT data.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Color preset export failed: $error');
      }
    }
  }

  Future<void> _importColorGradePreset() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['dvgrade', 'json'],
      );
      if (picked == null) return;
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw StateError('The selected preset has no readable local path.');
      }
      final preset = ColorGradePreset.decode(
        await File(sourcePath).readAsString(),
      );
      if (_selected == null) {
        throw StateError('Select a layer before applying a color preset.');
      }

      String? importedLutPath;
      final lutContent = preset.lut?.content;
      if (lutContent != null) {
        final info = CubeLutValidator.parse(lutContent);
        final documents = await getApplicationDocumentsDirectory();
        final lutDirectory = Directory(
          documents.path + Platform.pathSeparator +
              'DepthVibe' + Platform.pathSeparator + 'LUTs',
        );
        await lutDirectory.create(recursive: true);
        final fileName = (preset.lut?.fileName ?? 'preset.cube')
            .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final safeName = fileName.isEmpty ? 'preset.cube' : fileName;
        final target = File(
          lutDirectory.path + Platform.pathSeparator +
              DateTime.now().millisecondsSinceEpoch.toString() +
              '_' + safeName,
        );
        importedLutPath = (await target.writeAsString(
          lutContent,
          flush: true,
        )).path;
        _notice = 'Validated ${info.size}³ LUT · ${info.entryCount} samples';
      }

      _controller.applyColorGradePreset(
        preset,
        lutAssetUri: importedLutPath,
      );
      if (!mounted) return;
      setState(() {
        _notice = preset.lut != null && importedLutPath == null
            ? 'Applied "${preset.name}". Re-import its missing .cube LUT to render that effect.'
            : 'Applied color preset "${preset.name}" to ${_selected!.name}.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Color preset import failed: $error');
      }
    }
  }

  Future<void> _exportMotionPreset(CompositionLayer layer) async {
    try {
      final source = MotionPresetPackage.encode(layer, name: layer.name);
      final temporary = await getTemporaryDirectory();
      final safeName = layer.name
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final output = File(
        temporary.path + Platform.pathSeparator +
            'DepthVibe_' + (safeName.isEmpty ? 'Motion' : safeName) + '_' +
            DateTime.now().microsecondsSinceEpoch.toString() + '.dvmpreset',
      );
      await output.writeAsString(source, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(output.path)],
        text: 'DepthVibe editable motion/effect preset',
      ));
      if (mounted) setState(() => _notice =
          'Preset exported with editable keyframes, effect settings and native Adobe descriptors.');
    } catch (error) {
      if (mounted) setState(() => _notice = 'Preset export failed: $error');
    }
  }

  Future<void> _importMotionPreset() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['dvmpreset'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw StateError('The selected preset has no readable local path.');
      }
      final presetLayer = MotionPresetPackage.decode(
        await File(path).readAsString(),
      );
      if (_selected == null) {
        throw StateError('Select a target layer before applying a preset.');
      }
      _controller.applyLayerPreset(presetLayer);
      if (mounted) {
        setState(() => _notice =
            'Imported "' + presetLayer.name + '" with ' +
            presetLayer.effects.length.toString() + ' effect(s) and ' +
            presetLayer.keyframeTracks.length.toString() + ' animation track(s).');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Preset import failed: $error');
    }
  }

  Widget _buildColorScopes(
    CompositionLayer layer,
    EffectInstance? grade,
    int timeMs,
  ) {
    return FutureBuilder<img.Image?>(
      future: _scopeImageFor(
        layer,
        timeMs,
        _controller.document.frameRate,
      ),
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panelHeader('VIDEO SCOPES', Icons.multiline_chart),
              Text(
                snapshot.connectionState == ConnectionState.waiting
                    ? 'Reading the current frame for scopes…'
                    : 'Select an active video or image layer to inspect its pixel scopes.',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF9BAAC1),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panelHeader('VIDEO SCOPES', Icons.multiline_chart),
            ColorScopesView(
              image: image,
              mode: ColorScopeMode.waveform,
              grade: grade,
              timeMs: timeMs,
            ),
            const SizedBox(height: 7),
            ColorScopesView(
              image: image,
              mode: ColorScopeMode.rgbParade,
              grade: grade,
              timeMs: timeMs,
            ),
            const SizedBox(height: 7),
            ColorScopesView(
              image: image,
              mode: ColorScopeMode.vectorscope,
              grade: grade,
              timeMs: timeMs,
            ),
            const SizedBox(height: 5),
            const Text(
              'Scopes use the current decoded frame and the primary-wheel preview approximation. Curves and LUT data are not yet included in the scope calculations.',
              style: TextStyle(fontSize: 9, color: Color(0xFF8190A8)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColorPanel(CompositionLayer layer) {
    final grade = layer.effects
        .where((effect) => effect.effectId == 'color_grade')
        .firstOrNull;
    final curves = layer.effects
        .where((effect) => effect.effectId == 'color_curves')
        .firstOrNull;
    final lut = layer.effects
        .where((effect) => effect.effectId == 'color_lut')
        .firstOrNull;
    final definition = EffectCatalog.find('color_grade')!;
    final playheadMs = _controller.document.playheadMs;
    final outputProfile = _controller.document.colorOutputProfile;

    double value(EffectInstance activeGrade, String id) {
      final parameter = definition.parameters.firstWhere(
        (item) => item.id == id,
      );
      return activeGrade.parameterAt(
        id,
        playheadMs,
        fallback: parameter.defaultValue,
      ).clamp(parameter.min, parameter.max).toDouble();
    }

    Widget gradeSlider({
      required EffectInstance activeGrade,
      required String id,
      required String label,
      required double min,
      required double max,
      required bool keyframeable,
    }) {
      final current = value(activeGrade, id);
      final hasTrack = activeGrade.keyframeTracks.any(
        (track) => track.property == id && track.enabled,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  current.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFB9C6D9),
                  ),
                ),
                if (keyframeable)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Add ' + label + ' keyframe',
                    onPressed: () => _controller.addEffectKeyframe(
                      activeGrade.id,
                      id,
                    ),
                    icon: Icon(
                      Icons.diamond,
                      size: 15,
                      color: hasTrack
                          ? const Color(0xFFB8A4FF)
                          : const Color(0xFF8290A8),
                    ),
                  ),
              ],
            ),
            Slider(
              min: min,
              max: max,
              value: current,
              onChanged: (nextValue) => _controller.setEffectParameter(
                activeGrade.id,
                id,
                nextValue,
                keyframe: keyframeable && hasTrack,
              ),
            ),
          ],
        ),
      );
    }

    Widget wheelCard(
      EffectInstance activeGrade,
      String title,
      String prefix,
    ) {
      final ids = [
        prefix + '_r',
        prefix + '_g',
        prefix + '_b',
      ];
      final hasWheelTrack = activeGrade.keyframeTracks.any(
        (track) => ids.contains(track.property) && track.enabled,
      );
      return SizedBox(
        width: 142,
        child: Card(
          color: const Color(0xFF182231),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: 'Animate ' + title + ' wheel',
                      onPressed: () {
                        for (final id in ids) {
                          _controller.addEffectKeyframe(activeGrade.id, id);
                        }
                      },
                      icon: Icon(
                        Icons.diamond,
                        size: 14,
                        color: hasWheelTrack
                            ? const Color(0xFFB8A4FF)
                            : const Color(0xFF8290A8),
                      ),
                    ),
                  ],
                ),
                ColorWheelControl(
                  diameter: 112,
                  red: value(activeGrade, prefix + '_r'),
                  green: value(activeGrade, prefix + '_g'),
                  blue: value(activeGrade, prefix + '_b'),
                  onChanged: (wheel) {
                    _controller.setEffectParameter(
                      activeGrade.id,
                      prefix + '_r',
                      wheel.red,
                      keyframe: hasWheelTrack,
                    );
                    _controller.setEffectParameter(
                      activeGrade.id,
                      prefix + '_g',
                      wheel.green,
                      keyframe: hasWheelTrack,
                    );
                    _controller.setEffectParameter(
                      activeGrade.id,
                      prefix + '_b',
                      wheel.blue,
                      keyframe: hasWheelTrack,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget primaryGradeControls(EffectInstance activeGrade) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PRIMARY WHEELS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
              Switch(
                value: activeGrade.enabled,
                onChanged: (enabled) => _controller.setEffectEnabled(
                  activeGrade.id,
                  enabled,
                ),
              ),
            ],
          ),
          const Text(
            'Lift · Gamma · Gain · Offset — drag a wheel to shift RGB balance. The diamond creates keyframes for all three channels.',
            style: TextStyle(fontSize: 10, color: Color(0xFF9DABC3)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              wheelCard(activeGrade, 'Lift', 'lift'),
              wheelCard(activeGrade, 'Gamma', 'gamma'),
              wheelCard(activeGrade, 'Gain', 'gain'),
              wheelCard(activeGrade, 'Offset', 'offset'),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                for (final prefix in const [
                  'lift',
                  'gamma',
                  'gain',
                  'offset',
                ]) {
                  for (final channel in const ['r', 'g', 'b']) {
                    _controller.setEffectParameter(
                      activeGrade.id,
                      prefix + '_' + channel,
                      0,
                    );
                  }
                }
                _controller.setEffectParameter(activeGrade.id, 'temperature', 0);
                _controller.setEffectParameter(activeGrade.id, 'tint', 0);
              },
              icon: const Icon(Icons.restart_alt, size: 15),
              label: const Text(
                'Reset Wheels',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
          const Divider(color: Color(0xFF29354A)),
          _panelHeader('PRIMARY CONTROLS', Icons.tune),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'contrast',
            label: 'Contrast',
            min: 0,
            max: 3,
            keyframeable: true,
          ),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'brightness',
            label: 'Exposure / Brightness',
            min: -1,
            max: 1,
            keyframeable: true,
          ),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'master_gamma',
            label: 'Master Gamma',
            min: 0.1,
            max: 3,
            keyframeable: true,
          ),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'saturation',
            label: 'Saturation',
            min: 0,
            max: 3,
            keyframeable: true,
          ),
          const Divider(color: Color(0xFF29354A)),
          _panelHeader('WHITE BALANCE', Icons.wb_sunny_outlined),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'temperature',
            label: 'Temperature · Cool / Warm',
            min: -1,
            max: 1,
            keyframeable: false,
          ),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'tint',
            label: 'Tint · Green / Magenta',
            min: -1,
            max: 1,
            keyframeable: false,
          ),
        ],
      );
    }

    final curveValues = [
      for (var index = 0; index < 5; index++)
        curves?.parameters[_curveChannel + '_' + index.toString()] ??
            index * 0.25,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('COLOR PAGE · PRIMARY & SECONDARY', Icons.color_lens),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportColorGradePreset(layer),
                icon: const Icon(Icons.ios_share, size: 15),
                label: const Text('SAVE PRESET'),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importColorGradePreset,
                icon: const Icon(Icons.file_open_outlined, size: 15),
                label: const Text('LOAD PRESET'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (grade == null)
          FilledButton.icon(
            onPressed: () => _controller.addEffect('color_grade'),
            icon: const Icon(Icons.add),
            label: const Text('ADD PRIMARY COLOR GRADE'),
          )
        else
          primaryGradeControls(grade),
        const Divider(color: Color(0xFF29354A)),
        _panelHeader('CUSTOM RGB CURVES', Icons.show_chart),
        if (curves == null)
          OutlinedButton.icon(
            onPressed: () => _controller.addEffect('color_curves'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('ADD MASTER / RGB CURVES'),
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: _curveChannel,
            decoration: const InputDecoration(
              labelText: 'Curve channel',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'master', child: Text('Master / Luma')),
              DropdownMenuItem(value: 'red', child: Text('Red')),
              DropdownMenuItem(value: 'green', child: Text('Green')),
              DropdownMenuItem(value: 'blue', child: Text('Blue')),
            ],
            onChanged: (channel) => setState(
              () => _curveChannel = channel ?? 'master',
            ),
          ),
          const SizedBox(height: 8),
          ColorCurveEditor(
            values: curveValues,
            onChanged: (values) {
              for (var index = 0; index < values.length; index++) {
                _controller.setEffectParameter(
                  curves.id,
                  _curveChannel + '_' + index.toString(),
                  values[index],
                );
              }
            },
          ),
          const Text(
            'Curves are compiled into FFmpeg export. They are not yet included in the live preview transform.',
            style: TextStyle(fontSize: 9, color: Color(0xFF8190A8)),
          ),
        ],
        const Divider(color: Color(0xFF29354A)),
        _panelHeader('3D LUT MANAGEMENT', Icons.palette_outlined),
        if (lut?.assetUri != null)
          Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF73D6B2),
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lut!.assetUri!.split(Platform.pathSeparator).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              Switch(
                value: lut.enabled,
                onChanged: (enabled) => _controller.setEffectEnabled(
                  lut.id,
                  enabled,
                ),
              ),
            ],
          )
        else
          const Text(
            'Import a validated 3D .cube LUT. The table is applied by the native FFmpeg export filter.',
            style: TextStyle(fontSize: 10, color: Color(0xFF9DABC3)),
          ),
        OutlinedButton.icon(
          onPressed: _importColorLut,
          icon: const Icon(Icons.file_upload_outlined, size: 16),
          label: Text(
            lut?.assetUri == null ? 'IMPORT .CUBE LUT' : 'REPLACE LUT',
          ),
        ),
        if (lut?.assetUri != null)
          DropdownButtonFormField<String>(
            initialValue: lut!.assetInterpolation,
            decoration: const InputDecoration(
              labelText: 'LUT interpolation',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'nearest', child: Text('Nearest · fastest')),
              DropdownMenuItem(value: 'trilinear', child: Text('Trilinear · smooth')),
              DropdownMenuItem(value: 'tetrahedral', child: Text('Tetrahedral · high quality')),
              DropdownMenuItem(value: 'pyramid', child: Text('Pyramid')),
              DropdownMenuItem(value: 'prism', child: Text('Prism')),
            ],
            onChanged: (mode) {
              if (mode != null) {
                _controller.setEffectAssetInterpolation(lut.id, mode);
              }
            },
          ),
        const Divider(color: Color(0xFF29354A)),
        _panelHeader('HDR COLOR OUTPUT', Icons.hdr_on),
        DropdownButtonFormField<ColorOutputProfile>(
          initialValue: outputProfile,
          decoration: const InputDecoration(
            labelText: 'Composition output profile',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(
              value: ColorOutputProfile.rec709,
              child: Text('SDR · Rec.709 · 8-bit MP4'),
            ),
            DropdownMenuItem(
              value: ColorOutputProfile.hdr10Pq,
              child: Text('HDR10 · BT.2020 · PQ · 10-bit MOV'),
            ),
            DropdownMenuItem(
              value: ColorOutputProfile.hlg,
              child: Text('HLG · BT.2020 · 10-bit MOV'),
            ),
          ],
          onChanged: (profile) {
            if (profile != null) _controller.setColorOutputProfile(profile);
          },
        ),
        const SizedBox(height: 5),
        const Text(
          'HDR modes export a Rec.709-to-BT.2020 PQ/HLG mapped ProRes 422 HQ 10-bit file. This is an SDR-to-HDR mapping, not native scene-referred HDR mastering; source highlight detail and dynamic HDR metadata are not created.',
          style: TextStyle(fontSize: 9, color: Color(0xFFE1C28B)),
        ),
        const Divider(color: Color(0xFF29354A)),
        _buildColorScopes(layer, grade, playheadMs),
      ],
    );
  }


  Widget _buildTransitionBrowser() {
    String categoryFor(TransitionKind kind) {
      final id = kind.name.toLowerCase();
      if (id.contains('fade') || id == 'dissolve') return 'Fade';
      if (id.contains('wipe') || id.contains('diag')) return 'Wipe';
      if (id.contains('slide') || id.contains('cover') ||
          id.contains('reveal') || id.contains('wind') ||
          id.contains('slice') || id.contains('squeeze')) {
        return 'Move';
      }
      if (id.contains('circle') || id.contains('rect') ||
          id.contains('open') || id.contains('close')) {
        return 'Shape';
      }
      return 'Stylize';
    }

    final query = _transitionSearch.trim().toLowerCase();
    final visible = TransitionCatalog.all.where((kind) {
      final name = TransitionCatalog.displayName(kind);
      final matchesCategory = _transitionCategory == 'All' ||
          categoryFor(kind) == _transitionCategory;
      final matchesSearch = query.isEmpty ||
          (name + ' ' + kind.name + ' ' +
              TransitionCatalog.xfadeName(kind)).toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (value) => setState(() => _transitionSearch = value),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 17),
            hintText: 'Search 60+ transitions…',
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            for (final category in const [
              'All', 'Fade', 'Wipe', 'Move', 'Shape', 'Stylize',
            ])
              ChoiceChip(
                label: Text(category, style: const TextStyle(fontSize: 9)),
                selected: _transitionCategory == category,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(
                  () => _transitionCategory = category,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'LIVE TRANSITION PREVIEWS · ' + visible.length.toString(),
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.65,
                  color: Color(0xFF9EACC3),
                ),
              ),
            ),
            const Text(
              'Hover a card to animate',
              style: TextStyle(fontSize: 8, color: Color(0xFF8294AE)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No transitions match this search.',
              style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
            ),
          ),
        for (final kind in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TransitionPreviewTile(
              kind: kind,
              onApply: () => _controller.addTransition(kind),
            ),
          ),
      ],
    );
  }

  Widget _buildTransitionsPanel(CompositionLayer layer) {
    const validator = TransitionFrameValidator();
    final document = _controller.document;
    final report = validator.validate(document);
    final transitions = document.transitions.where(
      (item) => item.fromLayerId == layer.id || item.toLayerId == layer.id,
    ).toList();
    final layers = _controller.document.layers;
    String nameOf(String id) {
      final matches = layers.where((item) => item.id == id);
      return matches.isEmpty ? 'Missing layer' : matches.first.name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('CLIP TRANSITIONS', Icons.auto_awesome_motion),
        _buildTransitionBrowser(),
        const Divider(height: 18),
        PopupMenuButton<TransitionKind>(
          tooltip: 'Add transition to adjacent clip',
          onSelected: _controller.addTransition,
          itemBuilder: (_) => TransitionKind.values
              .map((kind) => PopupMenuItem(value: kind, child: Text(TransitionCatalog.displayName(kind))))
              .toList(),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16),
                SizedBox(width: 6),
                Text('Add transition to adjacent clip'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF141D2B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: report.isValid
                  ? const Color(0xFF35445C)
                  : const Color(0xFF8E6541),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'FRAME VALIDATION · ${document.frameRate.toStringAsFixed(3)} FPS',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  report.isValid
                      ? report.warningCount == 0
                          ? 'All transitions pass timing and clip-range checks.'
                          : '${report.warningCount} frame/range warning(s).'
                      : '${report.errorCount} error(s), ${report.warningCount} warning(s).',
                  style: const TextStyle(fontSize: 10),
                ),
                for (final issue in report.issues.where(
                  (item) => transitions.any(
                    (transition) => transition.id == item.transitionId,
                  ),
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '• ${issue.message}',
                      style: TextStyle(
                        fontSize: 9,
                        color: issue.severity ==
                                TransitionIssueSeverity.error
                            ? const Color(0xFFFFB18C)
                            : const Color(0xFFE5C18C),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (transitions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Select a video/image layer and add a transition. The transition is applied between the selected clip and its adjacent visual layer at the playhead.',
              style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
            ),
          ),
        for (final transition in transitions) ...[
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TransitionKind>(
                  initialValue: transition.kind,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Transition',
                    isDense: true,
                  ),
                  items: TransitionKind.values
                      .map((kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(TransitionCatalog.displayName(kind), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (kind) => _controller.updateTransition(
                    transition.id,
                    kind: kind,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove transition',
                onPressed: () => _controller.removeTransition(transition.id),
                icon: const Icon(Icons.delete_outline, size: 17),
              ),
            ],
          ),
          Text(
            nameOf(transition.fromLayerId) + ' → ' + nameOf(transition.toLayerId),
            style: const TextStyle(fontSize: 10, color: Color(0xFF9BAAC1)),
          ),
          _settingSlider(
            'Duration (ms)',
            transition.durationMs.toDouble(),
            50,
            4000,
            (value) => _controller.updateTransition(
              transition.id,
              durationMs: value.round(),
            ),
          ),
          _settingSlider(
            'Start (ms)',
            transition.startMs.toDouble(),
            0,
            _controller.document.durationMs.toDouble(),
            (value) => _controller.updateTransition(
              transition.id,
              startMs: value.round(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrackingPanel(CompositionLayer layer) {
    if (layer.kind != LayerKind.video || layer.sourceUri == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('MOTION TRACKING', Icons.track_changes),
          const Text(
            'Select a video layer to track a fixed object region and convert its movement into position keyframes.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('MOTION TRACKING', Icons.track_changes),
        const Text(
          'Choose a rectangle around a high-contrast object in the first source frame. Coordinates are source-video pixels.',
          style: TextStyle(fontSize: 10, color: Color(0xFF9BAAC1)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _trackingField('Left (px)', _trackingLeft,
                (value) => setState(() => _trackingLeft = value)),
            _trackingField('Top (px)', _trackingTop,
                (value) => setState(() => _trackingTop = value)),
            _trackingField('Width (px)', _trackingWidth,
                (value) => setState(() => _trackingWidth = value)),
            _trackingField('Height (px)', _trackingHeight,
                (value) => setState(() => _trackingHeight = value)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Match threshold  ' + _trackingThreshold.toStringAsFixed(2),
          style: const TextStyle(fontSize: 10),
        ),
        Slider(
          min: 0.01,
          max: 0.99,
          value: _trackingThreshold,
          onChanged: (value) => setState(() => _trackingThreshold = value),
        ),
        DropdownButtonFormField<bool>(
          initialValue: _stabilizeTracking,
          decoration: const InputDecoration(labelText: 'Tracking action'),
          items: const [
            DropdownMenuItem(value: true, child: Text('Stabilize the object')),
            DropdownMenuItem(value: false, child: Text('Follow the object motion')),
          ],
          onChanged: (value) => setState(
            () => _stabilizeTracking = value ?? true,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _tracking ? null : _runMotionTracking,
          icon: _tracking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.center_focus_strong),
          label: Text(_tracking ? 'TRACKING…' : 'TRACK OBJECT & CREATE KEYFRAMES'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tracker type: template matching at 10 samples/second. It handles translation on a mostly unchanged object; fast scale changes, rotation, occlusion and planar perspective need a stronger optical-flow/planar tracker.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
      ],
    );
  }

  Widget _audioBusAnimatedSlider(
    AudioBus bus,
    String property,
    String label,
    double min,
    double max,
  ) {
    final timeMs = _controller.document.playheadMs;
    final value = bus.valueAt(property, timeMs);
    final tracks = bus.keyframeTracks.where(
      (track) => track.property == property,
    );
    final animated = tracks.isNotEmpty && tracks.first.keyframes.isNotEmpty;
    final hasKey = animated &&
        tracks.first.keyframes.any((frame) => frame.timeMs == timeMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 10)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add bus automation keyframe',
              onPressed: () => _controller.setAudioBusValue(
                bus.id,
                property,
                value,
                keyframe: true,
              ),
              icon: Icon(
                Icons.diamond,
                size: 15,
                color: hasKey
                    ? const Color(0xFFB8A4FF)
                    : animated
                        ? const Color(0xFF8D9AB2)
                        : const Color(0xFF65738A),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                value.toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: (next) => _controller.setAudioBusValue(
            bus.id,
            property,
            next,
            keyframe: animated,
          ),
        ),
      ],
    );
  }

  Widget _buildAudioBusPanel(CompositionLayer? layer) {
    final buses = _controller.document.audioBuses;
    final master = buses.where((bus) => bus.isMaster).firstOrNull;
    final selectedBusId = layer?.audioSettings.busId ??
        master?.id ??
        buses.firstOrNull?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('AUDIO BUS MIXER', Icons.tune),
        const Text(
          'Route audio and video tracks into submix buses. Each bus has independent gain, stereo balance, compression and limiting.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
        if (layer != null &&
            (layer.kind == LayerKind.audio || layer.kind == LayerKind.video)) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: selectedBusId,
            decoration: const InputDecoration(
              labelText: 'Selected track output',
              isDense: true,
            ),
            items: buses
                .map((bus) => DropdownMenuItem(
                      value: bus.id,
                      child: Text(bus.name),
                    ))
                .toList(),
            onChanged: (value) =>
                _controller.assignSelectedAudioBus(value),
          ),
        ],
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () {
            _controller.addAudioBus();
            setState(() => _notice = 'New audio submix bus added');
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('ADD SUBMIX BUS'),
        ),
        const SizedBox(height: 8),
        for (final bus in buses)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        bus.isMaster ? Icons.speaker : Icons.graphic_eq,
                        size: 17,
                        color: bus.isMaster
                            ? const Color(0xFF7EDBCB)
                            : const Color(0xFFB6A5FF),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          bus.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      Switch(
                        value: !bus.muted,
                        onChanged: (value) => _controller.updateAudioBus(
                          bus.copyWith(muted: !value),
                        ),
                      ),
                      if (!bus.isMaster)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Remove bus and route its tracks to Master',
                          onPressed: () => _controller.removeAudioBus(bus.id),
                          icon: const Icon(Icons.delete_outline, size: 17),
                        ),
                    ],
                  ),
                  _audioBusAnimatedSlider(
                    bus,
                    'gainDb',
                    'Bus gain (dB)',
                    -24,
                    12,
                  ),
                  _audioBusAnimatedSlider(
                    bus,
                    'pan',
                    'Bus pan',
                    -1,
                    1,
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Compressor',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: bus.compressorEnabled,
                    onChanged: (value) => _controller.updateAudioBus(
                      bus.copyWith(compressorEnabled: value),
                    ),
                  ),
                  if (bus.compressorEnabled) ...[
                    _settingSlider(
                      'Threshold (dB)',
                      bus.compressorThresholdDb,
                      -48,
                      0,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(compressorThresholdDb: value),
                      ),
                    ),
                    _settingSlider(
                      'Ratio',
                      bus.compressorRatio,
                      1,
                      20,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(compressorRatio: value),
                      ),
                    ),
                    _settingSlider(
                      'Attack (ms)',
                      bus.compressorAttackMs,
                      1,
                      200,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(compressorAttackMs: value),
                      ),
                    ),
                    _settingSlider(
                      'Release (ms)',
                      bus.compressorReleaseMs,
                      10,
                      1000,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(compressorReleaseMs: value),
                      ),
                    ),
                    _settingSlider(
                      'Makeup gain (dB)',
                      bus.makeupGainDb,
                      0,
                      18,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(makeupGainDb: value),
                      ),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Output limiter',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: bus.limiterEnabled,
                    onChanged: (value) => _controller.updateAudioBus(
                      bus.copyWith(limiterEnabled: value),
                    ),
                  ),
                  if (bus.limiterEnabled)
                    _settingSlider(
                      'Ceiling (dBFS)',
                      bus.limiterCeilingDb,
                      -12,
                      0,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(limiterCeilingDb: value),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioPanel(CompositionLayer layer) {
    if (layer.kind != LayerKind.audio && layer.kind != LayerKind.video) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('AUDIO MIXER', Icons.graphic_eq),
          const Text('Select an Audio or Video layer to edit audio gain, pan, fades and ducking.'),
        ],
      );
    }
    final audio = layer.audioSettings;
    final gainTrack = layer.keyframeTracks.where(
      (track) => track.property == 'audio.gainDb',
    );
    final animated = gainTrack.isNotEmpty && gainTrack.first.keyframes.isNotEmpty;
    final gain = animated
        ? gainTrack.first.sample(
            _controller.document.playheadMs,
            fallback: audio.gainDb,
          )
        : audio.gainDb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('AUDIO MIXER', Icons.graphic_eq),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mute this track', style: TextStyle(fontSize: 11)),
          value: audio.muted,
          onChanged: (value) => _controller.setAudioSettings(
            audio.copyWith(muted: value),
          ),
        ),
        Row(
          children: [
            const Expanded(child: Text('Gain (dB)', style: TextStyle(fontSize: 11))),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Keyframe audio gain',
              onPressed: () => _controller.setAudioGain(gain, keyframe: true),
              icon: Icon(
                Icons.diamond,
                size: 16,
                color: animated
                    ? const Color(0xFFB8A4FF)
                    : const Color(0xFF8290A8),
              ),
            ),
            Text(gain.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
          ],
        ),
        Slider(
          min: -60,
          max: 12,
          value: gain.clamp(-60, 12).toDouble(),
          onChanged: (value) => _controller.setAudioGain(
            value,
            keyframe: animated,
          ),
        ),
        Builder(
          builder: (context) {
            final panTrack = layer.keyframeTracks.where(
              (track) => track.property == 'audio.pan',
            );
            final panAnimated = panTrack.isNotEmpty &&
                panTrack.first.keyframes.isNotEmpty;
            final pan = panAnimated
                ? panTrack.first.sample(
                    _controller.document.playheadMs,
                    fallback: audio.pan,
                  )
                : audio.pan;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Pan', style: TextStyle(fontSize: 11)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Add pan automation keyframe',
                      onPressed: () => _controller.setAudioPan(
                        pan,
                        keyframe: true,
                      ),
                      icon: Icon(
                        Icons.diamond,
                        size: 16,
                        color: panAnimated
                            ? const Color(0xFFB8A4FF)
                            : const Color(0xFF8290A8),
                      ),
                    ),
                    Text(
                      pan.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                Slider(
                  min: -1,
                  max: 1,
                  value: pan.clamp(-1, 1).toDouble(),
                  onChanged: (value) => _controller.setAudioPan(
                    value,
                    keyframe: panAnimated,
                  ),
                ),
              ],
            );
          },
        ),
        const Divider(height: 18),
        const Text(
          '3-BAND PARAMETRIC EQ',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        _settingSlider('Low · 120 Hz (dB)', audio.lowEqDb, -12, 12,
            (value) => _controller.setAudioSettings(
              audio.copyWith(lowEqDb: value),
            )),
        _settingSlider('Mid · 1 kHz (dB)', audio.midEqDb, -12, 12,
            (value) => _controller.setAudioSettings(
              audio.copyWith(midEqDb: value),
            )),
        _settingSlider('High · 8 kHz (dB)', audio.highEqDb, -12, 12,
            (value) => _controller.setAudioSettings(
              audio.copyWith(highEqDb: value),
            )),
        _settingSlider('Fade In (ms)', audio.fadeInMs.toDouble(), 0, 5000,
            (value) => _controller.setAudioSettings(
              audio.copyWith(fadeInMs: value.round()),
            )),
        _settingSlider('Fade Out (ms)', audio.fadeOutMs.toDouble(), 0, 5000,
            (value) => _controller.setAudioSettings(
              audio.copyWith(fadeOutMs: value.round()),
            )),
        DropdownButtonFormField<AudioDuckingRole>(
          initialValue: audio.duckingRole,
          decoration: const InputDecoration(labelText: 'Ducking role'),
          items: AudioDuckingRole.values
              .map((role) => DropdownMenuItem(value: role, child: Text(role.name)))
              .toList(),
          onChanged: (value) => _controller.setAudioSettings(
            audio.copyWith(duckingRole: value ?? AudioDuckingRole.none),
          ),
        ),
        if (audio.duckingRole == AudioDuckingRole.background) ...[
          _settingSlider('Ducking threshold', audio.duckingThreshold, 0.001, 0.5,
              (value) => _controller.setAudioSettings(
                audio.copyWith(duckingThreshold: value),
              )),
          _settingSlider('Ducking ratio', audio.duckingRatio, 1, 20,
              (value) => _controller.setAudioSettings(
                audio.copyWith(duckingRatio: value),
              )),
          _settingSlider('Attack (ms)', audio.duckingAttackMs, 1, 200,
              (value) => _controller.setAudioSettings(
                audio.copyWith(duckingAttackMs: value),
              )),
          _settingSlider('Release (ms)', audio.duckingReleaseMs, 10, 1000,
              (value) => _controller.setAudioSettings(
                audio.copyWith(duckingReleaseMs: value),
              )),
        ],
        const Text(
          'Tracks marked Trigger control the ducking of tracks marked Background during the final mix.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
      ],
    );
  }

  Widget _animatedMaskPropertyRow(
    MaskModel mask,
    String label,
    String property,
    double min,
    double max,
  ) {
    final playhead = _controller.document.playheadMs;
    final value = mask.valueAt(property, playhead);
    final tracks = mask.keyframeTracks.where(
      (track) => track.property == property,
    );
    final animated = tracks.isNotEmpty && tracks.first.keyframes.isNotEmpty;
    final hasKeyAtPlayhead = animated &&
        tracks.first.keyframes.any((frame) => frame.timeMs == playhead);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 10)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add mask keyframe at playhead',
              onPressed: () => _controller.setMaskAnimatedValue(
                mask.id,
                property,
                value,
                keyframe: true,
              ),
              icon: Icon(
                Icons.diamond,
                size: 15,
                color: hasKeyAtPlayhead
                    ? const Color(0xFFB8A4FF)
                    : animated
                        ? const Color(0xFF8D9AB2)
                        : const Color(0xFF65738A),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                value.toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: (next) => _controller.setMaskAnimatedValue(
            mask.id,
            property,
            next,
            keyframe: animated,
          ),
        ),
      ],
    );
  }

  Widget _animatedMaskVertexPropertyRow(
    MaskModel mask,
    int vertexIndex,
    String label,
    String component,
    double min,
    double max,
  ) {
    final playhead = _controller.document.playheadMs;
    final property = 'vertex.$vertexIndex.$component';
    final value = mask.vertexValueAt(vertexIndex, component, playhead);
    final tracks = mask.keyframeTracks.where(
      (track) => track.property == property,
    );
    final animated = tracks.isNotEmpty && tracks.first.keyframes.isNotEmpty;
    final hasKeyAtPlayhead = animated &&
        tracks.first.keyframes.any((frame) => frame.timeMs == playhead);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 10)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add vertex keyframe at playhead',
              onPressed: () => _controller.setMaskVertexAnimatedValue(
                mask.id,
                vertexIndex,
                component,
                value,
                keyframe: true,
              ),
              icon: Icon(
                Icons.diamond,
                size: 15,
                color: hasKeyAtPlayhead
                    ? const Color(0xFFB8A4FF)
                    : animated
                        ? const Color(0xFF8D9AB2)
                        : const Color(0xFF65738A),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                value.toStringAsFixed(3),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: (next) => _controller.setMaskVertexAnimatedValue(
            mask.id,
            vertexIndex,
            component,
            next,
            keyframe: animated,
          ),
        ),
      ],
    );
  }

  Widget _buildMasksPanel(CompositionLayer layer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('MASKS', Icons.crop_free),
        Wrap(
          spacing: 6,
          children: [
            for (final shape in MaskShape.values)
              ActionChip(
                label: Text(shape.name),
                onPressed: () => _controller.addMask(shape: shape),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final mask in layer.masks)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(mask.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                      Switch(
                        value: mask.enabled,
                        onChanged: (value) => _controller.setMaskEnabled(mask.id, value),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<MaskOperation>(
                    initialValue: mask.operation,
                    decoration: const InputDecoration(labelText: 'Mask mode'),
                    items: MaskOperation.values
                        .map((value) => DropdownMenuItem(value: value, child: Text(value.name)))
                        .toList(),
                    onChanged: (value) => _controller.setMaskParameters(mask.id, operation: value),
                  ),
                  _animatedMaskPropertyRow(mask, 'Feather', 'feather', 0, 200),
                  _animatedMaskPropertyRow(mask, 'Expansion', 'expansion', -100, 100),
                  _animatedMaskPropertyRow(mask, 'Left', 'left', 0, (1 - mask.width).clamp(0, 1).toDouble()),
                  _animatedMaskPropertyRow(mask, 'Top', 'top', 0, (1 - mask.height).clamp(0, 1).toDouble()),
                  _animatedMaskPropertyRow(mask, 'Width', 'width', 0.01, (1 - mask.left).clamp(0.01, 1).toDouble()),
                  _animatedMaskPropertyRow(mask, 'Height', 'height', 0.01, (1 - mask.top).clamp(0.01, 1).toDouble()),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Invert mask', style: TextStyle(fontSize: 10)),
                    value: mask.inverted,
                    onChanged: (value) => _controller.setMaskParameters(mask.id, inverted: value),
                  ),
                  if (mask.shape == MaskShape.bezier ||
                      mask.shape == MaskShape.polygon)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'PATH VERTICES · ${mask.vertices.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: mask.vertices.length < 3
                                ? null
                                : () => _controller.keyframeMaskPath(mask.id),
                            icon: const Icon(Icons.key, size: 15),
                            label: const Text('KEYFRAME FULL MASK'),
                          ),
                        ),
                        for (var index = 0; index < mask.vertices.length; index++)
                          Builder(
                            builder: (context) {
                              final vertex = mask.vertices[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Vertex ${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'Anchor X',
                                    'anchor.x',
                                    0,
                                    1,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'Anchor Y',
                                    'anchor.y',
                                    0,
                                    1,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'In handle X',
                                    'inHandle.x',
                                    -0.5,
                                    0.5,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'In handle Y',
                                    'inHandle.y',
                                    -0.5,
                                    0.5,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'Out handle X',
                                    'outHandle.x',
                                    -0.5,
                                    0.5,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'Out handle Y',
                                    'outHandle.y',
                                    -0.5,
                                    0.5,
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: const Text(
                                      'Smooth tangent',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                    value: vertex.smooth,
                                    onChanged: (value) =>
                                        _controller.setMaskVertex(
                                      mask.id,
                                      index,
                                      smooth: value,
                                    ),
                                  ),
                                  const Divider(height: 12),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const Text(
          'Polygon/Bezier anchors and tangent handles can be keyframed for per-frame rotoscoping. Export renders animated feather/expansion; the live canvas clip uses hard edges and does not yet preview feather or per-mask alpha.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
      ],
    );
  }

  Widget _buildParentPanel(CompositionLayer layer) {
    final candidates = _controller.document.layers.where((item) =>
        item.id != layer.id &&
        (item.kind == LayerKind.nullObject ||
            item.kind == LayerKind.camera ||
            item.kind == LayerKind.threeDModel));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('PARENT & LINK', Icons.account_tree),
        DropdownButtonFormField<String?>(
          initialValue: layer.parentId,
          decoration: const InputDecoration(labelText: 'Parent layer'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('No parent')),
            for (final candidate in candidates)
              DropdownMenuItem<String?>(
                value: candidate.id,
                child: Text(candidate.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            final success = _controller.setParent(layer.id, value);
            if (!success) {
              setState(() => _notice = 'Parent link rejected: cyclic or unsupported parent.');
            }
          },
        ),
        const SizedBox(height: 10),
        const Text('Null objects control child transforms without rendering pixels. Parenting is cycle-checked.', style: TextStyle(fontSize: 10, color: Color(0xFF9BAAC1))),
      ],
    );
  }

  Widget _build3dPanel(CompositionLayer layer) {
    if (layer.kind == LayerKind.camera) {
      final camera = layer.camera ?? const CameraSettings();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('CAMERA CONTROLS', Icons.videocam),
          const Text(
            'Camera orientation and perspective now drive image cards and imported OBJ geometry. Near/far clipping is shared by preview and FFmpeg camera projection; depth-of-field blur and shadow maps remain pending.',
            style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: camera.projection,
            decoration: const InputDecoration(labelText: 'Projection'),
            items: const [
              DropdownMenuItem(value: 'perspective', child: Text('Perspective')),
              DropdownMenuItem(value: 'orthographic', child: Text('Orthographic')),
            ],
            onChanged: (value) => _controller.setCameraSettings(
              camera.copyWith(projection: value ?? 'perspective'),
            ),
          ),
          _settingSlider('Field of View', camera.fieldOfView, 10, 120,
              (value) => _controller.setCameraSettings(camera.copyWith(fieldOfView: value))),
          _settingSlider('Focal Length', camera.focalLength, 10, 300,
              (value) => _controller.setCameraSettings(camera.copyWith(focalLength: value))),
          _settingSlider('Focus Distance', camera.focusDistance, 1, 5000,
              (value) => _controller.setCameraSettings(camera.copyWith(focusDistance: value))),
          _settingSlider('Near Clip', camera.nearClip, 1, 2000,
              (value) => _controller.setCameraSettings(camera.copyWith(
                    nearClip: value,
                    farClip: camera.farClip <= value ? value + 1 : camera.farClip,
                  ))),
          _settingSlider('Far Clip', camera.farClip, camera.nearClip + 1, 50000,
              (value) => _controller.setCameraSettings(camera.copyWith(farClip: value))),
          _settingSlider('Aperture · f-stop', camera.aperture, 0.7, 22,
              (value) => _controller.setCameraSettings(camera.copyWith(aperture: value))),
          _settingSlider('Sensor Width · mm', camera.sensorWidthMm, 18, 70,
              (value) => _controller.setCameraSettings(camera.copyWith(sensorWidthMm: value))),
          const SizedBox(height: 8),
          const Text(
            'CAMERA ORIENTATION',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
          _animatedPropertyRow(layer, 'Orbit X', 'rotation.x', -180, 180),
          _animatedPropertyRow(layer, 'Orbit Y', 'rotation.y', -180, 180),
          _animatedPropertyRow(layer, 'Roll Z', 'rotation.z', -180, 180),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Depth of Field · CPU preview',
              style: TextStyle(fontSize: 11),
            ),
            value: camera.depthOfField,
            onChanged: (value) => _controller.setCameraSettings(
              camera.copyWith(depthOfField: value),
            ),
          ),
        ],
      );
    }
    if (layer.kind == LayerKind.light) {
      final light = layer.light ?? const LightSettings();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('LIGHT CONTROLS', Icons.lightbulb_outline),
          const Text(
            'Directional, spot and point lights use depth-tested shadow maps with percentage-closer filtering. Mesh frames also use thin-lens depth of field and deterministic area-light sampling.',
            style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<LightKind>(
            initialValue: light.kind,
            decoration: const InputDecoration(labelText: 'Light type'),
            items: LightKind.values
                .map((value) => DropdownMenuItem(value: value, child: Text(value.name)))
                .toList(),
            onChanged: (value) => _controller.setLightSettings(
              light.copyWith(kind: value ?? LightKind.directional),
            ),
          ),
          _settingSlider('Intensity', light.intensity, 0, 1000,
              (value) => _controller.setLightSettings(light.copyWith(intensity: value))),
          _settingSlider('Spot Cone', light.coneAngle, 1, 180,
              (value) => _controller.setLightSettings(light.copyWith(coneAngle: value))),
          _settingSlider('Shadow Softness', light.shadowSoftness, 0, 100,
              (value) => _controller.setLightSettings(light.copyWith(shadowSoftness: value))),
          if (light.kind == LightKind.area) ...[
            _settingSlider('Area Size', light.areaSize, 1, 1000,
                (value) => _controller.setLightSettings(light.copyWith(areaSize: value))),
            _settingSlider('Area Samples', light.areaSamples.toDouble(), 1, 64,
                (value) => _controller.setLightSettings(
                    light.copyWith(areaSamples: value.round()))),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cast Shadows', style: TextStyle(fontSize: 11)),
            value: light.castShadows,
            onChanged: (value) => _controller.setLightSettings(
              light.copyWith(castShadows: value),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('3D MESH LAYER', Icons.view_in_ar),
        Text(
          layer.sourceUri == null
              ? 'Import OBJ, GLTF or GLB. GLTF scenes retain UV0, base-colour images, vertex normals, nested node transforms and embedded animation clips.'
              : 'Loaded source: ${layer.name}\nPreview and rendered frames use UV-mapped base-colour textures, transformed smooth normals, active-scene hierarchy and the selected animation clip.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF98A7C0)),
        ),
        if (layer.sourceUri != null) ...[
          const SizedBox(height: 10),
          FutureBuilder<ObjMesh>(
            future: _meshFor(layer.sourceUri!),
            builder: (context, snapshot) {
              final mesh = snapshot.data;
              if (snapshot.hasError) {
                return Text(
                  'Could not inspect scene metadata: ${snapshot.error}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFFF9D9D)),
                );
              }
              if (mesh == null) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              final texturedMaterials = mesh.materials.values
                  .where((material) => material.baseColorTextureBytes != null)
                  .length;
              final inventory = '${mesh.sceneNodes.length} nodes · ${mesh.triangles.length} triangles · '
                  '${mesh.materials.length} materials · $texturedMaterials base-colour maps · '
                  '${mesh.hasTextureCoordinates ? 'UV0 available' : 'no UV0 stream'}';
              if (mesh.animations.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(inventory, style: const TextStyle(fontSize: 9, color: Color(0xFF9BAAC1))),
                    const SizedBox(height: 5),
                    const Text(
                      'No embedded animation clips found. The model stays in its rest pose.',
                      style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
                    ),
                  ],
                );
              }
              final selectedIndex = layer.modelAnimationIndex
                  .clamp(-1, mesh.animations.length - 1)
                  .toInt();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(inventory, style: const TextStyle(fontSize: 9, color: Color(0xFF9BAAC1))),
                  const SizedBox(height: 7),
                  DropdownButtonFormField<int>(
                    key: ValueKey<String>(layer.id + ':gltf-animation'),
                    initialValue: selectedIndex,
                    decoration: const InputDecoration(labelText: 'Animation Clip'),
                    items: [
                      const DropdownMenuItem<int>(value: -1, child: Text('Rest Pose')),
                      for (final entry in mesh.animations.indexed)
                        DropdownMenuItem<int>(
                          value: entry.$1,
                          child: Text(
                            entry.$2.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _controller.setModelAnimationIndex(value);
                    },
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${mesh.animations.length} clip(s) · translation / rotation / scale · follows the composition playhead',
                    style: const TextStyle(fontSize: 9, color: Color(0xFF98A7C0)),
                  ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _addLayer(LayerKind.threeDModel),
          icon: const Icon(Icons.file_open),
          label: const Text('IMPORT OBJ / GLTF / GLB'),
        ),
      ],
    );
  }

  Widget _settingSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label  ${value.toStringAsFixed(1)}', style: const TextStyle(fontSize: 10)),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _splitSelectedLayer() {
    final selected = _selected;
    if (selected == null) return;
    final split = _controller.splitSelectedLayerAtPlayhead();
    if (!mounted) return;
    setState(() {
      _notice = split
          ? 'Split ${selected.name} at ${_time(_controller.document.playheadMs)}. The right segment is selected.'
          : 'Place the playhead inside an unlocked clip to split it.';
      if (split) {
        _panel = 'Timing';
        _graphEditorVisible = false;
      }
    });
  }

  void _deleteSelectedLayer() {
    final selected = _selected;
    if (selected == null) return;
    _controller.removeSelectedLayer();
    if (!mounted) return;
    setState(() => _notice = 'Deleted layer "${selected.name}". Use Undo to restore it.');
  }

  void _jumpToKeyframe({required bool forward}) {
    final layer = _selected;
    if (layer == null) return;
    final times = <int>{
      for (final track in layer.keyframeTracks)
        for (final keyframe in track.keyframes) keyframe.timeMs,
      for (final effect in layer.effects)
        for (final track in effect.keyframeTracks)
          for (final keyframe in track.keyframes) keyframe.timeMs,
      for (final mask in layer.masks)
        for (final track in mask.keyframeTracks)
          for (final keyframe in track.keyframes) keyframe.timeMs,
    }.toList()
      ..sort();
    if (times.isEmpty) {
      setState(() => _notice = 'No keyframes exist on the selected layer yet.');
      return;
    }
    final playhead = _controller.document.playheadMs;
    final candidates = forward
        ? times.where((time) => time > playhead).toList()
        : times.where((time) => time < playhead).toList();
    final target = candidates.isEmpty
        ? (forward ? times.first : times.last)
        : (forward ? candidates.first : candidates.last);
    _pausePreviewPlayback();
    _controller.setPlayhead(target);
  }

  List<({
    String label,
    KeyframeTrack track,
    String? effectId,
    String? maskId,
  })> _graphTracksFor(CompositionLayer? layer) {
    if (layer == null) return const [];
    return [
      for (final track in layer.keyframeTracks)
        (
          label: 'Transform · ${track.property}',
          track: track,
          effectId: null,
          maskId: null,
        ),
      for (final effect in layer.effects)
        for (final track in effect.keyframeTracks)
          (
            label: '${effect.name} · ${track.property}',
            track: track,
            effectId: effect.id,
            maskId: null,
          ),
      for (final mask in layer.masks)
        for (final track in mask.keyframeTracks)
          (
            label: 'Mask · ${mask.name} · ${track.property}',
            track: track,
            effectId: null,
            maskId: mask.id,
          ),
    ];
  }

  void _scrubGraph(double x, double width, int duration) {
    if (width <= 0 || duration <= 0) return;
    _pausePreviewPlayback();
    _controller.setPlayhead(
      (x / width * duration).round().clamp(0, duration),
    );
  }

  void _beginGraphGesture(
    Offset position,
    Size size,
    KeyframeTrack track,
    int duration,
  ) {
    final geometry = _KeyframeGraphGeometry(
      track: track,
      durationMs: duration,
      size: size,
      speedMode: _graphSpeedMode,
    );
    _graphDragGeometry = geometry;
    _graphDragHistoryRecorded = false;
    _graphScrubbing = true;
    _draggingGraphKeyframeMs = null;

    if (!_graphSpeedMode) {
      final keyframe = geometry.nearestKeyframe(position, track.keyframes);
      if (keyframe != null) {
        _draggingGraphKeyframeMs = keyframe.timeMs;
        _graphScrubbing = false;
        setState(() => _selectedGraphKeyframeMs = keyframe.timeMs);
      }
    }
  }

  void _updateGraphGesture(
    Offset position,
    KeyframeTrack track,
    int duration, {
    String? effectId,
    String? maskId,
  }) {
    final geometry = _graphDragGeometry;
    if (geometry == null) return;

    final draggingTime = _draggingGraphKeyframeMs;
    if (draggingTime != null && !_graphSpeedMode) {
      final fps = _controller.document.frameRate <= 0
          ? 24.0
          : _controller.document.frameRate;
      final frame = (geometry.timeAt(position) * fps / 1000).round();
      final snappedTime =
          (frame * 1000 / fps).round().clamp(0, duration).toInt();
      final value = geometry.valueAt(position);
      final resolvedTime = _controller.updateKeyframe(
        track.property,
        draggingTime,
        snappedTime,
        value,
        effectId: effectId,
        maskId: maskId,
        recordHistory: !_graphDragHistoryRecorded,
      );
      if (resolvedTime == null) return;
      _graphDragHistoryRecorded = true;
      _draggingGraphKeyframeMs = resolvedTime;
      _selectedGraphKeyframeMs = resolvedTime;
      return;
    }

    if (_graphScrubbing) {
      _pausePreviewPlayback();
      _controller.setPlayhead(
        geometry.timeAt(position).round().clamp(0, duration).toInt(),
      );
    }
  }

  void _endGraphGesture() {
    _graphDragGeometry = null;
    _draggingGraphKeyframeMs = null;
    _graphScrubbing = false;
    _graphDragHistoryRecorded = false;
  }

  void _tapGraph(
    Offset position,
    Size size,
    KeyframeTrack track,
    int duration,
  ) {
    final geometry = _KeyframeGraphGeometry(
      track: track,
      durationMs: duration,
      size: size,
      speedMode: _graphSpeedMode,
    );
    final keyframe = geometry.nearestKeyframe(position, track.keyframes);
    if (keyframe != null) {
      setState(() => _selectedGraphKeyframeMs = keyframe.timeMs);
      _pausePreviewPlayback();
      _controller.setPlayhead(keyframe.timeMs);
    } else {
      _scrubGraph(position.dx, size.width, duration);
    }
  }

  Widget _buildGraphEditor(int duration) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final options = _graphTracksFor(_selected);
    if (options.isEmpty) {
      return Center(
        child: Text(
          _selected == null
              ? 'Select a layer with animated properties to view its graph.'
              : 'No keyframes yet. Add a keyframe to Transform, Effects or Masks.',
          style: TextStyle(fontSize: 10, color: palette.secondaryText),
        ),
      );
    }
    final active = options.firstWhere(
      (item) => item.label == _graphTrackLabel,
      orElse: () => options.first,
    );
    if (_graphTrackLabel != active.label) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _graphTrackLabel != active.label) {
          setState(() {
            _graphTrackLabel = active.label;
            _selectedGraphKeyframeMs = null;
          });
        }
      });
    }
    final selectedFrames = active.track.keyframes
        .where((item) => item.timeMs == _selectedGraphKeyframeMs)
        .toList();
    final selectedKeyframe =
        selectedFrames.isEmpty ? null : selectedFrames.first;

    return Column(
      children: [
        SizedBox(
          height: 34,
          child: Row(
            children: [
              const Icon(Icons.show_chart, size: 14),
              const SizedBox(width: 7),
              Text(
                'GRAPH EDITOR',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w900,
                  color: palette.secondaryText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: active.label,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(fontSize: 9, color: palette.primaryText),
                  items: options
                      .map((item) => DropdownMenuItem(
                            value: item.label,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9),
                            ),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() {
                    _graphTrackLabel = value;
                    _selectedGraphKeyframeMs = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<bool>(
                value: _graphSpeedMode,
                underline: const SizedBox.shrink(),
                style: TextStyle(fontSize: 9, color: palette.primaryText),
                items: const [
                  DropdownMenuItem(value: false, child: Text('VALUE')),
                  DropdownMenuItem(value: true, child: Text('SPEED')),
                ],
                onChanged: (value) => setState(() => _graphSpeedMode = value ?? false),
              ),
              IconButton(
                tooltip: selectedKeyframe == null
                    ? 'Select a keyframe to edit its Bezier curve'
                    : 'Edit selected keyframe Bezier handles',
                visualDensity: VisualDensity.compact,
                onPressed: selectedKeyframe == null
                    ? null
                    : () => _editBezierCurve(
                          active.track.property,
                          selectedKeyframe.bezier,
                          effectId: active.effectId,
                          maskId: active.maskId,
                          timeMs: selectedKeyframe.timeMs,
                        ),
                icon: const Icon(Icons.tune, size: 15),
              ),
              Text(
                '${active.track.keyframes.length} KEYS',
                style: TextStyle(fontSize: 8, color: palette.secondaryText),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _tapGraph(
                  details.localPosition,
                  size,
                  active.track,
                  duration,
                ),
                onPanStart: (details) => _beginGraphGesture(
                  details.localPosition,
                  size,
                  active.track,
                  duration,
                ),
                onPanUpdate: (details) => _updateGraphGesture(
                  details.localPosition,
                  active.track,
                  duration,
                  effectId: active.effectId,
                  maskId: active.maskId,
                ),
                onPanEnd: (_) => _endGraphGesture(),
                onPanCancel: _endGraphGesture,
                child: CustomPaint(
                  size: size,
                  painter: _KeyframeGraphPainter(
                    track: active.track,
                    durationMs: duration,
                    playheadMs: _controller.document.playheadMs,
                    selectedKeyframeTimeMs: _selectedGraphKeyframeMs,
                    speedMode: _graphSpeedMode,
                    gridColor: palette.border,
                    curveColor: palette.accent,
                    keyframeColor: const Color(0xFFE7C46D),
                    playheadColor: const Color(0xFFFFA65C),
                    textColor: palette.secondaryText,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlayheadAwareTimeline() {
    final doc = _controller.document;
    return AnimatedBuilder(
      animation: _controller.playhead,
      child: _buildTimelineLayerRows(doc.layers, doc.durationMs),
      builder: (context, layerRows) {
        final currentDoc = _controller.document;
        return _buildTimeline(
          currentDoc.playheadMs,
          currentDoc.durationMs,
          layerRows: layerRows!,
        );
      },
    );
  }

  Widget _buildTimeline(
    int playhead,
    int duration, {
    required Widget layerRows,
  }) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      height: 260,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.toolbar,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, size: 16),
              const SizedBox(width: 8),
              Text(
                'TIMELINE  ·  ${_controller.document.name.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(_time(playhead), style: const TextStyle(fontSize: 10, color: Color(0xFFB7C4DC))),
              Builder(
                builder: (context) {
                  final stats = _previewFrameService.stats;
                  final decodeText = stats.averageDecodeMs <= 0
                      ? 'decode warming'
                      : '${stats.averageDecodeMs.round()} ms decode';
                  final uiText = stats.averageUiFrameMs <= 0
                      ? 'UI warming'
                      : '${stats.averageUiFrameMs.round()} ms UI';
                  final queueText = stats.averageQueueWaitMs <= 0
                      ? 'queue ready'
                      : '${stats.averageQueueWaitMs.round()} ms queue';
                  return Text(
                    '${stats.effectivePreviewWidth}px · '
                    '${stats.effectivePreviewFrameRate} FPS · '
                    '$decodeText · $queueText · $uiText · '
                    '${stats.droppedRequests} skipped',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF8D9CB3),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: _previewPlaying ? 'Pause realtime preview' : 'Play realtime preview',
                onPressed: duration <= 0 ? null : _togglePreviewPlayback,
                icon: Icon(
                  _previewPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  size: 21,
                ),
              ),
              IconButton(
                tooltip: 'Previous frame',
                onPressed: () {
                  _pausePreviewPlayback();
                  _controller.setPlayhead(
                    playhead - (1000 / _controller.document.frameRate).round(),
                  );
                },
                icon: const Icon(Icons.chevron_left, size: 18),
              ),
              IconButton(
                tooltip: 'Next frame',
                onPressed: () {
                  _pausePreviewPlayback();
                  _controller.setPlayhead(
                    playhead + (1000 / _controller.document.frameRate).round(),
                  );
                },
                icon: const Icon(Icons.chevron_right, size: 18),
              ),
              IconButton(
                tooltip: 'Previous keyframe',
                onPressed: () => _jumpToKeyframe(forward: false),
                icon: const Icon(Icons.skip_previous, size: 18),
              ),
              IconButton(
                tooltip: 'Next keyframe',
                onPressed: () => _jumpToKeyframe(forward: true),
                icon: const Icon(Icons.skip_next, size: 18),
              ),
              IconButton(
                tooltip: 'Add position keyframe',
                onPressed: _selected == null
                    ? null
                    : () => _addKeyframe('position.x'),
                icon: const Icon(Icons.diamond_outlined, size: 17),
              ),
              IconButton(
                tooltip: 'Split selected clip at playhead',
                onPressed: _selected == null || _selected!.locked
                    ? null
                    : _splitSelectedLayer,
                icon: const Icon(Icons.content_cut, size: 17),
              ),
              IconButton(
                tooltip: 'Delete selected layer',
                onPressed: _selected == null ? null : _deleteSelectedLayer,
                icon: const Icon(Icons.delete_outline, size: 17),
              ),
              IconButton(
                tooltip: _graphEditorVisible
                    ? 'Show layer timeline'
                    : 'Show Graph Editor',
                color: _graphEditorVisible ? palette.accent : null,
                onPressed: () => setState(() {
                  _graphEditorVisible = !_graphEditorVisible;
                  _panel = 'Animation';
                }),
                icon: const Icon(Icons.show_chart, size: 18),
              ),
              PopupMenuButton<TransitionKind>(
                tooltip: 'Add transition',
                onSelected: _controller.addTransition,
                itemBuilder: (_) => TransitionKind.values
                    .map((kind) => PopupMenuItem(value: kind, child: Text(kind.name)))
                    .toList(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.auto_awesome_motion, size: 18),
                ),
              ),
            ],
          ),
          Slider(
            value: playhead.toDouble().clamp(0, duration.toDouble()).toDouble(),
            min: 0,
            max: duration.toDouble(),
            onChanged: (value) {
              _pausePreviewPlayback();
              _controller.setPlayhead(value.round());
            },
          ),
          Expanded(
            child: _graphEditorVisible
                ? _buildGraphEditor(duration)
                : layerRows,
          ),
        ],
      ),
    );
  }

  /// Builds the layer list independently from the per-frame timeline header.
  ///
  /// The returned widget is passed as AnimatedBuilder.child, so playback ticks
  /// update only the time display/slider and the single playhead overlay rather
  /// than rebuilding every visible layer row and clip.
  List<({String label, KeyframeTrack track})> _timelineTracksFor(
    CompositionLayer layer,
  ) {
    return [
      for (final track in layer.keyframeTracks)
        (label: track.property, track: track),
      for (final effect in layer.effects)
        for (final track in effect.keyframeTracks)
          (label: '${effect.name} · ${track.property}', track: track),
      for (final mask in layer.masks)
        for (final track in mask.keyframeTracks)
          (label: 'Mask · ${mask.name} · ${track.property}', track: track),
    ];
  }

  Widget _buildTimelinePropertyLane(
    String label,
    KeyframeTrack track,
    int duration, {
    required double labelWidth,
  }) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final safeDuration = math.max(1, duration);
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 25, right: 5),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8,
                  color: palette.secondaryText,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: palette.appBackground.withValues(alpha: 0.6),
                border: Border(
                  top: BorderSide(color: palette.border.withValues(alpha: 0.45)),
                  bottom: BorderSide(color: palette.border.withValues(alpha: 0.45)),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final keyframe in track.keyframes)
                      Positioned(
                        left: (keyframe.timeMs / safeDuration *
                                constraints.maxWidth - 5)
                            .clamp(0.0, math.max(0.0, constraints.maxWidth - 10))
                            .toDouble(),
                        top: 2,
                        bottom: 2,
                        child: Tooltip(
                          message:
                              '${_time(keyframe.timeMs)} · ${keyframe.value.toStringAsFixed(3)} · ${keyframe.interpolation.name}',
                          child: GestureDetector(
                            onTap: () {
                              _pausePreviewPlayback();
                              _controller.setPlayhead(keyframe.timeMs);
                            },
                            child: const Icon(
                              Icons.diamond,
                              size: 10,
                              color: Color(0xFFE4C36B),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color paletteText(BuildContext context) =>
      Theme.of(context).extension<DepthVibePalette>()!.primaryText;

  Widget _buildTimelineLayerRows(
    List<CompositionLayer> layers,
    int duration,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = math.min(130.0, constraints.maxWidth);
        final trackWidth = math.max(0.0, constraints.maxWidth - labelWidth);
        final selectedId = _controller.document.selectedLayerId;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ListView.builder(
              itemCount: layers.length,
              itemBuilder: (context, index) {
                final layer = layers[index];
                final selected = layer.id == selectedId;
                final tracks = _timelineTracksFor(layer);
                final expanded = selected ||
                    _expandedTimelineLayers.contains(layer.id);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: selected
                          ? const Color(0x223C65A8)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 21,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    tooltip: expanded
                                        ? 'Collapse layer properties'
                                        : 'Expand layer properties',
                                    onPressed: () => setState(() {
                                      if (_expandedTimelineLayers.contains(layer.id)) {
                                        _expandedTimelineLayers.remove(layer.id);
                                      } else {
                                        _expandedTimelineLayers.add(layer.id);
                                      }
                                    }),
                                    icon: Icon(
                                      expanded
                                          ? Icons.expand_more
                                          : Icons.chevron_right,
                                      size: 14,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _controller.selectLayer(layer.id),
                                    child: Text(
                                      layer.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: selected
                                            ? FontWeight.w900
                                            : FontWeight.w500,
                                        color: selected
                                            ? const Color(0xFFEAF0FF)
                                            : paletteText(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _buildTimelineClip(layer, duration),
                          ),
                        ],
                      ),
                    ),
                    if (expanded)
                      for (final track in tracks)
                        _buildTimelinePropertyLane(
                          track.label,
                          track.track,
                          duration,
                          labelWidth: labelWidth,
                        ),
                  ],
                );
              },
            ),
            AnimatedBuilder(
              animation: _controller.playhead,
              builder: (context, _) {
                final currentDuration =
                    math.max(1, _controller.document.durationMs);
                final progress = (_controller.document.playheadMs /
                        currentDuration)
                    .clamp(0.0, 1.0)
                    .toDouble();
                final x = (labelWidth + progress * trackWidth)
                    .clamp(
                      0.0,
                      math.max(0.0, constraints.maxWidth - 1),
                    )
                    .toDouble();
                return Positioned(
                  left: x,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: IgnorePointer(
                    child: Container(color: const Color(0xFFFFC36A)),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimelineClip(CompositionLayer layer, int duration) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final safeDuration = math.max(1, duration);
        final left = (layer.startMs / safeDuration * width)
            .clamp(0.0, width).toDouble();
        final right = (layer.endMs / safeDuration * width)
            .clamp(left, width).toDouble();
        final clipWidth = math.max(8.0, right - left);
        final color = switch (layer.kind) {
          LayerKind.audio => const Color(0xFF247B76),
          LayerKind.video => const Color(0xFF425B9B),
          LayerKind.image || LayerKind.photoshopLayer => const Color(0xFF66539D),
          LayerKind.shape || LayerKind.text => const Color(0xFF93613D),
          _ => const Color(0xFF475568),
        };
        final markers = <int>[
          for (final track in layer.keyframeTracks)
            for (final keyframe in track.keyframes) keyframe.timeMs,
          for (final effect in layer.effects)
            for (final track in effect.keyframeTracks)
              for (final keyframe in track.keyframes) keyframe.timeMs,
          for (final mask in layer.masks)
            for (final track in mask.keyframeTracks)
              for (final keyframe in track.keyframes) keyframe.timeMs,
        ];
        return GestureDetector(
          onTapDown: (details) {
            final position = (details.localPosition.dx / width * safeDuration)
                .round().clamp(0, safeDuration);
            _pausePreviewPlayback();
            _controller.setPlayhead(position);
          },
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF101827),
              border: Border.all(color: const Color(0xFF2B3850)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (final transition in _controller.document.transitions)
                  if (transition.fromLayerId == layer.id ||
                      transition.toLayerId == layer.id)
                    Positioned(
                      left: (transition.startMs / safeDuration * width)
                          .clamp(0.0, width).toDouble(),
                      width: (transition.durationMs / safeDuration * width)
                          .clamp(2.0, width).toDouble(),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0x66B48CFF),
                          border: Border.all(color: const Color(0xFFB48CFF)),
                        ),
                      ),
                    ),
                Positioned(
                  left: left,
                  width: clipWidth,
                  top: 3,
                  bottom: 3,
                  child: GestureDetector(
                    onHorizontalDragUpdate: layer.locked
                        ? null
                        : (details) {
                            final delta = (details.delta.dx / width *
                                    safeDuration)
                                .round();
                            _controller.setLayerTiming(
                              layer.id,
                              startMs: layer.startMs + delta,
                            );
                          },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: layer.locked
                              ? const Color(0xFF687386)
                              : const Color(0xFF91A8FF),
                        ),
                      ),
                      child: Stack(
                        children: [
                          if (layer.kind == LayerKind.audio &&
                              layer.sourceUri != null)
                            Positioned.fill(
                              child: FutureBuilder<File?>(
                                future: _waveformFor(layer.sourceUri!),
                                builder: (context, snapshot) {
                                  final waveform = snapshot.data;
                                  if (waveform == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return IgnorePointer(
                                    child: Opacity(
                                      opacity: 0.82,
                                      child: Image.file(
                                        waveform,
                                        fit: BoxFit.fill,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          Positioned(
                            left: 5,
                            right: 12,
                            top: 4,
                            child: Text(
                              layer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF2F5FF),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onHorizontalDragUpdate: layer.locked
                                  ? null
                                  : (details) {
                                      final delta = (details.delta.dx /
                                              width * safeDuration)
                                          .round();
                                      _controller.setLayerTiming(
                                        layer.id,
                                        durationMs: layer.durationMs + delta,
                                      );
                                    },
                              child: Container(
                                width: 9,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFB8C8FF),
                                  borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final time in markers)
                  Positioned(
                    left: (time / safeDuration * width)
                        .clamp(0.0, math.max(0.0, width - 10)).toDouble(),
                    top: 0,
                    bottom: 0,
                    child: const Icon(
                      Icons.diamond,
                      size: 10,
                      color: Color(0xFFD6C8FF),
                    ),
                  ),

              ],
            ),
          ),
        );
      },
    );
  }

  Widget _panelHeader(String label, IconData icon) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 15, color: palette.accent),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: palette.secondaryText)),
        ],
      ),
    );
  }

  IconData _iconFor(LayerKind kind) => switch (kind) {
        LayerKind.video => Icons.movie,
        LayerKind.image => Icons.image,
        LayerKind.photoshopLayer => Icons.layers,
        LayerKind.text => Icons.text_fields,
        LayerKind.shape => Icons.category,
        LayerKind.audio => Icons.graphic_eq,
        LayerKind.nullObject => Icons.control_camera,
        LayerKind.adjustment => Icons.tune,
        LayerKind.camera => Icons.videocam,
        LayerKind.light => Icons.lightbulb,
        LayerKind.threeDModel => Icons.view_in_ar,
        LayerKind.particle => Icons.auto_awesome,
        LayerKind.precomposition => Icons.layers_outlined,
      };
}

/// A lightweight, CPU-painted value graph for the selected animated property.
class _KeyframeGraphGeometry {
  _KeyframeGraphGeometry({
    required this.track,
    required this.durationMs,
    required Size size,
    required this.speedMode,
  })  : plot = Rect.fromLTWH(
          42,
          8,
          math.max(1, size.width - 54),
          math.max(1, size.height - 28),
        ) {
    final safeDuration = math.max(1, durationMs);
    final samples = <double>[
      for (var index = 0; index <= 160; index++)
        graphValueAtTime((safeDuration * index / 160).round()),
      for (final frame in track.keyframes)
        graphValueAtTime(frame.timeMs),
    ].where((value) => value.isFinite).toList();
    var low = samples.isEmpty
        ? 0.0
        : samples.reduce((a, b) => a < b ? a : b);
    var high = samples.isEmpty
        ? 1.0
        : samples.reduce((a, b) => a > b ? a : b);
    if ((high - low).abs() < 0.000001) {
      final padding = math.max(1.0, high.abs() * 0.15);
      low -= padding;
      high += padding;
    } else {
      final padding = (high - low) * 0.18;
      low -= padding;
      high += padding;
    }
    minimum = low;
    maximum = high;
  }

  final KeyframeTrack track;
  final int durationMs;
  final bool speedMode;
  final Rect plot;
  late final double minimum;
  late final double maximum;

  double graphValueAtTime(int timeMs) {
    if (!speedMode) {
      return track.sample(timeMs, fallback: track.keyframes.first.value);
    }
    const halfWindowMs = 8;
    final before =
        (timeMs - halfWindowMs).clamp(0, durationMs).toInt();
    final after =
        (timeMs + halfWindowMs).clamp(0, durationMs).toInt();
    if (after <= before) return 0;
    final deltaSeconds = (after - before) / 1000;
    final deltaValue = track.sample(
          after,
          fallback: track.keyframes.first.value,
        ) -
        track.sample(
          before,
          fallback: track.keyframes.first.value,
        );
    return deltaValue / deltaSeconds;
  }

  double xAt(int timeMs) =>
      plot.left +
      timeMs.clamp(0, math.max(1, durationMs)) /
          math.max(1, durationMs) *
          plot.width;

  double yAt(double value) =>
      plot.bottom - (value - minimum) / (maximum - minimum) * plot.height;

  Offset pointFor(int timeMs) =>
      Offset(xAt(timeMs), yAt(graphValueAtTime(timeMs)));

  double timeAt(Offset point) =>
      ((point.dx - plot.left) / plot.width * math.max(1, durationMs))
          .clamp(0, math.max(1, durationMs))
          .toDouble();

  double valueAt(Offset point) =>
      maximum - (point.dy - plot.top) / plot.height * (maximum - minimum);

  ScalarKeyframe? nearestKeyframe(
    Offset position,
    List<ScalarKeyframe> keyframes, {
    double tolerance = 12,
  }) {
    ScalarKeyframe? nearest;
    var distance = tolerance;
    for (final keyframe in keyframes) {
      final candidateDistance = (pointFor(keyframe.timeMs) - position).distance;
      if (candidateDistance <= distance) {
        nearest = keyframe;
        distance = candidateDistance;
      }
    }
    return nearest;
  }
}

class _KeyframeGraphPainter extends CustomPainter {
  const _KeyframeGraphPainter({
    required this.track,
    required this.durationMs,
    required this.playheadMs,
    required this.selectedKeyframeTimeMs,
    required this.speedMode,
    required this.gridColor,
    required this.curveColor,
    required this.keyframeColor,
    required this.playheadColor,
    required this.textColor,
  });

  final KeyframeTrack track;
  final int durationMs;
  final int playheadMs;
  final int? selectedKeyframeTimeMs;
  final bool speedMode;
  final Color gridColor;
  final Color curveColor;
  final Color keyframeColor;
  final Color playheadColor;
  final Color textColor;

  void _drawLabel(Canvas canvas, String value, Offset offset, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: textColor,
          fontSize: 8,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 40 || size.height < 30 || track.keyframes.isEmpty) return;
    final geometry = _KeyframeGraphGeometry(
      track: track,
      durationMs: durationMs,
      size: size,
      speedMode: speedMode,
    );
    final plot = geometry.plot;
    final frames = [...track.keyframes]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 0.7;
    for (var index = 0; index <= 4; index++) {
      final y = plot.top + plot.height * index / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final value = geometry.maximum -
          (geometry.maximum - geometry.minimum) * index / 4;
      _drawLabel(
        canvas,
        speedMode ? value.toStringAsFixed(1) : value.toStringAsFixed(2),
        Offset(2, y - 5),
        36,
      );
    }
    for (var index = 0; index <= 8; index++) {
      final x = plot.left + plot.width * index / 8;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      final seconds =
          (math.max(1, durationMs) * index / 8 / 1000).toStringAsFixed(1);
      _drawLabel(canvas, seconds, Offset(x - 10, plot.bottom + 5), 24);
    }

    final curve = Path();
    const segments = 180;
    for (var index = 0; index <= segments; index++) {
      final time = (math.max(1, durationMs) * index / segments).round();
      final point = geometry.pointFor(time);
      if (index == 0) {
        curve.moveTo(point.dx, point.dy);
      } else {
        curve.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = curveColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    for (final frame in frames) {
      final center = geometry.pointFor(frame.timeMs);
      final selected = frame.timeMs == selectedKeyframeTimeMs;
      final radius = selected ? 6.0 : 4.2;
      final path = Path()
        ..moveTo(center.dx, center.dy - radius)
        ..lineTo(center.dx + radius, center.dy)
        ..lineTo(center.dx, center.dy + radius)
        ..lineTo(center.dx - radius, center.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = keyframeColor);
      canvas.drawPath(
        path,
        Paint()
          ..color = selected ? curveColor : const Color(0xFF171D2A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.6 : 0.7,
      );
    }

    final playheadX = geometry.xAt(playheadMs);
    canvas.drawLine(
      Offset(playheadX, plot.top),
      Offset(playheadX, plot.bottom),
      Paint()
        ..color = playheadColor
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(
      Offset(playheadX, plot.top),
      3,
      Paint()..color = playheadColor,
    );
    _drawLabel(
      canvas,
      speedMode ? 'VALUE / SEC' : 'VALUE',
      const Offset(4, 1),
      46,
    );
  }

  @override
  bool shouldRepaint(covariant _KeyframeGraphPainter oldDelegate) =>
      oldDelegate.track != track ||
      oldDelegate.durationMs != durationMs ||
      oldDelegate.playheadMs != playheadMs ||
      oldDelegate.selectedKeyframeTimeMs != selectedKeyframeTimeMs ||
      oldDelegate.speedMode != speedMode ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.curveColor != curveColor ||
      oldDelegate.keyframeColor != keyframeColor ||
      oldDelegate.playheadColor != playheadColor ||
      oldDelegate.textColor != textColor;
}

class _PreviewSelectionOutlinePainter extends CustomPainter {
  const _PreviewSelectionOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xFF6E83FF)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(size.width / 2, -18),
      Offset(size.width / 2, 0),
      Paint()
        ..color = const Color(0xAA6E83FF)
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _PreviewSelectionOutlinePainter oldDelegate) => false;
}

class _PreviewMotionPathPainter extends CustomPainter {
  const _PreviewMotionPathPainter({
    required this.layer,
    required this.document,
    required this.color,
  });

  final CompositionLayer layer;
  final CompositionDocument document;
  final Color color;

  Offset _pointAt(int timeMs, Size size) {
    return Offset(
      layer.valueAt('position.x', timeMs) /
          math.max(1, document.width) * size.width,
      layer.valueAt('position.y', timeMs) /
          math.max(1, document.height) * size.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final xTracks = layer.keyframeTracks.where((t) => t.property == 'position.x');
    final yTracks = layer.keyframeTracks.where((t) => t.property == 'position.y');
    final times = <int>{
      if (xTracks.isNotEmpty)
        for (final key in xTracks.first.keyframes) key.timeMs,
      if (yTracks.isNotEmpty)
        for (final key in yTracks.first.keyframes) key.timeMs,
    }.toList()..sort();
    if (times.length < 2) return;

    final path = Path();
    const samples = 100;
    for (var i = 0; i <= samples; i++) {
      final time = times.first + ((times.last - times.first) * i / samples).round();
      final point = _pointAt(time, size);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.82)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final time in times) {
      final point = _pointAt(time, size);
      final diamond = Path()
        ..moveTo(point.dx, point.dy - 5)
        ..lineTo(point.dx + 5, point.dy)
        ..lineTo(point.dx, point.dy + 5)
        ..lineTo(point.dx - 5, point.dy)
        ..close();
      canvas.drawCircle(point, 7, Paint()..color = color.withValues(alpha: 0.16));
      canvas.drawPath(diamond, Paint()..color = const Color(0xFFF5D27E));
    }
    canvas.drawCircle(
      _pointAt(document.playheadMs, size),
      4,
      Paint()..color = const Color(0xFFFFA65C),
    );
  }

  @override
  bool shouldRepaint(covariant _PreviewMotionPathPainter oldDelegate) =>
      oldDelegate.layer != layer ||
      oldDelegate.document.playheadMs != document.playheadMs ||
      oldDelegate.document.width != document.width ||
      oldDelegate.document.height != document.height ||
      oldDelegate.color != color;
}

/// Clips a layer to its frame-evaluated polygon/Bezier mask stack.
class _AnimatedMaskClipper extends CustomClipper<Path> {
  const _AnimatedMaskClipper({
    required this.masks,
    required this.timeMs,
  });

  final List<MaskModel> masks;
  final int timeMs;

  Path _shape(MaskModel mask, Size size) {
    final left =
        mask.valueAt('left', timeMs).clamp(0.0, 1.0).toDouble();
    final top =
        mask.valueAt('top', timeMs).clamp(0.0, 1.0).toDouble();
    final width =
        mask.valueAt('width', timeMs).clamp(0.01, 1.0).toDouble();
    final height =
        mask.valueAt('height', timeMs).clamp(0.01, 1.0).toDouble();
    final bounds = Rect.fromLTWH(
      left * size.width,
      top * size.height,
      width * size.width,
      height * size.height,
    );

    switch (mask.shape) {
      case MaskShape.rectangle:
        return Path()..addRect(bounds);
      case MaskShape.ellipse:
        return Path()..addOval(bounds);
      case MaskShape.polygon:
      case MaskShape.bezier:
        if (mask.vertices.length < 3) return Path()..addRect(bounds);
        final base = _baseOutline(mask);
        if (base.isEmpty) return Path();
        final minX = base
            .map((point) => point.dx)
            .reduce((a, b) => a < b ? a : b);
        final maxX = base
            .map((point) => point.dx)
            .reduce((a, b) => a > b ? a : b);
        final minY = base
            .map((point) => point.dy)
            .reduce((a, b) => a < b ? a : b);
        final maxY = base
            .map((point) => point.dy)
            .reduce((a, b) => a > b ? a : b);
        final spanX = (maxX - minX).abs() < 0.0001 ? 1.0 : maxX - minX;
        final spanY = (maxY - minY).abs() < 0.0001 ? 1.0 : maxY - minY;
        Offset mapPoint(double x, double y) => Offset(
              bounds.left + (x - minX) / spanX * bounds.width,
              bounds.top + (y - minY) / spanY * bounds.height,
            );
        final vertices = [
          for (var index = 0; index < mask.vertices.length; index++)
            Offset(
              mask.vertexValueAt(index, 'anchor.x', timeMs),
              mask.vertexValueAt(index, 'anchor.y', timeMs),
            ),
        ];
        final path = Path()..moveTo(
            mapPoint(vertices.first.dx, vertices.first.dy).dx,
            mapPoint(vertices.first.dx, vertices.first.dy).dy,
          );
        for (var index = 0; index < vertices.length; index++) {
          final next = (index + 1) % vertices.length;
          if (mask.shape == MaskShape.polygon) {
            final point = mapPoint(vertices[next].dx, vertices[next].dy);
            path.lineTo(point.dx, point.dy);
          } else {
            final start = vertices[index];
            final end = vertices[next];
            final p1 = mapPoint(
              start.dx +
                  mask.vertexValueAt(index, 'outHandle.x', timeMs),
              start.dy +
                  mask.vertexValueAt(index, 'outHandle.y', timeMs),
            );
            final p2 = mapPoint(
              end.dx +
                  mask.vertexValueAt(next, 'inHandle.x', timeMs),
              end.dy +
                  mask.vertexValueAt(next, 'inHandle.y', timeMs),
            );
            final p3 = mapPoint(end.dx, end.dy);
            path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
          }
        }
        path.close();
        return path;
    }
  }

  List<Offset> _baseOutline(MaskModel mask) {
    if (mask.shape != MaskShape.bezier) {
      return [
        for (var index = 0; index < mask.vertices.length; index++)
          Offset(
            mask.vertices[index].anchor.x,
            mask.vertices[index].anchor.y,
          ),
      ];
    }
    const subdivisions = 8;
    final points = <Offset>[];
    for (var index = 0; index < mask.vertices.length; index++) {
      final next = (index + 1) % mask.vertices.length;
      final start = mask.vertices[index];
      final end = mask.vertices[next];
      final p0 = start.anchor;
      final p1 = Offset(
        p0.x + start.outHandle.x,
        p0.y + start.outHandle.y,
      );
      final p3 = end.anchor;
      final p2 = Offset(
        p3.x + end.inHandle.x,
        p3.y + end.inHandle.y,
      );
      for (var step = 0; step < subdivisions; step++) {
        final t = step / subdivisions;
        final inverse = 1 - t;
        final a = inverse * inverse * inverse;
        final b = 3 * inverse * inverse * t;
        final c = 3 * inverse * t * t;
        final d = t * t * t;
        points.add(Offset(
          a * p0.x + b * p1.dx + c * p2.dx + d * p3.x,
          a * p0.y + b * p1.dy + c * p2.dy + d * p3.y,
        ));
      }
    }
    return points;
  }

  @override
  Path getClip(Size size) {
    if (masks.isEmpty) return Path()..addRect(Offset.zero & size);
    Path? combined;
    for (final mask in masks.where((item) => item.enabled)) {
      var shape = _shape(mask, size);
      if (mask.inverted) {
        final inverse = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addPath(shape, Offset.zero);
        shape = inverse;
      }
      if (combined == null) {
        combined = mask.operation == MaskOperation.subtract
            ? Path.combine(
                PathOperation.difference,
                Path()..addRect(Offset.zero & size),
                shape,
              )
            : shape;
        continue;
      }
      final operation = switch (mask.operation) {
        MaskOperation.add => PathOperation.union,
        MaskOperation.subtract => PathOperation.difference,
        MaskOperation.intersect => PathOperation.intersect,
        MaskOperation.difference => PathOperation.xor,
      };
      try {
        combined = Path.combine(operation, combined, shape);
      } on Exception {
        // Keep the last valid path if a malformed transient path cannot combine.
      }
    }
    return combined ?? (Path()..addRect(Offset.zero & size));
  }

  @override
  bool shouldReclip(covariant _AnimatedMaskClipper oldClipper) =>
      oldClipper.timeMs != timeMs || oldClipper.masks != masks;
}

class _ShapeLayerPainter extends CustomPainter {
  const _ShapeLayerPainter(this.style);

  final ShapeStyle style;

  Color _color(String value) {
    final normalized = value.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16) ?? 0x7C8CFF;
    return Color(0xFF000000 | parsed);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (style.primitive) {
      case ShapePrimitive.rectangle:
        path.addRect(Offset.zero & size);
        break;
      case ShapePrimitive.roundedRectangle:
        path.addRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            Radius.circular(style.cornerRadius),
          ),
        );
        break;
      case ShapePrimitive.ellipse:
        path.addOval(Offset.zero & size);
        break;
      case ShapePrimitive.polygon:
      case ShapePrimitive.star:
        final count = style.primitive == ShapePrimitive.star
            ? (style.points.clamp(3, 24) * 2)
            : style.points.clamp(3, 24);
        final center = Offset(size.width / 2, size.height / 2);
        final radius = math.min(size.width, size.height) / 2;
        for (var index = 0; index < count; index++) {
          final starInner = style.primitive == ShapePrimitive.star && index.isOdd;
          final pointRadius = starInner ? radius * 0.42 : radius;
          final angle = -math.pi / 2 + index * math.pi * 2 / count;
          final point = Offset(
            center.dx + math.cos(angle) * pointRadius,
            center.dy + math.sin(angle) * pointRadius,
          );
          if (index == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        break;
      case ShapePrimitive.path:
        path.addRect(Offset.zero & size);
        break;
    }

    if (style.fillColor.toLowerCase() != 'transparent') {
      canvas.drawPath(path, Paint()..color = _color(style.fillColor));
    }
    if (style.strokeWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.strokeWidth
          ..color = _color(style.strokeColor),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeLayerPainter oldDelegate) =>
      oldDelegate.style != style;
}

class _CanvasGridPainter extends CustomPainter {
  const _CanvasGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF263249)
      ..strokeWidth = 0.5;
    const step = 24.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGridPainter oldDelegate) => false;
}


/// Interactive cubic Bezier graph used by the keyframe interpolation editor.
class _BezierCurveEditor extends StatefulWidget {
  const _BezierCurveEditor({
    required this.curve,
    required this.onChanged,
  });

  final BezierCurve curve;
  final ValueChanged<BezierCurve> onChanged;

  @override
  State<_BezierCurveEditor> createState() => _BezierCurveEditorState();
}

class _BezierCurveEditorState extends State<_BezierCurveEditor> {
  int _activeHandle = 1;

  Rect _plotRect(Size size) =>
      Rect.fromLTWH(24, 12, size.width - 48, size.height - 36);

  Offset _handlePoint(BezierCurve curve, Rect plot, int handle) {
    final x = handle == 1 ? curve.x1 : curve.x2;
    final y = handle == 1 ? curve.y1 : curve.y2;
    return Offset(plot.left + x * plot.width, plot.bottom - y * plot.height);
  }

  void _beginDrag(Offset position, Size size) {
    final plot = _plotRect(size);
    final first = _handlePoint(widget.curve, plot, 1);
    final second = _handlePoint(widget.curve, plot, 2);
    _activeHandle =
        (position - first).distance <= (position - second).distance ? 1 : 2;
  }

  void _updateDrag(Offset position, Size size) {
    final plot = _plotRect(size);
    final x = ((position.dx - plot.left) / plot.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final y = (1 - (position.dy - plot.top) / plot.height)
        .clamp(0.0, 1.0)
        .toDouble();
    final current = widget.curve;
    widget.onChanged(
      _activeHandle == 1
          ? BezierCurve(x1: x, y1: y, x2: current.x2, y2: current.y2)
          : BezierCurve(x1: current.x1, y1: current.y1, x2: x, y2: y),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 320,
        height: 190,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) =>
                  _beginDrag(details.localPosition, size),
              onPanUpdate: (details) =>
                  _updateDrag(details.localPosition, size),
              child: CustomPaint(
                painter: _BezierCurveGraphPainter(widget.curve),
                size: size,
              ),
            );
          },
        ),
      );
}

class _BezierCurveGraphPainter extends CustomPainter {
  const _BezierCurveGraphPainter(this.curve);

  final BezierCurve curve;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(24, 12, size.width - 48, size.height - 36);
    final background = Paint()..color = const Color(0xFF101827);
    canvas.drawRRect(
      RRect.fromRectAndRadius(plot, const Radius.circular(8)),
      background,
    );

    final grid = Paint()
      ..color = const Color(0xFF2A3850)
      ..strokeWidth = 0.8;
    for (var index = 0; index <= 4; index++) {
      final x = plot.left + plot.width * index / 4;
      final y = plot.top + plot.height * index / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    Offset point(double x, double y) =>
        Offset(plot.left + x * plot.width, plot.bottom - y * plot.height);
    final start = point(0, 0);
    final end = point(1, 1);
    final first = point(
      curve.x1.clamp(0.0, 1.0).toDouble(),
      curve.y1.clamp(0.0, 1.0).toDouble(),
    );
    final second = point(
      curve.x2.clamp(0.0, 1.0).toDouble(),
      curve.y2.clamp(0.0, 1.0).toDouble(),
    );

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFF64748B)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      start,
      first,
      Paint()
        ..color = const Color(0xFF7C8CFF)
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      end,
      second,
      Paint()
        ..color = const Color(0xFF37D6C0)
        ..strokeWidth = 1.5,
    );

    final curvePath = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(first.dx, first.dy, second.dx, second.dy, end.dx, end.dy);
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = const Color(0xFFB6A5FF)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(start, 4, Paint()..color = const Color(0xFFE2E8F0));
    canvas.drawCircle(end, 4, Paint()..color = const Color(0xFFE2E8F0));
    canvas.drawCircle(first, 7, Paint()..color = const Color(0xFF7C8CFF));
    canvas.drawCircle(second, 7, Paint()..color = const Color(0xFF37D6C0));
  }

  @override
  bool shouldRepaint(covariant _BezierCurveGraphPainter oldDelegate) =>
      oldDelegate.curve.x1 != curve.x1 ||
      oldDelegate.curve.y1 != curve.y1 ||
      oldDelegate.curve.x2 != curve.x2 ||
      oldDelegate.curve.y2 != curve.y2;
}
