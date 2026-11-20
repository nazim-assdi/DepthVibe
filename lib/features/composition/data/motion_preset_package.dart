import 'dart:convert';

import '../domain/composition_models.dart';
import '../engine/composition_project_codec.dart';

/// Portable DepthVibe motion/effect package (.dvmpreset). It keeps editable
/// animation tracks and inert native Adobe effect descriptors. Host plug-in
/// binaries and external media files are never embedded.
class MotionPresetPackage {
  MotionPresetPackage._();

  static const format = 'DepthVibe.MotionPreset';
  static const schemaVersion = 1;
  static const maxBytes = 16 * 1024 * 1024;

  static String encode(CompositionLayer layer, {String? name}) {
    if (layer.effects.length > CompositionProjectCodec.maxEffectsPerLayer ||
        layer.keyframeTracks.length > 256) {
      throw const FormatException('This layer contains too much preset data.');
    }
    final document = CompositionDocument(
      name: name ?? layer.name,
      width: 1920,
      height: 1080,
      durationMs: layer.durationMs.clamp(1, 86400000).toInt(),
      layers: [layer],
      selectedLayerId: layer.id,
    );
    final payload = <String, Object?>{
      'format': format,
      'schemaVersion': schemaVersion,
      'name': name ?? layer.name,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'layer': CompositionProjectCodec.encodeDocument(document),
      'compatibility': {
        'nativeAdobeEffects': true,
        'pluginBinariesEmbedded': false,
        'expressionsExecuted': false,
      },
    };
    final result = const JsonEncoder.withIndent('  ').convert(payload);
    if (utf8.encode(result).length > maxBytes) {
      throw const FormatException('Preset package exceeds the 16 MB limit.');
    }
    return result;
  }

  static CompositionLayer decode(String source) {
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('Preset package exceeds the 16 MB limit.');
    }
    final raw = jsonDecode(source);
    if (raw is! Map) {
      throw const FormatException('Invalid DepthVibe preset package.');
    }
    if (raw['format'] != format ||
        (raw['schemaVersion'] as num?)?.toInt() != schemaVersion) {
      throw const FormatException('Unsupported DepthVibe preset format/version.');
    }
    final document = CompositionProjectCodec.decodeDocument(raw['layer']);
    if (document.layers.length != 1) {
      throw const FormatException('A motion preset must contain exactly one layer.');
    }
    final layer = document.layers.single;
    if (layer.effects.length > CompositionProjectCodec.maxEffectsPerLayer ||
        layer.keyframeTracks.length > 256) {
      throw const FormatException('Preset package exceeds supported effect/keyframe limits.');
    }
    return layer;
  }
}
