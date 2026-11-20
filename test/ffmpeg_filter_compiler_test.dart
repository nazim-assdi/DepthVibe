import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/ffmpeg_filter_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports animated brightness as a frame-evaluated FFmpeg expression', () {
    const compiler = FfmpegFilterCompiler();
    const layer = CompositionLayer(
      id: 'clip',
      name: 'Clip',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'brightness-1',
          effectId: 'brightness',
          name: 'Brightness',
          parameters: {'value': 0},
          keyframeTracks: [
            KeyframeTrack(
              property: 'value',
              keyframes: [
                ScalarKeyframe(
                  timeMs: 0,
                  value: -0.25,
                  interpolation: Interpolation.easeInOut,
                ),
                ScalarKeyframe(timeMs: 1000, value: 0.5),
              ],
            ),
          ],
        ),
      ],
    );

    final filters = compiler.compileEffects(layer, timeMs: 0);
    expect(filters, hasLength(1));
    expect(filters.single, contains('eq=brightness='));
    expect(filters.single, contains('eval=frame'));
    expect(filters.single, contains('pow('));
    expect(filters.single, contains('0.50000'));
  });


  test('compiles posterize with an alpha-safe native LUT instead of an optional filter', () {
    const layer = CompositionLayer(
      id: 'posterize-layer',
      name: 'Posterize',
      kind: LayerKind.adjustment,
      effects: [
        EffectInstance(
          id: 'psd-posterize',
          effectId: 'posterize',
          name: 'Photoshop Posterize',
          parameters: {'levels': 6},
        ),
      ],
    );

    final filters = const FfmpegFilterCompiler().compileEffects(
      layer,
      timeMs: 0,
    );

    expect(filters, hasLength(1));
    expect(filters.single, contains('format=rgba,lutrgb='));
    expect(filters.single, contains("round(val*5/255)*255/5"));
    expect(filters.single, contains(':a=val'));
    expect(filters.single, isNot(contains('posterize=')));
  });

  test('compiles threshold adjustment to an alpha-preserving RGB LUT', () {
    const layer = CompositionLayer(
      id: 'threshold-layer',
      name: 'Threshold',
      kind: LayerKind.adjustment,
      effects: [
        EffectInstance(
          id: 'psd-threshold',
          effectId: 'threshold',
          name: 'Photoshop Threshold',
          parameters: {'value': 128},
        ),
      ],
    );

    final filters = const FfmpegFilterCompiler().compileEffects(
      layer,
      timeMs: 0,
    );

    expect(filters, hasLength(1));
    expect(filters.single, contains('format=rgba,lutrgb='));
    expect(filters.single, contains("r='if(gte(val,128.00),255,0)'"));
    expect(filters.single, contains(':a=val'));
  });


  test('compiles primary lift gamma gain and offset wheels into color balance', () {
    const layer = CompositionLayer(
      id: 'graded-clip',
      name: 'Graded Footage',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'grade-1',
          effectId: 'color_grade',
          name: 'Primary Color Grade',
          parameters: {
            'lift_r': 0.2,
            'lift_g': -0.1,
            'lift_b': 0.05,
            'gamma_g': 0.25,
            'gain_b': -0.2,
            'offset_r': 0.1,
            'offset_b': -0.05,
            'temperature': 0.2,
            'tint': 0.1,
            'contrast': 1.35,
            'brightness': 0.05,
            'master_gamma': 1.2,
            'saturation': 1.4,
          },
        ),
      ],
    );

    final filters = const FfmpegFilterCompiler().compileEffects(
      layer,
      timeMs: 0,
    );

    expect(filters, hasLength(1));
    expect(filters.single, startsWith('colorbalance='));
    expect(filters.single, contains('rs=0.355:gs=-0.065:bs=-0.085'));
    expect(filters.single, contains('rm=0.155:gm=0.285:bm=-0.135'));
    expect(filters.single, contains('rh=0.155:gh=0.035:bh=-0.335:pl=1'));
    expect(
      filters.single,
      contains("eq=contrast='1.350':brightness='0.050':gamma='1.200':saturation='1.400':eval=frame"),
    );
  });

  test('exports animated contrast saturation and master gamma as frame expressions', () {
    const layer = CompositionLayer(
      id: 'animated-grade',
      name: 'Animated Grade',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'grade-animated',
          effectId: 'color_grade',
          name: 'Primary Color Grade',
          parameters: {
            'contrast': 1,
            'brightness': 0,
            'master_gamma': 1,
            'saturation': 1,
          },
          keyframeTracks: [
            KeyframeTrack(
              property: 'contrast',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 1),
                ScalarKeyframe(timeMs: 1000, value: 1.8),
              ],
            ),
            KeyframeTrack(
              property: 'saturation',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 1),
                ScalarKeyframe(timeMs: 1000, value: 1.5),
              ],
            ),
          ],
        ),
      ],
    );

    final filter = const FfmpegFilterCompiler()
        .compileEffects(layer, timeMs: 0)
        .single;

    expect(filter, contains("contrast='if(lt(t,"));
    expect(filter, contains("saturation='if(lt(t,"));
    expect(filter, contains(':eval=frame'));
  });

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

  test('compiles animated displacement as a frame-evaluated multi-channel pass', () {
    const layer = CompositionLayer(
      id: 'displace-layer',
      name: 'Displacement',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'displace-1',
          effectId: 'displacement',
          name: 'Displacement',
          parameters: {
            'amount': 12,
            'wavelength': 80,
            'speed': 1,
          },
          keyframeTracks: [
            KeyframeTrack(
              property: 'amount',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 4),
                ScalarKeyframe(timeMs: 1000, value: 24),
              ],
            ),
          ],
        ),
      ],
    );

    final filters = const FfmpegFilterCompiler().compileEffects(
      layer,
      timeMs: 0,
    );

    expect(filters, hasLength(1));
    expect(filters.single, startsWith('format=rgba,geq='));
    expect(filters.single, contains('T'));
    expect(filters.single, contains('r((X+'));
    expect(filters.single, contains('alpha(X,Y)'));
  });

  test('compiles animated particle dust into a transparent-safe VFX pass', () {
    const layer = CompositionLayer(
      id: 'particles-layer',
      name: 'Particle Dust',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'particles-1',
          effectId: 'particle_dust',
          name: 'Particle Dust',
          parameters: {
            'spacing': 72,
            'size': 2,
            'intensity': 0.55,
            'speed': 1,
          },
          keyframeTracks: [
            KeyframeTrack(
              property: 'intensity',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 0.2),
                ScalarKeyframe(timeMs: 1000, value: 0.8),
              ],
            ),
          ],
        ),
      ],
    );

    final filters = const FfmpegFilterCompiler().compileEffects(
      layer,
      timeMs: 0,
    );

    expect(filters, hasLength(1));
    expect(filters.single, startsWith('format=rgba,geq='));
    expect(filters.single, contains('mod('));
    expect(filters.single, contains('T'));
    expect(filters.single, contains("a='alpha(X,Y)'")); 
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
