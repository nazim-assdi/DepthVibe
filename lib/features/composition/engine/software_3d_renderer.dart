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
    this.uvA = Offset.zero,
    this.uvB = Offset.zero,
    this.uvC = Offset.zero,
    this.textureRgba,
    this.textureWidth = 0,
    this.textureHeight = 0,
    this.alphaMode = 'OPAQUE',
    this.alphaCutoff = 0.5,
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
  final Offset uvA;
  final Offset uvB;
  final Offset uvC;
  final Uint8List? textureRgba;
  final int textureWidth;
  final int textureHeight;
  final String alphaMode;
  final double alphaCutoff;
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

    final shadowMaps = List<_SceneShadowMap?>.generate(
      lights.length,
      (index) {
        final light = lights[index];
        if (!light.settings.castShadows ||
            light.settings.kind == LightKind.ambient) {
          return null;
        }
        return _createShadowMapForLight(
          light,
          worldVertices,
          mesh.triangles,
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

      final material = mesh.materialFor(triangle);
      Offset uvAt(int vertexIndex) {
        final uv = mesh.hasTextureCoordinates &&
                mesh.textureCoordinates.length == mesh.vertices.length
            ? mesh.textureCoordinates[vertexIndex]
            : Offset.zero;
        final textureMap = material.baseColorTextureMap;
        if (textureMap == null || textureMap.texCoord != 0) return uv;
        return textureMap.transformUv(uv);
      }
      var polygon = <_SceneVertex>[
        _SceneVertex(worldA, cameraVertices[triangle.a], focus, uvAt(triangle.a)),
        _SceneVertex(worldB, cameraVertices[triangle.b], focus, uvAt(triangle.b)),
        _SceneVertex(worldC, cameraVertices[triangle.c], focus, uvAt(triangle.c)),
      ];
      polygon = _clipPolygon(polygon, near, keepGreater: true);
      polygon = _clipPolygon(polygon, far, keepGreater: false);
      if (polygon.length < 3) continue;

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
          uv: vertex.uv,
        );
      }

      final clipped = polygon.map(project).toList();
      for (var index = 1; index < clipped.length - 1; index++) {
        final a = clipped[0];
        final b = clipped[index];
        final c = clipped[index + 1];
        final triangleHasUvs = [a.uv, b.uv, c.uv].every(
          (uv) => uv.dx.isFinite && uv.dy.isFinite,
        );
        final textureIsUsable = triangleHasUvs &&
            mesh.hasTextureCoordinates &&
            (material.baseColorTextureMap == null ||
                material.baseColorTextureMap!.texCoord == 0) &&
            material.baseColorTextureRgba != null &&
            material.baseColorTextureWidth > 0 &&
            material.baseColorTextureHeight > 0 &&
            material.baseColorTextureRgba!.length ==
                material.baseColorTextureWidth * material.baseColorTextureHeight * 4;
        faces.add(ProjectedMeshTriangle(
          a: a.point,
          b: b.point,
          c: c.point,
          color: color,
          distance: (a.distance + b.distance + c.distance) / 3,
          distanceA: a.distance,
          distanceB: b.distance,
          distanceC: c.distance,
          uvA: a.uv,
          uvB: b.uv,
          uvC: c.uv,
          textureRgba: textureIsUsable ? material.baseColorTextureRgba : null,
          textureWidth: textureIsUsable ? material.baseColorTextureWidth : 0,
          textureHeight: textureIsUsable ? material.baseColorTextureHeight : 0,
          alphaMode: material.alphaMode,
          alphaCutoff: material.alphaCutoff,
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
      focalLength: cameraSettings.focalLength,
      sensorWidthMm: cameraSettings.sensorWidthMm,
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
          _lerpOffset(previous.uv, current.uv, amount),
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

  Offset _lerpOffset(Offset a, Offset b, double amount) => Offset(
    a.dx + (b.dx - a.dx) * amount,
    a.dy + (b.dy - a.dy) * amount,
  );

  Color _shade(
    ObjMaterial material,
    Vector3 normal,
    Vector3 faceCenter,
    List<SceneLight> lights,
    List<_SceneShadowMap?> shadowMaps,
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
        final intensity =
            light.settings.intensity.clamp(0.0, 1000.0).toDouble() / 100.0;
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
            ? areaLightSamplePositions(light)
            : <Vector3>[light.transform.position];
        final shadowMap = shadowMaps[lightIndex];
        final shadowVisibility = shadowMap?.visibilityAt(
              faceCenter,
              softness: light.settings.shadowSoftness,
            ) ??
            1.0;
        var totalContribution = 0.0;

        for (final samplePosition in samples) {
          Vector3 toLight;
          var attenuation = 1.0;
          var emitterCosine = 1.0;
          var distance = double.infinity;

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
            distance = _length(delta);
            toLight = distance <= 0.0001
                ? const Vector3(0, 0, 1)
                : _multiply(delta, 1 / distance);

            // Inverse-square falloff, referenced to one scene unit of 1000.
            attenuation = 1 /
                math.max(0.01, math.pow(distance / 1000, 2).toDouble());

            if (light.settings.kind == LightKind.spot ||
                light.settings.kind == LightKind.area) {
              final emitterDirection = _normalize(_rotate(
                const Vector3(0, 0, -1),
                light.transform.rotation,
              ));
              final fromLight = _multiply(toLight, -1);
              emitterCosine =
                  _dot(emitterDirection, fromLight).clamp(0.0, 1.0).toDouble();
              if (emitterCosine <= 0) continue;
            }
          }

          if (light.settings.kind == LightKind.spot) {
            final spotDirection = _normalize(_rotate(
              const Vector3(0, 0, -1),
              light.transform.rotation,
            ));
            final fromLight = _multiply(toLight, -1);
            final alignment = _dot(spotDirection, fromLight);
            final cutoff = math.cos(
              light.settings.coneAngle.clamp(1.0, 175.0) * math.pi / 360,
            );
            if (alignment <= cutoff) continue;
            final coneWidth = math.max(0.0001, 1 - cutoff);
            attenuation *= ((alignment - cutoff) / coneWidth)
                .clamp(0.0, 1.0)
                .toDouble();
          }

          if (light.settings.kind == LightKind.area) {
            final size = light.settings.areaSize.clamp(1.0, 1000.0);
            attenuation *= emitterCosine * math.pow(size / 160, 2).toDouble();
          }

          final diffuse = _dot(normal, toLight).clamp(0.0, 1.0).toDouble();
          totalContribution += diffuse * attenuation * shadowVisibility;
        }

        totalContribution /= samples.length;
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
      channel(material.red * redLight + material.emissiveRed),
      channel(material.green * greenLight + material.emissiveGreen),
      channel(material.blue * blueLight + material.emissiveBlue),
    );
  }

  /// Deterministic Hammersley samples over a rectangular area emitter.
  ///
  /// The radical-inverse sequence distributes samples across the full emitter
  /// without random frame-to-frame noise. The result is stable for preview
  /// rendering, playback and export.
  List<Vector3> areaLightSamplePositions(SceneLight light) {
    final count = light.settings.areaSamples.clamp(1, 64).toInt();
    final half = light.settings.areaSize.clamp(1.0, 1000.0).toDouble() / 2;
    return List<Vector3>.generate(count, (index) {
      final x = (index + 0.5) / count - 0.5;
      final y = _radicalInverse(index) - 0.5;
      return _add(
        light.transform.position,
        _rotate(Vector3(half * x * 2, half * y * 2, 0),
            light.transform.rotation),
      );
    }, growable: false);
  }

  double _radicalInverse(int value) {
    var n = value;
    var inverse = 0.0;
    var factor = 0.5;
    while (n > 0) {
      inverse += (n & 1).toDouble() * factor;
      n >>= 1;
      factor *= 0.5;
    }
    return inverse;
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

abstract interface class _SceneShadowMap {
  double visibilityAt(Vector3 point, {double softness = 0});
}

/// Public diagnostic wrapper for validating the active scene-light shadow map.
class Software3dShadowMap {
  const Software3dShadowMap._(this._map);

  final _SceneShadowMap _map;

  factory Software3dShadowMap.forLight({
    required SceneLight light,
    required List<Vector3> vertices,
    required List<ObjTriangle> triangles,
    int resolution = 128,
  }) {
    final map = _createShadowMapForLight(
      light,
      vertices,
      triangles,
      resolution: resolution,
    );
    if (map == null) {
      throw ArgumentError('Ambient lights do not cast shadow maps.');
    }
    return Software3dShadowMap._(map);
  }

  double visibilityAt(Vector3 point, {double softness = 0}) =>
      _map.visibilityAt(point, softness: softness);
}

_SceneShadowMap? _createShadowMapForLight(
  SceneLight light,
  List<Vector3> vertices,
  List<ObjTriangle> triangles, {
  int resolution = 128,
}) {
  if (vertices.isEmpty || triangles.isEmpty) return null;
  final position = light.transform.position;
  switch (light.settings.kind) {
    case LightKind.ambient:
      return null;
    case LightKind.directional:
      return _DirectionalShadowMap.build(
        vertices,
        triangles,
        direction: _normalizeShadow(_rotateShadow(
          const Vector3(0, 0, 1),
          light.transform.rotation,
        )),
        resolution: math.max(32, resolution).toInt(),
      );
    case LightKind.spot:
      final forward = _normalizeShadow(_rotateShadow(
        const Vector3(0, 0, -1),
        light.transform.rotation,
      ));
      return _SpotShadowMap.build(
        vertices,
        triangles,
        origin: position,
        forward: forward,
        coneAngle: light.settings.coneAngle,
        resolution: resolution,
      );
    case LightKind.point:
    case LightKind.area:
      return _PointShadowMap.build(
        vertices,
        triangles,
        origin: position,
        resolution: resolution,
      );
  }
}

Vector3 _rotateShadow(Vector3 value, Vector3 degrees) {
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
  return Vector3(x2 * cz - y1 * sz, x2 * sz + y1 * cz, z2);
}

Vector3 _normalizeShadow(Vector3 value) {
  final length = math.sqrt(
    value.x * value.x + value.y * value.y + value.z * value.z,
  );
  if (length <= 0.000001) return const Vector3(0, 0, 1);
  return Vector3(value.x / length, value.y / length, value.z / length);
}

double _dotShadow(Vector3 a, Vector3 b) =>
    a.x * b.x + a.y * b.y + a.z * b.z;

Vector3 _crossShadow(Vector3 a, Vector3 b) => Vector3(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x,
    );

class _DirectionalShadowMap implements _SceneShadowMap {
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
    final right = _normalizeShadow(_crossShadow(upAxis, direction));
    final up = _normalizeShadow(_crossShadow(direction, right));
    final projected = vertices.map((point) => Vector3(
      _dotShadow(point, right),
      _dotShadow(point, up),
      _dotShadow(point, direction),
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
      final area = _edgeShadow(a, b, c);
      if (area.abs() < 0.000001) continue;
      final minPixelX =
          math.max(0, math.min(a.dx, math.min(b.dx, c.dx)).floor()).toInt();
      final maxPixelX = math
          .min(width - 1, math.max(a.dx, math.max(b.dx, c.dx)).ceil())
          .toInt();
      final minPixelY =
          math.max(0, math.min(a.dy, math.min(b.dy, c.dy)).floor()).toInt();
      final maxPixelY = math
          .min(height - 1, math.max(a.dy, math.max(b.dy, c.dy)).ceil())
          .toInt();
      if (minPixelX > maxPixelX || minPixelY > maxPixelY) continue;
      final za = projected[triangle.a].z;
      final zb = projected[triangle.b].z;
      final zc = projected[triangle.c].z;
      for (var y = minPixelY; y <= maxPixelY; y++) {
        for (var x = minPixelX; x <= maxPixelX; x++) {
          final p = Offset(x + 0.5, y + 0.5);
          final wa = _edgeShadow(b, c, p) / area;
          final wb = _edgeShadow(c, a, p) / area;
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

  @override
  double visibilityAt(Vector3 point, {double softness = 0}) {
    final x = _dotShadow(point, right);
    final y = _dotShadow(point, up);
    final z = _dotShadow(point, direction);
    final pixelX = ((x - minX) / rangeX * (width - 1)).round();
    final pixelY = (((minY + rangeY) - y) / rangeY * (height - 1)).round();
    if (pixelX < 0 || pixelX >= width || pixelY < 0 || pixelY >= height) {
      return 1;
    }
    final radius = (softness.clamp(0.0, 100.0) / 20)
        .round()
        .clamp(0, 5)
        .toInt();
    final bias = math.max(0.5, z.abs() * 0.0005);
    var visible = 0.0;
    var samples = 0;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final sx = pixelX + dx;
        final sy = pixelY + dy;
        samples++;
        if (sx < 0 || sx >= width || sy < 0 || sy >= height) {
          visible += 1;
          continue;
        }
        final nearest = depth[sy * width + sx];
        if (!nearest.isFinite || z >= nearest - bias) visible += 1;
      }
    }
    return samples == 0 ? 1 : visible / samples;
  }
}

class _SpotShadowMap implements _SceneShadowMap {
  const _SpotShadowMap(this._projection);

  final _PerspectiveShadowMap _projection;

  static _SpotShadowMap build(
    List<Vector3> vertices,
    List<ObjTriangle> triangles, {
    required Vector3 origin,
    required Vector3 forward,
    required double coneAngle,
    int resolution = 128,
  }) {
    final maxDistance = vertices
        .map((v) => math.sqrt(
              math.pow(v.x - origin.x, 2) +
                  math.pow(v.y - origin.y, 2) +
                  math.pow(v.z - origin.z, 2),
            ))
        .reduce((a, b) => a > b ? a : b);
    final far = math.max(10.0, maxDistance * 1.05).toDouble();
    return _SpotShadowMap(_PerspectiveShadowMap.build(
      vertices,
      triangles,
      origin: origin,
      forward: forward,
      upAxis: math.sqrt(forward.x * forward.x + forward.z * forward.z) < 0.001
          ? const Vector3(0, 0, 1)
          : const Vector3(0, 1, 0),
      halfFovRadians:
          coneAngle.clamp(2.0, 175.0) * math.pi / 360,
      near: math.max(0.1, far * 0.0005).toDouble(),
      far: far,
      resolution: resolution,
    ));
  }

  @override
  double visibilityAt(Vector3 point, {double softness = 0}) =>
      _projection.visibilityAt(point, softness: softness);
}

class _PointShadowMap implements _SceneShadowMap {
  const _PointShadowMap(this.origin, this.faces);

  final Vector3 origin;
  final List<_PerspectiveShadowMap> faces;

  static _PointShadowMap build(
    List<Vector3> vertices,
    List<ObjTriangle> triangles, {
    required Vector3 origin,
    int resolution = 128,
  }) {
    final maxDistance = vertices
        .map((v) => math.sqrt(
              math.pow(v.x - origin.x, 2) +
                  math.pow(v.y - origin.y, 2) +
                  math.pow(v.z - origin.z, 2),
            ))
        .reduce((a, b) => a > b ? a : b);
    final far = math.max(10.0, maxDistance * 1.05).toDouble();
    final near = math.max(0.1, far * 0.0005).toDouble();
    const directions = [
      Vector3(1, 0, 0),
      Vector3(-1, 0, 0),
      Vector3(0, 1, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, 1),
      Vector3(0, 0, -1),
    ];
    const upAxes = [
      Vector3(0, 1, 0),
      Vector3(0, 1, 0),
      Vector3(0, 0, -1),
      Vector3(0, 0, 1),
      Vector3(0, 1, 0),
      Vector3(0, 1, 0),
    ];
    final faces = List<_PerspectiveShadowMap>.generate(6, (index) {
      return _PerspectiveShadowMap.build(
        vertices,
        triangles,
        origin: origin,
        forward: directions[index],
        upAxis: upAxes[index],
        halfFovRadians: math.pi / 4,
        near: near,
        far: far,
        resolution: resolution,
      );
    }, growable: false);
    return _PointShadowMap(origin, faces);
  }

  @override
  double visibilityAt(Vector3 point, {double softness = 0}) {
    final delta = Vector3(
      point.x - origin.x,
      point.y - origin.y,
      point.z - origin.z,
    );
    final ax = delta.x.abs();
    final ay = delta.y.abs();
    final az = delta.z.abs();
    final faceIndex = ax >= ay && ax >= az
        ? (delta.x >= 0 ? 0 : 1)
        : ay >= ax && ay >= az
            ? (delta.y >= 0 ? 2 : 3)
            : (delta.z >= 0 ? 4 : 5);
    return faces[faceIndex].visibilityAt(point, softness: softness);
  }
}

class _ShadowVertex {
  const _ShadowVertex(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _ShadowVertex lerp(_ShadowVertex other, double t) => _ShadowVertex(
        x + (other.x - x) * t,
        y + (other.y - y) * t,
        z + (other.z - z) * t,
      );
}

class _PerspectiveShadowMap implements _SceneShadowMap {
  const _PerspectiveShadowMap({
    required this.origin,
    required this.right,
    required this.up,
    required this.forward,
    required this.halfFovTangent,
    required this.near,
    required this.far,
    required this.width,
    required this.height,
    required this.depth,
  });

  final Vector3 origin;
  final Vector3 right;
  final Vector3 up;
  final Vector3 forward;
  final double halfFovTangent;
  final double near;
  final double far;
  final int width;
  final int height;
  final Float32List depth;

  static _PerspectiveShadowMap build(
    List<Vector3> vertices,
    List<ObjTriangle> triangles, {
    required Vector3 origin,
    required Vector3 forward,
    required Vector3 upAxis,
    required double halfFovRadians,
    required double near,
    required double far,
    required int resolution,
  }) {
    final normalizedForward = _normalizeShadow(forward);
    final right = _normalizeShadow(_crossShadow(upAxis, normalizedForward));
    final up = _normalizeShadow(_crossShadow(normalizedForward, right));
    final halfFovTangent =
        math.tan(halfFovRadians.clamp(0.001, math.pi / 2 - 0.001));
    final width = resolution.clamp(32, 512).toInt();
    final height = resolution.clamp(32, 512).toInt();
    final depth = Float32List(width * height);
    depth.fillRange(0, depth.length, double.infinity);

    final localVertices = vertices.map((point) {
      final delta = Vector3(
        point.x - origin.x,
        point.y - origin.y,
        point.z - origin.z,
      );
      return _ShadowVertex(
        _dotShadow(delta, right),
        _dotShadow(delta, up),
        _dotShadow(delta, normalizedForward),
      );
    }).toList();

    double planeValue(_ShadowVertex v, int plane) => switch (plane) {
          0 => v.z - near,
          1 => far - v.z,
          2 => v.x + v.z * halfFovTangent,
          3 => v.z * halfFovTangent - v.x,
          4 => v.y + v.z * halfFovTangent,
          _ => v.z * halfFovTangent - v.y,
        };

    List<_ShadowVertex> clip(
        List<_ShadowVertex> polygon, int plane) {
      if (polygon.isEmpty) return const [];
      final output = <_ShadowVertex>[];
      for (var i = 0; i < polygon.length; i++) {
        final current = polygon[i];
        final previous = polygon[(i + polygon.length - 1) % polygon.length];
        final currentValue = planeValue(current, plane);
        final previousValue = planeValue(previous, plane);
        final currentInside = currentValue >= 0;
        final previousInside = previousValue >= 0;
        if (currentInside != previousInside) {
          final denominator = previousValue - currentValue;
          final t = denominator.abs() < 1e-12
              ? 0.0
              : (previousValue / denominator).clamp(0.0, 1.0).toDouble();
          output.add(previous.lerp(current, t));
        }
        if (currentInside) output.add(current);
      }
      return output;
    }

    for (final triangle in triangles) {
      var polygon = <_ShadowVertex>[
        localVertices[triangle.a],
        localVertices[triangle.b],
        localVertices[triangle.c],
      ];
      for (var plane = 0; plane < 6 && polygon.isNotEmpty; plane++) {
        polygon = clip(polygon, plane);
      }
      if (polygon.length < 3) continue;

      Offset project(_ShadowVertex v) {
        final nx = v.x / (v.z * halfFovTangent);
        final ny = v.y / (v.z * halfFovTangent);
        return Offset(
          (nx * 0.5 + 0.5) * (width - 1),
          (0.5 - ny * 0.5) * (height - 1),
        );
      }

      final projected = polygon.map(project).toList();
      for (var i = 1; i < polygon.length - 1; i++) {
        final a = projected[0];
        final b = projected[i];
        final c = projected[i + 1];
        final area = _edgeShadow(a, b, c);
        if (area.abs() < 1e-8) continue;
        final minX =
            math.max(0, math.min(a.dx, math.min(b.dx, c.dx)).floor()).toInt();
        final maxX = math
            .min(width - 1, math.max(a.dx, math.max(b.dx, c.dx)).ceil())
            .toInt();
        final minY =
            math.max(0, math.min(a.dy, math.min(b.dy, c.dy)).floor()).toInt();
        final maxY = math
            .min(height - 1, math.max(a.dy, math.max(b.dy, c.dy)).ceil())
            .toInt();
        final za = polygon[0].z;
        final zb = polygon[i].z;
        final zc = polygon[i + 1].z;
        for (var y = minY; y <= maxY; y++) {
          for (var x = minX; x <= maxX; x++) {
            final p = Offset(x + 0.5, y + 0.5);
            final wa = _edgeShadow(b, c, p) / area;
            final wb = _edgeShadow(c, a, p) / area;
            final wc = 1 - wa - wb;
            if (wa < -1e-5 || wb < -1e-5 || wc < -1e-5) continue;
            final z = 1 / (wa / za + wb / zb + wc / zc);
            final index = y * width + x;
            if (z < depth[index]) depth[index] = z;
          }
        }
      }
    }

    return _PerspectiveShadowMap(
      origin: origin,
      right: right,
      up: up,
      forward: normalizedForward,
      halfFovTangent: halfFovTangent,
      near: near,
      far: far,
      width: width,
      height: height,
      depth: depth,
    );
  }

  @override
  double visibilityAt(Vector3 point, {double softness = 0}) {
    final delta = Vector3(
      point.x - origin.x,
      point.y - origin.y,
      point.z - origin.z,
    );
    final x = _dotShadow(delta, right);
    final y = _dotShadow(delta, up);
    final z = _dotShadow(delta, forward);
    if (z < near || z > far) return 1;
    final nx = x / (z * halfFovTangent);
    final ny = y / (z * halfFovTangent);
    if (nx < -1 || nx > 1 || ny < -1 || ny > 1) return 1;
    final pixelX = ((nx * 0.5 + 0.5) * (width - 1)).round();
    final pixelY = ((0.5 - ny * 0.5) * (height - 1)).round();
    final radius = (softness.clamp(0.0, 100.0) / 20)
        .round()
        .clamp(0, 5)
        .toInt();
    final bias = math.max(0.5, z * 0.0005);
    var visible = 0.0;
    var samples = 0;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final sx = pixelX + dx;
        final sy = pixelY + dy;
        samples++;
        if (sx < 0 || sx >= width || sy < 0 || sy >= height) {
          visible += 1;
          continue;
        }
        final nearest = depth[sy * width + sx];
        if (!nearest.isFinite || z <= nearest + bias) visible += 1;
      }
    }
    return samples == 0 ? 1 : visible / samples;
  }
}

double _edgeShadow(Offset a, Offset b, Offset p) =>
    (p.dx - a.dx) * (b.dy - a.dy) -
    (p.dy - a.dy) * (b.dx - a.dx);

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

/// Thin-lens depth-of-field circle-of-confusion model.
class DepthOfFieldModel {
  const DepthOfFieldModel._();

  /// Returns the CoC radius in pixels for a 36 mm reference sensor.
  ///
  /// Inputs use the same scene-distance unit as CameraSettings.
  static double circleOfConfusionRadiusPixels({
    required double objectDistance,
    required double focusDistance,
    required double focalLength,
    required double fNumber,
    required double pixelsPerMillimetre,
  }) {
    final focal = focalLength.clamp(1.0, 300.0).toDouble();
    final object = objectDistance.clamp(focal + 0.001, 10000000.0).toDouble();
    final focus = focusDistance.clamp(focal + 0.001, 10000000.0).toDouble();
    final aperture = fNumber.clamp(0.7, 32.0).toDouble();
    final sensorScale = pixelsPerMillimetre.clamp(0.01, 10000.0).toDouble();
    final cocDiameterMm = focal * focal * (object - focus).abs() /
        (aperture * object * (focus - focal));
    return cocDiameterMm * sensorScale / 2;
  }
}

class Software3dRasterizer {
  Software3dFrame rasterize(
    List<ProjectedMeshTriangle> triangles, {
    required int width,
    required int height,
    bool depthOfField = false,
    double focusDistance = 1000,
    double aperture = 2.8,
    double focalLength = 50,
    double sensorWidthMm = 36,
    int maximumDofRadius = 6,
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
          final texel = triangle.textureRgba == null
              ? 0xFFFFFFFF
              : _sampleTexture(triangle, w0, w1, w2);
          final texelAlpha = texel & 0xFF;
          final materialAlpha = (triangle.color.a * 255)
              .round()
              .clamp(0, 255)
              .toInt();
          final combinedAlpha = (materialAlpha * texelAlpha / 255)
              .round()
              .clamp(0, 255)
              .toInt();
          if (triangle.alphaMode == 'MASK' &&
              combinedAlpha / 255 < triangle.alphaCutoff.clamp(0.0, 1.0)) {
            continue;
          }
          final alpha = triangle.alphaMode == 'OPAQUE' ||
                  triangle.alphaMode == 'MASK'
              ? 255
              : combinedAlpha;
          if (alpha <= 0) continue;
          depth[pixel] = z;
          final offset = pixel * 4;
          final inverse = 255 - alpha;
          final textureRed = (texel >> 24) & 0xFF;
          final textureGreen = (texel >> 16) & 0xFF;
          final textureBlue = (texel >> 8) & 0xFF;
          rgba[offset] = (triangle.color.r * textureRed +
                  rgba[offset] * inverse / 255)
              .round()
              .clamp(0, 255)
              .toInt();
          rgba[offset + 1] = (triangle.color.g * textureGreen +
                  rgba[offset + 1] * inverse / 255)
              .round()
              .clamp(0, 255)
              .toInt();
          rgba[offset + 2] = (triangle.color.b * textureBlue +
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
        focalLength,
        sensorWidthMm,
        maximumDofRadius.clamp(0, 6).toInt(),
      );
    }
    return Software3dFrame(
      width: width,
      height: height,
      rgba: rgba,
      depth: depth,
    );
  }

  int _sampleTexture(
    ProjectedMeshTriangle triangle,
    double w0,
    double w1,
    double w2,
  ) {
    final texture = triangle.textureRgba;
    final width = triangle.textureWidth;
    final height = triangle.textureHeight;
    if (texture == null || width <= 0 || height <= 0) return 0xFFFFFFFF;

    double u;
    double v;
    if (triangle.perspective) {
      final reciprocal = w0 / triangle.distanceA +
          w1 / triangle.distanceB +
          w2 / triangle.distanceC;
      if (reciprocal.abs() < 1e-9) return 0xFFFFFFFF;
      u = (w0 * triangle.uvA.dx / triangle.distanceA +
              w1 * triangle.uvB.dx / triangle.distanceB +
              w2 * triangle.uvC.dx / triangle.distanceC) /
          reciprocal;
      v = (w0 * triangle.uvA.dy / triangle.distanceA +
              w1 * triangle.uvB.dy / triangle.distanceB +
              w2 * triangle.uvC.dy / triangle.distanceC) /
          reciprocal;
    } else {
      u = w0 * triangle.uvA.dx + w1 * triangle.uvB.dx + w2 * triangle.uvC.dx;
      v = w0 * triangle.uvA.dy + w1 * triangle.uvB.dy + w2 * triangle.uvC.dy;
    }

    // Default glTF sampler behaviour is REPEAT with bilinear filtering.
    u -= u.floorToDouble();
    v -= v.floorToDouble();
    final sampleX = u * width - 0.5;
    final sampleY = v * height - 0.5;
    final x0 = sampleX.floor();
    final y0 = sampleY.floor();
    final tx = sampleX - x0;
    final ty = sampleY - y0;
    int wrap(int value, int extent) => (value % extent + extent) % extent;
    double channel(int component) {
      final xA = wrap(x0, width);
      final xB = wrap(x0 + 1, width);
      final yA = wrap(y0, height);
      final yB = wrap(y0 + 1, height);
      final c00 = texture[(yA * width + xA) * 4 + component].toDouble();
      final c10 = texture[(yA * width + xB) * 4 + component].toDouble();
      final c01 = texture[(yB * width + xA) * 4 + component].toDouble();
      final c11 = texture[(yB * width + xB) * 4 + component].toDouble();
      final top = c00 + (c10 - c00) * tx;
      final bottom = c01 + (c11 - c01) * tx;
      return top + (bottom - top) * ty;
    }

    final red = channel(0).round().clamp(0, 255).toInt();
    final green = channel(1).round().clamp(0, 255).toInt();
    final blue = channel(2).round().clamp(0, 255).toInt();
    final alpha = channel(3).round().clamp(0, 255).toInt();
    return (red << 24) | (green << 16) | (blue << 8) | alpha;
  }

  void _applyDepthOfField(
    Uint8List rgba,
    Float32List depth,
    int width,
    int height,
    double focusDistance,
    double aperture,
    double focalLength,
    double sensorWidthMm,
    int maxRadius,
  ) {
    if (maxRadius == 0) return;
    final source = Uint8List.fromList(rgba);
    final focus = math.max(focalLength + 0.01, focusDistance).toDouble();
    final fNumber = aperture.clamp(0.7, 32.0).toDouble();
    final focal = focalLength.clamp(1.0, 300.0).toDouble();
    final pixelsPerMillimetre =
        width / sensorWidthMm.clamp(1.0, 100.0).toDouble();

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = y * width + x;
        final z = depth[pixel];
        if (!z.isFinite) continue;
        final cocRadius = DepthOfFieldModel.circleOfConfusionRadiusPixels(
          objectDistance: z,
          focusDistance: focus,
          focalLength: focal,
          fNumber: fNumber,
          pixelsPerMillimetre: pixelsPerMillimetre,
        );
        if (cocRadius < 0.015) continue;
        final sampleRadius = math.max(1.0, cocRadius);
        final radius = sampleRadius.ceil().clamp(1, maxRadius).toInt();
        var red = 0.0;
        var green = 0.0;
        var blue = 0.0;
        var alpha = 0.0;
        var totalWeight = 0.0;
        final sigma = math.max(0.45, cocRadius * 0.58);
        final invTwoSigmaSquared = 1 / (2 * sigma * sigma);

        for (var dy = -radius; dy <= radius; dy++) {
          final sy = y + dy;
          if (sy < 0 || sy >= height) continue;
          for (var dx = -radius; dx <= radius; dx++) {
            final distanceSquared = dx * dx + dy * dy;
            if (distanceSquared > sampleRadius * sampleRadius + 0.25) continue;
            final sx = x + dx;
            if (sx < 0 || sx >= width) continue;

            final neighbour = sy * width + sx;
            final neighbourDepth = depth[neighbour];
            if (neighbourDepth.isFinite) {
              // Avoid pulling a substantially farther layer into a nearer
              // focused surface. Background pixels remain available at edges.
              final depthDelta = neighbourDepth - z;
              final depthTolerance = math.max(2.0, z * 0.002);
              if (depthDelta > depthTolerance &&
                  neighbourDepth > focus) {
                continue;
              }
            }
            final weight = math.exp(
              -distanceSquared * invTwoSigmaSquared,
            );
            final offset = neighbour * 4;
            final a = source[offset + 3] / 255;
            red += source[offset] * a * weight;
            green += source[offset + 1] * a * weight;
            blue += source[offset + 2] * a * weight;
            alpha += a * weight;
            totalWeight += weight;
          }
        }

        if (totalWeight <= 1e-8) continue;
        final outputOffset = pixel * 4;
        final coverage = (alpha / totalWeight).clamp(0.0, 1.0);
        if (alpha > 1e-8) {
          rgba[outputOffset] = (red / alpha).round().clamp(0, 255).toInt();
          rgba[outputOffset + 1] =
              (green / alpha).round().clamp(0, 255).toInt();
          rgba[outputOffset + 2] =
              (blue / alpha).round().clamp(0, 255).toInt();
        }
        rgba[outputOffset + 3] =
            (coverage * 255).round().clamp(0, 255).toInt();
      }
    }
  }

  double _edge(Offset a, Offset b, Offset p) =>
      (p.dx - a.dx) * (b.dy - a.dy) -
      (p.dy - a.dy) * (b.dx - a.dx);
}

class _SceneVertex {
  const _SceneVertex(
    this.world,
    this.camera,
    this.distance, [
    this.uv = Offset.zero,
  ]);

  final Vector3 world;
  final Vector3 camera;
  final double distance;
  final Offset uv;
}

class _ProjectedVertex {
  const _ProjectedVertex({
    required this.point,
    required this.distance,
    required this.visible,
    this.uv = Offset.zero,
  });

  final Offset point;
  final double distance;
  final bool visible;
  final Offset uv;
}
