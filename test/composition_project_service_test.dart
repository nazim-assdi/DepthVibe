import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/composition_project_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  const service = CompositionProjectService();

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('depthvibe_project_test_');
  });
  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('exports and restores media and LUT assets as a portable ZIP project', () async {
    final sourceDirectory = Directory(temporary.path + '/source')
      ..createSync(recursive: true);
    final video = File(sourceDirectory.path + '/camera.mp4')
      ..writeAsBytesSync([1, 2, 3, 4, 5]);
    final lut = File(sourceDirectory.path + '/warm.cube')
      ..writeAsStringSync(
        'TITLE "Test"\nLUT_3D_SIZE 2\n'
        '0 0 0\n1 0 0\n0 1 0\n1 1 0\n'
        '0 0 1\n1 0 1\n0 1 1\n1 1 1\n',
      );

    final document = CompositionDocument(
      name: 'Portable Test',
      colorOutputProfile: ColorOutputProfile.hlg,
      layers: [
        CompositionLayer(
          id: 'video_1',
          name: 'Camera',
          kind: LayerKind.video,
          sourceUri: video.path,
          effects: [
            EffectInstance(
              id: 'lut_1',
              effectId: 'color_lut',
              name: 'Warm LUT',
              assetUri: lut.path,
              assetInterpolation: 'prism',
            ),
          ],
        ),
      ],
    );
    final archiveFile = File(temporary.path + '/portable.dvproj');
    final exported = await service.exportProject(
      document,
      outputFile: archiveFile,
    );
    expect(exported.embeddedAssetCount, 2);
    expect(exported.missingAssetPaths, isEmpty);
    expect(await archiveFile.exists(), isTrue);

    final imported = await service.importProject(
      archiveFile,
      projectsDirectory: Directory(temporary.path + '/projects'),
    );
    expect(imported.extractedAssetCount, 2);
    expect(imported.document.colorOutputProfile, ColorOutputProfile.hlg);
    final restoredVideo = imported.document.layers.single;
    expect(restoredVideo.sourceUri, isNot(video.path));
    expect(await File(restoredVideo.sourceUri!).readAsBytes(), [1, 2, 3, 4, 5]);
    final restoredLut = restoredVideo.effects.single;
    expect(restoredLut.assetInterpolation, 'prism');
    expect(
      await File(restoredLut.assetUri!).readAsString(),
      contains('LUT_3D_SIZE 2'),
    );
  });

  test('rejects archives containing parent-directory traversal entries', () async {
    final archivePath = temporary.path + '/unsafe.dvproj';
    final encoder = ZipFileEncoder()..create(archivePath);
    final payload = File(temporary.path + '/payload.txt')
      ..writeAsStringSync('unsafe');
    await encoder.addFile(payload, '../outside.txt');
    await encoder.close();

    await expectLater(
      service.importProject(
        File(archivePath),
        projectsDirectory: Directory(temporary.path + '/projects'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await File(temporary.path + '/outside.txt').exists(), isFalse);
  });

  test('reports missing linked media and retains its external reference', () async {
    const document = CompositionDocument(
      layers: [
        CompositionLayer(
          id: 'offline',
          name: 'Offline media',
          kind: LayerKind.video,
          sourceUri: '/missing/source.mp4',
        ),
      ],
    );
    final output = File(temporary.path + '/offline.dvproj');
    final exported = await service.exportProject(document, outputFile: output);
    expect(exported.missingAssetPaths, ['/missing/source.mp4']);

    final imported = await service.importProject(
      output,
      projectsDirectory: Directory(temporary.path + '/projects'),
    );
    expect(imported.document.layers.single.sourceUri, '/missing/source.mp4');
  });
}
