import 'dart:math' as math;

import '../domain/composition_models.dart';

/// A 3×3 projective transform with the final matrix coefficient normalised to 1.
class Homography2D {
  const Homography2D._(this.values);

  final List<double> values;

  double get determinant {
    final h = values;
    return h[0] * (h[4] * h[8] - h[5] * h[7]) -
        h[1] * (h[3] * h[8] - h[5] * h[6]) +
        h[2] * (h[3] * h[7] - h[4] * h[6]);
  }

  Vector2 transform(Vector2 point) {
    final h = values;
    final denominator = h[6] * point.x + h[7] * point.y + h[8];
    if (!denominator.isFinite || denominator.abs() < 1e-10) {
      throw StateError('Homography maps this point to infinity.');
    }
    final x = (h[0] * point.x + h[1] * point.y + h[2]) / denominator;
    final y = (h[3] * point.x + h[4] * point.y + h[5]) / denominator;
    if (!x.isFinite || !y.isFinite) {
      throw StateError('Homography produced a non-finite point.');
    }
    return Vector2(x, y);
  }

  List<Vector2> transformAll(Iterable<Vector2> points) =>
      List.unmodifiable(points.map(transform));

  /// Estimates the projective transform from four or more matched points.
  ///
  /// With more than four correspondences, a least-squares solution is computed
  /// using the normal equations. Coordinates should be in a consistent space;
  /// callers should normalise very large pixel coordinates before estimating.
  factory Homography2D.fromCorrespondences({
    required List<Vector2> source,
    required List<Vector2> destination,
  }) {
    if (source.length != destination.length || source.length < 4) {
      throw ArgumentError(
        'A homography needs at least four matched source/destination points.',
      );
    }
    for (var index = 0; index < source.length; index++) {
      final a = source[index];
      final b = destination[index];
      if (!a.x.isFinite || !a.y.isFinite || !b.x.isFinite || !b.y.isFinite) {
        throw ArgumentError('Homography correspondence points must be finite.');
      }
    }

    final rows = <List<double>>[];
    final targets = <double>[];
    for (var index = 0; index < source.length; index++) {
      final x = source[index].x;
      final y = source[index].y;
      final u = destination[index].x;
      final v = destination[index].y;
      rows.add([
        x, y, 1, 0, 0, 0, -u * x, -u * y,
      ]);
      targets.add(u);
      rows.add([
        0, 0, 0, x, y, 1, -v * x, -v * y,
      ]);
      targets.add(v);
    }

    final matrix = List<List<double>>.generate(
      8,
      (row) => List<double>.filled(8, 0),
    );
    final vector = List<double>.filled(8, 0);

    for (var row = 0; row < rows.length; row++) {
      for (var i = 0; i < 8; i++) {
        vector[i] += rows[row][i] * targets[row];
        for (var j = 0; j < 8; j++) {
          matrix[i][j] += rows[row][i] * rows[row][j];
        }
      }
    }

    final solution = _solve(matrix, vector);
    final values = List<double>.unmodifiable([
      ...solution,
      1,
    ]);
    final result = Homography2D._(values);
    if (!result.determinant.isFinite ||
        result.determinant.abs() < 1e-12) {
      throw StateError('Matched points do not define a stable homography.');
    }
    return result;
  }

  static List<double> _solve(
    List<List<double>> matrix,
    List<double> vector,
  ) {
    const epsilon = 1e-11;
    final size = vector.length;
    final a = List<List<double>>.generate(
      size,
      (row) => [...matrix[row], vector[row]],
    );

    for (var column = 0; column < size; column++) {
      var pivot = column;
      for (var row = column + 1; row < size; row++) {
        if (a[row][column].abs() > a[pivot][column].abs()) {
          pivot = row;
        }
      }
      if (a[pivot][column].abs() < epsilon) {
        throw StateError(
          'Matched points are degenerate; a stable homography cannot be solved.',
        );
      }
      if (pivot != column) {
        final temporary = a[column];
        a[column] = a[pivot];
        a[pivot] = temporary;
      }

      final divisor = a[column][column];
      for (var entry = column; entry <= size; entry++) {
        a[column][entry] /= divisor;
      }

      for (var row = 0; row < size; row++) {
        if (row == column) continue;
        final factor = a[row][column];
        if (factor.abs() < epsilon) continue;
        for (var entry = column; entry <= size; entry++) {
          a[row][entry] -= factor * a[column][entry];
        }
      }
    }

    final result = List<double>.generate(size, (index) => a[index][size]);
    if (result.any((value) => !value.isFinite)) {
      throw StateError('Homography solution is not finite.');
    }
    return result;
  }
}

/// Reports geometric tracking quality from matched planar feature points.
class HomographyFit {
  const HomographyFit({
    required this.transform,
    required this.meanReprojectionError,
    required this.maximumReprojectionError,
  });

  final Homography2D transform;
  final double meanReprojectionError;
  final double maximumReprojectionError;
}

class PlanarHomographyEstimator {
  const PlanarHomographyEstimator();

  HomographyFit estimate({
    required List<Vector2> source,
    required List<Vector2> destination,
  }) {
    final transform = Homography2D.fromCorrespondences(
      source: source,
      destination: destination,
    );
    final errors = <double>[];
    for (var index = 0; index < source.length; index++) {
      final predicted = transform.transform(source[index]);
      errors.add(math.sqrt(
        math.pow(predicted.x - destination[index].x, 2) +
            math.pow(predicted.y - destination[index].y, 2),
      ));
    }
    final mean = errors.reduce((a, b) => a + b) / errors.length;
    final maximum = errors.reduce(math.max);
    return HomographyFit(
      transform: transform,
      meanReprojectionError: mean,
      maximumReprojectionError: maximum,
    );
  }
}
