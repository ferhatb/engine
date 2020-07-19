// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of engine;

/// Calculates piecewise reduction of curves.
///
/// The reduction result is returned as a verb:
///   - If reduced to point : moveTo
///   - If reduced to line : lineTo
///   - If reduced to quads : quadTo.
class ReduceOrder {
  /// If line end points are the same reduces input to a point.
  static int reduceLine(Float32List points) {
    final double startX = points[0];
    final double startY = points[1];
    if (_nearlyEqual(startX, points[2]) && _nearlyEqual(startY, points[3])) {
      points[2] = startX;
      points[3] = startY;
      return _ReduceOrderResult.kPoint;
    }
    return _ReduceOrderResult.kLine;
  }

  /// Reduces to quadratic or smaller.
  ///
  /// Check for identical points, looks for four points in a line. 3 points
  /// on a line doesn't simplify quadratic to a line.
  ///
  /// Returns [_ReduceOrderResult] and writes result into [target].
  static int quad(Float32List points, Float32List target) {
    int index;
    int minXIndex = 0;
    int minYIndex = 0;
    int maxXIndex = 0;
    int maxYIndex = 0;
    // Bit patterns that indicate minimumY is almost equal to point at index.
    int minXSet = 0;
    int minYSet = 0;
    for (int index = 2; index < 6; index += 2) {
      if (points[index] < points[minXIndex]) {
        minXIndex = index;
      }
      if (points[index + 1] < points[minYIndex + 1]) {
        minYIndex = index;
      }
      if (points[index] > points[maxXIndex]) {
        maxXIndex = index;
      }
      if (points[index + 1] > points[maxYIndex + 1]) {
        maxYIndex = index;
      }
    }
    for (index = 0; index < 3; index++) {
      if (almostEqualUlps(points[index * 2], points[minXIndex])) {
        minXSet |= 1 << index;
      }
      if (almostEqualUlps(points[index * 2 + 1], points[minYIndex + 1])) {
        minYSet |= 1 << index;
      }
    }
    if ((minXSet & 0x5) == 0x5 && (minYSet & 0x5) == 0x5) {
      // Quad starts and ends at the same place.
      return _coincidentLine(points, target);
    }
    if (minXSet == 0x7 || minYSet == 0x7) {
      // A vertical line, horizontal line or point.
      return _verticalOrHorizontalLine(points, target);
    }
    int result = _checkLinear(points, target);
    if (result != 0) {
      return _ReduceOrderResult.kLine;
    }
    if (target != points) {
      for (int i = 0; i < 8; i++) {
        target[i] = points[i];
      }
    }
    return _ReduceOrderResult.kQuad;
  }

  // Collapse quad into single point.
  static int _coincidentLine(Float32List points, Float32List reduction) {
    final double x = points[0];
    final double y = points[1];
    reduction[0] = reduction[2] = x;
    reduction[1] = reduction[3] = y;
    return _ReduceOrderResult.kPoint;
  }

  static int _reduceLine(Float32List reduction) {
    return approximatelyEqual(reduction[0], reduction[1],
        reduction[2], reduction[3])
        ? _ReduceOrderResult.kPoint : _ReduceOrderResult.kLine;
  }

  static int _verticalOrHorizontalLine(Float32List points,
      Float32List reduction) {
    reduction[0] = points[0];
    reduction[1] = points[1];
    reduction[2] = points[4];
    reduction[3] = points[5];
    return _reduceLine(reduction);
  }

  static int _checkLinear(Float32List points, Float32List reduction) {
    if (!Quad.isLinear(points, 0, 2)) {
      return 0;
    }
    // four are colinear: return line formed by outside
    reduction[0] = points[0];
    reduction[1] = points[1];
    reduction[2] = points[4];
    reduction[3] = points[5];
    return _reduceLine(reduction);
  }

  static int cubic(Float32List points) {
    throw UnimplementedError();
  }
}

/// Quadratic curve utilities.
class Quad {
  final Float32List points;
  Quad(this.points);

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
    if (almostDequalUlps(s[0], s[1])) {
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
}

abstract class _ReduceOrderResult {
  static const int kPoint = SPathVerb.kMove;
  static const int kLine = SPathVerb.kLine;
  static const int kQuad = SPathVerb.kQuad;
}

enum _Quadratics {
  kNo_Quadratics,
  kAllow_Quadratics
}
