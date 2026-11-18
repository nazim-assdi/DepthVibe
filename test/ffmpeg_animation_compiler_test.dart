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
            ScalarKeyframe(timeMs: 0, value: 100),
            ScalarKeyframe(
              timeMs: 1000,
              value: 500,
              interpolation: Interpolation.easeInOut,
            ),
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
        operation: MaskOperation.difference,
        vertices: [
          MaskVertex(anchor: Vector2(0.2, 0.2)),
          MaskVertex(anchor: Vector2(0.8, 0.2)),
          MaskVertex(anchor: Vector2(0.5, 0.8)),
        ],
      ),
    ]);

    expect(expression, contains('sqrt('));
    expect(expression, contains('mod('));
    expect(expression, contains('abs('));
    expect(expression, contains('min(1,max(0,'));
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
}
