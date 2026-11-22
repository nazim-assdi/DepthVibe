import 'package:depthvibe/app/depthvibe_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DepthVibe 3D preview performance modes', () {
    test('compatibility mode uses the smallest preview workload', () {
      expect(
        DepthVibePerformanceMode.compatibility.maximumPreviewDimension,
        320,
      );
      expect(DepthVibePerformanceMode.compatibility.gpuRenderScale, 0.55);
      expect(
        DepthVibePerformanceMode.compatibility.enableVideoHardwareAcceleration,
        isFalse,
      );
      expect(DepthVibePerformanceMode.compatibility.videoOutputScale, 0.5);
      expect(DepthVibePerformanceMode.compatibility.videoHardwareDecoder, 'no');
    });

    test('balanced mode stays between compatibility and quality', () {
      expect(
        DepthVibePerformanceMode.balanced.maximumPreviewDimension,
        480,
      );
      expect(DepthVibePerformanceMode.balanced.gpuRenderScale, 0.75);
      expect(
        DepthVibePerformanceMode.balanced.enableVideoHardwareAcceleration,
        isTrue,
      );
      expect(DepthVibePerformanceMode.balanced.videoOutputScale, 0.75);
      expect(DepthVibePerformanceMode.balanced.videoHardwareDecoder, 'auto');
    });

    test('quality mode requests the largest preview dimensions', () {
      expect(
        DepthVibePerformanceMode.quality.maximumPreviewDimension,
        640,
      );
      expect(DepthVibePerformanceMode.quality.gpuRenderScale, 1.0);
      expect(
        DepthVibePerformanceMode.quality.enableVideoHardwareAcceleration,
        isTrue,
      );
      expect(DepthVibePerformanceMode.quality.videoOutputScale, 1.0);
      expect(DepthVibePerformanceMode.quality.videoHardwareDecoder, 'auto');
    });

    test('preview workload increases monotonically with quality', () {
      final modes = DepthVibePerformanceMode.values;
      for (var index = 1; index < modes.length; index++) {
        expect(
          modes[index].maximumPreviewDimension,
          greaterThan(modes[index - 1].maximumPreviewDimension),
        );
        expect(
          modes[index].gpuRenderScale,
          greaterThan(modes[index - 1].gpuRenderScale),
        );
      }
    });
  });
}
