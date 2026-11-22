import 'dart:async';
import 'dart:io';

import 'package:depthvibe/features/composition/engine/preview_proxy_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('depthvibe-proxy-test-');
    cache = Directory('${root.path}/cache');
    await cache.create(recursive: true);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> source(String name, {List<int> bytes = const [1, 2, 3]}) async {
    final file = File('${root.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  test('duplicate proxy requests share one transcode and preserve source', () async {
    final input = await source('original.mov', bytes: List<int>.filled(128, 9));
    final gate = Completer<void>();
    final started = Completer<void>();
    var buildCalls = 0;

    final service = PreviewProxyService(
      cacheDirectory: cache,
      minimumSourceBytes: 0,
      builder: ({
        required sourcePath,
        required outputFile,
        required width,
        required frameRate,
      }) async {
        buildCalls++;
        if (!started.isCompleted) started.complete();
        await gate.future;
        await outputFile.writeAsBytes([7, 8, 9], flush: true);
        return true;
      },
    );

    final first = service.queueProxy(
      sourcePath: input.path,
      width: 480,
      frameRate: 18,
    );
    final second = service.queueProxy(
      sourcePath: input.path,
      width: 480,
      frameRate: 18,
    );

    await started.future;
    expect(buildCalls, 1);
    gate.complete();
    final results = await Future.wait([first, second]);

    expect(results[0], isNotNull);
    expect(results[1]?.path, results[0]?.path);
    expect(await results[0]!.readAsBytes(), [7, 8, 9]);
    expect(await input.readAsBytes(), List<int>.filled(128, 9));
    expect(service.successfulGenerations, 1);
    expect(service.pendingGenerations, 0);
    service.dispose();
  });

  test('CPU-heavy proxy generations are serialized across source files', () async {
    final firstInput = await source('first.mov');
    final secondInput = await source('second.mov');
    final firstGate = Completer<void>();
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    var active = 0;
    var maxActive = 0;
    var calls = 0;

    final service = PreviewProxyService(
      cacheDirectory: cache,
      minimumSourceBytes: 0,
      builder: ({
        required sourcePath,
        required outputFile,
        required width,
        required frameRate,
      }) async {
        calls++;
        active++;
        if (active > maxActive) maxActive = active;
        if (calls == 1) {
          firstStarted.complete();
          await firstGate.future;
        } else {
          secondStarted.complete();
        }
        await outputFile.writeAsBytes([1, 2, 3], flush: true);
        active--;
        return true;
      },
    );

    final first = service.queueProxy(
      sourcePath: firstInput.path,
      width: 480,
      frameRate: 18,
    );
    await firstStarted.future;
    final second = service.queueProxy(
      sourcePath: secondInput.path,
      width: 480,
      frameRate: 18,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    expect(active, 1);

    firstGate.complete();
    expect(await first, isNotNull);
    await secondStarted.future;
    expect(await second, isNotNull);
    expect(maxActive, 1);
    expect(calls, 2);
    service.dispose();
  });

  test('completed proxy cache is reused and different profiles are isolated', () async {
    final input = await source('camera.mp4');
    var buildCalls = 0;
    final service = PreviewProxyService(
      cacheDirectory: cache,
      minimumSourceBytes: 0,
      builder: ({
        required sourcePath,
        required outputFile,
        required width,
        required frameRate,
      }) async {
        buildCalls++;
        await outputFile.writeAsBytes([width, frameRate], flush: true);
        return true;
      },
    );

    expect(
      await service.findCachedProxy(
        sourcePath: input.path,
        width: 480,
        frameRate: 18,
      ),
      isNull,
    );
    final first = await service.queueProxy(
      sourcePath: input.path,
      width: 480,
      frameRate: 18,
    );
    final cached = await service.findCachedProxy(
      sourcePath: input.path,
      width: 480,
      frameRate: 18,
    );
    final otherProfile = await service.queueProxy(
      sourcePath: input.path,
      width: 640,
      frameRate: 24,
    );

    expect(first, isNotNull);
    expect(cached?.path, first?.path);
    expect(otherProfile, isNotNull);
    expect(otherProfile!.path, isNot(first!.path));
    expect(buildCalls, 2);
    service.dispose();
  });

  test('failed or empty proxy output is never published and partial file is removed',
      () async {
    final input = await source('broken.mp4');
    final service = PreviewProxyService(
      cacheDirectory: cache,
      minimumSourceBytes: 0,
      builder: ({
        required sourcePath,
        required outputFile,
        required width,
        required frameRate,
      }) async {
        await outputFile.writeAsBytes([], flush: true);
        return true;
      },
    );

    final result = await service.queueProxy(
      sourcePath: input.path,
      width: 480,
      frameRate: 18,
    );

    expect(result, isNull);
    expect(await cache.list().toList(), isEmpty);
    expect(
      await service.findCachedProxy(
        sourcePath: input.path,
        width: 480,
        frameRate: 18,
      ),
      isNull,
    );
    service.dispose();
  });

  test('source change produces a new cache identity', () async {
    final input = await source('replace-me.mp4', bytes: [1, 2, 3]);
    final firstService = PreviewProxyService(
      cacheDirectory: cache,
      minimumSourceBytes: 0,
      builder: ({
        required sourcePath,
        required outputFile,
        required width,
        required frameRate,
      }) async {
        await outputFile.writeAsBytes([4, 5, 6], flush: true);
        return true;
      },
    );
    final first = await firstService.queueProxy(
      sourcePath: input.path,
      width: 480,
      frameRate: 18,
    );
    firstService.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await input.writeAsBytes(List<int>.filled(300, 2), flush: true);
    final secondService = PreviewProxyService(
      cacheDirectory: cache,
      minimumSourceBytes: 0,
      builder: ({
        required sourcePath,
        required outputFile,
        required width,
        required frameRate,
      }) async {
        await outputFile.writeAsBytes([7, 8, 9], flush: true);
        return true;
      },
    );
    final second = await secondService.queueProxy(
      sourcePath: input.path,
      width: 480,
      frameRate: 18,
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(second!.path, isNot(first!.path));
    secondService.dispose();
  });
}
