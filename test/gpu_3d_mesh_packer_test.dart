import 'dart:typed_data';
import 'dart:ui';

import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/gpu_3d_mesh_packer.dart';
import 'package:depthvibe/features/composition/engine/software_3d_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const packer = GpuMeshVertexPacker();
  const triangle = ProjectedMeshTriangle(
    a: Offset(0, 0),
    b: Offset(100, 0),
    c: Offset(50, 100),
    color: Color(0xFF8040FF),
    distance: 200,
    distanceA: 50,
    distanceB: 5000,
    distanceC: 500,
  );

  test('packs clip-space GPU vertices and normalized RGBA', () {
    final result = packer.pack(
      triangles: const [triangle],
      viewport: const Size(100, 100),
      cameraSettings: const CameraSettings(
        nearClip: 50,
        farClip: 5000,
      ),
    );

    expect(result.vertexCount, 3);
    expect(result.bytes.length, 3 * 10 * 4);
    final values = Float32List.view(
      result.bytes.buffer,
      result.bytes.offsetInBytes,
      result.bytes.lengthInBytes ~/ 4,
    );
    expect(values[0], -1);
    expect(values[1], 1);
    expect(values[2], closeTo(0, 0.00001));
    expect(values[3], closeTo(128 / 255, 0.0001));
    expect(values[6], 1);
    expect(values[9], 0);
    expect(values[19], 0);
    expect(values[22], closeTo(0.90909, 0.0001));
  });


  test('packs UV0 and a shared base-colour image for GPU sampling', () {
    final pixels = Uint8List.fromList([30, 120, 240, 255]);
    final textured = ProjectedMeshTriangle(
      a: Offset.zero,
      b: const Offset(100, 0),
      c: const Offset(50, 100),
      color: const Color(0xFFFFFFFF),
      distance: 200,
      distanceA: 50,
      distanceB: 5000,
      distanceC: 500,
      uvA: const Offset(0.25, 0.5),
      uvB: const Offset(1, 0),
      uvC: const Offset(0, 1),
      textureRgba: pixels,
      textureWidth: 1,
      textureHeight: 1,
    );

    final result = packer.pack(
      triangles: [textured],
      viewport: const Size(100, 100),
      cameraSettings: const CameraSettings(nearClip: 50, farClip: 5000),
    );

    expect(result.canRenderGpuMaterialData, isTrue);
    expect(result.hasBaseColorTexture, isTrue);
    expect(result.baseColorTextureRgba, same(pixels));
    expect(result.baseColorTextureWidth, 1);
    expect(result.baseColorTextureHeight, 1);
    final values = Float32List.view(
      result.bytes.buffer,
      result.bytes.offsetInBytes,
      result.bytes.lengthInBytes ~/ 4,
    );
    expect(values[7], closeTo(0.25, 0.0001));
    expect(values[8], closeTo(0.5, 0.0001));
    expect(values[9], 1);
  });

  test('marks meshes with multiple base-colour images for CPU fallback', () {
    final first = Uint8List.fromList([255, 0, 0, 255]);
    final second = Uint8List.fromList([0, 255, 0, 255]);
    ProjectedMeshTriangle withImage(Uint8List pixels) =>
        ProjectedMeshTriangle(
          a: Offset.zero,
          b: const Offset(100, 0),
          c: const Offset(50, 100),
          color: const Color(0xFFFFFFFF),
          distance: 200,
          distanceA: 50,
          distanceB: 5000,
          distanceC: 500,
          textureRgba: pixels,
          textureWidth: 1,
          textureHeight: 1,
        );

    final result = packer.pack(
      triangles: [withImage(first), withImage(second)],
      viewport: const Size(100, 100),
      cameraSettings: const CameraSettings(),
    );

    expect(result.canRenderGpuMaterialData, isFalse);
    expect(result.hasBaseColorTexture, isFalse);
  });


  test('routes alpha mask and blend materials away from the opaque GPU pass', () {
    final masked = ProjectedMeshTriangle(
      a: Offset.zero,
      b: const Offset(100, 0),
      c: const Offset(50, 100),
      color: const Color(0xFFFFFFFF),
      distance: 200,
      distanceA: 50,
      distanceB: 5000,
      distanceC: 500,
      alphaMode: 'MASK',
      alphaCutoff: 0.4,
    );
    final result = packer.pack(
      triangles: [masked],
      viewport: const Size(100, 100),
      cameraSettings: const CameraSettings(),
    );
    expect(result.canRenderGpuMaterialData, isFalse);
  });

  test('uses linear camera depth for orthographic projection', () {
    final result = packer.pack(
      triangles: const [triangle],
      viewport: const Size(100, 100),
      cameraSettings: const CameraSettings(
        projection: 'orthographic',
        nearClip: 50,
        farClip: 5000,
      ),
    );
    final values = Float32List.view(
      result.bytes.buffer,
      result.bytes.offsetInBytes,
      result.bytes.lengthInBytes ~/ 4,
    );
    expect(values[2], 0);
    expect(values[9], 0);
    expect(values[12], 1);
    expect(values[22], closeTo(450 / 4950, 0.0001));
  });

  test('returns an empty upload for empty meshes or invalid viewports', () {
    final empty = packer.pack(
      triangles: const [],
      viewport: const Size(100, 100),
      cameraSettings: const CameraSettings(),
    );
    expect(empty.vertexCount, 0);
    expect(empty.bytes, isEmpty);

    final invalid = packer.pack(
      triangles: const [triangle],
      viewport: Size.zero,
      cameraSettings: const CameraSettings(),
    );
    expect(invalid.vertexCount, 0);
  });
}
