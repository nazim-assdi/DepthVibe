import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/parent_transform_resolver.dart';
import 'package:depthvibe/features/composition/engine/software_3d_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const renderer = Software3dRenderer();
  const transform = ResolvedLayerTransform(
    position: Vector3(10, 20, 30),
    scale: Vector3(100, 100, 100),
    rotation: Vector3(0, 0, 0),
    opacity: 100,
    enabled: true,
  );

  test('area emitter generates the configured deterministic sample count', () {
    const light = SceneLight(
      transform: transform,
      settings: LightSettings(
        kind: LightKind.area,
        areaSize: 200,
        areaSamples: 16,
      ),
    );
    final first = renderer.areaLightSamplePositions(light);
    final second = renderer.areaLightSamplePositions(light);
    String key(Vector3 p) => p.x.toString() + ':' + p.y.toString();

    expect(first, hasLength(16));
    expect(first.map(key).toSet(), hasLength(16));
    expect(first.map(key).toList(), second.map(key).toList());
    for (final sample in first) {
      expect(sample.x, inInclusiveRange(-90, 110));
      expect(sample.y, inInclusiveRange(-80, 120));
      expect(sample.z, 30);
    }
  });

  test('area sample count is clamped to safe bounds', () {
    const light = SceneLight(
      transform: transform,
      settings: LightSettings(
        kind: LightKind.area,
        areaSamples: 200,
      ),
    );
    expect(renderer.areaLightSamplePositions(light), hasLength(64));

    const lowCount = SceneLight(
      transform: transform,
      settings: LightSettings(
        kind: LightKind.area,
        areaSamples: 0,
      ),
    );
    expect(renderer.areaLightSamplePositions(lowCount), hasLength(1));
  });

  test('copyWith keeps the area-light sample budget editable', () {
    const original = LightSettings(kind: LightKind.area);
    final updated = original.copyWith(areaSamples: 32);
    expect(original.areaSamples, 16);
    expect(updated.areaSamples, 32);
  });
}
