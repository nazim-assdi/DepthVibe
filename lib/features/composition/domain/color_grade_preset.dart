import 'dart:convert';

import 'composition_models.dart';

/// A portable, versioned package of the color settings used by one layer.
class ColorGradePreset {
  const ColorGradePreset({
    required this.name,
    required this.outputProfile,
    this.primary,
    this.curves,
    this.lut,
  });

  static const formatId = 'DepthVibe.ColorGradePreset';
  static const schemaVersion = 1;
  static const maxPresetCharacters = 26 * 1024 * 1024;
  static const maxLutCharacters = 24 * 1024 * 1024;
  static const maxKeyframesPerTrack = 10000;
  static const maxTracksPerEffect = 64;

  static const primaryParameterIds = <String>{
    'lift_r', 'lift_g', 'lift_b',
    'gamma_r', 'gamma_g', 'gamma_b',
    'gain_r', 'gain_g', 'gain_b',
    'offset_r', 'offset_g', 'offset_b',
    'temperature', 'tint', 'contrast', 'brightness',
    'master_gamma', 'saturation',
  };

  static const curveParameterIds = <String>{
    'master_0', 'master_1', 'master_2', 'master_3', 'master_4',
    'red_0', 'red_1', 'red_2', 'red_3', 'red_4',
    'green_0', 'green_1', 'green_2', 'green_3', 'green_4',
    'blue_0', 'blue_1', 'blue_2', 'blue_3', 'blue_4',
  };

  static const lutInterpolations = <String>{
    'nearest', 'trilinear', 'tetrahedral', 'pyramid', 'prism',
  };

  final String name;
  final ColorOutputProfile outputProfile;
  final ColorGradePresetEffect? primary;
  final ColorGradePresetEffect? curves;
  final ColorGradePresetLut? lut;

  factory ColorGradePreset.fromLayer(
    CompositionLayer layer, {
    required ColorOutputProfile outputProfile,
    String? name,
  }) {
    EffectInstance? findEffect(String id) {
      for (final effect in layer.effects) {
        if (effect.effectId == id) return effect;
      }
      return null;
    }

    final primaryEffect = findEffect('color_grade');
    final curveEffect = findEffect('color_curves');
    final lutEffect = findEffect('color_lut');
    return ColorGradePreset(
      name: (name ?? layer.name).trim().isEmpty
          ? 'Color Grade'
          : (name ?? layer.name).trim(),
      outputProfile: outputProfile,
      primary: primaryEffect == null
          ? null
          : ColorGradePresetEffect.fromEffect(
              primaryEffect,
              allowedParameters: primaryParameterIds,
            ),
      curves: curveEffect == null
          ? null
          : ColorGradePresetEffect.fromEffect(
              curveEffect,
              allowedParameters: curveParameterIds,
            ),
      lut: lutEffect == null
          ? null
          : ColorGradePresetLut(
              enabled: lutEffect.enabled,
              interpolation: lutInterpolations.contains(
                lutEffect.assetInterpolation,
              )
                  ? lutEffect.assetInterpolation
                  : 'trilinear',
              fileName: _fileName(lutEffect.assetUri),
            ),
    );
  }

  ColorGradePreset withLutContent(String content) {
    final current = lut;
    if (current == null) {
      throw StateError('This preset does not contain a LUT effect.');
    }
    if (content.length > maxLutCharacters) {
      throw const FormatException('The embedded 3D LUT is too large.');
    }
    return ColorGradePreset(
      name: name,
      outputProfile: outputProfile,
      primary: primary,
      curves: curves,
      lut: ColorGradePresetLut(
        enabled: current.enabled,
        interpolation: current.interpolation,
        fileName: current.fileName,
        content: content,
      ),
    );
  }

  Map<String, Object?> toJson() => {
        'format': formatId,
        'version': schemaVersion,
        'name': name,
        'outputProfile': outputProfile.name,
        'primary': primary?.toJson(),
        'curves': curves?.toJson(),
        'lut': lut?.toJson(),
      };

  String encode() {
    final result = const JsonEncoder.withIndent('  ').convert(toJson());
    if (result.length > maxPresetCharacters) {
      throw const FormatException('The color preset exceeds the size limit.');
    }
    return result;
  }

  factory ColorGradePreset.decode(String source) {
    if (source.length > maxPresetCharacters) {
      throw const FormatException('The color preset exceeds the size limit.');
    }
    final decoded = jsonDecode(source);
    final json = _asMap(decoded, 'preset');
    if (json['format'] != formatId) {
      throw const FormatException('This is not a DepthVibe color preset.');
    }
    if (json['version'] != schemaVersion) {
      throw FormatException(
        'Unsupported color preset version: ${json['version']}.',
      );
    }

    final rawName = json['name'];
    if (rawName is! String || rawName.trim().isEmpty || rawName.length > 128) {
      throw const FormatException('The color preset name is invalid.');
    }
    final rawProfile = json['outputProfile'];
    if (rawProfile is! String) {
      throw const FormatException('The output color profile is missing.');
    }
    final profile = ColorOutputProfile.values.where(
      (item) => item.name == rawProfile,
    );
    if (profile.isEmpty) {
      throw FormatException('Unsupported output profile: $rawProfile.');
    }

    final primary = _readEffect(
      json['primary'],
      label: 'primary grade',
      allowedParameters: primaryParameterIds,
    );
    final curves = _readEffect(
      json['curves'],
      label: 'RGB curves',
      allowedParameters: curveParameterIds,
    );
    final lut = _readLut(json['lut']);

    return ColorGradePreset(
      name: rawName.trim(),
      outputProfile: profile.first,
      primary: primary,
      curves: curves,
      lut: lut,
    );
  }

  static ColorGradePresetEffect? _readEffect(
    Object? value, {
    required String label,
    required Set<String> allowedParameters,
  }) {
    if (value == null) return null;
    final json = _asMap(value, label);
    final enabled = json['enabled'] ?? true;
    if (enabled is! bool) {
      throw FormatException('The $label enabled flag is invalid.');
    }

    final rawParameters = _asMap(
      json['parameters'] ?? const <String, Object?>{},
      '$label parameters',
    );
    if (rawParameters.length > allowedParameters.length) {
      throw FormatException('The $label contains too many parameters.');
    }
    final parameters = <String, double>{};
    for (final entry in rawParameters.entries) {
      if (!allowedParameters.contains(entry.key) || entry.value is! num) {
        throw FormatException('Unsupported $label parameter: ${entry.key}.');
      }
      final numeric = (entry.value as num).toDouble();
      if (!_isParameterValueValid(entry.key, numeric)) {
        throw FormatException('Invalid value for ${entry.key}.');
      }
      parameters[entry.key] = numeric;
    }

    final rawTracks = json['keyframeTracks'] ?? const <Object?>[];
    if (rawTracks is! List || rawTracks.length > maxTracksPerEffect) {
      throw FormatException('The $label keyframe list is invalid.');
    }
    final tracks = <KeyframeTrack>[];
    for (final rawTrack in rawTracks) {
      final trackJson = _asMap(rawTrack, '$label keyframe track');
      final property = trackJson['property'];
      if (property is! String || !allowedParameters.contains(property)) {
        throw FormatException('Unsupported $label keyframe property.');
      }
      final rawFrames = trackJson['keyframes'] ?? const <Object?>[];
      if (rawFrames is! List || rawFrames.length > maxKeyframesPerTrack) {
        throw FormatException('The $label keyframe count is invalid.');
      }
      for (final rawFrame in rawFrames) {
        final frame = _asMap(rawFrame, '$label keyframe');
        final time = frame['timeMs'];
        final rawValue = frame['value'];
        if (time is! num ||
            !time.toDouble().isFinite ||
            time < 0 ||
            time.toDouble() != time.toInt().toDouble() ||
            rawValue is! num ||
            !_isParameterValueValid(property, rawValue.toDouble())) {
          throw FormatException('Invalid keyframe for $property.');
        }
        final interpolation = frame['interpolation'];
        if (interpolation != null &&
            (interpolation is! String ||
                !Interpolation.values.any(
                  (item) => item.name == interpolation,
                ))) {
          throw FormatException('Invalid keyframe interpolation.');
        }
        for (final tangent in const ['inTangent', 'outTangent']) {
          final tangentValue = frame[tangent];
          if (tangentValue != null &&
              (tangentValue is! num ||
                  !tangentValue.toDouble().isFinite)) {
            throw FormatException('Invalid keyframe tangent.');
          }
        }
        final rawBezier = frame['bezier'];
        if (rawBezier != null) {
          final bezier = _asMap(rawBezier, 'Bezier controls');
          for (final coordinate in const ['x1', 'y1', 'x2', 'y2']) {
            final coordinateValue = bezier[coordinate];
            if (coordinateValue != null &&
                (coordinateValue is! num ||
                    !coordinateValue.toDouble().isFinite)) {
              throw const FormatException('Invalid Bezier control value.');
            }
          }
        }
      }
      final trackEnabled = trackJson['enabled'];
      if (trackEnabled != null && trackEnabled is! bool) {
        throw FormatException('Invalid $label keyframe track state.');
      }
      tracks.add(KeyframeTrack.fromJson(trackJson));
    }

    return ColorGradePresetEffect(
      enabled: enabled,
      parameters: parameters,
      keyframeTracks: tracks,
    );
  }

  static ColorGradePresetLut? _readLut(Object? value) {
    if (value == null) return null;
    final json = _asMap(value, '3D LUT');
    final enabled = json['enabled'] ?? true;
    if (enabled is! bool) {
      throw const FormatException('The 3D LUT enabled flag is invalid.');
    }
    final rawInterpolation = json['interpolation'] ?? 'trilinear';
    if (rawInterpolation is! String ||
        !lutInterpolations.contains(rawInterpolation)) {
      throw const FormatException('The 3D LUT interpolation mode is invalid.');
    }
    final rawFileName = json['fileName'];
    if (rawFileName != null &&
        (rawFileName is! String ||
            rawFileName.isEmpty ||
            rawFileName.length > 255)) {
      throw const FormatException('The 3D LUT filename is invalid.');
    }
    final rawContent = json['content'];
    if (rawContent != null &&
        (rawContent is! String ||
            rawContent.isEmpty ||
            rawContent.length > maxLutCharacters)) {
      throw const FormatException('The embedded 3D LUT content is invalid.');
    }
    return ColorGradePresetLut(
      enabled: enabled,
      interpolation: rawInterpolation,
      fileName: rawFileName as String?,
      content: rawContent as String?,
    );
  }

  static Map<String, Object?> _asMap(Object? value, String label) {
    if (value is! Map) {
      throw FormatException('The $label section must be an object.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('The $label section has a non-text key.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static bool _isParameterValueValid(String id, double value) {
    if (!value.isFinite) return false;
    if (curveParameterIds.contains(id)) return value >= 0 && value <= 1;
    if (id == 'contrast' || id == 'saturation') {
      return value >= 0 && value <= 3;
    }
    if (id == 'master_gamma') return value >= 0.1 && value <= 3;
    return primaryParameterIds.contains(id) && value >= -1 && value <= 1;
  }

  static String? _fileName(String? uri) {
    if (uri == null || uri.trim().isEmpty) return null;
    return uri.replaceAll('\\', '/').split('/').last;
  }
}

class ColorGradePresetEffect {
  const ColorGradePresetEffect({
    required this.enabled,
    this.parameters = const {},
    this.keyframeTracks = const [],
  });

  final bool enabled;
  final Map<String, double> parameters;
  final List<KeyframeTrack> keyframeTracks;

  factory ColorGradePresetEffect.fromEffect(
    EffectInstance effect, {
    required Set<String> allowedParameters,
  }) =>
      ColorGradePresetEffect(
        enabled: effect.enabled,
        parameters: {
          for (final entry in effect.parameters.entries)
            if (allowedParameters.contains(entry.key) &&
                entry.value.isFinite)
              entry.key: entry.value,
        },
        keyframeTracks: [
          for (final track in effect.keyframeTracks)
            if (allowedParameters.contains(track.property)) track,
        ],
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'parameters': parameters,
        'keyframeTracks':
            keyframeTracks.map((track) => track.toJson()).toList(),
      };
}

class ColorGradePresetLut {
  const ColorGradePresetLut({
    required this.enabled,
    required this.interpolation,
    this.fileName,
    this.content,
  });

  final bool enabled;
  final String interpolation;
  final String? fileName;
  final String? content;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'interpolation': interpolation,
        if (fileName != null) 'fileName': fileName,
        if (content != null) 'content': content,
      };
}
