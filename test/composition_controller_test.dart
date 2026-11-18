import 'package:depthvibe/features/composition/application/composition_controller.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
