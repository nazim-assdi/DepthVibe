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
  average,
  bleach,
  divide,
  extremity,
  freeze,
  glow,
  grainExtract,
  grainMerge,
  hardMix,
  hardOverlay,
  heat,
  interpolate,
  linearLight,
  multiply128,
  negation,
  bitwiseAnd,
  bitwiseOr,
  phoenix,
  pinLight,
  reflect,
  softDifference,
  stain,
  subtract,
  vividLight,
  bitwiseXor,
  geometric,
  harmonic,
}

enum ShapePrimitive { rectangle, roundedRectangle, ellipse, polygon, star, path }

enum MaskShape { rectangle, ellipse, polygon, bezier }

enum MaskOperation { add, subtract, intersect, difference }

enum LightKind { ambient, directional, point, spot, area }

enum Interpolation { hold, linear, easeIn, easeOut, easeInOut, cubicBezier }

enum TransitionKind {
  dissolve, fadeThroughColor,
  wipeLeft, wipeRight, wipeUp, wipeDown,
  slideLeft, slideRight, slideUp, slideDown,
  zoomIn, zoomOut, blur, luma,
  circleCrop, rectangleCrop, distance, fadeBlack, fadeWhite, radial,
  smoothLeft, smoothRight, smoothUp, smoothDown,
  circleOpen, circleClose, verticalOpen, verticalClose,
  horizontalOpen, horizontalClose, pixelize,
  diagonalTopLeft, diagonalTopRight, diagonalBottomLeft, diagonalBottomRight,
  horizontalLeftSlice, horizontalRightSlice, verticalUpSlice, verticalDownSlice,
  horizontalBlur, fadeGrays,
  wipeTopLeft, wipeTopRight, wipeBottomLeft, wipeBottomRight,
  squeezeHorizontal, squeezeVertical, fadeFast, fadeSlow,
  horizontalLeftWind, horizontalRightWind, verticalUpWind, verticalDownWind,
  coverLeft, coverRight, coverUp, coverDown,
  revealLeft, revealRight, revealUp, revealDown,
}

enum AudioDuckingRole { none, background, trigger }

enum ColorOutputProfile { rec709, hdr10Pq, hlg }

class AudioSettings {
  const AudioSettings({
    this.gainDb = 0,
    this.pan = 0,
    this.muted = false,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.duckingRole = AudioDuckingRole.none,
    this.duckingThreshold = 0.05,
    this.duckingRatio = 8,
    this.duckingAttackMs = 20,
    this.duckingReleaseMs = 250,
    this.lowEqDb = 0,
    this.midEqDb = 0,
    this.highEqDb = 0,
    this.busId,
  });

  final double gainDb;
  final double pan;
  final bool muted;
  final int fadeInMs;
  final int fadeOutMs;
  final AudioDuckingRole duckingRole;
  final double duckingThreshold;
  final double duckingRatio;
  final double duckingAttackMs;
  final double duckingReleaseMs;
  final double lowEqDb;
  final double midEqDb;
  final double highEqDb;
  final String? busId;

  AudioSettings copyWith({
    double? gainDb,
    double? pan,
    bool? muted,
    int? fadeInMs,
    int? fadeOutMs,
    AudioDuckingRole? duckingRole,
    double? duckingThreshold,
    double? duckingRatio,
    double? duckingAttackMs,
    double? duckingReleaseMs,
    double? lowEqDb,
    double? midEqDb,
    double? highEqDb,
    String? busId,
    bool clearBus = false,
  }) => AudioSettings(
    gainDb: gainDb ?? this.gainDb,
    pan: pan ?? this.pan,
    muted: muted ?? this.muted,
    fadeInMs: fadeInMs ?? this.fadeInMs,
    fadeOutMs: fadeOutMs ?? this.fadeOutMs,
    duckingRole: duckingRole ?? this.duckingRole,
    duckingThreshold: duckingThreshold ?? this.duckingThreshold,
    duckingRatio: duckingRatio ?? this.duckingRatio,
    duckingAttackMs: duckingAttackMs ?? this.duckingAttackMs,
    duckingReleaseMs: duckingReleaseMs ?? this.duckingReleaseMs,
    lowEqDb: lowEqDb ?? this.lowEqDb,
    midEqDb: midEqDb ?? this.midEqDb,
    highEqDb: highEqDb ?? this.highEqDb,
    busId: clearBus ? null : (busId ?? this.busId),
  );
}

/// A routed audio submix with bus-level gain, pan and dynamics.
class AudioBus {
  const AudioBus({
    required this.id,
    required this.name,
    this.isMaster = false,
    this.gainDb = 0,
    this.pan = 0,
    this.muted = false,
    this.compressorEnabled = false,
    this.compressorThresholdDb = -18,
    this.compressorRatio = 3,
    this.compressorAttackMs = 15,
    this.compressorReleaseMs = 180,
    this.makeupGainDb = 0,
    this.limiterEnabled = false,
    this.limiterCeilingDb = -1,
    this.keyframeTracks = const [],
  });

  final String id;
  final String name;
  final bool isMaster;
  final double gainDb;
  final double pan;
  final bool muted;
  final bool compressorEnabled;
  final double compressorThresholdDb;
  final double compressorRatio;
  final double compressorAttackMs;
  final double compressorReleaseMs;
  final double makeupGainDb;
  final bool limiterEnabled;
  final double limiterCeilingDb;
  final List<KeyframeTrack> keyframeTracks;

  double valueAt(String property, int timeMs) {
    final fallback = switch (property) {
      'gainDb' => gainDb,
      'pan' => pan,
      _ => 0.0,
    };
    final matching = keyframeTracks.where(
      (track) => track.property == property && track.enabled,
    );
    return matching.isEmpty
        ? fallback
        : matching.first.sample(timeMs, fallback: fallback);
  }

  AudioBus copyWith({
    String? name,
    double? gainDb,
    double? pan,
    bool? muted,
    bool? compressorEnabled,
    double? compressorThresholdDb,
    double? compressorRatio,
    double? compressorAttackMs,
    double? compressorReleaseMs,
    double? makeupGainDb,
    bool? limiterEnabled,
    double? limiterCeilingDb,
    List<KeyframeTrack>? keyframeTracks,
  }) => AudioBus(
        id: id,
        name: name ?? this.name,
        isMaster: isMaster,
        gainDb: gainDb ?? this.gainDb,
        pan: pan ?? this.pan,
        muted: muted ?? this.muted,
        compressorEnabled: compressorEnabled ?? this.compressorEnabled,
        compressorThresholdDb:
            compressorThresholdDb ?? this.compressorThresholdDb,
        compressorRatio: compressorRatio ?? this.compressorRatio,
        compressorAttackMs: compressorAttackMs ?? this.compressorAttackMs,
        compressorReleaseMs:
            compressorReleaseMs ?? this.compressorReleaseMs,
        makeupGainDb: makeupGainDb ?? this.makeupGainDb,
        limiterEnabled: limiterEnabled ?? this.limiterEnabled,
        limiterCeilingDb: limiterCeilingDb ?? this.limiterCeilingDb,
        keyframeTracks: keyframeTracks ?? this.keyframeTracks,
      );
}

class MotionTrackSample {
  const MotionTrackSample({
    required this.timeMs,
    required this.x,
    required this.y,
    this.score = 1,
  });

  final int timeMs;
  final double x;
  final double y;
  final double score;
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

/// Cubic Bezier easing controls in normalized time/value coordinates.
/// X controls are constrained to [0, 1] so the curve can be inverted safely.
class BezierCurve {
  const BezierCurve({
    this.x1 = 0.25,
    this.y1 = 0.1,
    this.x2 = 0.25,
    this.y2 = 1,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  double sample(double progress) {
    final target = progress.clamp(0.0, 1.0).toDouble();
    if (target == 0 || target == 1) return target;

    final controlX1 = x1.clamp(0.0, 1.0).toDouble();
    final controlX2 = x2.clamp(0.0, 1.0).toDouble();
    var lower = 0.0;
    var upper = 1.0;
    var parameter = target;

    // Bisection is stable even for flat handles where Newton iteration
    // can have a near-zero derivative.
    for (var iteration = 0; iteration < 28; iteration++) {
      final inverse = 1 - parameter;
      final x = 3 * inverse * inverse * parameter * controlX1 +
          3 * inverse * parameter * parameter * controlX2 +
          parameter * parameter * parameter;
      if ((x - target).abs() < 1e-8) break;
      if (x < target) {
        lower = parameter;
      } else {
        upper = parameter;
      }
      parameter = (lower + upper) / 2;
    }

    final inverse = 1 - parameter;
    return (3 * inverse * inverse * parameter * y1 +
            3 * inverse * parameter * parameter * y2 +
            parameter * parameter * parameter)
        .toDouble();
  }

  Map<String, Object> toJson() => {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
      };

  factory BezierCurve.fromJson(Map<String, Object?> json) => BezierCurve(
        x1: (json['x1'] as num?)?.toDouble() ?? 0.25,
        y1: (json['y1'] as num?)?.toDouble() ?? 0.1,
        x2: (json['x2'] as num?)?.toDouble() ?? 0.25,
        y2: (json['y2'] as num?)?.toDouble() ?? 1,
      );
}

class ScalarKeyframe {
  const ScalarKeyframe({
    required this.timeMs,
    required this.value,
    this.interpolation = Interpolation.linear,
    this.inTangent = 0,
    this.outTangent = 0,
    this.bezier = const BezierCurve(),
    this.metadata = const {},
  });

  final int timeMs;
  final double value;
  final Interpolation interpolation;
  final double inTangent;
  final double outTangent;
  final BezierCurve bezier;
  /// Host-specific keyframe curve metadata retained for interchange.
  final Map<String, Object> metadata;

  Map<String, Object> toJson() => {
        'timeMs': timeMs,
        'value': value,
        'interpolation': interpolation.name,
        'inTangent': inTangent,
        'outTangent': outTangent,
        'bezier': bezier.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ScalarKeyframe.fromJson(Map<String, Object?> json) {
    final rawBezier = json['bezier'];
    final rawMetadata = json['metadata'];
    final metadata = <String, Object>{};
    if (rawMetadata is Map) {
      for (final entry in rawMetadata.entries) {
        if (entry.key is String && entry.value != null) {
          metadata[entry.key as String] = entry.value as Object;
        }
      }
    }
    return ScalarKeyframe(
      timeMs: (json['timeMs'] as num?)?.toInt() ?? 0,
      value: (json['value'] as num?)?.toDouble() ?? 0,
      interpolation: Interpolation.values.firstWhere(
        (item) => item.name == json['interpolation'],
        orElse: () => Interpolation.linear,
      ),
      inTangent: (json['inTangent'] as num?)?.toDouble() ?? 0,
      outTangent: (json['outTangent'] as num?)?.toDouble() ?? 0,
      bezier: rawBezier is Map
          ? BezierCurve.fromJson(rawBezier.cast<String, Object?>())
          : const BezierCurve(),
      metadata: metadata,
    );
  }
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
        Interpolation.cubicBezier => left.bezier.sample(t),
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

  MaskVertex copyWith({
    Vector2? anchor,
    Vector2? inHandle,
    Vector2? outHandle,
    bool? smooth,
  }) => MaskVertex(
        anchor: anchor ?? this.anchor,
        inHandle: inHandle ?? this.inHandle,
        outHandle: outHandle ?? this.outHandle,
        smooth: smooth ?? this.smooth,
      );
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
    this.left = 0.05,
    this.top = 0.05,
    this.width = 0.9,
    this.height = 0.9,
    this.vertices = const [],
    this.keyframeTracks = const [],
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
  final double left;
  final double top;
  final double width;
  final double height;
  final List<MaskVertex> vertices;
  final List<KeyframeTrack> keyframeTracks;

  double baseValue(String property) => switch (property) {
        'feather' => feather,
        'expansion' => expansion,
        'opacity' => opacity,
        'left' => left,
        'top' => top,
        'width' => width,
        'height' => height,
        _ => 0,
      };

  double valueAt(String property, int timeMs) {
    final matching = keyframeTracks.where(
      (track) => track.property == property && track.enabled,
    );
    if (matching.isEmpty) return baseValue(property);
    return matching.first.sample(timeMs, fallback: baseValue(property));
  }

  double vertexValueAt(int vertexIndex, String component, int timeMs) {
    if (vertexIndex < 0 || vertexIndex >= vertices.length) return 0;
    final vertex = vertices[vertexIndex];
    final property = 'vertex.$vertexIndex.$component';
    final fallback = switch (component) {
      'anchor.x' => vertex.anchor.x,
      'anchor.y' => vertex.anchor.y,
      'inHandle.x' => vertex.inHandle.x,
      'inHandle.y' => vertex.inHandle.y,
      'outHandle.x' => vertex.outHandle.x,
      'outHandle.y' => vertex.outHandle.y,
      _ => 0.0,
    };
    final matching = keyframeTracks.where(
      (track) => track.property == property,
    );
    return matching.isEmpty
        ? fallback
        : matching.first.sample(timeMs, fallback: fallback);
  }

  MaskModel copyWith({
    MaskShape? shape,
    MaskOperation? operation,
    bool? enabled,
    bool? inverted,
    double? feather,
    double? expansion,
    double? opacity,
    double? left,
    double? top,
    double? width,
    double? height,
    List<MaskVertex>? vertices,
    List<KeyframeTrack>? keyframeTracks,
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
        left: left ?? this.left,
        top: top ?? this.top,
        width: width ?? this.width,
        height: height ?? this.height,
        vertices: vertices ?? this.vertices,
        keyframeTracks: keyframeTracks ?? this.keyframeTracks,
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
    this.assetUri,
    this.assetInterpolation = 'trilinear',
  });

  final String id;
  final String effectId;
  final String name;
  final bool enabled;
  final Map<String, double> parameters;
  final String? assetUri;
  final String assetInterpolation;
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
    String? assetUri,
    bool clearAssetUri = false,
    String? assetInterpolation,
  }) =>
      EffectInstance(
        id: id,
        effectId: effectId,
        name: name,
        enabled: enabled ?? this.enabled,
        parameters: parameters ?? this.parameters,
        keyframeTracks: keyframeTracks ?? this.keyframeTracks,
        assetUri: clearAssetUri ? null : (assetUri ?? this.assetUri),
        assetInterpolation: assetInterpolation ?? this.assetInterpolation,
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
    this.nearClip = 50,
    this.farClip = 5000,
    this.aperture = 2.8,
    this.sensorWidthMm = 36,
    this.depthOfField = false,
  });

  final String projection;
  final double fieldOfView;
  final double focalLength;
  final double focusDistance;
  final double nearClip;
  final double farClip;
  final double aperture;
  final double sensorWidthMm;
  final bool depthOfField;

  CameraSettings copyWith({
    String? projection,
    double? fieldOfView,
    double? focalLength,
    double? focusDistance,
    double? nearClip,
    double? farClip,
    double? aperture,
    double? sensorWidthMm,
    bool? depthOfField,
  }) => CameraSettings(
    projection: projection ?? this.projection,
    fieldOfView: fieldOfView ?? this.fieldOfView,
    focalLength: focalLength ?? this.focalLength,
    focusDistance: focusDistance ?? this.focusDistance,
    nearClip: nearClip ?? this.nearClip,
    farClip: farClip ?? this.farClip,
    aperture: aperture ?? this.aperture,
    sensorWidthMm: sensorWidthMm ?? this.sensorWidthMm,
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
    this.areaSize = 160,
    this.areaSamples = 16,
  });

  final LightKind kind;
  final String color;
  final double intensity;
  final double coneAngle;
  final bool castShadows;
  final double shadowSoftness;
  final double areaSize;
  final int areaSamples;

  LightSettings copyWith({
    LightKind? kind,
    String? color,
    double? intensity,
    double? coneAngle,
    bool? castShadows,
    double? shadowSoftness,
    double? areaSize,
    int? areaSamples,
  }) => LightSettings(
    kind: kind ?? this.kind,
    color: color ?? this.color,
    intensity: intensity ?? this.intensity,
    coneAngle: coneAngle ?? this.coneAngle,
    castShadows: castShadows ?? this.castShadows,
    shadowSoftness: shadowSoftness ?? this.shadowSoftness,
    areaSize: areaSize ?? this.areaSize,
    areaSamples: areaSamples ?? this.areaSamples,
  );
}

class CompositionLayer {
  const CompositionLayer({
    required this.id,
    required this.name,
    required this.kind,
    this.startMs = 0,
    this.durationMs = 10000,
    this.sourceInMs = 0,
    this.enabled = true,
    this.solo = false,
    this.locked = false,
    this.parentId,
    this.sourceUri,
    this.sourceDocumentUri,
    this.sourceLayerIndex,
    this.externalSourceId,
    this.externalSourceName,
    this.externalHostApp,
    this.externalLayerIndex,
    this.interchangeMetadata = const {},
    this.textContent,
    this.textFontFamily,
    this.textFontAssetUri,
    this.textFontFallback = const [],
    this.textFontSize = 72,
    this.textFontWeight = 700,
    this.textItalic = false,
    this.textColor = '#FFFFFFFF',
    this.textLetterSpacing = 0,
    this.textLineHeight = 1.2,
    this.textAlign = 'left',
    this.textBoxWidth = 1000,
    this.clippingBaseLayerId,
    this.photoshopClipped = false,
    this.smartObjectSourceUri,
    this.smartObjectResourceId,
    this.photoshopAdjustmentKey,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.modelAnimationIndex = 0,
    this.transform = const LayerTransform(),
    this.blendMode = LayerBlendMode.normal,
    this.masks = const [],
    this.effects = const [],
    this.keyframeTracks = const [],
    this.shapeStyle,
    this.camera,
    this.light,
    this.audioSettings = const AudioSettings(),
  });

  final String id;
  final String name;
  final LayerKind kind;
  final int startMs;
  final int durationMs;
  final int sourceInMs;
  final bool enabled;
  final bool solo;
  final bool locked;
  final String? parentId;
  final String? sourceUri;
  final String? sourceDocumentUri;
  final int? sourceLayerIndex;
  /// Stable Adobe source identity for interchange round trips.
  final String? externalSourceId;
  final String? externalSourceName;
  final String? externalHostApp;
  final int? externalLayerIndex;
  /// Host-only metadata and unsupported effect data, retained as inert JSON.
  final Map<String, Object?> interchangeMetadata;
  final String? textContent;
  final String? textFontFamily;
  final String? textFontAssetUri;
  final List<String> textFontFallback;
  final double textFontSize;
  final int textFontWeight;
  final bool textItalic;
  final String textColor;
  final double textLetterSpacing;
  final double textLineHeight;
  final String textAlign;
  final double textBoxWidth;
  final String? clippingBaseLayerId;
  final bool photoshopClipped;
  final String? smartObjectSourceUri;
  final String? smartObjectResourceId;
  final String? photoshopAdjustmentKey;
  final int sourceWidth;
  final int sourceHeight;
  /// Selected embedded glTF clip; -1 keeps the model in its rest pose.
  final int modelAnimationIndex;
  final LayerTransform transform;
  final LayerBlendMode blendMode;
  final List<MaskModel> masks;
  final List<EffectInstance> effects;
  final List<KeyframeTrack> keyframeTracks;
  final ShapeStyle? shapeStyle;
  final CameraSettings? camera;
  final LightSettings? light;
  final AudioSettings audioSettings;

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
    int? sourceInMs,
    bool? enabled,
    bool? solo,
    bool? locked,
    String? parentId,
    bool clearParent = false,
    String? sourceUri,
    String? sourceDocumentUri,
    int? sourceLayerIndex,
    String? externalSourceId,
    String? externalSourceName,
    String? externalHostApp,
    int? externalLayerIndex,
    Map<String, Object?>? interchangeMetadata,
    String? textContent,
    String? textFontFamily,
    String? textFontAssetUri,
    List<String>? textFontFallback,
    double? textFontSize,
    int? textFontWeight,
    bool? textItalic,
    String? textColor,
    double? textLetterSpacing,
    double? textLineHeight,
    String? textAlign,
    double? textBoxWidth,
    bool clearTextFont = false,
    bool clearTextFontAsset = false,
    String? clippingBaseLayerId,
    bool clearClippingBase = false,
    bool? photoshopClipped,
    String? smartObjectSourceUri,
    bool clearSmartObjectSource = false,
    String? smartObjectResourceId,
    bool clearSmartObjectResource = false,
    String? photoshopAdjustmentKey,
    int? sourceWidth,
    int? sourceHeight,
    int? modelAnimationIndex,
    LayerTransform? transform,
    LayerBlendMode? blendMode,
    List<MaskModel>? masks,
    List<EffectInstance>? effects,
    List<KeyframeTrack>? keyframeTracks,
    ShapeStyle? shapeStyle,
    CameraSettings? camera,
    LightSettings? light,
    AudioSettings? audioSettings,
  }) =>
      CompositionLayer(
        id: id,
        name: name ?? this.name,
        kind: kind,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        sourceInMs: sourceInMs ?? this.sourceInMs,
        enabled: enabled ?? this.enabled,
        solo: solo ?? this.solo,
        locked: locked ?? this.locked,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        sourceUri: sourceUri ?? this.sourceUri,
        sourceDocumentUri: sourceDocumentUri ?? this.sourceDocumentUri,
        sourceLayerIndex: sourceLayerIndex ?? this.sourceLayerIndex,
        externalSourceId: externalSourceId ?? this.externalSourceId,
        externalSourceName: externalSourceName ?? this.externalSourceName,
        externalHostApp: externalHostApp ?? this.externalHostApp,
        externalLayerIndex: externalLayerIndex ?? this.externalLayerIndex,
        interchangeMetadata: interchangeMetadata ?? this.interchangeMetadata,
        textContent: textContent ?? this.textContent,
        textFontFamily: clearTextFont ? null : (textFontFamily ?? this.textFontFamily),
        textFontAssetUri: clearTextFont || clearTextFontAsset
            ? null
            : (textFontAssetUri ?? this.textFontAssetUri),
        textFontFallback: textFontFallback ?? this.textFontFallback,
        textFontSize: textFontSize ?? this.textFontSize,
        textFontWeight: textFontWeight ?? this.textFontWeight,
        textItalic: textItalic ?? this.textItalic,
        textColor: textColor ?? this.textColor,
        textLetterSpacing: textLetterSpacing ?? this.textLetterSpacing,
        textLineHeight: textLineHeight ?? this.textLineHeight,
        textAlign: textAlign ?? this.textAlign,
        textBoxWidth: textBoxWidth ?? this.textBoxWidth,
        clippingBaseLayerId: clearClippingBase
            ? null
            : (clippingBaseLayerId ?? this.clippingBaseLayerId),
        photoshopClipped: photoshopClipped ?? this.photoshopClipped,
        smartObjectSourceUri: clearSmartObjectSource
            ? null
            : (smartObjectSourceUri ?? this.smartObjectSourceUri),
        smartObjectResourceId: clearSmartObjectResource
            ? null
            : (smartObjectResourceId ?? this.smartObjectResourceId),
        photoshopAdjustmentKey:
            photoshopAdjustmentKey ?? this.photoshopAdjustmentKey,
        sourceWidth: sourceWidth ?? this.sourceWidth,
        sourceHeight: sourceHeight ?? this.sourceHeight,
        modelAnimationIndex: modelAnimationIndex ?? this.modelAnimationIndex,
        transform: transform ?? this.transform,
        blendMode: blendMode ?? this.blendMode,
        masks: masks ?? this.masks,
        effects: effects ?? this.effects,
        keyframeTracks: keyframeTracks ?? this.keyframeTracks,
        shapeStyle: shapeStyle ?? this.shapeStyle,
        camera: camera ?? this.camera,
        light: light ?? this.light,
        audioSettings: audioSettings ?? this.audioSettings,
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
    this.externalMatchName,
    this.metadata = const {},
  });

  final String id;
  final String fromLayerId;
  final String toLayerId;
  final TransitionKind kind;
  final int durationMs;
  final int startMs;
  /// Native Premiere/After Effects transition identifier, when imported.
  final String? externalMatchName;
  /// Original host transition descriptor retained for future round-trips.
  final Map<String, Object?> metadata;

  CompositionTransition copyWith({
    TransitionKind? kind,
    int? durationMs,
    int? startMs,
    String? externalMatchName,
    Map<String, Object?>? metadata,
  }) => CompositionTransition(
    id: id,
    fromLayerId: fromLayerId,
    toLayerId: toLayerId,
    kind: kind ?? this.kind,
    durationMs: durationMs ?? this.durationMs,
    startMs: startMs ?? this.startMs,
    externalMatchName: externalMatchName ?? this.externalMatchName,
    metadata: metadata ?? this.metadata,
  );
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
    this.parentGroupSourceIndex,
    this.clippingBaseSourceIndex,
    this.clipping = 0,
    this.smartObjectSourceUri,
    this.smartObjectResourceId,
    this.adjustmentKey,
    this.adjustmentEffects = const [],
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
  /// True only for the folder-opening record, not its closing divider.
  final bool isGroup;
  final bool isAdjustment;
  final String? textContent;
  final int? parentGroupSourceIndex;
  final int? clippingBaseSourceIndex;
  final int clipping;
  final String? smartObjectSourceUri;
  final String? smartObjectResourceId;
  final String? adjustmentKey;
  final List<EffectInstance> adjustmentEffects;
}

class CompositionDocument {
  const CompositionDocument({
    this.name = 'Untitled Composition',
    this.width = 1920,
    this.height = 1080,
    this.frameRate = 30,
    this.durationMs = 30000,
    this.colorOutputProfile = ColorOutputProfile.rec709,
    this.layers = const [],
    this.transitions = const [],
    this.audioBuses = const [
      AudioBus(id: 'master', name: 'Master', isMaster: true),
    ],
    this.playheadMs = 0,
    this.selectedLayerId,
  });

  final String name;
  final int width;
  final int height;
  final double frameRate;
  final int durationMs;
  final ColorOutputProfile colorOutputProfile;
  final List<CompositionLayer> layers;
  final List<CompositionTransition> transitions;
  final List<AudioBus> audioBuses;
  final int playheadMs;
  final String? selectedLayerId;

  CompositionDocument copyWith({
    String? name,
    int? width,
    int? height,
    double? frameRate,
    int? durationMs,
    ColorOutputProfile? colorOutputProfile,
    List<CompositionLayer>? layers,
    List<CompositionTransition>? transitions,
    List<AudioBus>? audioBuses,
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
        colorOutputProfile: colorOutputProfile ?? this.colorOutputProfile,
        layers: layers ?? this.layers,
        transitions: transitions ?? this.transitions,
        audioBuses: audioBuses ?? this.audioBuses,
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
