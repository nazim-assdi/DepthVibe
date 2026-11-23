import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/composition_models.dart';

/// Rasterizes editable vector shape layers to transparent PNG frames for the
/// CPU/FFmpeg export path. The returned bitmap remains a regular source layer,
/// so transforms, masks, blend modes and the layer effect stack are preserved.
class ShapeLayerRasterizer {
  const ShapeLayerRasterizer();

  static const int maxDimension = 16384;
  static const int maxPixels = 16 * 1024 * 1024;

  Future<Uint8List> rasterize(
    CompositionLayer layer, {
    required int width,
    required int height,
    required int timeMs,
  }) async {
    if (layer.kind != LayerKind.shape) {
      throw ArgumentError.value(layer.kind, 'layer.kind', 'Expected a shape layer.');
    }
    if (width < 1 || height < 1 ||
        width > maxDimension || height > maxDimension ||
        width * height > maxPixels) {
      throw StateError(
        'Shape layer ${layer.name} exceeds the safe 16-megapixel raster limit.',
      );
    }

    final style = _styleAt(layer, timeMs);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    _paint(canvas, ui.Size(width.toDouble(), height.toDouble()), style);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('Could not encode shape layer ${layer.name} as PNG.');
        }
        return data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  ShapeStyle _styleAt(CompositionLayer layer, int timeMs) {
    final style = layer.shapeStyle ?? const ShapeStyle();
    if (style.pathVertices.isEmpty) return style;

    double sample(int index, String property, double fallback) {
      final propertyName = 'shape.vertex.$index.$property';
      for (final track in layer.keyframeTracks) {
        if (track.enabled && track.property == propertyName) {
          return track.sample(timeMs, fallback: fallback);
        }
      }
      return fallback;
    }

    final vertices = <MaskVertex>[
      for (var index = 0; index < style.pathVertices.length; index++)
        style.pathVertices[index].copyWith(
          anchor: Vector2(
            sample(index, 'anchor.x', style.pathVertices[index].anchor.x),
            sample(index, 'anchor.y', style.pathVertices[index].anchor.y),
          ),
          inHandle: Vector2(
            sample(index, 'inHandle.x', style.pathVertices[index].inHandle.x),
            sample(index, 'inHandle.y', style.pathVertices[index].inHandle.y),
          ),
          outHandle: Vector2(
            sample(index, 'outHandle.x', style.pathVertices[index].outHandle.x),
            sample(index, 'outHandle.y', style.pathVertices[index].outHandle.y),
          ),
        ),
    ];
    return style.copyWith(pathVertices: vertices);
  }

  ui.Color _color(String value) {
    final normalized = value.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16) ?? 0x7C8CFF;
    return ui.Color(
      normalized.length == 8 ? parsed : (0xFF000000 | parsed),
    );
  }

  ui.Path _vectorPath(ui.Size size, ShapeStyle style) {
    final path = ui.Path();
    final vertices = style.pathVertices;
    if (vertices.length < 2) return path;

    ui.Offset map(Vector2 point) => ui.Offset(
          point.x * size.width,
          point.y * size.height,
        );

    path.moveTo(
      vertices.first.anchor.x * size.width,
      vertices.first.anchor.y * size.height,
    );
    final segments = style.pathClosed ? vertices.length : vertices.length - 1;
    for (var index = 0; index < segments; index++) {
      final next = (index + 1) % vertices.length;
      final start = vertices[index];
      final end = vertices[next];
      final p1 = map(Vector2(
        start.anchor.x + start.outHandle.x,
        start.anchor.y + start.outHandle.y,
      ));
      final p2 = map(Vector2(
        end.anchor.x + end.inHandle.x,
        end.anchor.y + end.inHandle.y,
      ));
      final p3 = map(end.anchor);
      path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
    }
    if (style.pathClosed) path.close();
    return path;
  }

  ui.Path _primitivePath(ui.Size size, ShapeStyle style) {
    final path = ui.Path();
    final bounds = ui.Offset.zero & size;
    switch (style.primitive) {
      case ShapePrimitive.rectangle:
        path.addRect(bounds);
        break;
      case ShapePrimitive.roundedRectangle:
        path.addRRect(
          ui.RRect.fromRectAndRadius(
            bounds,
            ui.Radius.circular(style.cornerRadius.clamp(0.0, 100000.0)),
          ),
        );
        break;
      case ShapePrimitive.ellipse:
        path.addOval(bounds);
        break;
      case ShapePrimitive.polygon:
      case ShapePrimitive.star:
        final points = style.points.clamp(3, 24);
        final count = style.primitive == ShapePrimitive.star ? points * 2 : points;
        final center = ui.Offset(size.width / 2, size.height / 2);
        final radius = size.shortestSide / 2;
        for (var index = 0; index < count; index++) {
          final inner = style.primitive == ShapePrimitive.star && index.isOdd;
          final pointRadius = inner ? radius * 0.42 : radius;
          final angle = -3.141592653589793 / 2 +
              index * 3.141592653589793 * 2 / count;
          final point = ui.Offset(
            center.dx + math.cos(angle) * pointRadius,
            center.dy + math.sin(angle) * pointRadius,
          );
          if (index == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        break;
      case ShapePrimitive.path:
        return _vectorPath(size, style);
    }
    return path;
  }

  void _paint(ui.Canvas canvas, ui.Size size, ShapeStyle style) {
    final path = _primitivePath(size, style);
    final hasFill = style.primitive != ShapePrimitive.path || style.pathClosed;
    if (hasFill && style.fillColor.toLowerCase() != 'transparent') {
      canvas.drawPath(
        path,
        ui.Paint()
          ..style = ui.PaintingStyle.fill
          ..color = _color(style.fillColor)
          ..isAntiAlias = true,
      );
    }
    if (style.strokeWidth > 0) {
      canvas.drawPath(
        path,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = style.strokeWidth
          ..color = _color(style.strokeColor)
          ..isAntiAlias = true,
      );
    }
  }
}
