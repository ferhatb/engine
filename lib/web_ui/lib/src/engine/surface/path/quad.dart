// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Quadratic curve utilities.
class Quad {
  final Float32List points;
  Quad(this.points);

  static const int kMaxPoints = 3;

  bool get linear => Quad.isLinear(points, 0, 2);

  static bool isLinear(Float32List points, int startIndex, int endIndex) {
    final LineParameters lineParameters = LineParameters();
    lineParameters.quadEndPointsAt(points, startIndex, endIndex);
    lineParameters.normalize();
    double distance = lineParameters.controlPtDistanceQuad(points);
    double tiniest = math.min(math.min(math.min(math.min(math.min(points[0], points[1]),
        points[2]), points[3]), points[4]), points[5]);
    double largest = math.max(math.max(math.max(math.max(math.max(points[0], points[1]),
        points[2]), points[3]), points[4]), points[5]);
    largest = math.max(largest, -tiniest);
    return approximatelyZeroWhenComparedTo(distance, largest);
  }

  /// Returns sorted list of t values for roots.
  static int rootsValidT(double A, double B, double C, List<double> t) {
    List<double> s = [];
    int realRoots = rootsReal(A, B, C, s);
    int foundRoots = addValidTs(s, realRoots, t);
    return foundRoots;
  }

  /// Numeric Solutions (5.6) suggests to solve the quadratic by computing
  ///   Q = -1/2(B + sgn(B)Sqrt(B^2 - 4 A C))
  ///   and using the roots
  ///   t1 = Q / A
  ///   t2 = C / Q
  ///
  /// this does not discard real roots <= 0 or >= 1 (use [addValidTs]).
  static int rootsReal(double a, double b, double c, List<double> s) {
    if (a == 0) {
      return _handleZero(b, c, s);
    }
    final double p = b / (2 * a);
    final double q = c / a;
    if (approximatelyZero(a) && (approximatelyZeroInverse(p) ||
        approximatelyZeroInverse(q))) {
      return _handleZero(b, c, s);
    }
    // Normal form: x^2 + px + q = 0.
    final double p2 = p * p;
    if (!almostDequalUlps(p2, q) && p2 < q) {
      return 0;
    }
    double sqrtD = 0;
    if (p2 > q) {
      sqrtD = math.sqrt(p2 - q);
    }
    final double root0 = sqrtD - p;
    final double root1 = -sqrtD - p;
    s.add(root0);
    if (almostDequalUlps(root0, root1)) {
      return 1;
    } else {
      s.add(root1);
      return 2;
    }
  }

  /// Compute single root for a = 0.
  static int _handleZero(double b, double c, List<double> s) {
    if (approximatelyZero(b)) {
      s.add(0);
      return c == 0 ? 1 : 0;
    }
    s.add(-c / b);
    return 1;
  }

  /// Filters a source list of T values to the range 0 < t < 1 and
  /// de-duplicates t values that are approximately equal.
  static int addValidTs(List<double> source, int sourceCount, List<double> target) {
    int foundRoots = 0;
    for (int index = 0; index < sourceCount; ++index) {
      double tValue = source[index];
      if (approximatelyZeroOrMore(tValue) && approximatelyOneOrLess(tValue)) {
        if (approximatelyLessThanZero(tValue)) {
          tValue = 0;
        } else if (approximatelyGreaterThanOne(tValue)) {
          tValue = 1;
        }
        bool alreadyAdded = false;
        for (int idx2 = 0; idx2 < foundRoots; ++idx2) {
          if (approximatelyEqualT(target[idx2], tValue)) {
            alreadyAdded = true;
            break;
          }
        }
        if (!alreadyAdded) {
          foundRoots++;
          target.add(tValue);
        }
      }
    }
    return foundRoots;
  }

  /// Returns point on curve at T = [t].
  ui.Offset ptAtT(double t) {
    if (0 == t) {
      return ui.Offset(points[0], points[1]);
    }
    if (1 == t) {
      return ui.Offset(points[4], points[5]);
    }
    double one_t = 1 - t;
    double a = one_t * one_t;
    double b = 2 * one_t * t;
    double c = t * t;
    return ui.Offset(a * points[0] + b * points[2] + c * points[4],
        a * points[1] + b * points[3] + c * points[5]);
  }
}

/// Chops a non-monotonic quadratic curve, returns subdivisions and writes
/// result into [buffer].
void _chopQuadAtT(Float32List buffer, double t, Float32List curve1, Float32List curve2) {
  final double x0 = buffer[0];
  final double y0 = buffer[1];
  final double x1 = buffer[2];
  final double y1 = buffer[3];
  final double x2 = buffer[4];
  final double y2 = buffer[5];
  // Chop quad at t value by interpolating along p0-p1 and p1-p2.
  double p01x = x0 + (t * (x1 - x0));
  double p01y = y0 + (t * (y1 - y0));
  double p12x = x1 + (t * (x2 - x1));
  double p12y = y1 + (t * (y2 - y1));
  double cx = p01x + (t * (p12x - p01x));
  double cy = p01y + (t * (p12y - p01y));
  curve1[0] = buffer[0];
  curve1[1] = buffer[0];
  curve1[2] = p01x;
  curve1[3] = p01y;
  curve1[4] = cx;
  curve1[5] = cy;
  curve2[0] = cx;
  curve2[1] = cy;
  buffer[6] = p12x;
  buffer[7] = p12y;
  buffer[8] = x2;
  buffer[9] = y2;
}