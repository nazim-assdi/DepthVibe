import 'dart:math' as math;

import '../domain/composition_models.dart';
import 'parent_transform_expression_resolver.dart';
import 'parent_transform_resolver.dart';

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

/// Shared camera-space projection helpers for the compositor and CPU mesh renderer.
///
/// Image/video layers still use camera-facing 2.5D cards. OBJ mesh vertices use
/// the same camera-space rotation, lens scale and near/far visibility rules.
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
      effectiveCameraRotation(camera, settings),
    );

    final distance = settings.focusDistance - local.z;
    final visible = isDistanceVisible(distance, settings);
    final factor = projectionFactor(local.z, settings);

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
    final rotationX = settings.cameraMode == 'twoNode'
        ? 'atan2(-(' + _n(settings.pointOfInterestY) + '-(' +
            camera.positionY + ')),sqrt(pow((' +
            _n(settings.pointOfInterestX) + '-(' + camera.positionX +
            ')),2)+pow((' + _n(settings.pointOfInterestZ) + '-(' +
            camera.positionZ + ')),2)))'
        : '((' + camera.rotationX + ')*PI/180)';
    final rotationY = settings.cameraMode == 'twoNode'
        ? 'atan2((' + _n(settings.pointOfInterestX) + '-(' +
            camera.positionX + ')),(' + _n(settings.pointOfInterestZ) +
            '-(' + camera.positionZ + ')))'
        : '((' + camera.rotationY + ')*PI/180)';
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

    final focus = _n(settings.focusDistance.clamp(1.0, 5000.0));
    final nearPlane = _n(settings.nearClip.clamp(0.01, 100000.0));
    final farPlane = _n(settings.farClip.clamp(
      settings.nearClip.clamp(0.01, 100000.0) + 0.01,
      1000000.0,
    ));
    final distance = '(' + focus + '-(' + cameraZ + '))';
    final visibility =
        'if(gte(' + distance + ',' + nearPlane + ')*lte(' + distance + ',' + farPlane + '),1,0)';
    final factor = settings.projection == 'orthographic'
        ? '1'
        : 'min(20,' + focus + '/max(' + nearPlane + ',' +
            distance + ')*' + _n(_fieldOfViewFactor(settings)) + ')';

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

  /// Resolved one-node Euler rotation or a two-node look-at rotation.
  /// A coincident point of interest safely falls back to the authored rotation.
  Vector3 effectiveCameraRotation(
    ResolvedLayerTransform camera,
    CameraSettings settings,
  ) {
    if (settings.cameraMode != 'twoNode') return camera.rotation;
    final dx = settings.pointOfInterestX - camera.position.x;
    final dy = settings.pointOfInterestY - camera.position.y;
    final dz = settings.pointOfInterestZ - camera.position.z;
    final horizontal = math.sqrt(dx * dx + dz * dz);
    if (horizontal + dy.abs() < 0.000001) return camera.rotation;
    return Vector3(
      math.atan2(-dy, horizontal) * 180 / math.pi,
      math.atan2(dx, dz) * 180 / math.pi,
      camera.rotation.z,
    );
  }

  /// Converts a world-space offset into camera space using the same
  /// inverse Euler rotation used by the 2.5D compositor and mesh renderer.
  Vector3 worldToCameraOffset(Vector3 offset, Vector3 rotationDegrees) =>
      _worldToCamera(offset, rotationDegrees);

  bool isDistanceVisible(double distance, CameraSettings settings) {
    final near = settings.nearClip.clamp(0.01, 100000.0).toDouble();
    final far = settings.farClip.clamp(near + 0.01, 1000000.0).toDouble();
    return distance >= near && distance <= far;
  }

  /// Returns the perspective magnification at a camera-space Z coordinate.
  /// Orthographic cameras still honour near/far clipping.
  double projectionFactor(double cameraSpaceZ, CameraSettings settings) {
    final focus = settings.focusDistance.clamp(1.0, 5000.0).toDouble();
    final distance = focus - cameraSpaceZ;
    if (!isDistanceVisible(distance, settings)) return 0;
    if (settings.projection == 'orthographic') return 1;
    final near = settings.nearClip.clamp(0.01, 100000.0).toDouble();
    return math.min(
      20.0,
      focus / math.max(near, distance) * _fieldOfViewFactor(settings),
    ).toDouble();
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
