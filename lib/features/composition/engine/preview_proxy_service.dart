import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';

typedef PreviewProxyBuilder = Future<bool> Function({
  required String sourcePath,
  required File outputFile,
  required int width,
  required int frameRate,
});

/// Creates disposable, low-resolution, video-only proxies for realtime preview.
///
/// Original media paths are never replaced in the composition. A proxy is
/// selected only after a complete file has been atomically published; until
/// then the compositor continues decoding the original source.
class PreviewProxyService {
  PreviewProxyService({
    Directory? cacheDirectory,
    PreviewProxyBuilder? builder,
    this.minimumSourceBytes = 24 * 1024 * 1024,
    this.maxCacheBytes = 2 * 1024 * 1024 * 1024,
    Duration generationTimeout = const Duration(minutes: 21),
  })  : _providedCacheDirectory = cacheDirectory,
        _builder = builder ?? _buildWithFfmpeg,
        _generationTimeout = generationTimeout;

  final Directory? _providedCacheDirectory;
  final PreviewProxyBuilder _builder;
  final int minimumSourceBytes;
  final int maxCacheBytes;
  final Duration _generationTimeout;

  final Map<String, Future<_PreviewProxyDescriptor>> _descriptorJobs = {};
  final Map<String, Future<File?>> _generationJobs = {};
  final Map<String, Future<File?>> _requestJobs = {};
  final Map<String, DateTime> _recentlyUsed = {};
  Future<void> _generationTail = Future<void>.value();
  Directory? _resolvedCacheDirectory;
  bool _disposed = false;
  int _successfulGenerations = 0;

  int get pendingGenerations => _generationJobs.length;
  int get successfulGenerations => _successfulGenerations;

  Future<Directory> _cacheDirectory() async {
    final existing = _resolvedCacheDirectory;
    if (existing != null) return existing;
    final directory = _providedCacheDirectory ??
        Directory(
          (await getTemporaryDirectory()).path +
              Platform.pathSeparator +
              'DepthVibe' +
              Platform.pathSeparator +
              'PreviewProxies',
        );
    await directory.create(recursive: true);
    _resolvedCacheDirectory = directory;
    return directory;
  }

  Future<_PreviewProxyDescriptor> _descriptor({
    required String sourcePath,
    required int width,
    required int frameRate,
  }) {
    final normalizedWidth = width.clamp(320, 1920).toInt();
    final normalizedFrameRate = frameRate.clamp(12, 60).toInt();
    final requestKey =
        '$sourcePath|$normalizedWidth|$normalizedFrameRate';
    return _descriptorJobs.putIfAbsent(requestKey, () async {
      final source = File(sourcePath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        throw FileSystemException('Preview proxy source is unavailable', sourcePath);
      }
      final directory = await _cacheDirectory();
      final key = _stableHash(
        '$sourcePath|${stat.size}|${stat.modified.microsecondsSinceEpoch}|'
        '$normalizedWidth|$normalizedFrameRate|proxy-v1',
      );
      return _PreviewProxyDescriptor(
        key: key,
        sourcePath: sourcePath,
        sourceBytes: stat.size,
        width: normalizedWidth,
        frameRate: normalizedFrameRate,
        output: File(
          directory.path +
              Platform.pathSeparator +
              'dvproxy_$key.mp4',
        ),
      );
    });
  }

  /// Returns the completed proxy, or null while it is missing/building.
  /// This method never waits for a transcode.
  Future<File?> findCachedProxy({
    required String sourcePath,
    required int width,
    required int frameRate,
  }) async {
    if (_disposed) return null;
    try {
      final descriptor = await _descriptor(
        sourcePath: sourcePath,
        width: width,
        frameRate: frameRate,
      );
      final file = descriptor.output;
      if (!await file.exists() || await file.length() <= 0) return null;
      _recentlyUsed[file.path] = DateTime.now();
      _recentlyUsed.removeWhere(
        (_, lastUsed) => DateTime.now().difference(lastUsed) >
            const Duration(minutes: 30),
      );
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Queues one proxy generation. Duplicate requests share the same Future;
  /// only one full-file transcode is allowed at a time on CPU-limited systems.
  Future<File?> queueProxy({
    required String sourcePath,
    required int width,
    required int frameRate,
  }) {
    if (_disposed) return Future<File?>.value(null);
    final requestKey =
        '$sourcePath|${width.clamp(320, 1920)}|${frameRate.clamp(12, 60)}';
    return _requestJobs.putIfAbsent(requestKey, () async {
      try {
        final descriptor = await _descriptor(
          sourcePath: sourcePath,
          width: width,
          frameRate: frameRate,
        );
        if (_disposed || descriptor.sourceBytes < minimumSourceBytes) {
          return null;
        }
        if (await descriptor.output.exists() &&
            await descriptor.output.length() > 0) {
          return descriptor.output;
        }
        final existing = _generationJobs[descriptor.key];
        if (existing != null) return existing;

        final partial = File(descriptor.output.path + '.part.mp4');
        final job = _generationTail.then((_) async {
          if (_disposed) return null;
          if (await descriptor.output.exists() &&
              await descriptor.output.length() > 0) {
            return descriptor.output;
          }
          try {
            if (await partial.exists()) await partial.delete();
            final success = await _builder(
              sourcePath: descriptor.sourcePath,
              outputFile: partial,
              width: descriptor.width,
              frameRate: descriptor.frameRate,
            ).timeout(_generationTimeout);
            if (!success ||
                !await partial.exists() ||
                await partial.length() <= 0) {
              return null;
            }
            if (await descriptor.output.exists()) {
              await descriptor.output.delete();
            }
            final ready = await partial.rename(descriptor.output.path);
            _successfulGenerations++;
            unawaited(_trimCache(keep: ready));
            return ready;
          } catch (_) {
            return null;
          } finally {
            try {
              if (await partial.exists()) await partial.delete();
            } catch (_) {}
          }
        });

        _generationTail = job.then<void>((_) {}, onError: (_) {});
        _generationJobs[descriptor.key] = job;
        return await job.whenComplete(() {
          if (identical(_generationJobs[descriptor.key], job)) {
            _generationJobs.remove(descriptor.key);
          }
        });
      } catch (_) {
        return null;
      }
    }).whenComplete(() {
      _requestJobs.remove(requestKey);
    });
  }

  Future<void> _trimCache({required File keep}) async {
    try {
      final directory = await _cacheDirectory();
      final entries = <({File file, int size, DateTime modified})>[];
      var total = 0;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.mp4')) continue;
        try {
          final stat = await entity.stat();
          total += stat.size;
          entries.add((file: entity, size: stat.size, modified: stat.modified));
        } catch (_) {}
      }
      if (total <= maxCacheBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      final targetBytes = (maxCacheBytes * 0.8).round();
      for (final entry in entries) {
        if (total <= targetBytes) break;
        if (entry.file.path == keep.path) continue;
        final lastUsed = _recentlyUsed[entry.file.path];
        if (lastUsed != null &&
            DateTime.now().difference(lastUsed) < const Duration(minutes: 10)) {
          continue;
        }
        try {
          if (await entry.file.exists()) {
            await entry.file.delete();
            total -= entry.size;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<bool> _buildWithFfmpeg({
    required String sourcePath,
    required File outputFile,
    required int width,
    required int frameRate,
  }) async {
    await outputFile.parent.create(recursive: true);
    final command = '-hide_banner -loglevel error -y '
        '-threads 1 -i ${_quoteFfmpeg(sourcePath)} '
        '-map 0:v:0 -an -sn -dn '
        '-vf "fps=$frameRate,'
        'scale=$width:$width:force_original_aspect_ratio=decrease:'
        'force_divisible_by=2:flags=fast_bilinear" '
        '-c:v mpeg4 -q:v 4 -pix_fmt yuv420p '
        '-movflags +faststart '
        '${_quoteFfmpeg(outputFile.path)}';

    try {
      final session = await FFmpegKit.executeAsync(command).timeout(
        const Duration(minutes: 20),
        onTimeout: () {
          final sessions = FFmpegKit.getFFmpegSessions()
              .where((item) => item.getCommand().contains(outputFile.path))
              .toList();
          for (final item in sessions) {
            item.cancel();
          }
          throw TimeoutException('Preview proxy generation timed out.');
        },
      );
      return ReturnCode.isSuccess(session.getReturnCode()) &&
          await outputFile.exists() &&
          await outputFile.length() > 0;
    } catch (_) {
      final sessions = FFmpegKit.getFFmpegSessions()
          .where((item) => item.getCommand().contains(outputFile.path))
          .toList();
      for (final item in sessions) {
        item.cancel();
      }
      return false;
    }
  }

  static String _quoteFfmpeg(String value) =>
      "'" + value.replaceAll("'", "'\\''") + "'";

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  void dispose() {
    _disposed = true;
    _descriptorJobs.clear();
    _requestJobs.clear();
    _recentlyUsed.clear();
  }
}

class _PreviewProxyDescriptor {
  const _PreviewProxyDescriptor({
    required this.key,
    required this.sourcePath,
    required this.sourceBytes,
    required this.width,
    required this.frameRate,
    required this.output,
  });

  final String key;
  final String sourcePath;
  final int sourceBytes;
  final int width;
  final int frameRate;
  final File output;
}
