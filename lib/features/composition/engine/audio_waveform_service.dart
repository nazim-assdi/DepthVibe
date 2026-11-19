import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Generates cached, local waveform thumbnails from audio media.
class AudioWaveformService {
  const AudioWaveformService();

  Future<File?> generate(
    String sourcePath, {
    int width = 1200,
    int height = 72,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final sourceStat = await source.stat();
    final cacheDirectory = await getTemporaryDirectory();
    final key = sourcePath.hashCode.toUnsigned(32).toRadixString(16);
    final output = File(
      cacheDirectory.path + Platform.pathSeparator +
          'depthvibe_waveform_${key}_${width}x${height}.png',
    );
    if (await output.exists()) {
      final cachedStat = await output.stat();
      if (!cachedStat.modified.isBefore(sourceStat.modified) &&
          await output.length() > 0) {
        return output;
      }
    }

    final command = '-hide_banner -loglevel error -y -i ' +
        _quote(sourcePath) +
        ' -filter_complex ' +
        _quote(
          'aformat=channel_layouts=mono,'
          'showwavespic=s=${width}x${height}:'
          'colors=0x57D6C0:scale=sqrt,format=rgba',
        ) +
        ' -frames:v 1 ' +
        _quote(output.path);

    final session = await FFmpegKit.execute(command);
    if (!ReturnCode.isSuccess(session.getReturnCode()) ||
        !await output.exists() ||
        await output.length() == 0) {
      return null;
    }
    return output;
  }

  String _quote(String value) =>
      "'" + value.replaceAll("'", "'\\''") + "'";
}
