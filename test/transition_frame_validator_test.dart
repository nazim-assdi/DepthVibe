import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/transition_frame_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = TransitionFrameValidator();

  test('snaps transition times to the nearest composition frame', () {
    expect(validator.snapToFrame(101, 30), 100);
    expect(validator.snapDurationToFrame(350, 30), 367);
    expect(validator.snapToFrame(123, 24), 125);
    expect(validator.snapDurationToFrame(333, 24), 333);
  });

  test('validates aligned transition inside both clip ranges', () {
    const document = CompositionDocument(
      frameRate: 30,
      durationMs: 3000,
      layers: [
        CompositionLayer(
          id: 'from',
          name: 'From',
          kind: LayerKind.video,
          durationMs: 3000,
        ),
        CompositionLayer(
          id: 'to',
          name: 'To',
          kind: LayerKind.image,
          durationMs: 3000,
        ),
      ],
      transitions: [
        CompositionTransition(
          id: 'dissolve',
          fromLayerId: 'from',
          toLayerId: 'to',
          startMs: 500,
          durationMs: 500,
        ),
      ],
    );

    final report = validator.validate(document);
    expect(report.isValid, isTrue);
    expect(report.issues, isEmpty);
  });

  test('reports off-grid start and duration as frame warnings', () {
    const document = CompositionDocument(
      frameRate: 30,
      durationMs: 3000,
      layers: [
        CompositionLayer(
          id: 'from',
          name: 'From',
          kind: LayerKind.video,
          durationMs: 3000,
        ),
        CompositionLayer(
          id: 'to',
          name: 'To',
          kind: LayerKind.video,
          durationMs: 3000,
        ),
      ],
      transitions: [
        CompositionTransition(
          id: 'off-grid',
          fromLayerId: 'from',
          toLayerId: 'to',
          startMs: 101,
          durationMs: 350,
        ),
      ],
    );

    final report = validator.validate(document);
    expect(report.isValid, isTrue);
    expect(report.warningCount, 2);
    expect(
      report.issues.map((issue) => issue.code),
      containsAll(['start_not_frame_aligned', 'duration_not_frame_aligned']),
    );
  });

  test('reports missing layer references and transitions outside clip ranges', () {
    const document = CompositionDocument(
      frameRate: 24,
      durationMs: 3000,
      layers: [
        CompositionLayer(
          id: 'from',
          name: 'From',
          kind: LayerKind.video,
          startMs: 0,
          durationMs: 1000,
        ),
        CompositionLayer(
          id: 'to',
          name: 'To',
          kind: LayerKind.video,
          startMs: 1000,
          durationMs: 1000,
        ),
      ],
      transitions: [
        CompositionTransition(
          id: 'no-overlap',
          fromLayerId: 'from',
          toLayerId: 'to',
          startMs: 1000,
          durationMs: 500,
        ),
        CompositionTransition(
          id: 'missing',
          fromLayerId: 'from',
          toLayerId: 'deleted-layer',
          startMs: 500,
          durationMs: 250,
        ),
      ],
    );

    final report = validator.validate(document);
    expect(report.errorCount, 1);
    expect(report.warningCount, 1);
    expect(report.issues.map((issue) => issue.code), contains('missing_layer'));
    expect(
      report.issues.map((issue) => issue.code),
      contains('outside_shared_clip_range'),
    );
  });
}
