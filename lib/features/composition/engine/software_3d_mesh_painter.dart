import 'package:flutter/rendering.dart';

import '../domain/composition_models.dart';
import 'obj_mesh_loader.dart';
import 'parent_transform_resolver.dart';
import 'software_3d_renderer.dart';

class Software3dMeshPainter extends CustomPainter {
  const Software3dMeshPainter({
    required this.mesh,
    required this.modelTransform,
    required this.cameraTransform,
    required this.cameraSettings,
    required this.lights,
    required this.compositionWidth,
    required this.compositionHeight,
    required this.baseWidth,
  });

  final ObjMesh mesh;
  final ResolvedLayerTransform modelTransform;
  final ResolvedLayerTransform cameraTransform;
  final CameraSettings cameraSettings;
  final List<SceneLight> lights;
  final double compositionWidth;
  final double compositionHeight;
  final double baseWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final triangles = const Software3dRenderer().projectTriangles(
      mesh: mesh,
      viewport: size,
      baseWidth: baseWidth,
      compositionWidth: compositionWidth,
      compositionHeight: compositionHeight,
      modelTransform: modelTransform,
      cameraTransform: cameraTransform,
      cameraSettings: cameraSettings,
      lights: lights,
    );
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55
      ..color = const Color(0x26314055)
      ..isAntiAlias = true;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final triangle in triangles) {
      final path = Path()
        ..moveTo(triangle.a.dx, triangle.a.dy)
        ..lineTo(triangle.b.dx, triangle.b.dy)
        ..lineTo(triangle.c.dx, triangle.c.dy)
        ..close();
      fill.color = triangle.color;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant Software3dMeshPainter oldDelegate) =>
      mesh != oldDelegate.mesh ||
      modelTransform != oldDelegate.modelTransform ||
      cameraTransform != oldDelegate.cameraTransform ||
      cameraSettings != oldDelegate.cameraSettings ||
      lights != oldDelegate.lights ||
      compositionWidth != oldDelegate.compositionWidth ||
      compositionHeight != oldDelegate.compositionHeight;
}
