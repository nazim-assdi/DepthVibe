import 'package:flutter_test/flutter_test.dart';

import '../lib/features/composition/data/motion_preset_package.dart';
import '../lib/features/composition/domain/composition_models.dart';

void main() {
  group('MotionPresetPackage', () {
    test('round-trips editable keyframes and native Adobe effect descriptors', () {
      const source = CompositionLayer(
        id: 'preset-layer',
        name: 'Native Glow Entrance',
        kind: LayerKind.text,
        startMs: 500,
        durationMs: 2400,
        textContent: 'DepthVibe',
        keyframeTracks: [
          KeyframeTrack(
            property: 'position.x',
            keyframes: [
              ScalarKeyframe(
                timeMs: 500,
                value: -960,
                interpolation: Interpolation.cubicBezier,
                bezier: BezierCurve(x1: 0.4, y1: 0, x2: 0.2, y2: 1),
              ),
              ScalarKeyframe(timeMs: 1200, value: 960),
            ],
          ),
        ],
        effects: [
          EffectInstance(
            id: 'native-glow',
            effectId: 'native_effect',
            name: 'Vendor Super Glow',
            enabled: true,
            nativeDescriptor: {
              'hostApp': 'aftereffects-beta',
              'matchName': 'Vendor.SuperGlow',
              'displayName': 'Super Glow',
              'category': 'Stylize',
              'parameters': [
                {
                  'index': 0,
                  'matchName': 'Vendor.SuperGlow-0001',
                  'name': 'Radius',
                  'displayName': 'Radius',
                  'value': 24.0,
                  'minValue': 0.0,
                  'maxValue': 100.0,
                  'unitsText': 'px',
                  'keyframes': [
                    {'timeMs': 500, 'value': 12.0},
                    {'timeMs': 1500, 'value': 24.0},
                  ],
                },
              ],
            },
          ),
        ],
      );

      final encoded = MotionPresetPackage.encode(source, name: 'Glow Entrance');
      expect(encoded, contains('DepthVibe.MotionPreset'));
      expect(encoded, contains('Vendor.SuperGlow'));

      final decoded = MotionPresetPackage.decode(encoded);
      expect(decoded.name, source.name);
      expect(decoded.textContent, 'DepthVibe');
      expect(decoded.keyframeTracks.single.property, 'position.x');
      expect(decoded.keyframeTracks.single.keyframes, hasLength(2));
      expect(decoded.keyframeTracks.single.keyframes.first.interpolation,
          Interpolation.cubicBezier);
      expect(decoded.effects.single.nativeDescriptor['matchName'], 'Vendor.SuperGlow');
      final radius = (decoded.effects.single.nativeDescriptor['parameters'] as List).single as Map;
      expect(radius['maxValue'], 100.0);
      expect((radius['keyframes'] as List), hasLength(2));
    });

    test('rejects unknown formats and unsupported schema versions', () {
      expect(
        () => MotionPresetPackage.decode('{"format":"Unknown","schemaVersion":1}'),
        throwsFormatException,
      );
      expect(
        () => MotionPresetPackage.decode(
          '{"format":"DepthVibe.MotionPreset","schemaVersion":99}',
        ),
        throwsFormatException,
      );
    });

    test('rejects package content above the safe size limit', () {
      final oversized = ' ' * (MotionPresetPackage.maxBytes + 1);
      expect(() => MotionPresetPackage.decode(oversized), throwsFormatException);
    });
  });
}
