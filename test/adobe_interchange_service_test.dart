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
      expect(logo.effects.length, 2);
      expect(logo.effects.first.effectId, 'invert');
      final nativeBlur = logo.effects.last;
      expect(nativeBlur.effectId, 'native_effect');
      expect(nativeBlur.nativeDescriptor['hostApp'], 'aftereffects-beta');
      expect(nativeBlur.nativeDescriptor['matchName'], 'Vendor.ThirdPartyBlur');
      expect(logo.interchangeMetadata['matchName'], 'ADBE AV Layer');
      expect(
        report.unsupportedEffects.any((item) => item.startsWith('aftereffects: Vendor.ThirdPartyBlur')),
        isTrue,
      );
      expect(report.document.layers.last.kind, LayerKind.nullObject);
      expect(report.document.layers.last.parentId, logo.id);

      final restored = CompositionProjectCodec.decodeDocument(
        CompositionProjectCodec.encodeDocument(report.document),
      );
      expect(restored.layers.first.externalSourceId, '2');
      expect(restored.layers.first.externalHostApp, 'aftereffects-beta');
      expect(restored.layers.first.interchangeMetadata['matchName'], 'ADBE AV Layer');
    });

    test('imports unknown After Effects plugins as usable native descriptors and exports them back', () {
      final report = AdobeInterchangeService.importSnapshot({
        'schemaVersion': 1,
        'hostApp': 'aftereffects-beta',
        'payload': {
          'composition': {
            'name': 'Native Effect Test',
            'width': 1920,
            'height': 1080,
            'durationSeconds': 3,
            'frameRate': 30,
          },
          'layers': [
            {
              'id': 'layer-1',
              'index': 1,
              'name': 'Glow Layer',
              'matchName': 'ADBE AV Layer',
              'startTimeSeconds': 0,
              'inPointSeconds': 0,
              'outPointSeconds': 3,
              'hasVideo': true,
              'effects': [
                {
                  'matchName': 'Vendor.SuperGlow',
                  'name': 'Super Glow',
                  'displayName': 'Super Glow',
                  'category': 'Stylize',
                  'version': '2.4',
                  'enabled': true,
                  'parameters': [
                    {
                      'matchName': 'Vendor.SuperGlow-0001',
                      'name': 'Radius',
                      'displayName': 'Glow Radius',
                      'path': ['Vendor.SuperGlow-0001'],
                      'value': 28.0,
                      'minValue': 0.0,
                      'maxValue': 100.0,
                      'unitsText': 'px',
                      'keyframes': [
                        {'timeMs': 0, 'value': 12.0},
                        {'timeMs': 1200, 'value': 28.0},
                      ],
                    },
                    {
                      'matchName': 'Vendor.SuperGlow-0002',
                      'name': 'Color',
                      'value': [1.0, 0.5, 0.2],
                    },
                  ],
                },
              ],
            },
          ],
        },
      });

      final effect = report.document.layers.single.effects.single;
      expect(effect.effectId, 'native_effect');
      expect(effect.name, 'Super Glow');
      expect(effect.nativeDescriptor['matchName'], 'Vendor.SuperGlow');
      expect(effect.nativeDescriptor['category'], 'Stylize');
      expect((effect.nativeDescriptor['parameters'] as List).length, 2);
      final radius = (effect.nativeDescriptor['parameters'] as List).first as Map;
      expect(radius['minValue'], 0.0);
      expect(radius['maxValue'], 100.0);
      expect((radius['keyframes'] as List).length, 2);

      final restored = CompositionProjectCodec.decodeDocument(
        CompositionProjectCodec.encodeDocument(report.document),
      );
      final restoredEffect = restored.layers.single.effects.single;
      expect(restoredEffect.nativeDescriptor['matchName'], 'Vendor.SuperGlow');
      final script = AdobeInterchangeService.buildAfterEffectsScript(restored);
      expect(script, contains('Vendor.SuperGlow'));
      expect(script, contains('applyNativeParameters'));
      expect(script, contains('effectProperty(group,item)'));
      expect(script, contains('nativeDescriptor.parameters'));
      expect(script, contains('setValueAtTime'));
    });

    test('imports Premiere video and audio plugins with media-specific native descriptors', () {
      final report = AdobeInterchangeService.importSnapshot({
        'schemaVersion': 1,
        'hostApp': 'premierepro',
        'payload': {
          'sequence': {
            'name': 'Native Effect Tracks',
            'width': 1920,
            'height': 1080,
            'timebase': '8467200000',
            'durationSeconds': 4,
          },
          'videoTracks': [
            {
              'index': 0,
              'id': 'V1',
              'name': 'V1',
              'clips': [
                {
                  'id': 'v1',
                  'name': 'Video',
                  'startSeconds': 0,
                  'durationSeconds': 3,
                  'effects': [
                    {
                      'matchName': 'PR.Vendor.VideoGlow',
                      'name': 'Video Glow',
                      'displayName': 'Video Glow',
                      'mediaType': 'video',
                      'parameters': [
                        {'index': 0, 'matchName': '0', 'displayName': 'Radius',
                          'name': 'Radius', 'value': 18.0, 'minValue': 0.0, 'maxValue': 50.0},
                      ],
                    },
                  ],
                },
              ],
            },
          ],
          'audioTracks': [
            {
              'index': 0,
              'id': 'A1',
              'name': 'A1',
              'clips': [
                {
                  'id': 'a1',
                  'name': 'Audio',
                  'startSeconds': 0,
                  'durationSeconds': 3,
                  'mediaType': 'audio',
                  'effects': [
                    {
                      'matchName': 'Dynamics',
                      'name': 'Dynamics',
                      'displayName': 'Dynamics',
                      'mediaType': 'audio',
                      'parameters': [
                        {'index': 0, 'matchName': '0', 'displayName': 'Threshold',
                          'name': 'Threshold', 'value': -18.0, 'minValue': -60.0, 'maxValue': 0.0},
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
      });
      final videoLayer = report.document.layers.firstWhere((layer) => layer.kind == LayerKind.video);
      final audioLayer = report.document.layers.firstWhere((layer) => layer.kind == LayerKind.audio);
      expect(videoLayer.effects.single.nativeDescriptor['mediaType'], 'video');
      expect(videoLayer.effects.single.nativeDescriptor['matchName'], 'PR.Vendor.VideoGlow');
      expect(audioLayer.effects.single.nativeDescriptor['mediaType'], 'audio');
      expect(audioLayer.effects.single.nativeDescriptor['matchName'], 'Dynamics');
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
      expect(xml, contains('<filter>'));
      expect(xml, contains('<effectid>Gaussian Blur</effectid>'));
      expect(xml, contains('<parameterid>radius</parameterid>'));
      expect(xml, contains('<value>4</value>'));

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
      expect((pr['mapped']! as List), hasLength(1));
      expect((pr['unsupported']! as List), isEmpty);
    });


    test('Premiere XMEML reports effects without a verified portable mapping', () {
      final doc = CompositionDocument(
        layers: [
          CompositionLayer(
            id: 'effect-clip',
            name: 'Effect Clip',
            kind: LayerKind.video,
            effects: [
              EffectInstance(
                id: 'blur',
                effectId: 'gaussian_blur',
                name: 'Gaussian Blur',
                parameters: const {'sigma': 9},
              ),
              EffectInstance(
                id: 'sharpen',
                effectId: 'sharpen',
                name: 'Sharpen',
                parameters: const {'amount': 2},
              ),
            ],
          ),
        ],
      );
      final xml = AdobeInterchangeService.buildPremiereXml(doc);
      expect(xml, contains('<effectid>Gaussian Blur</effectid>'));
      expect(xml, isNot(contains('<effectid>Sharpen</effectid>')));
      final mapping = AdobeInterchangeService.buildInterchangeBundle(doc)['effectMapping']!
          as Map<String, Object?>;
      final premiere = mapping['premiereFcpXml']! as Map<String, Object?>;
      expect(premiere['mapped'], hasLength(1));
      expect(premiere['unsupported'], hasLength(1));
      expect((premiere['unsupported']! as List).first['reason'],
          contains('No verified portable'));
    });

    test('Premiere applied transition metadata imports and survives project round-trip', () {
      final report = AdobeInterchangeService.importSnapshot({
        'schemaVersion': 1,
        'hostApp': 'premierepro',
        'payload': {
          'sequence': {
            'name': 'Transition Sequence',
            'width': 1920,
            'height': 1080,
            'timebase': '8467200000',
            'durationSeconds': 5,
          },
          'videoTracks': [
            {
              'index': 0,
              'id': 'V1',
              'name': 'V1',
              'clips': [
                {'id': 'a', 'name': 'A', 'startSeconds': 0, 'durationSeconds': 2, 'sourcePath': r'C:\Media\a.mp4'},
                {'id': 'b', 'name': 'B', 'startSeconds': 2, 'durationSeconds': 2, 'sourcePath': r'C:\Media\b.mp4'},
              ],
              'transitions': [
                {
                  'id': 'x1',
                  'name': 'Cross Dissolve',
                  'matchName': 'AE.ADBE Cross Dissolve',
                  'startSeconds': 1.9,
                  'durationSeconds': 0.5,
                },
              ],
            },
          ],
          'audioTracks': [],
        },
      });
      expect(report.document.transitions, hasLength(1));
      expect(report.document.transitions.single.kind, TransitionKind.dissolve);
      expect(report.document.transitions.single.externalMatchName, 'AE.ADBE Cross Dissolve');
      final restored = CompositionProjectCodec.decodeDocument(
        CompositionProjectCodec.encodeDocument(report.document),
      );
      expect(restored.transitions.single.externalMatchName, 'AE.ADBE Cross Dissolve');
      expect(restored.transitions.single.metadata['hostApp'], 'premierepro');
    });

    test('Premiere XML exports native transition items', () {
      final doc = CompositionDocument(
        name: 'Transition XML',
        durationMs: 4000,
        layers: [
          CompositionLayer(
            id: 'a', name: 'A', kind: LayerKind.video,
            startMs: 0, durationMs: 2200,
            interchangeMetadata: const {'hostApp': 'premierepro', 'trackIndex': 0},
            externalHostApp: 'premierepro',
          ),
          CompositionLayer(
            id: 'b', name: 'B', kind: LayerKind.video,
            startMs: 1800, durationMs: 2200,
            interchangeMetadata: const {'hostApp': 'premierepro', 'trackIndex': 0},
            externalHostApp: 'premierepro',
          ),
        ],
        transitions: [
          CompositionTransition(
            id: 'transition-1',
            fromLayerId: 'a',
            toLayerId: 'b',
            kind: TransitionKind.dissolve,
            startMs: 1800,
            durationMs: 400,
            externalMatchName: 'AE.ADBE Cross Dissolve',
            metadata: const {'sourceName': 'Cross Dissolve'},
          ),
        ],
      );
      final xml = AdobeInterchangeService.buildPremiereXml(doc);
      expect(xml, contains('<transitionitem>'));
      expect(xml, contains('<effecttype>transition</effecttype>'));
      expect(xml, contains('<effectid>AE.ADBE Cross Dissolve</effectid>'));
      expect(xml, contains('<alignment>center</alignment>'));
    });

    test('After Effects transform and effect keyframes import and survive .dvproj', () {
      final report = AdobeInterchangeService.importSnapshot({
        'schemaVersion': 1,
        'hostApp': 'aftereffects-beta',
        'payload': {
          'composition': {
            'name': 'Animated Shape',
            'width': 1920,
            'height': 1080,
            'durationSeconds': 4,
            'frameRate': 30,
          },
          'layers': [
            {
              'id': 'animated-layer',
              'index': 1,
              'name': 'Animated Logo',
              'matchName': 'ADBE AV Layer',
              'startTimeSeconds': 0,
              'inPointSeconds': 0,
              'outPointSeconds': 4,
              'enabled': true,
              'hasVideo': true,
              'hasAudio': false,
              'sourcePath': r'C:\\Assets\\logo.png',
              'transform': {
                'position': [200, 100, 0],
                'anchorPoint': [50, 50, 0],
                'scale': [100, 100, 100],
                'rotation': 0,
                'opacity': 100,
              },
              'keyframeTracks': [
                {
                  'property': 'position.x',
                  'keyframes': [
                    {'timeMs': 0, 'value': 200, 'interpolation': 'linear'},
                    {
                      'timeMs': 2000,
                      'value': 600,
                      'interpolation': 'cubicBezier',
                      'inInterpolation': 'cubicBezier',
                      'outInterpolation': 'cubicBezier',
                      'inTemporalEase': [{'speed': 12, 'influence': 35}],
                      'outTemporalEase': [{'speed': 18, 'influence': 62}],
                      'inSpatialTangent': [-8, 4],
                      'outSpatialTangent': [12, 6],
                      'roving': true,
                      'spatialAutoBezier': false,
                      'spatialContinuous': true,
                      'temporalAutoBezier': false,
                      'temporalContinuous': true,
                    },
                  ],
                },
                {
                  'property': 'opacity',
                  'keyframes': [
                    {'timeMs': 0, 'value': 40, 'interpolation': 'hold'},
                    {'timeMs': 2000, 'value': 100, 'interpolation': 'linear'},
                  ],
                },
              ],
              'expressions': [
                {'property': 'opacity', 'source': 'time * 20', 'enabled': true},
              ],
              'effects': [
                {
                  'matchName': 'ADBE Gaussian Blur 2',
                  'name': 'Gaussian Blur',
                  'enabled': true,
                  'properties': [
                    {
                      'matchName': 'ADBE Gaussian Blur 2-0001',
                      'name': 'Blurriness',
                      'value': 8,
                      'keyframes': [
                        {'timeMs': 0, 'value': 2, 'interpolation': 'hold'},
                        {'timeMs': 2000, 'value': 12, 'interpolation': 'linear'},
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
      });

      final layer = report.document.layers.single;
      final position = layer.keyframeTracks.singleWhere(
        (track) => track.property == 'position.x',
      );
      expect(position.keyframes, hasLength(2));
      expect(position.keyframes.last.interpolation, Interpolation.cubicBezier);
      expect(position.keyframes.last.metadata['roving'], true);
      expect(position.keyframes.last.metadata['spatialContinuous'], true);
      expect(position.keyframes.last.metadata['inSpatialTangent'], [-8, 4]);
      expect(position.keyframes.last.metadata['outTemporalEase'], [
        {'speed': 18, 'influence': 62},
      ]);
      expect(position.sample(1000), closeTo(400, 0.001));
      final opacity = layer.keyframeTracks.singleWhere(
        (track) => track.property == 'opacity',
      );
      expect(opacity.sample(1000), 40);
      final blur = layer.effects.single;
      expect(blur.effectId, 'gaussian_blur');
      expect(blur.keyframeTracks.single.property, 'sigma');
      expect(blur.parameterAt('sigma', 1000), 2);
      expect(layer.interchangeMetadata['expressions'], isA<List>());

      final restored = CompositionProjectCodec.decodeDocument(
        CompositionProjectCodec.encodeDocument(report.document),
      );
      expect(
        restored.layers.single.keyframeTracks.singleWhere(
          (track) => track.property == 'position.x',
        ).keyframes.last.interpolation,
        Interpolation.cubicBezier,
      );
      final restoredPosition = restored.layers.single.keyframeTracks.singleWhere(
        (track) => track.property == 'position.x',
      );
      expect(restoredPosition.keyframes.last.metadata['roving'], true);
      expect(restoredPosition.keyframes.last.metadata['inTemporalEase'], isA<List>());
      expect(restored.layers.single.effects.single.keyframeTracks, hasLength(1));
      expect(restored.layers.single.interchangeMetadata['expressions'], isA<List>());
    });

    test('Premiere XML keeps clips from the same imported track together', () {
      CompositionLayer makeVideo(String id, int trackIndex, int startMs) =>
          CompositionLayer(
            id: id,
            name: id,
            kind: LayerKind.video,
            startMs: startMs,
            durationMs: 1000,
            sourceUri: '/media/$id.mp4',
            externalHostApp: 'premierepro',
            externalLayerIndex: trackIndex,
            interchangeMetadata: {
              'hostApp': 'premierepro',
              'trackIndex': trackIndex,
              'trackName': 'V' + (trackIndex + 1).toString(),
            },
          );
      final doc = CompositionDocument(
        name: 'Multi Track',
        durationMs: 5000,
        frameRate: 25,
        layers: [
          makeVideo('v1-a', 0, 0),
          makeVideo('v1-b', 0, 2000),
          makeVideo('v2-a', 1, 500),
          CompositionLayer(
            id: 'a1',
            name: 'Music',
            kind: LayerKind.audio,
            durationMs: 5000,
            externalHostApp: 'premierepro',
            externalLayerIndex: 0,
            interchangeMetadata: {
              'hostApp': 'premierepro',
              'trackIndex': 0,
              'trackName': 'A1',
            },
          ),
        ],
      );

      final xml = AdobeInterchangeService.buildPremiereXml(doc);
      expect('<track>'.allMatches(xml), hasLength(3));
      expect('<clipitem '.allMatches(xml), hasLength(4));
      expect(xml, contains('v1-a'));
      expect(xml, contains('v1-b'));
      expect(xml, contains('v2-a'));
      expect(xml, contains('Music'));
    });

    test('After Effects export script writes keyframes on editable properties', () {
      final doc = CompositionDocument(
        layers: [
          CompositionLayer(
            id: 'animated',
            name: 'Animated',
            kind: LayerKind.video,
            keyframeTracks: [
              KeyframeTrack(
                property: 'position.x',
                keyframes: [
                  ScalarKeyframe(timeMs: 0, value: 100),
                  ScalarKeyframe(timeMs: 1000, value: 400),
                ],
              ),
              KeyframeTrack(
                property: 'opacity',
                keyframes: [
                  ScalarKeyframe(timeMs: 0, value: 0),
                  ScalarKeyframe(timeMs: 1000, value: 100),
                ],
              ),
            ],
            effects: [
              EffectInstance(
                id: 'blur',
                effectId: 'gaussian_blur',
                name: 'Gaussian Blur',
                parameters: const {'sigma': 4},
                keyframeTracks: [
                  KeyframeTrack(
                    property: 'sigma',
                    keyframes: [
                      ScalarKeyframe(timeMs: 0, value: 1),
                      ScalarKeyframe(timeMs: 1000, value: 8),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final script = AdobeInterchangeService.buildAfterEffectsScript(doc);
      expect(script, contains('applyVectorTracks'));
      expect(script, contains('applyScalarTrack'));
      expect(script, contains('setValueAtTime'));
      expect(script, contains('setInterpolationTypeAtKey'));
      expect(script, contains('setSpatialTangentsAtKey'));
      expect(script, contains('setTemporalEaseAtKey'));
      expect(script, contains('ADBE Effect Parade'));
      expect(script, contains('unsupportedEffects'));
      expect(script, contains('canAddProperty(rawMatch)'));
      expect(script, contains('setRovingAtKey'));
      expect(script, contains('applyImportedTransitions'));
      expect(script, contains('new KeyframeEase'));
      expect(script, contains('ADBE Gaussian Blur 2-0001'));
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
