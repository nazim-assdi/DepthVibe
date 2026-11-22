import 'package:depthvibe/features/editor/application/editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorController offline editing', () {
    test('imports media metadata and edits the timeline without a player', () {
      final controller = EditorController();

      controller.loadVideo('C:/Media/clip.mp4');
      controller.setSourceDuration(const Duration(seconds: 48));
      controller.setPlayhead(const Duration(seconds: 12));
      controller.addSplitMarker();
      controller.setTrimIn(2000);
      controller.setTrimOut(30000);
      controller.setSpeed(1.25);
      controller.rotateClockwise();
      controller.setTitle('Offline edit');
      controller.setCaption('CPU-only preview');

      expect(controller.project.hasVideo, isTrue);
      expect(controller.project.videoPath, 'C:/Media/clip.mp4');
      expect(controller.project.sourceDurationMs, 48000);
      expect(controller.playheadMs, 12000);
      expect(controller.project.splitMarkersMs, [12000]);
      expect(controller.project.trimInMs, 2000);
      expect(controller.project.trimOutMs, 30000);
      expect(controller.project.speed, 1.25);
      expect(controller.project.rotationDegrees, 90);
      expect(controller.project.title, 'Offline edit');
      expect(controller.project.caption, 'CPU-only preview');

      controller.dispose();
    });

    test('playhead and split markers remain usable without playback', () {
      final controller = EditorController();
      controller.loadVideo('clip.mp4');
      controller.setSourceDuration(const Duration(seconds: 10));
      controller.setPlayhead(const Duration(seconds: 3));
      controller.addSplitMarker();
      controller.setPlayhead(const Duration(seconds: 7));
      controller.addSplitMarker();
      controller.setPlayhead(const Duration(seconds: 3));
      controller.removeSplitMarker(3000);

      expect(controller.project.splitMarkersMs, [7000]);
      expect(controller.playheadMs, 3000);

      controller.dispose();
    });
  });
}
