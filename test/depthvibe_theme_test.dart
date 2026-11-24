import 'package:depthvibe/app/depthvibe_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DepthVibe appearance presets', () {
    test('Dark preset uses a low-luminance studio palette', () {
      final theme = DepthVibeTheme.build(
        appearance: DepthVibeAppearance.dark,
        fontFallback: const [],
      );
      final palette = DepthVibeTheme.paletteFor(DepthVibeAppearance.dark);

      expect(theme.brightness, Brightness.dark);
      expect(palette.appBackground, const Color(0xFF090D14));
      expect(palette.primaryText, const Color(0xFFF0F4FB));
    });

    test('White preset uses a bright neutral workspace palette', () {
      final theme = DepthVibeTheme.build(
        appearance: DepthVibeAppearance.light,
        fontFallback: const [],
      );
      final palette = DepthVibeTheme.paletteFor(DepthVibeAppearance.light);

      expect(theme.brightness, Brightness.light);
      expect(palette.appBackground, const Color(0xFFF0F3F8));
      expect(palette.panelRaised, const Color(0xFFFFFFFF));
    });

    test('Eye Comfort preset uses warm paper-like surfaces', () {
      final theme = DepthVibeTheme.build(
        appearance: DepthVibeAppearance.eyeComfort,
        fontFallback: const [],
      );
      final palette =
          DepthVibeTheme.paletteFor(DepthVibeAppearance.eyeComfort);

      expect(theme.brightness, Brightness.light);
      expect(palette.appBackground, const Color(0xFFF0EADB));
      expect(palette.panelRaised, const Color(0xFFFFF9EB));
    });

    test('All presets keep the global font and fallback chain', () {
      final theme = DepthVibeTheme.build(
        appearance: DepthVibeAppearance.dark,
        fontFamily: 'DepthVibeImportedSans',
        fontFallback: const ['Noto Sans Bengali', 'Noto Naskh Arabic'],
      );

      expect(theme.textTheme.bodyMedium?.fontFamily, 'DepthVibeImportedSans');
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        ['Noto Sans Bengali', 'Noto Naskh Arabic'],
      );
    });
  });
}
