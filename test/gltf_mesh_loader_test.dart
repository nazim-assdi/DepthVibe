import 'dart:convert';
import 'dart:typed_data';

import 'package:depthvibe/features/composition/engine/gltf_mesh_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const loader = GltfMeshLoader();

  Map<String, Object?> triangleDocument() => {
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': 42}
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
          {'buffer': 0, 'byteOffset': 36, 'byteLength': 6}
        ],
        'accessors': [
          {'bufferView': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
          {'bufferView': 1, 'componentType': 5123, 'count': 3, 'type': 'SCALAR'}
        ],
        'materials': [
          {
            'pbrMetallicRoughness': {
              'baseColorFactor': [0.15, 0.4, 0.85, 0.75]
            }
          }
        ],
        'meshes': [
          {
            'primitives': [
              {'attributes': {'POSITION': 0}, 'indices': 1, 'material': 0}
            ]
          }
        ]
      };

  Uint8List triangleBuffer() {
    final data = ByteData(42);
    const positions = [
      0.0, 0.0, 0.0,
      1.0, 0.0, 0.0,
      0.0, 1.0, 0.0,
    ];
    for (var index = 0; index < positions.length; index++) {
      data.setFloat32(index * 4, positions[index], Endian.little);
    }
    data.setUint16(36, 0, Endian.little);
    data.setUint16(38, 1, Endian.little);
    data.setUint16(40, 2, Endian.little);
    return data.buffer.asUint8List();
  }

  test('imports glTF triangle indices and PBR baseColorFactor', () {
    final mesh = loader.parseDocument(
      triangleDocument(),
      [triangleBuffer()],
    );

    expect(mesh.vertices, hasLength(3));
    expect(mesh.triangles, hasLength(1));
    final material = mesh.materialFor(mesh.triangles.single);
    expect(material.red, closeTo(0.15, 0.0001));
    expect(material.green, closeTo(0.4, 0.0001));
    expect(material.blue, closeTo(0.85, 0.0001));
    expect(material.alpha, closeTo(0.75, 0.0001));
  });

  test('reads packed GLB JSON and BIN chunks', () {
    final jsonBytes = utf8.encode(jsonEncode(triangleDocument()));
    final jsonLength = (jsonBytes.length + 3) & ~3;
    final binary = triangleBuffer();
    final binaryLength = (binary.length + 3) & ~3;
    final totalLength = 12 + 8 + jsonLength + 8 + binaryLength;
    final glb = Uint8List(totalLength);
    final data = ByteData.sublistView(glb);
    data.setUint32(0, 0x46546C67, Endian.little);
    data.setUint32(4, 2, Endian.little);
    data.setUint32(8, totalLength, Endian.little);
    var offset = 12;
    data.setUint32(offset, jsonLength, Endian.little);
    data.setUint32(offset + 4, 0x4E4F534A, Endian.little);
    glb.setRange(offset + 8, offset + 8 + jsonBytes.length, jsonBytes);
    for (var index = jsonBytes.length; index < jsonLength; index++) {
      glb[offset + 8 + index] = 0x20;
    }
    offset += 8 + jsonLength;
    data.setUint32(offset, binaryLength, Endian.little);
    data.setUint32(offset + 4, 0x004E4942, Endian.little);
    glb.setRange(offset + 8, offset + 8 + binary.length, binary);

    final parsed = loader.parseGlb(glb);
    final mesh = loader.parseDocument(parsed.document, [parsed.binaryChunk!]);
    expect(mesh.triangles, hasLength(1));
    expect(mesh.boundsMax.x, 1);
    expect(mesh.boundsMax.y, 1);
  });

  test('rejects GLB with an unsupported version', () {
    final bytes = Uint8List(20);
    final data = ByteData.sublistView(bytes)
      ..setUint32(0, 0x46546C67, Endian.little)
      ..setUint32(4, 1, Endian.little)
      ..setUint32(8, 20, Endian.little);
    expect(() => loader.parseGlb(bytes), throwsFormatException);
    expect(data.getUint32(4, Endian.little), 1);
  });
}
