import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/composition_models.dart';
import 'obj_mesh_loader.dart';

/// Evaluates glTF node hierarchies and animation channels at a composition
/// timestamp. CPU evaluation keeps the same pose shared by CPU and GPU paths.
class GltfSceneEvaluator {
  const GltfSceneEvaluator();

  List<Float64List> worldMatrices(
    ObjMesh mesh, {
    int timeMs = 0,
    int animationIndex = 0,
    bool loop = true,
  }) {
    final nodes = mesh.sceneNodes;
    if (nodes.isEmpty) return const [];

    final translations = [
      for (final node in nodes)
        [node.translation.x, node.translation.y, node.translation.z],
    ];
    final rotations = [
      for (final node in nodes) List<double>.of(node.rotation),
    ];
    final scales = [
      for (final node in nodes)
        [node.scale.x, node.scale.y, node.scale.z],
    ];

    if (mesh.animations.isNotEmpty &&
        animationIndex >= 0 &&
        animationIndex < mesh.animations.length) {
      final clip = mesh.animations[animationIndex];
      final duration = clip.durationSeconds;
      var seconds = timeMs / 1000.0;
      if (loop && duration > 0) {
        seconds %= duration;
      } else {
        seconds = seconds.clamp(0.0, duration).toDouble();
      }

      for (final channel in clip.channels) {
        if (channel.nodeIndex < 0 || channel.nodeIndex >= nodes.length) continue;
        final sampled = _sample(channel, seconds);
        if (sampled.isEmpty) continue;
        switch (channel.path) {
          case 'translation':
            _copyInto(translations[channel.nodeIndex], sampled, 3);
            break;
          case 'rotation':
            _copyInto(rotations[channel.nodeIndex], sampled, 4);
            final q = rotations[channel.nodeIndex];
            final length = math.sqrt(q.fold<double>(0, (sum, v) => sum + v * v));
            if (length > 1e-9) {
              for (var i = 0; i < 4; i++) {
                q[i] /= length;
              }
            }
            break;
          case 'scale':
            _copyInto(scales[channel.nodeIndex], sampled, 3);
            break;
          // Morph weights are preserved in the animation metadata but do not
          // alter the current triangle stream yet.
        }
      }
    }

    final local = List<Float64List>.generate(nodes.length, (index) {
      final node = nodes[index];
      if (node.isMatrixTransform) {
        return Float64List.fromList(node.localMatrix);
      }
      return _composeTrs(
        translations[index],
        rotations[index],
        scales[index],
      );
    });
    final world = List<Float64List?>.filled(nodes.length, null);
    final resolving = <int>{};

    Float64List resolve(int index) {
      final cached = world[index];
      if (cached != null) return cached;
      if (!resolving.add(index)) {
        throw StateError('glTF node hierarchy contains a cycle at $index.');
      }
      final parent = nodes[index].parentIndex;
      final matrix = parent == null
          ? local[index]
          : _multiply(resolve(parent), local[index]);
      resolving.remove(index);
      world[index] = matrix;
      return matrix;
    }

    return List<Float64List>.generate(nodes.length, resolve);
  }

  Vector3 transformPoint(Float64List matrix, Vector3 point) {
    final x = matrix[0] * point.x +
        matrix[4] * point.y +
        matrix[8] * point.z +
        matrix[12];
    final y = matrix[1] * point.x +
        matrix[5] * point.y +
        matrix[9] * point.z +
        matrix[13];
    final z = matrix[2] * point.x +
        matrix[6] * point.y +
        matrix[10] * point.z +
        matrix[14];
    final w = matrix[3] * point.x +
        matrix[7] * point.y +
        matrix[11] * point.z +
        matrix[15];
    if (w.abs() < 1e-9 || (w - 1).abs() < 1e-9) {
      return Vector3(x, y, z);
    }
    return Vector3(x / w, y / w, z / w);
  }

  Vector3 transformNormal(Float64List m, Vector3 n) {
    final a = m[0], b = m[4], c = m[8];
    final d = m[1], e = m[5], f = m[9];
    final g = m[2], h = m[6], i = m[10];
    final c00 = e * i - f * h;
    final c01 = f * g - d * i;
    final c02 = d * h - e * g;
    final c10 = c * h - b * i;
    final c11 = a * i - c * g;
    final c12 = b * g - a * h;
    final c20 = b * f - c * e;
    final c21 = c * d - a * f;
    final c22 = a * e - b * d;
    final determinant = a * c00 + b * c01 + c * c02;
    if (determinant.abs() < 1e-10) {
      return _normalize(Vector3(
        a * n.x + b * n.y + c * n.z,
        d * n.x + e * n.y + f * n.z,
        g * n.x + h * n.y + i * n.z,
      ));
    }
    final inv = 1 / determinant;
    return _normalize(Vector3(
      (c00 * n.x + c01 * n.y + c02 * n.z) * inv,
      (c10 * n.x + c11 * n.y + c12 * n.z) * inv,
      (c20 * n.x + c21 * n.y + c22 * n.z) * inv,
    ));
  }

  List<double> _sample(GltfMeshAnimationChannel channel, double seconds) {
    final times = channel.times;
    final values = channel.values;
    final components = channel.componentCount;
    if (times.isEmpty || components <= 0 || values.isEmpty) return const [];

    int valueOffset(int keyframe) =>
        channel.interpolation == 'CUBICSPLINE'
            ? keyframe * components * 3 + components
            : keyframe * components;

    if (seconds <= times.first) {
      final offset = valueOffset(0);
      return values.sublist(offset, offset + components);
    }
    if (seconds >= times.last) {
      final offset = valueOffset(times.length - 1);
      return values.sublist(offset, offset + components);
    }

    var left = 0;
    for (var i = 0; i < times.length - 1; i++) {
      if (seconds >= times[i] && seconds <= times[i + 1]) {
        left = i;
        break;
      }
    }
    final right = left + 1;
    final span = times[right] - times[left];
    if (span <= 0) {
      final offset = valueOffset(left);
      return values.sublist(offset, offset + components);
    }
    final t = ((seconds - times[left]) / span).clamp(0.0, 1.0).toDouble();
    final leftValue = valueOffset(left);
    if (channel.interpolation == 'STEP') {
      return values.sublist(leftValue, leftValue + components);
    }

    final rightValue = valueOffset(right);
    if (channel.interpolation == 'CUBICSPLINE') {
      final leftOut = left * components * 3 + components * 2;
      final rightIn = right * components * 3;
      final t2 = t * t;
      final t3 = t2 * t;
      final h00 = 2 * t3 - 3 * t2 + 1;
      final h10 = t3 - 2 * t2 + t;
      final h01 = -2 * t3 + 3 * t2;
      final h11 = t3 - t2;
      return List<double>.generate(components, (component) {
        final p0 = values[leftValue + component];
        final m0 = values[leftOut + component] * span;
        final p1 = values[rightValue + component];
        final m1 = values[rightIn + component] * span;
        return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1;
      });
    }

    if (channel.path == 'rotation' && components == 4) {
      return _slerp(
        values.sublist(leftValue, leftValue + 4),
        values.sublist(rightValue, rightValue + 4),
        t,
      );
    }
    return List<double>.generate(
      components,
      (component) => values[leftValue + component] * (1 - t) +
          values[rightValue + component] * t,
    );
  }

  List<double> _slerp(List<double> a, List<double> b, double t) {
    var dot = 0.0;
    for (var i = 0; i < 4; i++) {
      dot += a[i] * b[i];
    }
    final end = List<double>.of(b);
    if (dot < 0) {
      dot = -dot;
      for (var i = 0; i < 4; i++) {
        end[i] = -end[i];
      }
    }
    if (dot > 0.9995) {
      final result = List<double>.generate(
        4,
        (i) => a[i] + (end[i] - a[i]) * t,
      );
      final length = math.sqrt(result.fold<double>(0, (sum, v) => sum + v * v));
      return result.map((v) => v / length).toList();
    }
    final theta = math.acos(dot.clamp(-1.0, 1.0).toDouble());
    final sinTheta = math.sin(theta);
    final wa = math.sin((1 - t) * theta) / sinTheta;
    final wb = math.sin(t * theta) / sinTheta;
    return List<double>.generate(4, (i) => a[i] * wa + end[i] * wb);
  }

  void _copyInto(List<double> target, List<double> source, int count) {
    for (var i = 0; i < count && i < target.length && i < source.length; i++) {
      target[i] = source[i];
    }
  }

  Float64List _composeTrs(
    List<double> translation,
    List<double> rotation,
    List<double> scale,
  ) {
    final x = rotation[0], y = rotation[1], z = rotation[2], w = rotation[3];
    final xx = x * x, yy = y * y, zz = z * z;
    final xy = x * y, xz = x * z, yz = y * z;
    final wx = w * x, wy = w * y, wz = w * z;
    final sx = scale[0], sy = scale[1], sz = scale[2];
    return Float64List.fromList([
      (1 - 2 * (yy + zz)) * sx,
      (2 * (xy + wz)) * sx,
      (2 * (xz - wy)) * sx,
      0,
      (2 * (xy - wz)) * sy,
      (1 - 2 * (xx + zz)) * sy,
      (2 * (yz + wx)) * sy,
      0,
      (2 * (xz + wy)) * sz,
      (2 * (yz - wx)) * sz,
      (1 - 2 * (xx + yy)) * sz,
      0,
      translation[0],
      translation[1],
      translation[2],
      1,
    ]);
  }

  Float64List _multiply(Float64List a, Float64List b) {
    final result = Float64List(16);
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        var value = 0.0;
        for (var k = 0; k < 4; k++) {
          value += a[k * 4 + row] * b[column * 4 + k];
        }
        result[column * 4 + row] = value;
      }
    }
    return result;
  }

  Vector3 _normalize(Vector3 value) {
    final length = math.sqrt(
      value.x * value.x + value.y * value.y + value.z * value.z,
    );
    if (length < 1e-9) return const Vector3(0, 0, 0);
    return Vector3(value.x / length, value.y / length, value.z / length);
  }
}
