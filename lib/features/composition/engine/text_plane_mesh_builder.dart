import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/composition_models.dart';
import 'obj_mesh_loader.dart';

/// Converts a transparent text raster into a camera-facing textured mesh.
/// The source remains an editable text layer; this mesh is render-time output.
class TextPlaneMeshBuilder {
  const TextPlaneMeshBuilder();

  static const int _maxDimension = 8192;
  static const int _maxPixels = 16 * 1024 * 1024;
  static const int _maxGridDimension = 512;
  static const int _maxSideFaces = 50000;

  Future<ObjMesh> fromPngBytes(
    Uint8List pngBytes, {
    double extrusionDepth = 0,
    String sideColor = '#666666',
  }) async {
    if (pngBytes.isEmpty) {
      throw const FormatException('Text plane image is empty.');
    }
    if (!extrusionDepth.isFinite || extrusionDepth < 0 || extrusionDepth > 1) {
      throw ArgumentError.value(
        extrusionDepth,
        'extrusionDepth',
        'Expected a finite ratio from 0 to 1.',
      );
    }

    final codec = await ui.instantiateImageCodec(pngBytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final width = image.width;
        final height = image.height;
        if (width < 1 || height < 1 ||
            width > _maxDimension || height > _maxDimension ||
            width * height > _maxPixels) {
          throw const FormatException(
            'Text plane image exceeds the safe 16-megapixel limit.',
          );
        }
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) {
          throw const FormatException('Could not decode the text plane pixels.');
        }
        final rgba = Uint8List.fromList(data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ));
        if (extrusionDepth <= 0.0001) {
          return _flatPlane(
            pngBytes: pngBytes,
            rgba: rgba,
            width: width,
            height: height,
          );
        }
        return _extrudedText(
          pngBytes: pngBytes,
          rgba: rgba,
          width: width,
          height: height,
          depth: extrusionDepth,
          sideColor: sideColor,
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  ObjMesh _flatPlane({
    required Uint8List pngBytes,
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    final halfHeight = height / width / 2;
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
        'text': _textMaterial(pngBytes, rgba, width, height),
      },
      boundsMin: Vector3(-0.5, -halfHeight, 0),
      boundsMax: Vector3(0.5, halfHeight, 0),
      textureCoordinates: const [
        ui.Offset(0, 1),
        ui.Offset(1, 1),
        ui.Offset(1, 0),
        ui.Offset(0, 0),
      ],
      hasTextureCoordinates: true,
    );
  }

  ObjMesh _extrudedText({
    required Uint8List pngBytes,
    required Uint8List rgba,
    required int width,
    required int height,
    required double depth,
    required String sideColor,
  }) {
    final halfHeight = height / width / 2;
    final halfDepth = depth / 2;
    final step = (width > height ? width : height) / _maxGridDimension;
    final cellSize = step.ceil().clamp(1, _maxDimension).toInt();
    final columns = (width / cellSize).ceil();
    final rows = (height / cellSize).ceil();
    final occupied = List<bool>.filled(rows * columns, false);

    bool hasVisiblePixel(int left, int top, int right, int bottom) {
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          if (rgba[(y * width + x) * 4 + 3] >= 32) return true;
        }
      }
      return false;
    }

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final left = column * cellSize;
        final top = row * cellSize;
        final right = (left + cellSize).clamp(0, width).toInt();
        final bottom = (top + cellSize).clamp(0, height).toInt();
        occupied[row * columns + column] =
            hasVisiblePixel(left, top, right, bottom);
      }
    }

    bool solid(int row, int column) =>
        row >= 0 && row < rows &&
        column >= 0 && column < columns &&
        occupied[row * columns + column];

    double xAt(int pixelX) => -0.5 + pixelX / width;
    double yAt(int pixelY) => halfHeight - pixelY / width;

    final vertices = <Vector3>[];
    final textureCoordinates = <ui.Offset>[];
    final triangles = <ObjTriangle>[];

    void addQuad(
      List<Vector3> points,
      List<ui.Offset> uvs, {
      required String material,
    }) {
      final first = vertices.length;
      vertices.addAll(points);
      textureCoordinates.addAll(uvs);
      triangles
        ..add(ObjTriangle(first, first + 1, first + 2, material: material))
        ..add(ObjTriangle(first, first + 2, first + 3, material: material));
    }

    // Front textured cap, facing +Z.
    addQuad(
      [
        Vector3(-0.5, -halfHeight, halfDepth),
        Vector3(0.5, -halfHeight, halfDepth),
        Vector3(0.5, halfHeight, halfDepth),
        Vector3(-0.5, halfHeight, halfDepth),
      ],
      const [
        ui.Offset(0, 1),
        ui.Offset(1, 1),
        ui.Offset(1, 0),
        ui.Offset(0, 0),
      ],
      material: 'text',
    );

    // Back cap is wound in the opposite direction for the back-facing view.
    addQuad(
      [
        Vector3(-0.5, -halfHeight, -halfDepth),
        Vector3(-0.5, halfHeight, -halfDepth),
        Vector3(0.5, halfHeight, -halfDepth),
        Vector3(0.5, -halfHeight, -halfDepth),
      ],
      const [
        ui.Offset(0, 1),
        ui.Offset(0, 0),
        ui.Offset(1, 0),
        ui.Offset(1, 1),
      ],
      material: 'text',
    );

    var sideFaceCount = 0;
    void addSide(List<Vector3> points) {
      sideFaceCount++;
      if (sideFaceCount > _maxSideFaces) {
        throw StateError(
          '3D text outline is too complex for safe mesh generation. '
          'Reduce the text image size or extrusion detail.',
        );
      }
      addQuad(
        points,
        const [
          ui.Offset(0, 0),
          ui.Offset(0, 0),
          ui.Offset(0, 0),
          ui.Offset(0, 0),
        ],
        material: 'side',
      );
    }

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        if (!solid(row, column)) continue;
        final left = column * cellSize;
        final top = row * cellSize;
        final right = (left + cellSize).clamp(0, width);
        final bottom = (top + cellSize).clamp(0, height);
        final x0 = xAt(left);
        final x1 = xAt(right);
        final yTop = yAt(top);
        final yBottom = yAt(bottom);

        if (!solid(row - 1, column)) {
          // Top wall, outward normal +Y.
          addSide([
            Vector3(x0, yTop, halfDepth),
            Vector3(x1, yTop, halfDepth),
            Vector3(x1, yTop, -halfDepth),
            Vector3(x0, yTop, -halfDepth),
          ]);
        }
        if (!solid(row + 1, column)) {
          // Bottom wall, outward normal -Y.
          addSide([
            Vector3(x0, yBottom, halfDepth),
            Vector3(x0, yBottom, -halfDepth),
            Vector3(x1, yBottom, -halfDepth),
            Vector3(x1, yBottom, halfDepth),
          ]);
        }
        if (!solid(row, column - 1)) {
          // Left wall, outward normal -X.
          addSide([
            Vector3(x0, yTop, halfDepth),
            Vector3(x0, yTop, -halfDepth),
            Vector3(x0, yBottom, -halfDepth),
            Vector3(x0, yBottom, halfDepth),
          ]);
        }
        if (!solid(row, column + 1)) {
          // Right wall, outward normal +X.
          addSide([
            Vector3(x1, yTop, halfDepth),
            Vector3(x1, yBottom, halfDepth),
            Vector3(x1, yBottom, -halfDepth),
            Vector3(x1, yTop, -halfDepth),
          ]);
        }
      }
    }

    final side = _parseSideColor(sideColor);
    return ObjMesh(
      vertices: vertices,
      triangles: triangles,
      materials: {
        'text': _textMaterial(pngBytes, rgba, width, height),
        'side': ObjMaterial(
          red: side.$1,
          green: side.$2,
          blue: side.$3,
          alpha: 1,
          doubleSided: true,
        ),
      },
      boundsMin: Vector3(-0.5, -halfHeight, -halfDepth),
      boundsMax: Vector3(0.5, halfHeight, halfDepth),
      textureCoordinates: textureCoordinates,
      hasTextureCoordinates: true,
    );
  }

  ObjMaterial _textMaterial(
    Uint8List pngBytes,
    Uint8List rgba,
    int width,
    int height,
  ) =>
      ObjMaterial(
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
      );

  (double, double, double) _parseSideColor(String value) {
    var hex = value.replaceFirst('#', '');
    if (hex.length == 8) hex = hex.substring(2);
    final parsed = int.tryParse(hex, radix: 16) ?? 0x666666;
    final red = ((parsed >> 16) & 0xFF) / 255 * 0.48;
    final green = ((parsed >> 8) & 0xFF) / 255 * 0.48;
    final blue = (parsed & 0xFF) / 255 * 0.48;
    return (red, green, blue);
  }
}
