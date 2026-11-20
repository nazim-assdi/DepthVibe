import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/composition/data/motion_bro_pack_service.dart';

void main() {
  group('MotionBroPackService', () {
    late Directory temporaryDirectory;
    late Directory packRoot;
    late MotionBroPackService service;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('depthvibe_mbr_test_');
      packRoot = Directory(
        temporaryDirectory.path + Platform.pathSeparator + 'packs',
      );
      service = MotionBroPackService(rootDirectory: packRoot);
      await service.initialize();
    });

    tearDown(() async {
      service.dispose();
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    Future<File> makePackage({
      String info = '''
packName = Motion Bro Example
author = N Tech // author comment
version = 2.0 // version comment
apps = AE,PP // compatible apps
''',
      Map<String, List<int>>? entries,
    }) async {
      final archive = Archive();
      final infoBytes = utf8.encode(info);
      archive.addFile(ArchiveFile('pack.info', infoBytes.length, infoBytes));
      for (final entry in (entries ?? const <String, List<int>>{
        'Transitions/Zoom.ffx': [1, 2, 3, 4],
        'Transitions/(Preview)/Zoom.mp4': [5, 6, 7],
        'Titles/Title.mogrt': [8, 9, 10],
        '(Assets)/Cover.jpg': [11, 12],
        'Transitions/Apply.jsx': [13, 14],
      }).entries) {
        archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
      }
      final package = File(
        temporaryDirectory.path + Platform.pathSeparator +
            'test_' + DateTime.now().microsecondsSinceEpoch.toString() + '.mbr',
      );
      await package.writeAsBytes(ZipEncoder().encode(archive));
      return package;
    }

    test('imports pack.info, categories, AE/PR assets and cross-extension previews', () async {
      final package = await makePackage();
      final imported = await service.importPackage(package);

      expect(imported.name, 'Motion Bro Example');
      expect(imported.author, 'N Tech');
      expect(imported.version, '2.0');
      expect(imported.apps, containsAll(['AE', 'PP']));
      expect(imported.afterEffectsPresetCount, 1);
      expect(imported.premiereTemplateCount, 1);
      expect(imported.scriptCount, 1);
      expect(
        imported.assets.firstWhere((asset) => asset.fileName == 'Zoom.ffx').previewRelativePath,
        'Transitions/(Preview)/Zoom.mp4',
      );
      expect(
        imported.assets.firstWhere((asset) => asset.fileName == 'Zoom.ffx').category,
        'Transitions',
      );
      expect(await File(
        MotionBroPackService.join(imported.directoryPath, 'pack.info'),
      ).exists(), isTrue);
      expect(service.packs, hasLength(1));
    });

    test('exports an original MBR archive without DepthVibe private metadata', () async {
      final package = await makePackage();
      final imported = await service.importPackage(package);
      final exported = File(
        temporaryDirectory.path + Platform.pathSeparator + 'exported.mbr',
      );

      await service.exportPackage(imported.id, outputFile: exported);
      expect(await exported.exists(), isTrue);

      final bytes = await exported.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final names = archive.files.map((entry) => entry.name).toSet();
      expect(names, contains('pack.info'));
      expect(names, contains('Transitions/Zoom.ffx'));
      expect(names, contains('Transitions/(Preview)/Zoom.mp4'));
      expect(names, contains('Titles/Title.mogrt'));
      expect(names, contains('(Assets)/Cover.jpg'));
      expect(names, contains('Transitions/Apply.jsx'));
      expect(names, isNot(contains(MotionBroPackService.metadataFileName)));

      final secondRoot = Directory(
        temporaryDirectory.path + Platform.pathSeparator + 'reimported',
      );
      final secondService = MotionBroPackService(rootDirectory: secondRoot);
      addTearDown(secondService.dispose);
      await secondService.initialize();
      final restored = await secondService.importPackage(exported);
      expect(restored.name, imported.name);
      expect(restored.assets.length, imported.assets.length);
    });

    test('rejects ZIP path traversal without writing outside the pack directory', () async {
      final package = await makePackage(entries: {
        '../escape.ffx': [1, 2, 3],
      });

      await expectLater(
        service.importPackage(package),
        throwsFormatException,
      );
      expect(service.packs, isEmpty);
      expect(
        await File(temporaryDirectory.path + Platform.pathSeparator + 'escape.ffx').exists(),
        isFalse,
      );
    });

    test('rejects duplicate paths regardless of case', () async {
      final archive = Archive();
      final info = utf8.encode('packName=Duplicate\nversion=1.0\n');
      archive.addFile(ArchiveFile('pack.info', info.length, info));
      archive.addFile(ArchiveFile('Titles/Title.ffx', 1, [1]));
      archive.addFile(ArchiveFile('titles/title.FFX', 1, [2]));
      final package = File(
        temporaryDirectory.path + Platform.pathSeparator + 'duplicate.mbr',
      );
      await package.writeAsBytes(ZipEncoder().encode(archive));

      await expectLater(service.importPackage(package), throwsFormatException);
      expect(service.packs, isEmpty);
    });

    test('replaces an imported pack while preserving the new package contents', () async {
      final first = await makePackage(info: '''
packName=Replace Me
author=Original
version=1.0
apps=AE
''');
      final imported = await service.importPackage(first);
      final second = await makePackage(info: '''
packName=Replace Me
author=Updated
version=2.0
apps=PP
''', entries: {
        'Transitions/New.ffx': [9, 8, 7],
      });

      final replaced = await service.importPackage(second, replaceExisting: true);
      expect(replaced.id, imported.id);
      expect(replaced.author, 'Updated');
      expect(replaced.version, '2.0');
      expect(replaced.apps, ['PP']);
      expect(replaced.assets.map((asset) => asset.fileName), ['New.ffx']);
      expect(service.packs, hasLength(1));
    });
  });
}
