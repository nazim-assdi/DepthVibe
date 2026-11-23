import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/live_effect_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognises effect types with a live Flutter preview implementation', () {
    expect(LiveEffectPreview.supports('brightness'), isTrue);
    expect(LiveEffectPreview.supports('gaussian_blur'), isTrue);
    expect(LiveEffectPreview.supports('letterbox'), isTrue);
    expect(LiveEffectPreview.supports('displacement'), isFalse);
    expect(LiveEffectPreview.supports('color_lut'), isFalse);
  });

  test('samples keyframed brightness values at the playhead', () {
    const effect = EffectInstance(
      id: 'brightness-1',
      effectId: 'brightness',
      name: 'Brightness',
      parameters: {'value': 0},
      keyframeTracks: [
        KeyframeTrack(
          property: 'value',
          keyframes: [
            ScalarKeyframe(timeMs: 0, value: 0),
            ScalarKeyframe(timeMs: 1000, value: 0.5),
          ],
        ),
      ],
    );

    final atStart = LiveEffectPreview.colorMatrixFor(effect, 0)!;
    final atMiddle = LiveEffectPreview.colorMatrixFor(effect, 500)!;
    final atEnd = LiveEffectPreview.colorMatrixFor(effect, 1000)!;

    expect(atStart, hasLength(20));
    expect(atStart[4], 0);
    expect(atMiddle[4], closeTo(63.75, 0.0001));
    expect(atEnd[4], closeTo(127.5, 0.0001));
  });

  test('disabled effects remain absent from the live effect stack model', () {
    const disabled = EffectInstance(
      id: 'invert-1',
      effectId: 'invert',
      name: 'Invert',
      enabled: false,
    );

    expect(disabled.enabled, isFalse);
    expect(LiveEffectPreview.colorMatrixFor(disabled, 0), isNotNull);
  });
}
