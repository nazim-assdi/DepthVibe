import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

typedef PreviewFrameDecoder = Future<File?> Function();

class PreviewFrameCacheStats {
  const PreviewFrameCacheStats({
    required this.cachedFrames,
    required this.cachedBytes,
    required this.activeDecodes,
    required this.pendingDecodes,
    required this.cacheHits,
    required this.droppedRequests,
    required this.averageDecodeMs,
    required this.lastDecodeMs,
    required this.effectivePreviewWidth,
    required this.effectivePreviewFrameRate,
  });

  final int cachedFrames;
  final int cachedBytes;
  final int activeDecodes;
  final int pendingDecodes;
  final int cacheHits;
  final int droppedRequests;
  final double averageDecodeMs;
  final int lastDecodeMs;
  final int effectivePreviewWidth;
  final int effectivePreviewFrameRate;
}

/// A bounded, latest-frame-wins scheduler for compositor preview decoding.
///
/// A new playhead request replaces an older queued request for the same
/// timeline lane. Identical frame requests share the same Future, while
/// concurrent native decodes are capped to protect CPU and memory.
class PreviewFrameService {
  PreviewFrameService({
    int maxConcurrentDecodes = 1,
    this.maxCachedFrames = 120,
    this.maxCacheBytes = 96 * 1024 * 1024,
  }) : _maxConcurrentDecodes = maxConcurrentDecodes.clamp(1, 3).toInt();

  final int maxCachedFrames;
  final int maxCacheBytes;

  int _maxConcurrentDecodes;
  int _activeCount = 0;
  int _cachedBytes = 0;
  int _cacheHits = 0;
  int _droppedRequests = 0;
  bool _disposed = false;
  int _preferredPreviewWidth = 640;
  int _preferredPreviewFrameRate = 24;
  int _effectivePreviewWidth = 640;
  int _effectivePreviewFrameRate = 24;
  int _slowDecodeStreak = 0;
  int _fastDecodeStreak = 0;
  int _completedDecodes = 0;
  int _lastDecodeMs = 0;
  double _averageDecodeMs = 0;

  final LinkedHashMap<String, _PreviewFrameCacheEntry> _cache =
      LinkedHashMap<String, _PreviewFrameCacheEntry>();
  final LinkedHashMap<String, _PendingPreviewFrame> _pending =
      LinkedHashMap<String, _PendingPreviewFrame>();
  final Map<String, _PendingPreviewFrame> _pendingByLane = {};
  final Map<String, _PendingPreviewFrame> _pendingByKey = {};
  final Map<String, Future<File?>> _activeByKey = {};
  final Map<String, int> _latestRequestTokenByLane = {};

  int get maxConcurrentDecodes => _maxConcurrentDecodes;
  int get effectivePreviewWidth => _effectivePreviewWidth;
  int get effectivePreviewFrameRate => _effectivePreviewFrameRate;

  void configurePreviewProfile({
    required int width,
    required int frameRate,
  }) {
    final nextWidth = width.clamp(320, 1920).toInt();
    final nextFrameRate = frameRate.clamp(12, 60).toInt();
    if (_preferredPreviewWidth == nextWidth &&
        _preferredPreviewFrameRate == nextFrameRate) {
      return;
    }
    _preferredPreviewWidth = nextWidth;
    _preferredPreviewFrameRate = nextFrameRate;
    _effectivePreviewWidth = nextWidth;
    _effectivePreviewFrameRate = nextFrameRate;
    _slowDecodeStreak = 0;
    _fastDecodeStreak = 0;
  }

  /// Feed Flutter build+raster time into the same adaptive quality governor.
  void recordUiFrameDuration(Duration duration) {
    _recordPerformanceSample(duration);
  }

  /// Feed measured native decode time back into the adaptive preview profile.
  /// Five slow frames lower quality; forty fast frames restore it gradually.
  void recordDecodeDuration(
    Duration duration, {
    int framesDecoded = 1,
  }) {
    _recordPerformanceSample(
      Duration(
        microseconds:
            (duration.inMicroseconds / framesDecoded.clamp(1, 1000000)).round(),
      ),
    );
  }

  void _recordPerformanceSample(Duration duration) {
    final milliseconds =
        (duration.inMicroseconds / 1000).clamp(0, 60000).toDouble();
    _lastDecodeMs = milliseconds.round();
    _completedDecodes++;
    _averageDecodeMs = _completedDecodes == 1
        ? milliseconds
        : (_averageDecodeMs * 0.8) + (milliseconds * 0.2);

    final frameBudgetMs = 1000 / _effectivePreviewFrameRate;
    if (milliseconds > frameBudgetMs * 1.25) {
      _slowDecodeStreak++;
      _fastDecodeStreak = 0;
    } else if (milliseconds < frameBudgetMs * 0.55) {
      _fastDecodeStreak++;
      _slowDecodeStreak = 0;
    } else {
      _slowDecodeStreak = 0;
      _fastDecodeStreak = 0;
    }

    if (_slowDecodeStreak >= 5) {
      _effectivePreviewWidth = (_effectivePreviewWidth * 0.8)
          .round()
          .clamp(320, _preferredPreviewWidth)
          .toInt();
      _effectivePreviewFrameRate = (_effectivePreviewFrameRate - 3)
          .clamp(12, _preferredPreviewFrameRate)
          .toInt();
      _slowDecodeStreak = 0;
      _fastDecodeStreak = 0;
    } else if (_fastDecodeStreak >= 40) {
      _effectivePreviewWidth = math.min(
        _preferredPreviewWidth,
        (_effectivePreviewWidth * 1.2).round(),
      ).toInt();
      _effectivePreviewFrameRate = math.min(
        _preferredPreviewFrameRate,
        _effectivePreviewFrameRate + 2,
      ).toInt();
      _fastDecodeStreak = 0;
    }
  }

  set maxConcurrentDecodes(int value) {
    _maxConcurrentDecodes = value.clamp(1, 3).toInt();
    _pump();
  }

  PreviewFrameCacheStats get stats => PreviewFrameCacheStats(
        cachedFrames: _cache.length,
        cachedBytes: _cachedBytes,
        activeDecodes: _activeCount,
        pendingDecodes: _pending.length,
        cacheHits: _cacheHits,
        droppedRequests: _droppedRequests,
        averageDecodeMs: _averageDecodeMs,
        lastDecodeMs: _lastDecodeMs,
        effectivePreviewWidth: _effectivePreviewWidth,
        effectivePreviewFrameRate: _effectivePreviewFrameRate,
      );

  Future<File?> requestFrame({
    required String laneId,
    required String cacheKey,
    required File cacheFile,
    required PreviewFrameDecoder decode,
    int decodedFrameCount = 1,
  }) async {
    if (_disposed) return null;
    final requestToken =
        (_latestRequestTokenByLane[laneId] ?? 0) + 1;
    _latestRequestTokenByLane[laneId] = requestToken;

    final inMemory = _cache.remove(cacheKey);
    if (inMemory != null) {
      if (await inMemory.file.exists()) {
        if (_latestRequestTokenByLane[laneId] != requestToken) {
          _droppedRequests++;
          return null;
        }
        _cache[cacheKey] = inMemory;
        _cacheHits++;
        return inMemory.file;
      }
      _cachedBytes = (_cachedBytes - inMemory.bytes).clamp(0, 1 << 62).toInt();
    }

    // Join active/queued work before reading disk: FFmpeg may have created
    // the destination but not finished writing it yet.
    final active = _activeByKey[cacheKey];
    if (active != null) return active;

    final queued = _pendingByKey[cacheKey];
    if (queued != null) return queued.completer.future;

    // The disk cache survives a widget rebuild and can be reused after the
    // in-memory LRU entry has been evicted.
    try {
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        if (_latestRequestTokenByLane[laneId] != requestToken) {
          _droppedRequests++;
          return null;
        }
        await _remember(cacheKey, cacheFile);
        _cacheHits++;
        return cacheFile;
      }
    } catch (_) {
      // A partial/stale cache file is treated as a cache miss and regenerated.
      try {
        if (await cacheFile.exists()) await cacheFile.delete();
      } catch (_) {}
    }

    // Drop requests whose disk lookup completed after a newer frame was
    // requested for the same layer. Without this token check, a slow cache
    // read could enqueue an old playhead frame after the newest frame.
    if (_latestRequestTokenByLane[laneId] != requestToken) {
      _droppedRequests++;
      return null;
    }

    // Another caller may have scheduled this frame while the disk-cache
    // lookup above was awaiting I/O. Join it instead of starting a duplicate.
    final activeAfterDiskCheck = _activeByKey[cacheKey];
    if (activeAfterDiskCheck != null) return activeAfterDiskCheck;
    final queuedAfterDiskCheck = _pendingByKey[cacheKey];
    if (queuedAfterDiskCheck != null) {
      return queuedAfterDiskCheck.completer.future;
    }

    final task = _PendingPreviewFrame(
      laneId: laneId,
      key: cacheKey,
      decode: decode,
      decodedFrameCount: decodedFrameCount,
    );

    // Keep only the newest requested frame for each video layer. This is the
    // key to avoiding a queue of obsolete frames when the user scrubs quickly.
    final previous = _pendingByLane.remove(laneId);
    if (previous != null) {
      _pending.remove(previous.key);
      _pendingByKey.remove(previous.key);
      if (!previous.completer.isCompleted) {
        previous.completer.complete(null);
      }
      _droppedRequests++;
    }

    _pending[cacheKey] = task;
    _pendingByKey[cacheKey] = task;
    _pendingByLane[laneId] = task;
    _pump();
    return task.completer.future;
  }

  void _pump() {
    if (_disposed) return;
    while (_activeCount < _maxConcurrentDecodes && _pending.isNotEmpty) {
      final entry = _pending.entries.first;
      _pending.remove(entry.key);
      final task = entry.value;
      _pendingByKey.remove(task.key);
      if (identical(_pendingByLane[task.laneId], task)) {
        _pendingByLane.remove(task.laneId);
      }
      _activeCount++;
      _activeByKey[task.key] = task.completer.future;
      unawaited(_run(task));
    }
  }

  Future<void> _run(_PendingPreviewFrame task) async {
    try {
      final decoded = await task.decode();
      File? result;
      if (!_disposed && decoded != null) {
        try {
          if (await decoded.exists() && await decoded.length() > 0) {
            await _remember(task.key, decoded);
            result = decoded;
          }
        } catch (_) {
          result = null;
        }
      }
      if (!task.completer.isCompleted) task.completer.complete(result);
    } catch (_) {
      // Preview failures are recoverable: preserve the previous frame and keep
      // the editor responsive rather than failing the whole composition.
      if (!task.completer.isCompleted) task.completer.complete(null);
    } finally {
      recordDecodeDuration(
        task.requestedAt.elapsed,
        framesDecoded: task.decodedFrameCount,
      );
      _activeByKey.remove(task.key);
      _activeCount = (_activeCount - 1).clamp(0, 1 << 30).toInt();
      _pump();
    }
  }

  Future<void> _remember(String key, File file) async {
    if (_disposed) return;
    int bytes = 0;
    try {
      bytes = await file.length();
    } catch (_) {
      return;
    }
    final previous = _cache.remove(key);
    if (previous != null) {
      _cachedBytes = (_cachedBytes - previous.bytes).clamp(0, 1 << 62).toInt();
    }
    _cache[key] = _PreviewFrameCacheEntry(file, bytes);
    _cachedBytes += bytes;

    while (_cache.isNotEmpty &&
        (_cache.length > maxCachedFrames || _cachedBytes > maxCacheBytes)) {
      final oldestKey = _cache.keys.first;
      // A single oversized frame is still useful; keep it as the only entry.
      if (_cache.length == 1) break;
      final oldest = _cache.remove(oldestKey)!;
      _cachedBytes = (_cachedBytes - oldest.bytes).clamp(0, 1 << 62).toInt();
      // Keep the disk frame: a visible Image.file or the workspace's last
      // displayed frame may still reference it. Disk trimming is handled by
      // the preview-cache janitor, which knows the currently pinned frames.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final task in _pending.values) {
      if (!task.completer.isCompleted) task.completer.complete(null);
    }
    _pending.clear();
    _pendingByLane.clear();
    _pendingByKey.clear();
    _latestRequestTokenByLane.clear();
    _cache.clear();
    _cachedBytes = 0;
  }
}

class _PreviewFrameCacheEntry {
  const _PreviewFrameCacheEntry(this.file, this.bytes);

  final File file;
  final int bytes;
}

class _PendingPreviewFrame {
  _PendingPreviewFrame({
    required this.laneId,
    required this.key,
    required this.decode,
    required this.decodedFrameCount,
  }) : requestedAt = Stopwatch()..start();

  final String laneId;
  final String key;
  final PreviewFrameDecoder decode;
  final int decodedFrameCount;
  final Stopwatch requestedAt;
  final Completer<File?> completer = Completer<File?>();
}
