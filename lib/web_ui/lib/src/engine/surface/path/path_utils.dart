// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
part of engine;

/// Mask used to keep track of types of verbs used in a path segment.
class SPathSegmentMask {
  static const int kLine_SkPathSegmentMask   = 1 << 0;
  static const int kQuad_SkPathSegmentMask   = 1 << 1;
  static const int kConic_SkPathSegmentMask  = 1 << 2;
  static const int kCubic_SkPathSegmentMask  = 1 << 3;
}

/// Types of path operations.
class SPathVerb {
  static const int kMove = 1;  // 1 point
  static const int kLine = 2;  // 2 points
  static const int kQuad = 3;  // 3 points
  static const int kConic = 4; // 3 points + 1 weight
  static const int kCubic = 5; // 4 points
  static const int kClose = 6; // 0 points
}

class SPath {
  static const int kMoveVerb = SPathVerb.kMove;
  static const int kLineVerb = SPathVerb.kLine;
  static const int kQuadVerb = SPathVerb.kQuad;
  static const int kConicVerb = SPathVerb.kConic;
  static const int kCubicVerb = SPathVerb.kCubic;
  static const int kCloseVerb = SPathVerb.kClose;
  static const int kDoneVerb = SPathVerb.kClose + 1;

  static const int kLineSegmentMask   = SPathSegmentMask.kLine_SkPathSegmentMask;
  static const int kQuadSegmentMask   = SPathSegmentMask.kQuad_SkPathSegmentMask;
  static const int kConicSegmentMask  = SPathSegmentMask.kConic_SkPathSegmentMask;
  static const int kCubicSegmentMask  = SPathSegmentMask.kCubic_SkPathSegmentMask;

  static const double scalarNearlyZero = 1.0 / (1 << 12);
  /// Square root of 2 divided by 2. Useful for sin45 = cos45 = 1/sqrt(2).
  static const double scalarRoot2Over2 = 0.707106781;

  /// True if (a <= b <= c) || (a >= b >= c)
  static bool between(double a, double b, double c) {
    return (a - b) * (c - b) <= 0;
  }

  /// Returns -1 || 0 || 1 depending on the sign of value:
  /// -1 if x < 0
  ///  0 if x == 0
  ///  1 if x > 0
  static int scalarSignedAsInt(double x) {
    return x < 0 ? -1 : ((x > 0) ? 1 : 0);
  }
}

class SPathAddPathMode {
  // Append to destination unaltered.
  static const int kAppend = 0;
  // Add line if prior contour is not closed.
  static const int kExtend = 1;
}

class SPathDirection {
  /// Uninitialized value for empty paths.
  static const int kUnknown = -1;
  /// clockwise direction for adding closed contours.
  static const int kCW = 0;
  /// counter-clockwise direction for adding closed contours.
  static const int kCCW = 1;
}

class SPathConvexityType {
  static const int kUnknown = -1;
  static const int kConvex = 0;
  static const int kConcave = 1;
}

class SPathSegmentState {
  /// The current contour is empty. Starting processing or have just closed
  /// a contour.
  static const int kEmptyContour = 0;
  /// Have seen a move, but nothing else.
  static const int kAfterMove = 1;
  /// Have seen a primitive but not yet closed the path. Also the initial state.
  static const int kAfterPrimitive = 2;
}

/// Quadratic roots. See Numerical Recipes in C.
///
///    Q = -1/2 (B + sign(B) sqrt[B*B - 4*A*C])
///    x1 = Q / A
///    x2 = C / Q
class _QuadRoots {
  double root0;
  double root1;

  _QuadRoots();

  /// Returns roots as list.
  List<double> get roots =>
      (root0 == null) ? [] : (root1 == null ? [root0] : [root0, root1]);

  int findRoots(double a, double b, double c) {
    int rootCount = 0;
    if (a == 0) {
      root0 = _validUnitDivide(-c, b);
      return root0 == null ? 0 : 1;
    }

    double dr = b * b - 4 * a * c;
    if (dr < 0) {
      return 0;
    }
    dr = math.sqrt(dr);
    if (!dr.isFinite) {
      return 0;
    }

    double q = (b < 0) ? - (b - dr) / 2 : - (b + dr) / 2;
    double res = _validUnitDivide(q, a);
    if (res != null) {
      root0 = res;
      ++rootCount;
    }
    res = _validUnitDivide(c, q);
    if (res != null) {
      if (rootCount == 0) {
        root0 = res;
        ++rootCount;
      } else {
        root1 = res;
        ++rootCount;
      }
    }
    if (rootCount == 2) {
      if (root0 > root1) {
        final double swap = root0;
        root0 = root1;
        root1 = swap;
      } else if (root0 == root1) {
        return 1; // skip the double root
      }
    }
    return rootCount;
  }
}

double _validUnitDivide(double numer, double denom) {
  if (numer < 0) {
    numer = -numer;
    denom = -denom;
  }
  if (denom == 0 || numer == 0 || numer >= denom) {
    return null;
  }
  final double r = numer / denom;
  if (r.isNaN) {
    return null;
  }
  if (r == 0) { // catch underflow if numer <<<< denom
    return null;
  }
  return r;
}

// Snaps a value to zero if almost zero (within tolerance).
double _snapToZero(double value) => _nearlyEqual(value, 0.0) ? 0.0 : value;

bool _nearlyEqual(double value1, double value2) =>
    (value1 - value2).abs() < SPath.scalarNearlyZero;

bool _isInteger(double value) => value.floor() == value;

bool _isRRectOval(ui.RRect rrect) {
  if ((rrect.tlRadiusX + rrect.trRadiusX) != rrect.width) {
    return false;
  }
  if ((rrect.tlRadiusY + rrect.trRadiusY) != rrect.height) {
    return false;
  }
  if (rrect.tlRadiusX != rrect.blRadiusX || rrect.trRadiusX != rrect.brRadiusX
      || rrect.tlRadiusY != rrect.blRadiusY || rrect.trRadiusY != rrect.brRadiusY) {
    return false;
  }
  return true;
}

/// Evaluates degree 2 polynomial (quadratic).
double polyEval(double A, double B, double C, double t) =>
    (A * t + B) * t + C;

/// Evaluates degree 3 polynomial (cubic).
double polyEval4(double A, double B, double C, double D, double t) =>
    ((A * t + B) * t + C) * t + D;
