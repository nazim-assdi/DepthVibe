import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/effect_catalog.dart';
import '../data/effect_preset_catalog.dart';
import '../domain/composition_models.dart';
import '../domain/color_grade_preset.dart';
import '../data/motion_preset_catalog.dart';
import '../engine/transition_frame_validator.dart';

class CompositionController extends ChangeNotifier {
  CompositionController({
    CompositionDocument document = const CompositionDocument(),
  }) : _document = document {
    _nextId = document.layers.length + 1;
  }

  CompositionDocument _document;
  int _nextId = 1;
  late final ValueNotifier<int> playheadListenable =
      ValueNotifier<int>(_document.playheadMs);
  static const maxUndoHistory = 80;
  final List<CompositionDocument> _undoHistory = [];
  final List<CompositionDocument> _redoHistory = [];

  CompositionDocument get document => _document;
  ValueListenable<int> get playhead => playheadListenable;
  CompositionLayer? get selectedLayer => _document.selectedLayer;
  bool get canUndo => _undoHistory.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;
  int get undoHistoryLength => _undoHistory.length;

  void undo() {
    if (_undoHistory.isEmpty) return;
    _redoHistory.add(_document);
    _document = _undoHistory.removeLast();
    playheadListenable.value = _document.playheadMs;
    notifyListeners();
  }

  void redo() {
    if (_redoHistory.isEmpty) return;
    _undoHistory.add(_document);
    if (_undoHistory.length > maxUndoHistory) {
      _undoHistory.removeAt(0);
    }
    _document = _redoHistory.removeLast();
    playheadListenable.value = _document.playheadMs;
    notifyListeners();
  }

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


  void _set(
    CompositionDocument next, {
    bool recordHistory = true,
  }) {
    if (identical(next, _document)) return;
    if (recordHistory) {
      _undoHistory.add(_document);
      if (_undoHistory.length > maxUndoHistory) {
        _undoHistory.removeAt(0);
      }
      _redoHistory.clear();
    }
    _document = next;
    if (playheadListenable.value != next.playheadMs) {
      playheadListenable.value = next.playheadMs;
    }
    notifyListeners();
  }

  
  /// Replaces the full composition when a project package is opened.
  /// The ID counter is advanced past every imported numeric suffix.
  /// Replaces every reference to a missing local asset across the composition.
  void relinkAssetReference(String oldUri, String newUri) {
    if (oldUri.isEmpty || newUri.isEmpty || oldUri == newUri) return;
    final updatedLayers = _document.layers.map((layer) {
      final updatedEffects = layer.effects.map((effect) {
        if (effect.assetUri != oldUri) return effect;
        return effect.copyWith(assetUri: newUri);
      }).toList();
      return layer.copyWith(
        sourceUri: layer.sourceUri == oldUri ? newUri : null,
        sourceDocumentUri:
            layer.sourceDocumentUri == oldUri ? newUri : null,
        smartObjectSourceUri:
            layer.smartObjectSourceUri == oldUri ? newUri : null,
        effects: updatedEffects,
      );
    }).toList();
    _set(_document.copyWith(layers: updatedLayers));
  }

  void replaceDocument(CompositionDocument document) {
    _undoHistory.clear();
    _redoHistory.clear();
    _document = document;
    playheadListenable.value = document.playheadMs;
    var next = 1;
    final identifiers = <String>[
      for (final layer in document.layers) layer.id,
      for (final layer in document.layers)
        for (final effect in layer.effects) effect.id,
      for (final layer in document.layers)
        for (final mask in layer.masks) mask.id,
      for (final transition in document.transitions) transition.id,
      for (final bus in document.audioBuses) bus.id,
    ];
    final suffixPattern = RegExp(r'_(\d+)$');
    for (final identifier in identifiers) {
      final match = suffixPattern.firstMatch(identifier);
      final value = match == null ? null : int.tryParse(match.group(1)!);
      if (value != null && value >= next) next = value + 1;
    }
    _nextId = next;
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
      textContent: kind == LayerKind.text ? 'Your text' : null,
      durationMs: duration,
      transform: const LayerTransform(),
      shapeStyle: kind == LayerKind.shape ? const ShapeStyle() : null,
      camera: kind == LayerKind.camera ? const CameraSettings() : null,
      light: kind == LayerKind.light ? const LightSettings() : null,
    );
  }

  bool updateCompositionSettings({
    String? name,
    int? width,
    int? height,
    double? frameRate,
    int? durationMs,
  }) {
    final nextName = name?.trim();
    if (nextName != null && nextName.isEmpty) return false;
    if (width != null && (width < 16 || width > 16384)) return false;
    if (height != null && (height < 16 || height > 16384)) return false;
    if (frameRate != null &&
        (!frameRate.isFinite || frameRate < 1 || frameRate > 240)) {
      return false;
    }
    if (durationMs != null && (durationMs < 1000 || durationMs > 3600000)) {
      return false;
    }
    _set(_document.copyWith(
      name: nextName,
      width: width,
      height: height,
      frameRate: frameRate,
      durationMs: durationMs,
    ));
    return true;
  }

  String addShapeLayer({
    required ShapeStyle style,
    required Vector3 position,
    required double width,
    required double height,
    String? name,
  }) {
    final safeWidth = width.clamp(2.0, 100000.0).toDouble();
    final safeHeight = height.clamp(2.0, 100000.0).toDouble();
    final layer = _defaultLayer(
      LayerKind.shape,
      name: name ?? switch (style.primitive) {
        ShapePrimitive.rectangle => 'Rectangle',
        ShapePrimitive.roundedRectangle => 'Rounded Rectangle',
        ShapePrimitive.ellipse => 'Ellipse',
        ShapePrimitive.polygon => 'Polygon',
        ShapePrimitive.star => 'Star',
        ShapePrimitive.path => 'Bezier Shape',
      },
    ).copyWith(
      shapeStyle: style,
      transform: LayerTransform(
        position: position,
        scale: Vector3(
          safeWidth / 160 * 100,
          safeHeight / 120 * 100,
          100,
        ),
      ),
    );
    _set(_document.copyWith(
      layers: [layer, ..._document.layers],
      selectedLayerId: layer.id,
    ));
    return layer.id;
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

  void updateTextLayer({
    String? textContent,
    bool? is3dText,
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
  }) {
    final layer = selectedLayer;
    if (layer == null || layer.kind != LayerKind.text) return;
    _replace(layer.copyWith(
      textContent: textContent,
      is3dText: is3dText,
      textFontFamily: textFontFamily,
      textFontAssetUri: textFontAssetUri,
      textFontFallback: textFontFallback,
      textFontSize: textFontSize,
      textFontWeight: textFontWeight,
      textItalic: textItalic,
      textColor: textColor,
      textLetterSpacing: textLetterSpacing,
      textLineHeight: textLineHeight,
      textAlign: textAlign,
      textBoxWidth: textBoxWidth,
      clearTextFont: clearTextFont,
      clearTextFontAsset: clearTextFontAsset,
    ));
  }

  void selectLayer(String? id) {
    if (id != null && !_document.layers.any((layer) => layer.id == id)) return;
    _set(
      _document.copyWith(selectedLayerId: id),
      recordHistory: false,
    );
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

  /// Splits the selected clip at the composition playhead.
  ///
  /// The left segment keeps its original identity. The right segment receives
  /// new layer/effect/mask IDs and an advanced source in-point, while preserving
  /// its original effect stack, masks and keyframe data. The operation is one
  /// undoable history entry.
  bool splitSelectedLayerAtPlayhead() {
    final selected = selectedLayer;
    if (selected == null || selected.locked) return false;

    final splitTimeMs = _document.playheadMs;
    if (splitTimeMs <= selected.startMs || splitTimeMs >= selected.endMs) {
      return false;
    }

    final leftDurationMs = splitTimeMs - selected.startMs;
    final rightDurationMs = selected.endMs - splitTimeMs;
    final rightSegment = selected.copyWith(
      id: _id('clip'),
      name: '${selected.name} (split)',
      startMs: splitTimeMs,
      durationMs: rightDurationMs,
      sourceInMs: selected.sourceInMs + leftDurationMs,
      effects: selected.effects
          .map((effect) => effect.copyWith(id: _id('effect')))
          .toList(growable: false),
      masks: selected.masks
          .map((mask) => mask.copyWith(id: _id('mask')))
          .toList(growable: false),
    );

    final layers = [..._document.layers];
    final selectedIndex = layers.indexWhere((layer) => layer.id == selected.id);
    if (selectedIndex < 0) return false;
    layers[selectedIndex] = selected.copyWith(durationMs: leftDurationMs);
    layers.insert(selectedIndex + 1, rightSegment);

    _set(_document.copyWith(
      layers: layers,
      selectedLayerId: rightSegment.id,
    ));
    return true;
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
    List<MaskVertex>? vertices,
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;
    final mask = MaskModel(
      id: _id('mask'),
      name: '${shape.name} mask',
      shape: shape,
      operation: operation,
      left: left ??
          (shape == MaskShape.bezier || shape == MaskShape.polygon ? 0.2 : 0.05),
      top: top ??
          (shape == MaskShape.bezier || shape == MaskShape.polygon ? 0.2 : 0.05),
      width: width ??
          (shape == MaskShape.bezier || shape == MaskShape.polygon ? 0.6 : 0.9),
      height: height ??
          (shape == MaskShape.bezier || shape == MaskShape.polygon ? 0.6 : 0.9),
      vertices: vertices ??
          (shape == MaskShape.bezier || shape == MaskShape.polygon
              ? const [
                  MaskVertex(anchor: Vector2(0.2, 0.2)),
                  MaskVertex(anchor: Vector2(0.8, 0.2)),
                  MaskVertex(anchor: Vector2(0.8, 0.8)),
                  MaskVertex(anchor: Vector2(0.2, 0.8)),
                ]
              : const []),
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
    bool recordHistory = true,
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
    ), recordHistory: recordHistory);
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

  /// Applies an original multi-effect look as editable native effects.
  /// Unknown effect IDs/parameters are ignored and values are clamped to the
  /// registered parameter schema before they enter a project.
  void applyEffectPreset(String presetId) {
    final layer = selectedLayer;
    final preset = EffectPresetCatalog.find(presetId);
    if (layer == null || layer.locked || preset == null) return;

    final additions = <EffectInstance>[];
    for (final step in preset.steps) {
      final definition = EffectCatalog.find(step.effectId);
      if (definition == null) continue;
      final parameters = <String, double>{
        for (final parameter in definition.parameters)
          parameter.id: parameter.defaultValue,
      };
      for (final entry in step.parameters.entries) {
        final parameter = definition.parameters
            .where((item) => item.id == entry.key)
            .firstOrNull;
        if (parameter == null || !entry.value.isFinite) continue;
        parameters[entry.key] =
            entry.value.clamp(parameter.min, parameter.max).toDouble();
      }
      additions.add(EffectInstance(
        id: _id('preset_effect'),
        effectId: definition.id,
        name: definition.name,
        parameters: parameters,
        assetUri: definition.assetUri,
      ));
    }
    if (additions.isEmpty) return;
    _replace(layer.copyWith(effects: [...layer.effects, ...additions]));
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
          assetUri: definition.assetUri,
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

  void setEffectAssetUri(String effectInstanceId, String? assetUri) {
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      effects: layer.effects.map((effect) {
        if (effect.id != effectInstanceId) return effect;
        return effect.copyWith(
          assetUri: assetUri,
          clearAssetUri: assetUri == null,
        );
      }).toList(),
    ));
  }

  void setEffectAssetInterpolation(
    String effectInstanceId,
    String interpolation,
  ) {
    const supported = {
      'nearest',
      'trilinear',
      'tetrahedral',
      'pyramid',
      'prism',
    };
    if (!supported.contains(interpolation)) return;
    final layer = selectedLayer;
    if (layer == null) return;
    _replace(layer.copyWith(
      effects: layer.effects.map((effect) {
        if (effect.id != effectInstanceId) return effect;
        return effect.copyWith(assetInterpolation: interpolation);
      }).toList(),
    ));
  }

  void setColorOutputProfile(ColorOutputProfile profile) {
    _set(_document.copyWith(colorOutputProfile: profile));
  }

  void applyColorGradePreset(
    ColorGradePreset preset, {
    String? lutAssetUri,
  }) {
    final layer = selectedLayer;
    if (layer == null) return;

    final replacements = <EffectInstance>[];
    final primary = preset.primary;
    if (primary != null) {
      replacements.add(EffectInstance(
        id: _id('effect'),
        effectId: 'color_grade',
        name: 'Primary Color Grade',
        enabled: primary.enabled,
        parameters: primary.parameters,
        keyframeTracks: primary.keyframeTracks,
      ));
    }
    final curves = preset.curves;
    if (curves != null) {
      replacements.add(EffectInstance(
        id: _id('effect'),
        effectId: 'color_curves',
        name: 'Primary Curves',
        enabled: curves.enabled,
        parameters: curves.parameters,
        keyframeTracks: curves.keyframeTracks,
      ));
    }
    final lut = preset.lut;
    if (lut != null) {
      replacements.add(EffectInstance(
        id: _id('effect'),
        effectId: 'color_lut',
        name: '3D LUT',
        enabled: lut.enabled,
        assetUri: lutAssetUri,
        assetInterpolation: lut.interpolation,
      ));
    }

    const colorEffectIds = {'color_grade', 'color_curves', 'color_lut'};
    final retained = layer.effects
        .where((effect) => !colorEffectIds.contains(effect.effectId))
        .toList();
    final updatedLayer = layer.copyWith(
      effects: [...retained, ...replacements],
    );
    _set(_document.copyWith(
      colorOutputProfile: preset.outputProfile,
      layers: _document.layers
          .map((item) => item.id == layer.id ? updatedLayer : item)
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

  /// Applies an editable native motion recipe at the current playhead.
  void applyMotionPreset(String presetId) {
    final layer = selectedLayer;
    final preset = MotionPresetCatalog.find(presetId);
    if (layer == null || layer.locked || preset == null) return;
    final startMs = _frameAlignedTransitionStart(_document.playheadMs);
    final remainingMs = (_document.durationMs - startMs)
        .clamp(1, preset.durationMs).toInt();
    final durationMs = _frameAlignedTransitionDuration(remainingMs);
    var tracks = [...layer.keyframeTracks];

    for (final presetTrack in preset.tracks) {
      final index = tracks.indexWhere((item) => item.property == presetTrack.property);
      var track = index < 0
          ? KeyframeTrack(property: presetTrack.property)
          : tracks[index];
      final base = layer.transform.valueFor(presetTrack.property);
      for (final frame in presetTrack.frames) {
        final timeMs = _frameAlignedTransitionStart(
          startMs + (durationMs * frame.progress.clamp(0, 1)).round(),
        );
        final value = switch (frame.mode) {
          MotionPresetValueMode.absolute => frame.value,
          MotionPresetValueMode.offset => base + frame.value,
          MotionPresetValueMode.multiplier => base * frame.value,
          MotionPresetValueMode.compositionWidthOffset =>
            base + _document.width * frame.value,
          MotionPresetValueMode.compositionHeightOffset =>
            base + _document.height * frame.value,
        };
        track = track.upsert(ScalarKeyframe(
          timeMs: timeMs,
          value: value,
          interpolation: preset.interpolation,
        ));
      }
      if (index < 0) {
        tracks.add(track);
      } else {
        tracks[index] = track;
      }
    }
    _replace(layer.copyWith(keyframeTracks: tracks));
  }

  /// Applies a portable layer preset at the current playhead. Keyframes are
  /// time-shifted, transform curves are offset to the target layer baseline,
  /// and native effect descriptors remain inert host metadata.
  void applyLayerPreset(CompositionLayer presetLayer) {
    final target = selectedLayer;
    if (target == null || target.locked) return;
    final timeShift = _document.playheadMs - presetLayer.startMs;

    KeyframeTrack remapTrack(KeyframeTrack source, {double valueOffset = 0}) {
      final frames = source.keyframes.map((frame) {
        return ScalarKeyframe(
          timeMs: (frame.timeMs + timeShift)
              .clamp(0, _document.durationMs - 1).toInt(),
          value: frame.value + valueOffset,
          interpolation: frame.interpolation,
          inTangent: frame.inTangent,
          outTangent: frame.outTangent,
          bezier: frame.bezier,
          metadata: frame.metadata,
        );
      }).toList();
      return KeyframeTrack(
        property: source.property,
        keyframes: frames,
        enabled: source.enabled,
      );
    }

    var tracks = [...target.keyframeTracks];
    for (final source in presetLayer.keyframeTracks) {
      final offset = target.transform.valueFor(source.property) -
          presetLayer.transform.valueFor(source.property);
      final remapped = remapTrack(source, valueOffset: offset);
      final index = tracks.indexWhere((item) => item.property == source.property);
      if (index < 0) {
        tracks.add(remapped);
      } else {
        var merged = tracks[index];
        for (final keyframe in remapped.keyframes) {
          merged = merged.upsert(keyframe);
        }
        tracks[index] = merged;
      }
    }

    final effects = [...target.effects];
    for (final source in presetLayer.effects) {
      effects.add(EffectInstance(
        id: _id('preset_effect'),
        effectId: source.effectId,
        name: source.name,
        enabled: source.enabled,
        parameters: source.parameters,
        keyframeTracks: source.keyframeTracks
            .map((track) => remapTrack(track))
            .toList(),
        assetUri: source.assetUri,
        assetInterpolation: source.assetInterpolation,
        nativeDescriptor: source.nativeDescriptor,
      ));
    }
    _replace(target.copyWith(effects: effects, keyframeTracks: tracks));
  }

  Map<String, Object?>? _premiereMappedParameter(
    String componentMatchName,
    String parameterName,
    Object? rawValue,
  ) {
    if (rawValue is! num || !rawValue.toDouble().isFinite) return null;
    final component = componentMatchName.toLowerCase();
    final parameter = parameterName.toLowerCase();
    final value = rawValue.toDouble();
    if ((component.contains('gaussian blur') || component.contains('fast blur')) &&
        (parameter.contains('blurriness') || parameter.contains('blur amount') ||
            parameter.contains('radius'))) {
      return {'effectId': 'gaussian_blur', 'property': 'sigma',
        'value': value.clamp(0, 30).toDouble()};
    }
    if (component.contains('brightness') && component.contains('contrast')) {
      if (parameter.contains('brightness')) {
        return {'effectId': 'brightness', 'property': 'value',
          'value': (value / 100).clamp(-1, 1).toDouble()};
      }
      if (parameter.contains('contrast')) {
        return {'effectId': 'contrast', 'property': 'value',
          'value': (1 + value / 100).clamp(0, 3).toDouble()};
      }
    }
    if (component.contains('sharpen') &&
        (parameter.contains('amount') || parameter.contains('sharpness'))) {
      return {'effectId': 'sharpen', 'property': 'amount',
        'value': value.clamp(0, 5).toDouble()};
    }
    if ((component.contains('hue/saturation') || component.contains('hue saturation')) &&
        (parameter.contains('master saturation') || parameter.contains('saturation'))) {
      return {'effectId': 'saturation', 'property': 'value',
        'value': (1 + value / 100).clamp(0, 3).toDouble()};
    }
    return null;
  }

  void setNativeEffectParameter(
    String effectInstanceId,
    String parameterMatchName,
    Object? value, {
    List<String>? parameterPath,
  }) {
    final layer = selectedLayer;
    if (layer == null || layer.locked) return;
    Map<String, Object?>? mappedValue;
    final effects = layer.effects.map((effect) {
      if (effect.id != effectInstanceId) return effect;
      final descriptor = <String, Object?>{...effect.nativeDescriptor};
      final rawParameters = descriptor['parameters'];
      if (rawParameters is! List) return effect;
      final componentMatchName = descriptor['matchName']?.toString() ?? '';
      final parameters = rawParameters.map((raw) {
        if (raw is! Map) return raw;
        final item = Map<String, Object?>.from(raw);
        final matchName = item['matchName']?.toString() ?? '';
        final rawPath = item['path'];
        final itemPath = rawPath is List
            ? rawPath.map((part) => part.toString()).toList()
            : const <String>[];
        final pathMatches = parameterPath == null ||
            (itemPath.length == parameterPath.length &&
                List.generate(itemPath.length,
                    (index) => itemPath[index] == parameterPath[index])
                    .every((same) => same));
        if (pathMatches && matchName == parameterMatchName) {
          item['value'] = value;
          mappedValue = _premiereMappedParameter(
            componentMatchName,
            (item['displayName'] ?? item['name'] ?? '').toString(),
            value,
          );
        }
        return item;
      }).toList();
      descriptor['parameters'] = parameters;
      return effect.copyWith(nativeDescriptor: descriptor);
    }).toList();
    final mapped = mappedValue;
    if (mapped != null) {
      final nextEffects = effects.map((effect) {
        if (effect.effectId != mapped['effectId']) return effect;
        final values = <String, double>{...effect.parameters};
        values[mapped['property']!.toString()] = (mapped['value'] as num).toDouble();
        return effect.copyWith(parameters: values);
      }).toList();
      _replace(layer.copyWith(effects: nextEffects));
    } else {
      _replace(layer.copyWith(effects: effects));
    }
  }

  void setNativeEffectParameterKeyframe(
    String effectInstanceId,
    String parameterMatchName,
    double timeSeconds,
    Object? value, {
    String? interpolation,
    List<String>? parameterPath,
  }) {
    final layer = selectedLayer;
    if (layer == null || layer.locked || !timeSeconds.isFinite || timeSeconds < 0) return;
    Map<String, Object?>? mappedValue;
    final effects = layer.effects.map((effect) {
      if (effect.id != effectInstanceId) return effect;
      final descriptor = <String, Object?>{...effect.nativeDescriptor};
      final rawParameters = descriptor['parameters'];
      if (rawParameters is! List) return effect;
      final componentMatchName = descriptor['matchName']?.toString() ?? '';
      final parameters = rawParameters.map((raw) {
        if (raw is! Map) return raw;
        final item = Map<String, Object?>.from(raw);
        final matchName = item['matchName']?.toString() ?? '';
        final rawPath = item['path'];
        final itemPath = rawPath is List
            ? rawPath.map((part) => part.toString()).toList()
            : const <String>[];
        final pathMatches = parameterPath == null ||
            (itemPath.length == parameterPath.length &&
                List.generate(itemPath.length,
                    (index) => itemPath[index] == parameterPath[index])
                    .every((same) => same));
        if (!pathMatches || matchName != parameterMatchName) return item;
        final rawFrames = item['keyframes'];
        final frames = rawFrames is List
            ? rawFrames.whereType<Map>().map((frame) =>
                Map<String, Object?>.from(frame)).toList()
            : <Map<String, Object?>>[];
        final existingIndex = frames.indexWhere((frame) {
          final rawTime = frame['timeSeconds'];
          return rawTime is num &&
              (rawTime.toDouble() - timeSeconds).abs() < 0.000001;
        });
        final frame = existingIndex >= 0
            ? frames[existingIndex]
            : <String, Object?>{'timeSeconds': timeSeconds};
        frame['value'] = value;
        if (interpolation != null) {
          frame['interpolation'] = interpolation;
          frame.remove('interpolationMode');
        }
        if (existingIndex < 0) {
          frames.add(frame);
        } else {
          frames[existingIndex] = frame;
        }
        frames.sort((left, right) =>
            ((left['timeSeconds'] as num?)?.toDouble() ?? 0)
                .compareTo((right['timeSeconds'] as num?)?.toDouble() ?? 0));
        item['keyframes'] = frames;
        item['keyframesSupported'] = true;
        item['isTimeVarying'] = true;
        mappedValue = _premiereMappedParameter(
          componentMatchName,
          (item['displayName'] ?? item['name'] ?? '').toString(),
          value,
        );
        return item;
      }).toList();
      descriptor['parameters'] = parameters;
      return effect.copyWith(nativeDescriptor: descriptor);
    }).toList();

    final mapped = mappedValue;
    if (mapped != null) {
      final targetTimeMs = (timeSeconds * 1000).round();
      final targetProperty = mapped['property']!.toString();
      final targetId = mapped['effectId']!.toString();
      final curve = switch ((interpolation ?? 'linear').toLowerCase()) {
        'hold' => Interpolation.hold,
        'bezier' || 'cubicbezier' => Interpolation.cubicBezier,
        _ => Interpolation.linear,
      };
      final nextEffects = effects.map((effect) {
        if (effect.effectId != targetId) return effect;
        final trackIndex = effect.keyframeTracks.indexWhere(
          (track) => track.property == targetProperty,
        );
        final currentTrack = trackIndex < 0
            ? KeyframeTrack(property: targetProperty)
            : effect.keyframeTracks[trackIndex];
        final updatedTrack = currentTrack.upsert(ScalarKeyframe(
          timeMs: targetTimeMs,
          value: (mapped['value'] as num).toDouble(),
          interpolation: curve,
        ));
        final tracks = [...effect.keyframeTracks];
        if (trackIndex < 0) {
          tracks.add(updatedTrack);
        } else {
          tracks[trackIndex] = updatedTrack;
        }
        final parameters = <String, double>{...effect.parameters};
        parameters[targetProperty] = (mapped['value'] as num).toDouble();
        return effect.copyWith(parameters: parameters, keyframeTracks: tracks);
      }).toList();
      _replace(layer.copyWith(effects: nextEffects));
    } else {
      _replace(layer.copyWith(effects: effects));
    }
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

  /// Updates several transform channels as one undoable document operation.
  /// Animated properties are edited at the current playhead. [autoKey] also
  /// creates keyframes for channels that are not yet animated.
  void updateTransformValues(
    Map<String, double> values, {
    bool autoKey = false,
    int? timeMs,
    bool recordHistory = true,
  }) {
    final layer = selectedLayer;
    if (layer == null || layer.locked || values.isEmpty) return;
    var transform = layer.transform;
    final tracks = [...layer.keyframeTracks];
    final targetTimeMs =
        (timeMs ?? _document.playheadMs).clamp(0, _document.durationMs).toInt();

    for (final entry in values.entries) {
      if (!entry.value.isFinite) continue;
      final trackIndex = tracks.indexWhere((track) => track.property == entry.key);
      final shouldKeyframe = autoKey || trackIndex >= 0;
      if (!shouldKeyframe) {
        transform = transform.withValue(entry.key, entry.value);
        continue;
      }
      final track = trackIndex < 0 ? KeyframeTrack(property: entry.key) : tracks[trackIndex];
      final existingIndex = track.keyframes.indexWhere((item) => item.timeMs == targetTimeMs);
      final existing = existingIndex < 0 ? null : track.keyframes[existingIndex];
      final updated = track.upsert(ScalarKeyframe(
        timeMs: targetTimeMs,
        value: entry.value,
        interpolation: existing?.interpolation ?? Interpolation.easeInOut,
        inTangent: existing?.inTangent ?? 0,
        outTangent: existing?.outTangent ?? 0,
        bezier: existing?.bezier ?? const BezierCurve(),
        metadata: existing?.metadata ?? const {},
      ));
      if (trackIndex < 0) {
        tracks.add(updated);
      } else {
        tracks[trackIndex] = updated;
      }
    }

    _set(
      _document.copyWith(
        layers: _document.layers
            .map((item) => item.id == layer.id
                ? layer.copyWith(transform: transform, keyframeTracks: tracks)
                : item)
            .toList(),
      ),
      recordHistory: recordHistory,
    );
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

  /// Moves one keyframe in time and value without changing its interpolation.
  ///
  /// The target time is constrained between neighbouring keys so a drag cannot
  /// overwrite or reorder another keyframe. A complete drag can be recorded as
  /// one undo step by setting [recordHistory] to false after its first update.
  int? updateKeyframe(
    String property,
    int fromTimeMs,
    int toTimeMs,
    double value, {
    String? effectId,
    String? maskId,
    bool recordHistory = true,
  }) {
    final layer = selectedLayer;
    if (layer == null || layer.locked || !value.isFinite) return null;

    final frameStepMs = math.max(
      1,
      (_document.frameRate <= 0
          ? (1000 / 24).round()
          : (1000 / _document.frameRate).round()),
    );

    KeyframeTrack? updateTrack(KeyframeTrack track) {
      if (track.property != property) return null;
      final frames = [...track.keyframes]
        ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
      final index = frames.indexWhere((item) => item.timeMs == fromTimeMs);
      if (index < 0) return null;

      final previous = index > 0 ? frames[index - 1] : null;
      final next = index < frames.length - 1 ? frames[index + 1] : null;
      final minimumTime = previous == null ? 0 : previous.timeMs + frameStepMs;
      final maximumTime = next == null
          ? _document.durationMs
          : next.timeMs - frameStepMs;
      if (minimumTime > maximumTime) return null;
      final targetTime =
          toTimeMs.clamp(minimumTime, maximumTime).toInt();
      final old = frames[index];
      frames[index] = ScalarKeyframe(
        timeMs: targetTime,
        value: value,
        interpolation: old.interpolation,
        inTangent: old.inTangent,
        outTangent: old.outTangent,
        bezier: old.bezier,
        metadata: old.metadata,
      );
      frames.sort((a, b) => a.timeMs.compareTo(b.timeMs));
      return KeyframeTrack(
        property: track.property,
        keyframes: frames,
        enabled: track.enabled,
      );
    }

    int? resolvedTimeMs;
    if (effectId != null) {
      var changed = false;
      final effects = layer.effects.map((effect) {
        if (effect.id != effectId) return effect;
        final tracks = effect.keyframeTracks.map((track) {
          final updated = updateTrack(track);
          if (updated == null) return track;
          changed = true;
          resolvedTimeMs = updated.keyframes
              .firstWhere((item) => item.value == value &&
                  item.timeMs >= 0)
              .timeMs;
          return updated;
        }).toList();
        return effect.copyWith(keyframeTracks: tracks);
      }).toList();
      if (!changed) return null;
      _replaceWithHistory(
        layer.copyWith(effects: effects),
        recordHistory: recordHistory,
      );
      return resolvedTimeMs;
    }

    if (maskId != null) {
      var changed = false;
      final masks = layer.masks.map((mask) {
        if (mask.id != maskId) return mask;
        final tracks = mask.keyframeTracks.map((track) {
          final updated = updateTrack(track);
          if (updated == null) return track;
          changed = true;
          resolvedTimeMs = updated.keyframes
              .firstWhere((item) => item.value == value &&
                  item.timeMs >= 0)
              .timeMs;
          return updated;
        }).toList();
        return mask.copyWith(keyframeTracks: tracks);
      }).toList();
      if (!changed) return null;
      _replaceWithHistory(
        layer.copyWith(masks: masks),
        recordHistory: recordHistory,
      );
      return resolvedTimeMs;
    }

    var changed = false;
    final tracks = layer.keyframeTracks.map((track) {
      final updated = updateTrack(track);
      if (updated == null) return track;
      changed = true;
      resolvedTimeMs = updated.keyframes
          .firstWhere((item) => item.value == value && item.timeMs >= 0)
          .timeMs;
      return updated;
    }).toList();
    if (!changed) return null;
    _replaceWithHistory(
      layer.copyWith(keyframeTracks: tracks),
      recordHistory: recordHistory,
    );
    return resolvedTimeMs;
  }

  void _replaceWithHistory(
    CompositionLayer updated, {
    required bool recordHistory,
  }) {
    _set(_document.copyWith(
      layers: _document.layers
          .map((layer) => layer.id == updated.id ? updated : layer)
          .toList(),
    ), recordHistory: recordHistory);
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
    final nextTime = timeMs.clamp(0, _document.durationMs).toInt();
    if (nextTime == _document.playheadMs) return;
    // Playhead movement is high-frequency transport state, not a document
    // edit. Notify only the canvas/timeline listeners so panels and inspectors
    // do not rebuild on every preview frame.
    _document = _document.copyWith(playheadMs: nextTime);
    playheadListenable.value = nextTime;
  }

  @override
  void dispose() {
    playheadListenable.dispose();
    super.dispose();
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

  bool _shapePathHasAnimation(CompositionLayer layer) =>
      layer.keyframeTracks.any(
        (track) => track.property.startsWith('shape.vertex.'),
      );

  /// Inserts a point by splitting the selected cubic Bezier segment exactly.
  /// Returns the new vertex index, or null if the path cannot be edited safely.
  int? insertShapePathVertex(int segmentIndex, {double t = 0.5}) {
    final layer = selectedLayer;
    if (layer == null || layer.locked || layer.kind != LayerKind.shape) {
      return null;
    }
    final style = layer.shapeStyle;
    if (style == null ||
        style.primitive != ShapePrimitive.path ||
        style.pathVertices.length < 2 ||
        _shapePathHasAnimation(layer)) {
      return null;
    }
    final vertices = [...style.pathVertices];
    final segmentCount =
        style.pathClosed ? vertices.length : vertices.length - 1;
    if (segmentIndex < 0 || segmentIndex >= segmentCount) return null;

    final parameter = t.clamp(0.001, 0.999).toDouble();
    Vector2 mix(Vector2 a, Vector2 b) => Vector2(
          a.x + (b.x - a.x) * parameter,
          a.y + (b.y - a.y) * parameter,
        );
    final nextIndex = (segmentIndex + 1) % vertices.length;
    final start = vertices[segmentIndex];
    final end = vertices[nextIndex];
    final p0 = start.anchor;
    final p1 = Vector2(
      p0.x + start.outHandle.x,
      p0.y + start.outHandle.y,
    );
    final p3 = end.anchor;
    final p2 = Vector2(
      p3.x + end.inHandle.x,
      p3.y + end.inHandle.y,
    );

    final p01 = mix(p0, p1);
    final p12 = mix(p1, p2);
    final p23 = mix(p2, p3);
    final p012 = mix(p01, p12);
    final p123 = mix(p12, p23);
    final point = mix(p012, p123);

    vertices[segmentIndex] = start.copyWith(
      outHandle: Vector2(p01.x - p0.x, p01.y - p0.y),
    );
    vertices[nextIndex] = end.copyWith(
      inHandle: Vector2(p23.x - p3.x, p23.y - p3.y),
    );
    final inserted = MaskVertex(
      anchor: point,
      inHandle: Vector2(
        p012.x - point.x,
        p012.y - point.y,
      ),
      outHandle: Vector2(
        p123.x - point.x,
        p123.y - point.y,
      ),
      smooth: true,
    );
    final insertIndex = segmentIndex + 1;
    vertices.insert(insertIndex, inserted);
    _replace(layer.copyWith(
      shapeStyle: style.copyWith(pathVertices: vertices),
    ));
    return insertIndex;
  }

  bool removeShapePathVertex(int vertexIndex) {
    final layer = selectedLayer;
    if (layer == null || layer.locked || layer.kind != LayerKind.shape) {
      return false;
    }
    final style = layer.shapeStyle;
    if (style == null ||
        style.primitive != ShapePrimitive.path ||
        _shapePathHasAnimation(layer) ||
        vertexIndex < 0 ||
        vertexIndex >= style.pathVertices.length) {
      return false;
    }
    final minimumVertices = style.pathClosed ? 3 : 2;
    if (style.pathVertices.length <= minimumVertices) return false;
    final vertices = [...style.pathVertices]..removeAt(vertexIndex);
    _replace(layer.copyWith(
      shapeStyle: style.copyWith(pathVertices: vertices),
    ));
    return true;
  }

  bool toggleShapeVertexSmooth(int vertexIndex) {
    final layer = selectedLayer;
    if (layer == null || layer.locked || layer.kind != LayerKind.shape) {
      return false;
    }
    final style = layer.shapeStyle;
    if (style == null ||
        style.primitive != ShapePrimitive.path ||
        vertexIndex < 0 ||
        vertexIndex >= style.pathVertices.length) {
      return false;
    }
    final vertices = [...style.pathVertices];
    final old = vertices[vertexIndex];
    if (old.smooth) {
      vertices[vertexIndex] = old.copyWith(smooth: false);
    } else {
      final inLength = math.sqrt(
        old.inHandle.x * old.inHandle.x +
            old.inHandle.y * old.inHandle.y,
      );
      final outLength = math.sqrt(
        old.outHandle.x * old.outHandle.x +
            old.outHandle.y * old.outHandle.y,
      );
      if (outLength > 0.000001) {
        final length = inLength > 0.000001 ? inLength : outLength;
        vertices[vertexIndex] = old.copyWith(
          smooth: true,
          inHandle: Vector2(
            -old.outHandle.x / outLength * length,
            -old.outHandle.y / outLength * length,
          ),
        );
      } else if (inLength > 0.000001) {
        final length = outLength > 0.000001 ? outLength : inLength;
        vertices[vertexIndex] = old.copyWith(
          smooth: true,
          outHandle: Vector2(
            -old.inHandle.x / inLength * length,
            -old.inHandle.y / inLength * length,
          ),
        );
      } else {
        vertices[vertexIndex] = old.copyWith(smooth: true);
      }
    }
    _replace(layer.copyWith(
      shapeStyle: style.copyWith(pathVertices: vertices),
    ));
    return true;
  }

  void setShapeStyle(
    ShapeStyle style, {
    bool recordHistory = true,
  }) {
    final layer = selectedLayer;
    if (layer == null || layer.kind != LayerKind.shape) return;
    _replace(
      layer.copyWith(shapeStyle: style),
      recordHistory: recordHistory,
    );
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

  void setModelAnimationIndex(int index) {
    final layer = selectedLayer;
    if (layer == null || layer.kind != LayerKind.threeDModel) return;
    _replace(layer.copyWith(modelAnimationIndex: index));
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

  void _replace(
    CompositionLayer updated, {
    bool recordHistory = true,
  }) {
    _set(
      _document.copyWith(
        layers: _document.layers
            .map((layer) => layer.id == updated.id ? updated : layer)
            .toList(),
      ),
      recordHistory: recordHistory,
    );
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
