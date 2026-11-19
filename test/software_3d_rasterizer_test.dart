import 'dart:ui';

import 'package:depthvibe/features/composition/engine/software_3d_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Z-buffer keeps the nearer triangle regardless of draw order', () {
    const far = ProjectedMeshTriangle(
      a: Offset(1, 1),
      b: Offset(7, 1),
      c: Offset(4, 7),
      color: Color(0xFFFF0000),
      distance: 20,
      distanceA: 20,
      distanceB: 20,
      distanceC: 20,
    );
    const near = ProjectedMeshTriangle(
      a: Offset(1, 1),
      b: Offset(7, 1),
      c: Offset(4, 7),
      color: Color(0xFF00FF00),
      distance: 10,
      distanceA: 10,
      distanceB: 10,
      distanceC: 10,
    );
    final frame = Software3dRasterizer().rasterize(
      const [near, far],
      width: 8,
      height: 8,
    );
    final pixel = (3 * 8 + 4) * 4;
    expect(frame.rgba[pixel], 0);
    expect(frame.rgba[pixel + 1], 255);
    expect(frame.rgba[pixel + 2], 0);
    expect(frame.depth[3 * 8 + 4], 10);
  });

  test('depth-of-field pass softens pixels away from the focus plane', () {
    const triangle = ProjectedMeshTriangle(
      a: Offset(1, 1),
      b: Offset(7, 1),
      c: Offset(4, 7),
      color: Color(0xFFFFFFFF),
      distance: 1200,
      distanceA: 1200,
      distanceB: 1200,
      distanceC: 1200,
    );
    final sharp = Software3dRasterizer().rasterize(
      const [triangle],
      width: 9,
      height: 9,
      focusDistance: 1000,
      aperture: 22,
    );
    final blurred = Software3dRasterizer().rasterize(
      const [triangle],
      width: 9,
      height: 9,
      depthOfField: true,
      focusDistance: 1000,
      aperture: 22,
    );
    final edgePixel = (4 * 9 + 2) * 4;
    expect(sharp.rgba[edgePixel + 3], 255);
    expect(blurred.rgba[edgePixel + 3], lessThan(sharp.rgba[edgePixel + 3]));
    expect(blurred.depth[4 * 9 + 4], 1200);
  });

  test('rejects unsafe raster dimensions', () {
    expect(
      () => Software3dRasterizer().rasterize(
        const [],
        width: 5000,
        height: 5000,
      ),
      throwsArgumentError,
    );
  });
}
