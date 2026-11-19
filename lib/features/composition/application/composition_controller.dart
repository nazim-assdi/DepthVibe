import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/effect_catalog.dart';
import '../domain/composition_models.dart';
import '../engine/transition_frame_validator.dart';

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
  int _frameAlignedTransitionStart(int milliseconds) {
    final fps = _document.frameRate;
    if (fps <= 0) return milliseconds.clamp(0, _document.durationMs - 1);
    final lastFrame =
        (((_document.durationMs - 1) * fps) / 1000).floor();
    final frame = (milliseconds * fps / 1000)
        .round()
        .clamp(0, lastFrame);
    return (frame * 1000 / fps).round();
  }

  int _frameAlignedTransitionDuration(int milliseconds) =>
      const TransitionFrameValidator().snapDurationToFrame(
        milliseconds.clamp(50, 10000),
        _document.frameRate,
      );


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
    final sourceIds = <int, String>{};

    for (final asset in assets) {
      final kind = asset.isGroup
          ? LayerKind.precomposition
          : asset.textContent != null
              ? LayerKind.text
              : asset.isAdjustment
                  ? LayerKind.adjustment
                  : LayerKind.photoshopLayer;
      final original = _defaultLayer(
        kind,
        name: asset.name.trim().isEmpty
            ? (asset.isGroup
                ? 'Group ${asset.sourceIndex + 1}'
                : 'Photoshop Layer ${asset.sourceIndex + 1}')
            : asset.name,
      );
      final hasBounds = asset.width > 0 && asset.height > 0;
      final initialTransform = LayerTransform(
        position: hasBounds
            ? Vector3(
                asset.left + asset.width / 2,
                asset.top + asset.height / 2,
                0,
              )
            : Vector3(documentWidth / 2, documentHeight / 2, 0),
        opacity: asset.opacity / 255 * 100,
      );
      final parentId = asset.parentGroupSourceIndex == null
          ? null
          : sourceIds[asset.parentGroupSourceIndex];
      final imported = original.copyWith(
        sourceUri: asset.assetPath.isEmpty ? null : asset.assetPath,
        sourceDocumentUri: sourceDocumentUri,
        sourceLayerIndex: asset.sourceIndex,
        textContent: asset.textContent,
        sourceWidth: asset.width,
        sourceHeight: asset.height,
        enabled: asset.visible,
        parentId: parentId,
        photoshopClipped: asset.clipping != 0,
        smartObjectSourceUri: asset.smartObjectSourceUri,
        smartObjectResourceId: asset.smartObjectResourceId,
        photoshopAdjustmentKey: asset.adjustmentKey,
        effects: asset.adjustmentEffects,
        transform: initialTransform,
      );
      layers.add(imported);
      sourceIds[asset.sourceIndex] = imported.id;
    }

    // Resolve group parents and clipping bases after all source records
    // have been assigned composition-layer IDs.
    for (var index = 0; index < layers.length; index++) {
      final sourceIndex = layers[index].sourceLayerIndex;
      if (sourceIndex == null) continue;
      final asset = assets.firstWhere(
        (item) => item.sourceIndex == sourceIndex,
      );
      final parentId = asset.parentGroupSourceIndex == null
          ? null
          : sourceIds[asset.parentGroupSourceIndex];
      final baseId = asset.clippingBaseSourceIndex == null
          ? null
          : sourceIds[asset.clippingBaseSourceIndex];
      layers[index] = layers[index].copyWith(
        parentId: parentId,
        clippingBaseLayerId: baseId,
        clearClippingBase: baseId == null,
      );
    }

    _set(_document.copyWith(
      width: documentWidth,
      height: documentHeight,
      name: sourceDocumentUri.split(RegExp(r'[/\\\\]')).last,
      layers: [...layers, ..._document.layers],
      selectedLayerId: layers.isEmpty ? _document.selectedLayerId : layers.first.id,
    ));
  }

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
          parent.kind != LayerKind.camera &&
          parent.kind != LayerKind.precomposition) {
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
      left: shape == MaskShape.bezier || shape == MaskShape.polygon ? 0.2 : 0.05,
      top: shape == MaskShape.bezier || shape == MaskShape.polygon ? 0.2 : 0.05,
      width: shape == MaskShape.bezier || shape == MaskShape.polygon ? 0.6 : 0.9,
      height: shape == MaskShape.bezier || shape == MaskShape.polygon ? 0.6 : 0.9,
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

  void setMaskVertex(
    String maskId,
    int vertexIndex, {
    Vector2? anchor,
    Vector2? inHandle,
    Vector2? outHandle,
    bool? smooth,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      masks: layer.masks.map((mask) {
        if (mask.id != maskId ||
            vertexIndex < 0 ||
            vertexIndex >= mask.vertices.length) {
          return mask;
        }
        final vertices = [...mask.vertices];
        final old = vertices[vertexIndex];
        final nextSmooth = smooth ?? old.smooth;
        var nextIn = inHandle ?? old.inHandle;
        var nextOut = outHandle ?? old.outHandle;

        double length(Vector2 value) =>
            math.sqrt(value.x * value.x + value.y * value.y);

        if (nextSmooth && inHandle != null) {
          final oppositeLength = length(old.outHandle);
          final movedLength = length(inHandle);
          final factor = movedLength == 0 ? 0 : oppositeLength / movedLength;
          nextOut = Vector2(-inHandle.x * factor, -inHandle.y * factor);
        } else if (nextSmooth && outHandle != null) {
          final oppositeLength = length(old.inHandle);
          final movedLength = length(outHandle);
          final factor = movedLength == 0 ? 0 : oppositeLength / movedLength;
          nextIn = Vector2(-outHandle.x * factor, -outHandle.y * factor);
        }

        vertices[vertexIndex] = old.copyWith(
          anchor: anchor,
          inHandle: nextIn,
          outHandle: nextOut,
          smooth: nextSmooth,
        );
        return mask.copyWith(vertices: vertices);
      }).toList(),
    ));
  }

  void keyframeMaskPath(String maskId) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      masks: layer.masks.map((mask) {
        if (mask.id != maskId || mask.vertices.length < 3) return mask;
        final tracks = [...mask.keyframeTracks];
        for (var index = 0; index < mask.vertices.length; index++) {
          final vertex = mask.vertices[index];
          final values = <String, double>{
            'anchor.x': vertex.anchor.x,
            'anchor.y': vertex.anchor.y,
            'inHandle.x': vertex.inHandle.x,
            'inHandle.y': vertex.inHandle.y,
            'outHandle.x': vertex.outHandle.x,
            'outHandle.y': vertex.outHandle.y,
          };
          for (final entry in values.entries) {
            final property = 'vertex.$index.${entry.key}';
            final trackIndex = tracks.indexWhere(
              (track) => track.property == property,
            );
            final track = trackIndex < 0
                ? KeyframeTrack(property: property)
                : tracks[trackIndex];
            final updated = track.upsert(ScalarKeyframe(
              timeMs: _document.playheadMs,
              value: entry.value,
              interpolation: Interpolation.easeInOut,
            ));
            if (trackIndex < 0) {
              tracks.add(updated);
            } else {
              tracks[trackIndex] = updated;
            }
          }
        }
        return mask.copyWith(keyframeTracks: tracks);
      }).toList(),
    ));
  }

  void setMaskVertexAnimatedValue(
    String maskId,
    int vertexIndex,
    String component,
    double value, {
    bool keyframe = false,
  }) {
    const components = {
      'anchor.x',
      'anchor.y',
      'inHandle.x',
      'inHandle.y',
      'outHandle.x',
      'outHandle.y',
    };
    if (!components.contains(component)) return;
    final layer = selectedLayer;
    if (layer == null) return;

    final property = 'vertex.$vertexIndex.$component';
    _replace(layer.copyWith(
      masks: layer.masks.map((mask) {
        if (mask.id != maskId ||
            vertexIndex < 0 ||
            vertexIndex >= mask.vertices.length) {
          return mask;
        }
        final bounded = component.startsWith('anchor.')
            ? value.clamp(-2.0, 3.0).toDouble()
            : value.clamp(-2.0, 2.0).toDouble();
        if (!keyframe) {
          final vertices = [...mask.vertices];
          final old = vertices[vertexIndex];
          final next = switch (component) {
            'anchor.x' => old.copyWith(
                anchor: Vector2(bounded, old.anchor.y),
              ),
            'anchor.y' => old.copyWith(
                anchor: Vector2(old.anchor.x, bounded),
              ),
            'inHandle.x' => old.copyWith(
                inHandle: Vector2(bounded, old.inHandle.y),
              ),
            'inHandle.y' => old.copyWith(
                inHandle: Vector2(old.inHandle.x, bounded),
              ),
            'outHandle.x' => old.copyWith(
                outHandle: Vector2(bounded, old.outHandle.y),
              ),
            'outHandle.y' => old.copyWith(
                outHandle: Vector2(old.outHandle.x, bounded),
              ),
            _ => old,
          };
          vertices[vertexIndex] = next;
          return mask.copyWith(vertices: vertices);
        }

        final index = mask.keyframeTracks.indexWhere(
          (track) => track.property == property,
        );
        final track = index < 0
            ? KeyframeTrack(property: property)
            : mask.keyframeTracks[index];
        final updated = track.upsert(ScalarKeyframe(
          timeMs: _document.playheadMs,
          value: bounded,
          interpolation: Interpolation.easeInOut,
        ));
        final tracks = [...mask.keyframeTracks];
        if (index < 0) {
          tracks.add(updated);
        } else {
          tracks[index] = updated;
        }
        return mask.copyWith(keyframeTracks: tracks);
      }).toList(),
    ));
  }

  void setMaskAnimatedValue(
    String maskId,
    String property,
    double value, {
    bool keyframe = false,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      masks: layer.masks.map((mask) {
        if (mask.id != maskId) return mask;
        if (!keyframe) {
          return switch (property) {
            'feather' => mask.copyWith(feather: value),
            'expansion' => mask.copyWith(expansion: value),
            'opacity' => mask.copyWith(opacity: value.clamp(0, 100).toDouble()),
            'left' => mask.copyWith(left: value.clamp(0, 1).toDouble()),
            'top' => mask.copyWith(top: value.clamp(0, 1).toDouble()),
            'width' => mask.copyWith(width: value.clamp(0.01, 1).toDouble()),
            'height' => mask.copyWith(height: value.clamp(0.01, 1).toDouble()),
            _ => mask,
          };
        }
        final index = mask.keyframeTracks.indexWhere(
          (track) => track.property == property,
        );
        final track = index < 0
            ? KeyframeTrack(property: property)
            : mask.keyframeTracks[index];
        final updated = track.upsert(ScalarKeyframe(
          timeMs: _document.playheadMs,
          value: value,
          interpolation: Interpolation.easeInOut,
        ));
        final tracks = [...mask.keyframeTracks];
        if (index < 0) {
          tracks.add(updated);
        } else {
          tracks[index] = updated;
        }
        return mask.copyWith(keyframeTracks: tracks);
      }).toList(),
    ));
  }

  void setMaskInterpolation(
    String maskId,
    String property,
    Interpolation interpolation, {
    int? timeMs,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;
    final targetTimeMs = timeMs ?? _document.playheadMs;
    _replace(layer.copyWith(
      masks: layer.masks.map((mask) {
        if (mask.id != maskId) return mask;
        final tracks = mask.keyframeTracks.map((track) {
          if (track.property != property) return track;
          final frameIndex = track.keyframes.indexWhere(
            (frame) => frame.timeMs == targetTimeMs,
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
          return KeyframeTrack(
            property: track.property,
            keyframes: frames,
            enabled: track.enabled,
          );
        }).toList();
        return mask.copyWith(keyframeTracks: tracks);
      }).toList(),
    ));
  }

  void setMaskBezierCurve(
    String maskId,
    String property,
    BezierCurve curve, {
    int? timeMs,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;
    final targetTimeMs = timeMs ?? _document.playheadMs;
    _replace(layer.copyWith(
      masks: layer.masks.map((mask) {
        if (mask.id != maskId) return mask;
        final tracks = mask.keyframeTracks.map((track) {
          if (track.property != property) return track;
          final frameIndex = track.keyframes.indexWhere(
            (frame) => frame.timeMs == targetTimeMs,
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
        }).toList();
        return mask.copyWith(keyframeTracks: tracks);
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
    int? timeMs,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;

    KeyframeTrack update(KeyframeTrack track) {
      if (track.property != property) return track;
      final targetTimeMs = timeMs ?? _document.playheadMs;
      final frameIndex = track.keyframes.indexWhere(
        (item) => item.timeMs == targetTimeMs,
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
    int? timeMs,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;

    KeyframeTrack update(KeyframeTrack track) {
      if (track.property != property) return track;
      final targetTimeMs = timeMs ?? _document.playheadMs;
      final frameIndex = track.keyframes.indexWhere(
        (item) => item.timeMs == targetTimeMs,
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
      startMs: _frameAlignedTransitionStart(_document.playheadMs),
      durationMs: _frameAlignedTransitionDuration(500),
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
      durationMs: durationMs == null
          ? null
          : _frameAlignedTransitionDuration(durationMs),
      startMs: startMs == null
          ? null
          : _frameAlignedTransitionStart(startMs),
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

  AudioBus addAudioBus({String? name}) {
    final bus = AudioBus(
      id: _id('bus'),
      name: name ?? 'Bus ${_document.audioBuses.length}',
    );
    _set(_document.copyWith(
      audioBuses: [..._document.audioBuses, bus],
    ));
    return bus;
  }

  void updateAudioBus(AudioBus updated) {
    if (!_document.audioBuses.any((bus) => bus.id == updated.id)) return;
    final buses = _document.audioBuses
        .map((bus) => bus.id == updated.id ? updated : bus)
        .toList();
    _set(_document.copyWith(audioBuses: buses));
  }

  void setAudioBusValue(
    String busId,
    String property,
    double value, {
    bool keyframe = false,
  }) {
    final bus = _document.audioBuses.where((item) => item.id == busId);
    if (bus.isEmpty) return;
    final current = bus.first;
    if (property != 'gainDb' && property != 'pan') return;

    if (!keyframe) {
      final updated = property == 'gainDb'
          ? current.copyWith(
              gainDb: value.clamp(-60.0, 24.0).toDouble(),
            )
          : current.copyWith(
              pan: value.clamp(-1.0, 1.0).toDouble(),
            );
      updateAudioBus(updated);
      return;
    }

    final bounded = property == 'gainDb'
        ? value.clamp(-60.0, 24.0).toDouble()
        : value.clamp(-1.0, 1.0).toDouble();
    final index = current.keyframeTracks.indexWhere(
      (track) => track.property == property,
    );
    final track = index < 0
        ? KeyframeTrack(property: property)
        : current.keyframeTracks[index];
    final updatedTrack = track.upsert(ScalarKeyframe(
      timeMs: _document.playheadMs,
      value: bounded,
      interpolation: Interpolation.easeInOut,
    ));
    final tracks = [...current.keyframeTracks];
    if (index < 0) {
      tracks.add(updatedTrack);
    } else {
      tracks[index] = updatedTrack;
    }
    updateAudioBus(current.copyWith(keyframeTracks: tracks));
  }

  void setAudioBusInterpolation(
    String busId,
    String property,
    Interpolation interpolation, {
    int? timeMs,
  }) {
    final bus = _document.audioBuses.where((item) => item.id == busId);
    if (bus.isEmpty) return;
    final current = bus.first;
    final targetTime = timeMs ?? _document.playheadMs;
    final tracks = current.keyframeTracks.map((track) {
      if (track.property != property) return track;
      final index = track.keyframes.indexWhere(
        (frame) => frame.timeMs == targetTime,
      );
      if (index < 0) return track;
      final frames = [...track.keyframes];
      final old = frames[index];
      frames[index] = ScalarKeyframe(
        timeMs: old.timeMs,
        value: old.value,
        interpolation: interpolation,
        inTangent: old.inTangent,
        outTangent: old.outTangent,
        bezier: old.bezier,
      );
      return KeyframeTrack(
        property: track.property,
        keyframes: frames,
        enabled: track.enabled,
      );
    }).toList();
    updateAudioBus(current.copyWith(keyframeTracks: tracks));
  }

  void setAudioBusBezierCurve(
    String busId,
    String property,
    BezierCurve curve, {
    int? timeMs,
  }) {
    final bus = _document.audioBuses.where((item) => item.id == busId);
    if (bus.isEmpty) return;
    final current = bus.first;
    final targetTime = timeMs ?? _document.playheadMs;
    final tracks = current.keyframeTracks.map((track) {
      if (track.property != property) return track;
      final index = track.keyframes.indexWhere(
        (frame) => frame.timeMs == targetTime,
      );
      if (index < 0) return track;
      final frames = [...track.keyframes];
      final old = frames[index];
      frames[index] = ScalarKeyframe(
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
    }).toList();
    updateAudioBus(current.copyWith(keyframeTracks: tracks));
  }

  void removeAudioBus(String busId) {
    final bus = _document.audioBuses.where((item) => item.id == busId);
    if (bus.isEmpty || bus.first.isMaster) return;
    final masterId = _document.audioBuses
        .where((item) => item.isMaster)
        .firstOrNull
        ?.id;
    final layers = _document.layers.map((layer) {
      if (layer.audioSettings.busId != busId) return layer;
      return layer.copyWith(
        audioSettings: masterId == null
            ? layer.audioSettings.copyWith(clearBus: true)
            : layer.audioSettings.copyWith(busId: masterId),
      );
    }).toList();
    _set(_document.copyWith(
      audioBuses: _document.audioBuses
          .where((item) => item.id != busId)
          .toList(),
      layers: layers,
    ));
  }

  void assignSelectedAudioBus(String? busId) {
    final layer = selectedLayer;
    if (layer == null ||
        (layer.kind != LayerKind.audio && layer.kind != LayerKind.video)) {
      return;
    }
    if (busId != null &&
        !_document.audioBuses.any((bus) => bus.id == busId)) {
      return;
    }
    _replace(layer.copyWith(
      audioSettings: layer.audioSettings.copyWith(
        busId: busId,
        clearBus: busId == null,
      ),
    ));
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

  void setAudioPan(double value, {bool keyframe = false}) {
    final layer = selectedLayer;
    if (layer == null ||
        (layer.kind != LayerKind.audio && layer.kind != LayerKind.video)) {
      return;
    }
    final bounded = value.clamp(-1.0, 1.0).toDouble();
    if (!keyframe) {
      _replace(layer.copyWith(
        audioSettings: layer.audioSettings.copyWith(pan: bounded),
      ));
      return;
    }
    final index = layer.keyframeTracks.indexWhere(
      (track) => track.property == 'audio.pan',
    );
    final track = index < 0
        ? const KeyframeTrack(property: 'audio.pan')
        : layer.keyframeTracks[index];
    final updated = track.upsert(ScalarKeyframe(
      timeMs: _document.playheadMs,
      value: bounded,
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
