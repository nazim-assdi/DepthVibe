import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/ffmpeg_compositing_effect_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const compiler = FfmpegCompositingEffectCompiler();

  test('compiles animated Glow threshold intensity and blur radius passes', () {
    const layer = CompositionLayer(
      id: 'glow-layer',
      name: 'Neon Sign',
      kind: LayerKind.image,
      effects: [
        EffectInstance(
          id: 'glow-1',
          effectId: 'glow',
          name: 'Glow',
          parameters: {
            'threshold': 0.5,
            'radius': 8,
            'intensity': 1,
          },
          keyframeTracks: [
            KeyframeTrack(
              property: 'threshold',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 0.2),
                ScalarKeyframe(timeMs: 1000, value: 0.8),
              ],
            ),
            KeyframeTrack(
              property: 'radius',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 4),
                ScalarKeyframe(timeMs: 1000, value: 20),
              ],
            ),
            KeyframeTrack(
              property: 'intensity',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 0.5),
                ScalarKeyframe(timeMs: 1000, value: 2),
              ],
            ),
          ],
        ),
      ],
    );
    final filters = <String>[];

    final output = compiler.compile(
      filters: filters,
      inputLabel: 'layerInput',
      layer: layer,
      index: 0,
      timeMs: 0,
    );

    expect(output, 'glowOutput0_0');
    expect(filters.join(';'), contains('geq='));
    expect(filters.join(';'), contains('gblur=sigma=4.000'));
    expect(filters.join(';'), contains('gblur=sigma=20.000'));
    expect(filters.join(';'), contains('blend=all_expr='));
    expect(filters.join(';'), contains('if(lt(T,1.00000)'));
    expect(filters.join(';'), contains('0.80000'));
    expect(filters.join(';'), contains('2.00000'));
    expect(filters.join(';'), contains('pad=w=iw+2*60'));
  });

  test('compiles animated Drop Shadow opacity blur and offset', () {
    const layer = CompositionLayer(
      id: 'shadow-layer',
      name: 'Title',
      kind: LayerKind.text,
      effects: [
        EffectInstance(
          id: 'shadow-1',
          effectId: 'drop_shadow',
          name: 'Drop Shadow',
          parameters: {
            'opacity': 0.6,
            'blur': 8,
            'offset': 8,
          },
          keyframeTracks: [
            KeyframeTrack(
              property: 'opacity',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 0.2),
                ScalarKeyframe(timeMs: 1000, value: 0.9),
              ],
            ),
            KeyframeTrack(
              property: 'blur',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 2),
                ScalarKeyframe(timeMs: 1000, value: 16),
              ],
            ),
            KeyframeTrack(
              property: 'offset',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: -12),
                ScalarKeyframe(timeMs: 1000, value: 24),
              ],
            ),
          ],
        ),
      ],
    );
    final filters = <String>[];

    final output = compiler.compile(
      filters: filters,
      inputLabel: 'titleInput',
      layer: layer,
      index: 2,
      timeMs: 0,
    );

    final graph = filters.join(';');
    expect(output, 'shadowOutput2_0');
    expect(graph, contains("a='alpha(X,Y)*("));
    expect(graph, contains('gblur=sigma=2.000'));
    expect(graph, contains('gblur=sigma=16.000'));
    expect(graph, contains('blend=all_expr='));
    expect(graph, contains('overlay=x='));
    expect(graph, contains(':eval=frame:shortest=1'));
    expect(graph, contains('if(lt(T,1.00000)'));
    expect(graph, contains('0.90000'));
    expect(graph, contains('24.00000'));
  });

  test('keeps non-keyframed Glow and Drop Shadow as simple single-blur passes', () {
    const layer = CompositionLayer(
      id: 'static-layer',
      name: 'Static',
      kind: LayerKind.image,
      effects: [
        EffectInstance(
          id: 'static-glow',
          effectId: 'glow',
          name: 'Glow',
          parameters: {
            'threshold': 0.6,
            'radius': 14,
            'intensity': 1.4,
          },
        ),
      ],
    );
    final filters = <String>[];

    compiler.compile(
      filters: filters,
      inputLabel: 'staticInput',
      layer: layer,
      index: 1,
      timeMs: 500,
    );

    expect(filters.join(';'), contains('gblur=sigma=14.000'));
    expect(filters.join(';'), isNot(contains('blend=all_expr=')));
  });
}
