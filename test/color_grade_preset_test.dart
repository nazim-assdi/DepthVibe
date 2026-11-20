import 'dart:convert';

import 'package:depthvibe/features/composition/application/composition_controller.dart';
import 'package:depthvibe/features/composition/domain/color_grade_preset.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _identityCube = '''
TITLE "Identity"
LUT_3D_SIZE 2
0 0 0
1 0 0
0 1 0
1 1 0
0 0 1
1 0 1
0 1 1
1 1 1
''';

void main() {
  test('round-trips primary wheels, animated curves, LUT and HDR profile', () {
    const layer = CompositionLayer(
      id: 'clip-1',
      name: 'Warm sunset',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'grade-1',
          effectId: 'color_grade',
          name: 'Primary Color Grade',
          parameters: {
            'lift_r': 0.2,
            'contrast': 1.4,
            'saturation': 1.2,
          },
          keyframeTracks: [
            KeyframeTrack(
              property: 'contrast',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 1.0),
                ScalarKeyframe(
                  timeMs: 1200,
                  value: 1.8,
                  interpolation: Interpolation.easeInOut,
                ),
              ],
            ),
          ],
        ),
        EffectInstance(
          id: 'curves-1',
          effectId: 'color_curves',
          name: 'Primary Curves',
          parameters: {
            'master_2': 0.56,
            'red_2': 0.62,
          },
        ),
        EffectInstance(
          id: 'lut-1',
          effectId: 'color_lut',
          name: '3D LUT',
          enabled: false,
          assetUri: '/tmp/LUTs/warm-film.cube',
          assetInterpolation: 'tetrahedral',
        ),
        EffectInstance(
          id: 'blur-1',
          effectId: 'gaussian_blur',
          name: 'Gaussian Blur',
          parameters: {'sigma': 3},
        ),
      ],
    );

    final preset = ColorGradePreset.fromLayer(
      layer,
      outputProfile: ColorOutputProfile.hdr10Pq,
    ).withLutContent(_identityCube);
    final restored = ColorGradePreset.decode(preset.encode());

    expect(restored.name, 'Warm sunset');
    expect(restored.outputProfile, ColorOutputProfile.hdr10Pq);
    expect(restored.primary!.enabled, isTrue);
    expect(restored.primary!.parameters['lift_r'], 0.2);
    expect(restored.primary!.parameters['contrast'], 1.4);
    expect(restored.primary!.keyframeTracks.single.keyframes, hasLength(2));
    expect(
      restored.primary!.keyframeTracks.single.keyframes.last.interpolation,
      Interpolation.easeInOut,
    );
    expect(restored.curves!.parameters['master_2'], 0.56);
    expect(restored.curves!.parameters['red_2'], 0.62);
    expect(restored.lut!.enabled, isFalse);
    expect(restored.lut!.interpolation, 'tetrahedral');
    expect(restored.lut!.fileName, 'warm-film.cube');
    expect(restored.lut!.content, _identityCube);
  });

  test('only color-grade, curves and LUT effects are captured', () {
    const layer = CompositionLayer(
      id: 'clip-1',
      name: 'Clip',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'blur-1',
          effectId: 'gaussian_blur',
          name: 'Gaussian Blur',
          parameters: {'sigma': 4},
        ),
      ],
    );

    final preset = ColorGradePreset.fromLayer(
      layer,
      outputProfile: ColorOutputProfile.rec709,
    );
    expect(preset.primary, isNull);
    expect(preset.curves, isNull);
    expect(preset.lut, isNull);
  });

  test('rejects an unsupported schema version', () {
    final json = ColorGradePreset.fromLayer(
      const CompositionLayer(
        id: 'clip',
        name: 'Clip',
        kind: LayerKind.video,
      ),
      outputProfile: ColorOutputProfile.rec709,
    ).toJson();
    json['version'] = 99;

    expect(
      () => ColorGradePreset.decode(jsonEncode(json)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unknown primary parameters', () {
    final json = ColorGradePreset.fromLayer(
      const CompositionLayer(
        id: 'clip',
        name: 'Clip',
        kind: LayerKind.video,
        effects: [
          EffectInstance(
            id: 'grade',
            effectId: 'color_grade',
            name: 'Grade',
            parameters: {'contrast': 1.2},
          ),
        ],
      ),
      outputProfile: ColorOutputProfile.rec709,
    ).toJson();
    (json['primary'] as Map<String, Object?>)['injected_filter'] = 1;

    expect(
      () => ColorGradePreset.decode(jsonEncode(json)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects out-of-range curve samples and invalid LUT interpolation', () {
    final base = ColorGradePreset.fromLayer(
      const CompositionLayer(
        id: 'clip',
        name: 'Clip',
        kind: LayerKind.video,
        effects: [
          EffectInstance(
            id: 'curves',
            effectId: 'color_curves',
            name: 'Curves',
            parameters: {'red_2': 0.5},
          ),
          EffectInstance(
            id: 'lut',
            effectId: 'color_lut',
            name: 'LUT',
            assetInterpolation: 'trilinear',
          ),
        ],
      ),
      outputProfile: ColorOutputProfile.rec709,
    );

    final badCurve = base.toJson();
    (badCurve['curves'] as Map<String, Object?>)['parameters'] = {
      'red_2': 1.5,
    };
    expect(
      () => ColorGradePreset.decode(jsonEncode(badCurve)),
      throwsA(isA<FormatException>()),
    );

    final badLut = base.toJson();
    (badLut['lut'] as Map<String, Object?>)['interpolation'] = 'unknown';
    expect(
      () => ColorGradePreset.decode(jsonEncode(badLut)),
      throwsA(isA<FormatException>()),
    );
  });

  test('applies imported settings to the selected layer without deleting other effects', () {
    const layer = CompositionLayer(
      id: 'clip-1',
      name: 'Clip',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'old-grade',
          effectId: 'color_grade',
          name: 'Old grade',
          parameters: {'contrast': 0.8},
        ),
        EffectInstance(
          id: 'keep-blur',
          effectId: 'gaussian_blur',
          name: 'Gaussian Blur',
          parameters: {'sigma': 5},
        ),
      ],
    );
    final controller = CompositionController(
      document: CompositionDocument(
        layers: const [layer],
        selectedLayerId: layer.id,
      ),
    );
    final preset = ColorGradePreset.fromLayer(
      const CompositionLayer(
        id: 'preset-source',
        name: 'Golden',
        kind: LayerKind.video,
        effects: [
          EffectInstance(
            id: 'new-grade',
            effectId: 'color_grade',
            name: 'Primary Color Grade',
            parameters: {'contrast': 1.7},
          ),
        ],
      ),
      outputProfile: ColorOutputProfile.hlg,
    );

    controller.applyColorGradePreset(
      preset,
      lutAssetUri: null,
    );

    final applied = controller.selectedLayer!;
    expect(
      applied.effects.where((effect) => effect.effectId == 'color_grade'),
      hasLength(1),
    );
    expect(
      applied.effects.firstWhere(
        (effect) => effect.effectId == 'color_grade',
      ).parameters['contrast'],
      1.7,
    );
    expect(
      applied.effects.any((effect) => effect.id == 'keep-blur'),
      isTrue,
    );
    expect(controller.document.colorOutputProfile, ColorOutputProfile.hlg);
  });
}
