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
