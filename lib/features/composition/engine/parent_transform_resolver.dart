import '../domain/composition_models.dart';

class ResolvedLayerTransform {
  const ResolvedLayerTransform({
    required this.position,
    required this.scale,
    required this.rotation,
    required this.opacity,
  });

  final Vector3 position;
  final Vector3 scale;
  final Vector3 rotation;
  final double opacity;

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
    );
  }
}
