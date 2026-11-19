import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../domain/composition_models.dart';

class ObjMaterial {
  const ObjMaterial({
    this.red = 0.72,
    this.green = 0.78,
    this.blue = 0.88,
    this.alpha = 1,
    this.metallicFactor = 0,
    this.roughnessFactor = 1,
    this.baseColorTextureBytes,
    this.alphaMode = 'OPAQUE',
    this.doubleSided = false,
    this.emissiveRed = 0,
    this.emissiveGreen = 0,
    this.emissiveBlue = 0,
  });

  final double red;
  final double green;
  final double blue;
  final double alpha;
  final double metallicFactor;
  final double roughnessFactor;
  final Uint8List? baseColorTextureBytes;
  final String alphaMode;
  final bool doubleSided;
  final double emissiveRed;
  final double emissiveGreen;
  final double emissiveBlue;
}

class ObjTriangle {
  const ObjTriangle(this.a, this.b, this.c, {this.material});

  final int a;
  final int b;
  final int c;
  final String? material;
}

class ObjMesh {
  const ObjMesh({
    required this.vertices,
    required this.triangles,
    required this.materials,
    required this.boundsMin,
    required this.boundsMax,
    this.textureCoordinates = const [],
    this.vertexNormals = const [],
    this.sceneNodes = const [],
    this.animations = const [],
    this.vertexNodeIndices = const [],
  });

  final List<Vector3> vertices;
  final List<ObjTriangle> triangles;
  final Map<String, ObjMaterial> materials;
  final Vector3 boundsMin;
  final Vector3 boundsMax;
  final List<Offset> textureCoordinates;
  final List<Vector3> vertexNormals;
  final List<GltfMeshNodeMetadata> sceneNodes;
  final List<GltfMeshAnimationMetadata> animations;
  final List<int> vertexNodeIndices;

  Vector3 get center => Vector3(
        (boundsMin.x + boundsMax.x) / 2,
        (boundsMin.y + boundsMax.y) / 2,
        (boundsMin.z + boundsMax.z) / 2,
      );

  double get maxDimension => math.max(
        boundsMax.x - boundsMin.x,
        math.max(
          boundsMax.y - boundsMin.y,
          boundsMax.z - boundsMin.z,
        ),
      ).toDouble();

  ObjMaterial materialFor(ObjTriangle triangle) =>
      materials[triangle.material] ?? const ObjMaterial();
}

/// Reads Wavefront OBJ geometry and its basic MTL diffuse colours.
/// Texture maps and unsupported OBJ extensions are intentionally ignored.
class ObjMeshLoader {
  const ObjMeshLoader();

  Future<ObjMesh> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('OBJ model file does not exist', path);
    }
    final source = await file.readAsString();
    final materialSources = <String>[];
    for (final line in source.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('mtllib ')) continue;
      final libraryPath = trimmed.substring(7).trim();
      if (libraryPath.isEmpty) continue;
      final resolved = File(Uri.file(file.path).resolve(libraryPath).toFilePath());
      if (await resolved.exists()) {
        materialSources.add(await resolved.readAsString());
      }
    }
    return parse(
      source,
      materials: parseMaterialLibraries(materialSources),
    );
  }

  ObjMesh parse(
    String source, {
    Map<String, ObjMaterial> materials = const {},
  }) {
    final vertices = <Vector3>[];
    final triangles = <ObjTriangle>[];
    String? activeMaterial;

    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      switch (parts.first) {
        case 'v':
          if (parts.length < 4) continue;
          final x = double.tryParse(parts[1]);
          final y = double.tryParse(parts[2]);
          final z = double.tryParse(parts[3]);
          if (x == null || y == null || z == null) continue;
          vertices.add(Vector3(x, y, z));
          break;
        case 'usemtl':
          activeMaterial = parts.length > 1 ? parts.sublist(1).join(' ') : null;
          break;
        case 'f':
          if (parts.length < 4) continue;
          final indices = <int>[];
          var valid = true;
          for (final token in parts.skip(1)) {
            final vertexToken = token.split('/').first;
            final parsed = int.tryParse(vertexToken);
            if (parsed == null || parsed == 0) {
              valid = false;
              break;
            }
            final index = parsed > 0 ? parsed - 1 : vertices.length + parsed;
            if (index < 0 || index >= vertices.length) {
              valid = false;
              break;
            }
            indices.add(index);
          }
          if (!valid || indices.length < 3) continue;
          for (var index = 1; index < indices.length - 1; index++) {
            triangles.add(ObjTriangle(
              indices[0],
              indices[index],
              indices[index + 1],
              material: activeMaterial,
            ));
          }
          break;
      }
    }

    if (vertices.isEmpty || triangles.isEmpty) {
      throw const FormatException(
        'OBJ must contain at least three vertices and one valid face.',
      );
    }

    final minX = vertices.map((v) => v.x).reduce((a, b) => a < b ? a : b);
    final minY = vertices.map((v) => v.y).reduce((a, b) => a < b ? a : b);
    final minZ = vertices.map((v) => v.z).reduce((a, b) => a < b ? a : b);
    final maxX = vertices.map((v) => v.x).reduce((a, b) => a > b ? a : b);
    final maxY = vertices.map((v) => v.y).reduce((a, b) => a > b ? a : b);
    final maxZ = vertices.map((v) => v.z).reduce((a, b) => a > b ? a : b);

    return ObjMesh(
      vertices: List.unmodifiable(vertices),
      triangles: List.unmodifiable(triangles),
      materials: Map.unmodifiable(materials),
      boundsMin: Vector3(minX, minY, minZ),
      boundsMax: Vector3(maxX, maxY, maxZ),
    );
  }

  Map<String, ObjMaterial> parseMaterialLibraries(Iterable<String> sources) {
    final result = <String, ObjMaterial>{};
    for (final source in sources) {
      String? name;
      var red = 0.72;
      var green = 0.78;
      var blue = 0.88;
      var alpha = 1.0;

      void save() {
        final materialName = name;
        if (materialName == null) return;
        result[materialName] = ObjMaterial(
          red: red.clamp(0.0, 1.0).toDouble(),
          green: green.clamp(0.0, 1.0).toDouble(),
          blue: blue.clamp(0.0, 1.0).toDouble(),
          alpha: alpha.clamp(0.0, 1.0).toDouble(),
        );
      }

      for (final rawLine in source.split(RegExp(r'\r?\n'))) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final parts = line.split(RegExp(r'\s+'));
        switch (parts.first) {
          case 'newmtl':
            save();
            name = parts.length > 1 ? parts.sublist(1).join(' ') : null;
            red = 0.72;
            green = 0.78;
            blue = 0.88;
            alpha = 1;
            break;
          case 'Kd':
            if (parts.length >= 4) {
              red = double.tryParse(parts[1]) ?? red;
              green = double.tryParse(parts[2]) ?? green;
              blue = double.tryParse(parts[3]) ?? blue;
            }
            break;
          case 'd':
            if (parts.length >= 2) alpha = double.tryParse(parts[1]) ?? alpha;
            break;
          case 'Tr':
            if (parts.length >= 2) {
              alpha = 1 - (double.tryParse(parts[1]) ?? (1 - alpha));
            }
            break;
        }
      }
      save();
    }
    return Map.unmodifiable(result);
  }
}


/// A glTF node retained with its parent link and column-major local transform.
class GltfMeshNodeMetadata {
  const GltfMeshNodeMetadata({
    required this.index,
    required this.parentIndex,
    required this.localMatrix,
    required this.name,
    this.meshIndex,
    this.isMatrixTransform = false,
    this.translation = const Vector3(0, 0, 0),
    this.rotation = const [0, 0, 0, 1],
    this.scale = const Vector3(1, 1, 1),
  });

  final int index;
  final int? parentIndex;
  final List<double> localMatrix;
  final String? name;
  final int? meshIndex;
  final bool isMatrixTransform;
  final Vector3 translation;
  final List<double> rotation;
  final Vector3 scale;
}

/// Animation channel decoded from glTF accessors.
class GltfMeshAnimationChannel {
  const GltfMeshAnimationChannel({
    required this.nodeIndex,
    required this.path,
    required this.interpolation,
    required this.times,
    required this.values,
    required this.componentCount,
  });

  final int nodeIndex;
  final String path;
  final String interpolation;
  final List<double> times;
  final List<double> values;
  final int componentCount;
}

/// Imported glTF animation clip metadata, including decoded keyframe values.
class GltfMeshAnimationMetadata {
  const GltfMeshAnimationMetadata({
    required this.name,
    required this.durationSeconds,
    required this.channels,
  });

  final String name;
  final double durationSeconds;
  final List<GltfMeshAnimationChannel> channels;
}
