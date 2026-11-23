import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/adjustment_preview_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const compiler = AdjustmentPreviewCompiler();

  test('compiles brightness, contrast and saturation into RGBA matrices', () {
    const effects = [
      EffectInstance(
        id: 'brightness',
        effectId: 'brightness',
        name: 'Brightness',
        parameters: {'value': 0.25},
      ),
      EffectInstance(
        id: 'contrast',
        effectId: 'contrast',
        name: 'Contrast',
        parameters: {'value': 1.5},
      ),
      EffectInstance(
        id: 'saturation',
        effectId: 'saturation',
        name: 'Saturation',
        parameters: {'value': 0},
      ),
    ];

    final operations = effects
        .map((effect) => compiler.compile(effect, 0)!)
        .toList();

    expect(operations, hasLength(3));
    for (final operation in operations) {
      expect(operation.kind, AdjustmentPreviewKind.colorMatrix);
      expect(operation.colorMatrix, hasLength(20));
    }
    expect(operations.first.colorMatrix[4], closeTo(63.75, 0.001));
    expect(operations[1].colorMatrix[0], 1.5);
    expect(operations[2].colorMatrix[0], closeTo(0.2126, 0.0001));
  });

  test('evaluates animated adjustment parameters at the requested playhead', () {
    const effect = EffectInstance(
      id: 'animated-brightness',
      effectId: 'brightness',
      name: 'Animated Brightness',
      parameters: {'value': 0},
      keyframeTracks: [
        KeyframeTrack(
          property: 'value',
          keyframes: [
            ScalarKeyframe(timeMs: 0, value: -0.5),
            ScalarKeyframe(timeMs: 1000, value: 0.5),
          ],
        ),
      ],
    );

    final start = compiler.compile(effect, 0)!;
    final middle = compiler.compile(effect, 500)!;
    final end = compiler.compile(effect, 1000)!;

    expect(start.colorMatrix[4], closeTo(-127.5, 0.001));
    expect(middle.colorMatrix[4], closeTo(0, 0.001));
    expect(end.colorMatrix[4], closeTo(127.5, 0.001));
  });

  test('supports blur, flip, vignette and exposure preview operations', () {
    const effects = [
      EffectInstance(id: 'blur', effectId: 'gaussian_blur', name: 'Blur',
          parameters: {'sigma': 6}),
      EffectInstance(id: 'box', effectId: 'box_blur', name: 'Box',
          parameters: {'radius': 4}),
      EffectInstance(id: 'mirror', effectId: 'mirror', name: 'Mirror'),
      EffectInstance(id: 'flip', effectId: 'flip', name: 'Flip'),
      EffectInstance(id: 'vignette', effectId: 'vignette', name: 'Vignette',
          parameters: {'angle': 1.0}),
      EffectInstance(id: 'exposure', effectId: 'exposure', name: 'Exposure',
          parameters: {'value': 1}),
    ];

    final operations = effects
        .map((effect) => compiler.compile(effect, 0)!)
        .toList();

    expect(operations.map((item) => item.kind), [
      AdjustmentPreviewKind.gaussianBlur,
      AdjustmentPreviewKind.boxBlur,
      AdjustmentPreviewKind.horizontalFlip,
      AdjustmentPreviewKind.verticalFlip,
      AdjustmentPreviewKind.vignette,
      AdjustmentPreviewKind.colorMatrix,
    ]);
    expect(operations.first.amount, 6);
    expect(operations[1].amount, 4);
    expect(operations.last.colorMatrix[0], 2);
  });

  test('returns no preview for disabled or unsupported native effects', () {
    const disabled = EffectInstance(
      id: 'disabled',
      effectId: 'brightness',
      name: 'Disabled',
      enabled: false,
      parameters: {'value': 1},
    );
    const unsupported = EffectInstance(
      id: 'unsupported',
      effectId: 'third_party_glow',
      name: 'Third party glow',
    );

    expect(compiler.compile(disabled, 0), isNull);
    expect(compiler.compile(unsupported, 0), isNull);
  });

  test('keeps alpha unchanged in color matrix operations', () {
    const effect = EffectInstance(
      id: 'invert',
      effectId: 'invert',
      name: 'Invert',
    );
    final operation = compiler.compile(effect, 0)!;

    expect(operation.colorMatrix.sublist(15), [0, 0, 0, 1, 0]);
  });
}
