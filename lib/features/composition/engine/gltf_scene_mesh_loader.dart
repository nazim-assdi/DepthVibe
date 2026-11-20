import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:gltfx/gltfx.dart' as gltf;
import 'package:image/image.dart' as img;

import '../domain/composition_models.dart';
import 'obj_mesh_loader.dart';

/// Full glTF 2.0 scene decoder used by the DepthVibe mesh pipeline.
///
/// This imports the active scene, applies hierarchical node transforms,
/// retains UV0 and vertex normals, resolves material base-colour images and
/// stores animation channels for timeline evaluation. Unsupported skinning
/// and morph targets remain in the source document but are not deformed here.
class GltfSceneMeshLoader {
  const GltfSceneMeshLoader();

  Future<ObjMesh> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('glTF model file does not exist', path);
    }
    final extension = path.toLowerCase().split('.').last;
    final gltf.GltfDocument document;
    if (extension == 'glb') {
      document = gltf.Glb.parse(await file.readAsBytes());
    } else if (extension == 'gltf') {
      document = await gltf.Gltf.parse(
        await file.readAsString(),
        loader: (uri) async {
          final resolved = File(Uri.file(file.path).resolve(uri).toFilePath());
          if (!await resolved.exists()) {
            throw FileSystemException('glTF resource was not found', resolved.path);
          }
          return resolved.readAsBytes();
        },
      );
    } else {
      throw FormatException('Expected a .gltf or .glb file: $path');
    }
    return decodeDocument(document);
  }

  ObjTextureMap? _loadTextureMap(
    gltf.GltfDocument document, {
    required int? textureIndex,
    required int texCoord,
    required gltf.GltfExtensions? extensions,
  }) {
    if (textureIndex == null ||
        textureIndex < 0 ||
        textureIndex >= document.textures.length) {
      return null;
    }
    final source = document.textures[gltf.TextureIdx(textureIndex)].source;
    if (source == null ||
        source.value < 0 ||
        source.value >= document.imageData.length) {
      return null;
    }

    final encoded = document.imageData[gltf.ImageIdx(source.value)];
    if (encoded == null || encoded.isEmpty) return null;
    final decoded = img.decodeImage(encoded);
    final transform = extensions?.get(gltf.khrTextureTransform);
    return ObjTextureMap(
      sourceBytes: encoded,
      pixelsRgba: decoded == null
          ? null
          : Uint8List.fromList(
              decoded.getBytes(order: img.ChannelOrder.rgba),
            ),
      width: decoded?.width ?? 0,
      height: decoded?.height ?? 0,
      texCoord: transform?.texCoord ?? texCoord,
      offset: Offset(
        transform?.offsetU ?? 0,
        transform?.offsetV ?? 0,
      ),
      scale: Offset(
        transform?.scaleU ?? 1,
        transform?.scaleV ?? 1,
      ),
      rotationRadians: transform?.rotation ?? 0,
    );
  }

  ObjMesh decodeDocument(gltf.GltfDocument document) {
    if (document.asset.version.split('.').first != '2') {
      throw FormatException(
        'Only glTF 2.x documents are supported; got \${document.asset.version}.',
      );
    }

    final materials = <String, ObjMaterial>{};
    for (final entry in document.materials.indexed) {
      final index = entry.$1;
      final material = entry.$2;
      final pbr = material.pbrMetallicRoughness;
      final factor = pbr?.baseColorFactor;
      final baseColorInfo = pbr?.baseColorTexture;
      final metallicRoughnessInfo = pbr?.metallicRoughnessTexture;
      final normalInfo = material.normalTexture;
      final occlusionInfo = material.occlusionTexture;
      final emissiveInfo = material.emissiveTexture;
      final baseColorMap = _loadTextureMap(
        document,
        textureIndex: baseColorInfo?.index.value,
        texCoord: baseColorInfo?.texCoord ?? 0,
        extensions: baseColorInfo?.extensions,
      );
      final metallicRoughnessMap = _loadTextureMap(
        document,
        textureIndex: metallicRoughnessInfo?.index.value,
        texCoord: metallicRoughnessInfo?.texCoord ?? 0,
        extensions: metallicRoughnessInfo?.extensions,
      );
      final normalMap = _loadTextureMap(
        document,
        textureIndex: normalInfo?.index.value,
        texCoord: normalInfo?.texCoord ?? 0,
        extensions: normalInfo?.extensions,
      );
      final occlusionMap = _loadTextureMap(
        document,
        textureIndex: occlusionInfo?.index.value,
        texCoord: occlusionInfo?.texCoord ?? 0,
        extensions: occlusionInfo?.extensions,
      );
      final emissiveMap = _loadTextureMap(
        document,
        textureIndex: emissiveInfo?.index.value,
        texCoord: emissiveInfo?.texCoord ?? 0,
        extensions: emissiveInfo?.extensions,
      );
      double component(int componentIndex, double fallback) =>
          factor != null && componentIndex < factor.length
              ? factor[componentIndex].toDouble()
              : fallback;
      final emissive = material.emissiveFactor;
      materials['gltf_material_$index'] = ObjMaterial(
        red: component(0, 1).clamp(0.0, 1.0).toDouble(),
        green: component(1, 1).clamp(0.0, 1.0).toDouble(),
        blue: component(2, 1).clamp(0.0, 1.0).toDouble(),
        alpha: component(3, 1).clamp(0.0, 1.0).toDouble(),
        metallicFactor: pbr?.metallicFactor ?? 1,
        roughnessFactor: pbr?.roughnessFactor ?? 1,
        baseColorTextureBytes: baseColorMap?.sourceBytes,
        baseColorTextureRgba: baseColorMap?.pixelsRgba,
        baseColorTextureWidth: baseColorMap?.width ?? 0,
        baseColorTextureHeight: baseColorMap?.height ?? 0,
        alphaCutoff: material.alphaCutoff,
        alphaMode: material.alphaMode.name,
        doubleSided: material.doubleSided,
        emissiveRed: emissive != null && emissive.isNotEmpty ? emissive[0] : 0,
        emissiveGreen: emissive != null && emissive.length > 1 ? emissive[1] : 0,
        emissiveBlue: emissive != null && emissive.length > 2 ? emissive[2] : 0,
        baseColorTextureMap: baseColorMap,
        metallicRoughnessTextureMap: metallicRoughnessMap,
        normalTextureMap: normalMap,
        occlusionTextureMap: occlusionMap,
        emissiveTextureMap: emissiveMap,
        normalScale: normalInfo?.scale ?? 1,
        occlusionStrength: occlusionInfo?.strength ?? 1,
      );
    }

    final nodes = <GltfMeshNodeMetadata>[];
    final parentIndices = List<int?>.filled(document.nodes.length, null);
    for (final entry in document.nodes.indexed) {
      for (final child in entry.$2.children) {
        if (child.value >= 0 && child.value < parentIndices.length) {
          parentIndices[child.value] = entry.$1;
        }
      }
      nodes.add(GltfMeshNodeMetadata(
        index: entry.$1,
        parentIndex: null,
        localMatrix: List.unmodifiable(_localMatrix(entry.$2.transform)),
        name: entry.$2.name,
        meshIndex: entry.$2.mesh?.value,
        isMatrixTransform: entry.$2.transform is gltf.MatrixTransform,
        translation: _nodeTranslation(entry.$2.transform),
        rotation: _nodeRotation(entry.$2.transform),
        scale: _nodeScale(entry.$2.transform),
      ));
    }
    for (var i = 0; i < nodes.length; i++) {
      final item = nodes[i];
      nodes[i] = GltfMeshNodeMetadata(
        index: item.index,
        parentIndex: parentIndices[i],
        localMatrix: item.localMatrix,
        name: item.name,
        meshIndex: item.meshIndex,
        isMatrixTransform: item.isMatrixTransform,
        translation: item.translation,
        rotation: item.rotation,
        scale: item.scale,
      );
    }

    final vertices = <Vector3>[];
    final vertexNormals = <Vector3>[];
    final textureCoordinates = <Offset>[];
    final vertexNodeIndices = <int>[];
    final triangles = <ObjTriangle>[];
    final restBounds = <Vector3>[];
    var hasTextureCoordinates = false;
    final visitedPath = <int>{};

    void visitNode(int nodeIndex, Float64List parentMatrix) {
      if (nodeIndex < 0 || nodeIndex >= document.nodes.length) {
        throw FormatException('glTF scene references invalid node $nodeIndex.');
      }
      if (!visitedPath.add(nodeIndex)) {
        throw FormatException('glTF node hierarchy contains a cycle at node $nodeIndex.');
      }
      final node = document.nodes[gltf.NodeIdx(nodeIndex)];
      final worldMatrix = _multiply(
        parentMatrix,
        _localMatrix(node.transform),
      );

      final meshIndex = node.mesh?.value;
      if (meshIndex != null) {
        if (meshIndex < 0 || meshIndex >= document.meshes.length) {
          throw FormatException('glTF node $nodeIndex references invalid mesh $meshIndex.');
        }
        final mesh = document.meshes[gltf.MeshIdx(meshIndex)];
        for (final primitive in mesh.primitives) {
          if (primitive.mode.value != 4 &&
              primitive.mode.value != 5 &&
              primitive.mode.value != 6) {
            continue;
          }
          final rawPositions = primitive.getPositions(document);
          if (rawPositions == null || rawPositions.length < 9) continue;
          final vertexCount = rawPositions.length ~/ 3;
          final rawNormals = primitive.getNormals(document);
          final rawUvs = primitive.getTexCoord0(document);
          final baseVertex = vertices.length;

          for (var index = 0; index < vertexCount; index++) {
            final local = Vector3(
              rawPositions[index * 3],
              rawPositions[index * 3 + 1],
              rawPositions[index * 3 + 2],
            );
            final world = _transformPoint(worldMatrix, local);
            vertices.add(local);
            restBounds.add(world);
            vertexNodeIndices.add(nodeIndex);

            if (rawNormals != null && rawNormals.length >= (index + 1) * 3) {
              vertexNormals.add(_normalize(Vector3(
                rawNormals[index * 3],
                rawNormals[index * 3 + 1],
                rawNormals[index * 3 + 2],
              )));
            } else {
              vertexNormals.add(const Vector3(0, 0, 0));
            }

            if (rawUvs != null && rawUvs.length >= (index + 1) * 2) {
              textureCoordinates.add(Offset(
                rawUvs[index * 2],
                rawUvs[index * 2 + 1],
              ));
              hasTextureCoordinates = true;
            } else {
              // A sentinel keeps UV-less primitives independent of textured
              // sibling primitives in the same active glTF scene.
              textureCoordinates.add(const Offset(double.nan, double.nan));
            }
          }

          final indices = _readIndices(document, primitive, vertexCount);
          final materialIndex = primitive.material?.value;
          final materialName = materialIndex == null
              ? null
              : 'gltf_material_$materialIndex';
          void addTriangle(int a, int b, int c) {
            if (a < 0 || b < 0 || c < 0 ||
                a >= vertexCount || b >= vertexCount || c >= vertexCount) {
              throw FormatException(
                'glTF primitive on node $nodeIndex has an out-of-range index.',
              );
            }
            triangles.add(ObjTriangle(
              baseVertex + a,
              baseVertex + b,
              baseVertex + c,
              material: materialName,
            ));
          }

          switch (primitive.mode.value) {
            case 4: // TRIANGLES
              for (var i = 0; i + 2 < indices.length; i += 3) {
                addTriangle(indices[i], indices[i + 1], indices[i + 2]);
              }
              break;
            case 5: // TRIANGLE_STRIP
              for (var i = 0; i + 2 < indices.length; i++) {
                if (i.isEven) {
                  addTriangle(indices[i], indices[i + 1], indices[i + 2]);
                } else {
                  addTriangle(indices[i + 1], indices[i], indices[i + 2]);
                }
              }
              break;
            case 6: // TRIANGLE_FAN
              for (var i = 1; i + 1 < indices.length; i++) {
                addTriangle(indices[0], indices[i], indices[i + 1]);
              }
              break;
          }
        }
      }

      for (final child in node.children) {
        visitNode(child.value, worldMatrix);
      }
      visitedPath.remove(nodeIndex);
    }

    final roots = document.defaultScene?.nodes.map((node) => node.value).toList() ??
        List<int>.generate(document.nodes.length, (index) => index)
            .where((index) => parentIndices[index] == null)
            .toList();
    final identity = _identity();
    for (final root in roots) {
      visitNode(root, identity);
    }

    if (vertices.isEmpty || triangles.isEmpty) {
      throw const FormatException(
        'glTF contains no supported triangle mesh in the active scene.',
      );
    }

    final minX = restBounds.map((v) => v.x).reduce((a, b) => a < b ? a : b);
    final minY = restBounds.map((v) => v.y).reduce((a, b) => a < b ? a : b);
    final minZ = restBounds.map((v) => v.z).reduce((a, b) => a < b ? a : b);
    final maxX = restBounds.map((v) => v.x).reduce((a, b) => a > b ? a : b);
    final maxY = restBounds.map((v) => v.y).reduce((a, b) => a > b ? a : b);
    final maxZ = restBounds.map((v) => v.z).reduce((a, b) => a > b ? a : b);

    final animations = <GltfMeshAnimationMetadata>[];
    for (final entry in document.animations.indexed) {
      final animation = entry.$2;
      final channels = <GltfMeshAnimationChannel>[];
      for (final channel in animation.channels) {
        final nodeIndex = channel.target.node?.value ?? -1;
        if (nodeIndex < 0 || nodeIndex >= document.nodes.length) continue;
        if (channel.samplerIndex < 0 ||
            channel.samplerIndex >= animation.samplers.length) {
          continue;
        }
        final sampler = animation.samplers[channel.samplerIndex];
        final times = sampler.getTimes(document);
        final values = sampler.getValues(document);
        final path = channel.target.path.name;
        final components = switch (path) {
          'translation' || 'scale' => 3,
          'rotation' => 4,
          _ => 0,
        };
        channels.add(GltfMeshAnimationChannel(
          nodeIndex: nodeIndex,
          path: path,
          interpolation: sampler.interpolation.name,
          times: List.unmodifiable(times.map((value) => value.toDouble())),
          values: List.unmodifiable(values.map((value) => value.toDouble())),
          componentCount: components,
        ));
      }
      animations.add(GltfMeshAnimationMetadata(
        name: animation.name ?? 'Animation ' + (entry.$1 + 1).toString(),
        durationSeconds: animation.getDuration(document),
        channels: List.unmodifiable(channels),
      ));
    }

    return ObjMesh(
      vertices: List.unmodifiable(vertices),
      triangles: List.unmodifiable(triangles),
      materials: Map.unmodifiable(materials),
      boundsMin: Vector3(minX, minY, minZ),
      boundsMax: Vector3(maxX, maxY, maxZ),
      textureCoordinates: List.unmodifiable(textureCoordinates),
      hasTextureCoordinates: hasTextureCoordinates &&
          textureCoordinates.length == vertices.length,
      vertexNormals: List.unmodifiable(vertexNormals),
      sceneNodes: List.unmodifiable(nodes),
      animations: List.unmodifiable(animations),
      vertexNodeIndices: List.unmodifiable(vertexNodeIndices),
    );
  }

  List<int> _readIndices(
    gltf.GltfDocument document,
    gltf.GltfPrimitive primitive,
    int vertexCount,
  ) {
    final accessorIndex = primitive.indices;
    if (accessorIndex == null) {
      return List<int>.generate(vertexCount, (index) => index);
    }
    final decoded = gltf.AccessorDecoder.decode(document, accessorIndex);
    return switch (decoded) {
      Uint8List values => values.toList(growable: false),
      Uint16List values => values.toList(growable: false),
      Uint32List values => values.toList(growable: false),
      _ => throw const FormatException(
          'glTF index accessors must use unsigned 8, 16 or 32-bit integers.',
        ),
    };
  }

  Vector3 _nodeTranslation(gltf.Transform transform) {
    if (transform is gltf.TrsTransform && transform.translation != null) {
      return Vector3(
        transform.translation![0],
        transform.translation![1],
        transform.translation![2],
      );
    }
    if (transform is gltf.MatrixTransform) {
      final m = transform.matrix;
      return Vector3(m[12], m[13], m[14]);
    }
    return const Vector3(0, 0, 0);
  }

  List<double> _nodeRotation(gltf.Transform transform) {
    if (transform is gltf.TrsTransform && transform.rotation != null) {
      return List.unmodifiable(transform.rotation!.map((v) => v.toDouble()));
    }
    return const [0.0, 0.0, 0.0, 1.0];
  }

  Vector3 _nodeScale(gltf.Transform transform) {
    if (transform is gltf.TrsTransform && transform.scale != null) {
      return Vector3(
        transform.scale![0],
        transform.scale![1],
        transform.scale![2],
      );
    }
    return const Vector3(1, 1, 1);
  }

  Float64List _identity() => Float64List.fromList([
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]);

  Float64List _localMatrix(gltf.Transform transform) {
    if (transform case gltf.MatrixTransform(matrix: final matrix)) {
      return Float64List.fromList(matrix);
    }
    final trs = transform as gltf.TrsTransform;
    final translation = trs.translation ?? Float32List.fromList([0, 0, 0]);
    final rotation = trs.rotation ?? Float32List.fromList([0, 0, 0, 1]);
    final scale = trs.scale ?? Float32List.fromList([1, 1, 1]);

    final x = rotation[0], y = rotation[1], z = rotation[2], w = rotation[3];
    final xx = x * x, yy = y * y, zz = z * z;
    final xy = x * y, xz = x * z, yz = y * z;
    final wx = w * x, wy = w * y, wz = w * z;
    final sx = scale[0], sy = scale[1], sz = scale[2];

    return Float64List.fromList([
      (1 - 2 * (yy + zz)) * sx,
      (2 * (xy + wz)) * sx,
      (2 * (xz - wy)) * sx,
      0,
      (2 * (xy - wz)) * sy,
      (1 - 2 * (xx + zz)) * sy,
      (2 * (yz + wx)) * sy,
      0,
      (2 * (xz + wy)) * sz,
      (2 * (yz - wx)) * sz,
      (1 - 2 * (xx + yy)) * sz,
      0,
      translation[0],
      translation[1],
      translation[2],
      1,
    ]);
  }

  Float64List _multiply(Float64List a, Float64List b) {
    final result = Float64List(16);
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        var value = 0.0;
        for (var k = 0; k < 4; k++) {
          value += a[k * 4 + row] * b[column * 4 + k];
        }
        result[column * 4 + row] = value;
      }
    }
    return result;
  }

  Vector3 _transformPoint(Float64List m, Vector3 p) {
    final x = m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12];
    final y = m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13];
    final z = m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14];
    final w = m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15];
    if (w.abs() < 1e-9 || (w - 1).abs() < 1e-9) {
      return Vector3(x, y, z);
    }
    return Vector3(x / w, y / w, z / w);
  }


  Vector3 _normalize(Vector3 value) {
    final length = math.sqrt(
      value.x * value.x + value.y * value.y + value.z * value.z,
    );
    if (length < 1e-9) return const Vector3(0, 0, 0);
    return Vector3(value.x / length, value.y / length, value.z / length);
  }
}
