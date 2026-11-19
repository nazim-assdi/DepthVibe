import 'dart:typed_data';
import 'dart:ui';

import '../domain/composition_models.dart';
import 'software_3d_renderer.dart';

/// Packs CPU-evaluated scene triangles into a compact GPU vertex stream.
///
/// Projection and flat material shading remain CPU evaluated for now. The
/// returned clip-space vertices are rasterized, depth-tested and multisampled
/// by the WebGPU render pipeline.
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

    const floatsPerVertex = 7;
    const verticesPerTriangle = 3;
    final values = Float32List(
      triangles.length * verticesPerTriangle * floatsPerVertex,
    );
    var cursor = 0;

    void writeVertex(Offset point, double distance, Color color) {
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
    }

    for (final triangle in triangles) {
      writeVertex(triangle.a, triangle.distanceA, triangle.color);
      writeVertex(triangle.b, triangle.distanceB, triangle.color);
      writeVertex(triangle.c, triangle.distanceC, triangle.color);
    }

    return GpuMeshVertexData(
      bytes: values.buffer.asUint8List(
        values.offsetInBytes,
        values.lengthInBytes,
      ),
      vertexCount: triangles.length * verticesPerTriangle,
    );
  }

  double _max(double a, double b) => a > b ? a : b;
}

class GpuMeshVertexData {
  const GpuMeshVertexData({
    required this.bytes,
    required this.vertexCount,
  });

  static final empty = GpuMeshVertexData(
    bytes: Uint8List(0),
    vertexCount: 0,
  );

  final Uint8List bytes;
  final int vertexCount;
}
