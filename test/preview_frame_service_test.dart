import 'dart:async';
import 'dart:io';

import 'package:depthvibe/features/composition/engine/preview_frame_service.dart';
import 'package:flutter_test/flutter_test.dart';

Future<File> _writeFrame(Directory directory, String name) async {
  final file = File('${directory.path}/$name.jpg');
  await file.writeAsBytes(List<int>.filled(256, 7));
  return file;
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('depthvibe-preview-test-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('identical in-flight frame requests share one native decode', () async {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    final gate = Completer<File?>();
    var decodeCalls = 0;
    final cacheFile = File('${directory.path}/shared.jpg');

    Future<File?> request() => service.requestFrame(
          laneId: 'video-a',
          cacheKey: 'same-frame',
          cacheFile: cacheFile,
          decode: () {
            decodeCalls++;
            return gate.future;
          },
        );

    final first = request();
    await Future<void>.delayed(Duration.zero);
    final second = request();
    await Future<void>.delayed(Duration.zero);

    expect(decodeCalls, 1);
    final frame = await _writeFrame(directory, 'shared');
    gate.complete(frame);

    expect(await first, frame);
    expect(await second, frame);
    expect(service.stats.activeDecodes, 0);
    expect(service.stats.cachedFrames, 1);
    service.dispose();
  });

  test('visible requests run before queued background prefetch frames', () async {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    final blockerGate = Completer<File?>();
    final blockerStarted = Completer<void>();
    final order = <String>[];

    final blocker = service.requestFrame(
      laneId: 'blocker',
      cacheKey: 'blocker-frame',
      cacheFile: File('${directory.path}/blocker.jpg'),
      decode: () {
        if (!blockerStarted.isCompleted) blockerStarted.complete();
        return blockerGate.future;
      },
    );
    await blockerStarted.future;

    final background = service.requestFrame(
      laneId: 'video-b',
      cacheKey: 'background-frame',
      cacheFile: File('${directory.path}/background.jpg'),
      isPrefetch: true,
      decode: () async {
        order.add('background');
        return _writeFrame(directory, 'background');
      },
    );
    final visible = service.requestFrame(
      laneId: 'video-c',
      cacheKey: 'visible-frame',
      cacheFile: File('${directory.path}/visible.jpg'),
      decode: () async {
        order.add('visible');
        return _writeFrame(directory, 'visible');
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.stats.pendingDecodes, 2);
    blockerGate.complete(await _writeFrame(directory, 'blocker'));
    await blocker;
    await visible;
    await background;

    expect(order, <String>['visible', 'background']);
    expect(service.stats.pendingDecodes, 0);
    service.dispose();
  });

  test('foreground requests promote matching queued prefetch frames', () async {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    final blockerGate = Completer<File?>();
    final blockerStarted = Completer<void>();
    final order = <String>[];

    final blocker = service.requestFrame(
      laneId: 'blocker',
      cacheKey: 'blocker-frame',
      cacheFile: File('${directory.path}/blocker-2.jpg'),
      decode: () {
        if (!blockerStarted.isCompleted) blockerStarted.complete();
        return blockerGate.future;
      },
    );
    await blockerStarted.future;

    final prefetch = service.requestFrame(
      laneId: 'video-b',
      cacheKey: 'shared-frame',
      cacheFile: File('${directory.path}/shared-frame.jpg'),
      isPrefetch: true,
      decode: () async {
        order.add('shared');
        return _writeFrame(directory, 'shared-frame');
      },
    );
    // Let the speculative request complete its asynchronous disk-cache
    // lookup and enter the background queue before the visible request joins
    // it. This makes the promotion scenario deterministic.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.stats.pendingDecodes, 1);

    final visible = service.requestFrame(
      laneId: 'video-b',
      cacheKey: 'shared-frame',
      cacheFile: File('${directory.path}/shared-frame.jpg'),
      decode: () async {
        order.add('duplicate-visible-decode');
        return _writeFrame(directory, 'shared-frame-visible');
      },
    );
    final otherBackground = service.requestFrame(
      laneId: 'video-c',
      cacheKey: 'other-background-frame',
      cacheFile: File('${directory.path}/other-background.jpg'),
      isPrefetch: true,
      decode: () async {
        order.add('other-background');
        return _writeFrame(directory, 'other-background');
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.stats.pendingDecodes, 2);
    blockerGate.complete(await _writeFrame(directory, 'blocker-2'));
    await blocker;
    await prefetch;
    await visible;
    await otherBackground;

    expect(order, <String>['shared', 'other-background']);
    service.dispose();
  });

  test('new playhead request drops stale queued frames for the same layer', () async {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    final activeGate = Completer<File?>();
    final activeStarted = Completer<void>();
    var newestDecodeCalls = 0;

    final active = service.requestFrame(
      laneId: 'video-a',
      cacheKey: 'frame-0',
      cacheFile: File('${directory.path}/frame-0.jpg'),
      decode: () {
        if (!activeStarted.isCompleted) activeStarted.complete();
        return activeGate.future;
      },
    );
    await activeStarted.future;
    expect(service.stats.activeDecodes, 1);

    final stale = service.requestFrame(
      laneId: 'video-a',
      cacheKey: 'frame-1',
      cacheFile: File('${directory.path}/frame-1.jpg'),
      decode: () async => _writeFrame(directory, 'frame-1'),
    );
    final newest = service.requestFrame(
      laneId: 'video-a',
      cacheKey: 'frame-2',
      cacheFile: File('${directory.path}/frame-2.jpg'),
      decode: () async {
        newestDecodeCalls++;
        return _writeFrame(directory, 'frame-2');
      },
    );

    // The request token is checked after asynchronous cache-file lookup,
    // so wait for the stale request to finish before asserting the counter.
    expect(await stale, isNull);
    expect(service.stats.droppedRequests, 1);

    final firstFrame = await _writeFrame(directory, 'frame-0');
    activeGate.complete(firstFrame);
    expect(await active, firstFrame);

    final newestFrame = await newest;
    expect(newestFrame?.path, contains('frame-2.jpg'));
    expect(newestDecodeCalls, 1);
    expect(service.stats.pendingDecodes, 0);
    service.dispose();
  });

  test('scheduler queue latency is recorded separately from decode time', () async {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    final firstGate = Completer<File?>();
    final firstStarted = Completer<void>();

    final first = service.requestFrame(
      laneId: 'video-a',
      cacheKey: 'slow-first',
      cacheFile: File('${directory.path}/slow-first.jpg'),
      decode: () {
        if (!firstStarted.isCompleted) firstStarted.complete();
        return firstGate.future;
      },
    );
    await firstStarted.future;

    final second = service.requestFrame(
      laneId: 'video-b',
      cacheKey: 'queued-second',
      cacheFile: File('${directory.path}/queued-second.jpg'),
      decode: () async => _writeFrame(directory, 'queued-second'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 35));
    firstGate.complete(await _writeFrame(directory, 'slow-first'));
    expect(await first, isNotNull);
    expect(await second, isNotNull);
    expect(service.stats.lastQueueWaitMs, greaterThanOrEqualTo(25));
    expect(service.stats.lastDecodeMs, lessThan(service.stats.lastQueueWaitMs));
    service.dispose();
  });

  test('LRU cache evicts old files after the configured frame limit', () async {
    final service = PreviewFrameService(
      maxConcurrentDecodes: 1,
      maxCachedFrames: 1,
      maxCacheBytes: 1024,
    );

    final first = await service.requestFrame(
      laneId: 'video-a',
      cacheKey: 'frame-1',
      cacheFile: File('${directory.path}/first.jpg'),
      decode: () async => _writeFrame(directory, 'first'),
    );
    final second = await service.requestFrame(
      laneId: 'video-a',
      cacheKey: 'frame-2',
      cacheFile: File('${directory.path}/second.jpg'),
      decode: () async => _writeFrame(directory, 'second'),
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    // The in-memory LRU forgets the older frame, but the disk cache keeps
    // it available for a later seek and a workspace rebuild.
    expect(await first!.exists(), isTrue);
    expect(await second!.exists(), isTrue);
    expect(service.stats.cachedFrames, 1);
    expect(service.stats.cachedBytes, 256);
    service.dispose();
  });

  test('fast UI frames cannot hide a slow native video decoder', () {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    service.configurePreviewProfile(width: 960, frameRate: 30);

    for (var index = 0; index < 5; index++) {
      service.recordUiFrameDuration(const Duration(milliseconds: 1));
      service.recordDecodeDuration(const Duration(milliseconds: 120));
    }

    expect(service.effectivePreviewWidth, 768);
    expect(service.effectivePreviewFrameRate, 27);
    expect(service.stats.lastDecodeMs, 120);
    expect(service.stats.lastUiFrameMs, 1);
    expect(service.stats.averageDecodeMs, 120);
    expect(service.stats.averageUiFrameMs, 1);
    service.dispose();
  });

  test('queue backlog lowers preview load without inflating decoder time', () {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    service.configurePreviewProfile(width: 960, frameRate: 30);

    for (var index = 0; index < 5; index++) {
      service.recordQueueWaitDuration(const Duration(milliseconds: 100));
      service.recordDecodeDuration(const Duration(milliseconds: 1));
    }

    expect(service.stats.lastQueueWaitMs, 100);
    expect(service.stats.averageQueueWaitMs, 100);
    expect(service.stats.lastDecodeMs, 1);
    expect(service.effectivePreviewWidth, 768);
    expect(service.effectivePreviewFrameRate, 27);
    service.dispose();
  });

  test('slow Flutter raster frames lower preview quality even with fast decode', () {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    service.configurePreviewProfile(width: 960, frameRate: 30);

    for (var index = 0; index < 5; index++) {
      service.recordDecodeDuration(const Duration(milliseconds: 1));
      service.recordUiFrameDuration(const Duration(milliseconds: 120));
    }

    expect(service.effectivePreviewWidth, 768);
    expect(service.effectivePreviewFrameRate, 27);
    expect(service.stats.lastDecodeMs, 1);
    expect(service.stats.lastUiFrameMs, 120);
    service.dispose();
  });

  test('one-second batch decode time is normalized by its frame count', () {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    service.configurePreviewProfile(width: 960, frameRate: 30);

    for (var index = 0; index < 5; index++) {
      service.recordDecodeDuration(
        const Duration(milliseconds: 2160),
        framesDecoded: 18,
      );
    }

    // 2.16 seconds for 18 frames is 120 ms per frame, which is slower
    // than the 30 FPS budget and must lower the preview profile.
    expect(service.stats.lastDecodeMs, 120);
    expect(service.effectivePreviewWidth, 768);
    expect(service.effectivePreviewFrameRate, 27);
    service.dispose();
  });

  test('slow decodes lower preview load and sustained fast decodes recover it', () {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    service.configurePreviewProfile(width: 960, frameRate: 30);

    expect(service.effectivePreviewWidth, 960);
    expect(service.effectivePreviewFrameRate, 30);

    for (var index = 0; index < 5; index++) {
      service.recordDecodeDuration(const Duration(milliseconds: 120));
    }
    expect(service.effectivePreviewWidth, 768);
    expect(service.effectivePreviewFrameRate, 27);

    for (var index = 0; index < 40; index++) {
      service.recordDecodeDuration(const Duration(milliseconds: 1));
    }
    expect(service.effectivePreviewWidth, greaterThan(768));
    expect(service.effectivePreviewFrameRate, greaterThan(27));

    service.configurePreviewProfile(width: 480, frameRate: 18);
    expect(service.effectivePreviewWidth, 480);
    expect(service.effectivePreviewFrameRate, 18);
    service.dispose();
  });

  test('decoder concurrency can be changed without exceeding the cap', () {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);

    service.maxConcurrentDecodes = 2;
    expect(service.maxConcurrentDecodes, 2);

    service.maxConcurrentDecodes = 10;
    expect(service.maxConcurrentDecodes, 3);

    service.maxConcurrentDecodes = 0;
    expect(service.maxConcurrentDecodes, 1);
    service.dispose();
  });
}
