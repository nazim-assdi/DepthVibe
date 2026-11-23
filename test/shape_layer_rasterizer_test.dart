import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../lib/features/composition/domain/composition_models.dart';
import '../lib/features/composition/engine/shape_layer_rasterizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShapeLayerRasterizer', () {
    test('exports a filled ellipse as a transparent PNG at requested size', () async {
      const layer = CompositionLayer(
        id: 'shape-1',
        name: 'Ellipse',
        kind: LayerKind.shape,
        shapeStyle: ShapeStyle(
          primitive: ShapePrimitive.ellipse,
          fillColor: '#12AB34',
        ),
      );

      final bytes = await const ShapeLayerRasterizer().rasterize(
        layer,
        width: 96,
        height: 64,
        timeMs: 0,
      );

      final decoded = image.decodePng(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 96);
      expect(decoded.height, 64);
      expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    test('renders animated Bezier path vertices at the requested time', () async {
      const layer = CompositionLayer(
        id: 'shape-path',
        name: 'Animated path',
        kind: LayerKind.shape,
        shapeStyle: ShapeStyle(
          primitive: ShapePrimitive.path,
          fillColor: '#FFFFFF',
          pathClosed: true,
          pathVertices: [
            MaskVertex(
              anchor: Vector2(0.1, 0.1),
              outHandle: Vector2(0.1, 0),
            ),
            MaskVertex(
              anchor: Vector2(0.9, 0.1),
              inHandle: Vector2(-0.1, 0),
            ),
            MaskVertex(anchor: Vector2(0.5, 0.9)),
          ],
        ),
        keyframeTracks: [
          KeyframeTrack(
            property: 'shape.vertex.1.anchor.x',
            keyframes: [
              ScalarKeyframe(timeMs: 0, value: 0.9),
              ScalarKeyframe(timeMs: 1000, value: 0.7),
            ],
          ),
        ],
      );

      final rasterizer = const ShapeLayerRasterizer();
      final first = await rasterizer.rasterize(
        layer,
        width: 128,
        height: 128,
        timeMs: 0,
      );
      final second = await rasterizer.rasterize(
        layer,
        width: 128,
        height: 128,
        timeMs: 1000,
      );

      expect(image.decodePng(first), isNotNull);
      expect(image.decodePng(second), isNotNull);
      expect(first, isNot(equals(second)));
    });

    test('rejects raster sizes above the safe pixel budget', () async {
      const layer = CompositionLayer(
        id: 'shape-limit',
        name: 'Oversized',
        kind: LayerKind.shape,
        shapeStyle: ShapeStyle(),
      );

      await expectLater(
        const ShapeLayerRasterizer().rasterize(
          layer,
          width: 8192,
          height: 4096,
          timeMs: 0,
        ),
        throwsStateError,
      );
    });
  });
}
