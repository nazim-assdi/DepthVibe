
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/extensions/data/extension_manifest.dart';

void main() {
  Map<String, Object?> validManifest({
    String operation = 'gaussian_blur',
    Object? defaults = const {'sigma': 1.5},
    String? asset,
  }) =>
      <String, Object?>{
        'format': 'DepthVibe.Extension',
        'schemaVersion': 1,
        'id': 'com.example.cinematic',
        'name': 'Cinematic Pack',
        'version': '1.0.0',
        'author': 'Example',
        'description': 'Test package',
        'effects': [
          <String, Object?>{
            'id': 'soft-focus',
            'name': 'Soft Focus',
            'category': 'Creative Looks',
            'description': 'A soft Gaussian blur.',
            'operation': operation,
            'defaults': defaults,
            if (asset != null) 'asset': asset,
          },
        ],
      };

  test('parses a safe renderer operation and bounded defaults', () {
    final manifest =
        DepthVibeExtensionManifest.fromJson(validManifest());
    expect(manifest.id, 'com.example.cinematic');
    expect(manifest.effects.single.operation, 'gaussian_blur');
    expect(manifest.effects.single.defaultOverrides['sigma'], 1.5);
  });

  test('rejects arbitrary or unsupported renderer operations', () {
    expect(
      () => DepthVibeExtensionManifest.fromJson(
        validManifest(operation: 'raw_ffmpeg'),
      ),
      throwsFormatException,
    );
  });

  test('rejects parameter values outside the host schema', () {
    expect(
      () => DepthVibeExtensionManifest.fromJson(
        validManifest(defaults: const {'sigma': 1000}),
      ),
      throwsFormatException,
    );
  });

  test('rejects extension asset traversal paths', () {
    expect(
      () => DepthVibeExtensionManifest.fromJson(
        validManifest(
          operation: 'color_lut',
          defaults: const {},
          asset: 'assets/../outside.cube',
        ),
      ),
      throwsFormatException,
    );
  });

  test('requires a bundled LUT file for color_lut effects', () {
    expect(
      () => DepthVibeExtensionManifest.fromJson(
        validManifest(operation: 'color_lut', defaults: const {}),
      ),
      throwsFormatException,
    );
  });

  test('rejects duplicate effect identifiers', () {
    final manifest = validManifest();
    final first = (manifest['effects'] as List).single as Map<String, Object?>;
    manifest['effects'] = [first, first];
    expect(
      () => DepthVibeExtensionManifest.fromJson(manifest),
      throwsFormatException,
    );
  });
}
