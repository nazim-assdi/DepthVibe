import 'dart:math' as math;

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
    final byId = <String, CompositionLayer>{
      for (final item in layers) item.id: item,
    };

    ResolvedLayerTransform resolveOne(
      CompositionLayer current,
      Set<String> visiting,
    ) {
      if (!visiting.add(current.id)) {
        throw StateError(
          'Parent cycle detected while resolving layer ${current.id}.',
        );
      }

      var position = Vector3(
        current.valueAt('position.x', timeMs),
        current.valueAt('position.y', timeMs),
        current.valueAt('position.z', timeMs),
      );
      var scale = Vector3(
        current.valueAt('scale.x', timeMs),
        current.valueAt('scale.y', timeMs),
        current.valueAt('scale.z', timeMs),
      );
      var rotation = Vector3(
        current.valueAt('rotation.x', timeMs),
        current.valueAt('rotation.y', timeMs),
        current.valueAt('rotation.z', timeMs),
      );
      var opacity = current.valueAt('opacity', timeMs);
      var enabled = current.enabled;

      final parentId = current.parentId;
      final parent = parentId == null ? null : byId[parentId];
      if (parent != null) {
        final inherited = resolveOne(parent, visiting);
        final scaledOffset = Vector3(
          position.x * inherited.scale.x / 100,
          position.y * inherited.scale.y / 100,
          position.z * inherited.scale.z / 100,
        );
        final rotatedOffset = _rotateByEuler(scaledOffset, inherited.rotation);
        position = Vector3(
          inherited.position.x + rotatedOffset.x,
          inherited.position.y + rotatedOffset.y,
          inherited.position.z + rotatedOffset.z,
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

      visiting.remove(current.id);
      return ResolvedLayerTransform(
        position: position,
        scale: scale,
        rotation: rotation,
        opacity: opacity.clamp(0, 100).toDouble(),
        enabled: enabled,
      );
    }

    return resolveOne(layer, <String>{});
  }

  /// Applies parent Euler rotation in X, then Y, then Z order to a
  /// child-space offset. Parent scale is applied before this rotation.
  Vector3 _rotateByEuler(Vector3 offset, Vector3 rotationDegrees) {
    final rx = rotationDegrees.x * math.pi / 180;
    final ry = rotationDegrees.y * math.pi / 180;
    final rz = rotationDegrees.z * math.pi / 180;

    final cosX = math.cos(rx);
    final sinX = math.sin(rx);
    final y1 = offset.y * cosX - offset.z * sinX;
    final z1 = offset.y * sinX + offset.z * cosX;

    final cosY = math.cos(ry);
    final sinY = math.sin(ry);
    final x2 = offset.x * cosY + z1 * sinY;
    final z2 = -offset.x * sinY + z1 * cosY;

    final cosZ = math.cos(rz);
    final sinZ = math.sin(rz);
    return Vector3(
      x2 * cosZ - y1 * sinZ,
      x2 * sinZ + y1 * cosZ,
      z2,
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
        final scaledOffset = Vector3(
          position.x * inherited.scale.x / 100,
          position.y * inherited.scale.y / 100,
          position.z * inherited.scale.z / 100,
        );
        final rotatedOffset = _rotateByEuler(scaledOffset, inherited.rotation);
        position = Vector3(
          inherited.position.x + rotatedOffset.x,
          inherited.position.y + rotatedOffset.y,
          inherited.position.z + rotatedOffset.z,
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
