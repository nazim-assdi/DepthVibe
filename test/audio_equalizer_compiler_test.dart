import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/audio_equalizer_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const compiler = AudioEqualizerCompiler();

  test('neutral EQ does not add filters to the audio chain', () {
    expect(compiler.compile(const AudioSettings()), isEmpty);
  });

  test('compiles only the bands that have non-zero gain', () {
    final filters = compiler.compile(const AudioSettings(
      lowEqDb: 3,
      midEqDb: 0,
      highEqDb: -4.5,
    ));

    expect(filters, [
      'equalizer=f=120:t=q:w=0.8:g=3.00',
      'equalizer=f=8000:t=q:w=0.8:g=-4.50',
    ]);
  });

  test('limits extreme gain values to a safe range', () {
    final filters = compiler.compile(const AudioSettings(
      midEqDb: 60,
    ));

    expect(filters, ['equalizer=f=1000:t=q:w=1.0:g=24.00']);
  });
}
