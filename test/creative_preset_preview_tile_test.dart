import 'package:depthvibe/features/composition/data/audio_preset_catalog.dart';
import 'package:depthvibe/features/composition/data/motion_preset_catalog.dart';
import 'package:depthvibe/features/composition/presentation/creative_preset_preview_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('motion preset tile previews and applies a keyframe recipe', (tester) async {
    var applied = 0;
    final preset = MotionPresetCatalog.find('snap_zoom')!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CreativePresetPreviewTile(
          title: preset.name,
          category: preset.category,
          description: preset.description,
          kind: CreativePresetPreviewKind.motion,
          motionPreset: preset,
          onApply: () => applied++,
        ),
      ),
    ));

    expect(find.text('Snap Zoom'), findsOneWidget);
    await tester.tap(find.byTooltip('Apply Snap Zoom'));
    await tester.pump();
    expect(applied, 1);
  });

  testWidgets('audio preset tile renders a waveform preview', (tester) async {
    final preset = AudioPresetCatalog.find('voice_clean')!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CreativePresetPreviewTile(
          title: preset.name,
          category: preset.category,
          description: preset.description,
          kind: CreativePresetPreviewKind.audio,
          audioPreset: preset,
          onApply: () {},
        ),
      ),
    ));

    expect(find.text('Clean Voice'), findsOneWidget);
    expect(find.textContaining('GAIN'), findsOneWidget);
  });

  testWidgets('title card shows the actual preset sample text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CreativePresetPreviewTile(
          title: 'Epic Feature Title',
          category: 'Cinematic Titles',
          description: 'Large centred title.',
          kind: CreativePresetPreviewKind.title,
          sampleText: 'THE JOURNEY',
          onApply: () {},
        ),
      ),
    ));

    expect(find.text('Epic Feature Title'), findsOneWidget);
    expect(find.text('THE JOURNEY'), findsOneWidget);
  });
}
