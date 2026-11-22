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

  test('new playhead request drops stale queued frames for the same layer', () async {
    final service = PreviewFrameService(maxConcurrentDecodes: 1);
    final activeGate = Completer<File?>();
    var newestDecodeCalls = 0;

    final active = service.requestFrame(
      laneId: 'video-a',
      cacheKey: 'frame-0',
      cacheFile: File('${directory.path}/frame-0.jpg'),
      decode: () => activeGate.future,
    );
    await Future<void>.delayed(Duration.zero);

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

    expect(service.stats.droppedRequests, 1);
    expect(await stale, isNull);

    final firstFrame = await _writeFrame(directory, 'frame-0');
    activeGate.complete(firstFrame);
    expect(await active, firstFrame);

    final newestFrame = await newest;
    expect(newestFrame?.path, contains('frame-2.jpg'));
    expect(newestDecodeCalls, 1);
    expect(service.stats.pendingDecodes, 0);
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
    expect(await first!.exists(), isFalse);
    expect(await second!.exists(), isTrue);
    expect(service.stats.cachedFrames, 1);
    expect(service.stats.cachedBytes, 256);
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
