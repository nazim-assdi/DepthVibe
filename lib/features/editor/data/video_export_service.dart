import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

import '../../media/data/gallery_permission_service.dart';

import '../domain/editor_project.dart';

typedef ExportProgress = void Function(double progress);

class VideoExportResult {
  const VideoExportResult({required this.file, this.galleryUri, this.gallerySaveError});

  final File file;
  final String? galleryUri;
  final String? gallerySaveError;
}

class VideoExportService {
  const VideoExportService();

  Future<VideoExportResult> export(EditorProject project, {ExportProgress? onProgress}) async {
    if (!project.hasVideo || !project.hasValidTrim) {
      throw StateError('Choose a video and set a valid trim range before exporting.');
    }

    final source = File(project.videoPath!);
    if (!await source.exists()) {
      throw FileSystemException('The selected source video could not be found.', source.path);
    }

    final documents = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}DepthVibe${Platform.pathSeparator}Exports',
    );
    await exportDirectory.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final output = File(
      '${exportDirectory.path}${Platform.pathSeparator}DepthVibe_$stamp.mp4',
    );

    String? overlayPath;
    if (project.title.trim().isNotEmpty || project.caption.trim().isNotEmpty) {
      final overlay = await _renderTextOverlay(project);
      overlayPath = overlay.path;
    }

    final command = _buildCommand(project, output.path, overlayPath);
    final expectedDuration = project.renderedDurationMs;
    final completion = Completer<void>();

    try {
      final startFuture = FFmpegKit.executeAsync(
          command,
          onStatistics: (statistics) {
            if (expectedDuration > 0) {
              final value = (statistics.time / expectedDuration).clamp(0.0, 0.99);
              onProgress?.call(value.toDouble());
            }
          },
          onComplete: (session) {
            final returnCode = session.getReturnCode();
            if (ReturnCode.isSuccess(returnCode)) {
              if (!completion.isCompleted) completion.complete();
            } else {
              final detail = session.getFailStackTrace() ?? 'FFmpeg export failed.';
              if (!completion.isCompleted) {
                completion.completeError(StateError(detail));
              }
            }
          },
        );
      unawaited(startFuture.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) {
            completion.completeError(error, stackTrace);
          }
        },
      ));
      await completion.future.timeout(const Duration(hours: 2));
      if (!await output.exists() || await output.length() == 0) {
        throw StateError('The export completed but no MP4 file was created.');
      }
      String? galleryUri;
      String? gallerySaveError;
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          final permissionGranted =
              await GalleryPermissionService.requestSavePermission();
          if (!permissionGranted) {
            gallerySaveError = 'Gallery permission was denied. The export remains in app storage.';
          } else {
            final saved = await SaverGallery.saveFile(
              filePath: output.path,
              skipIfExists: false,
              fileName: output.uri.pathSegments.last,
              albumPath: 'DepthVibe',
            );
            galleryUri = saved.savedUri;
          }
        } catch (error) {
          // Keep the rendered MP4 in the app folder even if gallery access is denied.
          gallerySaveError = error.toString();
        }
      }
      onProgress?.call(1);
      return VideoExportResult(
        file: output,
        galleryUri: galleryUri,
        gallerySaveError: gallerySaveError,
      );
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      if (overlayPath != null) {
        final overlay = File(overlayPath);
        if (await overlay.exists()) await overlay.delete();
      }
    }
  }

  String _buildCommand(
    EditorProject project,
    String outputPath,
    String? overlayPath,
  ) {
    final aspect = project.aspect;
    final filters = <String>[
      'trim=start=${_seconds(project.trimInMs)}:end=${_seconds(project.trimOutMs)}',
      'setpts=(PTS-STARTPTS)/${project.speed.toStringAsFixed(3)}',
    ];

    final rotation = project.rotationDegrees % 360;
    if (rotation == 90) {
      filters.add('transpose=clock');
    } else if (rotation == 180) {
      filters.addAll(['hflip', 'vflip']);
    } else if (rotation == 270) {
      filters.add('transpose=cclock');
    }

    if (project.canvasFit == CanvasFit.fit) {
      filters.add(
        'scale=${aspect.width}:${aspect.height}:force_original_aspect_ratio=decrease',
      );
      filters.add(
        'pad=${aspect.width}:${aspect.height}:(ow-iw)/2:(oh-ih)/2:color=black',
      );
    } else {
      filters.add(
        'scale=${aspect.width}:${aspect.height}:force_original_aspect_ratio=increase',
      );
      filters.add('crop=${aspect.width}:${aspect.height}');
    }
    filters.addAll(['setsar=1', 'fps=30']);

    final graph = overlayPath == null
        ? '[0:v]${filters.join(',')},format=yuv420p[vout]'
        : '[0:v]${filters.join(',')}[base];'
            '[1:v]format=rgba[title];'
            '[base][title]overlay=0:0:shortest=1:format=auto,format=yuv420p[vout]';

    final buffer = StringBuffer();
    buffer.write('-y -i ${_quote(project.videoPath!)} ');
    if (overlayPath != null) {
      buffer.write('-loop 1 -framerate 30 -i ${_quote(overlayPath)} ');
    }
    buffer.write('-filter_complex ${_quote(graph)} ');
    buffer.write('-map "[vout]" ');
    buffer.write('-t ${_seconds(project.renderedDurationMs)} ');
    if (project.muted) {
      buffer.write('-an ');
    } else {
      buffer.write('-map 0:a? ');
      final audioFilters = <String>[
        'atrim=start=${_seconds(project.trimInMs)}:end=${_seconds(project.trimOutMs)}',
        'asetpts=PTS-STARTPTS',
        _audioTempo(project.speed),
      ];
      buffer.write('-af ${_quote(audioFilters.join(','))} ');
      buffer.write('-c:a aac -b:a 192k ');
    }
    buffer.write('-c:v mpeg4 -q:v 3 -pix_fmt yuv420p -movflags +faststart ');
    buffer.write(_quote(outputPath));
    return buffer.toString();
  }

  Future<File> _renderTextOverlay(EditorProject project) async {
    final width = project.aspect.width;
    final height = project.aspect.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    final title = project.title.trim();
    final caption = project.caption.trim();
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: Colors.white,
          fontSize: width * 0.046,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 3))],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: width * 0.84);

    final captionPainter = TextPainter(
      text: TextSpan(
        text: caption,
        style: TextStyle(
          color: const Color(0xFFE6E9F2),
          fontSize: width * 0.026,
          fontWeight: FontWeight.w500,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: width * 0.84);

    final gap = title.isNotEmpty && caption.isNotEmpty ? height * 0.012 : 0.0;
    final contentHeight = titlePainter.height + captionPainter.height + gap;
    final left = (width - (titlePainter.width > captionPainter.width
            ? titlePainter.width
            : captionPainter.width)) /
        2;
    final top = height * 0.78 - contentHeight / 2;
    final box = Rect.fromLTWH(
      left - width * 0.035,
      top - height * 0.025,
      (width - left * 2) + width * 0.07,
      contentHeight + height * 0.05,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(width * 0.018)),
      Paint()..color = const Color(0x99070B12),
    );

    var y = top;
    if (title.isNotEmpty) {
      titlePainter.paint(canvas, Offset((width - titlePainter.width) / 2, y));
      y += titlePainter.height + gap;
    }
    if (caption.isNotEmpty) {
      captionPainter.paint(canvas, Offset((width - captionPainter.width) / 2, y));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) throw StateError('Could not create title overlay.');

    final temp = await getTemporaryDirectory();
    final file = File(
      '${temp.path}${Platform.pathSeparator}depthvibe_title_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file;
  }

  String _audioTempo(double speed) {
    if (speed < 0.5) {
      return 'atempo=0.5,atempo=${(speed / 0.5).toStringAsFixed(3)}';
    }
    return 'atempo=${speed.toStringAsFixed(3)}';
  }

  String _seconds(int milliseconds) => (milliseconds / 1000).toStringAsFixed(3);

  String _quote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";
}
