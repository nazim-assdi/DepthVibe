import 'package:depthvibe/features/composition/engine/cube_lut_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a complete 2x2x2 3D cube LUT', () {
    const cube = '''
TITLE "Identity LUT"
LUT_3D_SIZE 2
DOMAIN_MIN 0.0 0.0 0.0
DOMAIN_MAX 1.0 1.0 1.0
0.0 0.0 0.0
1.0 0.0 0.0
0.0 1.0 0.0
1.0 1.0 0.0
0.0 0.0 1.0
1.0 0.0 1.0
0.0 1.0 1.0
1.0 1.0 1.0
''';
    final info = CubeLutValidator.parse(cube);
    expect(info.title, 'Identity LUT');
    expect(info.size, 2);
    expect(info.entryCount, 8);
  });

  test('rejects a cube LUT with missing samples', () {
    const cube = '''
LUT_3D_SIZE 2
0 0 0
1 0 0
''';
    expect(
      () => CubeLutValidator.parse(cube),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid DOMAIN_MIN / DOMAIN_MAX ordering', () {
    const cube = '''
LUT_3D_SIZE 2
DOMAIN_MIN 1.0 0.0 0.0
DOMAIN_MAX 1.0 1.0 1.0
0 0 0
1 0 0
0 1 0
1 1 0
0 0 1
1 0 1
0 1 1
1 1 1
''';
    expect(
      () => CubeLutValidator.parse(cube),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects oversized LUT text before parsing samples', () {
    expect(
      () => CubeLutValidator.parse(
        ''.padRight(CubeLutValidator.maxContentCharacters + 1),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects one-dimensional LUT declarations', () {
    expect(
      () => CubeLutValidator.parse('LUT_1D_SIZE 16\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects non-finite LUT sample values', () {
    const cube = '''
LUT_3D_SIZE 2
0 0 0
1 0 0
0 1 0
1 1 0
0 0 1
1 0 1
0 1 1
NaN 1 1
''';
    expect(
      () => CubeLutValidator.parse(cube),
      throwsA(isA<FormatException>()),
    );
  });
}
