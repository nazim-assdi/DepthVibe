import 'dart:math' as math;

import '../domain/composition_models.dart';
import 'parent_transform_expression_resolver.dart';

class CameraProjectedTransform {
  const CameraProjectedTransform({
    required this.position,
    required this.scale,
    required this.rotation,
    required this.opacity,
  });

  final Vector3 position;
  final Vector3 scale;
  final Vector3 rotation;
  final double opacity;
}

class CameraProjectedExpressions {
  const CameraProjectedExpressions({
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
}

/// Shared 2.5D camera projection for the composition preview and FFmpeg export.
///
/// It projects layer centres and scales around a camera position using depth,
/// focal length and field of view. It is not a mesh renderer and does not yet
/// model camera orientation, surface normals, shadows or depth-of-field.
class CameraProjectionResolver {
  const CameraProjectionResolver();

  CameraProjectedTransform project({
    required ResolvedLayerTransform layer,
    required ResolvedLayerTransform camera,
    required CameraSettings settings,
  }) {
    if (settings.projection == 'orthographic') {
      return CameraProjectedTransform(
        position: layer.position,
        scale: layer.scale,
        rotation: layer.rotation,
        opacity: layer.opacity,
      );
    }

    final factor = _projectionFactor(
      settings: settings,
      relativeDepth: layer.position.z - camera.position.z,
    );
    return CameraProjectedTransform(
      position: Vector3(
        camera.position.x + (layer.position.x - camera.position.x) * factor,
        camera.position.y + (layer.position.y - camera.position.y) * factor,
        layer.position.z,
      ),
      scale: Vector3(
        layer.scale.x * factor,
        layer.scale.y * factor,
        layer.scale.z * factor,
      ),
      rotation: layer.rotation,
      opacity: layer.opacity,
    );
  }

  CameraProjectedExpressions compile({
    required ResolvedTransformExpressions layer,
    required ResolvedTransformExpressions camera,
    required CameraSettings settings,
  }) {
    if (settings.projection == 'orthographic') {
      return CameraProjectedExpressions(
        positionX: layer.positionX,
        positionY: layer.positionY,
        positionZ: layer.positionZ,
        scaleX: layer.scaleX,
        scaleY: layer.scaleY,
        scaleZ: layer.scaleZ,
        rotationX: layer.rotationX,
        rotationY: layer.rotationY,
        rotationZ: layer.rotationZ,
        opacity: layer.opacity,
      );
    }

    final focus = _n(settings.focusDistance.clamp(1.0, 5000.0));
    final depth = '(' + layer.positionZ + '-(' + camera.positionZ + '))';
    final distance = 'max(1,(' + focus + ')-' + depth + ')';
    final fov = settings.fieldOfView.clamp(10.0, 120.0) * math.pi / 180;
    final fovFactor = math.tan(25 * math.pi / 180) /
        math.tan(fov / 2);
    final focalFactor =
        settings.focalLength.clamp(10.0, 300.0) / 50.0;
    final constantFactor = _n(fovFactor * focalFactor);
    final factor =
        '((' + focus + ')/(' + distance + ')*' + constantFactor + ')';

    String position(String cameraPosition, String layerPosition) =>
        '(' + cameraPosition + '+((' + layerPosition + ')-(' +
        cameraPosition + '))*' + factor + ')';
    String scale(String value) => '((' + value + ')*' + factor + ')';

    return CameraProjectedExpressions(
      positionX: position(camera.positionX, layer.positionX),
      positionY: position(camera.positionY, layer.positionY),
      positionZ: layer.positionZ,
      scaleX: scale(layer.scaleX),
      scaleY: scale(layer.scaleY),
      scaleZ: scale(layer.scaleZ),
      rotationX: layer.rotationX,
      rotationY: layer.rotationY,
      rotationZ: layer.rotationZ,
      opacity: layer.opacity,
    );
  }

  double _projectionFactor({
    required CameraSettings settings,
    required double relativeDepth,
  }) {
    final focus = settings.focusDistance.clamp(1.0, 5000.0);
    final distance = math.max(1.0, focus - relativeDepth);
    final fov = settings.fieldOfView.clamp(10.0, 120.0) * math.pi / 180;
    final fovFactor = math.tan(25 * math.pi / 180) /
        math.tan(fov / 2);
    final focalFactor =
        settings.focalLength.clamp(10.0, 300.0) / 50.0;
    return focus / distance * fovFactor * focalFactor;
  }

  String _n(num value) => value.toStringAsFixed(6);
}
