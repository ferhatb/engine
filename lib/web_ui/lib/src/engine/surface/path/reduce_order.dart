// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
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
      return ReduceOrderResult.kPoint;
    }
    return ReduceOrderResult.kLine;
  }

  /// Reduces to quadratic or smaller.
  ///
  /// Check for identical points, looks for four points in a line. 3 points
  /// on a line doesn't simplify quadratic to a line.
  ///
  /// Returns [ReduceOrderResult] and writes result into [target].
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
      return _verticalOrHorizontalLineQuad(points, target);
    }
    int result = _checkLinearQuad(points, target);
    if (result != 0) {
      return ReduceOrderResult.kLine;
    }
    if (target != points) {
      for (int i = 0; i < (Quad.kMaxPoints * 2); i++) {
        target[i] = points[i];
      }
    }
    return ReduceOrderResult.kQuad;
  }

  /// Reduces conic curve to quadratic or smaller.
  static int conic(Float32List points, double weight, Float32List target) {
    int res = quad(points, target);
    if (res > ReduceOrderResult.kLine && weight == 1) {
      return ReduceOrderResult.kQuad;
    }
    return res == ReduceOrderResult.kQuad ? ReduceOrderResult.kConic : res;
  }

  /// Collapse quad into single point.
  static int _coincidentLine(Float32List points, Float32List reduction) {
    final double x = points[0];
    final double y = points[1];
    reduction[0] = reduction[2] = x;
    reduction[1] = reduction[3] = y;
    return ReduceOrderResult.kPoint;
  }

  static int _reduceLine(Float32List reduction) {
    return approximatelyEqual(reduction[0], reduction[1],
        reduction[2], reduction[3])
        ? ReduceOrderResult.kPoint : ReduceOrderResult.kLine;
  }

  static int _verticalOrHorizontalLineQuad(Float32List points,
      Float32List reduction) {
    reduction[0] = points[0];
    reduction[1] = points[1];
    reduction[2] = points[4];
    reduction[3] = points[5];
    return _reduceLine(reduction);
  }

  static int _checkLinearQuad(Float32List points, Float32List reduction) {
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

  /// check to see if it is a quadratic or a line
  static int _checkQuadratic(Float32List points, Float32List reduction) {
    double dx10 = points[2] - points[0];
    double dx23 = points[4] - points[6];
    double midX = points[0] + dx10 * 3 / 2;
    double sideAx = midX - points[6];
    double sideBx = dx23 * 3 / 2;
    if (approximatelyZero(sideAx) ? !approximatelyEqualT(sideAx, sideBx)
        : !almostEqualUlpsPin(sideAx, sideBx)) {
      return 0;
    }
    double dy10 = points[3] - points[1];
    double dy23 = points[5] - points[7];
    double midY = points[1] + dy10 * 3 / 2;
    double sideAy = midY - points[7];
    double sideBy = dy23 * 3 / 2;
    if (approximatelyZero(sideAy) ? !approximatelyEqualT(sideAy, sideBy)
        : !almostEqualUlpsPin(sideAy, sideBy)) {
      return 0;
    }
    reduction[0] = points[0];
    reduction[1] = points[1];
    reduction[2] = midX;
    reduction[3] = midY;
    reduction[4] = points[6];
    reduction[5] = points[7];
    return ReduceOrderResult.kQuad;
  }

  static int _verticalOrHorizontalLineCubic(Float32List points,
      Float32List reduction) {
    reduction[0] = points[0];
    reduction[1] = points[1];
    reduction[2] = points[6];
    reduction[3] = points[7];
    return _reduceLine(reduction);
  }

  static int _checkLinearCubic(Float32List points, Float32List reduction) {
    if (!Cubic.isLinear(points, 0, 3)) {
      return 0;
    }
    // four are colinear: return line formed by outside
    reduction[0] = points[0];
    reduction[1] = points[1];
    reduction[2] = points[6];
    reduction[3] = points[7];
    return _reduceLine(reduction);
  }

  /// Reduce cubic curve to a quadratic or smaller.
  ///
  /// look for identical points
  /// look for all four points in a line
  /// note that three points in a line doesn't simplify a cubic
  /// look for approximation with single quadratic
  /// save approximation with multiple quadratics in [fQuads] for later.
  static int _cubic(Float32List points, Float32List target,
      {bool allowQuadratics = true}) {
    int index;
    int minXIndex = 0;
    int minYIndex = 0;
    int maxXIndex = 0;
    int maxYIndex = 0;
    // Bit patterns that indicate minimumY is almost equal to point at index.
    int minXSet = 0;
    int minYSet = 0;
    for (int index = 2; index < 8; index += 2) {
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
    final double minX = points[minXIndex];
    final double minY = points[minYIndex + 1];
    for (index = 0; index < 4; ++index) {
        double cx = points[index * 2];
        double cy = points[index * 2 + 1];
        double denom = math.max(cx.abs(), math.max(cy.abs(),
          math.max(minX.abs(), minY.abs())));
        if (denom == 0) {
          minXSet |= 1 << index;
          minYSet |= 1 << index;
          continue;
        }
        double inv = 1 / denom;
        if (approximatelyEqualHalf(cx * inv, minX * inv)) {
            minXSet |= 1 << index;
        }
        if (approximatelyEqualHalf(cy * inv, minY * inv)) {
            minYSet |= 1 << index;
        }
    }
    if (minXSet == 0xF) {  // test for vertical line
        if (minYSet == 0xF) {  // return 1 if all four are coincident
            return _coincidentLine(points, target);
        }
        return _verticalOrHorizontalLineCubic(points, target);
    }
    if (minYSet == 0xF) {  // test for horizontal line
        return _verticalOrHorizontalLineCubic(points, target);
    }
    int result = _checkLinearCubic(points, target);
    if (result != 0) {
      return result;
    }
    if (allowQuadratics &&
        (result = _checkQuadratic(points, target)) != 0) {
      return result;
    }
    if (target != points) {
      for (int i = 0; i < 8; i++) {
        target[i] = points[i];
      }
    }
    return ReduceOrderResult.kCubic;
  }

  /// Reduce cubic curve to a quadratic or smaller.
  static int cubic(Float32List points, Float32List target) {
    if (approximatelyEqual(points[0], points[1], points[2], points[3])
        && approximatelyEqual(points[0], points[1], points[4], points[5])
        && approximatelyEqual(points[0], points[1], points[6], points[7])) {
      if (target != points) {
        target[0] = points[0];
        target[1] = points[1];
      }
      return ReduceOrderResult.kPoint;
    }
    return _cubic(points, target, allowQuadratics: true);
  }
}

abstract class ReduceOrderResult {
  static const int kPoint = SPathVerb.kMove;
  static const int kLine = SPathVerb.kLine;
  static const int kQuad = SPathVerb.kQuad;
  static const int kConic = SPathVerb.kConic;
  static const int kCubic = SPathVerb.kCubic;
}

enum _Quadratics {
  kNo_Quadratics,
  kAllow_Quadratics
}
