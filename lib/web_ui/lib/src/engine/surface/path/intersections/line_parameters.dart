// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Parameterized line of the form :  ax + by + c = 0
///
/// Line is normalized when length is 1 (a^2 + b^2 == 1).
///
/// The distance to the line for (x, y) is d(x,y) = ax + by + c
/// To get true distance either call [normalize] or divide distance by
/// sqrt([normalSquared].
///
/// This class contains several helper methods to read quadratic and cubic
/// curve points and converts them to parametric form.
///
/// Sources:
/// Thomas W. Sederberg, Tomoyuki Nishita:  Curve intersection using Bezier
/// clipping. Computer Aided Design 1990;22(9):538–49.
/// https://github.com/google/skia/blob/master/src/pathops/SkLineParameters.h
class LineParameters {
  double _a = 0;
  double _b = 0;
  double _c = 0;

  /// Create line from cubic curve end points.
  bool cubicEndPoints(Float32List points) {
    int endIndex = 1;
    _readPoints(points, 0, endIndex);
    if (dy != 0) {
      return true;
    }
    if (dx == 0) {
      _readPoints(points, 0, ++endIndex);
      assert(endIndex == 2);
      if (dy != 0) {
          return true;
      }
      if (dx == 0) {
        // Line.
        _readPoints(points, 0, ++endIndex);
        assert(endIndex == 3);
        return false;
      }
    }
    if (dx < 0) {
      // Only worry about y bias when breaking cw/ccw tie.
      return true;
    }
    // If Cubic tangent is on x axis, look at next control point to break tie
    // control point may be approximate, so it must move significantly to
    // account for error.
    if (!almostEqualUlps(points[1], points[(++endIndex) * 2 + 1])) {
      if (points[1] > points[endIndex * 2 + 1]) {
        // Push it from 0 to slightly negative (y returns -a).
        _a = kDblEpsilon;
      }
      return true;
    }
    if (endIndex == 3) {
      return true;
    }
    assert(endIndex == 2);
    if (points[1] > points[7]) {
      // Push it from 0 to slightly negative (y() returns -a).
      _a = kDblEpsilon;
    }
    return true;
  }

  void cubicEndPointsAt(Float32List points, int startIndex, int endIndex) {
    _readPoints(points, startIndex, endIndex);
  }

  void quadEndPointsAt(Float32List points, int startIndex, int endIndex) {
    _readPoints(points, startIndex, endIndex);
  }

  void _readPoints(Float32List points, int startIndex, int endIndex) {
    startIndex *= 2;
    endIndex *= 2;
    final double startX = points[startIndex];
    final double startY = points[startIndex + 1];
    final double endX = points[endIndex];
    final double endY = points[endIndex + 1];
    _a = startY - endY;
    _b = endX - startX;
    _c = startX * endY - endX * startY;
  }

  /// Returns distance from cubic end point to line.
  double cubicPart(Float32List points) {
    cubicEndPoints(points);
    if ((points[0] == points[2] && points[1] == points[3])
        || _pointNearRay(points[4], points[5], points[0], points[1],
            points[2], points[3])) {
      // Return distance from end point.
      return pointDistance(points[6], points[7]);
    }
    // Return distance from second control point.
    return pointDistance(points[4], points[5]);
  }

  /// Create from line end points.
  void lineEndPoints(Float32List points) {
    _a = points[1] - points[3];
    _b = points[2] - points[0];
    _c = points[0] * points[3] - points[2] * points[1];
  }

  /// Create from line end points.
  void lineEndOffsets(ui.Offset p0, ui.Offset p1) {
    _a = p0.dy - p1.dy;
    _b = p1.dx - p0.dx;
    _c = p0.dx * p1.dy - p1.dx * p0.dy;
  }

  /// Create from quadratic curve end points.
  bool quadEndPoints(Float32List points) {
    _readPoints(points, 0, 1);
    if (dy != 0) {
      return true;
    }
    if (dx == 0) {
      _readPoints(points, 0, 2);
      return false;
    }
    if (dx < 0) {
      // Only worry about y bias when breaking cw/ccw tie.
      return true;
    }
    if (points[1] > points[5]) {
      _a = kDblEpsilon;
    }
    return true;
  }

  /// Returns distance from quadratic end point to line.
  double quadPart(Float32List points) {
    quadEndPoints(points);
    return pointDistance(points[4], points[5]);
  }

  /// Returns square of normal vector length.
  double get normalSquared {
    return _a * _a + _b * _b;
  }

  /// Normalizes line so that a^2 + b^2 = 1.
  bool normalize() {
    double normal = math.sqrt(normalSquared);
    if (approximatelyZero(normal)) {
      _a = _b = _c = 0;
      return false;
    }
    double reciprocal = 1 / normal;
    _a *= reciprocal;
    _b *= reciprocal;
    _c *= reciprocal;
    return true;
  }

  /// Computes vertical distance from cubic points to line.
  void cubicDistanceY(Float32List points, Float32List distance) {
    double oneThird = 1 / 3.0;
    for (int index = 0; index < 4; ++index) {
      distance[index * 2] = index * oneThird;
      distance[index * 2 + 1] = _a * points[index * 2] + _b * points[index * 2 + 1] + _c;
    }
  }

  /// Computes vertical distance from quad points to line.
  void quadDistanceY(Float32List points, Float32List distance) {
    double oneHalf = 1 / 2.0;
    for (int index = 0; index < 3; ++index) {
      distance[index * 2] = index * oneHalf;
      distance[index * 2 + 1] = _a * points[index * 2] + _b * points[index * 2 + 1] + _c;
    }
  }

  /// Returns distance from control point to line.
  double controlPtDistance(Float32List points, int index) {
    assert(index == 1 || index == 2);
    return _a * points[index * 2] + _b * points[index * 2 + 1] + _c;
  }

  /// Returns distance from quad control point to line.
  double controlPtDistanceQuad(Float32List points) =>
    controlPtDistance(points, 1);

  /// Returns distance from arbitrary point to line.
  double pointDistance(double x, double y) {
    return _a * x + _b * y + _c;
  }

  /// Horizontal range.
  double get dx => _b;

  /// Vertical range.
  double get dy => _a;
}

/// Returns true if point [x],[y] is nearly on line
/// [startX],[startY] - [endX],[endY].
bool _pointNearRay(double x, double y,
    double startX, double startY, double endX, double endY) {
  // Project a perpendicular ray from the point to the line; find the T on the line
  final double dx = endX - startX;
  final double dy = endY - startY;
  double denom = dx * dx + dy * dy;
  final double ab0x = x - startX;
  final double ab0y = y - startY;
  double numer = dx * ab0x + ab0y * dy;
  double t = numer / denom;

  final double realX = _interpolate(startX, endX, t);
  final double realY = _interpolate(startY, endY, t);
  final double lenX = realX - x;
  final double lenY = realY - y;
  double dist = math.sqrt(lenX * lenX + lenY * lenY);
  // Find the ordinal in the original line with the largest unsigned exponent
  double tiniest = math.min(math.min(math.min(startX, startY), endX), endY);
  double largest = math.max(math.max(math.max(startX, startY), endX), endY);
  largest = math.max(largest, -tiniest);
  return roughlyEqualUlps(largest, largest + dist); // is the dist within ULPS tolerance?
}
