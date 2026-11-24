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
    expect(projected.positionX, contains('50.000000'));
    expect(projected.scaleX, contains('1000.000000'));
    expect(projected.scaleX, contains('500.00000'));
  });
  test('camera yaw moves objects through camera-space coordinates', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 90, 0),
      opacity: 100,
      enabled: true,
    );
    const layer = ResolvedLayerTransform(
      position: Vector3(960, 540, 500),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );

    final projected = resolver.project(
      layer: layer,
      camera: camera,
      settings: const CameraSettings(),
    );

    expect(projected.position.x, closeTo(460, 0.001));
    expect(projected.position.y, closeTo(540, 0.001));
  });

  test('camera roll rotates the view and counter-rotates layer cards', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 90),
      opacity: 100,
      enabled: true,
    );
    const layer = ResolvedLayerTransform(
      position: Vector3(1060, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );

    final projected = resolver.project(
      layer: layer,
      camera: camera,
      settings: const CameraSettings(projection: 'orthographic'),
    );

    expect(projected.position.x, closeTo(960, 0.001));
    expect(projected.position.y, closeTo(440, 0.001));
    expect(projected.rotation.z, -90);
  });

  test('perspective camera hides layers behind its near plane', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );
    const layer = ResolvedLayerTransform(
      position: Vector3(1100, 540, 1100),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 75,
      enabled: true,
    );

    final projected = resolver.project(
      layer: layer,
      camera: camera,
      settings: const CameraSettings(focusDistance: 1000),
    );

    expect(projected.opacity, 0);
    expect(projected.scale.x, lessThanOrEqualTo(2000));
  });

  test('clips camera layers outside the configured far plane', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );
    const layer = ResolvedLayerTransform(
      position: Vector3(1100, 540, -250),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 75,
      enabled: true,
    );

    final projected = resolver.project(
      layer: layer,
      camera: camera,
      settings: const CameraSettings(
        focusDistance: 1000,
        nearClip: 50,
        farClip: 1000,
      ),
    );

    expect(projected.opacity, 0);
    expect(
      resolver.isDistanceVisible(1000, const CameraSettings(farClip: 1000)),
      isTrue,
    );
    expect(
      resolver.isDistanceVisible(1000.1, const CameraSettings(farClip: 1000)),
      isFalse,
    );
  });

  test('two-node camera aims its optical axis at the point of interest', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 30),
      opacity: 100,
      enabled: true,
    );
    const settings = CameraSettings(
      cameraMode: 'twoNode',
      pointOfInterestX: 1160,
      pointOfInterestY: 440,
      pointOfInterestZ: 1000,
    );

    final rotation = resolver.effectiveCameraRotation(camera, settings);
    final direction = resolver.worldToCameraOffset(
      const Vector3(200, -100, 1000),
      rotation,
    );

    expect(direction.x, closeTo(0, 0.0001));
    expect(direction.y, closeTo(0, 0.0001));
    expect(direction.z, greaterThan(1000));
    expect(rotation.z, 30);
  });

  test('two-node camera falls back to authored rotation for a coincident target', () {
    const camera = ResolvedLayerTransform(
      position: Vector3(960, 540, 0),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(12, 25, 30),
      opacity: 100,
      enabled: true,
    );
    const settings = CameraSettings(
      cameraMode: 'twoNode',
      pointOfInterestX: 960,
      pointOfInterestY: 540,
      pointOfInterestZ: 0,
    );

    expect(resolver.effectiveCameraRotation(camera, settings), camera.rotation);
  });

  test('two-node export expressions contain the saved point of interest', () {
    const parentResolver = ParentTransformExpressionResolver();
    const cameraLayer = CompositionLayer(
      id: 'camera',
      name: 'Camera',
      kind: LayerKind.camera,
      camera: CameraSettings(
        cameraMode: 'twoNode',
        pointOfInterestX: 1200,
        pointOfInterestY: 500,
        pointOfInterestZ: 800,
      ),
    );
    const objectLayer = CompositionLayer(
      id: 'object',
      name: 'Object',
      kind: LayerKind.image,
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
      settings: cameraLayer.camera!,
    );

    expect(projected.positionX, contains('atan2'));
    expect(projected.positionY, contains('atan2'));
    expect(projected.positionX, contains('1200.000000'));
    expect(projected.positionY, contains('500.000000'));
  });

  test('FFmpeg camera projection includes orientation and near/far culling', () {
    const parentResolver = ParentTransformExpressionResolver();
    const cameraLayer = CompositionLayer(
      id: 'camera',
      name: 'Camera',
      kind: LayerKind.camera,
      transform: LayerTransform(
        rotation: Vector3(12, 25, 35),
      ),
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

    expect(projected.positionX, contains('sin('));
    expect(projected.positionY, contains('cos('));
    expect(projected.rotationZ, contains('35.00000'));
    expect(projected.opacity, contains('if(gte('));
    expect(projected.opacity, contains('lte('));
    expect(projected.scaleX, contains('min(20,'));
  });
}
