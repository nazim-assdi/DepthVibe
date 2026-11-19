import 'dart:typed_data';
import 'dart:ui';

import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/obj_mesh_loader.dart';
import 'package:depthvibe/features/composition/engine/parent_transform_resolver.dart';
import 'package:depthvibe/features/composition/engine/software_3d_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const renderer = Software3dRenderer();
  const mesh = ObjMesh(
    vertices: [
      Vector3(-1, -1, 0),
      Vector3(1, -1, 0),
      Vector3(0, 1, 0),
    ],
    triangles: [ObjTriangle(0, 1, 2)],
    materials: {},
    boundsMin: Vector3(-1, -1, 0),
    boundsMax: Vector3(1, 1, 0),
  );
  const cameraTransform = ResolvedLayerTransform(
    position: Vector3(200, 200, 0),
    scale: Vector3(100, 100, 100),
    rotation: Vector3(0, 0, 0),
    opacity: 100,
    enabled: true,
  );
  const modelTransform = ResolvedLayerTransform(
    position: Vector3(200, 200, 0),
    scale: Vector3(100, 100, 100),
    rotation: Vector3(0, 0, 0),
    opacity: 100,
    enabled: true,
  );

  test('samples a base-colour texture using interpolated UV coordinates', () {
    final triangle = ProjectedMeshTriangle(
      a: const Offset(0, 0),
      b: const Offset(4, 0),
      c: const Offset(0, 4),
      color: const Color(0xFFFFFFFF),
      distance: 1,
      distanceA: 1,
      distanceB: 1,
      distanceC: 1,
      uvA: Offset.zero,
      uvB: const Offset(1, 0),
      uvC: const Offset(0, 1),
      textureRgba: Uint8List.fromList([80, 150, 220, 255]),
      textureWidth: 1,
      textureHeight: 1,
    );
    final frame = Software3dRasterizer().rasterize(
      [triangle],
      width: 4,
      height: 4,
    );
    const pixel = 0;
    expect(frame.rgba[pixel], 80);
    expect(frame.rgba[pixel + 1], 150);
    expect(frame.rgba[pixel + 2], 220);
    expect(frame.rgba[pixel + 3], 255);
  });

  test('projects OBJ triangles into camera space with a shaded surface', () {
    final triangles = renderer.projectTriangles(
      mesh: mesh,
      viewport: const Size(400, 400),
      baseWidth: 400,
      compositionWidth: 400,
      compositionHeight: 400,
      modelTransform: modelTransform,
      cameraTransform: cameraTransform,
      cameraSettings: const CameraSettings(),
      lights: const [
        SceneLight(
          transform: ResolvedLayerTransform(
            position: Vector3(200, 200, 500),
            scale: Vector3(100, 100, 100),
            rotation: Vector3(0, 0, 0),
            opacity: 100,
            enabled: true,
          ),
          settings: LightSettings(
            kind: LightKind.directional,
            intensity: 400,
            color: '#FFFFFF',
          ),
        ),
      ],
    );

    expect(triangles, hasLength(1));
    expect(triangles.single.a, isNot(Offset.zero));
    expect(triangles.single.distance, closeTo(1000, 0.001));
    expect(triangles.single.color.a, 1);
  });

  test('does not draw a mesh outside the active camera far plane', () {
    final triangles = renderer.projectTriangles(
      mesh: mesh,
      viewport: const Size(400, 400),
      baseWidth: 400,
      compositionWidth: 400,
      compositionHeight: 400,
      modelTransform: modelTransform,
      cameraTransform: cameraTransform,
      cameraSettings: const CameraSettings(
        focusDistance: 1000,
        nearClip: 50,
        farClip: 500,
      ),
    );

    expect(triangles, isEmpty);
  });

  test('clips a triangle that crosses the near plane into visible geometry', () {
    const crossingMesh = ObjMesh(
      vertices: [
        Vector3(-1, -1, 0),
        Vector3(1, -1, 0),
        Vector3(0, 1, 1000),
      ],
      triangles: [ObjTriangle(0, 1, 2)],
      materials: {},
      boundsMin: Vector3(-1, -1, 0),
      boundsMax: Vector3(1, 1, 1000),
    );
    const distantModel = ResolvedLayerTransform(
      position: Vector3(200, 200, 1000),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );

    final triangles = renderer.projectTriangles(
      mesh: crossingMesh,
      viewport: const Size(400, 400),
      baseWidth: 400,
      compositionWidth: 400,
      compositionHeight: 400,
      modelTransform: distantModel,
      cameraTransform: cameraTransform,
      cameraSettings: const CameraSettings(
        focusDistance: 1000,
        nearClip: 50,
        farClip: 2000,
      ),
    );

    expect(triangles, isNotEmpty);
    for (final triangle in triangles) {
      expect(triangle.distanceA, greaterThanOrEqualTo(50));
      expect(triangle.distanceB, greaterThanOrEqualTo(50));
      expect(triangle.distanceC, greaterThanOrEqualTo(50));
    }
  });

  test('clips a triangle that crosses the far plane instead of dropping it', () {
    const crossingMesh = ObjMesh(
      vertices: [
        Vector3(-1, -1, 0),
        Vector3(1, -1, 0),
        Vector3(0, 1, 1000),
      ],
      triangles: [ObjTriangle(0, 1, 2)],
      materials: {},
      boundsMin: Vector3(-1, -1, 0),
      boundsMax: Vector3(1, 1, 1000),
    );
    const distantModel = ResolvedLayerTransform(
      position: Vector3(200, 200, -150),
      scale: Vector3(100, 100, 100),
      rotation: Vector3(0, 0, 0),
      opacity: 100,
      enabled: true,
    );

    final triangles = renderer.projectTriangles(
      mesh: crossingMesh,
      viewport: const Size(400, 400),
      baseWidth: 400,
      compositionWidth: 400,
      compositionHeight: 400,
      modelTransform: distantModel,
      cameraTransform: cameraTransform,
      cameraSettings: const CameraSettings(
        focusDistance: 1000,
        nearClip: 50,
        farClip: 1100,
      ),
    );

    expect(triangles, hasLength(1));
    expect(triangles.single.distanceA, lessThanOrEqualTo(1100));
    expect(triangles.single.distanceB, lessThanOrEqualTo(1100));
    expect(triangles.single.distanceC, lessThanOrEqualTo(1100));
  });

}
