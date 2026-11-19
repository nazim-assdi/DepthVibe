import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/audio_bus_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const compiler = AudioBusCompiler();

  test('a neutral bus adds no extra processing filters', () {
    expect(
      compiler.compile(const AudioBus(id: 'master', name: 'Master')),
      isEmpty,
    );
  });

  test('compiles bus gain, pan, compressor and limiter filters', () {
    final filters = compiler.compile(const AudioBus(
      id: 'music',
      name: 'Music',
      gainDb: 3,
      pan: -0.25,
      compressorEnabled: true,
      compressorThresholdDb: -18,
      compressorRatio: 4,
      compressorAttackMs: 10,
      compressorReleaseMs: 200,
      makeupGainDb: 2,
      limiterEnabled: true,
      limiterCeilingDb: -1,
    ));

    expect(filters.first, startsWith('volume='));
    expect(filters[1], startsWith('pan=stereo'));
    expect(filters[2], contains('acompressor='));
    expect(filters[2], contains('ratio=4.00'));
    expect(filters[3], startsWith('alimiter=limit='));
  });

  test('clamps dynamics values before generating FFmpeg filters', () {
    final filters = compiler.compile(const AudioBus(
      id: 'extreme',
      name: 'Extreme',
      compressorEnabled: true,
      compressorThresholdDb: -90,
      compressorRatio: 99,
      compressorAttackMs: 0,
      compressorReleaseMs: 9000,
      makeupGainDb: 50,
      limiterEnabled: true,
      limiterCeilingDb: 6,
    ));

    expect(filters, hasLength(2));
    expect(filters.first, contains('threshold=0.001000'));
    expect(filters.first, contains('ratio=20.00'));
    expect(filters.first, contains('attack=0.1'));
    expect(filters.first, contains('release=2000.0'));
    expect(filters.last, contains('limit=1.000000'));
  });
}
