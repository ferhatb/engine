// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// A Line represented by 2 endpoints as doubles.
class DLine {
  double x0, y0, x1, y1;

  DLine(this.x0, this.y0, this.x1, this.y1);

  DLine.offsets(ui.Offset start, ui.Offset end) :
        x0 = start.dx, y0 = start.dy, x1 = end.dx, y1 = end.dy;

  factory DLine.fromPoints(Float32List points) =>
      DLine(points[0], points[1], points[2], points[3]);

  DLine clone() => DLine(x0, y0, x1, y1);

  static const int kPointCount = 2;
  static const int kPointLast = kPointCount - 1;

  /// Checks if point is exactly at start or end of the line.
  double exactPoint(double x, double y) {
    // Do cheapest test first.
    if (x == x0 && y == y0) {
      return 0;
    }
    if (x == x1 && y == y1) {
      return 1;
    }
    return -1;
  }

  void offset(ui.Offset offset) {
    final double dx = offset.dx;
    final double dy = offset.dy;
    x0 += dx;
    y0 += dy;
    x1 += dx;
    y1 += dy;
  }

  // Given an end point return t for a horizontal line.
  static double exactPointH(double px, double py, double left, double right,
      double y) {
    if (py == y) {
      if (px == left) {
        return 0;
      }
      if (px == right) {
        return 1;
      }
    }
    return -1;
  }

  // Given a point return nearest t.
  static double nearPointH(double px, double py, double left, double right, double y) {
    if (!almostBequalUlps(py, y)) {
      return -1;
    }
    if (!almostBetweenUlps(left, px, right)) {
      return -1;
    }
    double t = (px - left) / (right - left);
    t = pinT(t);
    double realPtX = (1 - t) * left + t * right;
    double dist = math.sqrt(distanceSquared(px, py, realPtX, y));
    double tiniest = math.min(math.min(y, left), right);
    double largest = math.max(math.max(y, left), right);
    largest = math.max(largest, -tiniest);
    if (!almostEqualUlps(largest, largest + dist)) { // is the dist within ULPS tolerance?
      return -1;
    }
    return t;
  }

  static double exactPointV(double px, double py, double top, double bottom, double x) {
    if (px == x) {
      if (py == top) {
        return 0;
      }
      if (py == bottom) {
        return 1;
      }
    }
    return -1;
  }

  static double nearPointV(double px, double py, double top, double bottom, double x) {
    if (!almostBequalUlps(px, x)) {
      return -1;
    }
    if (!almostBetweenUlps(top, py, bottom)) {
    return -1;
    }
    double t = (py - top) / (bottom - top);
    t = pinT(t);
    assert(SPath.between(0, t, 1));
    double realPtY = (1 - t) * top + t * bottom;
    double dist = math.sqrt(distanceSquared(px, py, x, realPtY));
    double tiniest = math.min(math.min(x, top), bottom);
    double largest = math.max(math.max(x, top), bottom);
    largest = math.max(largest, -tiniest);
    if (!almostEqualUlps(largest, largest + dist)) { // is the dist within ULPS tolerance?
      return -1;
    }
    return t;
  }

  /// Set by nearPoint to indicate that distance compare to magnitude of
  /// vectors is negligible at float precision.
  bool unequal = false;

  // Returns T value for nearest point on line to [x],[y] or -1
  // if out to bounds.
  double nearPoint(double x, double y) {
    unequal = false;
    if (!almostBetweenUlps(x0, x, x1)
        || !almostBetweenUlps(y0, y, y1)) {
      return -1;
    }
    // Project a perpendicular ray from the point to the line; find the T on
    // the line.
    final double lenX = x1 - x0;
    final double lenY = y1 - y0;
    // See intersectRay.
    final double denom = lenX * lenX + lenY * lenY;
    final double ab0X = x - x0;
    final double ab0Y = y - y0;
    final double numer = lenX * ab0X + ab0Y * lenY;
    if (!SPath.between(0, numer, denom)) {
      return -1;
    }
    if (denom == 0) {
      return 0;
    }
    double t = numer / denom;
    // Calculate point at t.
    double one_t = 1 - t;
    double realX = t == 0 ? x0 : (t == 1 ? x1 : (one_t * x0 + t * x1));
    double realY = t == 0 ? y0 : (t == 1 ? y1 : (one_t * y0 + t * y1));
    // Calculate distance between intersection and point.
    double dist = math.sqrt(distanceSquared(realX, realY, x, y));
    // Find the ordinal in the original line with the largest unsigned exponent.
    double tiniest = math.min(math.min(math.min(x0, y0), x1), y1);
    double largest = math.max(math.max(math.max(x0, y0), x1), y1);
    largest = math.max(largest, -tiniest);
    // Check if distance is within ULPS tolerance.
    if (!almostEqualUlpsPin(largest, largest + dist)) {
      return -1;
    }
    unequal = !equalAsFloats(largest, largest + dist);
    t = pinT(t);
    assert(SPath.between(0, t, 1));
    return t;
  }

  double ptAtTx(double t) => t == 0 ? x0 : (t == 1 ? x1 : (x0 * (1 - t) + x1 * t));
  double ptAtTy(double t) => t == 0 ? y0 : (t == 1 ? y1 : (y0 * (1 - t) + y1 * t));
  ui.Offset ptAtT(double t) => ui.Offset(ptAtTx(t), ptAtTy(t));
  double xAt(int index) => index == 0 ? x0 : x1;
  double yAt(int index) => index == 0 ? y0 : y1;

  void setPoint(int pointIndex, double x, double y) {
    if (pointIndex == 0) {
      x0 = x;
      y0 = y;
    } else {
      x1 = x;
      y1 = y;
    }
  }
}
