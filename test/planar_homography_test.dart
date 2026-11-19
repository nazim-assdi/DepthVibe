import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/planar_homography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const estimator = PlanarHomographyEstimator();

  test('recovers a projective transform from four or more matched corners', () {
    const source = [
      Vector2(0, 0),
      Vector2(100, 0),
      Vector2(100, 100),
      Vector2(0, 100),
      Vector2(50, 50),
      Vector2(25, 75),
    ];
    const h = [1.2, 0.1, 10.0, 0.05, 1.1, 5.0, 0.001, 0.0005, 1.0];
    final destination = source.map((point) {
      final denominator = h[6] * point.x + h[7] * point.y + h[8];
      return Vector2(
        (h[0] * point.x + h[1] * point.y + h[2]) / denominator,
        (h[3] * point.x + h[4] * point.y + h[5]) / denominator,
      );
    }).toList();

    final fit = estimator.estimate(
      source: source,
      destination: destination,
    );

    expect(fit.meanReprojectionError, lessThan(0.000001));
    expect(fit.maximumReprojectionError, lessThan(0.00001));
    for (var index = 0; index < source.length; index++) {
      final mapped = fit.transform.transform(source[index]);
      expect(mapped.x, closeTo(destination[index].x, 0.00001));
      expect(mapped.y, closeTo(destination[index].y, 0.00001));
    }
  });

  test('supports affine translation and transforms a list of points', () {
    final transform = Homography2D.fromCorrespondences(
      source: const [
        Vector2(0, 0),
        Vector2(100, 0),
        Vector2(100, 100),
        Vector2(0, 100),
      ],
      destination: const [
        Vector2(15, 20),
        Vector2(115, 20),
        Vector2(115, 120),
        Vector2(15, 120),
      ],
    );

    final mapped = transform.transformAll(const [
      Vector2(10, 10),
      Vector2(50, 50),
    ]);

    expect(mapped[0].x, closeTo(25, 0.00001));
    expect(mapped[0].y, closeTo(30, 0.00001));
    expect(mapped[1].x, closeTo(65, 0.00001));
    expect(mapped[1].y, closeTo(70, 0.00001));
    expect(transform.determinant, greaterThan(0));
  });

  test('rejects insufficient, mismatched and degenerate correspondences', () {
    expect(
      () => Homography2D.fromCorrespondences(
        source: const [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
        destination: const [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
      ),
      throwsArgumentError,
    );
    expect(
      () => Homography2D.fromCorrespondences(
        source: const [
          Vector2(0, 0),
          Vector2(1, 0),
          Vector2(1, 1),
          Vector2(0, 1),
        ],
        destination: const [
          Vector2(0, 0),
          Vector2(1, 0),
          Vector2(1, 1),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => Homography2D.fromCorrespondences(
        source: const [
          Vector2(0, 0),
          Vector2(1, 0),
          Vector2(2, 0),
          Vector2(3, 0),
        ],
        destination: const [
          Vector2(0, 0),
          Vector2(1, 0),
          Vector2(2, 0),
          Vector2(3, 0),
        ],
      ),
      throwsStateError,
    );
  });

  test('reports infinity when a point lies on the projective horizon', () {
    const source = [
      Vector2(0, 0),
      Vector2(50, 0),
      Vector2(50, 50),
      Vector2(0, 50),
    ];
    final destination = source.map((point) {
      final denominator = 1 - 0.01 * point.x;
      return Vector2(
        point.x / denominator,
        point.y / denominator,
      );
    }).toList();
    final transform = Homography2D.fromCorrespondences(
      source: source,
      destination: destination,
    );

    expect(
      () => transform.transform(const Vector2(100, 10)),
      throwsStateError,
    );
  });
}
