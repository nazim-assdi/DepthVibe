import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/gltf_scene_evaluator.dart';
import 'package:depthvibe/features/composition/engine/gltf_scene_mesh_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gltfx/gltfx.dart' as gltf;

void main() {
  const loader = GltfSceneMeshLoader();

  Uint8List fixtureBuffer() {
    const byteLength = 136;
    final data = ByteData(byteLength);
    const positions = [
      0.0, 0.0, 0.0,
      1.0, 0.0, 0.0,
      0.0, 1.0, 0.0,
    ];
    const normals = [
      0.0, 0.0, 1.0,
      0.0, 0.0, 1.0,
      0.0, 0.0, 1.0,
    ];
    const uvs = [
      0.0, 0.0,
      1.0, 0.0,
      0.0, 1.0,
    ];
    const times = [0.0, 1.0];
    const translations = [
      3.0, 0.0, 0.0,
      5.0, 0.0, 0.0,
    ];
    for (var index = 0; index < positions.length; index++) {
      data.setFloat32(index * 4, positions[index], Endian.little);
    }
    for (var index = 0; index < normals.length; index++) {
      data.setFloat32(36 + index * 4, normals[index], Endian.little);
    }
    for (var index = 0; index < uvs.length; index++) {
      data.setFloat32(72 + index * 4, uvs[index], Endian.little);
    }
    data.setUint16(96, 0, Endian.little);
    data.setUint16(98, 1, Endian.little);
    data.setUint16(100, 2, Endian.little);
    for (var index = 0; index < times.length; index++) {
      data.setFloat32(104 + index * 4, times[index], Endian.little);
    }
    for (var index = 0; index < translations.length; index++) {
      data.setFloat32(112 + index * 4, translations[index], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  Map<String, Object?> fixtureJson(
    Uint8List buffer,
    String encodedBuffer,
  ) => {
        'asset': {'version': '2.0', 'generator': 'DepthVibe test'},
        'scene': 0,
        'scenes': [
          {'nodes': [0]}
        ],
        'nodes': [
          {'name': 'Root', 'translation': [2, 0, 0], 'children': [1]},
          {'name': 'AnimatedMesh', 'mesh': 0, 'translation': [3, 0, 0]}
        ],
        'meshes': [
          {
            'primitives': [
              {
                'attributes': {
                  'POSITION': 0,
                  'NORMAL': 1,
                  'TEXCOORD_0': 2
                },
                'indices': 3,
                'material': 0
              }
            ]
          }
        ],
        'materials': [
          {
            'pbrMetallicRoughness': {
              'baseColorFactor': [0.2, 0.4, 0.8, 1],
              'metallicFactor': 0.65,
              'roughnessFactor': 0.25,
              'baseColorTexture': {'index': 0}
            }
          }
        ],
        'textures': [
          {'source': 0}
        ],
        'images': [
          {'uri': 'data:image/png;base64,AA=='}
        ],
        'buffers': [
          {
            'byteLength': buffer.length,
            'uri': 'data:application/octet-stream;base64,' + encodedBuffer
          }
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
          {'buffer': 0, 'byteOffset': 36, 'byteLength': 36},
          {'buffer': 0, 'byteOffset': 72, 'byteLength': 24},
          {'buffer': 0, 'byteOffset': 96, 'byteLength': 6},
          {'buffer': 0, 'byteOffset': 104, 'byteLength': 8},
          {'buffer': 0, 'byteOffset': 112, 'byteLength': 24}
        ],
        'accessors': [
          {'bufferView': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
          {'bufferView': 1, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
          {'bufferView': 2, 'componentType': 5126, 'count': 3, 'type': 'VEC2'},
          {'bufferView': 3, 'componentType': 5123, 'count': 3, 'type': 'SCALAR'},
          {'bufferView': 4, 'componentType': 5126, 'count': 2, 'type': 'SCALAR'},
          {'bufferView': 5, 'componentType': 5126, 'count': 2, 'type': 'VEC3'}
        ],
        'animations': [
          {
            'name': 'Move node',
            'samplers': [
              {'input': 4, 'output': 5, 'interpolation': 'LINEAR'}
            ],
            'channels': [
              {
                'sampler': 0,
                'target': {'node': 1, 'path': 'translation'}
              }
            ]
          }
        ]
      };

  Future<gltf.GltfDocument> parseFixture() async {
    final buffer = fixtureBuffer();
    return gltf.Gltf.parse(
      jsonEncode(fixtureJson(buffer, base64Encode(buffer))),
      loader: (_) async => buffer,
    );
  }

  test('imports active scene nodes, UVs, normals, PBR material and image data', () async {
    final mesh = loader.decodeDocument(await parseFixture());

    expect(mesh.triangles, hasLength(1));
    expect(mesh.vertices, hasLength(3));
    expect(mesh.textureCoordinates, hasLength(3));
    expect(mesh.hasTextureCoordinates, isTrue);
    expect(mesh.textureCoordinates[1].dx, 1);
    expect(mesh.vertexNormals, hasLength(3));
    expect(mesh.vertexNormals.first.z, 1);
    expect(mesh.boundsMin.x, 5);
    expect(mesh.boundsMax.x, 6);
    expect(mesh.sceneNodes, hasLength(2));
    expect(mesh.sceneNodes[1].parentIndex, 0);

    final material = mesh.materialFor(mesh.triangles.single);
    expect(material.metallicFactor, closeTo(0.65, 0.0001));
    expect(material.roughnessFactor, closeTo(0.25, 0.0001));
    expect(material.baseColorTextureBytes, isNotNull);
    expect(material.baseColorTextureBytes, [0]);
    expect(mesh.animations, hasLength(1));
    expect(mesh.animations.single.channels.single.path, 'translation');
  });

  test('decodes glTF base-colour PNG pixels into RGBA texture storage', () async {
    final buffer = fixtureBuffer();
    final sourceImage = img.Image(width: 1, height: 1);
    sourceImage.setPixelRgba(0, 0, 30, 120, 240, 255);
    final pngBytes = img.encodePng(sourceImage);
    final documentJson = fixtureJson(buffer, base64Encode(buffer));
    documentJson['images'] = [
      {'uri': 'data:image/png;base64,${base64Encode(pngBytes)}'}
    ];
    final document = await gltf.Gltf.parse(
      jsonEncode(documentJson),
      loader: (_) async => buffer,
    );

    final mesh = loader.decodeDocument(document);
    final material = mesh.materialFor(mesh.triangles.single);
    expect(material.baseColorTextureWidth, 1);
    expect(material.baseColorTextureHeight, 1);
    expect(material.baseColorTextureRgba, [30, 120, 240, 255]);
  });

  test('evaluates nested node translation animation at the current playhead', () async {
    final mesh = loader.decodeDocument(await parseFixture());
    final evaluator = const GltfSceneEvaluator();
    final matrices = evaluator.worldMatrices(mesh, timeMs: 500);
    final animatedOrigin = evaluator.transformPoint(
      matrices[1],
      const Vector3(0, 0, 0),
    );

    // Root contributes 2, animated child interpolates from 3 to 5.
    expect(animatedOrigin.x, closeTo(6, 0.0001));
  });

  test('rejects a glTF document with no triangle scene geometry', () async {
    final empty = await gltf.Gltf.parse(
      jsonEncode({
        'asset': {'version': '2.0'},
        'scenes': [{'nodes': []}],
        'nodes': [],
      }),
      loader: (_) async => Uint8List(0),
    );
    expect(() => loader.decodeDocument(empty), throwsFormatException);
  });
}
