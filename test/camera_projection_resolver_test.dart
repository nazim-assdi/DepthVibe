import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/camera_projection_resolver.dart';
import 'package:depthvibe/features/composition/engine/parent_transform_expression_resolver.dart';
import 'package:depthvibe/features/composition/engine/parent_transform_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = CameraProjectionResolver();

  test('keeps the focus plane unchanged with default camera settings', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );
    const layer = ResolvedLayerTransform(
      position: Vector3(1200, 700, 0),
      scale: Vector3(100, 80, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 75,
      enabled: true,
    );

    final projected = resolver.project(
      layer: layer,
      camera: camera,
      settings: const CameraSettings(),
    );

    expect(projected.position.x, closeTo(1200, 0.0001));
    expect(projected.position.y, closeTo(700, 0.0001));
    expect(projected.scale.x, closeTo(100, 0.0001));
    expect(projected.scale.y, closeTo(80, 0.0001));
    expect(projected.opacity, 75);
  });

  test('scales and moves a nearer layer around the camera centre', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );
    const layer = ResolvedLayerTransform(
      position: Vector3(1000, 540, 500),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );

    final projected = resolver.project(
      layer: layer,
      camera: camera,
      settings: const CameraSettings(
        focusDistance: 1000,
        fieldOfView: 50,
        focalLength: 50,
      ),
    );

    expect(projected.position.x, closeTo(1040, 0.0001));
    expect(projected.scale.x, closeTo(200, 0.0001));
    expect(projected.position.z, 500);
  });

  test('orthographic mode does not apply depth perspective', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );
    const layer = ResolvedLayerTransform(
      position: Vector3(1200, 700, 900),
      scale: Vector3(150, 125, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 80,
      enabled: true,
    );

    final projected = resolver.project(
      layer: layer,
      camera: camera,
      settings: const CameraSettings(projection: 'orthographic'),
    );

    expect(projected.position.x, 1200);
    expect(projected.position.y, 700);
    expect(projected.scale.x, 150);
    expect(projected.scale.y, 125);
  });

  test('compiles depth perspective into frame-evaluated export expressions', () {
    const parentResolver = ParentTransformExpressionResolver();
    const cameraLayer = CompositionLayer(
      id: 'camera',
      name: 'Camera',
      kind: LayerKind.camera,
    );
    const objectLayer = CompositionLayer(
      id: 'object',
      name: 'Object',
      kind: LayerKind.image,
      transform: LayerTransform(
        position: Vector3(1200, 540, 500),
      ),
    );

    final camera = parentResolver.resolve(
      layer: cameraLayer,
      layers: const [cameraLayer, objectLayer],
    );
    final layer = parentResolver.resolve(
      layer: objectLayer,
      layers: const [cameraLayer, objectLayer],
    );
    final projected = resolver.compile(
      layer: layer,
      camera: camera,
      settings: const CameraSettings(),
    );

    expect(projected.positionX, contains('1200.00000'));
    expect(projected.positionX, contains('0.05'));
    expect(projected.scaleX, contains('1000.000000'));
    expect(projected.scaleX, contains('500.00000'));
  });
}
