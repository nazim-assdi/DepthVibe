import 'package:depthvibe/features/composition/data/effect_catalog.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/ffmpeg_filter_compiler.dart';
import 'package:depthvibe/features/composition/engine/ffmpeg_compositing_effect_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {

  test('every built-in effect has a native FFmpeg or compositing render path', () {
    const compiler = FfmpegFilterCompiler();
    const compositeCompiler = FfmpegCompositingEffectCompiler();

    for (final definition in EffectCatalog.all) {
      final parameters = <String, double>{
        for (final parameter in definition.parameters)
          parameter.id: parameter.defaultValue,
      };
      final layer = CompositionLayer(
        id: 'catalog-' + definition.id,
        name: definition.name,
        kind: LayerKind.video,
        effects: [
          EffectInstance(
            id: 'effect-' + definition.id,
            effectId: definition.id,
            name: definition.name,
            parameters: parameters,
            assetUri: definition.id == 'color_lut'
                ? '/tmp/depthvibe-test-identity.cube'
                : null,
          ),
        ],
      );

      final nativeFilters = compiler.compileEffects(layer, timeMs: 0);
      final compositeFilters = <String>[];
      compositeCompiler.compile(
        filters: compositeFilters,
        inputLabel: 'source',
        layer: layer,
        index: 0,
      );

      expect(
        nativeFilters.isNotEmpty || compositeFilters.isNotEmpty,
        isTrue,
        reason: definition.id + ' does not have a render path',
      );
    }
  });

  test('Transform effect compiles animated scale and rotation with transparent edges', () {
    const layer = CompositionLayer(
      id: 'animated-transform',
      name: 'Animated Transform',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'transform-1',
          effectId: 'transform',
          name: 'Transform',
          parameters: {'scale': 100, 'rotation': 0},
          keyframeTracks: [
            KeyframeTrack(
              property: 'scale',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 70),
                ScalarKeyframe(timeMs: 1000, value: 125),
              ],
            ),
            KeyframeTrack(
              property: 'rotation',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: -15),
                ScalarKeyframe(timeMs: 1000, value: 25),
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
    expect(filters.single, contains('format=rgba'));
    expect(filters.single, contains('scale=w='));
    expect(filters.single, contains('eval=frame'));
    expect(filters.single, contains('rotate=angle='));
    expect(filters.single, contains('rotw('));
    expect(filters.single, contains('roth('));
    expect(filters.single, contains('black@0'));
    expect(filters.single, contains('T'));
  });

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
      contains("eq=contrast='1.35000':brightness='0.05000':gamma='1.20000':saturation='1.40000':eval=frame"),
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

  test('renders the expanded native effect library through supported FFmpeg filters', () {
    const compiler = FfmpegFilterCompiler();
    final cases = <String, Map<String, double>>{
      'exposure': {'value': 1.25, 'black': 0},
      'hue_rotate': {'degrees': 45},
      'colorize': {'hue': 210, 'saturation': 0.7, 'lightness': 0, 'mix': 0.5},
      'directional_blur': {'angle': 35, 'radius': 12},
      'average_blur': {'size': 7},
      'chroma_denoise': {'threshold': 0.1, 'window': 3},
      'deband': {'threshold': 0.02, 'range': 16},
      'deflicker': {'size': 9},
      'scanlines': {'spacing': 4, 'thickness': 1, 'opacity': 0.2},
      'rgb_split': {'shift': 5},
      'posterize_time': {'fps': 12},
      'echo_trails': {'frames': 5},
      'vhs_warp': {'shift': 3, 'noise': 18},
      'fisheye': {'strength': 0.3},
      'radial_blur': {'angle': 10, 'radius': 15},
      'noise_reduction': {'luma': 1.5, 'chroma': 2, 'temporal': 3},
    };
    for (final entry in cases.entries) {
      final filters = compiler.compileEffects(
        CompositionLayer(
          id: entry.key,
          name: entry.key,
          kind: LayerKind.video,
          effects: [EffectInstance(
            id: 'fx-' + entry.key,
            effectId: entry.key,
            name: entry.key,
            parameters: entry.value,
          )],
        ),
        timeMs: 0,
      );
      expect(filters, isNotEmpty, reason: entry.key);
      expect(filters.single, isNotEmpty, reason: entry.key);
    }
  });

  test('every built-in transition maps to a native xfade identifier', () {
    const compiler = FfmpegFilterCompiler();
    for (final kind in TransitionKind.values) {
      final filter = compiler.compileTransition(CompositionTransition(
        id: kind.name,
        fromLayerId: 'from',
        toLayerId: 'to',
        kind: kind,
        durationMs: 500,
        startMs: 1000,
      ));
      expect(filter, isNotNull, reason: kind.name);
      expect(filter, contains('xfade=transition='), reason: kind.name);
    }
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

  test('compiles primary curves into a native FFmpeg curves filter', () {
    const layer = CompositionLayer(
      id: 'curve-layer',
      name: 'Curve layer',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'curve-1',
          effectId: 'color_curves',
          name: 'Primary Curves',
          parameters: {
            'master_0': 0,
            'master_1': 0.25,
            'master_2': 0.5,
            'master_3': 0.75,
            'master_4': 1,
            'red_0': 0,
            'red_1': 0.2,
            'red_2': 0.55,
            'red_3': 0.8,
            'red_4': 1,
          },
        ),
      ],
    );

    final filters = const FfmpegFilterCompiler().compileEffects(
      layer,
      timeMs: 0,
    );

    expect(filters, hasLength(1));
    expect(filters.single, startsWith('curves=master='));
    expect(filters.single, contains("r='0.00/0.000 0.25/0.200"));
    expect(filters.single, contains("interp=natural"));
  });

  test('compiles imported 3D cube LUTs using a quoted file path', () {
    const layer = CompositionLayer(
      id: 'lut-layer',
      name: 'LUT layer',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'lut-1',
          effectId: 'color_lut',
          name: '3D LUT',
          assetUri: '/tmp/DepthVibe LUTs/identity.cube',
        ),
      ],
    );

    final filters = const FfmpegFilterCompiler().compileEffects(
      layer,
      timeMs: 0,
    );

    expect(filters, hasLength(1));
    expect(filters.single, contains("lut3d=file='/tmp/DepthVibe LUTs/identity.cube'"));
    expect(filters.single, contains('interp=trilinear'));
  });

  test('compiles animated primary wheel channels into a frame-evaluated geq pass', () {
    const layer = CompositionLayer(
      id: 'animated-wheels',
      name: 'Animated Wheels',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'grade-wheels',
          effectId: 'color_grade',
          name: 'Primary Color Grade',
          parameters: {
            'lift_r': 0,
            'lift_g': 0,
            'lift_b': 0,
            'gamma_r': 0,
            'gamma_g': 0,
            'gamma_b': 0,
            'gain_r': 0,
            'gain_g': 0,
            'gain_b': 0,
            'offset_r': 0,
            'offset_g': 0,
            'offset_b': 0,
          },
          keyframeTracks: [
            KeyframeTrack(
              property: 'lift_r',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 0),
                ScalarKeyframe(timeMs: 1000, value: 0.5),
              ],
            ),
          ],
        ),
      ],
    );

    final filter = const FfmpegFilterCompiler()
        .compileEffects(layer, timeMs: 0)
        .single;

    expect(filter, startsWith('format=rgba,geq='));
    expect(filter, contains("r='clip(r(X,Y)+"));
    expect(filter, contains('if(lt(T,'));
    expect(filter, contains("a='alpha(X,Y)'"));
    expect(filter, contains(':eval=frame'));
  });


  test('compiles the expanded original effects into FFmpeg filter strings', () {
    const compiler=FfmpegFilterCompiler();
    final cases=<String,Map<String,double>>{
      'solarize':{'threshold':174},
      'color_temperature':{'temperature':0.25,'tint':0.04,'intensity':0.8},
      'soft_focus':{'radius':1.8,'brightness':0.04},
      'ripple_warp':{'amount':6,'wavelength':88,'speed':1.2},
      'zoom_warp':{'amount':0.12,'center_x':0.5,'center_y':0.5},
      'color_key':{'similarity':0.3,'blend':0.12},
      'high_pass_sharpen':{'amount':1.4},
      'chroma_smear':{'shift':3.5},
    };
    for(final entry in cases.entries){
      final filters=compiler.compileEffects(CompositionLayer(
        id:entry.key,name:entry.key,kind:LayerKind.video,
        effects:[EffectInstance(id:'fx-'+entry.key,effectId:entry.key,name:entry.key,parameters:entry.value)],
      ),timeMs:0);
      expect(filters,isNotEmpty,reason:entry.key);
    }
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
