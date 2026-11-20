
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/composition/data/effect_catalog.dart';
import '../lib/features/extensions/data/extension_manager_service.dart';

void main() {
  group('ExtensionManagerService', () {
    late Directory temporaryDirectory;
    late Directory extensionRoot;
    late ExtensionManagerService manager;

    setUp(() async {
      temporaryDirectory =
          await Directory.systemTemp.createTemp('depthvibe_extensions_test_');
      extensionRoot = Directory(
        temporaryDirectory.path +
            Platform.pathSeparator +
            'Extensions',
      );
      manager = ExtensionManagerService(rootDirectory: extensionRoot);
      await manager.initialize();
    });

    tearDown(() async {
      manager.dispose();
      EffectCatalog.setExtensionEffects(const []);
      await temporaryDirectory.delete(recursive: true);
    });

    test('installs, enables, disables and uninstalls a declarative package',
        () async {
      final manifest = <String, Object?>{
        'format': 'DepthVibe.Extension',
        'schemaVersion': 1,
        'id': 'com.example.test-pack',
        'name': 'Test Pack',
        'version': '1.0.0',
        'author': 'Test',
        'description': 'A test extension.',
        'effects': [
          {
            'id': 'warm-film',
            'name': 'Warm Film',
            'category': 'Looks',
            'description': 'Warm color balance.',
            'operation': 'color_balance',
            'defaults': {'red': 0.1},
          },
          {
            'id': 'warm-lut',
            'name': 'Warm LUT',
            'category': 'Looks',
            'description': 'Bundled warm 3D LUT.',
            'operation': 'color_lut',
            'defaults': {},
            'asset': 'assets/warm.cube',
          },
        ],
      };
      final manifestBytes = utf8.encode(jsonEncode(manifest));
      const lutContents = '''
LUT_3D_SIZE 2
0 0 0
0 0 1
0 1 0
0 1 1
1 0 0
1 0 1
1 1 0
1 1 1
''';
      final lutBytes = utf8.encode(lutContents);
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'manifest.json',
            manifestBytes.length,
            manifestBytes,
          ),
        )
        ..addFile(
          ArchiveFile(
            'assets/warm.cube',
            lutBytes.length,
            lutBytes,
          ),
        );
      final bytes = ZipEncoder().encode(archive);
      final package = File(
        temporaryDirectory.path +
            Platform.pathSeparator +
            'test.dvext',
      );
      await package.writeAsBytes(bytes);

      final installed = await manager.installFromFile(package);
      const effectId = 'extension.com.example.test-pack.warm-film';
      expect(installed.enabled, isTrue);
      expect(manager.installed.single.manifest.id, 'com.example.test-pack');
      expect(EffectCatalog.find(effectId), isNotNull);
      final lutDefinition = EffectCatalog.find(
        'extension.com.example.test-pack.warm-lut',
      );
      expect(lutDefinition, isNotNull);
      expect(await File(lutDefinition!.assetUri!).exists(), isTrue);

      await manager.setEnabled('com.example.test-pack', false);
      expect(EffectCatalog.find(effectId), isNull);
      expect(
        EffectCatalog.find('extension.com.example.test-pack.warm-lut'),
        isNull,
      );
      expect(manager.installed.single.enabled, isFalse);

      await manager.setEnabled('com.example.test-pack', true);
      expect(EffectCatalog.find(effectId), isNotNull);

      await manager.uninstall('com.example.test-pack');
      expect(manager.installed, isEmpty);
      expect(EffectCatalog.find(effectId), isNull);
    });

    test('rejects a package with an unsupported file', () async {
      final manifestBytes = utf8.encode(jsonEncode({
        'format': 'DepthVibe.Extension',
        'schemaVersion': 1,
        'id': 'com.example.invalid',
        'name': 'Invalid Pack',
        'version': '1.0.0',
        'effects': [
          {
            'id': 'blur',
            'name': 'Blur',
            'operation': 'gaussian_blur',
            'defaults': {'sigma': 2},
          },
        ],
      }));
      final archive = Archive()
        ..addFile(ArchiveFile(
          'manifest.json',
          manifestBytes.length,
          manifestBytes,
        ))
        ..addFile(ArchiveFile('payload.bin', 4, [1, 2, 3, 4]));
      final package = File(
        temporaryDirectory.path +
            Platform.pathSeparator +
            'bad.dvext',
      );
      await package.writeAsBytes(ZipEncoder().encode(archive));

      await expectLater(
        manager.installFromFile(package),
        throwsFormatException,
      );
      expect(manager.installed, isEmpty);
    });
  });
}
