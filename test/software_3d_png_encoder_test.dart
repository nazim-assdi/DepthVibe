import 'dart:typed_data';

import 'package:depthvibe/features/composition/engine/software_3d_png_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('encodes transparent RGBA bytes into a decodable PNG', () {
    final rgba = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 128,
      0, 0, 255, 0, 255, 255, 255, 255,
    ]);
    final png = const Software3dPngEncoder().encodeRgba(
      width: 2,
      height: 2,
      rgba: rgba,
    );
    expect(png.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    final decoded = img.decodeImage(png);
    expect(decoded, isNotNull);
    expect(decoded!.width, 2);
    expect(decoded.height, 2);
    expect(decoded.getPixel(0, 0).r, 255);
    expect(decoded.getPixel(1, 0).a, closeTo(128, 1));
    expect(decoded.getPixel(0, 1).a, 0);
  });

  test('rejects a mismatched RGBA buffer length', () {
    expect(
      () => const Software3dPngEncoder().encodeRgba(
        width: 2,
        height: 2,
        rgba: Uint8List(4),
      ),
      throwsArgumentError,
    );
  });
}
