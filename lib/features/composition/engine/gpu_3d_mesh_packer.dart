import 'dart:typed_data';
import 'dart:ui';

import '../domain/composition_models.dart';
import 'software_3d_renderer.dart';

/// Packs projected scene triangles for the WebGPU mesh pass.
///
/// Position, precomputed CPU lighting and UV0 are uploaded together. A single
/// shared base-colour image can be sampled by the GPU; multi-image materials
/// are explicitly flagged for the software renderer until material batching
/// and texture arrays are introduced.
class GpuMeshVertexPacker {
  const GpuMeshVertexPacker();

  GpuMeshVertexData pack({
    required List<ProjectedMeshTriangle> triangles,
    required Size viewport,
    required CameraSettings cameraSettings,
  }) {
    if (viewport.width <= 0 || viewport.height <= 0 || triangles.isEmpty) {
      return GpuMeshVertexData.empty;
    }

    bool hasValidTexture(ProjectedMeshTriangle triangle) {
      final pixels = triangle.textureRgba;
      return pixels != null &&
          triangle.textureWidth > 0 &&
          triangle.textureHeight > 0 &&
          pixels.length == triangle.textureWidth * triangle.textureHeight * 4;
    }

    final uniqueTextures = <Uint8List>{};
    for (final triangle in triangles) {
      if (hasValidTexture(triangle)) {
        uniqueTextures.add(triangle.textureRgba!);
      }
    }
    final canRenderBaseColorTextures = uniqueTextures.length <= 1;
    final texture = canRenderBaseColorTextures && uniqueTextures.isNotEmpty
        ? uniqueTextures.single
        : null;
    final texturedTriangle = canRenderBaseColorTextures
        ? triangles.cast<ProjectedMeshTriangle?>().firstWhere(
              (triangle) =>
                  triangle != null && hasValidTexture(triangle),
              orElse: () => null,
            )
        : null;
    final textureWidth = texturedTriangle?.textureWidth ?? 0;
    final textureHeight = texturedTriangle?.textureHeight ?? 0;

    // position(3) + colour(4) + UV(2) + texture-present flag(1).
    const floatsPerVertex = 10;
    const verticesPerTriangle = 3;
    final values = Float32List(
      triangles.length * verticesPerTriangle * floatsPerVertex,
    );
    var cursor = 0;

    void writeVertex(
      Offset point,
      double distance,
      Color color,
      Offset uv,
      bool hasTexture,
    ) {
      final x = (point.dx / viewport.width) * 2 - 1;
      final y = 1 - (point.dy / viewport.height) * 2;
      final near = cameraSettings.nearClip.clamp(0.001, 100000.0).toDouble();
      final far = _max(near + 0.001, cameraSettings.farClip);
      final d = distance.clamp(near, far).toDouble();
      final depth = cameraSettings.projection == 'orthographic'
          ? (d - near) / (far - near)
          : far / (far - near) -
              (far * near) / ((far - near) * d);

      values[cursor++] = x;
      values[cursor++] = y;
      values[cursor++] = depth.clamp(0.0, 1.0).toDouble();
      values[cursor++] = color.r;
      values[cursor++] = color.g;
      values[cursor++] = color.b;
      values[cursor++] = color.a;
      values[cursor++] = uv.dx;
      values[cursor++] = uv.dy;
      values[cursor++] = hasTexture ? 1 : 0;
    }

    for (final triangle in triangles) {
      final useTexture = canRenderBaseColorTextures &&
          hasValidTexture(triangle) &&
          texture != null &&
          identical(triangle.textureRgba, texture);
      writeVertex(
        triangle.a,
        triangle.distanceA,
        triangle.color,
        triangle.uvA,
        useTexture,
      );
      writeVertex(
        triangle.b,
        triangle.distanceB,
        triangle.color,
        triangle.uvB,
        useTexture,
      );
      writeVertex(
        triangle.c,
        triangle.distanceC,
        triangle.color,
        triangle.uvC,
        useTexture,
      );
    }

    return GpuMeshVertexData(
      bytes: values.buffer.asUint8List(
        values.offsetInBytes,
        values.lengthInBytes,
      ),
      vertexCount: triangles.length * verticesPerTriangle,
      canRenderBaseColorTextures: canRenderBaseColorTextures,
      baseColorTextureRgba: texture,
      baseColorTextureWidth: textureWidth,
      baseColorTextureHeight: textureHeight,
    );
  }

  double _max(double a, double b) => a > b ? a : b;
}

class GpuMeshVertexData {
  const GpuMeshVertexData({
    required this.bytes,
    required this.vertexCount,
    required this.canRenderBaseColorTextures,
    this.baseColorTextureRgba,
    this.baseColorTextureWidth = 0,
    this.baseColorTextureHeight = 0,
  });

  static final empty = GpuMeshVertexData(
    bytes: Uint8List(0),
    vertexCount: 0,
    canRenderBaseColorTextures: true,
  );

  final Uint8List bytes;
  final int vertexCount;
  final bool canRenderBaseColorTextures;
  final Uint8List? baseColorTextureRgba;
  final int baseColorTextureWidth;
  final int baseColorTextureHeight;

  bool get hasBaseColorTexture =>
      baseColorTextureRgba != null &&
      baseColorTextureWidth > 0 &&
      baseColorTextureHeight > 0;
}
