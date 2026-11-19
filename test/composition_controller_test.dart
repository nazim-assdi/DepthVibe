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
