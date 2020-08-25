// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Quadratic curve utilities.
class Quad {
  final Float32List points;

  Quad(this.points);

  static const int kPointCount = 3;
  static const int kPointLast = kPointCount - 1;

  bool get linear => Quad.isLinear(points, 0, 2);

  double xAt(int index) => points[index * 2];

  double yAt(int index) => points[index * 2 + 1];

  void setPoint(int pointIndex, double x, double y) {
    points[pointIndex * 2] = x;
    points[pointIndex * 2 + 1] = y;
  }

  /// Checks if quadratic points collapse to a single point.
  bool collapsed() =>
      approximatelyEqualPoints(points[0], points[1], points[4], points[5]) &&
          approximatelyEqualPoints(points[0], points[1], points[2], points[3]);

  bool controlsInside() => controlsInsideQuad(points);

  Quad clone() => Quad(Float32List(kPointCount)..setAll(0, points));

  void offset(ui.Offset offset) {
    final double dx = offset.dx;
    final double dy = offset.dy;
    points[5] += dy;
    points[0] += dx;
    points[2] += dx;
    points[4] += dx;
    points[1] += dy;
    points[3] += dy;
  }

  /// Checks if control points are inside.
  static bool controlsInsideQuad(Float32List points) {
    double v01x = points[0] - points[2];
    double v01y = points[1] - points[3];
    double v02x = points[0] - points[4];
    double v02y = points[1] - points[5];
    double v12x = points[2] - points[4];
    double v12y = points[3] - points[5];
    double dot1 = v01x * v02x + v01y * v02y;
    double dot2 = v02x * v12x + v02y * v12y;
    return dot1 > 0 && dot2 > 0;
  }

  /// List of points other than at index [oddMan].
  Float32List otherPts(int oddMan) {
    Float32List result = Float32List(4);
    if (oddMan == 0) {
      result[0] = points[2];
      result[1] = points[3];
      result[2] = points[4];
      result[3] = points[5];
    } else if (oddMan == 1) {
      result[0] = points[0];
      result[1] = points[1];
      result[2] = points[4];
      result[3] = points[5];
    } else {
      result[0] = points[2];
      result[1] = points[3];
      result[2] = points[0];
      result[3] = points[1];
    }
    return result;
  }

  static bool isLinear(Float32List points, int startIndex, int endIndex) {
    final LineParameters lineParameters = LineParameters();
    lineParameters.quadEndPointsAt(points, startIndex, endIndex);
    lineParameters.normalize();
    double distance = lineParameters.controlPtDistanceQuad(points);
    double tiniest = math.min(
        math.min(math.min(math.min(math.min(points[0], points[1]),
            points[2]), points[3]), points[4]), points[5]);
    double largest = math.max(
        math.max(math.max(math.max(math.max(points[0], points[1]),
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
  static int addValidTs(List<double> source, int sourceCount,
      List<double> target) {
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

  /// Slope of curve at t.
  ui.Offset dxdyAtT(double t) {
    double a = t - 1;
    double b = 1 - 2 * t;
    double c = t;
    if (zeroOrOne(t)) {
      return ui.Offset(points[2] - points[0], points[3] - points[1]);
    }
    return ui.Offset(a * points[0] + b * points[2] + c * points[4],
        a * points[1] + b * points[3] + c * points[5]);
  }

  Quad subDivide(double t1, double t2) {
    Float32List result = Float32List(6);
    _chopQuadBetweenT(points, t1, t2, result);
    return Quad(result);
  }

  _HullIntersectResult hullIntersectsQuad(Quad q2) {
    bool linear = true;
    for (int oddMan = 0; oddMan < kPointCount; ++oddMan) {
      Float32List endPts = otherPts(oddMan);
      double origX = endPts[0];
      double origY = endPts[1];
      double adj = endPts[2] - origX;
      double opp = endPts[3] - origY;
      double sign = (yAt(oddMan) - origY) * adj - (xAt(oddMan) - origX) * opp;
      if (approximatelyZero(sign)) {
        continue;
      }
      linear = false;
      bool foundOutlier = false;
      for (int n = 0; n < kPointCount; ++n) {
        double test = (q2.yAt(n) - origY) * adj - (q2.xAt(n) - origX) * opp;
        if (test * sign > 0 && !preciselyZero(test)) {
          foundOutlier = true;
          break;
        }
      }
      if (!foundOutlier) {
        return _HullIntersectResult(false, linear);
      }
    }
    if (linear && !_matchesEnd(q2.points[0], q2.points[1]) &&
        !_matchesEnd(q2.points[4], q2.points[5])) {
      // if the end point of the opposite quad is inside the hull that is nearly a line,
      // then representing the quad as a line may cause the intersection to be missed.
      // Check to see if the endpoint is in the triangle.
      if (pointInTriangle(points, q2.points[0], q2.points[1]) ||
          pointInTriangle(points, q2.points[4], q2.points[5])) {
        linear = false;
      }
    }
    return _HullIntersectResult(true, linear);
  }

  _HullIntersectResult hullIntersectsConic(Conic conic) =>
      conic.hullIntersectsQuad(this);

  _HullIntersectResult hullIntersectsCubic(Cubic cubic) =>
      cubic.hullIntersects(points, kPointCount);

  /// Checks if point is an end point
  bool _matchesEnd(double testX, double testY) =>
      (testX == points[0] && testY == points[1]) ||
          (testX == points[4] && testY == points[5]);
}

/// Checks if a point is inside a triangle defined by [points].
///
/// A simple way is to look at angle from point to all 3 corners. If
/// sum is 360, this point is inside the triangle, however this is slow.
///
/// This method uses Barycentric coordinates to check if point is inside. See
/// "Determining location with respect to a triangle"
/// https://en.wikipedia.org/wiki/Barycentric_coordinate_system
bool pointInTriangle(Float32List points, double testX, double testY) {
  double v0x = points[4] - points[0];
  double v0y = points[5] - points[1];
  double v1x = points[2] - points[0];
  double v1y = points[3] - points[1];
  double v2x = testX - points[0];
  double v2y = testY - points[1];
  double dot00 = v0x * v0x + v0y * v0y;
  double dot01 = v0x * v1x + v0y * v1y;
  double dot02 = v0x * v2x + v0y * v2y;
  double dot11 = v1x * v1x + v1y * v1y;
  double dot12 = v1x * v2x + v1y * v2y;
  // Compute barycentric coordinates.
  double denom = dot00 * dot11 - dot01 * dot01;
  double u = dot11 * dot02 - dot01 * dot12;
  double v = dot00 * dot12 - dot01 * dot02;
  // Check if point is in triangle.
  if (denom >= 0) {
    return u >= 0 && v >= 0 && u + v < denom;
  }
  return u <= 0 && v <= 0 && u + v > denom;
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