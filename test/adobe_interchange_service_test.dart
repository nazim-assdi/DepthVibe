import 'package:flutter_test/flutter_test.dart';

import 'package:depthvibe/features/composition/data/effect_catalog.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/composition_project_codec.dart';
import 'package:depthvibe/features/extensions/data/adobe_interchange_service.dart';

void main() {
  group('Adobe interchange', () {
    test('Premiere clips become editable video and audio timeline layers', () {
      final report = AdobeInterchangeService.importSnapshot({
        'schemaVersion': 1,
        'hostApp': 'premierepro',
        'payload': {
          'sequence': {
            'name': 'Trailer',
            'width': 1920,
            'height': 1080,
            'timebase': '10594584000',
            'durationSeconds': 12,
          },
          'videoTracks': [
            {
              'index': 0,
              'id': 'V1',
              'name': 'V1',
              'clips': [
                {
                  'id': 'clip-a',
                  'name': 'Opening',
                  'sourceName': 'opening.mp4',
                  'sourcePath': r'C:\Media\opening.mp4',
                  'startSeconds': 1.5,
                  'endSeconds': 5.5,
                  'durationSeconds': 4,
                  'sourceInSeconds': 2,
                  'speed': 1,
                  'mediaType': 'video',
                  'effects': [
                    {
                      'matchName': 'ADBE Gaussian Blur 2',
                      'name': 'Gaussian Blur',
                      'properties': [
                        {'name': 'Blurriness', 'value': 6},
                      ],
                    },
                    {'matchName': 'Vendor.SuperGlow', 'name': 'Super Glow'},
                  ],
                },
              ],
            },
          ],
          'audioTracks': [
            {
              'index': 0,
              'id': 'A1',
              'muted': false,
              'clips': [
                {
                  'id': 'audio-a',
                  'name': 'Music',
                  'startSeconds': 0,
                  'durationSeconds': 10,
                  'sourceInSeconds': 0.5,
                  'mediaType': 'audio',
                },
              ],
            },
          ],
        },
      });

      expect(report.document.name, 'Trailer');
      expect(report.document.width, 1920);
      expect(report.document.layers, hasLength(2));
      final video = report.document.layers.first;
      expect(video.kind, LayerKind.video);
      expect(video.startMs, 1500);
      expect(video.durationMs, 4000);
      expect(video.sourceInMs, 2000);
      expect(video.sourceUri, r'C:\Media\opening.mp4');
      expect(video.effects.single.effectId, 'gaussian_blur');
      expect(video.effects.single.parameters['sigma'], 6);
      expect(report.mappedEffects, hasLength(1));
      expect(report.unsupportedEffects, contains('premierepro: Vendor.SuperGlow'));
      expect(report.document.layers.last.kind, LayerKind.audio);
    });

    test('After Effects layers retain transform, parent, source and effect metadata', () {
      final report = AdobeInterchangeService.importSnapshot({
        'schemaVersion': 1,
        'hostApp': 'aftereffects-beta',
        'payload': {
          'composition': {
            'name': 'Logo Animation',
            'width': 1080,
            'height': 1080,
            'durationSeconds': 8,
            'frameRate': 30,
          },
          'layers': [
            {
              'id': '2',
              'index': 1,
              'name': 'Logo',
              'matchName': 'ADBE AV Layer',
              'startTimeSeconds': 0,
              'inPointSeconds': 1,
              'outPointSeconds': 6,
              'enabled': true,
              'hasVideo': true,
              'hasAudio': false,
              'sourcePath': r'D:\Assets\logo.png',
              'source': {'name': 'logo.png', 'width': 400, 'height': 200},
              'transform': {
                'position': [500, 400, 0],
                'anchorPoint': [200, 100, 0],
                'scale': [80, 80, 100],
                'rotation': 15,
                'opacity': 75,
              },
              'effects': [
                {
                  'matchName': 'ADBE Invert',
                  'name': 'Invert',
                  'properties': [],
                },
                {
                  'matchName': 'Vendor.ThirdPartyBlur',
                  'name': 'Third Party Blur',
                  'properties': [],
                },
              ],
            },
            {
              'id': '3',
              'index': 2,
              'name': 'Controller',
              'matchName': 'ADBE AV Layer',
              'startTimeSeconds': 0,
              'inPointSeconds': 0,
              'outPointSeconds': 8,
              'enabled': true,
              'nullLayer': true,
              'parentLayerId': '2',
              'hasVideo': false,
              'hasAudio': false,
            },
          ],
        },
      });

      final logo = report.document.layers.first;
      expect(logo.kind, LayerKind.video);
      expect(logo.startMs, 1000);
      expect(logo.durationMs, 5000);
      expect(logo.sourceInMs, 1000);
      expect(logo.transform.position.x, 500);
      expect(logo.transform.scale.x, 80);
      expect(logo.transform.rotation.z, 15);
      expect(logo.transform.opacity, 75);
      expect(logo.sourceUri, r'D:\Assets\logo.png');
      expect(logo.effects.single.effectId, 'invert');
      expect(logo.interchangeMetadata['matchName'], 'ADBE AV Layer');
      expect(report.unsupportedEffects, contains('aftereffects: Vendor.ThirdPartyBlur'));
      expect(report.document.layers.last.kind, LayerKind.nullObject);
      expect(report.document.layers.last.parentId, logo.id);

      final restored = CompositionProjectCodec.decodeDocument(
        CompositionProjectCodec.encodeDocument(report.document),
      );
      expect(restored.layers.first.externalSourceId, '2');
      expect(restored.layers.first.externalHostApp, 'aftereffects-beta');
      expect(restored.layers.first.interchangeMetadata['matchName'], 'ADBE AV Layer');
    });

    test('exports Premiere XML and editable After Effects script with explicit mapping report', () {
      final doc = CompositionDocument(
        name: 'Interchange Demo',
        width: 1920,
        height: 1080,
        durationMs: 5000,
        frameRate: 25,
        layers: [
          CompositionLayer(
            id: 'clip-1',
            name: 'Video One',
            kind: LayerKind.video,
            durationMs: 5000,
            sourceUri: r'C:\Media\clip.mp4',
            effects: [
              EffectInstance(
                id: 'fx-1',
                effectId: 'gaussian_blur',
                name: 'Gaussian Blur',
                parameters: const {'sigma': 4},
              ),
            ],
          ),
        ],
      );

      final xml = AdobeInterchangeService.buildPremiereXml(doc);
      expect(xml, contains('<xmeml version="5">'));
      expect(xml, contains('<clipitem id="clip-1">'));
      expect(xml, contains('file://'));
      expect(xml, contains('effect filters are not encoded'));

      final jsx = AdobeInterchangeService.buildAfterEffectsScript(doc);
      expect(jsx, contains('app.project.items.addComp'));
      expect(jsx, contains('ADBE Gaussian Blur 2'));
      expect(jsx, contains('app.project.importFile'));
      expect(jsx, contains('editable solid placeholder'));

      final bundle = AdobeInterchangeService.buildInterchangeBundle(doc);
      final mapping = bundle['effectMapping']! as Map<String, Object?>;
      final ae = mapping['afterEffects']! as Map<String, Object?>;
      expect((ae['mapped']! as List), hasLength(1));
      final pr = mapping['premiereFcpXml']! as Map<String, Object?>;
      expect((pr['mapped']! as List), isEmpty);
      expect((pr['unsupported']! as List), hasLength(1));
    });

    test('rejects unsupported snapshot versions and unknown hosts', () {
      expect(
        () => AdobeInterchangeService.importSnapshot({
          'schemaVersion': 9,
          'hostApp': 'premierepro',
        }),
        throwsFormatException,
      );
      expect(
        () => AdobeInterchangeService.importSnapshot({
          'schemaVersion': 1,
          'hostApp': 'unknown',
        }),
        throwsFormatException,
      );
      expect(EffectCatalog.findBuiltin('gaussian_blur'), isNotNull);
    });
  });
}
