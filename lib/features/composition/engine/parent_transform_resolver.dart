import '../domain/composition_models.dart';

class ResolvedLayerTransform {
  const ResolvedLayerTransform({
    required this.position,
    required this.scale,
    required this.rotation,
    required this.opacity,
    required this.enabled,
  });

  final Vector3 position;
  final Vector3 scale;
  final Vector3 rotation;
  final double opacity;
  final bool enabled;

  LayerTransform toLayerTransform() => LayerTransform(
        position: position,
        scale: scale,
        rotation: rotation,
        opacity: opacity,
      );
}

/// Resolves parent/null chains so child layers inherit parent animation.
///
/// Position uses a simplified additive 3D transform. Full matrix parenting
/// (including anchor-space rotations, skew and 3D camera projection) remains
/// a renderer responsibility.
class ParentTransformResolver {
  const ParentTransformResolver();

  ResolvedLayerTransform resolve({
    required CompositionLayer layer,
    required int timeMs,
    required List<CompositionLayer> layers,
  }) {
    final byId = {for (final item in layers) item.id: item};
    final visited = <String>{layer.id};

    var position = Vector3(
      layer.valueAt('position.x', timeMs),
      layer.valueAt('position.y', timeMs),
      layer.valueAt('position.z', timeMs),
    );
    var scale = Vector3(
      layer.valueAt('scale.x', timeMs),
      layer.valueAt('scale.y', timeMs),
      layer.valueAt('scale.z', timeMs),
    );
    var rotation = Vector3(
      layer.valueAt('rotation.x', timeMs),
      layer.valueAt('rotation.y', timeMs),
      layer.valueAt('rotation.z', timeMs),
    );
    var opacity = layer.valueAt('opacity', timeMs) / 100;
    var enabled = layer.enabled;

    var parentId = layer.parentId;
    while (parentId != null) {
      if (!visited.add(parentId)) {
        throw StateError('Parent cycle detected while resolving layer ${layer.id}.');
      }
      final parent = byId[parentId];
      if (parent == null) break;

      final parentPosition = Vector3(
        parent.valueAt('position.x', timeMs),
        parent.valueAt('position.y', timeMs),
        parent.valueAt('position.z', timeMs),
      );
      final parentScale = Vector3(
        parent.valueAt('scale.x', timeMs),
        parent.valueAt('scale.y', timeMs),
        parent.valueAt('scale.z', timeMs),
      );
      final parentRotation = Vector3(
        parent.valueAt('rotation.x', timeMs),
        parent.valueAt('rotation.y', timeMs),
        parent.valueAt('rotation.z', timeMs),
      );
      final parentOpacity = parent.valueAt('opacity', timeMs) / 100;
      enabled = enabled && parent.enabled;

      position = Vector3(
        parentPosition.x + position.x * parentScale.x / 100,
        parentPosition.y + position.y * parentScale.y / 100,
        parentPosition.z + position.z * parentScale.z / 100,
      );
      scale = Vector3(
        scale.x * parentScale.x / 100,
        scale.y * parentScale.y / 100,
        scale.z * parentScale.z / 100,
      );
      rotation = Vector3(
        rotation.x + parentRotation.x,
        rotation.y + parentRotation.y,
        rotation.z + parentRotation.z,
      );
      opacity *= parentOpacity;
      parentId = parent.parentId;
    }

    return ResolvedLayerTransform(
      position: position,
      scale: scale,
      rotation: rotation,
      opacity: (opacity * 100).clamp(0, 100).toDouble(),
      enabled: enabled,
    );
  }

  /// Resolves every layer for one playhead position with shared parent-chain
  /// memoization, avoiding a new ID map and repeated parent-chain walks for
  /// every visible layer in the compositor.
  Map<String, ResolvedLayerTransform> resolveAll({
    required int timeMs,
    required List<CompositionLayer> layers,
  }) {
    final byId = <String, CompositionLayer>{
      for (final layer in layers) layer.id: layer,
    };
    final resolvedById = <String, ResolvedLayerTransform>{};

    ResolvedLayerTransform resolveOne(
      CompositionLayer layer,
      Set<String> visiting,
    ) {
      final cached = resolvedById[layer.id];
      if (cached != null) return cached;
      if (!visiting.add(layer.id)) {
        throw StateError(
          'Parent cycle detected while resolving layer ${layer.id}.',
        );
      }

      var position = Vector3(
        layer.valueAt('position.x', timeMs),
        layer.valueAt('position.y', timeMs),
        layer.valueAt('position.z', timeMs),
      );
      var scale = Vector3(
        layer.valueAt('scale.x', timeMs),
        layer.valueAt('scale.y', timeMs),
        layer.valueAt('scale.z', timeMs),
      );
      var rotation = Vector3(
        layer.valueAt('rotation.x', timeMs),
        layer.valueAt('rotation.y', timeMs),
        layer.valueAt('rotation.z', timeMs),
      );
      var opacity = layer.valueAt('opacity', timeMs);
      var enabled = layer.enabled;

      final parentId = layer.parentId;
      final parent = parentId == null ? null : byId[parentId];
      if (parent != null) {
        final inherited = resolveOne(parent, visiting);
        position = Vector3(
          inherited.position.x + position.x * inherited.scale.x / 100,
          inherited.position.y + position.y * inherited.scale.y / 100,
          inherited.position.z + position.z * inherited.scale.z / 100,
        );
        scale = Vector3(
          scale.x * inherited.scale.x / 100,
          scale.y * inherited.scale.y / 100,
          scale.z * inherited.scale.z / 100,
        );
        rotation = Vector3(
          rotation.x + inherited.rotation.x,
          rotation.y + inherited.rotation.y,
          rotation.z + inherited.rotation.z,
        );
        opacity = opacity * inherited.opacity / 100;
        enabled = enabled && inherited.enabled;
      }

      visiting.remove(layer.id);
      final resolved = ResolvedLayerTransform(
        position: position,
        scale: scale,
        rotation: rotation,
        opacity: opacity.clamp(0, 100).toDouble(),
        enabled: enabled,
      );
      resolvedById[layer.id] = resolved;
      return resolved;
    }

    for (final layer in layers) {
      resolveOne(layer, <String>{});
    }
    return Map<String, ResolvedLayerTransform>.unmodifiable(resolvedById);
  }
}
