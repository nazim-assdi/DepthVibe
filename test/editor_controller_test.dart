import 'package:flutter_test/flutter_test.dart';
import 'package:depthvibe/features/editor/application/editor_controller.dart';
import 'package:depthvibe/features/editor/domain/editor_project.dart';

void main() {
  group('EditorController', () {
    test('loads a video and initializes the source duration', () {
      final controller = EditorController();
      controller.loadVideo('/media/source.mp4');
      controller.setSourceDuration(const Duration(seconds: 12));

      expect(controller.project.hasVideo, isTrue);
      expect(controller.project.trimInMs, 0);
      expect(controller.project.trimOutMs, 12000);
      controller.dispose();
    });

    test('keeps trim in and out in a valid order', () {
      final controller = EditorController();
      controller.loadVideo('/media/source.mp4');
      controller.setSourceDuration(const Duration(seconds: 10));
      controller.setTrimIn(9000);
      controller.setTrimOut(2000);

      expect(controller.project.trimOutMs, greaterThan(controller.project.trimInMs));
      expect(controller.project.hasValidTrim, isTrue);
      controller.dispose();
    });

    test('accepts the supported speed interval and rejects invalid speed', () {
      final controller = EditorController();
      controller.setSpeed(0.25);
      expect(controller.project.speed, 0.25);
      controller.setSpeed(2);
      expect(controller.project.speed, 2);
      expect(() => controller.setSpeed(2.5), throwsRangeError);
      controller.dispose();
    });

    test('rotation cycles through quarter turns', () {
      final controller = EditorController();
      controller.rotateClockwise();
      controller.rotateClockwise();
      expect(controller.project.rotationDegrees, 180);
      controller.rotateClockwise();
      controller.rotateClockwise();
      expect(controller.project.rotationDegrees, 0);
      controller.dispose();
    });

    test('split markers are sorted and unique', () {
      final controller = EditorController();
      controller.loadVideo('/media/source.mp4');
      controller.setSourceDuration(const Duration(seconds: 20));
      controller.setPlayhead(const Duration(seconds: 8));
      controller.addSplitMarker();
      controller.setPlayhead(const Duration(seconds: 3));
      controller.addSplitMarker();
      controller.addSplitMarker();

      expect(controller.project.splitMarkersMs, [3000, 8000]);
      controller.dispose();
    });

    test('project settings survive JSON round-trip', () {
      final original = const EditorProject(
        videoPath: '/media/clip.mp4',
        sourceDurationMs: 10000,
        trimInMs: 1000,
        trimOutMs: 9000,
        speed: 1.5,
        rotationDegrees: 90,
        muted: true,
        aspect: OutputAspect.portrait9x16,
        canvasFit: CanvasFit.fill,
        title: 'DepthVibe',
        caption: 'N Tech',
        splitMarkersMs: [2500, 5000],
      );
      final decoded = EditorProject.fromJson(original.toJson());

      expect(decoded.toJson(), original.toJson());
    });
  });
}
