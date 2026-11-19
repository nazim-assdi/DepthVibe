import '../domain/composition_models.dart';
import 'ffmpeg_animation_compiler.dart';

class ResolvedTransformExpressions {
  const ResolvedTransformExpressions({
    required this.positionX,
    required this.positionY,
    required this.positionZ,
    required this.scaleX,
    required this.scaleY,
    required this.scaleZ,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.opacity,
    required this.enabled,
  });

  final String positionX;
  final String positionY;
  final String positionZ;
  final String scaleX;
  final String scaleY;
  final String scaleZ;
  final String rotationX;
  final String rotationY;
  final String rotationZ;
  final String opacity;
  final bool enabled;
}

/// Compiles the same additive parent-chain transform used by the 2D preview
/// into FFmpeg per-frame expressions.
class ParentTransformExpressionResolver {
  const ParentTransformExpressionResolver({
    this.animationCompiler = const FfmpegAnimationCompiler(),
  });

  final FfmpegAnimationCompiler animationCompiler;

  ResolvedTransformExpressions resolve({
    required CompositionLayer layer,
    required List<CompositionLayer> layers,
  }) {
    final byId = <String, CompositionLayer>{
      for (final item in layers) item.id: item,
    };
    final visited = <String>{layer.id};
    var current = _local(layer);
    var enabled = layer.enabled;

    var parentId = layer.parentId;
    while (parentId != null) {
      if (!visited.add(parentId)) {
        throw StateError(
          'Parent cycle detected while compiling layer ${layer.id}.',
        );
      }
      final parent = byId[parentId];
      if (parent == null) break;
      final parentLocal = _local(parent);
      enabled = enabled && parent.enabled;
      current = _combine(parentLocal, current);
      parentId = parent.parentId;
    }
    return ResolvedTransformExpressions(
      positionX: current.positionX,
      positionY: current.positionY,
      positionZ: current.positionZ,
      scaleX: current.scaleX,
      scaleY: current.scaleY,
      scaleZ: current.scaleZ,
      rotationX: current.rotationX,
      rotationY: current.rotationY,
      rotationZ: current.rotationZ,
      opacity: current.opacity,
      enabled: enabled,
    );
  }

  ResolvedTransformExpressions _local(CompositionLayer layer) {
    String value(String property, double fallback, {String time = 't'}) =>
        animationCompiler.scalarExpression(
          layer: layer,
          property: property,
          fallback: fallback,
          timeVariable: time,
        );

    return ResolvedTransformExpressions(
      positionX: value('position.x', layer.transform.position.x),
      positionY: value('position.y', layer.transform.position.y),
      positionZ: value('position.z', layer.transform.position.z),
      scaleX: value('scale.x', layer.transform.scale.x),
      scaleY: value('scale.y', layer.transform.scale.y),
      scaleZ: value('scale.z', layer.transform.scale.z),
      rotationX: value('rotation.x', layer.transform.rotation.x),
      rotationY: value('rotation.y', layer.transform.rotation.y),
      rotationZ: value('rotation.z', layer.transform.rotation.z),
      opacity: value(
        'opacity',
        layer.transform.opacity,
        time: 'T',
      ),
      enabled: layer.enabled,
    );
  }

  ResolvedTransformExpressions _combine(
    ResolvedTransformExpressions parent,
    ResolvedTransformExpressions child,
  ) {
    String position(String parentPosition, String childPosition, String scale) =>
        '(' + parentPosition + '+(' + childPosition + ')*(' + scale + ')/100)';
    String scale(String parentScale, String childScale) =>
        '((' + parentScale + ')*(' + childScale + ')/100)';
    String rotation(String parentRotation, String childRotation) =>
        '((' + parentRotation + ')+(' + childRotation + '))';

    return ResolvedTransformExpressions(
      positionX: position(parent.positionX, child.positionX, parent.scaleX),
      positionY: position(parent.positionY, child.positionY, parent.scaleY),
      positionZ: position(parent.positionZ, child.positionZ, parent.scaleZ),
      scaleX: scale(parent.scaleX, child.scaleX),
      scaleY: scale(parent.scaleY, child.scaleY),
      scaleZ: scale(parent.scaleZ, child.scaleZ),
      rotationX: rotation(parent.rotationX, child.rotationX),
      rotationY: rotation(parent.rotationY, child.rotationY),
      rotationZ: rotation(parent.rotationZ, child.rotationZ),
      opacity: '((' + parent.opacity + ')*(' + child.opacity + ')/100)',
      enabled: parent.enabled && child.enabled,
    );
  }
}
