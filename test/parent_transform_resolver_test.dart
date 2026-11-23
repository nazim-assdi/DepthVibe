import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/parent_transform_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {

  test('resolveAll matches individual resolution across animated parent chains', () {
    const root = CompositionLayer(
      id: 'root',
      name: 'Root',
      kind: LayerKind.nullObject,
      transform: LayerTransform(
        position: Vector3(100, 200, 10),
        scale: Vector3(200, 150, 100),
        rotation: Vector3(0, 0, 15),
        opacity: 60,
      ),
      keyframeTracks: [
        KeyframeTrack(
          property: 'position.x',
          keyframes: [
            ScalarKeyframe(timeMs: 0, value: 100),
            ScalarKeyframe(timeMs: 1000, value: 300),
          ],
        ),
      ],
    );
    const child = CompositionLayer(
      id: 'child',
      name: 'Child',
      kind: LayerKind.nullObject,
      parentId: 'root',
      transform: LayerTransform(
        position: Vector3(20, 30, 5),
        scale: Vector3(50, 80, 100),
        rotation: Vector3(0, 0, 25),
        opacity: 80,
      ),
    );
    const leaf = CompositionLayer(
      id: 'leaf',
      name: 'Leaf',
      kind: LayerKind.video,
      parentId: 'child',
      transform: LayerTransform(position: Vector3(10, 5, 0)),
    );
    const resolver = ParentTransformResolver();
    const layers = [root, child, leaf];

    for (final timeMs in [0, 500, 1000]) {
      final all = resolver.resolveAll(timeMs: timeMs, layers: layers);
      expect(all.keys, containsAll(['root', 'child', 'leaf']));
      for (final layer in layers) {
        final expected = resolver.resolve(
          layer: layer,
          timeMs: timeMs,
          layers: layers,
        );
        final actual = all[layer.id]!;
        expect(actual.position.x, closeTo(expected.position.x, 0.000001));
        expect(actual.position.y, closeTo(expected.position.y, 0.000001));
        expect(actual.position.z, closeTo(expected.position.z, 0.000001));
        expect(actual.scale.x, closeTo(expected.scale.x, 0.000001));
        expect(actual.scale.y, closeTo(expected.scale.y, 0.000001));
        expect(actual.rotation.z, closeTo(expected.rotation.z, 0.000001));
        expect(actual.opacity, closeTo(expected.opacity, 0.000001));
        expect(actual.enabled, expected.enabled);
      }
    }
  });

  test('resolveAll rejects cycles in any parent chain', () {
    const first = CompositionLayer(
      id: 'first',
      name: 'First',
      kind: LayerKind.nullObject,
      parentId: 'second',
    );
    const second = CompositionLayer(
      id: 'second',
      name: 'Second',
      kind: LayerKind.nullObject,
      parentId: 'first',
    );

    expect(
      () => const ParentTransformResolver().resolveAll(
        timeMs: 0,
        layers: const [first, second],
      ),
      throwsStateError,
    );
  });

  test('parent XYZ rotation rotates the child offset before world positioning', () {
    const parent = CompositionLayer(
      id: 'rotation-null',
      name: 'Rotation Null',
      kind: LayerKind.nullObject,
      transform: LayerTransform(
        position: Vector3(0, 0, 0),
        scale: Vector3(100, 100, 100),
        rotation: Vector3(0, 0, 90),
      ),
    );
    const child = CompositionLayer(
      id: 'rotated-child',
      name: 'Child',
      kind: LayerKind.text,
      parentId: 'rotation-null',
      transform: LayerTransform(
        position: Vector3(10, 0, 0),
      ),
    );
    const layers = [parent, child];
    const resolver = ParentTransformResolver();

    final resolved = resolver.resolve(
      layer: child,
      timeMs: 0,
      layers: layers,
    );
    final all = resolver.resolveAll(timeMs: 0, layers: layers)[child.id]!;

    expect(resolved.position.x, closeTo(0, 0.000001));
    expect(resolved.position.y, closeTo(10, 0.000001));
    expect(all.position.x, closeTo(resolved.position.x, 0.000001));
    expect(all.position.y, closeTo(resolved.position.y, 0.000001));
  });

  test('parent X rotation carries a child offset into Z depth', () {
    const parent = CompositionLayer(
      id: 'x-null',
      name: 'X Null',
      kind: LayerKind.nullObject,
      transform: LayerTransform(
        position: Vector3(0, 0, 0),
        rotation: Vector3(90, 0, 0),
      ),
    );
    const child = CompositionLayer(
      id: 'z-child',
      name: 'Depth Child',
      kind: LayerKind.text,
      parentId: 'x-null',
      transform: LayerTransform(
        position: Vector3(0, 10, 0),
      ),
    );

    final resolved = const ParentTransformResolver().resolve(
      layer: child,
      timeMs: 0,
      layers: const [parent, child],
    );
    expect(resolved.position.y, closeTo(0, 0.000001));
    expect(resolved.position.z, closeTo(10, 0.000001));
  });

  test('disabled group parent hides nested child layers', () {
    const group = CompositionLayer(
      id: 'group',
      name: 'PSD Group',
      kind: LayerKind.precomposition,
      enabled: false,
    );
    const child = CompositionLayer(
      id: 'child',
      name: 'Child Layer',
      kind: LayerKind.image,
      parentId: 'group',
    );

    final resolved = const ParentTransformResolver().resolve(
      layer: child,
      timeMs: 0,
      layers: const [group, child],
    );

    expect(resolved.enabled, isFalse);
  });

  test('parent transform is inherited through a null controller', () {
    const parent = CompositionLayer(
      id: 'null-1',
      name: 'Null',
      kind: LayerKind.nullObject,
      transform: LayerTransform(
        position: Vector3(100, 200, 0),
        scale: Vector3(200, 200, 100),
        opacity: 50,
      ),
    );
    const child = CompositionLayer(
      id: 'image-1',
      name: 'Image',
      kind: LayerKind.image,
      parentId: 'null-1',
      transform: LayerTransform(
        position: Vector3(20, 30, 0),
        opacity: 80,
      ),
    );

    final resolved = const ParentTransformResolver().resolve(
      layer: child,
      timeMs: 0,
      layers: const [parent, child],
    );

    expect(resolved.position.x, 140);
    expect(resolved.position.y, 260);
    expect(resolved.scale.x, 200);
    expect(resolved.opacity, 40);
  });
}
