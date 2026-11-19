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

/// Shared 2.5D camera projection for compositor preview and FFmpeg export.
///
/// The camera's inverse Euler rotation is applied to layer positions before
/// projection. Image/video layers remain camera-facing 2.5D cards; this is not
/// a mesh renderer and does not calculate per-vertex perspective or lighting.
class CameraProjectionResolver {
  const CameraProjectionResolver();

  CameraProjectedTransform project({
    required ResolvedLayerTransform layer,
    required ResolvedLayerTransform camera,
    required CameraSettings settings,
  }) {
    final local = _worldToCamera(
      Vector3(
        layer.position.x - camera.position.x,
        layer.position.y - camera.position.y,
        layer.position.z - camera.position.z,
      ),
      camera.rotation,
    );

    final perspective = settings.projection != 'orthographic';
    final focus = settings.focusDistance.clamp(1.0, 5000.0).toDouble();
    final nearPlane = focus * 0.05;
    final distance = focus - local.z;
    final visible = !perspective || distance >= nearPlane;
    final factor = perspective
        ? math.min(
            20.0,
            focus / math.max(nearPlane, distance) *
                _fieldOfViewFactor(settings),
          ).toDouble()
        : 1.0;

    return CameraProjectedTransform(
      position: Vector3(
        camera.position.x + local.x * factor,
        camera.position.y + local.y * factor,
        layer.position.z,
      ),
      scale: Vector3(
        layer.scale.x * factor,
        layer.scale.y * factor,
        layer.scale.z * factor,
      ),
      // Camera roll rotates the image plane in the opposite direction.
      // X/Y layer rotation remains available to future mesh/card renderers.
      rotation: Vector3(
        layer.rotation.x,
        layer.rotation.y,
        layer.rotation.z - camera.rotation.z,
      ),
      opacity: visible ? layer.opacity : 0,
    );
  }

  CameraProjectedExpressions compile({
    required ResolvedTransformExpressions layer,
    required ResolvedTransformExpressions camera,
    required CameraSettings settings,
  }) {
    final rotationX = '((' + camera.rotationX + ')*PI/180)';
    final rotationY = '((' + camera.rotationY + ')*PI/180)';
    final rotationZ = '((' + camera.rotationZ + ')*PI/180)';

    final dx = '(' + layer.positionX + '-(' + camera.positionX + '))';
    final dy = '(' + layer.positionY + '-(' + camera.positionY + '))';
    final dz = '(' + layer.positionZ + '-(' + camera.positionZ + '))';

    // Inverse camera rotation: Rz(-z), then Ry(-y), then Rx(-x).
    final xAfterRoll = '((' + dx + ')*cos(' + rotationZ + ')+(' +
        dy + ')*sin(' + rotationZ + '))';
    final yAfterRoll = '(-(' + dx + ')*sin(' + rotationZ + ')+(' +
        dy + ')*cos(' + rotationZ + '))';
    final xAfterYaw = '((' + xAfterRoll + ')*cos(' + rotationY +
        ')-(' + dz + ')*sin(' + rotationY + '))';
    final zAfterYaw = '((' + xAfterRoll + ')*sin(' + rotationY +
        ')+(' + dz + ')*cos(' + rotationY + '))';
    final cameraX = xAfterYaw;
    final cameraY = '((' + yAfterRoll + ')*cos(' + rotationX +
        ')+(' + zAfterYaw + ')*sin(' + rotationX + '))';
    final cameraZ = '(-(' + yAfterRoll + ')*sin(' + rotationX +
        ')+(' + zAfterYaw + ')*cos(' + rotationX + '))';

    String factor;
    String visibility;
    if (settings.projection == 'orthographic') {
      factor = '1';
      visibility = '1';
    } else {
      final focus = _n(settings.focusDistance.clamp(1.0, 5000.0));
      final nearPlane = '((' + focus + ')*0.05)';
      final distance = '(' + focus + '-(' + cameraZ + '))';
      final fov = _n(_fieldOfViewFactor(settings));
      factor = 'min(20,' + focus + '/max(' + nearPlane + ',' +
          distance + ')*' + fov + ')';
      visibility = 'if(gte(' + distance + ',' + nearPlane + '),1,0)';
    }

    String screenPosition(String cameraPosition, String cameraOffset) =>
        '(' + cameraPosition + '+(' + cameraOffset + ')*' + factor + ')';
    String scale(String value) => '((' + value + ')*' + factor + ')';

    return CameraProjectedExpressions(
      positionX: screenPosition(camera.positionX, cameraX),
      positionY: screenPosition(camera.positionY, cameraY),
      positionZ: layer.positionZ,
      scaleX: scale(layer.scaleX),
      scaleY: scale(layer.scaleY),
      scaleZ: scale(layer.scaleZ),
      rotationX: layer.rotationX,
      rotationY: layer.rotationY,
      rotationZ: '(' + layer.rotationZ + '-(' + camera.rotationZ + '))',
      opacity: '((' + layer.opacity + ')*(' + visibility + '))',
    );
  }

  Vector3 _worldToCamera(Vector3 offset, Vector3 rotationDegrees) {
    final rx = _radians(rotationDegrees.x);
    final ry = _radians(rotationDegrees.y);
    final rz = _radians(rotationDegrees.z);

    final cosZ = math.cos(rz);
    final sinZ = math.sin(rz);
    final x1 = offset.x * cosZ + offset.y * sinZ;
    final y1 = -offset.x * sinZ + offset.y * cosZ;

    final cosY = math.cos(ry);
    final sinY = math.sin(ry);
    final x2 = x1 * cosY - offset.z * sinY;
    final z2 = x1 * sinY + offset.z * cosY;

    final cosX = math.cos(rx);
    final sinX = math.sin(rx);
    final y3 = y1 * cosX + z2 * sinX;
    final z3 = -y1 * sinX + z2 * cosX;
    return Vector3(x2, y3, z3);
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  double _fieldOfViewFactor(CameraSettings settings) {
    final fov = settings.fieldOfView.clamp(10.0, 120.0) * math.pi / 180;
    final fovFactor = math.tan(25 * math.pi / 180) / math.tan(fov / 2);
    final focalFactor = settings.focalLength.clamp(10.0, 300.0) / 50.0;
    return fovFactor * focalFactor;
  }

  String _n(num value) => value.toStringAsFixed(6);
}
