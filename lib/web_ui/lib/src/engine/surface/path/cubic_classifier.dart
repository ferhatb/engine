// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

abstract class CubicType {
  // This curve has 3 co-linear inflection points.
  // https://en.wikipedia.org/wiki/Serpentine_curve
  static const int kSerpentine = 0;
  // One inflection point and one double point.
  static const int kLoop = 1;
  // One inflection point and one cusp.
  // Cusp at a non-infinite t with an inflection at t=infinity.
  static const int kLocalCusp = 2;
  // Cusp at t=infinity and a local inflection point.
  static const int kCuspAtInfinity = 3;
  static const int kQuadratic = 4;
  static const int kLineOrPoint = 5;
}

/// Classifies a cubic curve as a point, line, cubic or a degenerate form of
/// cubic that has inflection points.
///
/// Computes t values at the inflection points to be able to subdivide a
/// cubic to use for intersection/ordering.
///
/// For background see:
/// http://graphics.pixar.com/people/derose/publications/CubicClassification/paper.pdf
/// https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-25-rendering-vector-art-gpu
///
/// At an inflection point on a curve, the curvature vanishes at values t
/// where the first and second derivates are 0. Given vector d * C(t) = [0 0 0].
/// We convert a cubic curve C(t) to a cubic polynomial I(t,s) where
/// the roots are the inflection points.
///
/// The inflection point polynomial is:
/// I(t,s) = d0*t³ - 3d1*t²s + 3d2*t*s² - d3*s³
/// Solving for the roots requires solving cubic equation. Since the curve
/// is integral (w=1) , it simplifies to s(- 3d1*t²s + 3d2*t*s²).
///
class CubicClassifier {
  final double t0, t1;
  final double s0, s1;
  final int cubicType;

  CubicClassifier(this.cubicType, this.t0, this.t1, this.s0, this.s1);
  CubicClassifier.fromType(this.cubicType)
      : t0 = 0,
        t1 = 0,
        s0 = 0,
        s1 = 0;

  /// Constructs from unordered list of roots.
  factory CubicClassifier.fromInflectionRoots(
      int cubicType, double t0, double s0, double t1, double s1) {
    // Orient the function so positive values are on the left side of the curve.
    t1 = -copySign(t1, t1 * s1);
    s1 = -s1.abs();
    if (copySign(s1, s0) * t0 > -(s0 * t1).abs()) {
      return CubicClassifier(cubicType, t1, s1, t0, s0);
    } else {
      return CubicClassifier(cubicType, t0, s0, t1, s1);
    }
  }

  /// Classifies curve.
  ///
  /// If [computeRoots] is set to false, only returns cubic curve type.
  static CubicClassifier classify(Float32List points,
      {bool computeRoots = true}) {
    // Compute vector d where C(T)*d = 0.
    final double a1 = _dotProductCubic(
        points[0], points[1], points[6], points[7], points[4], points[5]);
    final double a2 = _dotProductCubic(
        points[2], points[3], points[0], points[1], points[6], points[7]);
    final double a3 = _dotProductCubic(
        points[4], points[5], points[2], points[3], points[0], points[1]);

    double d3 = 3.0 * a3;
    double d2 = d3 - a2;
    double d1 = d2 - a2 + a1;

    // To prevent possible exponent overflows, scale the d values to get
    // a more stable solution to quadratic equation.
    double dMax = math.max(d1.abs(), math.max(d2.abs(), d3.abs()));
    double scaleToNormalize = previousInversePow2(dMax);
    d1 *= scaleToNormalize;
    d2 *= scaleToNormalize;
    d3 *= scaleToNormalize;

    int type;
    if (d1 != 0) {
      double discr = 3 * d2 * d2 - 4 * d1 * d3;
      if (discr > 0) {
        // Serpentine.
        if (!computeRoots) {
          double q = 3 * d2 + copySign(math.sqrt(3 * discr), d2);
          return CubicClassifier.fromInflectionRoots(
              CubicType.kSerpentine, q, 6 * d1, 2 * d3, q);
        }
        return CubicClassifier.fromType(CubicType.kSerpentine);
      } else if (discr < 0) {
        // Loop.
        if (computeRoots) {
          double q = d2 + copySign(math.sqrt(-discr), d2);
          CubicClassifier.fromInflectionRoots(
              CubicType.kLoop, q, 2 * d1, 2 * (d2 * d2 - d3 * d1), d1 * q);
        }
        return CubicClassifier.fromType(CubicType.kLoop);
      } else {
        // Cusp.
        if (computeRoots) {
          return CubicClassifier.fromInflectionRoots(
              CubicType.kLocalCusp, d2, 2 * d1, d2, 2 * d1);
        }
        return CubicClassifier.fromType(CubicType.kLocalCusp);
      }
    } else {
      if (0 != d2) {
        // Cusp at T=infinity.
        if (computeRoots) {
          CubicClassifier.fromInflectionRoots(
              CubicType.kCuspAtInfinity, d3, 3 * d2, 1, 0);
        }
        return CubicClassifier.fromType(CubicType.kCuspAtInfinity);
      } else {
        // Degenerate.
        int type = 0 != d3 ? CubicType.kQuadratic : CubicType.kLineOrPoint;
        if (computeRoots) {
          return CubicClassifier.fromInflectionRoots(type, 1, 0, 1, 0);
        }
        return CubicClassifier.fromType(type);
      }
    }
  }
}
