import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/ffmpeg_animation_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const compiler = FfmpegAnimationCompiler();

  test('compiles interpolated transform keyframes into per-frame expressions', () {
    const layer = CompositionLayer(
      id: 'footage',
      name: 'Footage',
      kind: LayerKind.video,
      transform: LayerTransform(
        position: Vector3(100, 200, 0),
      ),
      keyframeTracks: [
        KeyframeTrack(
          property: 'position.x',
          keyframes: [
            ScalarKeyframe(
              timeMs: 0,
              value: 100,
              interpolation: Interpolation.easeInOut,
            ),
            ScalarKeyframe(timeMs: 1000, value: 500),
          ],
        ),
      ],
    );

    final expression = compiler.scalarExpression(
      layer: layer,
      property: 'position.x',
      fallback: 100,
    );

    expect(expression, contains('if(lt(t,'));
    expect(expression, contains('pow('));
    expect(expression, contains('500.00000'));
  });

  test('keeps hold keyframes constant between keyframe times', () {
    const track = KeyframeTrack(
      property: 'opacity',
      keyframes: [
        ScalarKeyframe(
          timeMs: 0,
          value: 25,
          interpolation: Interpolation.hold,
        ),
        ScalarKeyframe(timeMs: 1000, value: 90),
      ],
    );

    final expression = compiler.keyframeExpression(track, fallback: 100);
    expect(expression, contains('25.00000'));
    expect(expression, contains('90.00000'));
    expect(expression, isNot(contains('pow(')));
  });

  test('builds rectangle, ellipse and polygon mask alpha expressions', () {
    final expression = compiler.maskAlphaExpression(const [
      MaskModel(
        id: 'rect',
        name: 'Frame',
        shape: MaskShape.rectangle,
        feather: 12,
      ),
      MaskModel(
        id: 'ellipse',
        name: 'Soft circle',
        shape: MaskShape.ellipse,
        operation: MaskOperation.intersect,
        inverted: true,
      ),
      MaskModel(
        id: 'poly',
        name: 'Polygon',
        shape: MaskShape.polygon,
        operation: MaskOperation.subtract,
        vertices: [
          MaskVertex(anchor: Vector2(0.2, 0.2)),
          MaskVertex(anchor: Vector2(0.8, 0.2)),
          MaskVertex(anchor: Vector2(0.5, 0.8)),
        ],
      ),
    ]);

    expect(expression, contains('sqrt('));
    expect(expression, contains('mod('));
    expect(expression, contains('hypot('));
    expect(expression, contains('min(1,max(0,'));
  });

  test('flattens Bezier mask handles into curved export outlines', () {
    const compiler = FfmpegAnimationCompiler();
    final vertices = [
      const MaskVertex(
        anchor: Vector2(0.2, 0.2),
        outHandle: Vector2(0.25, 0),
      ),
      const MaskVertex(
        anchor: Vector2(0.8, 0.2),
        inHandle: Vector2(-0.25, 0.25),
      ),
      const MaskVertex(
        anchor: Vector2(0.5, 0.8),
        outHandle: Vector2(0, -0.2),
      ),
    ];

    final polygon = compiler.maskAlphaExpression([
      MaskModel(
        id: 'polygon',
        name: 'Polygon',
        shape: MaskShape.polygon,
        vertices: vertices,
      ),
    ]);
    final bezier = compiler.maskAlphaExpression([
      MaskModel(
        id: 'bezier',
        name: 'Bezier',
        shape: MaskShape.bezier,
        vertices: vertices,
      ),
    ]);

    final polygonEdges = RegExp('hypot\\(').allMatches(polygon).length;
    final bezierEdges = RegExp('hypot\\(').allMatches(bezier).length;
    expect(bezierEdges, greaterThan(polygonEdges));
  });

  test('compiles wipe alpha and slide position transitions', () {
    const layer = CompositionLayer(
      id: 'clip-b',
      name: 'Clip B',
      kind: LayerKind.video,
    );
    const wipe = CompositionTransition(
      id: 'wipe-1',
      fromLayerId: 'clip-a',
      toLayerId: 'clip-b',
      kind: TransitionKind.wipeLeft,
      durationMs: 800,
      startMs: 1000,
    );
    const slide = CompositionTransition(
      id: 'slide-1',
      fromLayerId: 'clip-a',
      toLayerId: 'clip-b',
      kind: TransitionKind.slideLeft,
      durationMs: 800,
      startMs: 1000,
    );

    final alpha = compiler.transitionAlphaExpression(
      layer: layer,
      transitions: const [wipe],
    );
    final position = compiler.transitionPositionExpression(
      layer: layer,
      transitions: const [slide],
      baseExpression: '960',
      axis: 'x',
      compositionWidth: 1920,
      compositionHeight: 1080,
    );

    expect(alpha, contains('X'));
    expect(alpha, contains('T'));
    expect(position, contains('1920'));
    expect(position, contains('t'));
  });

  test('samples custom cubic Bezier keyframe curves in timeline time', () {
    const track = KeyframeTrack(
      property: 'position.x',
      keyframes: [
        ScalarKeyframe(
          timeMs: 0,
          value: 0,
          interpolation: Interpolation.cubicBezier,
          bezier: BezierCurve(x1: 0.42, y1: 0, x2: 0.58, y2: 1),
        ),
        ScalarKeyframe(timeMs: 1000, value: 100),
      ],
    );

    expect(track.sample(0), 0);
    expect(track.sample(500), closeTo(50, 0.001));
    expect(track.sample(1000), 100);
  });

  test('preserves Bezier control points when keyframes are serialized', () {
    const keyframe = ScalarKeyframe(
      timeMs: 420,
      value: 75,
      interpolation: Interpolation.cubicBezier,
      bezier: BezierCurve(x1: 0.1, y1: 0.2, x2: 0.8, y2: 0.9),
    );

    final decoded = ScalarKeyframe.fromJson(
      keyframe.toJson().cast<String, Object?>(),
    );

    expect(decoded.interpolation, Interpolation.cubicBezier);
    expect(decoded.bezier.x1, 0.1);
    expect(decoded.bezier.y1, 0.2);
    expect(decoded.bezier.x2, 0.8);
    expect(decoded.bezier.y2, 0.9);
  });

  test('compiles cubic Bezier handles to native FFmpeg frame expressions', () {
    const layer = CompositionLayer(
      id: 'bezier-layer',
      name: 'Bezier Layer',
      kind: LayerKind.video,
      keyframeTracks: [
        KeyframeTrack(
          property: 'position.x',
          keyframes: [
            ScalarKeyframe(
              timeMs: 0,
              value: 100,
              interpolation: Interpolation.cubicBezier,
              bezier: BezierCurve(x1: 0.15, y1: 0.05, x2: 0.7, y2: 0.95),
            ),
            ScalarKeyframe(timeMs: 1000, value: 500),
          ],
        ),
      ],
    );

    final expression = compiler.scalarExpression(
      layer: layer,
      property: 'position.x',
      fallback: 100,
    );

    expect(expression, contains('root('));
    expect(expression, contains('st(9,'));
    expect(expression, contains('ld(9)'));
    expect(expression, contains('500.00000'));
  });
}
