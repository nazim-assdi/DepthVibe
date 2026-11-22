
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/composition/application/composition_controller.dart';
import '../lib/features/composition/domain/composition_models.dart';

void main() {
  group('CompositionController undo and redo', () {
    test('undoes and redoes layer creation', () {
      final controller = CompositionController();

      final layerId = controller.addLayer(LayerKind.video);
      expect(controller.document.layers.single.id, layerId);
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);

      controller.undo();
      expect(controller.document.layers, isEmpty);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.document.layers.single.id, layerId);
      expect(controller.canUndo, isTrue);

      controller.dispose();
    });

    test('playhead and selection changes do not enter edit history', () {
      final controller = CompositionController();
      final layerId = controller.addLayer(LayerKind.video);
      controller.setPlayhead(1200);
      controller.selectLayer(layerId);

      expect(controller.undoHistoryLength, 1);
      controller.undo();
      expect(controller.document.layers, isEmpty);
      controller.dispose();
    });

    test('playhead notifies only preview listeners, not document inspectors', () {
      final controller = CompositionController();
      final layerId = controller.addLayer(LayerKind.video);
      var documentNotifications = 0;
      var playheadNotifications = 0;
      controller.addListener(() => documentNotifications++);
      controller.playhead.addListener(() => playheadNotifications++);

      controller.setPlayhead(1200);

      expect(controller.document.playheadMs, 1200);
      expect(controller.playhead.value, 1200);
      expect(playheadNotifications, 1);
      expect(documentNotifications, 0);
      expect(controller.undoHistoryLength, 1);

      controller.selectLayer(layerId);
      expect(documentNotifications, 1);
      controller.dispose();
    });

    test('opening another document clears the old history', () {
      final controller = CompositionController();
      controller.addLayer(LayerKind.video);
      controller.replaceDocument(const CompositionDocument());

      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      controller.dispose();
    });

    test('history is bounded', () {
      final controller = CompositionController();
      for (var index = 0; index < 100; index++) {
        controller.addLayer(LayerKind.video);
      }
      expect(controller.undoHistoryLength, 80);
      controller.dispose();
    });

    test('a new edit clears the redo stack', () {
      final controller = CompositionController();
      controller.addLayer(LayerKind.video);
      controller.undo();
      expect(controller.canRedo, isTrue);

      controller.addLayer(LayerKind.image);
      expect(controller.canRedo, isFalse);
      controller.dispose();
    });
  });
}
