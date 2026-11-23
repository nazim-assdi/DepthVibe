import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/composition/engine/software_3d_png_encoder.dart';
import '../lib/features/composition/engine/text_plane_mesh_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a camera-ready textured quad from a transparent text PNG', () async {
    final png = const Software3dPngEncoder().encodeRgba(
      width: 4,
      height: 2,
      rgba: Uint8List.fromList([
        255, 255, 255, 0, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 255, 0,
        255, 255, 255, 0, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 255, 0,
      ]),
    );

    final mesh = await const TextPlaneMeshBuilder().fromPngBytes(png);
    expect(mesh.vertices, hasLength(4));
    expect(mesh.triangles, hasLength(2));
    expect(mesh.textureCoordinates, hasLength(4));
    expect(mesh.hasTextureCoordinates, isTrue);
    expect(mesh.materials['text']?.alphaMode, 'BLEND');
    expect(mesh.materials['text']?.baseColorTextureWidth, 4);
    expect(mesh.materials['text']?.baseColorTextureHeight, 2);
    expect(mesh.materials['text']?.baseColorTextureRgba, hasLength(32));
    expect(mesh.maxDimension, 1);
  });

  test('rejects empty and invalid text image data', () async {
    final builder = const TextPlaneMeshBuilder();
    await expectLater(builder.fromPngBytes(Uint8List(0)), throwsFormatException);
    await expectLater(
      builder.fromPngBytes(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(anything),
    );
  });
}
