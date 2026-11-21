import 'package:depthvibe/features/composition/data/effect_catalog.dart';
import 'package:depthvibe/features/composition/data/effect_preset_catalog.dart';
import 'package:depthvibe/features/composition/data/transition_preset_catalog.dart';
import 'package:depthvibe/features/composition/application/composition_controller.dart';
import 'package:depthvibe/features/composition/data/motion_preset_catalog.dart';
import 'package:depthvibe/features/composition/data/transition_catalog.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/presentation/transition_preview_tile.dart';
import 'package:depthvibe/features/composition/presentation/effect_preview_tile.dart';
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
    expect(MotionPresetCatalog.all.length, 54);
    expect(ids.length, MotionPresetCatalog.all.length);
    expect(ids, containsAll([
      'fade_slide_up',
      'drop_in',
      'zoom_bounce',
      'overshoot_left',
      'heartbeat',
      'jelly',
      'cinematic_push_in',
      'spin_pop_in',
      'lower_third_rise',
      'snap_zoom',
    ]));
  });


  test('original effect looks contain only safe registered native effects', () {
    final ids = EffectPresetCatalog.all.map((preset) => preset.id).toList();
    expect(ids.length, 39);
    expect(ids.toSet().length, ids.length);

    for (final preset in EffectPresetCatalog.all) {
      expect(preset.steps, isNotEmpty, reason: preset.id);
      for (final step in preset.steps) {
        final definition = EffectCatalog.findBuiltin(step.effectId);
        expect(definition, isNotNull, reason: '${preset.id} -> ${step.effectId}');
        for (final entry in step.parameters.entries) {
          final matches = definition!.parameters
              .where((item) => item.id == entry.key)
              .toList();
          expect(matches.length, 1, reason: '${preset.id} -> ${entry.key}');
          final parameter = matches.single;
          expect(entry.value, inInclusiveRange(parameter.min, parameter.max));
        }
      }
    }
  });

  test('effect look applies as an editable multi-effect stack', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        layers: [
          CompositionLayer(id: 'layer-1', name: 'Footage', kind: LayerKind.video),
        ],
        selectedLayerId: 'layer-1',
      ),
    );

    controller.applyEffectPreset('cinema_teal_amber');

    final effects = controller.selectedLayer!.effects;
    expect(effects.length, 3);
    expect(effects.map((effect) => effect.effectId), [
      'color_grade',
      'vibrance',
      'vignette',
    ]);
  });

  test('pro transition recipes map to registered transition kinds', () {
    final ids = TransitionPresetCatalog.all.map((preset) => preset.id).toList();
    expect(ids.length, 38);
    expect(ids.toSet().length, ids.length);
    for (final preset in TransitionPresetCatalog.all) {
      expect(TransitionCatalog.all, contains(preset.kind));
      expect(preset.durationMs, inInclusiveRange(150, 2000));
    }
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

  testWidgets('effect preview tile applies the selected effect', (tester) async {
    var applied = 0;
    final effect = EffectCatalog.findBuiltin('sepia')!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EffectPreviewTile(
            effect: effect,
            onApply: () => applied++,
          ),
        ),
      ),
    );

    expect(find.text('Sepia Tone'), findsOneWidget);
    await tester.tap(find.byTooltip('Add Sepia Tone'));
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
