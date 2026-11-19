import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/parent_transform_expression_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = ParentTransformExpressionResolver();

  test('compiles parent position scale rotation and opacity into expressions', () {
    const parent = CompositionLayer(
      id: 'parent',
      name: 'Parent',
      kind: LayerKind.nullObject,
      transform: LayerTransform(
        position: Vector3(100, 200, 0),
        scale: Vector3(200, 150, 100),
        rotation: Vector3(0, 0, 30),
        opacity: 50,
      ),
    );
    const child = CompositionLayer(
      id: 'child',
      name: 'Child',
      kind: LayerKind.image,
      parentId: 'parent',
      transform: LayerTransform(
        position: Vector3(20, 40, 0),
        scale: Vector3(50, 80, 100),
        rotation: Vector3(0, 0, 15),
        opacity: 80,
      ),
    );

    final result = resolver.resolve(
      layer: child,
      layers: const [parent, child],
    );

    expect(result.positionX, contains('100.00000'));
    expect(result.positionX, contains('20.00000'));
    expect(result.scaleX, contains('200.00000'));
    expect(result.scaleX, contains('50.00000'));
    expect(result.rotationZ, contains('30.00000'));
    expect(result.rotationZ, contains('15.00000'));
    expect(result.opacity, contains('50.00000'));
    expect(result.opacity, contains('80.00000'));
  });

  test('inherits animated parent and child properties', () {
    const parent = CompositionLayer(
      id: 'parent',
      name: 'Parent',
      kind: LayerKind.nullObject,
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
      kind: LayerKind.video,
      parentId: 'parent',
      keyframeTracks: [
        KeyframeTrack(
          property: 'position.x',
          keyframes: [
            ScalarKeyframe(timeMs: 0, value: 20),
            ScalarKeyframe(timeMs: 1000, value: 60),
          ],
        ),
      ],
    );

    final expression = resolver.resolve(
      layer: child,
      layers: const [parent, child],
    );

    expect(expression.positionX, contains('if(lt(t,1.00000)'));
    expect(expression.positionX, contains('300.00000'));
    expect(expression.positionX, contains('60.00000'));
  });

  test('rejects cyclic parent chains', () {
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
      () => resolver.resolve(layer: first, layers: const [first, second]),
      throwsStateError,
    );
  });
}
