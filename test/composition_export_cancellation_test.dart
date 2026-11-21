import 'package:depthvibe/features/composition/engine/composition_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompositionExportCancellation', () {
    test('cancels an attached FFmpeg session handler only once', () {
      final cancellation = CompositionExportCancellation();
      var cancelCalls = 0;

      cancellation.attachCancelHandler(() => cancelCalls++);
      cancellation.cancel();
      cancellation.cancel();

      expect(cancellation.isCancelled, isTrue);
      expect(cancelCalls, 1);
      expect(
        () => cancellation.throwIfCancelled(),
        throwsA(isA<CompositionExportCancelled>()),
      );
    });

    test('cancelling before session startup cancels it when attached', () {
      final cancellation = CompositionExportCancellation();
      var cancelCalls = 0;

      cancellation.cancel();
      cancellation.attachCancelHandler(() => cancelCalls++);

      expect(cancelCalls, 1);
      expect(cancellation.isCancelled, isTrue);
    });

    test('a later render phase can replace a completed session handler', () {
      final cancellation = CompositionExportCancellation();
      var firstSessionCancelCalls = 0;
      var secondSessionCancelCalls = 0;

      cancellation.attachCancelHandler(() => firstSessionCancelCalls++);
      cancellation.clearCancelHandler();
      cancellation.attachCancelHandler(() => secondSessionCancelCalls++);
      cancellation.cancel();

      expect(firstSessionCancelCalls, 0);
      expect(secondSessionCancelCalls, 1);
    });
  });
}
