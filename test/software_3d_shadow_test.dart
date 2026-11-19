import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/obj_mesh_loader.dart';
import 'package:depthvibe/features/composition/engine/parent_transform_resolver.dart';
import 'package:depthvibe/features/composition/engine/software_3d_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vertices = [
    Vector3(-3, -3, 5),
    Vector3(3, -3, 5),
    Vector3(0, 3, 5),
    Vector3(-3, -3, 0),
    Vector3(3, -3, 0),
    Vector3(0, 3, 0),
  ];
  const triangles = [
    ObjTriangle(0, 1, 2),
    ObjTriangle(3, 4, 5),
  ];

  ResolvedLayerTransform lightTransform() => const ResolvedLayerTransform(
        position: Vector3(0, 0, 10),
        scale: Vector3(100, 100, 100),
        rotation: Vector3(0, 0, 0),
        opacity: 100,
        enabled: true,
      );

  test('point light cubemap shadow map occludes a receiver behind a blocker', () {
    final map = Software3dShadowMap.forLight(
      light: SceneLight(
        transform: lightTransform(),
        settings: const LightSettings(
          kind: LightKind.point,
          castShadows: true,
        ),
      ),
      vertices: vertices,
      triangles: triangles,
      resolution: 96,
    );

    expect(map.visibilityAt(const Vector3(0, 0, 8)), greaterThan(0.95));
    expect(map.visibilityAt(const Vector3(0, 0, 0)), lessThan(0.05));
  });

  test('spot perspective shadow map applies its cone and depth range', () {
    final map = Software3dShadowMap.forLight(
      light: SceneLight(
        transform: lightTransform(),
        settings: const LightSettings(
          kind: LightKind.spot,
          coneAngle: 45,
          castShadows: true,
        ),
      ),
      vertices: vertices,
      triangles: triangles,
      resolution: 96,
    );

    expect(map.visibilityAt(const Vector3(0, 0, 0)), lessThan(0.05));
    expect(map.visibilityAt(const Vector3(8, 0, 0)), greaterThan(0.95));
  });

  test('shadow softness returns a filtered visibility value', () {
    final map = Software3dShadowMap.forLight(
      light: SceneLight(
        transform: lightTransform(),
        settings: const LightSettings(kind: LightKind.point),
      ),
      vertices: vertices,
      triangles: triangles,
      resolution: 96,
    );

    final hard = map.visibilityAt(const Vector3(0, 0, 0), softness: 0);
    final soft = map.visibilityAt(const Vector3(0, 0, 0), softness: 80);
    expect(hard, inInclusiveRange(0, 1));
    expect(soft, inInclusiveRange(0, 1));
    expect(soft, greaterThanOrEqualTo(hard));
  });


  test('directional orthographic shadow map depth-tests the receiver', () {
    final map = Software3dShadowMap.forLight(
      light: SceneLight(
        transform: lightTransform(),
        settings: const LightSettings(kind: LightKind.directional),
      ),
      vertices: vertices,
      triangles: triangles,
      resolution: 96,
    );

    expect(map.visibilityAt(const Vector3(0, 0, 0)), lessThan(0.05));
    expect(map.visibilityAt(const Vector3(0, 0, 8)), greaterThan(0.95));
  });

  test('area shadow maps use point-light cubemap projection', () {
    final map = Software3dShadowMap.forLight(
      light: SceneLight(
        transform: lightTransform(),
        settings: const LightSettings(kind: LightKind.area),
      ),
      vertices: vertices,
      triangles: triangles,
      resolution: 64,
    );
    expect(map.visibilityAt(const Vector3(0, 0, 0)), lessThan(0.05));
  });
}
