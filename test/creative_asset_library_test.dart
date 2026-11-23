import 'package:depthvibe/features/composition/data/audio_preset_catalog.dart';
import 'package:depthvibe/features/composition/data/color_preset_catalog.dart';
import 'package:depthvibe/features/composition/data/effect_catalog.dart';
import 'package:depthvibe/features/composition/data/motion_preset_catalog.dart';
import 'package:depthvibe/features/composition/data/overlay_sticker_catalog.dart';
import 'package:depthvibe/features/composition/data/open_asset_source_catalog.dart';
import 'package:depthvibe/features/composition/data/title_preset_catalog.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overlay and sticker catalogue entries resolve to native effects or text', () {
    expect(OverlayStickerCatalog.all.length, 72);
    final ids = OverlayStickerCatalog.all.map((item) => item.id).toSet();
    expect(ids.length, OverlayStickerCatalog.all.length);

    for (final asset in OverlayStickerCatalog.all) {
      expect(asset.name.trim(), isNotEmpty);
      expect(asset.description.trim(), isNotEmpty);
      expect(MotionPresetCatalog.find(asset.motionPresetId), isNotNull,
          reason: asset.id);
      if (asset.effectId != null) {
        expect(EffectCatalog.findBuiltin(asset.effectId!), isNotNull,
            reason: asset.id);
      } else {
        expect(asset.textContent.trim(), isNotEmpty, reason: asset.id);
      }
    }
  });

  test('audio preset values stay within the native track EQ and gain limits', () {
    expect(AudioPresetCatalog.all.length, 41);
    final ids = AudioPresetCatalog.all.map((item) => item.id).toSet();
    expect(ids.length, AudioPresetCatalog.all.length);

    for (final preset in AudioPresetCatalog.all) {
      expect(preset.gainDb, inInclusiveRange(-24, 24), reason: preset.id);
      expect(preset.lowEqDb, inInclusiveRange(-18, 18), reason: preset.id);
      expect(preset.midEqDb, inInclusiveRange(-18, 18), reason: preset.id);
      expect(preset.highEqDb, inInclusiveRange(-18, 18), reason: preset.id);
      expect(preset.pan, inInclusiveRange(-1, 1), reason: preset.id);
      final applied = preset.applyTo(const AudioSettings());
      expect(applied.gainDb, preset.gainDb);
      expect(applied.lowEqDb, preset.lowEqDb);
      expect(applied.fadeInMs, preset.fadeInMs);
      expect(applied.fadeOutMs, preset.fadeOutMs);
    }
  });

  test('title and lower-third recipes reference installed motion tracks', () {
    expect(TitlePresetCatalog.all.length, 51);
    final ids = TitlePresetCatalog.all.map((item) => item.id).toSet();
    expect(ids.length, TitlePresetCatalog.all.length);

    for (final preset in TitlePresetCatalog.all) {
      expect(preset.sampleText.trim(), isNotEmpty, reason: preset.id);
      expect(preset.fontSize, inInclusiveRange(1, 2000), reason: preset.id);
      expect(preset.fontWeight, inInclusiveRange(100, 900), reason: preset.id);
      expect(preset.textColor, matches(RegExp(r'^#[0-9A-Fa-f]{8}$')),
          reason: preset.id);
      expect(MotionPresetCatalog.find(preset.motionPresetId), isNotNull,
          reason: preset.id);
    }
  });

  test('online asset directory only exposes HTTPS sources with licence labels', () {
    expect(OpenAssetSourceCatalog.all.length, 9);
    final ids = OpenAssetSourceCatalog.all.map((item) => item.id).toSet();
    expect(ids.length, OpenAssetSourceCatalog.all.length);
    for (final source in OpenAssetSourceCatalog.all) {
      expect(Uri.parse(source.url).scheme, 'https', reason: source.id);
      expect(source.licenseLabel.trim(), isNotEmpty, reason: source.id);
      expect(source.category.trim(), isNotEmpty, reason: source.id);
    }
  });

  test('color look parameters match the native color-grade schema', () {
    expect(ColorPresetCatalog.all.length, 48);
    final ids = ColorPresetCatalog.all.map((item) => item.id).toSet();
    expect(ids.length, ColorPresetCatalog.all.length);
    final definition = EffectCatalog.findBuiltin('color_grade')!;
    for (final preset in ColorPresetCatalog.all) {
      for (final entry in preset.parameters.entries) {
        final matches = definition.parameters
            .where((parameter) => parameter.id == entry.key)
            .toList();
        expect(matches, hasLength(1), reason: preset.id);
        expect(entry.value,
            inInclusiveRange(matches.single.min, matches.single.max),
            reason: '${preset.id} / ${entry.key}');
      }
    }
  });
}
