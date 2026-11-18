import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/parent_transform_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
