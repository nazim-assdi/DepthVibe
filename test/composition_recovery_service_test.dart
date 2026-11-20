import 'dart:io';

import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/composition_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  const service = CompositionRecoveryService();

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('depthvibe_recovery_test_');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('saves and restores a full recovery document', () async {
    const document = CompositionDocument(
      name: 'Crash Recovery',
      colorOutputProfile: ColorOutputProfile.hlg,
      playheadMs: 4567,
      layers: [
        CompositionLayer(
          id: 'video_1',
          name: 'Footage',
          kind: LayerKind.video,
          sourceUri: '/media/footage.mp4',
          keyframeTracks: [
            KeyframeTrack(
              property: 'position.x',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 10),
                ScalarKeyframe(timeMs: 2000, value: 50),
              ],
            ),
          ],
          effects: [
            EffectInstance(
              id: 'lut_2',
              effectId: 'color_lut',
              name: 'LUT',
              assetUri: '/media/grade.cube',
              assetInterpolation: 'tetrahedral',
            ),
          ],
        ),
      ],
      transitions: [
        CompositionTransition(
          id: 'transition_3',
          fromLayerId: 'video_1',
          toLayerId: 'video_1',
          durationMs: 400,
        ),
      ],
    );

    final file = await service.save(document, recoveryDirectory: temporary);
    expect(await file.exists(), isTrue);

    final restored = await service.load(recoveryDirectory: temporary);
    expect(restored, isNotNull);
    expect(restored!.document.name, 'Crash Recovery');
    expect(restored.document.colorOutputProfile, ColorOutputProfile.hlg);
    expect(restored.document.playheadMs, 4567);
    expect(restored.document.layers.single.sourceUri, '/media/footage.mp4');
    expect(
      restored.document.layers.single.keyframeTracks.single.keyframes,
      hasLength(2),
    );
    expect(
      restored.document.layers.single.effects.single.assetInterpolation,
      'tetrahedral',
    );
    expect(restored.document.transitions, hasLength(1));
    expect(
      restored.savedAt.isBefore(DateTime.now().add(const Duration(seconds: 1))),
      isTrue,
    );
  });

  test('replaces the prior autosave snapshot atomically', () async {
    await service.save(
      const CompositionDocument(name: 'Old'),
      recoveryDirectory: temporary,
    );
    await service.save(
      const CompositionDocument(name: 'New'),
      recoveryDirectory: temporary,
    );
    final restored = await service.load(recoveryDirectory: temporary);
    expect(restored!.document.name, 'New');
  });

  test('recovers the previous snapshot if the active file was interrupted', () async {
    final active = await service.save(
      const CompositionDocument(name: 'Previous durable snapshot'),
      recoveryDirectory: temporary,
    );
    await active.rename(active.path + '.bak');

    final restored = await service.load(recoveryDirectory: temporary);
    expect(restored, isNotNull);
    expect(restored!.document.name, 'Previous durable snapshot');
  });

  test('rejects recovery files with unknown versions', () async {
    final file = File(temporary.path + '/active_recovery.json');
    await file.writeAsString(
      '{"format":"DepthVibe.Recovery","version":99,'
      '"savedAt":"2026-11-20T00:00:00Z","document":{}}',
    );
    await expectLater(
      service.load(recoveryDirectory: temporary),
      throwsA(isA<FormatException>()),
    );
  });

  test('clear removes active and temporary recovery files', () async {
    await service.save(
      const CompositionDocument(name: 'Clear me'),
      recoveryDirectory: temporary,
    );
    await File(temporary.path + '/stale.tmp_123').writeAsString('partial');
    await service.clear(recoveryDirectory: temporary);
    expect(await service.load(recoveryDirectory: temporary), isNull);
    expect(await File(temporary.path + '/stale.tmp_123').exists(), isFalse);
  });
}
