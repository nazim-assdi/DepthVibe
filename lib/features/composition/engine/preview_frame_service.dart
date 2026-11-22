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

  /// Feed measured native decode time back into the adaptive preview profile.
  /// Five slow frames lower quality; forty fast frames restore it gradually.
  void recordDecodeDuration(Duration duration) {
    final milliseconds = duration.inMilliseconds.clamp(0, 60000).toInt();
    _lastDecodeMs = milliseconds;
    _completedDecodes++;
    _averageDecodeMs = _completedDecodes == 1
        ? milliseconds.toDouble()
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
      _effectivePreviewWidth =
          (_effectivePreviewWidth * 0.8).round().clamp(320, _preferredPreviewWidth);
      _effectivePreviewFrameRate =
          (_effectivePreviewFrameRate - 3).clamp(12, _preferredPreviewFrameRate);
      _slowDecodeStreak = 0;
      _fastDecodeStreak = 0;
    } else if (_fastDecodeStreak >= 40) {
      _effectivePreviewWidth = math.min(
        _preferredPreviewWidth,
        (_effectivePreviewWidth * 1.2).round(),
      );
      _effectivePreviewFrameRate = math.min(
        _preferredPreviewFrameRate,
        _effectivePreviewFrameRate + 2,
      );
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
  }) async {
    if (_disposed) return null;

    final inMemory = _cache.remove(cacheKey);
    if (inMemory != null) {
      if (await inMemory.file.exists()) {
        _cache[cacheKey] = inMemory;
        _cacheHits++;
        return inMemory.file;
      }
      _cachedBytes = (_cachedBytes - inMemory.bytes).clamp(0, 1 << 62).toInt();
    }

    // The disk cache survives a widget rebuild and can be reused after the
    // in-memory LRU entry has been evicted.
    try {
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
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

    final active = _activeByKey[cacheKey];
    if (active != null) return active;

    final queued = _pendingByKey[cacheKey];
    if (queued != null) return queued.completer.future;

    final task = _PendingPreviewFrame(
      laneId: laneId,
      key: cacheKey,
      decode: decode,
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
    final stopwatch = Stopwatch()..start();
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
      stopwatch.stop();
      recordDecodeDuration(stopwatch.elapsed);
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
      try {
        if (oldest.file.path != file.path && await oldest.file.exists()) {
          await oldest.file.delete();
        }
      } catch (_) {
        // A cache eviction failure must not interrupt preview playback.
      }
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
  });

  final String laneId;
  final String key;
  final PreviewFrameDecoder decode;
  final Completer<File?> completer = Completer<File?>();
}
