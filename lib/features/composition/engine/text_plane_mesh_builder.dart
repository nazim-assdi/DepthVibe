import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/composition_models.dart';
import 'obj_mesh_loader.dart';

/// Converts a transparent text PNG into a camera-facing, texture-mapped quad.
/// The text remains editable in the document; this mesh is generated output.
class TextPlaneMeshBuilder {
  const TextPlaneMeshBuilder();

  Future<ObjMesh> fromPngBytes(Uint8List pngBytes) async {
    if (pngBytes.isEmpty) {
      throw const FormatException('Text plane image is empty.');
    }

    final codec = await ui.instantiateImageCodec(pngBytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final width = image.width;
        final height = image.height;
        if (width < 1 || height < 1 ||
            width > 8192 || height > 8192 ||
            width * height > 16 * 1024 * 1024) {
          throw const FormatException('Text plane image exceeds the 16-megapixel limit.');
        }
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) {
          throw const FormatException('Could not decode the text plane pixels.');
        }
        final rgba = Uint8List.fromList(data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ));
        final aspect = height / width;
        final halfHeight = aspect / 2;
        const boundsMin = Vector3(-0.5, -0.5, 0);
        const boundsMax = Vector3(0.5, 0.5, 0);

        return ObjMesh(
          vertices: [
            Vector3(-0.5, -halfHeight, 0),
            Vector3(0.5, -halfHeight, 0),
            Vector3(0.5, halfHeight, 0),
            Vector3(-0.5, halfHeight, 0),
          ],
          triangles: const [
            ObjTriangle(0, 1, 2, material: 'text'),
            ObjTriangle(0, 2, 3, material: 'text'),
          ],
          materials: {
            'text': ObjMaterial(
              red: 1,
              green: 1,
              blue: 1,
              alpha: 1,
              baseColorTextureBytes: Uint8List.fromList(pngBytes),
              baseColorTextureRgba: rgba,
              baseColorTextureWidth: width,
              baseColorTextureHeight: height,
              alphaMode: 'BLEND',
              doubleSided: true,
            ),
          },
          boundsMin: Vector3(-0.5, -halfHeight, 0),
          boundsMax: Vector3(0.5, halfHeight, 0),
          textureCoordinates: const [
            ui.Offset(0, 0),
            ui.Offset(1, 0),
            ui.Offset(1, 1),
            ui.Offset(0, 1),
          ],
          hasTextureCoordinates: true,
          vertexNormals: const [
            Vector3(0, 0, 1),
            Vector3(0, 0, 1),
            Vector3(0, 0, 1),
            Vector3(0, 0, 1),
          ],
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
