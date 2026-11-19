import 'dart:math' as math;
import 'dart:ui';

import '../domain/composition_models.dart';
import 'camera_projection_resolver.dart';
import 'obj_mesh_loader.dart';
import 'parent_transform_resolver.dart';

class SceneLight {
  const SceneLight({
    required this.transform,
    required this.settings,
  });

  final ResolvedLayerTransform transform;
  final LightSettings settings;
}

class ProjectedMeshTriangle {
  const ProjectedMeshTriangle({
    required this.a,
    required this.b,
    required this.c,
    required this.color,
    required this.distance,
  });

  final Offset a;
  final Offset b;
  final Offset c;
  final Color color;
  final double distance;
}

/// Deterministic CPU mesh projector and flat-shading renderer shared by the
/// compositor preview. It keeps the model lightweight for low-memory devices.
class Software3dRenderer {
  const Software3dRenderer({
    this.cameraResolver = const CameraProjectionResolver(),
  });

  final CameraProjectionResolver cameraResolver;

  List<ProjectedMeshTriangle> projectTriangles({
    required ObjMesh mesh,
    required Size viewport,
    required double baseWidth,
    required double compositionWidth,
    required double compositionHeight,
    required ResolvedLayerTransform modelTransform,
    required ResolvedLayerTransform cameraTransform,
    required CameraSettings cameraSettings,
    List<SceneLight> lights = const [],
  }) {
    if (mesh.triangles.isEmpty ||
        mesh.maxDimension <= 0 ||
        viewport.width <= 0 ||
        viewport.height <= 0 ||
        baseWidth <= 0) {
      return const [];
    }

    final center = mesh.center;
    final fitSize = math.min(compositionWidth, compositionHeight).toDouble() * 0.28;
    final unitScale = fitSize / mesh.maxDimension;
    final pixelScale = viewport.width / baseWidth;
    final cameraOffset = Vector3(
      modelTransform.position.x - cameraTransform.position.x,
      modelTransform.position.y - cameraTransform.position.y,
      modelTransform.position.z - cameraTransform.position.z,
    );
    final centerCamera = cameraResolver.worldToCameraOffset(
      cameraOffset,
      cameraTransform.rotation,
    );
    final centerDistance = cameraSettings.focusDistance - centerCamera.z;
    if (!cameraResolver.isDistanceVisible(centerDistance, cameraSettings)) {
      return const [];
    }
    final centerFactor = cameraResolver.projectionFactor(
      centerCamera.z,
      cameraSettings,
    );

    final projected = <_ProjectedVertex>[];
    final worldVertices = <Vector3>[];
    for (final vertex in mesh.vertices) {
      final local = Vector3(
        (vertex.x - center.x) * unitScale * modelTransform.scale.x / 100,
        (vertex.y - center.y) * unitScale * modelTransform.scale.y / 100,
        (vertex.z - center.z) * unitScale * modelTransform.scale.z / 100,
      );
      final rotated = _rotate(local, modelTransform.rotation);
      final world = Vector3(
        modelTransform.position.x + rotated.x,
        modelTransform.position.y + rotated.y,
        modelTransform.position.z + rotated.z,
      );
      worldVertices.add(world);

      final relativeToCamera = Vector3(
        world.x - cameraTransform.position.x,
        world.y - cameraTransform.position.y,
        world.z - cameraTransform.position.z,
      );
      final cameraPoint = cameraResolver.worldToCameraOffset(
        relativeToCamera,
        cameraTransform.rotation,
      );
      final distance = cameraSettings.focusDistance - cameraPoint.z;
      if (!cameraResolver.isDistanceVisible(distance, cameraSettings)) {
        projected.add(const _ProjectedVertex.hidden());
        continue;
      }

      final factor = cameraResolver.projectionFactor(
        cameraPoint.z,
        cameraSettings,
      );
      final dx = (cameraPoint.x * factor -
              centerCamera.x * centerFactor) *
          pixelScale;
      final dy = -(cameraPoint.y * factor -
              centerCamera.y * centerFactor) *
          pixelScale;
      projected.add(_ProjectedVertex(
        point: Offset(viewport.width / 2 + dx, viewport.height / 2 + dy),
        distance: distance,
        visible: true,
      ));
    }

    final faces = <ProjectedMeshTriangle>[];
    for (final triangle in mesh.triangles) {
      final a = projected[triangle.a];
      final b = projected[triangle.b];
      final c = projected[triangle.c];
      if (!a.visible || !b.visible || !c.visible) continue;

      final worldA = worldVertices[triangle.a];
      final worldB = worldVertices[triangle.b];
      final worldC = worldVertices[triangle.c];
      final normal = _normalize(_cross(
        _subtract(worldB, worldA),
        _subtract(worldC, worldA),
      ));
      final faceCenter = Vector3(
        (worldA.x + worldB.x + worldC.x) / 3,
        (worldA.y + worldB.y + worldC.y) / 3,
        (worldA.z + worldB.z + worldC.z) / 3,
      );
      final viewDirection = _normalize(Vector3(
        cameraTransform.position.x - faceCenter.x,
        cameraTransform.position.y - faceCenter.y,
        cameraTransform.position.z - faceCenter.z,
      ));
      final twoSidedNormal = _dot(normal, viewDirection) < 0
          ? _multiply(normal, -1)
          : normal;
      final material = mesh.materialFor(triangle);
      final color = _shade(material, twoSidedNormal, faceCenter, lights);
      faces.add(ProjectedMeshTriangle(
        a: a.point,
        b: b.point,
        c: c.point,
        color: color,
        distance: (a.distance + b.distance + c.distance) / 3,
      ));
    }

    // Painter's order: far faces first, near faces last.
    faces.sort((a, b) => b.distance.compareTo(a.distance));
    return faces;
  }

  Color _shade(
    ObjMaterial material,
    Vector3 normal,
    Vector3 faceCenter,
    List<SceneLight> lights,
  ) {
    var redLight = 0.20;
    var greenLight = 0.20;
    var blueLight = 0.20;

    if (lights.isEmpty) {
      final direction = _normalize(const Vector3(0.35, 0.55, 1));
      final diffuse = _dot(normal, direction).clamp(0.0, 1.0).toDouble();
      final amount = 0.82 * diffuse;
      redLight += amount;
      greenLight += amount;
      blueLight += amount;
    } else {
      for (final light in lights) {
        final intensity = light.settings.intensity.clamp(0.0, 1000.0).toDouble() / 100.0;
        if (intensity <= 0) continue;
        final lightColor = _parseColor(light.settings.color);
        if (light.settings.kind == LightKind.ambient) {
          final amount = (intensity * 0.22).clamp(0.0, 1.0).toDouble();
          redLight += lightColor.red * amount;
          greenLight += lightColor.green * amount;
          blueLight += lightColor.blue * amount;
          continue;
        }

        Vector3 toLight;
        Vector3? lightPosition;
        var attenuation = 1.0;
        if (light.settings.kind == LightKind.directional) {
          toLight = _normalize(_rotate(
            const Vector3(0, 0, 1),
            light.transform.rotation,
          ));
        } else {
          lightPosition = light.transform.position;
          final delta = Vector3(
            lightPosition.x - faceCenter.x,
            lightPosition.y - faceCenter.y,
            lightPosition.z - faceCenter.z,
          );
          final distance = _length(delta);
          toLight = distance <= 0.0001
              ? const Vector3(0, 0, 1)
              : _multiply(delta, 1 / distance);
          attenuation = 1 / (1 + math.pow(distance / 1000, 2));
        }
        if (light.settings.kind == LightKind.spot && lightPosition != null) {
          final spotDirection = _normalize(_rotate(
            const Vector3(0, 0, -1),
            light.transform.rotation,
          ));
          final fromLight = _normalize(Vector3(
            faceCenter.x - lightPosition.x,
            faceCenter.y - lightPosition.y,
            faceCenter.z - lightPosition.z,
          ));
          final alignment = _dot(spotDirection, fromLight);
          final cutoff = math.cos(
            light.settings.coneAngle.clamp(1.0, 180.0) * math.pi / 360,
          );
          if (alignment <= cutoff) continue;
          attenuation *= ((alignment - cutoff) / (1 - cutoff))
              .clamp(0.0, 1.0)
              .toDouble();
        }
        final diffuse = _dot(normal, toLight).clamp(0.0, 1.0).toDouble();
        final amount = (intensity * 0.62 * diffuse * attenuation)
            .clamp(0.0, 1.5)
            .toDouble();
        redLight += lightColor.red * amount;
        greenLight += lightColor.green * amount;
        blueLight += lightColor.blue * amount;
      }
    }

    int channel(double value) =>
        (value * 255).round().clamp(0, 255).toInt();
    return Color.fromARGB(
      (material.alpha * 255).round().clamp(0, 255).toInt(),
      channel(material.red * redLight),
      channel(material.green * greenLight),
      channel(material.blue * blueLight),
    );
  }

  Color _parseColor(String value) {
    final hex = value.replaceFirst('#', '');
    if (hex.length != 6) return const Color(0xFFFFFFFF);
    final parsed = int.tryParse(hex, radix: 16) ?? 0xFFFFFF;
    return Color(0xFF000000 | parsed);
  }

  Vector3 _rotate(Vector3 value, Vector3 degrees) {
    final rx = degrees.x * math.pi / 180;
    final ry = degrees.y * math.pi / 180;
    final rz = degrees.z * math.pi / 180;

    final cy = math.cos(rx);
    final sy = math.sin(rx);
    final y1 = value.y * cy - value.z * sy;
    final z1 = value.y * sy + value.z * cy;

    final cx = math.cos(ry);
    final sx = math.sin(ry);
    final x2 = value.x * cx + z1 * sx;
    final z2 = -value.x * sx + z1 * cx;

    final cz = math.cos(rz);
    final sz = math.sin(rz);
    return Vector3(
      x2 * cz - y1 * sz,
      x2 * sz + y1 * cz,
      z2,
    );
  }

  Vector3 _subtract(Vector3 a, Vector3 b) =>
      Vector3(a.x - b.x, a.y - b.y, a.z - b.z);

  Vector3 _multiply(Vector3 value, double factor) =>
      Vector3(value.x * factor, value.y * factor, value.z * factor);

  Vector3 _cross(Vector3 a, Vector3 b) => Vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
      );

  double _dot(Vector3 a, Vector3 b) =>
      a.x * b.x + a.y * b.y + a.z * b.z;

  double _length(Vector3 value) =>
      math.sqrt(_dot(value, value));

  Vector3 _normalize(Vector3 value) {
    final length = _length(value);
    if (length <= 0.000001) return const Vector3(0, 0, 1);
    return _multiply(value, 1 / length);
  }
}

class _ProjectedVertex {
  const _ProjectedVertex({
    required this.point,
    required this.distance,
    required this.visible,
  });

  const _ProjectedVertex.hidden()
      : point = Offset.zero,
        distance = 0,
        visible = false;

  final Offset point;
  final double distance;
  final bool visible;
}
