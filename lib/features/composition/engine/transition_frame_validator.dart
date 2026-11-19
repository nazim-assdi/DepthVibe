import '../domain/composition_models.dart';

enum TransitionIssueSeverity { warning, error }

class TransitionValidationIssue {
  const TransitionValidationIssue({
    required this.transitionId,
    required this.code,
    required this.message,
    required this.severity,
  });

  final String transitionId;
  final String code;
  final String message;
  final TransitionIssueSeverity severity;
}

class TransitionValidationReport {
  const TransitionValidationReport(this.issues);

  final List<TransitionValidationIssue> issues;

  int get errorCount => issues
      .where((issue) => issue.severity == TransitionIssueSeverity.error)
      .length;

  int get warningCount => issues
      .where((issue) => issue.severity == TransitionIssueSeverity.warning)
      .length;

  bool get isValid => errorCount == 0;
}

/// Validates transition timing against the composition's actual frame grid.
class TransitionFrameValidator {
  const TransitionFrameValidator();

  int snapToFrame(int milliseconds, double frameRate) {
    if (frameRate <= 0) return milliseconds;
    final frames = (milliseconds * frameRate / 1000).round();
    return (frames * 1000 / frameRate).round();
  }

  int snapDurationToFrame(int milliseconds, double frameRate) {
    if (frameRate <= 0) return milliseconds;
    final frames = (milliseconds * frameRate / 1000)
        .round()
        .clamp(1, 1 << 30);
    return (frames * 1000 / frameRate).round();
  }

  TransitionValidationReport validate(CompositionDocument document) {
    final issues = <TransitionValidationIssue>[];
    if (document.frameRate <= 0) {
      return TransitionValidationReport([
        const TransitionValidationIssue(
          transitionId: '*',
          code: 'invalid_frame_rate',
          message: 'Composition frame rate must be greater than zero.',
          severity: TransitionIssueSeverity.error,
        ),
      ]);
    }

    final layers = {
      for (final layer in document.layers) layer.id: layer,
    };
    for (final transition in document.transitions) {
      void add(
        String code,
        String message, [
        TransitionIssueSeverity severity = TransitionIssueSeverity.error,
      ]) {
        issues.add(TransitionValidationIssue(
          transitionId: transition.id,
          code: code,
          message: message,
          severity: severity,
        ));
      }

      final from = layers[transition.fromLayerId];
      final to = layers[transition.toLayerId];
      if (from == null || to == null) {
        add(
          'missing_layer',
          'Transition references a layer that no longer exists.',
        );
        continue;
      }
      if (from.id == to.id) {
        add('same_layer', 'A transition needs two different layers.');
      }
      if (transition.durationMs <= 0) {
        add('invalid_duration', 'Transition duration must be positive.');
        continue;
      }

      final alignedStart = snapToFrame(
        transition.startMs,
        document.frameRate,
      );
      final alignedDuration = snapDurationToFrame(
        transition.durationMs,
        document.frameRate,
      );
      if (alignedStart != transition.startMs) {
        add(
          'start_not_frame_aligned',
          'Start time should be $alignedStart ms at this frame rate.',
          TransitionIssueSeverity.warning,
        );
      }
      if (alignedDuration != transition.durationMs) {
        add(
          'duration_not_frame_aligned',
          'Duration should be $alignedDuration ms at this frame rate.',
          TransitionIssueSeverity.warning,
        );
      }

      final endMs = transition.startMs + transition.durationMs;
      if (transition.startMs < 0 || endMs > document.durationMs) {
        add(
          'outside_composition',
          'Transition extends outside the composition duration.',
        );
      }
      if (transition.startMs < from.startMs ||
          transition.startMs < to.startMs ||
          endMs > from.endMs ||
          endMs > to.endMs) {
        add(
          'outside_shared_clip_range',
          'Transition is not fully inside the active range of both clips.',
          TransitionIssueSeverity.warning,
        );
      }
    }
    return TransitionValidationReport(List.unmodifiable(issues));
  }
}
