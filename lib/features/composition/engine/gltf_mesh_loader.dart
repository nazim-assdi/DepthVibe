import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/composition_models.dart';
import 'obj_mesh_loader.dart';

/// Reads glTF 2.0 JSON (.gltf) and binary GLB (.glb) mesh primitives.
///
/// Supported attributes are POSITION and optional uint8/uint16/uint32 indices.
/// PBR baseColorFactor is mapped to the software renderer's flat material.
/// Node hierarchy, animations, skinning, normals and texture images are not
/// interpreted by this lightweight geometry importer.
class GltfMeshLoader {
  const GltfMeshLoader();

  Future<ObjMesh> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('glTF model file does not exist', path);
    }
    final extension = path.toLowerCase().split('.').last;
    Map<String, Object?> document;
    Uint8List? binaryChunk;
    if (extension == 'glb') {
      final parsed = parseGlb(await file.readAsBytes());
      document = parsed.document;
      binaryChunk = parsed.binaryChunk;
    } else if (extension == 'gltf') {
      document = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } else {
      throw FormatException('Expected a .gltf or .glb file: $path');
    }

    final buffers = <Uint8List>[];
    final definitions = (document['buffers'] as List<Object?>? ?? const []);
    for (var index = 0; index < definitions.length; index++) {
      final definition = definitions[index] as Map<String, Object?>;
      final uri = definition['uri'] as String?;
      late Uint8List bytes;
      if (uri == null) {
        if (index != 0 || binaryChunk == null) {
          throw const FormatException('glTF buffer has no URI or GLB BIN chunk.');
        }
        bytes = binaryChunk;
      } else if (uri.startsWith('data:')) {
        final comma = uri.indexOf(',');
        if (comma < 0 || !uri.substring(0, comma).contains(';base64')) {
          throw const FormatException('Only base64 data URIs are supported in glTF buffers.');
        }
        bytes = base64Decode(uri.substring(comma + 1));
      } else {
        final bufferFile = File(Uri.file(file.path).resolve(uri).toFilePath());
        if (!await bufferFile.exists()) {
          throw FileSystemException('glTF buffer file was not found', bufferFile.path);
        }
        bytes = await bufferFile.readAsBytes();
      }
      final expected = (definition['byteLength'] as num?)?.toInt() ?? bytes.length;
      if (bytes.length < expected) {
        throw FormatException('glTF buffer $index is shorter than byteLength.');
      }
      buffers.add(bytes);
    }
    return parseDocument(document, buffers);
  }

  _ParsedGlb parseGlb(Uint8List bytes) {
    if (bytes.length < 20) throw const FormatException('GLB header is incomplete.');
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != 0x46546C67) {
      throw const FormatException('Invalid GLB magic header.');
    }
    if (data.getUint32(4, Endian.little) != 2) {
      throw const FormatException('Only GLB version 2 is supported.');
    }
    final declaredLength = data.getUint32(8, Endian.little);
    if (declaredLength > bytes.length || declaredLength < 20) {
      throw const FormatException('Invalid GLB declared length.');
    }

    Uint8List? jsonBytes;
    Uint8List? binaryChunk;
    var offset = 12;
    while (offset + 8 <= declaredLength) {
      final chunkLength = data.getUint32(offset, Endian.little);
      final chunkType = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final chunkEnd = chunkStart + chunkLength;
      if (chunkEnd > declaredLength) {
        throw const FormatException('GLB chunk exceeds the file length.');
      }
      final chunk = Uint8List.sublistView(bytes, chunkStart, chunkEnd);
      if (chunkType == 0x4E4F534A && jsonBytes == null) {
        jsonBytes = chunk;
      } else if (chunkType == 0x004E4942 && binaryChunk == null) {
        binaryChunk = chunk;
      }
      offset = chunkEnd;
    }

    if (jsonBytes == null) throw const FormatException('GLB JSON chunk is missing.');
    final jsonText = utf8.decode(jsonBytes).replaceAll('\u0000', '').trim();
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('GLB JSON root must be an object.');
    }
    return _ParsedGlb(decoded, binaryChunk);
  }

  ObjMesh parseDocument(
    Map<String, Object?> document,
    List<Uint8List> buffers,
  ) {
    final bufferViews = document['bufferViews'] as List<Object?>? ?? const [];
    final accessors = document['accessors'] as List<Object?>? ?? const [];
    final meshDefinitions = document['meshes'] as List<Object?>? ?? const [];
    final materialDefinitions = document['materials'] as List<Object?>? ?? const [];
    final vertices = <Vector3>[];
    final triangles = <ObjTriangle>[];
    final materialMap = <String, ObjMaterial>{};

    for (var index = 0; index < materialDefinitions.length; index++) {
      final material = materialDefinitions[index] as Map<String, Object?>;
      final pbr = material['pbrMetallicRoughness'] as Map<String, Object?>? ?? const {};
      final factor = pbr['baseColorFactor'] as List<Object?>? ?? const [0.72, 0.78, 0.88, 1.0];
      double component(int i, double fallback) =>
          i < factor.length ? (factor[i] as num?)?.toDouble() ?? fallback : fallback;
      materialMap['gltf_material_$index'] = ObjMaterial(
        red: component(0, 0.72).clamp(0.0, 1.0).toDouble(),
        green: component(1, 0.78).clamp(0.0, 1.0).toDouble(),
        blue: component(2, 0.88).clamp(0.0, 1.0).toDouble(),
        alpha: component(3, 1).clamp(0.0, 1.0).toDouble(),
      );
    }

    Uint8List bufferForView(int viewIndex) {
      if (viewIndex < 0 || viewIndex >= bufferViews.length) {
        throw const FormatException('glTF references an invalid bufferView.');
      }
      final view = bufferViews[viewIndex] as Map<String, Object?>;
      final bufferIndex = (view['buffer'] as num?)?.toInt() ?? 0;
      if (bufferIndex < 0 || bufferIndex >= buffers.length) {
        throw const FormatException('glTF bufferView references an invalid buffer.');
      }
      return buffers[bufferIndex];
    }

    Map<String, Object?> accessorAt(int accessorIndex) {
      if (accessorIndex < 0 || accessorIndex >= accessors.length) {
        throw const FormatException('glTF references an invalid accessor.');
      }
      return accessors[accessorIndex] as Map<String, Object?>;
    }

    List<Vector3> readPositions(int accessorIndex) {
      final accessor = accessorAt(accessorIndex);
      if (accessor['type'] != 'VEC3' || accessor['componentType'] != 5126) {
        throw const FormatException('glTF POSITION must use FLOAT VEC3 data.');
      }
      final viewIndex = (accessor['bufferView'] as num?)?.toInt();
      if (viewIndex == null) {
        throw const FormatException('Sparse or bufferless POSITION accessors are not supported.');
      }
      final view = bufferViews[viewIndex] as Map<String, Object?>;
      final buffer = bufferForView(viewIndex);
      final viewOffset = (view['byteOffset'] as num?)?.toInt() ?? 0;
      final accessorOffset = (accessor['byteOffset'] as num?)?.toInt() ?? 0;
      final stride = (view['byteStride'] as num?)?.toInt() ?? 12;
      final count = (accessor['count'] as num?)?.toInt() ?? 0;
      if (stride < 12 || count <= 0) {
        throw const FormatException('glTF POSITION accessor has an invalid stride or count.');
      }
      final values = <Vector3>[];
      final byteData = ByteData.sublistView(buffer);
      for (var index = 0; index < count; index++) {
        final offset = viewOffset + accessorOffset + index * stride;
        if (offset < 0 || offset + 12 > buffer.length) {
          throw const FormatException('glTF POSITION accessor exceeds its buffer.');
        }
        values.add(Vector3(
          byteData.getFloat32(offset, Endian.little),
          byteData.getFloat32(offset + 4, Endian.little),
          byteData.getFloat32(offset + 8, Endian.little),
        ));
      }
      return values;
    }

    List<int> readIndices(int accessorIndex) {
      final accessor = accessorAt(accessorIndex);
      if (accessor['type'] != 'SCALAR') {
        throw const FormatException('glTF index accessor must be SCALAR.');
      }
      final component = (accessor['componentType'] as num?)?.toInt();
      final elementSize = switch (component) {
        5121 => 1,
        5123 => 2,
        5125 => 4,
        _ => 0,
      };
      if (elementSize == 0) {
        throw const FormatException('glTF indices must be unsigned byte, short or int.');
      }
      final viewIndex = (accessor['bufferView'] as num?)?.toInt();
      if (viewIndex == null) throw const FormatException('Sparse index accessors are unsupported.');
      final view = bufferViews[viewIndex] as Map<String, Object?>;
      final buffer = bufferForView(viewIndex);
      final viewOffset = (view['byteOffset'] as num?)?.toInt() ?? 0;
      final accessorOffset = (accessor['byteOffset'] as num?)?.toInt() ?? 0;
      final stride = (view['byteStride'] as num?)?.toInt() ?? elementSize;
      if (stride < elementSize) throw const FormatException('Invalid glTF index stride.');
      final count = (accessor['count'] as num?)?.toInt() ?? 0;
      final values = <int>[];
      final byteData = ByteData.sublistView(buffer);
      for (var index = 0; index < count; index++) {
        final offset = viewOffset + accessorOffset + index * stride;
        if (offset < 0 || offset + elementSize > buffer.length) {
          throw const FormatException('glTF index accessor exceeds its buffer.');
        }
        values.add(switch (component) {
          5121 => byteData.getUint8(offset),
          5123 => byteData.getUint16(offset, Endian.little),
          _ => byteData.getUint32(offset, Endian.little),
        });
      }
      return values;
    }

    for (final rawMesh in meshDefinitions) {
      final mesh = rawMesh as Map<String, Object?>;
      final primitives = mesh['primitives'] as List<Object?>? ?? const [];
      for (final rawPrimitive in primitives) {
        final primitive = rawPrimitive as Map<String, Object?>;
        // TRIANGLES only; strips, fans, morph targets and skins are reported by omission.
        final mode = (primitive['mode'] as num?)?.toInt() ?? 4;
        if (mode != 4) continue;
        final attributes = primitive['attributes'] as Map<String, Object?>? ?? const {};
        final positionAccessor = (attributes['POSITION'] as num?)?.toInt();
        if (positionAccessor == null) continue;
        final primitiveVertices = readPositions(positionAccessor);
        final baseVertex = vertices.length;
        vertices.addAll(primitiveVertices);

        final indices = primitive['indices'] == null
            ? List<int>.generate(primitiveVertices.length, (index) => index)
            : readIndices((primitive['indices'] as num).toInt());
        final materialIndex = (primitive['material'] as num?)?.toInt();
        final materialName = materialIndex == null ? null : 'gltf_material_$materialIndex';
        for (var index = 0; index + 2 < indices.length; index += 3) {
          final a = indices[index];
          final b = indices[index + 1];
          final c = indices[index + 2];
          if (a < 0 || b < 0 || c < 0 ||
              a >= primitiveVertices.length ||
              b >= primitiveVertices.length ||
              c >= primitiveVertices.length) {
            throw const FormatException('glTF primitive index is outside POSITION bounds.');
          }
          triangles.add(ObjTriangle(
            baseVertex + a,
            baseVertex + b,
            baseVertex + c,
            material: materialName,
          ));
        }
      }
    }

    if (vertices.isEmpty || triangles.isEmpty) {
      throw const FormatException('glTF contains no supported triangle mesh primitives.');
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
      materials: Map.unmodifiable(materialMap),
      boundsMin: Vector3(minX, minY, minZ),
      boundsMax: Vector3(maxX, maxY, maxZ),
    );
  }
}

class _ParsedGlb {
  const _ParsedGlb(this.document, this.binaryChunk);

  final Map<String, Object?> document;
  final Uint8List? binaryChunk;
}
