import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/color_grade_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(ColorGradePreview.clearCache);

  test('reuses a color-filter matrix for the same effect instance and time', () {
    const grade = EffectInstance(
      id: 'grade-1',
      effectId: 'color_grade',
      name: 'Grade',
      parameters: {'contrast': 1.4, 'saturation': 1.2},
    );

    final first = ColorGradePreview.filterFor(grade, 1000);
    final second = ColorGradePreview.filterFor(grade, 1000);

    expect(first, isNotNull);
    expect(identical(first, second), isTrue);
    expect(ColorGradePreview.cacheMisses, 1);
    expect(ColorGradePreview.cacheHits, 1);
    expect(ColorGradePreview.cacheSize, 1);
  });

  test('separates keyframe times and distinct effect instances', () {
    const firstGrade = EffectInstance(
      id: 'same-id',
      effectId: 'color_grade',
      name: 'Grade A',
      parameters: {'contrast': 1.2},
    );
    const secondGrade = EffectInstance(
      id: 'same-id',
      effectId: 'color_grade',
      name: 'Grade B',
      parameters: {'contrast': 1.8},
    );

    final first = ColorGradePreview.filterFor(firstGrade, 0);
    final atNextTime = ColorGradePreview.filterFor(firstGrade, 1000);
    final second = ColorGradePreview.filterFor(secondGrade, 0);

    expect(first, isNotNull);
    expect(atNextTime, isNotNull);
    expect(second, isNotNull);
    expect(identical(first, atNextTime), isFalse);
    expect(identical(first, second), isFalse);
    expect(ColorGradePreview.cacheMisses, 3);
  });

  test('bounds the cache and does not cache disabled effects', () {
    const grade = EffectInstance(
      id: 'grade-2',
      effectId: 'color_grade',
      name: 'Grade',
      parameters: {'contrast': 1.1},
    );
    const disabled = EffectInstance(
      id: 'grade-disabled',
      effectId: 'color_grade',
      name: 'Disabled',
      enabled: false,
    );

    expect(ColorGradePreview.filterFor(disabled, 0), isNull);
    for (var timeMs = 0; timeMs < ColorGradePreview.maxCachedFilters + 25; timeMs++) {
      ColorGradePreview.filterFor(grade, timeMs);
    }

    expect(ColorGradePreview.cacheSize, ColorGradePreview.maxCachedFilters);
    expect(ColorGradePreview.cacheHits, 0);
  });
}
