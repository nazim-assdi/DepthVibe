import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/ffmpeg_filter_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compiles an effect stack into FFmpeg filters', () {
    const layer = CompositionLayer(
      id: 'video-1',
      name: 'Footage',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'fx-1',
          effectId: 'gaussian_blur',
          name: 'Gaussian Blur',
          parameters: {'sigma': 5},
        ),
        EffectInstance(
          id: 'fx-2',
          effectId: 'saturation',
          name: 'Saturation',
          parameters: {'value': 1.4},
        ),
      ],
    );
    const compiler = FfmpegFilterCompiler();
    expect(
      compiler.compileEffects(layer, timeMs: 0),
      ['gblur=sigma=5.000', 'hue=s=1.400'],
    );
  });

  test('skips disabled effects', () {
    const layer = CompositionLayer(
      id: 'video-1',
      name: 'Footage',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'fx-1',
          effectId: 'invert',
          name: 'Invert',
          enabled: false,
        ),
      ],
    );
    expect(const FfmpegFilterCompiler().compileEffects(layer, timeMs: 0), isEmpty);
  });
}
