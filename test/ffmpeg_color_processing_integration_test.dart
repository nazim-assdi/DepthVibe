import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:depthvibe/features/composition/data/effect_catalog.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/ffmpeg_filter_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

const _frameInput = [
  '-hide_banner',
  '-loglevel',
  'error',
  '-f',
  'lavfi',
  '-i',
  'testsrc2=s=48x32:d=0.25:r=24',
];

Future<ProcessResult> _runFfmpeg(
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final process = await Process.start(
    'ffmpeg',
    arguments,
    runInShell: false,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();

  try {
    final exitCode = await process.exitCode.timeout(timeout);
    return ProcessResult(
      process.pid,
      exitCode,
      await stdoutFuture,
      await stderrFuture,
    );
  } on TimeoutException {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    rethrow;
  }
}

Future<void> _expectFilterPasses(String filter) async {
  final result = await _runFfmpeg([
    ..._frameInput,
    '-vf',
    filter,
    '-frames:v',
    '3',
    '-f',
    'null',
    '-',
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'FFmpeg failed to process filter:\n' +
        filter + '\n' + result.stderr.toString(),
  );
}

void main() {
  late bool ffmpegAvailable;
  final temporaryDirectories = <Directory>[];

  setUpAll(() async {
    try {
      final result = await Process.run(
        'ffmpeg',
        const ['-version'],
        runInShell: false,
      ).timeout(const Duration(seconds: 3));
      ffmpegAvailable = result.exitCode == 0;
    } catch (_) {
      ffmpegAvailable = false;
    }
  });

  tearDownAll(() async {
    for (final directory in temporaryDirectories) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('FFmpeg processes compiled primary wheels and animated controls', () async {
    if (!ffmpegAvailable) return;
    const layer = CompositionLayer(
      id: 'grade-smoke',
      name: 'Primary grade',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'grade-1',
          effectId: 'color_grade',
          name: 'Primary Color Grade',
          parameters: {
            'lift_r': 0.16,
            'lift_g': -0.08,
            'lift_b': 0.04,
            'gamma_r': 0.05,
            'gamma_g': 0.12,
            'gamma_b': -0.04,
            'gain_r': 0.08,
            'gain_g': -0.03,
            'gain_b': 0.02,
            'offset_r': 0.02,
            'offset_g': -0.01,
            'offset_b': 0.01,
            'temperature': 0.12,
            'tint': -0.06,
            'contrast': 1.2,
            'brightness': 0.02,
            'master_gamma': 1.1,
            'saturation': 1.25,
          },
        ),
      ],
    );
    final filter = const FfmpegFilterCompiler()
        .compileEffects(layer, timeMs: 0)
        .single;
    await _expectFilterPasses(filter);
  });

  test('FFmpeg processes generated master and RGB curve control points', () async {
    if (!ffmpegAvailable) return;
    final definition = EffectCatalog.find('color_curves')!;
    final parameters = {
      for (final parameter in definition.parameters)
        parameter.id: parameter.defaultValue,
      'master_2': 0.62,
      'red_1': 0.18,
      'green_3': 0.88,
      'blue_2': 0.42,
    };
    final layer = CompositionLayer(
      id: 'curve-smoke',
      name: 'Custom curves',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'curves-1',
          effectId: 'color_curves',
          name: 'Primary Curves',
          parameters: parameters,
        ),
      ],
    );
    final filter = const FfmpegFilterCompiler()
        .compileEffects(layer, timeMs: 0)
        .single;
    expect(filter, contains('interp=natural'));
    await _expectFilterPasses(filter);
  });

  test(
    'FFmpeg processes all five supported 3D LUT interpolation modes',
    () async {
      if (!ffmpegAvailable) return;
      final directory = await Directory.systemTemp.createTemp(
        'depthvibe-color-lut-',
      );
      temporaryDirectories.add(directory);
      final lutFile = File(
        directory.path + Platform.pathSeparator + 'identity.cube',
      );
      await lutFile.writeAsString('''
TITLE "Identity"
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
''');

      for (final mode in const [
        'nearest',
        'trilinear',
        'tetrahedral',
        'pyramid',
        'prism',
      ]) {
        final layer = CompositionLayer(
          id: 'lut-' + mode,
          name: 'LUT ' + mode,
          kind: LayerKind.video,
          effects: [
            EffectInstance(
              id: 'lut-1',
              effectId: 'color_lut',
              name: '3D LUT',
              assetUri: lutFile.path,
              assetInterpolation: mode,
            ),
          ],
        );
        final filter = const FfmpegFilterCompiler()
            .compileEffects(layer, timeMs: 0)
            .single;
        expect(filter, contains('interp=' + mode));
        await _expectFilterPasses(filter);
      }
    },
  );

  test('FFmpeg processes animated primary wheels per frame', () async {
    if (!ffmpegAvailable) return;
    const layer = CompositionLayer(
      id: 'animated-grade-smoke',
      name: 'Animated color wheel',
      kind: LayerKind.video,
      effects: [
        EffectInstance(
          id: 'grade-animated',
          effectId: 'color_grade',
          name: 'Primary Color Grade',
          parameters: {
            'lift_r': 0,
            'lift_g': 0,
            'lift_b': 0,
            'gamma_r': 0,
            'gamma_g': 0,
            'gamma_b': 0,
            'gain_r': 0,
            'gain_g': 0,
            'gain_b': 0,
            'offset_r': 0,
            'offset_g': 0,
            'offset_b': 0,
          },
          keyframeTracks: [
            KeyframeTrack(
              property: 'lift_r',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 0),
                ScalarKeyframe(timeMs: 1000, value: 0.35),
              ],
            ),
          ],
        ),
      ],
    );
    final filter = const FfmpegFilterCompiler()
        .compileEffects(layer, timeMs: 0)
        .single;
    expect(filter, contains('if(lt(T,'));
    await _expectFilterPasses(filter);
  });

  test('color processing timeout kills a deliberately slow FFmpeg process', () async {
    if (!ffmpegAvailable) return;
    final stopwatch = Stopwatch()..start();
    await expectLater(
      _runFfmpeg(
        const [
          '-hide_banner',
          '-loglevel',
          'error',
          '-re',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=s=16x16:r=1:d=5',
          '-t',
          '5',
          '-f',
          'null',
          '-',
        ],
        timeout: const Duration(milliseconds: 250),
      ),
      throwsA(isA<TimeoutException>()),
    );
    stopwatch.stop();
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 4)),
      reason: 'The test process should be terminated shortly after timeout.',
    );
  });
}
