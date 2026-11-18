import 'dart:math' as math;

enum LayerKind {
  video,
  image,
  photoshopLayer,
  text,
  shape,
  audio,
  nullObject,
  adjustment,
  camera,
  light,
  threeDModel,
  particle,
  precomposition,
}

enum LayerBlendMode {
  normal,
  multiply,
  screen,
  overlay,
  softLight,
  hardLight,
  colorDodge,
  colorBurn,
  difference,
  exclusion,
  add,
  lighten,
  darken,
}

enum ShapePrimitive { rectangle, roundedRectangle, ellipse, polygon, star, path }

enum MaskShape { rectangle, ellipse, polygon, bezier }

enum MaskOperation { add, subtract, intersect, difference }

enum LightKind { ambient, directional, point, spot, area }

enum Interpolation { hold, linear, easeIn, easeOut, easeInOut }

enum TransitionKind {
  dissolve,
  fadeThroughColor,
  wipeLeft,
  wipeRight,
  wipeUp,
  wipeDown,
  slideLeft,
  slideRight,
  zoomIn,
  zoomOut,
  blur,
  luma,
}

class Vector2 {
  const Vector2(this.x, this.y);

  final double x;
  final double y;

  Map<String, Object> toJson() => {'x': x, 'y': y};

  factory Vector2.fromJson(Map<String, Object?> json) => Vector2(
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
      );
}

class Vector3 {
  const Vector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  Map<String, Object> toJson() => {'x': x, 'y': y, 'z': z};

  factory Vector3.fromJson(Map<String, Object?> json) => Vector3(
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
        (json['z'] as num?)?.toDouble() ?? 0,
      );
}

class LayerTransform {
  const LayerTransform({
    this.position = const Vector3(960, 540, 0),
    this.anchor = const Vector3(0, 0, 0),
    this.scale = const Vector3(100, 100, 100),
    this.rotation = const Vector3(0, 0, 0),
    this.opacity = 100,
  });

  final Vector3 position;
  final Vector3 anchor;
  final Vector3 scale;
  final Vector3 rotation;
  final double opacity;

  double valueFor(String property) {
    return switch (property) {
      'position.x' => position.x,
      'position.y' => position.y,
      'position.z' => position.z,
      'anchor.x' => anchor.x,
      'anchor.y' => anchor.y,
      'anchor.z' => anchor.z,
      'scale.x' => scale.x,
      'scale.y' => scale.y,
      'scale.z' => scale.z,
      'rotation.x' => rotation.x,
      'rotation.y' => rotation.y,
      'rotation.z' => rotation.z,
      'opacity' => opacity,
      _ => 0,
    };
  }

  LayerTransform withValue(String property, double value) {
    return switch (property) {
      'position.x' => copyWith(position: Vector3(value, position.y, position.z)),
      'position.y' => copyWith(position: Vector3(position.x, value, position.z)),
      'position.z' => copyWith(position: Vector3(position.x, position.y, value)),
      'anchor.x' => copyWith(anchor: Vector3(value, anchor.y, anchor.z)),
      'anchor.y' => copyWith(anchor: Vector3(anchor.x, value, anchor.z)),
      'anchor.z' => copyWith(anchor: Vector3(anchor.x, anchor.y, value)),
      'scale.x' => copyWith(scale: Vector3(value, scale.y, scale.z)),
      'scale.y' => copyWith(scale: Vector3(scale.x, value, scale.z)),
      'scale.z' => copyWith(scale: Vector3(scale.x, scale.y, value)),
      'rotation.x' => copyWith(rotation: Vector3(value, rotation.y, rotation.z)),
      'rotation.y' => copyWith(rotation: Vector3(rotation.x, value, rotation.z)),
      'rotation.z' => copyWith(rotation: Vector3(rotation.x, rotation.y, value)),
      'opacity' => copyWith(opacity: value.clamp(0, 100).toDouble()),
      _ => this,
    };
  }

  LayerTransform copyWith({
    Vector3? position,
    Vector3? anchor,
    Vector3? scale,
    Vector3? rotation,
    double? opacity,
  }) =>
      LayerTransform(
        position: position ?? this.position,
        anchor: anchor ?? this.anchor,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  Map<String, Object> toJson() => {
        'position': position.toJson(),
        'anchor': anchor.toJson(),
        'scale': scale.toJson(),
        'rotation': rotation.toJson(),
        'opacity': opacity,
      };

  factory LayerTransform.fromJson(Map<String, Object?> json) {
    Map<String, Object?> vector(String key) =>
        (json[key] as Map?)?.cast<String, Object?>() ?? const {};
    return LayerTransform(
      position: Vector3.fromJson(vector('position')),
      anchor: Vector3.fromJson(vector('anchor')),
      scale: Vector3.fromJson(vector('scale')),
      rotation: Vector3.fromJson(vector('rotation')),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 100,
    );
  }
}

class ScalarKeyframe {
  const ScalarKeyframe({
    required this.timeMs,
    required this.value,
    this.interpolation = Interpolation.linear,
    this.inTangent = 0,
    this.outTangent = 0,
  });

  final int timeMs;
  final double value;
  final Interpolation interpolation;
  final double inTangent;
  final double outTangent;

  Map<String, Object> toJson() => {
        'timeMs': timeMs,
        'value': value,
        'interpolation': interpolation.name,
        'inTangent': inTangent,
        'outTangent': outTangent,
      };

  factory ScalarKeyframe.fromJson(Map<String, Object?> json) =>
      ScalarKeyframe(
        timeMs: (json['timeMs'] as num?)?.toInt() ?? 0,
        value: (json['value'] as num?)?.toDouble() ?? 0,
        interpolation: Interpolation.values.firstWhere(
          (item) => item.name == json['interpolation'],
          orElse: () => Interpolation.linear,
        ),
        inTangent: (json['inTangent'] as num?)?.toDouble() ?? 0,
        outTangent: (json['outTangent'] as num?)?.toDouble() ?? 0,
      );
}

class KeyframeTrack {
  const KeyframeTrack({
    required this.property,
    this.keyframes = const [],
    this.enabled = true,
  });

  final String property;
  final List<ScalarKeyframe> keyframes;
  final bool enabled;

  double sample(int timeMs, {double fallback = 0}) {
    if (!enabled || keyframes.isEmpty) return fallback;
    final sorted = [...keyframes]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    if (timeMs <= sorted.first.timeMs) return sorted.first.value;
    if (timeMs >= sorted.last.timeMs) return sorted.last.value;

    for (var index = 0; index < sorted.length - 1; index++) {
      final left = sorted[index];
      final right = sorted[index + 1];
      if (timeMs < left.timeMs || timeMs > right.timeMs) continue;
      if (left.interpolation == Interpolation.hold) return left.value;

      final span = right.timeMs - left.timeMs;
      if (span <= 0) return right.value;
      var t = (timeMs - left.timeMs) / span;
      t = switch (left.interpolation) {
        Interpolation.hold => 0,
        Interpolation.linear => t,
        Interpolation.easeIn => t * t,
        Interpolation.easeOut => 1 - math.pow(1 - t, 2).toDouble(),
        Interpolation.easeInOut => t < 0.5
            ? 2 * t * t
            : 1 - math.pow(-2 * t + 2, 2).toDouble() / 2,
      };
      return left.value + (right.value - left.value) * t;
    }
    return sorted.last.value;
  }

  KeyframeTrack upsert(ScalarKeyframe keyframe) {
    final updated = keyframes
        .where((item) => item.timeMs != keyframe.timeMs)
        .toList()
      ..add(keyframe)
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return KeyframeTrack(
      property: property,
      keyframes: updated,
      enabled: enabled,
    );
  }

  Map<String, Object> toJson() => {
        'property': property,
        'enabled': enabled,
        'keyframes': keyframes.map((item) => item.toJson()).toList(),
      };

  factory KeyframeTrack.fromJson(Map<String, Object?> json) =>
      KeyframeTrack(
        property: json['property'] as String? ?? 'opacity',
        enabled: json['enabled'] as bool? ?? true,
        keyframes: (json['keyframes'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => ScalarKeyframe.fromJson(
                  item.cast<String, Object?>(),
                ))
            .toList(),
      );
}

class MaskVertex {
  const MaskVertex({
    required this.anchor,
    this.inHandle = const Vector2(0, 0),
    this.outHandle = const Vector2(0, 0),
    this.smooth = false,
  });

  final Vector2 anchor;
  final Vector2 inHandle;
  final Vector2 outHandle;
  final bool smooth;
}

class MaskModel {
  const MaskModel({
    required this.id,
    required this.name,
    this.shape = MaskShape.rectangle,
    this.operation = MaskOperation.add,
    this.enabled = true,
    this.inverted = false,
    this.feather = 0,
    this.expansion = 0,
    this.opacity = 100,
    this.vertices = const [],
  });

  final String id;
  final String name;
  final MaskShape shape;
  final MaskOperation operation;
  final bool enabled;
  final bool inverted;
  final double feather;
  final double expansion;
  final double opacity;
  final List<MaskVertex> vertices;

  MaskModel copyWith({
    MaskShape? shape,
    MaskOperation? operation,
    bool? enabled,
    bool? inverted,
    double? feather,
    double? expansion,
    double? opacity,
    List<MaskVertex>? vertices,
  }) =>
      MaskModel(
        id: id,
        name: name,
        shape: shape ?? this.shape,
        operation: operation ?? this.operation,
        enabled: enabled ?? this.enabled,
        inverted: inverted ?? this.inverted,
        feather: feather ?? this.feather,
        expansion: expansion ?? this.expansion,
        opacity: opacity ?? this.opacity,
        vertices: vertices ?? this.vertices,
      );
}

class EffectInstance {
  const EffectInstance({
    required this.id,
    required this.effectId,
    required this.name,
    this.enabled = true,
    this.parameters = const {},
    this.keyframeTracks = const [],
  });

  final String id;
  final String effectId;
  final String name;
  final bool enabled;
  final Map<String, double> parameters;
  final List<KeyframeTrack> keyframeTracks;

  double parameterAt(String key, int timeMs, {double fallback = 0}) {
    final track = keyframeTracks.where((item) => item.property == key);
    if (track.isEmpty) return parameters[key] ?? fallback;
    return track.first.sample(timeMs, fallback: parameters[key] ?? fallback);
  }

  EffectInstance copyWith({
    bool? enabled,
    Map<String, double>? parameters,
    List<KeyframeTrack>? keyframeTracks,
  }) =>
      EffectInstance(
        id: id,
        effectId: effectId,
        name: name,
        enabled: enabled ?? this.enabled,
        parameters: parameters ?? this.parameters,
        keyframeTracks: keyframeTracks ?? this.keyframeTracks,
      );
}

class ShapeStyle {
  const ShapeStyle({
    this.primitive = ShapePrimitive.rectangle,
    this.fillColor = '#7C8CFF',
    this.strokeColor = '#FFFFFF',
    this.strokeWidth = 0,
    this.cornerRadius = 0,
    this.points = 5,
  });

  final ShapePrimitive primitive;
  final String fillColor;
  final String strokeColor;
  final double strokeWidth;
  final double cornerRadius;
  final int points;

  ShapeStyle copyWith({
    ShapePrimitive? primitive,
    String? fillColor,
    String? strokeColor,
    double? strokeWidth,
    double? cornerRadius,
    int? points,
  }) => ShapeStyle(
    primitive: primitive ?? this.primitive,
    fillColor: fillColor ?? this.fillColor,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    points: points ?? this.points,
  );
}

class CameraSettings {
  const CameraSettings({
    this.projection = 'perspective',
    this.fieldOfView = 50,
    this.focalLength = 50,
    this.focusDistance = 1000,
    this.aperture = 2.8,
    this.depthOfField = false,
  });

  final String projection;
  final double fieldOfView;
  final double focalLength;
  final double focusDistance;
  final double aperture;
  final bool depthOfField;

  CameraSettings copyWith({
    String? projection,
    double? fieldOfView,
    double? focalLength,
    double? focusDistance,
    double? aperture,
    bool? depthOfField,
  }) => CameraSettings(
    projection: projection ?? this.projection,
    fieldOfView: fieldOfView ?? this.fieldOfView,
    focalLength: focalLength ?? this.focalLength,
    focusDistance: focusDistance ?? this.focusDistance,
    aperture: aperture ?? this.aperture,
    depthOfField: depthOfField ?? this.depthOfField,
  );
}

class LightSettings {
  const LightSettings({
    this.kind = LightKind.directional,
    this.color = '#FFFFFF',
    this.intensity = 100,
    this.coneAngle = 45,
    this.castShadows = true,
    this.shadowSoftness = 20,
  });

  final LightKind kind;
  final String color;
  final double intensity;
  final double coneAngle;
  final bool castShadows;
  final double shadowSoftness;

  LightSettings copyWith({
    LightKind? kind,
    String? color,
    double? intensity,
    double? coneAngle,
    bool? castShadows,
    double? shadowSoftness,
  }) => LightSettings(
    kind: kind ?? this.kind,
    color: color ?? this.color,
    intensity: intensity ?? this.intensity,
    coneAngle: coneAngle ?? this.coneAngle,
    castShadows: castShadows ?? this.castShadows,
    shadowSoftness: shadowSoftness ?? this.shadowSoftness,
  );
}

class CompositionLayer {
  const CompositionLayer({
    required this.id,
    required this.name,
    required this.kind,
    this.startMs = 0,
    this.durationMs = 10000,
    this.enabled = true,
    this.solo = false,
    this.locked = false,
    this.parentId,
    this.sourceUri,
    this.sourceDocumentUri,
    this.sourceLayerIndex,
    this.textContent,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.transform = const LayerTransform(),
    this.blendMode = LayerBlendMode.normal,
    this.masks = const [],
    this.effects = const [],
    this.keyframeTracks = const [],
    this.shapeStyle,
    this.camera,
    this.light,
  });

  final String id;
  final String name;
  final LayerKind kind;
  final int startMs;
  final int durationMs;
  final bool enabled;
  final bool solo;
  final bool locked;
  final String? parentId;
  final String? sourceUri;
  final String? sourceDocumentUri;
  final int? sourceLayerIndex;
  final String? textContent;
  final int sourceWidth;
  final int sourceHeight;
  final LayerTransform transform;
  final LayerBlendMode blendMode;
  final List<MaskModel> masks;
  final List<EffectInstance> effects;
  final List<KeyframeTrack> keyframeTracks;
  final ShapeStyle? shapeStyle;
  final CameraSettings? camera;
  final LightSettings? light;

  int get endMs => startMs + durationMs;

  double valueAt(String property, int timeMs) {
    final track = keyframeTracks.where((item) => item.property == property);
    return track.isEmpty
        ? transform.valueFor(property)
        : track.first.sample(
            timeMs,
            fallback: transform.valueFor(property),
          );
  }

  CompositionLayer copyWith({
    String? name,
    int? startMs,
    int? durationMs,
    bool? enabled,
    bool? solo,
    bool? locked,
    String? parentId,
    bool clearParent = false,
    String? sourceUri,
    String? sourceDocumentUri,
    int? sourceLayerIndex,
    String? textContent,
    int? sourceWidth,
    int? sourceHeight,
    LayerTransform? transform,
    LayerBlendMode? blendMode,
    List<MaskModel>? masks,
    List<EffectInstance>? effects,
    List<KeyframeTrack>? keyframeTracks,
    ShapeStyle? shapeStyle,
    CameraSettings? camera,
    LightSettings? light,
  }) =>
      CompositionLayer(
        id: id,
        name: name ?? this.name,
        kind: kind,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        enabled: enabled ?? this.enabled,
        solo: solo ?? this.solo,
        locked: locked ?? this.locked,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        sourceUri: sourceUri ?? this.sourceUri,
        sourceDocumentUri: sourceDocumentUri ?? this.sourceDocumentUri,
        sourceLayerIndex: sourceLayerIndex ?? this.sourceLayerIndex,
        textContent: textContent ?? this.textContent,
        sourceWidth: sourceWidth ?? this.sourceWidth,
        sourceHeight: sourceHeight ?? this.sourceHeight,
        transform: transform ?? this.transform,
        blendMode: blendMode ?? this.blendMode,
        masks: masks ?? this.masks,
        effects: effects ?? this.effects,
        keyframeTracks: keyframeTracks ?? this.keyframeTracks,
        shapeStyle: shapeStyle ?? this.shapeStyle,
        camera: camera ?? this.camera,
        light: light ?? this.light,
      );
}

class CompositionTransition {
  const CompositionTransition({
    required this.id,
    required this.fromLayerId,
    required this.toLayerId,
    this.kind = TransitionKind.dissolve,
    this.durationMs = 500,
    this.startMs = 0,
  });

  final String id;
  final String fromLayerId;
  final String toLayerId;
  final TransitionKind kind;
  final int durationMs;
  final int startMs;
}

class PhotoshopLayerAsset {
  const PhotoshopLayerAsset({
    required this.sourceIndex,
    required this.name,
    required this.assetPath,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.opacity,
    required this.blendMode,
    required this.visible,
    required this.isGroup,
    this.isAdjustment = false,
    this.textContent,
  });

  final int sourceIndex;
  final String name;
  final String assetPath;
  final int left;
  final int top;
  final int width;
  final int height;
  final int opacity;
  final String blendMode;
  final bool visible;
  final bool isGroup;
  final bool isAdjustment;
  final String? textContent;
}

class CompositionDocument {
  const CompositionDocument({
    this.name = 'Untitled Composition',
    this.width = 1920,
    this.height = 1080,
    this.frameRate = 30,
    this.durationMs = 30000,
    this.layers = const [],
    this.transitions = const [],
    this.playheadMs = 0,
    this.selectedLayerId,
  });

  final String name;
  final int width;
  final int height;
  final double frameRate;
  final int durationMs;
  final List<CompositionLayer> layers;
  final List<CompositionTransition> transitions;
  final int playheadMs;
  final String? selectedLayerId;

  CompositionDocument copyWith({
    String? name,
    int? width,
    int? height,
    double? frameRate,
    int? durationMs,
    List<CompositionLayer>? layers,
    List<CompositionTransition>? transitions,
    int? playheadMs,
    String? selectedLayerId,
    bool clearSelectedLayer = false,
  }) =>
      CompositionDocument(
        name: name ?? this.name,
        width: width ?? this.width,
        height: height ?? this.height,
        frameRate: frameRate ?? this.frameRate,
        durationMs: durationMs ?? this.durationMs,
        layers: layers ?? this.layers,
        transitions: transitions ?? this.transitions,
        playheadMs: playheadMs ?? this.playheadMs,
        selectedLayerId: clearSelectedLayer ? null : (selectedLayerId ?? this.selectedLayerId),
      );

  CompositionLayer? get selectedLayer {
    for (final layer in layers) {
      if (layer.id == selectedLayerId) return layer;
    }
    return null;
  }
}
