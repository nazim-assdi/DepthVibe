import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../domain/composition_models.dart';
import 'camera_projection_resolver.dart';
import 'obj_mesh_loader.dart';
import 'parent_transform_resolver.dart';
import 'gltf_scene_evaluator.dart';

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
    required this.distanceA,
    required this.distanceB,
    required this.distanceC,
    this.perspective = true,
  });

  final Offset a;
  final Offset b;
  final Offset c;
  final Color color;
  final double distance;
  final double distanceA;
  final double distanceB;
  final double distanceC;
  final bool perspective;
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
    bool centerOnModel = true,
    int timeMs = 0,
    int animationIndex = 0,
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
    final near = cameraSettings.nearClip.clamp(0.01, 100000.0).toDouble();
    final far = cameraSettings.farClip
        .clamp(near + 0.01, 1000000.0)
        .toDouble();
    final focus = cameraSettings.focusDistance.clamp(1.0, 5000.0).toDouble();
    final centerCameraZ = centerCamera.z.clamp(
      focus - far,
      focus - near,
    );
    final centerFactor = cameraResolver.projectionFactor(
      centerCameraZ,
      cameraSettings,
    );

    final sceneEvaluator = const GltfSceneEvaluator();
    final nodeMatrices = sceneEvaluator.worldMatrices(
      mesh,
      timeMs: timeMs,
      animationIndex: animationIndex,
    );
    final worldVertices = <Vector3>[];
    final worldNormals = <Vector3>[];
    final cameraVertices = <Vector3>[];
    for (var vertexIndex = 0; vertexIndex < mesh.vertices.length; vertexIndex++) {
      final vertex = mesh.vertices[vertexIndex];
      Float64List? nodeMatrix;
      if (mesh.vertexNodeIndices.length == mesh.vertices.length) {
        final nodeIndex = mesh.vertexNodeIndices[vertexIndex];
        if (nodeIndex >= 0 && nodeIndex < nodeMatrices.length) {
          nodeMatrix = nodeMatrices[nodeIndex];
        }
      }
      final scenePosition = nodeMatrix == null
          ? vertex
          : sceneEvaluator.transformPoint(nodeMatrix, vertex);
      final local = Vector3(
        (scenePosition.x - center.x) * unitScale * modelTransform.scale.x / 100,
        (scenePosition.y - center.y) * unitScale * modelTransform.scale.y / 100,
        (scenePosition.z - center.z) * unitScale * modelTransform.scale.z / 100,
      );
      final rotated = _rotate(local, modelTransform.rotation);
      final world = Vector3(
        modelTransform.position.x + rotated.x,
        modelTransform.position.y + rotated.y,
        modelTransform.position.z + rotated.z,
      );
      worldVertices.add(world);
      if (mesh.vertexNormals.length == mesh.vertices.length) {
        final sourceNormal = mesh.vertexNormals[vertexIndex];
        final nodeNormal = nodeMatrix == null
            ? sourceNormal
            : sceneEvaluator.transformNormal(nodeMatrix, sourceNormal);
        final safeScaleX = modelTransform.scale.x.abs() < 1e-9
            ? 1.0
            : modelTransform.scale.x / 100;
        final safeScaleY = modelTransform.scale.y.abs() < 1e-9
            ? 1.0
            : modelTransform.scale.y / 100;
        final safeScaleZ = modelTransform.scale.z.abs() < 1e-9
            ? 1.0
            : modelTransform.scale.z / 100;
        worldNormals.add(_normalize(_rotate(
          Vector3(
            nodeNormal.x / safeScaleX,
            nodeNormal.y / safeScaleY,
            nodeNormal.z / safeScaleZ,
          ),
          modelTransform.rotation,
        )));
      } else {
        worldNormals.add(const Vector3(0, 0, 0));
      }

      final relativeToCamera = Vector3(
        world.x - cameraTransform.position.x,
        world.y - cameraTransform.position.y,
        world.z - cameraTransform.position.z,
      );
      cameraVertices.add(cameraResolver.worldToCameraOffset(
        relativeToCamera,
        cameraTransform.rotation,
      ));
    }

    final shadowMaps = List<_DirectionalShadowMap?>.generate(
      lights.length,
      (index) {
        final light = lights[index];
        if (light.settings.kind != LightKind.directional ||
            !light.settings.castShadows) {
          return null;
        }
        return _DirectionalShadowMap.build(
          worldVertices,
          mesh.triangles,
          direction: _normalize(_rotate(
            const Vector3(0, 0, 1),
            light.transform.rotation,
          )),
        );
      },
    );

    final faces = <ProjectedMeshTriangle>[];
    for (final triangle in mesh.triangles) {
      final worldA = worldVertices[triangle.a];
      final worldB = worldVertices[triangle.b];
      final worldC = worldVertices[triangle.c];
      final faceNormal = _normalize(_cross(
        _subtract(worldB, worldA),
        _subtract(worldC, worldA),
      ));
      final normal = mesh.vertexNormals.length == mesh.vertices.length
          ? _normalize(_add(
              _add(worldNormals[triangle.a], worldNormals[triangle.b]),
              worldNormals[triangle.c],
            ))
          : faceNormal;
      final shadingNormal = _length(normal) < 1e-9 ? faceNormal : normal;
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
      final twoSidedNormal = _dot(shadingNormal, viewDirection) < 0
          ? _multiply(shadingNormal, -1)
          : shadingNormal;

      var polygon = <_SceneVertex>[
        _SceneVertex(worldA, cameraVertices[triangle.a], focus),
        _SceneVertex(worldB, cameraVertices[triangle.b], focus),
        _SceneVertex(worldC, cameraVertices[triangle.c], focus),
      ];
      polygon = _clipPolygon(polygon, near, keepGreater: true);
      polygon = _clipPolygon(polygon, far, keepGreater: false);
      if (polygon.length < 3) continue;

      final material = mesh.materialFor(triangle);
      final color = _shade(
        material,
        twoSidedNormal,
        faceCenter,
        lights,
        shadowMaps,
      );

      _ProjectedVertex project(_SceneVertex vertex) {
        final factor = cameraResolver.projectionFactor(
          vertex.camera.z,
          cameraSettings,
        );
        final offsetX = centerOnModel
            ? vertex.camera.x * factor - centerCamera.x * centerFactor
            : cameraTransform.position.x +
                vertex.camera.x * factor -
                compositionWidth / 2;
        final offsetY = centerOnModel
            ? vertex.camera.y * factor - centerCamera.y * centerFactor
            : cameraTransform.position.y +
                vertex.camera.y * factor -
                compositionHeight / 2;
        return _ProjectedVertex(
          point: Offset(
            viewport.width / 2 + offsetX * pixelScale,
            viewport.height / 2 - offsetY * pixelScale,
          ),
          distance: vertex.distance,
          visible: true,
        );
      }

      final clipped = polygon.map(project).toList();
      for (var index = 1; index < clipped.length - 1; index++) {
        final a = clipped[0];
        final b = clipped[index];
        final c = clipped[index + 1];
        faces.add(ProjectedMeshTriangle(
          a: a.point,
          b: b.point,
          c: c.point,
          color: color,
          distance: (a.distance + b.distance + c.distance) / 3,
          distanceA: a.distance,
          distanceB: b.distance,
          distanceC: c.distance,
        ));
      }
    }

    // Painter's order: far faces first, near faces last.
    faces.sort((a, b) => b.distance.compareTo(a.distance));
    return faces;
  }

  /// Rasterizes the mesh into an RGBA frame using a per-pixel depth buffer.
  /// When [centerOnModel] is false, coordinates are composition-relative and
  /// can be used to produce a transparent full-frame export plate.
  Software3dFrame rasterizeFrame({
    required ObjMesh mesh,
    required int width,
    required int height,
    required double compositionWidth,
    required double compositionHeight,
    required ResolvedLayerTransform modelTransform,
    required ResolvedLayerTransform cameraTransform,
    required CameraSettings cameraSettings,
    List<SceneLight> lights = const [],
    bool centerOnModel = false,
    int timeMs = 0,
    int animationIndex = 0,
  }) {
    final triangles = projectTriangles(
      mesh: mesh,
      viewport: Size(width.toDouble(), height.toDouble()),
      baseWidth: compositionWidth,
      compositionWidth: compositionWidth,
      compositionHeight: compositionHeight,
      modelTransform: modelTransform,
      cameraTransform: cameraTransform,
      cameraSettings: cameraSettings,
      lights: lights,
      centerOnModel: centerOnModel,
      timeMs: timeMs,
      animationIndex: animationIndex,
    );
    return Software3dRasterizer().rasterize(
      triangles,
      width: width,
      height: height,
      depthOfField: cameraSettings.depthOfField,
      focusDistance: cameraSettings.focusDistance,
      aperture: cameraSettings.aperture,
    );
  }

  List<_SceneVertex> _clipPolygon(
    List<_SceneVertex> input,
    double plane, {
    required bool keepGreater,
  }) {
    if (input.isEmpty) return const [];
    final output = <_SceneVertex>[];
    bool inside(_SceneVertex vertex) =>
        keepGreater ? vertex.distance >= plane : vertex.distance <= plane;

    for (var index = 0; index < input.length; index++) {
      final current = input[index];
      final previous = input[(index + input.length - 1) % input.length];
      final currentInside = inside(current);
      final previousInside = inside(previous);

      if (currentInside != previousInside) {
        final delta = current.distance - previous.distance;
        final amount = delta.abs() < 1e-9
            ? 0.0
            : ((plane - previous.distance) / delta).clamp(0.0, 1.0).toDouble();
        output.add(_SceneVertex(
          _lerpVector(previous.world, current.world, amount),
          _lerpVector(previous.camera, current.camera, amount),
          plane,
        ));
      }
      if (currentInside) output.add(current);
    }
    return output;
  }

  Vector3 _lerpVector(Vector3 a, Vector3 b, double amount) => Vector3(
    a.x + (b.x - a.x) * amount,
    a.y + (b.y - a.y) * amount,
    a.z + (b.z - a.z) * amount,
  );

  Color _shade(
    ObjMaterial material,
    Vector3 normal,
    Vector3 faceCenter,
    List<SceneLight> lights,
    List<_DirectionalShadowMap?> shadowMaps,
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
      for (var lightIndex = 0; lightIndex < lights.length; lightIndex++) {
        final light = lights[lightIndex];
        final intensity = light.settings.intensity.clamp(0.0, 1000.0).toDouble() / 100.0;
        if (intensity <= 0) continue;
        final lightColor = _parseColor(light.settings.color);
        if (light.settings.kind == LightKind.ambient) {
          final amount = (intensity * 0.22).clamp(0.0, 1.0).toDouble();
          redLight += lightColor.r * amount;
          greenLight += lightColor.g * amount;
          blueLight += lightColor.b * amount;
          continue;
        }

        final samples = light.settings.kind == LightKind.area
            ? _areaLightSamples(light)
            : <Vector3>[light.transform.position];
        var totalContribution = 0.0;
        for (final samplePosition in samples) {
          Vector3 toLight;
          var attenuation = 1.0;
          if (light.settings.kind == LightKind.directional) {
            toLight = _normalize(_rotate(
              const Vector3(0, 0, 1),
              light.transform.rotation,
            ));
          } else {
            final delta = Vector3(
              samplePosition.x - faceCenter.x,
              samplePosition.y - faceCenter.y,
              samplePosition.z - faceCenter.z,
            );
            final distance = _length(delta);
            toLight = distance <= 0.0001
                ? const Vector3(0, 0, 1)
                : _multiply(delta, 1 / distance);
            attenuation = 1 / (1 + math.pow(distance / 1000, 2));
          }

          if (light.settings.kind == LightKind.spot) {
            final spotDirection = _normalize(_rotate(
              const Vector3(0, 0, -1),
              light.transform.rotation,
            ));
            final fromLight = _normalize(Vector3(
              faceCenter.x - samplePosition.x,
              faceCenter.y - samplePosition.y,
              faceCenter.z - samplePosition.z,
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
          totalContribution += diffuse * attenuation;
        }

        totalContribution /= samples.length;
        final shadowMap = shadowMaps[lightIndex];
        if (shadowMap != null && shadowMap.isOccluded(
          faceCenter,
          softness: light.settings.shadowSoftness,
        )) {
          totalContribution *= 0.20;
        }
        final amount = (intensity * 0.62 * totalContribution)
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

  List<Vector3> _areaLightSamples(SceneLight light) {
    final half = light.settings.areaSize.clamp(1.0, 1000.0).toDouble() / 2;
    return [
      for (final x in [-0.5, 0.5])
        for (final y in [-0.5, 0.5])
          _add(
            light.transform.position,
            _rotate(Vector3(half * x, half * y, 0), light.transform.rotation),
          ),
    ];
  }

  Vector3 _add(Vector3 a, Vector3 b) =>
      Vector3(a.x + b.x, a.y + b.y, a.z + b.z);

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

class _DirectionalShadowMap {
  const _DirectionalShadowMap({
    required this.width,
    required this.height,
    required this.minX,
    required this.minY,
    required this.rangeX,
    required this.rangeY,
    required this.right,
    required this.up,
    required this.direction,
    required this.depth,
  });

  final int width;
  final int height;
  final double minX;
  final double minY;
  final double rangeX;
  final double rangeY;
  final Vector3 right;
  final Vector3 up;
  final Vector3 direction;
  final Float32List depth;

  static _DirectionalShadowMap build(
    List<Vector3> vertices,
    List<ObjTriangle> triangles, {
    required Vector3 direction,
    int resolution = 192,
  }) {
    final upAxis = direction.y.abs() > 0.95
        ? const Vector3(1, 0, 0)
        : const Vector3(0, 1, 0);
    final right = _normalize(_cross(upAxis, direction));
    final up = _normalize(_cross(direction, right));
    final projected = vertices.map((point) => Vector3(
      _dot(point, right),
      _dot(point, up),
      _dot(point, direction),
    )).toList();
    final minX = projected.map((p) => p.x).reduce((a, b) => a < b ? a : b);
    final maxX = projected.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final minY = projected.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxY = projected.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final rangeX = math.max(0.001, maxX - minX).toDouble();
    final rangeY = math.max(0.001, maxY - minY).toDouble();
    final aspect = rangeX / rangeY;
    final width = (aspect >= 1
        ? resolution
        : math.max(16, (resolution * aspect).round())).toInt();
    final height = (aspect >= 1
        ? math.max(16, (resolution / aspect).round())
        : resolution).toInt();
    final depth = Float32List(width * height);
    depth.fillRange(0, depth.length, double.negativeInfinity);

    final screen = projected.map((point) => Offset(
      (point.x - minX) / rangeX * (width - 1),
      (maxY - point.y) / rangeY * (height - 1),
    )).toList();

    for (final triangle in triangles) {
      final a = screen[triangle.a];
      final b = screen[triangle.b];
      final c = screen[triangle.c];
      final minPixelX = math.max(0, math.min(a.dx, math.min(b.dx, c.dx)).floor()).toInt();
      final maxPixelX = math.min(width - 1, math.max(a.dx, math.max(b.dx, c.dx)).ceil()).toInt();
      final minPixelY = math.max(0, math.min(a.dy, math.min(b.dy, c.dy)).floor()).toInt();
      final maxPixelY = math.min(height - 1, math.max(a.dy, math.max(b.dy, c.dy)).ceil()).toInt();
      final area = _edge(a, b, c);
      if (area.abs() < 0.000001 || minPixelX > maxPixelX || minPixelY > maxPixelY) continue;

      final za = projected[triangle.a].z;
      final zb = projected[triangle.b].z;
      final zc = projected[triangle.c].z;
      for (var y = minPixelY; y <= maxPixelY; y++) {
        for (var x = minPixelX; x <= maxPixelX; x++) {
          final point = Offset(x + 0.5, y + 0.5);
          final wa = _edge(b, c, point) / area;
          final wb = _edge(c, a, point) / area;
          final wc = 1 - wa - wb;
          if (wa < -0.00001 || wb < -0.00001 || wc < -0.00001) continue;
          final z = wa * za + wb * zb + wc * zc;
          final index = y * width + x;
          if (z > depth[index]) depth[index] = z;
        }
      }
    }

    return _DirectionalShadowMap(
      width: width,
      height: height,
      minX: minX,
      minY: minY,
      rangeX: rangeX,
      rangeY: rangeY,
      right: right,
      up: up,
      direction: direction,
      depth: depth,
    );
  }

  bool isOccluded(Vector3 point, {double softness = 0}) {
    final x = _dot(point, right);
    final y = _dot(point, up);
    final z = _dot(point, direction);
    final pixelX = ((x - minX) / rangeX * (width - 1)).round();
    final pixelY = (((minY + rangeY) - y) / rangeY * (height - 1)).round();
    if (pixelX < 0 || pixelX >= width || pixelY < 0 || pixelY >= height) {
      return false;
    }
    final radius = (softness.clamp(0.0, 100.0) / 35).round().clamp(0, 3).toInt();
    var occludedSamples = 0;
    var testedSamples = 0;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final sx = pixelX + dx;
        final sy = pixelY + dy;
        if (sx < 0 || sx >= width || sy < 0 || sy >= height) continue;
        final nearest = depth[sy * width + sx];
        if (!nearest.isFinite) continue;
        testedSamples++;
        if (z < nearest - 0.001) occludedSamples++;
      }
    }
    return testedSamples > 0 && occludedSamples / testedSamples >= 0.35;
  }

  static double _dot(Vector3 a, Vector3 b) =>
      a.x * b.x + a.y * b.y + a.z * b.z;

  static Vector3 _cross(Vector3 a, Vector3 b) => Vector3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x,
  );

  static Vector3 _normalize(Vector3 value) {
    final length = math.sqrt(_dot(value, value));
    if (length <= 0.000001) return const Vector3(0, 0, 1);
    return Vector3(value.x / length, value.y / length, value.z / length);
  }

  static double _edge(Offset a, Offset b, Offset p) =>
      (p.dx - a.dx) * (b.dy - a.dy) -
      (p.dy - a.dy) * (b.dx - a.dx);
}

class Software3dFrame {
  const Software3dFrame({
    required this.width,
    required this.height,
    required this.rgba,
    required this.depth,
  });

  final int width;
  final int height;
  final Uint8List rgba;
  final Float32List depth;
}

class Software3dRasterizer {
  Software3dFrame rasterize(
    List<ProjectedMeshTriangle> triangles, {
    required int width,
    required int height,
    bool depthOfField = false,
    double focusDistance = 1000,
    double aperture = 2.8,
    int maximumDofRadius = 3,
  }) {
    if (width <= 0 || height <= 0 || width * height > 16000000) {
      throw ArgumentError('Raster dimensions must be positive and at most 16 MP.');
    }
    final pixelCount = width * height;
    final rgba = Uint8List(pixelCount * 4);
    final depth = Float32List(pixelCount);
    depth.fillRange(0, depth.length, double.infinity);

    for (final triangle in triangles) {
      final minX = math.max(0, math.min(triangle.a.dx,
          math.min(triangle.b.dx, triangle.c.dx)).floor()).toInt();
      final maxX = math.min(width - 1, math.max(triangle.a.dx,
          math.max(triangle.b.dx, triangle.c.dx)).ceil()).toInt();
      final minY = math.max(0, math.min(triangle.a.dy,
          math.min(triangle.b.dy, triangle.c.dy)).floor()).toInt();
      final maxY = math.min(height - 1, math.max(triangle.a.dy,
          math.max(triangle.b.dy, triangle.c.dy)).ceil()).toInt();
      final area = _edge(triangle.a, triangle.b, triangle.c);
      if (area.abs() < 0.000001 || minX > maxX || minY > maxY) continue;

      for (var y = minY; y <= maxY; y++) {
        for (var x = minX; x <= maxX; x++) {
          final point = Offset(x + 0.5, y + 0.5);
          final w0 = _edge(triangle.b, triangle.c, point) / area;
          final w1 = _edge(triangle.c, triangle.a, point) / area;
          final w2 = 1 - w0 - w1;
          if (w0 < -0.00001 || w1 < -0.00001 || w2 < -0.00001) continue;

          final z = triangle.perspective
              ? 1 /
                  (w0 / triangle.distanceA +
                      w1 / triangle.distanceB +
                      w2 / triangle.distanceC)
              : w0 * triangle.distanceA +
                  w1 * triangle.distanceB +
                  w2 * triangle.distanceC;
          final pixel = y * width + x;
          if (z >= depth[pixel]) continue;
          final alpha =
              (triangle.color.a * 255).round().clamp(0, 255).toInt();
          if (alpha <= 0) continue;
          depth[pixel] = z;
          final offset = pixel * 4;
          final inverse = 255 - alpha;
          rgba[offset] = (triangle.color.r * 255 +
                  rgba[offset] * inverse / 255)
              .round()
              .clamp(0, 255)
              .toInt();
          rgba[offset + 1] = (triangle.color.g * 255 +
                  rgba[offset + 1] * inverse / 255)
              .round()
              .clamp(0, 255)
              .toInt();
          rgba[offset + 2] = (triangle.color.b * 255 +
                  rgba[offset + 2] * inverse / 255)
              .round()
              .clamp(0, 255)
              .toInt();
          rgba[offset + 3] = (alpha +
                  rgba[offset + 3] * inverse / 255)
              .round()
              .clamp(0, 255)
              .toInt();
        }
      }
    }

    if (depthOfField) {
      _applyDepthOfField(
        rgba,
        depth,
        width,
        height,
        focusDistance,
        aperture,
        maximumDofRadius.clamp(0, 6),
      );
    }
    return Software3dFrame(
      width: width,
      height: height,
      rgba: rgba,
      depth: depth,
    );
  }

  void _applyDepthOfField(
    Uint8List rgba,
    Float32List depth,
    int width,
    int height,
    double focusDistance,
    double aperture,
    int maxRadius,
  ) {
    if (maxRadius == 0) return;
    final source = Uint8List.fromList(rgba);
    final focus = math.max(1.0, focusDistance);
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final pixel = y * width + x;
        if (!depth[pixel].isFinite) continue;
        final blur = ((depth[pixel] - focus).abs() / focus) *
            aperture.clamp(0.7, 22.0) *
            1.15;
        final radius = blur.round().clamp(0, maxRadius).toInt();
        if (radius == 0 ||
            x - radius < 0 ||
            x + radius >= width ||
            y - radius < 0 ||
            y + radius >= height) {
          continue;
        }
        var red = 0;
        var green = 0;
        var blue = 0;
        var alpha = 0;
        var samples = 0;
        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final index = ((y + dy) * width + x + dx) * 4;
            red += source[index];
            green += source[index + 1];
            blue += source[index + 2];
            alpha += source[index + 3];
            samples++;
          }
        }
        final target = pixel * 4;
        final mix = (blur / (maxRadius + 1)).clamp(0.0, 0.85);
        rgba[target] = (source[target] * (1 - mix) + red / samples * mix).round();
        rgba[target + 1] =
            (source[target + 1] * (1 - mix) + green / samples * mix).round();
        rgba[target + 2] =
            (source[target + 2] * (1 - mix) + blue / samples * mix).round();
        rgba[target + 3] =
            (source[target + 3] * (1 - mix) + alpha / samples * mix).round();
      }
    }
  }

  double _edge(Offset a, Offset b, Offset p) =>
      (p.dx - a.dx) * (b.dy - a.dy) -
      (p.dy - a.dy) * (b.dx - a.dx);
}

class _SceneVertex {
  const _SceneVertex(this.world, this.camera, this.distance);

  final Vector3 world;
  final Vector3 camera;
  final double distance;
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
