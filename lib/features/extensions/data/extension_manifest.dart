
import '../../composition/data/effect_catalog.dart';

class ExtensionEffectSpec {
  const ExtensionEffectSpec({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.operation,
    required this.defaultOverrides,
    this.asset,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String operation;
  final Map<String, double> defaultOverrides;
  final String? asset;

  factory ExtensionEffectSpec.fromJson(Object? raw) {
    final json = _asMap(raw, 'extension effect');
    final id = _requiredString(json['id'], 'effect id', 48);
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,47}$').hasMatch(id)) {
      throw FormatException('Invalid extension effect id: ' + id);
    }

    final operation = _requiredString(json['operation'], 'effect operation', 64);
    if (!EffectCatalog.extensionSafeRendererIds.contains(operation)) {
      throw FormatException('Renderer operation is not allowed: ' + operation);
    }
    final renderer = EffectCatalog.findBuiltin(operation);
    if (renderer == null) {
      throw FormatException('Unknown renderer operation: ' + operation);
    }

    final defaultsJson = _asMap(
      json['defaults'] ?? const <String, Object?>{},
      'effect defaults',
    );
    final parameterIds = renderer.parameters.map((item) => item.id).toSet();
    final defaults = <String, double>{};
    for (final entry in defaultsJson.entries) {
      if (!parameterIds.contains(entry.key)) {
        throw FormatException('Unknown parameter: ' + entry.key);
      }
      if (entry.value is! num) {
        throw FormatException('Default must be numeric: ' + entry.key);
      }
      final value = (entry.value as num).toDouble();
      if (!value.isFinite) {
        throw FormatException('Default must be finite: ' + entry.key);
      }
      final parameter = renderer.parameters.firstWhere(
        (item) => item.id == entry.key,
      );
      if (value < parameter.min || value > parameter.max) {
        throw FormatException('Default is outside supported range: ' + entry.key);
      }
      defaults[entry.key] = value;
    }

    final asset = json['asset'] == null
        ? null
        : _requiredString(json['asset'], 'effect asset', 255);
    if (operation == 'color_lut') {
      if (asset == null || !_isSafeCubeAsset(asset)) {
        throw const FormatException(
          'A LUT effect must reference a safe .cube file under assets/.',
        );
      }
    } else if (asset != null) {
      throw const FormatException(
        'Only the color_lut operation may include an asset.',
      );
    }

    return ExtensionEffectSpec(
      id: id,
      name: _requiredString(json['name'], 'effect name', 80),
      category: _requiredString(
        json['category'] ?? 'Extensions',
        'effect category',
        48,
      ),
      description: _optionalString(json['description'], 240),
      operation: operation,
      defaultOverrides: Map.unmodifiable(defaults),
      asset: asset,
    );
  }

  static bool _isSafeCubeAsset(String value) {
    if (!value.startsWith('assets/') ||
        !value.toLowerCase().endsWith('.cube') ||
        value.contains(String.fromCharCode(92)) ||
        value.contains(String.fromCharCode(0))) {
      return false;
    }
    final segments = value.split('/');
    return segments.length >= 2 &&
        segments.every(
          (segment) =>
              segment.isNotEmpty && segment != '.' && segment != '..',
        ) &&
        RegExp(r'^assets/[A-Za-z0-9][A-Za-z0-9._/-]{0,240}\.cube$')
            .hasMatch(value);
  }
}

class DepthVibeExtensionManifest {
  const DepthVibeExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.effects,
  });

  static const formatId = 'DepthVibe.Extension';
  static const schemaVersion = 1;

  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final List<ExtensionEffectSpec> effects;

  factory DepthVibeExtensionManifest.fromJson(Object? raw) {
    final json = _asMap(raw, 'extension manifest');
    if (json['format'] != formatId) {
      throw const FormatException('Not a DepthVibe extension package.');
    }
    if (json['schemaVersion'] != schemaVersion) {
      throw FormatException(
        'Unsupported extension schema version: ' +
            (json['schemaVersion']?.toString() ?? 'missing'),
      );
    }

    final id = _requiredString(json['id'], 'extension id', 80);
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,79}$').hasMatch(id)) {
      throw const FormatException('The extension id is invalid.');
    }
    final version = _requiredString(json['version'], 'extension version', 40);
    if (!RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?
        .hasMatch(version)) {
      throw const FormatException(
        'Extension version must use semantic version notation.',
      );
    }

    final rawEffects = json['effects'];
    if (rawEffects is! List || rawEffects.isEmpty || rawEffects.length > 100) {
      throw const FormatException(
        'An extension must declare between 1 and 100 effects.',
      );
    }
    final effects = rawEffects
        .map(ExtensionEffectSpec.fromJson)
        .toList(growable: false);
    final seen = <String>{};
    for (final effect in effects) {
      if (!seen.add(effect.id)) {
        throw FormatException('Duplicate extension effect id: ' + effect.id);
      }
    }

    return DepthVibeExtensionManifest(
      id: id,
      name: _requiredString(json['name'], 'extension name', 80),
      version: version,
      author: _optionalString(json['author'], 80),
      description: _optionalString(json['description'], 500),
      effects: List.unmodifiable(effects),
    );
  }
}

Map<String, Object?> _asMap(Object? value, String label) {
  if (value is! Map) throw FormatException('The ' + label + ' must be an object.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('The ' + label + ' contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Object? value, String label, int maxLength) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > maxLength) {
    throw FormatException('The ' + label + ' is missing or too long.');
  }
  return value.trim();
}

String _optionalString(Object? value, int maxLength) {
  if (value == null) return '';
  if (value is! String || value.length > maxLength) {
    throw const FormatException('An optional text field is invalid.');
  }
  return value.trim();
}
)
        .hasMatch(version)) {
      throw const FormatException(
        'Extension version must use semantic version notation.',
      );
    }

    final rawEffects = json['effects'];
    if (rawEffects is! List || rawEffects.isEmpty || rawEffects.length > 100) {
      throw const FormatException(
        'An extension must declare between 1 and 100 effects.',
      );
    }
    final effects = rawEffects
        .map(ExtensionEffectSpec.fromJson)
        .toList(growable: false);
    final seen = <String>{};
    for (final effect in effects) {
      if (!seen.add(effect.id)) {
        throw FormatException('Duplicate extension effect id: ' + effect.id);
      }
    }

    return DepthVibeExtensionManifest(
      id: id,
      name: _requiredString(json['name'], 'extension name', 80),
      version: version,
      author: _optionalString(json['author'], 80),
      description: _optionalString(json['description'], 500),
      effects: List.unmodifiable(effects),
    );
  }
}

Map<String, Object?> _asMap(Object? value, String label) {
  if (value is! Map) throw FormatException('The ' + label + ' must be an object.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('The ' + label + ' contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Object? value, String label, int maxLength) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > maxLength) {
    throw FormatException('The ' + label + ' is missing or too long.');
  }
  return value.trim();
}

String _optionalString(Object? value, int maxLength) {
  if (value == null) return '';
  if (value is! String || value.length > maxLength) {
    throw const FormatException('An optional text field is invalid.');
  }
  return value.trim();
}
