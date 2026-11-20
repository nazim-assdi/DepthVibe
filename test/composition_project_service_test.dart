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

  test('embeds selected text fonts and preserves multilingual typography settings', () async {
    final fontBytes = <int>[0x4F, 0x54, 0x54, 0x4F, 1, 2, 3, 4, 5, 6];
    final font = File(temporary.path + '/NotoSansBengali.otf')
      ..writeAsBytesSync(fontBytes);
    final document = CompositionDocument(
      name: 'Typography project',
      layers: [
        CompositionLayer(
          id: 'text_1',
          name: 'Multilingual title',
          kind: LayerKind.text,
          textContent: 'বাংলা العربية English हिन्दी 中文 日本語',
          textFontFamily: 'DV_NotoSansBengali',
          textFontAssetUri: font.path,
          textFontFallback: const ['Noto Naskh Arabic', 'Noto Sans CJK SC'],
          textFontSize: 104,
          textFontWeight: 600,
          textItalic: true,
          textColor: '#FF42A5F5',
          textLetterSpacing: 1.25,
          textLineHeight: 1.35,
          textAlign: 'center',
          textBoxWidth: 1600,
        ),
      ],
    );
    final archiveFile = File(temporary.path + '/typography.dvproj');
    final exported = await service.exportProject(document, outputFile: archiveFile);
    expect(exported.embeddedAssetCount, 1);
    expect(exported.missingAssetPaths, isEmpty);

    final imported = await service.importProject(
      archiveFile,
      projectsDirectory: Directory(temporary.path + '/restored'),
    );
    expect(imported.extractedAssetCount, 1);
    final text = imported.document.layers.single;
    expect(text.textContent, 'বাংলা العربية English हिन्दी 中文 日本語');
    expect(text.textFontFamily, 'DV_NotoSansBengali');
    expect(text.textFontFallback, ['Noto Naskh Arabic', 'Noto Sans CJK SC']);
    expect(text.textFontSize, 104);
    expect(text.textFontWeight, 600);
    expect(text.textItalic, isTrue);
    expect(text.textColor, '#FF42A5F5');
    expect(text.textLetterSpacing, 1.25);
    expect(text.textLineHeight, 1.35);
    expect(text.textAlign, 'center');
    expect(text.textBoxWidth, 1600);
    expect(text.textFontAssetUri, isNot(font.path));
    expect(await File(text.textFontAssetUri!).readAsBytes(), fontBytes);
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

  test('keeps project save versions and restores an earlier package', () async {
    final output = File(temporary.path + '/history.dvproj');
    const first = CompositionDocument(
      name: 'Version One',
      layers: [
        CompositionLayer(id: 'layer_1', name: 'First', kind: LayerKind.video),
      ],
    );
    const second = CompositionDocument(
      name: 'Version Two',
      layers: [
        CompositionLayer(id: 'layer_1', name: 'Second', kind: LayerKind.video),
      ],
    );

    await service.exportVersionedProject(first, outputFile: output);
    await service.exportVersionedProject(second, outputFile: output);

    final versions = await service.listProjectVersions(output);
    expect(versions, hasLength(1));
    final restored = await service.importProject(
      versions.single.file,
      projectsDirectory: Directory(temporary.path + '/history_restore'),
    );
    expect(restored.document.name, 'Version One');
  });

  test('retains only the newest ten project history snapshots', () async {
    final output = File(temporary.path + '/retention.dvproj');
    for (var index = 0; index < 12; index++) {
      await service.exportVersionedProject(
        CompositionDocument(name: 'Version ' + index.toString()),
        outputFile: output,
      );
    }
    final versions = await service.listProjectVersions(output);
    expect(versions, hasLength(10));
  });

  test('failed project export does not replace the last valid package', () async {
    final output = File(temporary.path + '/atomic.dvproj');
    await service.exportProject(
      const CompositionDocument(name: 'Last valid package'),
      outputFile: output,
    );
    final originalBytes = await output.readAsBytes();

    const invalid = CompositionDocument(
      name: 'Invalid replacement',
      layers: [
        CompositionLayer(
          id: 'layer_1',
          name: 'Invalid effect',
          kind: LayerKind.video,
          effects: [
            EffectInstance(
              id: 'effect_1',
              effectId: 'color_grade',
              name: 'Grade',
              parameters: {'contrast': double.infinity},
            ),
          ],
        ),
      ],
    );
    await expectLater(
      service.exportProject(invalid, outputFile: output),
      throwsA(isA<FormatException>()),
    );
    expect(await output.readAsBytes(), originalBytes);
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
