import 'package:depthvibe/features/composition/data/effect_catalog.dart';
import 'package:depthvibe/features/composition/data/motion_preset_catalog.dart';
import 'package:depthvibe/features/composition/data/transition_catalog.dart';
import 'package:depthvibe/features/composition/presentation/transition_preview_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expanded built-in effect ids are unique and renderable', () {
    final ids = EffectCatalog.all.map((effect) => effect.id).toList();
    expect(ids.toSet().length, ids.length);

    const addedEffects = [
      'vibrance',
      'color_contrast',
      'auto_white_balance',
      'rgb_channel_mixer',
      'adaptive_sharpen',
      'median_denoise',
      'temporal_denoise',
      'nlmeans_denoise',
      'frame_blend',
      'wave_distortion',
      'heat_haze',
      'film_gate_weave',
      'camera_flash',
      'letterbox',
      'frame_border',
      'old_film',
      'analog_glitch',
      'bleach_bypass',
      'sepia',
      'edge_glow',
    ];

    for (final id in addedEffects) {
      final effect = EffectCatalog.findBuiltin(id);
      expect(effect, isNotNull, reason: '$id should be registered');
      expect(
        effect!.ffmpegFilter,
        isNotEmpty,
        reason: '$id should declare its native renderer family',
      );
      for (final parameter in effect.parameters) {
        expect(parameter.min, lessThan(parameter.max));
        expect(parameter.defaultValue, inInclusiveRange(parameter.min, parameter.max));
      }
    }
  });

  test('motion preset catalog contains the expanded editable recipes', () {
    final ids = MotionPresetCatalog.all.map((preset) => preset.id).toSet();
    expect(MotionPresetCatalog.all.length, 34);
    expect(ids.length, MotionPresetCatalog.all.length);
    expect(ids, containsAll([
      'fade_slide_up',
      'drop_in',
      'zoom_bounce',
      'overshoot_left',
      'heartbeat',
      'jelly',
    ]));
  });

  testWidgets('transition preview tile applies the selected transition', (tester) async {
    var applied = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransitionPreviewTile(
            kind: TransitionKind.dissolve,
            onApply: () => applied++,
          ),
        ),
      ),
    );

    expect(find.text('Cross Dissolve'), findsOneWidget);
    await tester.tap(find.byTooltip('Apply Cross Dissolve'));
    await tester.pump();
    expect(applied, 1);
  });

  test('every transition kind has a native xfade identifier', () {
    for (final kind in TransitionCatalog.all) {
      expect(TransitionCatalog.xfadeName(kind), isNotEmpty);
    }
    expect(TransitionCatalog.all.length, 61);
  });
}
