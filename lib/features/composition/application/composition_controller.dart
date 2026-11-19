import 'package:flutter/foundation.dart';

import '../data/effect_catalog.dart';
import '../domain/composition_models.dart';

class CompositionController extends ChangeNotifier {
  CompositionController({
    CompositionDocument document = const CompositionDocument(),
  }) : _document = document {
    _nextId = document.layers.length + 1;
  }

  CompositionDocument _document;
  int _nextId = 1;

  CompositionDocument get document => _document;
  CompositionLayer? get selectedLayer => _document.selectedLayer;

  String _id(String prefix) => '${prefix}_${_nextId++}';

  void _set(CompositionDocument next) {
    _document = next;
    notifyListeners();
  }

  CompositionLayer _defaultLayer(LayerKind kind, {String? name}) {
    final id = _id(kind.name);
    final duration = _document.durationMs;
    return CompositionLayer(
      id: id,
      name: name ?? switch (kind) {
        LayerKind.nullObject => 'Null ${_nextId - 1}',
        LayerKind.adjustment => 'Adjustment ${_nextId - 1}',
        LayerKind.camera => 'Camera ${_nextId - 1}',
        LayerKind.light => 'Light ${_nextId - 1}',
        LayerKind.shape => 'Shape ${_nextId - 1}',
        LayerKind.photoshopLayer => 'Photoshop Layer ${_nextId - 1}',
        _ => '${kind.name[0].toUpperCase()}${kind.name.substring(1)} ${_nextId - 1}',
      },
      kind: kind,
      durationMs: duration,
      transform: const LayerTransform(),
      shapeStyle: kind == LayerKind.shape ? const ShapeStyle() : null,
      camera: kind == LayerKind.camera ? const CameraSettings() : null,
      light: kind == LayerKind.light ? const LightSettings() : null,
    );
  }

  String addLayer(
    LayerKind kind, {
    String? name,
    String? sourceUri,
    int sourceWidth = 0,
    int sourceHeight = 0,
  }) {
    final layer = _defaultLayer(kind, name: name).copyWith(
      sourceUri: sourceUri,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
    _set(_document.copyWith(
      layers: [layer, ..._document.layers],
      selectedLayerId: layer.id,
    ));
    return layer.id;
  }

  void addPhotoshopLayers({
    required String sourceDocumentUri,
    required int documentWidth,
    required int documentHeight,
    required List<PhotoshopLayerAsset> assets,
  }) {
    final layers = <CompositionLayer>[];
    for (final asset in assets.where((item) => !item.isGroup)) {
      final kind = asset.textContent != null
          ? LayerKind.text
          : asset.isAdjustment
              ? LayerKind.adjustment
              : LayerKind.photoshopLayer;
      final original = _defaultLayer(
        kind,
        name: asset.name.trim().isEmpty
            ? 'Photoshop Layer ${asset.sourceIndex + 1}'
            : asset.name,
      );
      final initialTransform = LayerTransform(
        position: Vector3(
          asset.left + asset.width / 2,
          asset.top + asset.height / 2,
          0,
        ),
        opacity: asset.opacity / 255 * 100,
      );
      layers.add(original.copyWith(
        sourceUri: asset.assetPath.isEmpty ? null : asset.assetPath,
        sourceDocumentUri: sourceDocumentUri,
        sourceLayerIndex: asset.sourceIndex,
        textContent: asset.textContent,
        sourceWidth: asset.width,
        sourceHeight: asset.height,
        enabled: asset.visible,
        blendMode: _photoshopLayerBlendMode(asset.blendMode),
        transform: initialTransform,
      ));
    }
    _set(_document.copyWith(
      width: documentWidth,
      height: documentHeight,
      name: sourceDocumentUri.split(RegExp(r'[/\\]')).last,
      layers: [...layers, ..._document.layers],
      selectedLayerId: layers.isEmpty ? _document.selectedLayerId : layers.first.id,
    ));
  }

  LayerBlendMode _photoshopLayerBlendMode(String mode) => switch (mode) {
    'mul ' => LayerBlendMode.multiply,
    'scrn' => LayerBlendMode.screen,
    'over' => LayerBlendMode.overlay,
    'sLit' => LayerBlendMode.softLight,
    'hLit' => LayerBlendMode.hardLight,
    'dodge' => LayerBlendMode.colorDodge,
    'div ' => LayerBlendMode.colorBurn,
    'diff' => LayerBlendMode.difference,
    'dark' => LayerBlendMode.darken,
    'lite' => LayerBlendMode.lighten,
    'add ' => LayerBlendMode.add,
    _ => LayerBlendMode.normal,
  };

  void setLayerBlendMode(LayerBlendMode mode) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(blendMode: mode));
  }

  void selectLayer(String? id) {
    if (id != null && !_document.layers.any((layer) => layer.id == id)) return;
    _set(_document.copyWith(selectedLayerId: id));
  }

  void removeSelectedLayer() {
    final selected = selectedLayer;
    if (selected == null) return;
    final remaining = _document.layers
        .where((layer) => layer.id != selected.id)
        .map((layer) => layer.parentId == selected.id
            ? layer.copyWith(clearParent: true)
            : layer)
        .toList();
    _set(_document.copyWith(
      layers: remaining,
      selectedLayerId: remaining.isEmpty ? null : remaining.first.id,
      transitions: _document.transitions
          .where((item) =>
              item.fromLayerId != selected.id && item.toLayerId != selected.id)
          .toList(),
    ));
  }

  void reorderLayer(String id, int newIndex) {
    final layers = [..._document.layers];
    final oldIndex = layers.indexWhere((layer) => layer.id == id);
    if (oldIndex < 0) return;
    final item = layers.removeAt(oldIndex);
    final target = newIndex.clamp(0, layers.length).toInt();
    layers.insert(target, item);
    _set(_document.copyWith(layers: layers));
  }

  bool setParent(String childId, String? parentId) {
    final child = _find(childId);
    if (child == null) return false;
    if (parentId == childId) return false;
    if (parentId != null) {
      final parent = _find(parentId);
      if (parent == null) return false;
      if (parent.kind != LayerKind.nullObject &&
          parent.kind != LayerKind.threeDModel &&
          parent.kind != LayerKind.camera) {
        return false;
      }
      var cursor = parent;
      final visited = <String>{childId};
      while (cursor.parentId != null) {
        if (!visited.add(cursor.id)) return false;
        if (cursor.parentId == childId) return false;
        final next = _find(cursor.parentId!);
        if (next == null) break;
        cursor = next;
      }
    }
    _replace(child.copyWith(parentId: parentId, clearParent: parentId == null));
    return true;
  }

  void addMask({
    MaskShape shape = MaskShape.rectangle,
    MaskOperation operation = MaskOperation.add,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;
    final mask = MaskModel(
      id: _id('mask'),
      name: '${shape.name} mask',
      shape: shape,
      operation: operation,
      vertices: shape == MaskShape.bezier || shape == MaskShape.polygon
          ? const [
              MaskVertex(anchor: Vector2(0.2, 0.2)),
              MaskVertex(anchor: Vector2(0.8, 0.2)),
              MaskVertex(anchor: Vector2(0.8, 0.8)),
              MaskVertex(anchor: Vector2(0.2, 0.8)),
            ]
          : const [],
    );
    _replace(layer.copyWith(masks: [...layer.masks, mask]));
  }

  void setMaskEnabled(String maskId, bool enabled) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      masks: layer.masks
          .map((mask) => mask.id == maskId
              ? mask.copyWith(enabled: enabled)
              : mask)
          .toList(),
    ));
  }

  void setMaskParameters(
    String maskId, {
    MaskOperation? operation,
    double? feather,
    double? expansion,
    double? opacity,
    bool? inverted,
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      masks: layer.masks.map((mask) {
        if (mask.id != maskId) return mask;
        return mask.copyWith(
          operation: operation,
          feather: feather,
          expansion: expansion,
          opacity: opacity,
          inverted: inverted,
          left: left,
          top: top,
          width: width,
          height: height,
        );
      }).toList(),
    ));
  }

  void addEffect(String effectId) {
    final layer = selectedLayer;
    final definition = EffectCatalog.find(effectId);
    if (layer == null || definition == null) return;
    final parameters = {
      for (final parameter in definition.parameters)
        parameter.id: parameter.defaultValue,
    };
    _replace(layer.copyWith(
      effects: [
        ...layer.effects,
        EffectInstance(
          id: _id('effect'),
          effectId: effectId,
          name: definition.name,
          parameters: parameters,
        ),
      ],
    ));
  }

  void setEffectEnabled(String effectInstanceId, bool enabled) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      effects: layer.effects
          .map((effect) => effect.id == effectInstanceId
              ? effect.copyWith(enabled: enabled)
              : effect)
          .toList(),
    ));
  }

  void setEffectParameter(
    String effectInstanceId,
    String parameterId,
    double value, {
    bool keyframe = false,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      effects: layer.effects.map((effect) {
        if (effect.id != effectInstanceId) return effect;
        final definition = EffectCatalog.find(effect.effectId);
        final parameter = definition?.parameters
            .where((item) => item.id == parameterId)
            .firstOrNull;
        if (parameter == null) return effect;
        final clamped = value.clamp(parameter.min, parameter.max).toDouble();
        if (keyframe) {
          final existingIndex = effect.keyframeTracks.indexWhere(
            (track) => track.property == parameterId,
          );
          final track = existingIndex < 0
              ? KeyframeTrack(property: parameterId)
              : effect.keyframeTracks[existingIndex];
          final updated = track.upsert(ScalarKeyframe(
            timeMs: _document.playheadMs,
            value: clamped,
            interpolation: Interpolation.easeInOut,
          ));
          final tracks = [...effect.keyframeTracks];
          if (existingIndex < 0) {
            tracks.add(updated);
          } else {
            tracks[existingIndex] = updated;
          }
          return effect.copyWith(keyframeTracks: tracks);
        }
        final values = Map<String, double>.from(effect.parameters)
          ..[parameterId] = clamped;
        return effect.copyWith(parameters: values);
      }).toList(),
    ));
  }

  void addEffectKeyframe(String effectInstanceId, String parameterId) {
    final layer = selectedLayer;
    if (layer == null) return;
    final effect = layer.effects.where((item) => item.id == effectInstanceId).firstOrNull;
    if (effect == null) return;
    final definition = EffectCatalog.find(effect.effectId);
    final parameter = definition?.parameters
        .where((item) => item.id == parameterId)
        .firstOrNull;
    if (parameter == null) return;
    setEffectParameter(
      effectInstanceId,
      parameterId,
      effect.parameterAt(
        parameterId,
        _document.playheadMs,
        fallback: parameter.defaultValue,
      ),
      keyframe: true,
    );
  }

  void addKeyframe(String property, {double? value}) {
    final layer = selectedLayer;
    if (layer == null) return;
    final currentValue = value ?? layer.transform.valueFor(property);
    final index = layer.keyframeTracks.indexWhere(
      (track) => track.property == property,
    );
    final track = index < 0
        ? KeyframeTrack(property: property)
        : layer.keyframeTracks[index];
    final updated = track.upsert(ScalarKeyframe(
      timeMs: _document.playheadMs,
      value: currentValue,
      interpolation: Interpolation.easeInOut,
    ));
    final tracks = [...layer.keyframeTracks];
    if (index < 0) {
      tracks.add(updated);
    } else {
      tracks[index] = updated;
    }
    _replace(layer.copyWith(keyframeTracks: tracks));
  }

  void setTransformValue(String property, double value, {bool keyframe = false}) {
    final layer = selectedLayer;
    if (layer == null) return;
    if (keyframe) {
      final trackIndex = layer.keyframeTracks.indexWhere(
        (track) => track.property == property,
      );
      final track = trackIndex < 0
          ? KeyframeTrack(property: property)
          : layer.keyframeTracks[trackIndex];
      final updated = track.upsert(ScalarKeyframe(
        timeMs: _document.playheadMs,
        value: value,
        interpolation: Interpolation.easeInOut,
      ));
      final tracks = [...layer.keyframeTracks];
      if (trackIndex < 0) {
        tracks.add(updated);
      } else {
        tracks[trackIndex] = updated;
      }
      _replace(layer.copyWith(keyframeTracks: tracks));
    } else {
      _replace(layer.copyWith(
        transform: layer.transform.withValue(property, value),
      ));
    }
  }

  void setInterpolation(
    String property,
    Interpolation interpolation, {
    String? effectId,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;

    KeyframeTrack update(KeyframeTrack track) {
      if (track.property != property) return track;
      final frameIndex = track.keyframes.indexWhere(
        (item) => item.timeMs == _document.playheadMs,
      );
      if (frameIndex < 0) return track;
      final frames = [...track.keyframes];
      final old = frames[frameIndex];
      frames[frameIndex] = ScalarKeyframe(
        timeMs: old.timeMs,
        value: old.value,
        interpolation: interpolation,
        inTangent: old.inTangent,
        outTangent: old.outTangent,
        bezier: old.bezier,
      );
      return KeyframeTrack(property: track.property, keyframes: frames);
    }

    final tracks = layer.keyframeTracks.map(update).toList();
    final effects = layer.effects.map((effect) {
      if (effectId != null && effect.id != effectId) return effect;
      return effect.copyWith(
        keyframeTracks: effect.keyframeTracks.map(update).toList(),
      );
    }).toList();
    _replace(layer.copyWith(keyframeTracks: tracks, effects: effects));
  }

  void setBezierCurve(
    String property,
    BezierCurve curve, {
    String? effectId,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;

    KeyframeTrack update(KeyframeTrack track) {
      if (track.property != property) return track;
      final frameIndex = track.keyframes.indexWhere(
        (item) => item.timeMs == _document.playheadMs,
      );
      if (frameIndex < 0) return track;
      final frames = [...track.keyframes];
      final old = frames[frameIndex];
      frames[frameIndex] = ScalarKeyframe(
        timeMs: old.timeMs,
        value: old.value,
        interpolation: Interpolation.cubicBezier,
        inTangent: old.inTangent,
        outTangent: old.outTangent,
        bezier: curve,
      );
      return KeyframeTrack(
        property: track.property,
        keyframes: frames,
        enabled: track.enabled,
      );
    }

    final tracks = layer.keyframeTracks.map(update).toList();
    final effects = layer.effects.map((effect) {
      if (effectId != null && effect.id != effectId) return effect;
      return effect.copyWith(
        keyframeTracks: effect.keyframeTracks.map(update).toList(),
      );
    }).toList();
    _replace(layer.copyWith(keyframeTracks: tracks, effects: effects));
  }

  void addTransition(TransitionKind kind) {
    const visualKinds = {
      LayerKind.video,
      LayerKind.image,
      LayerKind.photoshopLayer,
    };
    final candidates = _document.layers
        .where((layer) => layer.enabled && visualKinds.contains(layer.kind))
        .toList();
    if (candidates.length < 2) return;
    final selectedIndex = candidates.indexWhere(
      (layer) => layer.id == _document.selectedLayerId,
    );
    final toIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final fromIndex = toIndex == 0 ? 1 : toIndex;
    final destinationIndex = toIndex == 0 ? 0 : toIndex - 1;
    final transition = CompositionTransition(
      id: _id('transition'),
      fromLayerId: candidates[fromIndex].id,
      toLayerId: candidates[destinationIndex].id,
      kind: kind,
      startMs: _document.playheadMs,
    );
    _set(_document.copyWith(
      transitions: [..._document.transitions, transition],
    ));
  }

  void updateTransition(
    String id, {
    TransitionKind? kind,
    int? durationMs,
    int? startMs,
  }) {
    final index = _document.transitions.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final current = _document.transitions[index];
    final updated = current.copyWith(
      kind: kind,
      durationMs: durationMs?.clamp(50, 10000).toInt(),
      startMs: startMs?.clamp(0, _document.durationMs - 1).toInt(),
    );
    final transitions = [..._document.transitions];
    transitions[index] = updated;
    _set(_document.copyWith(transitions: transitions));
  }

  void removeTransition(String id) {
    final transitions = _document.transitions
        .where((item) => item.id != id)
        .toList();
    if (transitions.length == _document.transitions.length) return;
    _set(_document.copyWith(transitions: transitions));
  }

  void setCanvasSize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    _set(_document.copyWith(width: width, height: height));
  }

  void setPlayhead(int timeMs) {
    _set(_document.copyWith(
      playheadMs: timeMs.clamp(0, _document.durationMs).toInt(),
    ));
  }

  void setLayerTiming(
    String id, {
    int? startMs,
    int? durationMs,
    int? sourceInMs,
  }) {
    final layer = _find(id);
    if (layer == null || layer.locked) return;
    final nextStart = (startMs ?? layer.startMs)
        .clamp(0, _document.durationMs - 1)
        .toInt();
    final maxDuration = _document.durationMs - nextStart;
    final nextDuration = (durationMs ?? layer.durationMs)
        .clamp(1, maxDuration)
        .toInt();
    final nextSourceIn = (sourceInMs ?? layer.sourceInMs)
        .clamp(0, 1 << 30)
        .toInt();
    _replace(layer.copyWith(
      startMs: nextStart,
      durationMs: nextDuration,
      sourceInMs: nextSourceIn,
    ));
  }

  void setLayerEnabled(String id, bool enabled) {
    final layer = _find(id);
    if (layer == null) return;
    _replace(layer.copyWith(enabled: enabled));
  }

  void setShapeStyle(ShapeStyle style) {
    final layer = selectedLayer;
    if (layer == null || layer.kind != LayerKind.shape) return;
    _replace(layer.copyWith(shapeStyle: style));
  }

  void setCameraSettings(CameraSettings settings) {
    final layer = selectedLayer;
    if (layer == null || layer.kind != LayerKind.camera) return;
    _replace(layer.copyWith(camera: settings));
  }

  void setLightSettings(LightSettings settings) {
    final layer = selectedLayer;
    if (layer == null || layer.kind != LayerKind.light) return;
    _replace(layer.copyWith(light: settings));
  }

  void setAudioSettings(AudioSettings settings) {
    final layer = selectedLayer;
    if (layer == null ||
        (layer.kind != LayerKind.audio && layer.kind != LayerKind.video)) return;
    _replace(layer.copyWith(audioSettings: settings));
  }

  void applyMotionTrack({
    required String layerId,
    required List<MotionTrackSample> samples,
    required int sourceWidth,
    required int sourceHeight,
    bool stabilize = true,
  }) {
    final layer = _find(layerId);
    if (layer == null || layer.kind != LayerKind.video ||
        samples.length < 2 || sourceWidth <= 0 || sourceHeight <= 0) {
      return;
    }

    final initial = samples.first;
    final scaleX = _document.width / sourceWidth;
    final scaleY = _document.height / sourceHeight;
    final xIndex = layer.keyframeTracks.indexWhere(
      (track) => track.property == 'position.x',
    );
    final yIndex = layer.keyframeTracks.indexWhere(
      (track) => track.property == 'position.y',
    );
    var xTrack = xIndex < 0
        ? const KeyframeTrack(property: 'position.x')
        : layer.keyframeTracks[xIndex];
    var yTrack = yIndex < 0
        ? const KeyframeTrack(property: 'position.y')
        : layer.keyframeTracks[yIndex];

    for (final sample in samples) {
      final timeMs = layer.startMs + sample.timeMs;
      final direction = stabilize ? -1.0 : 1.0;
      final x = layer.transform.position.x +
          (sample.x - initial.x) * scaleX * direction;
      final y = layer.transform.position.y +
          (sample.y - initial.y) * scaleY * direction;
      xTrack = xTrack.upsert(ScalarKeyframe(
        timeMs: timeMs,
        value: x,
        interpolation: Interpolation.easeInOut,
      ));
      yTrack = yTrack.upsert(ScalarKeyframe(
        timeMs: timeMs,
        value: y,
        interpolation: Interpolation.easeInOut,
      ));
    }

    final tracks = [...layer.keyframeTracks];
    if (xIndex < 0) {
      tracks.add(xTrack);
    } else {
      tracks[xIndex] = xTrack;
    }
    if (yIndex < 0) {
      tracks.add(yTrack);
    } else {
      tracks[yIndex] = yTrack;
    }
    _replace(layer.copyWith(keyframeTracks: tracks));
  }

  void setAudioGain(double value, {bool keyframe = false}) {
    final layer = selectedLayer;
    if (layer == null ||
        (layer.kind != LayerKind.audio && layer.kind != LayerKind.video)) return;
    if (!keyframe) {
      _replace(layer.copyWith(
        audioSettings: layer.audioSettings.copyWith(gainDb: value),
      ));
      return;
    }
    final index = layer.keyframeTracks.indexWhere(
      (track) => track.property == 'audio.gainDb',
    );
    final track = index < 0
        ? KeyframeTrack(property: 'audio.gainDb')
        : layer.keyframeTracks[index];
    final updated = track.upsert(ScalarKeyframe(
      timeMs: _document.playheadMs,
      value: value.clamp(-60, 12).toDouble(),
      interpolation: Interpolation.easeInOut,
    ));
    final tracks = [...layer.keyframeTracks];
    if (index < 0) {
      tracks.add(updated);
    } else {
      tracks[index] = updated;
    }
    _replace(layer.copyWith(keyframeTracks: tracks));
  }

  void setLayerLocked(String id, bool locked) {
    final layer = _find(id);
    if (layer == null) return;
    _replace(layer.copyWith(locked: locked));
  }

  CompositionLayer? _find(String id) {
    for (final layer in _document.layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  void _replace(CompositionLayer updated) {
    _set(_document.copyWith(
      layers: _document.layers
          .map((layer) => layer.id == updated.id ? updated : layer)
          .toList(),
    ));
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
