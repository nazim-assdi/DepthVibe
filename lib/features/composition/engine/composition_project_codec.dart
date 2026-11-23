import '../domain/composition_models.dart';

/// JSON codec for the versioned manifest stored inside a .dvproj ZIP package.
class CompositionProjectCodec {
  CompositionProjectCodec._();

  static const formatId = 'DepthVibe.Project';
  static const schemaVersion = 1;
  static const maxLayers = 10000;
  static const maxTransitions = 20000;
  static const maxAudioBuses = 256;
  static const maxEffectsPerLayer = 512;
  static const maxMasksPerLayer = 512;
  static const maxKeyframeTracks = 50000;
  static const maxKeyframesPerTrack = 100000;

  static Map<String, Object?> encodeDocument(
    CompositionDocument document, {
    String? Function(String? uri)? rewriteAssetUri,
  }) {
    String? asset(String? uri) =>
        rewriteAssetUri == null ? uri : rewriteAssetUri(uri);

    final layers = document.layers.map((layer) {
      return <String, Object?>{
        'id': layer.id,
        'name': layer.name,
        'kind': layer.kind.name,
        'startMs': layer.startMs,
        'durationMs': layer.durationMs,
        'sourceInMs': layer.sourceInMs,
        'enabled': layer.enabled,
        'solo': layer.solo,
        'locked': layer.locked,
        'guideLayer': layer.guideLayer,
        'shy': layer.shy,
        'parentId': layer.parentId,
        'sourceUri': asset(layer.sourceUri),
        'sourceDocumentUri': asset(layer.sourceDocumentUri),
        'sourceLayerIndex': layer.sourceLayerIndex,
        'externalSourceId': layer.externalSourceId,
        'externalSourceName': layer.externalSourceName,
        'externalHostApp': layer.externalHostApp,
        'externalLayerIndex': layer.externalLayerIndex,
        'interchangeMetadata': layer.interchangeMetadata,
        'textContent': layer.textContent,
        'textFontFamily': layer.textFontFamily,
        'textFontAssetUri': asset(layer.textFontAssetUri),
        'textFontFallback': layer.textFontFallback,
        'textFontSize': layer.textFontSize,
        'textFontWeight': layer.textFontWeight,
        'textItalic': layer.textItalic,
        'textColor': layer.textColor,
        'textLetterSpacing': layer.textLetterSpacing,
        'textLineHeight': layer.textLineHeight,
        'textAlign': layer.textAlign,
        'textBoxWidth': layer.textBoxWidth,
        'clippingBaseLayerId': layer.clippingBaseLayerId,
        'photoshopClipped': layer.photoshopClipped,
        'smartObjectSourceUri': asset(layer.smartObjectSourceUri),
        'smartObjectResourceId': layer.smartObjectResourceId,
        'photoshopAdjustmentKey': layer.photoshopAdjustmentKey,
        'sourceWidth': layer.sourceWidth,
        'sourceHeight': layer.sourceHeight,
        'modelAnimationIndex': layer.modelAnimationIndex,
        'transform': layer.transform.toJson(),
        'blendMode': layer.blendMode.name,
        'masks': layer.masks.map(_encodeMask).toList(),
        'effects': layer.effects.map((effect) => <String, Object?>{
              'id': effect.id,
              'effectId': effect.effectId,
              'name': effect.name,
              'enabled': effect.enabled,
              'parameters': _encodeParameters(effect.parameters),
              'keyframeTracks':
                  effect.keyframeTracks.map((track) => track.toJson()).toList(),
              'assetUri': asset(effect.assetUri),
              'assetInterpolation': effect.assetInterpolation,
              if (effect.nativeDescriptor.isNotEmpty)
                'nativeDescriptor': effect.nativeDescriptor,
            }).toList(),
        'keyframeTracks':
            layer.keyframeTracks.map((track) => track.toJson()).toList(),
        'shapeStyle':
            layer.shapeStyle == null ? null : _encodeShapeStyle(layer.shapeStyle!),
        'camera': layer.camera == null ? null : _encodeCamera(layer.camera!),
        'light': layer.light == null ? null : _encodeLight(layer.light!),
        'audioSettings': _encodeAudioSettings(layer.audioSettings),
      };
    }).toList();

    return <String, Object?>{
      'name': document.name,
      'width': document.width,
      'height': document.height,
      'frameRate': document.frameRate,
      'durationMs': document.durationMs,
      'colorOutputProfile': document.colorOutputProfile.name,
      'layers': layers,
      'transitions': document.transitions.map((item) => <String, Object?>{
            'id': item.id,
            'fromLayerId': item.fromLayerId,
            'toLayerId': item.toLayerId,
            'kind': item.kind.name,
            'durationMs': item.durationMs,
            'startMs': item.startMs,
            'externalMatchName': item.externalMatchName,
            'metadata': item.metadata,
          }).toList(),
      'audioBuses': document.audioBuses.map(_encodeAudioBus).toList(),
      'playheadMs': document.playheadMs,
      'selectedLayerId': document.selectedLayerId,
    };
  }

  static CompositionDocument decodeDocument(
    Object? value, {
    String? Function(String? uri)? resolveAssetUri,
  }) {
    final json = _asMap(value, 'composition document');
    final rawLayers = _asList(json['layers'] ?? const [], 'layers');
    if (rawLayers.length > maxLayers) {
      throw const FormatException('The project has too many layers.');
    }
    String? asset(String? uri) =>
        resolveAssetUri == null ? uri : resolveAssetUri(uri);

    final layers = rawLayers.map((rawLayer) {
      final item = _asMap(rawLayer, 'layer');
      final rawEffects = _asList(item['effects'] ?? const [], 'layer effects');
      final rawMasks = _asList(item['masks'] ?? const [], 'layer masks');
      if (rawEffects.length > maxEffectsPerLayer ||
          rawMasks.length > maxMasksPerLayer) {
        throw const FormatException('A layer contains too many effects or masks.');
      }
      final effects = rawEffects.map((rawEffect) {
        final effect = _asMap(rawEffect, 'effect');
        return EffectInstance(
          id: _string(effect['id'], ''),
          effectId: _string(effect['effectId'], ''),
          name: _string(effect['name'], 'Effect'),
          enabled: _boolean(effect['enabled'], true),
          parameters: _decodeParameters(effect['parameters']),
          keyframeTracks: _decodeTracks(effect['keyframeTracks']),
          assetUri: asset(_optionalString(effect['assetUri'])),
          assetInterpolation: _string(effect['assetInterpolation'], 'trilinear'),
          nativeDescriptor: _safeMetadata(effect['nativeDescriptor']),
        );
      }).toList();

      return CompositionLayer(
        id: _string(item['id'], ''),
        name: _string(item['name'], 'Layer'),
        kind: _enumValue(LayerKind.values, item['kind'], LayerKind.video),
        startMs: _integer(item['startMs'], 0),
        durationMs: _integer(item['durationMs'], 10000),
        sourceInMs: _integer(item['sourceInMs'], 0),
        enabled: _boolean(item['enabled'], true),
        solo: _boolean(item['solo'], false),
        locked: _boolean(item['locked'], false),
        guideLayer: _boolean(item['guideLayer'], false),
        shy: _boolean(item['shy'], false),
        parentId: _optionalString(item['parentId']),
        sourceUri: asset(_optionalString(item['sourceUri'])),
        sourceDocumentUri: asset(_optionalString(item['sourceDocumentUri'])),
        sourceLayerIndex: _optionalInteger(item['sourceLayerIndex']),
        externalSourceId: _optionalString(item['externalSourceId']),
        externalSourceName: _optionalString(item['externalSourceName']),
        externalHostApp: _optionalString(item['externalHostApp']),
        externalLayerIndex: _optionalInteger(item['externalLayerIndex']),
        interchangeMetadata: _safeMetadata(item['interchangeMetadata']),
        textContent: _optionalString(item['textContent']),
        textFontFamily: _optionalString(item['textFontFamily']),
        textFontAssetUri: asset(_optionalString(item['textFontAssetUri'])),
        textFontFallback: (item['textFontFallback'] as List? ?? const [])
            .whereType<String>().take(32).toList(),
        textFontSize: _number(item['textFontSize'], 72).clamp(1, 2000).toDouble(),
        textFontWeight: _integer(item['textFontWeight'], 700).clamp(100, 900).toInt(),
        textItalic: _boolean(item['textItalic'], false),
        textColor: _string(item['textColor'], '#FFFFFFFF'),
        textLetterSpacing: _number(item['textLetterSpacing'], 0).clamp(-100, 500).toDouble(),
        textLineHeight: _number(item['textLineHeight'], 1.2).clamp(0.1, 10).toDouble(),
        textAlign: _string(item['textAlign'], 'left'),
        textBoxWidth: _number(item['textBoxWidth'], 1000).clamp(1, 20000).toDouble(),
        clippingBaseLayerId: _optionalString(item['clippingBaseLayerId']),
        photoshopClipped: _boolean(item['photoshopClipped'], false),
        smartObjectSourceUri:
            asset(_optionalString(item['smartObjectSourceUri'])),
        smartObjectResourceId: _optionalString(item['smartObjectResourceId']),
        photoshopAdjustmentKey:
            _optionalString(item['photoshopAdjustmentKey']),
        sourceWidth: _integer(item['sourceWidth'], 0),
        sourceHeight: _integer(item['sourceHeight'], 0),
        modelAnimationIndex: _integer(item['modelAnimationIndex'], 0),
        transform: LayerTransform.fromJson(
          _asMap(item['transform'] ?? const <String, Object?>{}, 'transform'),
        ),
        blendMode: _enumValue(
          LayerBlendMode.values,
          item['blendMode'],
          LayerBlendMode.normal,
        ),
        masks: rawMasks.map(_decodeMask).toList(),
        effects: effects,
        keyframeTracks: _decodeTracks(item['keyframeTracks']),
        shapeStyle:
            item['shapeStyle'] == null ? null : _decodeShapeStyle(item['shapeStyle']),
        camera: item['camera'] == null ? null : _decodeCamera(item['camera']),
        light: item['light'] == null ? null : _decodeLight(item['light']),
        audioSettings: _decodeAudioSettings(item['audioSettings']),
      );
    }).toList();

    final ids = <String>{};
    for (final layer in layers) {
      if (layer.id.isEmpty || !ids.add(layer.id)) {
        throw const FormatException('Layer IDs must be present and unique.');
      }
    }

    final rawTransitions =
        _asList(json['transitions'] ?? const [], 'transitions');
    if (rawTransitions.length > maxTransitions) {
      throw const FormatException('The project has too many transitions.');
    }
    final transitions = rawTransitions.map((raw) {
      final item = _asMap(raw, 'transition');
      return CompositionTransition(
        id: _string(item['id'], ''),
        fromLayerId: _string(item['fromLayerId'], ''),
        toLayerId: _string(item['toLayerId'], ''),
        kind: _enumValue(
          TransitionKind.values,
          item['kind'],
          TransitionKind.dissolve,
        ),
        durationMs: _integer(item['durationMs'], 500),
        startMs: _integer(item['startMs'], 0),
        externalMatchName: _optionalString(item['externalMatchName']),
        metadata: _safeMetadata(item['metadata']),
      );
    }).toList();

    final rawBuses = json['audioBuses'];
    final audioBuses = rawBuses == null
        ? const <AudioBus>[
            AudioBus(id: 'master', name: 'Master', isMaster: true),
          ]
        : _asList(rawBuses, 'audio buses').map(_decodeAudioBus).toList();
    if (audioBuses.length > maxAudioBuses) {
      throw const FormatException('The project has too many audio buses.');
    }

    final selected = _optionalString(json['selectedLayerId']);
    return CompositionDocument(
      name: _string(json['name'], 'Untitled Composition'),
      width: _integer(json['width'], 1920),
      height: _integer(json['height'], 1080),
      frameRate: _number(json['frameRate'], 30),
      durationMs: _integer(json['durationMs'], 30000),
      colorOutputProfile: _enumValue(
        ColorOutputProfile.values,
        json['colorOutputProfile'],
        ColorOutputProfile.rec709,
      ),
      layers: layers,
      transitions: transitions,
      audioBuses: audioBuses,
      playheadMs: _integer(json['playheadMs'], 0),
      selectedLayerId: selected != null && ids.contains(selected) ? selected : null,
    );
  }

  static Map<String, Object?> _safeMetadata(Object? raw) {
    if (raw is! Map) return const <String, Object?>{};
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) continue;
      final key = entry.key as String;
      if (key.length > 128) continue;
      final value = entry.value;
      if (value is String || value is num || value is bool || value == null ||
          value is List || value is Map) {
        result[key] = value;
      }
    }
    return result;
  }

  static Map<String, Object?> _encodeMask(MaskModel mask) => {
        'id': mask.id,
        'name': mask.name,
        'shape': mask.shape.name,
        'operation': mask.operation.name,
        'enabled': mask.enabled,
        'inverted': mask.inverted,
        'feather': mask.feather,
        'expansion': mask.expansion,
        'opacity': mask.opacity,
        'left': mask.left,
        'top': mask.top,
        'width': mask.width,
        'height': mask.height,
        'vertices': mask.vertices.map((vertex) => <String, Object?>{
              'anchor': vertex.anchor.toJson(),
              'inHandle': vertex.inHandle.toJson(),
              'outHandle': vertex.outHandle.toJson(),
              'smooth': vertex.smooth,
            }).toList(),
        'keyframeTracks':
            mask.keyframeTracks.map((track) => track.toJson()).toList(),
      };

  static MaskModel _decodeMask(Object? raw) {
    final json = _asMap(raw, 'mask');
    final vertices = _asList(json['vertices'] ?? const [], 'mask vertices');
    return MaskModel(
      id: _string(json['id'], ''),
      name: _string(json['name'], 'Mask'),
      shape: _enumValue(MaskShape.values, json['shape'], MaskShape.rectangle),
      operation:
          _enumValue(MaskOperation.values, json['operation'], MaskOperation.add),
      enabled: _boolean(json['enabled'], true),
      inverted: _boolean(json['inverted'], false),
      feather: _number(json['feather'], 0),
      expansion: _number(json['expansion'], 0),
      opacity: _number(json['opacity'], 100),
      left: _number(json['left'], 0.05),
      top: _number(json['top'], 0.05),
      width: _number(json['width'], 0.9),
      height: _number(json['height'], 0.9),
      vertices: vertices.map((rawVertex) {
        final vertex = _asMap(rawVertex, 'mask vertex');
        return MaskVertex(
          anchor: Vector2.fromJson(_asMap(vertex['anchor'], 'mask anchor')),
          inHandle:
              Vector2.fromJson(_asMap(vertex['inHandle'], 'mask in handle')),
          outHandle:
              Vector2.fromJson(_asMap(vertex['outHandle'], 'mask out handle')),
          smooth: _boolean(vertex['smooth'], false),
        );
      }).toList(),
      keyframeTracks: _decodeTracks(json['keyframeTracks']),
    );
  }

  static Map<String, Object?> _encodeShapeStyle(ShapeStyle style) => {
        'primitive': style.primitive.name,
        'fillColor': style.fillColor,
        'strokeColor': style.strokeColor,
        'strokeWidth': style.strokeWidth,
        'cornerRadius': style.cornerRadius,
        'points': style.points,
        'pathVertices': style.pathVertices.map((vertex) => <String, Object?>{
              'anchor': vertex.anchor.toJson(),
              'inHandle': vertex.inHandle.toJson(),
              'outHandle': vertex.outHandle.toJson(),
              'smooth': vertex.smooth,
            }).toList(),
        'pathClosed': style.pathClosed,
      };

  static ShapeStyle _decodeShapeStyle(Object? raw) {
    final json = _asMap(raw, 'shape style');
    final pathVertices =
        _asList(json['pathVertices'] ?? const [], 'shape path vertices');
    return ShapeStyle(
      primitive: _enumValue(
        ShapePrimitive.values,
        json['primitive'],
        ShapePrimitive.rectangle,
      ),
      fillColor: _string(json['fillColor'], '#7C8CFF'),
      strokeColor: _string(json['strokeColor'], '#FFFFFF'),
      strokeWidth: _number(json['strokeWidth'], 0),
      cornerRadius: _number(json['cornerRadius'], 0),
      points: _integer(json['points'], 5),
      pathVertices: pathVertices.map((rawVertex) {
        final vertex = _asMap(rawVertex, 'shape path vertex');
        return MaskVertex(
          anchor: Vector2.fromJson(_asMap(vertex['anchor'], 'shape anchor')),
          inHandle: Vector2.fromJson(
            _asMap(vertex['inHandle'], 'shape in handle'),
          ),
          outHandle: Vector2.fromJson(
            _asMap(vertex['outHandle'], 'shape out handle'),
          ),
          smooth: _boolean(vertex['smooth'], false),
        );
      }).toList(),
      pathClosed: _boolean(json['pathClosed'], true),
    );
  }

  static Map<String, Object?> _encodeCamera(CameraSettings camera) => {
        'projection': camera.projection,
        'fieldOfView': camera.fieldOfView,
        'focalLength': camera.focalLength,
        'focusDistance': camera.focusDistance,
        'nearClip': camera.nearClip,
        'farClip': camera.farClip,
        'aperture': camera.aperture,
        'sensorWidthMm': camera.sensorWidthMm,
        'depthOfField': camera.depthOfField,
      };

  static CameraSettings _decodeCamera(Object? raw) {
    final json = _asMap(raw, 'camera settings');
    return CameraSettings(
      projection: _string(json['projection'], 'perspective'),
      fieldOfView: _number(json['fieldOfView'], 50),
      focalLength: _number(json['focalLength'], 50),
      focusDistance: _number(json['focusDistance'], 1000),
      nearClip: _number(json['nearClip'], 50),
      farClip: _number(json['farClip'], 5000),
      aperture: _number(json['aperture'], 2.8),
      sensorWidthMm: _number(json['sensorWidthMm'], 36),
      depthOfField: _boolean(json['depthOfField'], false),
    );
  }

  static Map<String, Object?> _encodeLight(LightSettings light) => {
        'kind': light.kind.name,
        'color': light.color,
        'intensity': light.intensity,
        'coneAngle': light.coneAngle,
        'castShadows': light.castShadows,
        'shadowSoftness': light.shadowSoftness,
        'areaSize': light.areaSize,
        'areaSamples': light.areaSamples,
      };

  static LightSettings _decodeLight(Object? raw) {
    final json = _asMap(raw, 'light settings');
    return LightSettings(
      kind: _enumValue(LightKind.values, json['kind'], LightKind.directional),
      color: _string(json['color'], '#FFFFFF'),
      intensity: _number(json['intensity'], 100),
      coneAngle: _number(json['coneAngle'], 45),
      castShadows: _boolean(json['castShadows'], true),
      shadowSoftness: _number(json['shadowSoftness'], 20),
      areaSize: _number(json['areaSize'], 160),
      areaSamples: _integer(json['areaSamples'], 16),
    );
  }

  static Map<String, Object?> _encodeAudioSettings(AudioSettings audio) => {
        'gainDb': audio.gainDb,
        'pan': audio.pan,
        'muted': audio.muted,
        'fadeInMs': audio.fadeInMs,
        'fadeOutMs': audio.fadeOutMs,
        'duckingRole': audio.duckingRole.name,
        'duckingThreshold': audio.duckingThreshold,
        'duckingRatio': audio.duckingRatio,
        'duckingAttackMs': audio.duckingAttackMs,
        'duckingReleaseMs': audio.duckingReleaseMs,
        'lowEqDb': audio.lowEqDb,
        'midEqDb': audio.midEqDb,
        'highEqDb': audio.highEqDb,
        'busId': audio.busId,
      };

  static AudioSettings _decodeAudioSettings(Object? raw) {
    final json = raw == null
        ? const <String, Object?>{}
        : _asMap(raw, 'audio settings');
    return AudioSettings(
      gainDb: _number(json['gainDb'], 0),
      pan: _number(json['pan'], 0),
      muted: _boolean(json['muted'], false),
      fadeInMs: _integer(json['fadeInMs'], 0),
      fadeOutMs: _integer(json['fadeOutMs'], 0),
      duckingRole: _enumValue(
        AudioDuckingRole.values,
        json['duckingRole'],
        AudioDuckingRole.none,
      ),
      duckingThreshold: _number(json['duckingThreshold'], 0.05),
      duckingRatio: _number(json['duckingRatio'], 8),
      duckingAttackMs: _number(json['duckingAttackMs'], 20),
      duckingReleaseMs: _number(json['duckingReleaseMs'], 250),
      lowEqDb: _number(json['lowEqDb'], 0),
      midEqDb: _number(json['midEqDb'], 0),
      highEqDb: _number(json['highEqDb'], 0),
      busId: _optionalString(json['busId']),
    );
  }

  static Map<String, Object?> _encodeAudioBus(AudioBus bus) => {
        'id': bus.id,
        'name': bus.name,
        'isMaster': bus.isMaster,
        'gainDb': bus.gainDb,
        'pan': bus.pan,
        'muted': bus.muted,
        'compressorEnabled': bus.compressorEnabled,
        'compressorThresholdDb': bus.compressorThresholdDb,
        'compressorRatio': bus.compressorRatio,
        'compressorAttackMs': bus.compressorAttackMs,
        'compressorReleaseMs': bus.compressorReleaseMs,
        'makeupGainDb': bus.makeupGainDb,
        'limiterEnabled': bus.limiterEnabled,
        'limiterCeilingDb': bus.limiterCeilingDb,
        'keyframeTracks':
            bus.keyframeTracks.map((track) => track.toJson()).toList(),
      };

  static AudioBus _decodeAudioBus(Object? raw) {
    final json = _asMap(raw, 'audio bus');
    return AudioBus(
      id: _string(json['id'], 'master'),
      name: _string(json['name'], 'Master'),
      isMaster: _boolean(json['isMaster'], false),
      gainDb: _number(json['gainDb'], 0),
      pan: _number(json['pan'], 0),
      muted: _boolean(json['muted'], false),
      compressorEnabled: _boolean(json['compressorEnabled'], false),
      compressorThresholdDb: _number(json['compressorThresholdDb'], -18),
      compressorRatio: _number(json['compressorRatio'], 3),
      compressorAttackMs: _number(json['compressorAttackMs'], 15),
      compressorReleaseMs: _number(json['compressorReleaseMs'], 180),
      makeupGainDb: _number(json['makeupGainDb'], 0),
      limiterEnabled: _boolean(json['limiterEnabled'], false),
      limiterCeilingDb: _number(json['limiterCeilingDb'], -1),
      keyframeTracks: _decodeTracks(json['keyframeTracks']),
    );
  }

  static Map<String, double> _encodeParameters(
    Map<String, double> parameters,
  ) {
    for (final entry in parameters.entries) {
      if (!entry.value.isFinite) {
        throw FormatException(
          'Effect parameter ' + entry.key + ' is not a finite number.',
        );
      }
    }
    return Map<String, double>.from(parameters);
  }

  static Map<String, double> _decodeParameters(Object? raw) {
    if (raw == null) return const {};
    final json = _asMap(raw, 'effect parameters');
    final result = <String, double>{};
    for (final entry in json.entries) {
      if (entry.value is! num ||
          !(entry.value as num).toDouble().isFinite) {
        throw FormatException(
          'Effect parameter ' + entry.key + ' is not a finite number.',
        );
      }
      result[entry.key] = (entry.value as num).toDouble();
    }
    return result;
  }

  static List<KeyframeTrack> _decodeTracks(Object? raw) {
    if (raw == null) return const [];
    final list = _asList(raw, 'keyframe tracks');
    if (list.length > maxKeyframeTracks) {
      throw const FormatException('The project has too many keyframe tracks.');
    }
    return list.map((item) {
      final json = _asMap(item, 'keyframe track');
      final frames = _asList(json['keyframes'] ?? const [], 'keyframes');
      if (frames.length > maxKeyframesPerTrack) {
        throw const FormatException('A keyframe track is too large.');
      }
      return KeyframeTrack.fromJson(json);
    }).toList();
  }

  static Map<String, Object?> _asMap(Object? value, String label) {
    if (value is! Map) throw FormatException('The $label field must be an object.');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('The $label object contains a non-text key.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _asList(Object? value, String label) {
    if (value is! List) throw FormatException('The $label field must be an array.');
    return value.cast<Object?>();
  }

  static String _string(Object? value, String fallback) =>
      value is String ? value : fallback;

  static String? _optionalString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static bool _boolean(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  static double _number(Object? value, double fallback) {
    if (value == null) return fallback;
    if (value is! num || !value.toDouble().isFinite) {
      throw const FormatException('A project numeric field is invalid.');
    }
    return value.toDouble();
  }

  static int _integer(Object? value, int fallback) {
    if (value == null) return fallback;
    if (value is! num ||
        !value.toDouble().isFinite ||
        value.toDouble() != value.toInt().toDouble()) {
      throw const FormatException('A project integer field is invalid.');
    }
    return value.toInt();
  }

  static int? _optionalInteger(Object? value) =>
      value == null ? null : _integer(value, 0);

  static T _enumValue<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    if (raw is! String) return fallback;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return fallback;
  }
}
