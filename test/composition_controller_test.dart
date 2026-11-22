import 'package:depthvibe/features/composition/application/composition_controller.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applies a portable native-effect preset with shifted editable keyframes', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 8000,
        playheadMs: 3000,
        layers: [
          CompositionLayer(
            id: 'target',
            name: 'Target',
            kind: LayerKind.video,
            startMs: 0,
            transform: LayerTransform(position: Vector3(600, 400, 0)),
          ),
        ],
        selectedLayerId: 'target',
      ),
    );
    final preset = CompositionLayer(
      id: 'preset',
      name: 'Native preset',
      kind: LayerKind.video,
      startMs: 1000,
      transform: const LayerTransform(position: Vector3(100, 200, 0)),
      keyframeTracks: const [
        KeyframeTrack(
          property: 'position.x',
          keyframes: [
            ScalarKeyframe(timeMs: 1000, value: 100),
            ScalarKeyframe(timeMs: 1500, value: 200),
          ],
        ),
      ],
      effects: const [
        EffectInstance(
          id: 'source-effect',
          effectId: 'native_effect',
          name: 'Third-party Glow',
          nativeDescriptor: {
            'hostApp': 'aftereffects-beta',
            'matchName': 'Vendor.Glow',
            'parameters': [
              {'matchName': 'Vendor.Glow-0001', 'name': 'Radius', 'value': 18},
            ],
          },
        ),
      ],
    );
    controller.applyLayerPreset(preset);
    final layer = controller.selectedLayer!;
    final track = layer.keyframeTracks.single;
    expect(track.keyframes.first.timeMs, 3000);
    expect(track.keyframes.last.timeMs, 3500);
    expect(track.keyframes.first.value, 600);
    expect(track.keyframes.last.value, 700);
    expect(layer.effects.single.nativeDescriptor['matchName'], 'Vendor.Glow');
  });

  test('updates a captured native effect parameter without discarding its descriptor', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        layers: [
          CompositionLayer(
            id: 'target',
            name: 'Target',
            kind: LayerKind.video,
            effects: [
              EffectInstance(
                id: 'native-1',
                effectId: 'native_effect',
                name: 'Native effect',
                nativeDescriptor: {
                  'matchName': 'Vendor.Glow',
                  'parameters': [
                    {'matchName': 'Vendor.Glow-0001', 'name': 'Radius', 'value': 18},
                  ],
                },
              ),
            ],
          ),
        ],
        selectedLayerId: 'target',
      ),
    );
    controller.setNativeEffectParameter('native-1', 'Vendor.Glow-0001', 32);
    final descriptor = controller.selectedLayer!.effects.single.nativeDescriptor;
    expect((descriptor['parameters'] as List).single['value'], 32);
    expect(descriptor['matchName'], 'Vendor.Glow');
  });

  test('updates duplicate native parameter names by full host property path', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        layers: [
          CompositionLayer(
            id: 'target',
            name: 'Target',
            kind: LayerKind.video,
            effects: [
              EffectInstance(
                id: 'native-1',
                effectId: 'native_effect',
                name: 'Nested native effect',
                nativeDescriptor: {
                  'matchName': 'Vendor.Nested',
                  'parameters': [
                    {'matchName': 'Radius', 'path': ['GroupA', 'Radius'], 'value': 5.0},
                    {'matchName': 'Radius', 'path': ['GroupB', 'Radius'], 'value': 15.0},
                  ],
                },
              ),
            ],
          ),
        ],
        selectedLayerId: 'target',
      ),
    );
    controller.setNativeEffectParameter(
      'native-1', 'Radius', 25.0,
      parameterPath: const ['GroupB', 'Radius'],
    );
    final parameters = controller.selectedLayer!.effects.single.nativeDescriptor['parameters'] as List;
    expect((parameters[0] as Map)['value'], 5.0);
    expect((parameters[1] as Map)['value'], 25.0);
  });

  test('edits a captured native-effect keyframe without losing interpolation metadata', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        layers: [
          CompositionLayer(
            id: 'target',
            name: 'Target',
            kind: LayerKind.video,
            effects: [
              EffectInstance(
                id: 'native-1',
                effectId: 'native_effect',
                name: 'Premiere Gaussian Blur',
                nativeDescriptor: {
                  'hostApp': 'premierepro',
                  'matchName': 'PR.ADBE Gaussian Blur',
                  'parameters': [
                    {
                      'index': 0,
                      'matchName': '0',
                      'name': 'Blurriness',
                      'displayName': 'Blurriness',
                      'path': ['PR.ADBE Gaussian Blur', '0'],
                      'keyframes': [
                        {'timeSeconds': 0.5, 'value': 2.0, 'interpolation': 'linear'},
                      ],
                    },
                  ],
                },
              ),
              EffectInstance(
                id: 'mapped-blur',
                effectId: 'gaussian_blur',
                name: 'Gaussian Blur',
                parameters: const {'sigma': 2.0},
              ),
            ],
          ),
        ],
        selectedLayerId: 'target',
      ),
    );
    controller.setNativeEffectParameterKeyframe(
      'native-1',
      '0',
      0.5,
      8.0,
      interpolation: 'bezier',
      parameterPath: const ['PR.ADBE Gaussian Blur', '0'],
    );
    final parameter = (controller.selectedLayer!.effects
        .singleWhere((effect) => effect.id == 'native-1')
        .nativeDescriptor['parameters'] as List).single as Map;
    final keyframe = (parameter['keyframes'] as List).single as Map;
    expect(keyframe['value'], 8.0);
    expect(keyframe['interpolation'], 'bezier');
    expect(parameter['keyframesSupported'], true);
    final mappedBlur = controller.selectedLayer!.effects
        .singleWhere((effect) => effect.id == 'mapped-blur');
    expect(mappedBlur.parameters['sigma'], 8.0);
    expect(mappedBlur.keyframeTracks.single.property, 'sigma');
    expect(mappedBlur.keyframeTracks.single.keyframes.single.value, 8.0);
  });

  test('applies motion presets as editable keyframe tracks', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 5000,
        layers: [
          CompositionLayer(
            id: 'text',
            name: 'Title',
            kind: LayerKind.text,
            transform: LayerTransform(position: Vector3(960, 540, 0)),
          ),
        ],
        selectedLayerId: 'text',
      ),
    );
    controller.applyMotionPreset('slide_in_left');
    final layer = controller.selectedLayer!;
    final track = layer.keyframeTracks.singleWhere(
      (item) => item.property == 'position.x',
    );
    expect(track.keyframes, hasLength(2));
    expect(track.keyframes.first.value, lessThan(0));
    expect(track.keyframes.last.value, 960);
    controller.applyMotionPreset('pop_bounce');
    expect(controller.selectedLayer!.keyframeTracks.any(
      (item) => item.property == 'scale.x' && item.keyframes.length >= 4,
    ), isTrue);
  });

  group('CompositionController', () {
    test('creates AE-style layer types and selects the new layer', () {
      final controller = CompositionController();
      final nullId = controller.addLayer(LayerKind.nullObject);
      final footageId = controller.addLayer(LayerKind.video);

      expect(controller.document.layers.length, 2);
      expect(controller.document.selectedLayerId, footageId);
      expect(controller.document.layers.first.kind, LayerKind.video);
      expect(nullId, isNot(footageId));
      controller.dispose();
    });

    test('parent links support null controllers and prevent cycles', () {
      final controller = CompositionController();
      final parentA = controller.addLayer(LayerKind.nullObject);
      final parentB = controller.addLayer(LayerKind.nullObject);
      final child = controller.addLayer(LayerKind.image);

      expect(controller.setParent(child, parentA), isTrue);
      expect(controller.setParent(parentA, parentB), isTrue);
      expect(controller.setParent(parentB, child), isFalse);
      controller.dispose();
    });

    test('keyframes interpolate linear and eased values', () {
      final track = const KeyframeTrack(
        property: 'opacity',
        keyframes: [
          ScalarKeyframe(timeMs: 0, value: 0),
          ScalarKeyframe(timeMs: 1000, value: 100),
        ],
      );
      expect(track.sample(500), 50);
      final eased = const KeyframeTrack(
        property: 'opacity',
        keyframes: [
          ScalarKeyframe(timeMs: 0, value: 0, interpolation: Interpolation.easeInOut),
          ScalarKeyframe(timeMs: 1000, value: 100),
        ],
      );
      expect(eased.sample(500), closeTo(50, 0.001));
    });

    test('setInterpolation updates the selected effect parameter keyframe', () {
      final controller = CompositionController();
      final layerId = controller.addLayer(LayerKind.video);
      controller.addEffect('brightness');
      final effectId = controller.selectedLayer!.effects.single.id;
      controller.addEffectKeyframe(effectId, 'value');
      controller.setInterpolation(
        'value',
        Interpolation.easeOut,
        effectId: effectId,
      );

      final layer = controller.document.layers
          .firstWhere((item) => item.id == layerId);
      final track = layer.effects
          .firstWhere((item) => item.id == effectId)
          .keyframeTracks
          .first;
      expect(track.keyframes.first.interpolation, Interpolation.easeOut);
      controller.dispose();
    });

    test('transitions connect selected adjacent clips and can be edited', () {
      final controller = CompositionController();
      final first = controller.addLayer(LayerKind.video);
      final second = controller.addLayer(LayerKind.image);

      controller.addTransition(TransitionKind.wipeLeft);
      expect(controller.document.transitions, hasLength(1));
      var transition = controller.document.transitions.single;
      expect(transition.fromLayerId, first);
      expect(transition.toLayerId, second);

      controller.updateTransition(
        transition.id,
        kind: TransitionKind.slideRight,
        durationMs: 1200,
        startMs: 600,
      );
      transition = controller.document.transitions.single;
      expect(transition.kind, TransitionKind.slideRight);
      expect(transition.durationMs, 1200);
      expect(transition.startMs, 600);

      controller.removeTransition(transition.id);
      expect(controller.document.transitions, isEmpty);
      controller.dispose();
    });

    test('timeline source-in and clip timing are clamped to composition bounds', () {
      final controller = CompositionController();
      final id = controller.addLayer(LayerKind.video);

      controller.setLayerTiming(
        id,
        startMs: 5000,
        durationMs: 9000,
        sourceInMs: 3000,
      );
      var layer = controller.document.layers.single;
      expect(layer.startMs, 5000);
      expect(layer.durationMs, 9000);
      expect(layer.sourceInMs, 3000);

      controller.setLayerTiming(id, startMs: 40000, durationMs: 9000);
      layer = controller.document.layers.single;
      expect(layer.startMs, 29999);
      expect(layer.durationMs, 1);
      expect(layer.sourceInMs, 3000);
      controller.dispose();
    });

    test('tracking samples become inverse stabilizing position keyframes', () {
      final controller = CompositionController();
      final layerId = controller.addLayer(LayerKind.video);
      final layer = controller.selectedLayer!;

      controller.applyMotionTrack(
        layerId: layerId,
        sourceWidth: 1920,
        sourceHeight: 1080,
        stabilize: true,
        samples: const [
          MotionTrackSample(timeMs: 0, x: 300, y: 200, score: 0.9),
          MotionTrackSample(timeMs: 100, x: 320, y: 230, score: 0.8),
        ],
      );

      final tracked = controller.document.layers.single;
      final xTrack = tracked.keyframeTracks.firstWhere(
        (track) => track.property == 'position.x',
      );
      final yTrack = tracked.keyframeTracks.firstWhere(
        (track) => track.property == 'position.y',
      );

      expect(xTrack.keyframes, hasLength(2));
      expect(yTrack.keyframes, hasLength(2));
      expect(xTrack.keyframes.last.value, closeTo(
        layer.transform.position.x - 20,
        0.001,
      ));
      expect(yTrack.keyframes.last.value, closeTo(
        layer.transform.position.y - 30,
        0.001,
      ));
      controller.dispose();
    });

    test('Photoshop adjustment layers keep mapped editable effects', () {
      final controller = CompositionController();
      controller.addPhotoshopLayers(
        sourceDocumentUri: '/design/adjustments.psd',
        documentWidth: 800,
        documentHeight: 600,
        assets: const [
          PhotoshopLayerAsset(
            sourceIndex: 0,
            name: 'Black and White Threshold',
            assetPath: '',
            left: 0,
            top: 0,
            width: 800,
            height: 600,
            opacity: 255,
            blendMode: 'norm',
            visible: true,
            isGroup: false,
            isAdjustment: true,
            adjustmentKey: 'thrs',
            adjustmentEffects: [
              EffectInstance(
                id: 'psd_0_threshold',
                effectId: 'threshold',
                name: 'Photoshop Threshold',
                parameters: {'value': 144},
              ),
            ],
          ),
        ],
      );

      final layer = controller.document.layers.single;
      expect(layer.kind, LayerKind.adjustment);
      expect(layer.photoshopAdjustmentKey, 'thrs');
      expect(layer.effects, hasLength(1));
      expect(layer.effects.single.effectId, 'threshold');
      expect(layer.effects.single.parameters['value'], 144);
      controller.dispose();
    });

    test('Photoshop groups preserve nesting, clipping bases and smart objects', () {
      final controller = CompositionController();
      controller.addPhotoshopLayers(
        sourceDocumentUri: '/design/nested-layout.psd',
        documentWidth: 1600,
        documentHeight: 900,
        assets: const [
          PhotoshopLayerAsset(
            sourceIndex: 0,
            name: 'Hero Group',
            assetPath: '',
            left: 0,
            top: 0,
            width: 1600,
            height: 900,
            opacity: 255,
            blendMode: 'pass',
            visible: true,
            isGroup: true,
          ),
          PhotoshopLayerAsset(
            sourceIndex: 1,
            name: 'Base Photo',
            assetPath: '/cache/base.png',
            left: 100,
            top: 100,
            width: 700,
            height: 500,
            opacity: 255,
            blendMode: 'norm',
            visible: true,
            isGroup: false,
            parentGroupSourceIndex: 0,
          ),
          PhotoshopLayerAsset(
            sourceIndex: 2,
            name: 'Tint Smart Object',
            assetPath: '/cache/tint-preview.png',
            left: 100,
            top: 100,
            width: 700,
            height: 500,
            opacity: 180,
            blendMode: 'over',
            visible: true,
            isGroup: false,
            parentGroupSourceIndex: 0,
            clipping: 1,
            clippingBaseSourceIndex: 1,
            smartObjectSourceUri: '/cache/tint-source.psb',
            smartObjectResourceId: 'linked-object-123',
          ),
        ],
      );

      final group = controller.document.layers
          .firstWhere((layer) => layer.sourceLayerIndex == 0);
      final base = controller.document.layers
          .firstWhere((layer) => layer.sourceLayerIndex == 1);
      final clipped = controller.document.layers
          .firstWhere((layer) => layer.sourceLayerIndex == 2);

      expect(group.kind, LayerKind.precomposition);
      expect(base.parentId, group.id);
      expect(clipped.parentId, group.id);
      expect(clipped.photoshopClipped, isTrue);
      expect(clipped.clippingBaseLayerId, base.id);
      expect(clipped.smartObjectSourceUri, '/cache/tint-source.psb');
      expect(clipped.smartObjectResourceId, 'linked-object-123');
      controller.dispose();
    });

    test('photoshop assets become separate layers with document geometry', () {
      final controller = CompositionController();
      controller.addPhotoshopLayers(
        sourceDocumentUri: '/design/cover.psd',
        documentWidth: 2400,
        documentHeight: 1600,
        assets: const [
          PhotoshopLayerAsset(
            sourceIndex: 0,
            name: 'Title',
            assetPath: '/cache/title.png',
            left: 100,
            top: 200,
            width: 900,
            height: 260,
            opacity: 200,
            blendMode: 'norm',
            visible: true,
            isGroup: false,
            textContent: 'DepthVibe',
          ),
        ],
      );

      final layer = controller.document.layers.single;
      expect(controller.document.width, 2400);
      expect(controller.document.height, 1600);
      expect(layer.kind, LayerKind.text);
      expect(layer.textContent, 'DepthVibe');
      expect(layer.sourceLayerIndex, 0);
      expect(layer.transform.position.x, 550);
      controller.dispose();
    });

    test('effect parameters can receive keyframes', () {
      final controller = CompositionController();
      final layerId = controller.addLayer(LayerKind.video);
      controller.addEffect('gaussian_blur');
      final effectId = controller.document.layers
          .firstWhere((layer) => layer.id == layerId)
          .effects
          .single
          .id;

      controller.setPlayhead(1200);
      controller.addEffectKeyframe(effectId, 'sigma');
      controller.setEffectParameter(effectId, 'sigma', 12, keyframe: true);

      final effect = controller.document.layers
          .firstWhere((layer) => layer.id == layerId)
          .effects
          .single;
      expect(effect.keyframeTracks.single.keyframes.single.timeMs, 1200);
      expect(effect.parameterAt('sigma', 1200), 12);
      controller.dispose();
    });

    test('new and edited transitions snap to composition frames', () {
      final controller = CompositionController(
        document: const CompositionDocument(
          frameRate: 24,
          durationMs: 3000,
        ),
      );
      controller.addLayer(LayerKind.video);
      controller.addLayer(LayerKind.image);
      controller.setPlayhead(123);

      controller.addTransition(TransitionKind.dissolve);
      var transition = controller.document.transitions.single;
      expect(transition.startMs, 125);
      expect(transition.durationMs, 500);

      controller.updateTransition(
        transition.id,
        startMs: 333,
        durationMs: 350,
      );
      transition = controller.document.transitions.single;
      expect(transition.startMs, 333);
      expect(transition.durationMs, 333);
      controller.dispose();
    });

    test('audio tracks can be routed to a submix bus and back to master', () {
      final controller = CompositionController();
      controller.addLayer(LayerKind.audio);

      final master = controller.document.audioBuses.single;
      final musicBus = controller.addAudioBus(name: 'Music');

      controller.assignSelectedAudioBus(musicBus.id);
      expect(controller.selectedLayer!.audioSettings.busId, musicBus.id);

      controller.removeAudioBus(musicBus.id);
      expect(controller.document.audioBuses, hasLength(1));
      expect(controller.selectedLayer!.audioSettings.busId, master.id);
      controller.dispose();
    });

    test('master audio bus cannot be removed', () {
      final controller = CompositionController();
      final master = controller.document.audioBuses.single;

      controller.removeAudioBus(master.id);

      expect(controller.document.audioBuses, hasLength(1));
      expect(controller.document.audioBuses.single.isMaster, isTrue);
      controller.dispose();
    });

    test('audio buses store and edit gain and pan keyframes', () {
      final controller = CompositionController();
      final bus = controller.addAudioBus(name: 'Music');

      controller.setPlayhead(0);
      controller.setAudioBusValue(
        bus.id,
        'gainDb',
        -12,
        keyframe: true,
      );
      controller.setAudioBusValue(
        bus.id,
        'pan',
        -1,
        keyframe: true,
      );
      controller.setPlayhead(1000);
      controller.setAudioBusValue(
        bus.id,
        'gainDb',
        0,
        keyframe: true,
      );
      controller.setAudioBusValue(
        bus.id,
        'pan',
        1,
        keyframe: true,
      );

      var updated = controller.document.audioBuses
          .firstWhere((item) => item.id == bus.id);
      expect(updated.valueAt('gainDb', 500), closeTo(-6, 0.001));
      expect(updated.valueAt('pan', 500), closeTo(0, 0.001));

      const curve = BezierCurve(x1: 0.2, y1: 0, x2: 0.8, y2: 1);
      controller.setAudioBusBezierCurve(
        bus.id,
        'gainDb',
        curve,
        timeMs: 0,
      );
      controller.setAudioBusInterpolation(
        bus.id,
        'pan',
        Interpolation.cubicBezier,
        timeMs: 0,
      );

      updated = controller.document.audioBuses
          .firstWhere((item) => item.id == bus.id);
      expect(
        updated.keyframeTracks.firstWhere(
          (track) => track.property == 'gainDb',
        ).keyframes.first.bezier.x1,
        0.2,
      );
      expect(
        updated.keyframeTracks.firstWhere(
          (track) => track.property == 'pan',
        ).keyframes.first.interpolation,
        Interpolation.cubicBezier,
      );
      controller.dispose();
    });

    test('audio bus dynamics can be updated without changing its identity', () {
      final controller = CompositionController();
      final bus = controller.addAudioBus(name: 'Dialogue');

      controller.updateAudioBus(bus.copyWith(
        compressorEnabled: true,
        compressorThresholdDb: -24,
        compressorRatio: 5,
        limiterEnabled: true,
      ));

      final updated = controller.document.audioBuses
          .firstWhere((item) => item.id == bus.id);
      expect(updated.name, 'Dialogue');
      expect(updated.compressorEnabled, isTrue);
      expect(updated.compressorThresholdDb, -24);
      expect(updated.compressorRatio, 5);
      expect(updated.limiterEnabled, isTrue);
      controller.dispose();
    });

    test('one click keys every anchor and tangent on the mask path', () {
      final controller = CompositionController();
      controller.addLayer(LayerKind.shape);
      controller.addMask(shape: MaskShape.bezier);
      final maskId = controller.selectedLayer!.masks.single.id;
      controller.setPlayhead(640);

      controller.keyframeMaskPath(maskId);

      final mask = controller.selectedLayer!.masks.single;
      expect(mask.keyframeTracks, hasLength(mask.vertices.length * 6));
      for (var index = 0; index < mask.vertices.length; index++) {
        for (final component in const [
          'anchor.x',
          'anchor.y',
          'inHandle.x',
          'inHandle.y',
          'outHandle.x',
          'outHandle.y',
        ]) {
          final track = mask.keyframeTracks.firstWhere(
            (item) => item.property == 'vertex.$index.$component',
          );
          expect(track.keyframes.single.timeMs, 640);
        }
      }
      controller.dispose();
    });

    test('polygon and Bezier mask vertex components can be keyframed', () {
      final controller = CompositionController();
      controller.addLayer(LayerKind.shape);
      controller.addMask(shape: MaskShape.bezier);
      final maskId = controller.selectedLayer!.masks.single.id;

      controller.setPlayhead(0);
      controller.setMaskVertexAnimatedValue(
        maskId,
        0,
        'anchor.x',
        0.2,
        keyframe: true,
      );
      controller.setMaskVertexAnimatedValue(
        maskId,
        0,
        'outHandle.y',
        0.1,
        keyframe: true,
      );
      controller.setPlayhead(1000);
      controller.setMaskVertexAnimatedValue(
        maskId,
        0,
        'anchor.x',
        0.6,
        keyframe: true,
      );
      controller.setMaskVertexAnimatedValue(
        maskId,
        0,
        'outHandle.y',
        0.3,
        keyframe: true,
      );

      final mask = controller.selectedLayer!.masks.single;
      expect(mask.vertexValueAt(0, 'anchor.x', 500), closeTo(0.4, 0.001));
      expect(mask.vertexValueAt(0, 'outHandle.y', 500), closeTo(0.2, 0.001));
      expect(
        mask.keyframeTracks.map((track) => track.property),
        containsAll([
          'vertex.0.anchor.x',
          'vertex.0.outHandle.y',
        ]),
      );
      controller.dispose();
    });

    test('Bezier mask handles can be edited independently', () {
      final controller = CompositionController();
      controller.addLayer(LayerKind.shape);
      controller.addMask(shape: MaskShape.bezier);
      final mask = controller.selectedLayer!.masks.single;

      controller.setMaskVertex(
        mask.id,
        0,
        anchor: const Vector2(0.3, 0.4),
        outHandle: const Vector2(0.2, 0.1),
        smooth: true,
      );

      final edited = controller.selectedLayer!.masks.single.vertices.first;
      expect(edited.anchor.x, 0.3);
      expect(edited.anchor.y, 0.4);
      expect(edited.outHandle.x, 0.2);
      expect(edited.outHandle.y, 0.1);
      expect(edited.smooth, isTrue);
      controller.dispose();
    });

    test('smooth Bezier mask handles remain collinear and opposite', () {
      final controller = CompositionController();
      controller.addLayer(LayerKind.shape);
      controller.addMask(shape: MaskShape.bezier);
      final mask = controller.selectedLayer!.masks.single;

      controller.setMaskVertex(
        mask.id,
        0,
        inHandle: const Vector2(-0.1, 0.1),
      );
      controller.setMaskVertex(
        mask.id,
        0,
        outHandle: const Vector2(0.2, 0),
        smooth: true,
      );

      final vertex = controller.selectedLayer!.masks.single.vertices.first;
      final cross = vertex.inHandle.x * vertex.outHandle.y -
          vertex.inHandle.y * vertex.outHandle.x;
      final dot = vertex.inHandle.x * vertex.outHandle.x +
          vertex.inHandle.y * vertex.outHandle.y;
      expect(cross, closeTo(0, 0.000001));
      expect(dot, lessThan(0));
      controller.dispose();
    });

    test('Bezier graph edits are stored on the current keyframe', () {
      final controller = CompositionController();
      controller.addLayer(LayerKind.video);
      controller.addKeyframe('position.x', value: 100);
      const curve = BezierCurve(x1: 0.2, y1: 0.1, x2: 0.8, y2: 0.95);

      controller.setBezierCurve('position.x', curve);

      final frame = controller.selectedLayer!.keyframeTracks
          .single
          .keyframes
          .single;
      expect(frame.interpolation, Interpolation.cubicBezier);
      expect(frame.bezier.x1, 0.2);
      expect(frame.bezier.y1, 0.1);
      expect(frame.bezier.x2, 0.8);
      expect(frame.bezier.y2, 0.95);
      controller.dispose();
    });

    test('text layers retain editable international typography settings', () {
      final controller = CompositionController();
      final id = controller.addLayer(LayerKind.text);
      expect(controller.selectedLayer!.textContent, 'Your text');

      controller.updateTextLayer(
        textContent: 'বাংলা العربية English 日本語',
        textFontFamily: 'DV_Noto_Sans_Bengali',
        textFontAssetUri: '/fonts/noto-bengali.ttf',
        textFontFallback: const ['Noto Naskh Arabic', 'Noto Sans CJK SC'],
        textFontSize: 96,
        textFontWeight: 600,
        textItalic: true,
        textColor: '#FF22AA88',
        textLetterSpacing: 1.5,
        textLineHeight: 1.4,
        textAlign: 'center',
        textBoxWidth: 1440,
      );

      final layer = controller.document.layers.single;
      expect(layer.id, id);
      expect(layer.textContent, 'বাংলা العربية English 日本語');
      expect(layer.textFontFamily, 'DV_Noto_Sans_Bengali');
      expect(layer.textFontAssetUri, '/fonts/noto-bengali.ttf');
      expect(layer.textFontFallback, ['Noto Naskh Arabic', 'Noto Sans CJK SC']);
      expect(layer.textFontSize, 96);
      expect(layer.textFontWeight, 600);
      expect(layer.textItalic, isTrue);
      expect(layer.textColor, '#FF22AA88');
      expect(layer.textLetterSpacing, 1.5);
      expect(layer.textLineHeight, 1.4);
      expect(layer.textAlign, 'center');
      expect(layer.textBoxWidth, 1440);

      controller.updateTextLayer(
        textFontFamily: 'Arial',
        clearTextFontAsset: true,
      );
      expect(controller.selectedLayer!.textFontFamily, 'Arial');
      expect(controller.selectedLayer!.textFontAssetUri, isNull);

      controller.updateTextLayer(clearTextFont: true);
      expect(controller.selectedLayer!.textFontFamily, isNull);
      expect(controller.selectedLayer!.textFontAssetUri, isNull);
      controller.dispose();
    });

    test('splits a selected clip at playhead with independent effects and masks', () {
      final controller = CompositionController(
        document: const CompositionDocument(
          durationMs: 8000,
          playheadMs: 3200,
          layers: [
            CompositionLayer(
              id: 'video_a',
              name: 'Interview',
              kind: LayerKind.video,
              startMs: 1000,
              durationMs: 4000,
              sourceInMs: 500,
              sourceUri: '/media/interview.mp4',
              effects: [
                EffectInstance(
                  id: 'effect_a',
                  effectId: 'gaussian_blur',
                  name: 'Gaussian Blur',
                  parameters: {'sigma': 4},
                ),
              ],
              masks: [
                MaskModel(id: 'mask_a', name: 'Subject Mask'),
              ],
            ),
          ],
          selectedLayerId: 'video_a',
        ),
      );

      expect(controller.splitSelectedLayerAtPlayhead(), isTrue);
      expect(controller.document.layers, hasLength(2));

      final left = controller.document.layers.first;
      final right = controller.document.layers.last;
      expect(left.id, 'video_a');
      expect(left.startMs, 1000);
      expect(left.durationMs, 2200);
      expect(left.endMs, 3200);
      expect(right.id, isNot(left.id));
      expect(right.name, 'Interview (split)');
      expect(right.startMs, 3200);
      expect(right.durationMs, 1800);
      expect(right.sourceInMs, 2700);
      expect(right.sourceUri, left.sourceUri);
      expect(right.effects.single.id, isNot(left.effects.single.id));
      expect(right.masks.single.id, isNot(left.masks.single.id));
      expect(right.effects.single.parameters['sigma'], 4);
      expect(controller.document.selectedLayerId, right.id);

      controller.undo();
      expect(controller.document.layers, hasLength(1));
      expect(controller.document.layers.single.durationMs, 4000);
      expect(controller.document.selectedLayerId, 'video_a');
      controller.dispose();
    });

    test('rejects a clip split outside its bounds or on a locked layer', () {
      final controller = CompositionController(
        document: const CompositionDocument(
          durationMs: 5000,
          playheadMs: 0,
          layers: [
            CompositionLayer(
              id: 'clip',
              name: 'Locked',
              kind: LayerKind.video,
              startMs: 500,
              durationMs: 3000,
              locked: true,
            ),
          ],
          selectedLayerId: 'clip',
        ),
      );
      expect(controller.splitSelectedLayerAtPlayhead(), isFalse);
      controller.setPlayhead(1000);
      expect(controller.splitSelectedLayerAtPlayhead(), isFalse);
      expect(controller.document.layers, hasLength(1));
      controller.dispose();
    });

    test('masks and effects attach to the selected layer', () {
      final controller = CompositionController();
      final id = controller.addLayer(LayerKind.shape);
      controller.addMask(shape: MaskShape.ellipse);
      controller.addEffect('gaussian_blur');
      final layer = controller.document.layers.firstWhere((item) => item.id == id);

      expect(layer.masks.single.shape, MaskShape.ellipse);
      expect(layer.effects.single.effectId, 'gaussian_blur');
      controller.dispose();
    });
  });

  test('graph keyframe updates preserve interpolation metadata and undo as one edit', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 5000,
        frameRate: 25,
        layers: [
          CompositionLayer(
            id: 'target',
            name: 'Target',
            kind: LayerKind.shape,
            keyframeTracks: [
              KeyframeTrack(
                property: 'position.x',
                keyframes: [
                  ScalarKeyframe(
                    timeMs: 400,
                    value: 100,
                    interpolation: Interpolation.cubicBezier,
                    bezier: BezierCurve(x1: 0.2, y1: 0.3, x2: 0.8, y2: 0.9),
                    metadata: {'host': 'after-effects', 'spatial': true},
                  ),
                  ScalarKeyframe(timeMs: 1600, value: 300),
                ],
              ),
            ],
          ),
        ],
        selectedLayerId: 'target',
      ),
    );

    expect(controller.updateKeyframe('position.x', 400, 800, 220), 800);
    expect(
      controller.updateKeyframe(
        'position.x',
        800,
        900,
        240,
        recordHistory: false,
      ),
      900,
    );

    final keys = controller.selectedLayer!.keyframeTracks.single.keyframes;
    expect(keys.first.timeMs, 900);
    expect(keys.first.value, 240);
    expect(keys.first.interpolation, Interpolation.cubicBezier);
    expect(keys.first.bezier.x1, 0.2);
    expect(keys.first.metadata['host'], 'after-effects');
    expect(keys.last.timeMs, 1600);

    controller.undo();
    final restored = controller.selectedLayer!.keyframeTracks.single.keyframes;
    expect(restored.first.timeMs, 400);
    expect(restored.first.value, 100);
  });

  test('graph keyframe updates target effect and mask tracks independently', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 4000,
        layers: [
          CompositionLayer(
            id: 'target',
            name: 'Target',
            kind: LayerKind.shape,
            effects: [
              EffectInstance(
                id: 'blur',
                effectId: 'gaussian_blur',
                name: 'Blur',
                keyframeTracks: [
                  KeyframeTrack(
                    property: 'sigma',
                    keyframes: [
                      ScalarKeyframe(timeMs: 500, value: 2),
                      ScalarKeyframe(timeMs: 1500, value: 8),
                    ],
                  ),
                ],
              ),
            ],
            masks: [
              MaskModel(
                id: 'mask-1',
                name: 'Mask',
                keyframeTracks: [
                  KeyframeTrack(
                    property: 'feather',
                    keyframes: [
                      ScalarKeyframe(timeMs: 500, value: 4),
                      ScalarKeyframe(timeMs: 1500, value: 20),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
        selectedLayerId: 'target',
      ),
    );

    controller.updateKeyframe('sigma', 500, 700, 5, effectId: 'blur');
    controller.updateKeyframe(
      'feather',
      500,
      800,
      9,
      maskId: 'mask-1',
    );

    final layer = controller.selectedLayer!;
    expect(layer.effects.single.keyframeTracks.single.keyframes.first.timeMs, 700);
    expect(layer.effects.single.keyframeTracks.single.keyframes.first.value, 5);
    expect(layer.masks.single.keyframeTracks.single.keyframes.first.timeMs, 800);
    expect(layer.masks.single.keyframeTracks.single.keyframes.first.value, 9);
    expect(layer.keyframeTracks, isEmpty);
  });


  test('preview transform batch edits channels and records one undo step', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 5000,
        layers: [
          CompositionLayer(id: 'shape', name: 'Shape', kind: LayerKind.shape),
        ],
        selectedLayerId: 'shape',
      ),
    );
    controller.updateTransformValues({
      'position.x': 720,
      'position.y': 360,
      'scale.x': 150,
      'scale.y': 125,
    });
    expect(controller.selectedLayer!.transform.position.x, 720);
    expect(controller.selectedLayer!.transform.position.y, 360);
    expect(controller.selectedLayer!.transform.scale.x, 150);
    expect(controller.selectedLayer!.transform.scale.y, 125);
    expect(controller.selectedLayer!.keyframeTracks, isEmpty);
    controller.undo();
    expect(controller.selectedLayer!.transform.position.x, 960);
    expect(controller.selectedLayer!.transform.position.y, 540);
    expect(controller.selectedLayer!.transform.scale.x, 100);
    controller.dispose();
  });

  test('preview auto-key creates editable Position and Rotation tracks', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 5000,
        playheadMs: 1000,
        layers: [
          CompositionLayer(id: 'shape', name: 'Shape', kind: LayerKind.shape),
        ],
        selectedLayerId: 'shape',
      ),
    );
    controller.updateTransformValues({
      'position.x': 700,
      'position.y': 420,
      'rotation.z': 32,
    }, autoKey: true);
    final layer = controller.selectedLayer!;
    expect(layer.keyframeTracks.map((track) => track.property),
        containsAll(['position.x', 'position.y', 'rotation.z']));
    expect(layer.keyframeTracks.firstWhere((t) => t.property == 'position.x')
        .keyframes.single.value, 700);
    expect(layer.valueAt('position.y', 1000), 420);
    expect(layer.valueAt('rotation.z', 1000), 32);

    controller.updateTransformValues({
      'position.x': 760,
      'position.y': 460,
      'rotation.z': 45,
    }, autoKey: true, recordHistory: false);
    controller.undo();
    expect(controller.selectedLayer!.keyframeTracks, isEmpty);
    controller.dispose();
  });

  test('preview drag updates an already animated property at playhead', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 5000,
        playheadMs: 1500,
        layers: [
          CompositionLayer(
            id: 'shape',
            name: 'Shape',
            kind: LayerKind.shape,
            keyframeTracks: [
              KeyframeTrack(
                property: 'position.x',
                keyframes: [
                  ScalarKeyframe(timeMs: 0, value: 200),
                  ScalarKeyframe(timeMs: 3000, value: 800),
                ],
              ),
            ],
          ),
        ],
        selectedLayerId: 'shape',
      ),
    );
    controller.updateTransformValues({'position.x': 520});
    final track = controller.selectedLayer!.keyframeTracks.single;
    expect(track.keyframes, hasLength(3));
    expect(track.keyframes[1].timeMs, 1500);
    expect(track.keyframes[1].value, 520);
    controller.dispose();
  });


  test('preview motion keyframe edits its own timeline time without changing playhead', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 5000,
        playheadMs: 2500,
        layers: [
          CompositionLayer(
            id: 'shape',
            name: 'Shape',
            kind: LayerKind.shape,
            keyframeTracks: [
              KeyframeTrack(
                property: 'position.x',
                keyframes: [
                  ScalarKeyframe(timeMs: 500, value: 200),
                  ScalarKeyframe(timeMs: 1500, value: 500),
                ],
              ),
              KeyframeTrack(
                property: 'position.y',
                keyframes: [
                  ScalarKeyframe(timeMs: 500, value: 300),
                  ScalarKeyframe(timeMs: 1500, value: 600),
                ],
              ),
            ],
          ),
        ],
        selectedLayerId: 'shape',
      ),
    );

    controller.updateTransformValues(
      {'position.x': 420, 'position.y': 380},
      autoKey: true,
      timeMs: 500,
    );
    final layer = controller.selectedLayer!;
    expect(layer.valueAt('position.x', 500), 420);
    expect(layer.valueAt('position.y', 500), 380);
    expect(layer.keyframeTracks.first.keyframes.first.timeMs, 500);
    expect(controller.document.playheadMs, 2500);

    controller.undo();
    expect(controller.selectedLayer!.valueAt('position.x', 500), 200);
    controller.dispose();
  });


  test('mask vertex drags can keyframe and undo as one operation', () {
    final controller = CompositionController(
      document: const CompositionDocument(
        durationMs: 5000,
        playheadMs: 1200,
        layers: [
          CompositionLayer(
            id: 'shape',
            name: 'Shape',
            kind: LayerKind.shape,
            masks: [
              MaskModel(
                id: 'mask',
                name: 'Bezier Mask',
                shape: MaskShape.bezier,
                vertices: [
                  MaskVertex(anchor: Vector2(0.2, 0.2)),
                  MaskVertex(anchor: Vector2(0.8, 0.2)),
                  MaskVertex(anchor: Vector2(0.8, 0.8)),
                  MaskVertex(anchor: Vector2(0.2, 0.8)),
                ],
              ),
            ],
          ),
        ],
        selectedLayerId: 'shape',
      ),
    );

    controller.setMaskVertexAnimatedValue(
      'mask',
      0,
      'anchor.x',
      0.3,
      keyframe: true,
    );
    controller.setMaskVertexAnimatedValue(
      'mask',
      0,
      'anchor.y',
      0.35,
      keyframe: true,
      recordHistory: false,
    );
    final mask = controller.selectedLayer!.masks.single;
    expect(mask.vertexValueAt(0, 'anchor.x', 1200), 0.3);
    expect(mask.vertexValueAt(0, 'anchor.y', 1200), 0.35);
    expect(mask.keyframeTracks, hasLength(2));

    controller.undo();
    final restored = controller.selectedLayer!.masks.single;
    expect(restored.keyframeTracks, isEmpty);
    expect(restored.vertices.first.anchor.x, 0.2);
    controller.dispose();
  });

}
