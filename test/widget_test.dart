import 'package:depthvibe/features/editor/domain/editor_project.dart';
import 'package:flutter/material.dart';
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

    final renderAspect =
        tester.renderObject<RenderAspectRatio>(find.byType(AspectRatio));
    expect(renderAspect.aspectRatio, 9 / 16);
  });
}
