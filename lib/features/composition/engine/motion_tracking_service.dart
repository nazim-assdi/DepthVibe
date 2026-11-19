import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/composition_models.dart';
import 'planar_homography.dart';

class MotionTrackingResult {
  const MotionTrackingResult({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.samples,
  });

  final int sourceWidth;
  final int sourceHeight;
  final List<MotionTrackSample> samples;
}

/// Lightweight translation tracking with FFmpeg template matching.
/// It is not optical flow, planar tracking or a 3D camera solve.
class MotionTrackingService {
  const MotionTrackingService();

  /// Estimates a planar perspective transform from matched feature points.
  ///
  /// The current on-device tracker still produces translation samples; this
  /// entry point is for feature-match providers that can supply four or more
  /// stable point correspondences per frame.
  HomographyFit estimatePlanarHomography({
    required List<Vector2> sourcePoints,
    required List<Vector2> destinationPoints,
  }) {
    return const PlanarHomographyEstimator().estimate(
      source: sourcePoints,
      destination: destinationPoints,
    );
  }

  Future<MotionTrackingResult> track({
    required String sourcePath,
    required int left,
    required int top,
    required int width,
    required int height,
    double threshold = 0.30,
    double samplesPerSecond = 10,
    int sourceStartMs = 0,
  }) async {
    if (!await File(sourcePath).exists()) {
      throw StateError('Tracking source video does not exist.');
    }
    if (width < 4 || height < 4 || left < 0 || top < 0) {
      throw ArgumentError('Select a tracking region at least 4×4 pixels in size.');
    }
    if (threshold < 0.01 || threshold > 0.99 ||
        samplesPerSecond < 1 || samplesPerSecond > 30) {
      throw ArgumentError('Tracking threshold or sample rate is outside supported limits.');
    }

    final info = await _probe(
      '-v error -select_streams v:0 -show_entries stream=width,height '
      '-of csv=s=x:p=0 ' + _quote(sourcePath),
    );
    final dimensions = RegExp(r'(\d+)x(\d+)').firstMatch(info);
    if (dimensions == null) {
      throw StateError('FFprobe could not read source video dimensions.');
    }
    final sourceWidth = int.parse(dimensions.group(1)!);
    final sourceHeight = int.parse(dimensions.group(2)!);
    if (left + width > sourceWidth || top + height > sourceHeight) {
      throw ArgumentError(
        'Tracking region exceeds source bounds (' +
        sourceWidth.toString() + '×' + sourceHeight.toString() + ').',
      );
    }

    final temp = await getTemporaryDirectory();
    final templatePath = temp.path + Platform.pathSeparator +
        'depthvibe-track-' + DateTime.now().microsecondsSinceEpoch.toString() + '.pgm';
    final template = File(templatePath);

    try {
      final extractionCommand = '-y -ss ' +
          (sourceStartMs / 1000).toStringAsFixed(3) +
          ' -i ' + _quote(sourcePath) +
          ' -frames:v 1 -vf ' + _quote(
            'crop=' + width.toString() + ':' + height.toString() + ':' +
            left.toString() + ':' + top.toString() + ',format=gray',
          ) +
          ' -an -f image2 -c:v pgm ' + _quote(templatePath);
      await _runFfmpeg(extractionCommand);
      if (!await template.exists() || await template.length() < 16) {
        throw StateError('Could not extract a grayscale tracking template.');
      }

      final graph = 'movie=' + _filterPath(sourcePath) +
          ',fps=' + samplesPerSecond.toStringAsFixed(2) +
          ',find_rect=object=' + _filterPath(templatePath) +
          ':threshold=' + threshold.toStringAsFixed(3) +
          ':mipmaps=3';
      final command = '-v error -f lavfi -i ' + _quote(graph) +
          ' -show_entries frame=pkt_pts_time:frame_tags='
          'lavfi.rect.x,lavfi.rect.y,lavfi.rect.w,lavfi.rect.h,lavfi.rect.score '
          '-of csv=p=0';
      final output = await _probe(command);
      final samples = _parseSamples(output);
      if (samples.length < 2) {
        throw StateError(
          'Tracking found fewer than two matching frames. Try a larger region or a different threshold.',
        );
      }
      return MotionTrackingResult(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        samples: List.unmodifiable(samples),
      );
    } finally {
      if (await template.exists()) await template.delete();
    }
  }

  List<MotionTrackSample> _parseSamples(String output) {
    final samples = <MotionTrackSample>[];
    for (final line in output.split(RegExp(r'[\r\n]+'))) {
      final values = line.trim().split(',');
      if (values.length < 6) continue;
      final parsed = values.take(6).map(
        (value) => double.tryParse(value.trim().replaceAll('"', '')),
      ).toList();
      if (parsed.any((value) => value == null || !value.isFinite)) continue;

      final timeSeconds = parsed[0]!;
      final x = parsed[1]!;
      final y = parsed[2]!;
      final rectWidth = parsed[3]!;
      final rectHeight = parsed[4]!;
      final score = parsed[5]!;
      samples.add(MotionTrackSample(
        timeMs: (timeSeconds * 1000).round(),
        x: x + rectWidth / 2,
        y: y + rectHeight / 2,
        score: score,
      ));
    }
    samples.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return samples;
  }

  Future<String> _probe(String command) async {
    final session = await FFprobeKit.executeAsync(command);
    if (!ReturnCode.isSuccess(session.getReturnCode())) {
      throw StateError(
        session.getFailStackTrace() ??
            session.getOutput() ??
            'FFprobe failed while preparing object tracking.',
      );
    }
    return session.getOutput() ?? '';
  }

  Future<void> _runFfmpeg(String command) async {
    final completer = Completer<void>();
    final starting = FFmpegKit.executeAsync(
      command,
      onComplete: (session) {
        if (ReturnCode.isSuccess(session.getReturnCode())) {
          if (!completer.isCompleted) completer.complete();
        } else if (!completer.isCompleted) {
          completer.completeError(
            StateError(session.getFailStackTrace() ?? 'Tracking template extraction failed.'),
          );
        }
      },
    );
    unawaited(starting.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    ));
    await completer.future.timeout(const Duration(minutes: 2));
  }

  String _quote(String value) =>
      '"' + value.replaceAll('"', r'\"') + '"';

  String _filterPath(String value) {
    final normalized = value.replaceAll(r'\', '/');
    final escaped = normalized
        .replaceAll("'", r"\'")
        .replaceAll(':', r'\:')
        .replaceAll(',', r'\,');
    return "'" + escaped + "'";
  }
}
