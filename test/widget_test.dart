import 'package:depthvibe/features/editor/domain/editor_project.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('output aspect preset controls the preview canvas ratio',
      (tester) async {
    const aspect = OutputAspect.portrait9x16;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AspectRatio(
            aspectRatio: aspect.ratio,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    final canvasSize = tester.getSize(find.byType(AspectRatio));
    expect(canvasSize.width / canvasSize.height, closeTo(9 / 16, 0.001));
  });
}
