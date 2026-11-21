import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/composition/data/creative_asset_pack_catalog.dart';
import '../lib/features/composition/data/creative_asset_pack_service.dart';

void main() {
  group('Creative asset pack catalogue', () {
    test('contains all individually licensed DAEDAL packs and both CLR volumes', () {
      expect(CreativeAssetPackCatalog.all, hasLength(26));
      final ids = CreativeAssetPackCatalog.all.map((item) => item.id).toSet();
      expect(ids, hasLength(CreativeAssetPackCatalog.all.length));
      for (final pack in CreativeAssetPackCatalog.all) {
        expect(Uri.parse(pack.downloadUrl).scheme, 'https', reason: pack.id);
        expect(Uri.parse(pack.sourceUrl).scheme, 'https', reason: pack.id);
        expect(pack.licenseLabel, isNotEmpty, reason: pack.id);
        expect(pack.estimatedBytes, greaterThan(0), reason: pack.id);
      }
      final clr = CreativeAssetPackCatalog.all
          .where((item) => item.id.startsWith('clr_audio_'))
          .toList();
      expect(clr, hasLength(2));
      expect(clr.fold<int>(0, (sum, item) => sum + item.exactBytes!), 3359833518);
      expect(
        CreativeAssetPackCatalog.all
            .where((item) => item.id.startsWith('daedal_'))
            .every((item) => item.licenseLabel == 'CC0 1.0'),
        isTrue,
      );
    });

    test('total estimate is over five gigabytes and includes all 26 packs', () {
      expect(CreativeAssetPackCatalog.totalEstimatedBytes, greaterThan(5 * 1024 * 1024 * 1024));
      expect(CreativeAssetPackCatalog.totalEstimatedBytes, lessThan(6 * 1024 * 1024 * 1024));
    });
  });

  group('CreativeAssetPackService', () {
    late Directory temporaryDirectory;
    late CreativeAssetPackService service;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('depthvibe_assets_');
      service = CreativeAssetPackService(
        rootDirectory: Directory(
          temporaryDirectory.path + Platform.pathSeparator + 'packs',
        ),
      );
      await service.initialize();
    });

    tearDown(() async {
      service.dispose();
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    Future<File> createZip({
      Map<String, List<int>> entries = const {
        'LICENSE.txt': [67, 67, 48],
        'README.txt': [65, 115, 115, 101, 116, 32, 112, 97, 99, 107],
        'Stickers/demo.svg': [60, 115, 118, 103, 47, 62],
      },
    }) async {
      final archive = Archive();
      for (final item in entries.entries) {
        archive.addFile(ArchiveFile(item.key, item.value.length, item.value));
      }
      final file = File(
        temporaryDirectory.path + Platform.pathSeparator +
            'pack_' + DateTime.now().microsecondsSinceEpoch.toString() + '.zip',
      );
      await file.writeAsBytes(ZipEncoder().encode(archive));
      return file;
    }

    test('imports an offline ZIP, preserves licence files, and indexes media', () async {
      final zip = await createZip();
      final installed = await service.importArchive(
        zip,
        name: 'Test CC0 Pack',
        licenseLabel: 'CC0 1.0',
        sourceUrl: 'https://example.org/assets',
      );
      expect(installed.name, 'Test CC0 Pack');
      expect(installed.fileCount, 3);
      expect(service.installed, hasLength(1));

      final license = File(
        installed.directoryPath + Platform.pathSeparator +
            'files' + Platform.pathSeparator + 'LICENSE.txt',
      );
      expect(await license.exists(), isTrue);
      final indexed = await service.filesForPack(installed.id);
      expect(indexed, hasLength(1));
      expect(indexed.single.kind, 'image');
      expect(indexed.single.name, 'demo.svg');
    });

    test('rejects ZIP packs without an included licence file', () async {
      final zip = await createZip(entries: {
        'Stickers/demo.svg': [60, 115, 118, 103, 47, 62],
      });
      await expectLater(
        service.importArchive(
          zip,
          name: 'No Licence',
          licenseLabel: 'Unknown',
        ),
        throwsFormatException,
      );
      expect(service.installed, isEmpty);
    });

    test('rejects ZIP traversal and never writes outside the pack root', () async {
      final zip = await createZip(entries: {
        'LICENSE.txt': [67, 67, 48],
        '../escaped.txt': [1, 2, 3],
      });
      await expectLater(
        service.importArchive(
          zip,
          name: 'Traversal Attempt',
          licenseLabel: 'CC0 1.0',
        ),
        throwsFormatException,
      );
      expect(
        await File(temporaryDirectory.path + Platform.pathSeparator + 'escaped.txt').exists(),
        isFalse,
      );
      expect(service.installed, isEmpty);
    });

    test('restores installed packs after reinitializing the service', () async {
      final zip = await createZip();
      final installed = await service.importArchive(
        zip,
        name: 'Persistent Pack',
        licenseLabel: 'CC0 1.0',
      );
      final second = CreativeAssetPackService(
        rootDirectory: Directory(
          temporaryDirectory.path + Platform.pathSeparator + 'packs',
        ),
      );
      addTearDown(second.dispose);
      await second.initialize();
      expect(second.installed, hasLength(1));
      expect(second.installed.single.id, installed.id);
    });
  });
}
