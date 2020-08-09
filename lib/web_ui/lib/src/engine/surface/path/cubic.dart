// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Cubic bezier curve using double precicion.
class Cubic {
  Cubic(this.p0x, this.p0y, this.p1x, this.p1y, this.p2x, this.p2y,
      this.p3x, this.p3y);

  double p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y;
  static const int kPointCount = 4;
  static const int kPointLast = kPointCount - 1;

  factory Cubic.fromPoints(Float32List points) {
    return Cubic(points[0], points[1], points[2], points[3], points[4],
        points[5], points[6], points[7]);
  }

  Float32List toPoints() {
    final Float32List points = Float32List(8);
    points[0] = p0x;
    points[1] = p0y;
    points[2] = p1x;
    points[3] = p1y;
    points[4] = p2x;
    points[5] = p2y;
    points[6] = p3x;
    points[7] = p3y;
    return points;
  }

  /// Checks if cubic points collapse to a point.
  bool collapsed() => approximatelyEqualPoints(p0x, p0y, p3x, p3y) &&
      approximatelyEqualPoints(p0x, p0y, p1x, p1y) &&
      approximatelyEqualPoints(p0x, p0y, p2x, p2y);

  /// Checks if control points are inside.
  bool controlsInside() {
    double v01x = p0x - p1x;
    double v01y = p0y - p1y;
    double v02x = p0x - p2x;
    double v02y = p0y - p2y;
    double v03x = p0x - p3x;
    double v03y = p0y - p3y;
    double v13x = p1x - p3x;
    double v13y = p1y - p3y;
    double v23x = p2x - p3x;
    double v23y = p2y - p3y;
    double dot1 = v03x * v01x + v03y * v01y;
    double dot2 = v03x * v02x + v03y * v02y;
    double dot3 = v03x * v13x + v03y * v13y;
    double dot4 = v03x * v23x + v03y * v23y;
    return dot1 > 0 && dot2 > 0 && dot3 > 0 && dot4 > 0;
  }

  /// Returns 3 points other than [oddMan] where oddMan == 0 or 1 for start
  /// or end point.
  Float32List otherPts(int oddMan) {
    Float32List result = Float32List(6);
    if (oddMan == 0) {
      result[0] = p1x;
      result[1] = p1y;
      result[2] = p2x;
      result[3] = p2y;
      result[4] = p3x;
      result[5] = p3y;
    } else {
      result[0] = p0x;
      result[1] = p0y;
      result[2] = p1x;
      result[3] = p1y;
      result[4] = p2x;
      result[5] = p2y;
    }
    return result;
  }

  Cubic subDivide(double t1, double t2) {
    if (t1 == 0 || t2 == 1) {
      if (t1 == 0 && t2 == 1) {
        return this;
      }
      _CubicPair pair = chopAt(t1 == 0 ? t2 : t1);
      return t1 == 0 ? pair.first : pair.second;
    }
    if (t1 < t2) {
      return chopAt(t1).second.chopAt(t2).first;
    } else {
      return chopAt(t2).second.chopAt(t1).first;
    }
  }

  /// Cubic point x at curve point [index].
  double xAt(int index) => index == 0 ? p0x : (index == 1 ? p1x : index == 2 ? p2x : p3x);
  double yAt(int index) => index == 0 ? p0y : (index == 1 ? p1y : index == 2 ? p2y : p3y);
  void setXAt(int index, double x) {
    if (index == 0) {
      p0x = x;
    } else if (index == 1) {
      p1x = x;
    } else if (index == 2) {
      p2x = x;
    } else {
      p3x = x;
    }
  }

  void setYAt(int index, double y) {
    if (index == 0) {
      p0y = y;
    } else if (index == 1) {
      p1y = y;
    } else if (index == 2) {
      p2y = y;
    } else {
      p3y = y;
    }
  }

  bool get isFinite => p0x.isFinite && p0y.isFinite && p1x.isFinite &&
      p1y.isFinite && p2x.isFinite && p2y.isFinite && p3x.isFinite &&
      p3y.isFinite;

  _CubicPair chopAt(double t) {
    assert(t > 0 && t < 1);
    // If startT == 0 chop at end point and return curve.
    final double ab1x = _interpolate(p0x, p1x, t);
    final double ab1y = _interpolate(p0y, p1y, t);
    final double bc1x = _interpolate(p1x, p2x, t);
    final double bc1y = _interpolate(p1y, p2y, t);
    final double cd1x = _interpolate(p2x, p3x, t);
    final double cd1y = _interpolate(p2y, p3y, t);
    final double abc1x = _interpolate(ab1x, bc1x, t);
    final double abc1y = _interpolate(ab1y, bc1y, t);
    final double bcd1x = _interpolate(bc1x, cd1x, t);
    final double bcd1y = _interpolate(bc1y, cd1y, t);
    final double abcd1x = _interpolate(abc1x, bcd1x, t);
    final double abcd1y = _interpolate(abc1y, bcd1y, t);

    Cubic left = Cubic(p0x, p0y, ab1x, ab1y, abc1x, abc1y, abcd1x, abcd1y);
    Cubic right = Cubic(abcd1x, abcd1y, bcd1x, bcd1y, cd1x, cd1y, p3x, p3y);
    return _CubicPair(left, right);
  }

  static _QuadRoots findExtrema(double a, double b, double c, double d) {
    // A,B,C scaled by 1/3 to simplify
    final double A = d - a + 3 * (b - c);
    final double B = 2 * (a - b - b + c);
    final double C = b - a;
    return _QuadRoots()..findRoots(A, B, C);
  }

  /// True if curve is monotonically increasing or decreasing in x.
  bool monotonicInX() => preciselyBetween(p0x, p1x, p3x)
      && preciselyBetween(p0x, p2x, p3x);

  /// True if curve is monotonically increasing or decreasing in y.
  bool monotonicInY() => preciselyBetween(p0y, p1y, p3y)
      && preciselyBetween(p0y, p2y, p3y);

  /// Breaks up the curve into simpler cubics that have derivates at t within
  /// numerical precision required for intersection and ordering.
  List<double> complexBreak() {
    if (monotonicInX() && monotonicInY()) {
      // No need to split curve since it is monotonic on both axis.
      return const [];
    }
    final Float32List points = toPoints();
    CubicClassifier classifier = CubicClassifier.classify(points);
    final int cubicType = classifier.cubicType;
    final double t0 = classifier.t0;
    final double t1 = classifier.t1;
    final double s0 = classifier.s0;
    final double s1 = classifier.s0;
    if (cubicType == CubicType.kLoop) {
      if (roughlyBetween(0, t0, s0) && roughlyBetween(0, t1, s1)) {
        final double t0prime = (t0 * s1 + t1 * s0) / (2 * s0 * s1);
        return t0prime > 0 && t0prime < 1 ? [t0prime] : const [];
      }
    }
    if (cubicType == CubicType.kQuadratic || cubicType == CubicType.kLineOrPoint) {
      return const [];
    }
    // loop, serpentine, local cusp or cusp at infinity.
    List<double> inflectionTs = [];
    int infTCount = findInflections(inflectionTs);
    List<double> maxCurvature = [];
    int roots = findMaxCurvature(maxCurvature);

    if (infTCount == 2) {
      for (int index = 0; index < roots; ++index) {
        if (SPath.between(inflectionTs[0], maxCurvature[index], inflectionTs[1])) {
          double t0 = maxCurvature[index];
          return (t0 > 0 && t0 < 1) ? [t0] : const[];
        }
      }
    } else {
      double precision = calcPrecision() * 2;
      List<double> t = [];
      for (int index = 0; index < roots; ++index) {
        double testT = maxCurvature[index];
        if (0 >= testT || testT >= 1) {
          continue;
        }
        // don't call dxdyAtT since we want (0,0) results
        double dPtx = derivativeAtT(p0x, p1x, p2x, p3x, testT);
        double dPty = derivativeAtT(p0y, p1y, p2y, p3y, testT);
        double dPtLen = math.sqrt(_lengthSquared(dPtx, dPty));

        if (dPtLen < precision) {
          t.add(testT);
        }
      }
      if (t.isEmpty && infTCount == 1) {
        double inflT = inflectionTs[0];
        if (inflT > 0 && inflT < 1) {
          t.add(inflT);
        }
      }
      return t;
    }
    return const [];
  }

  static const double gPrecisionUnit = 256;

  static bool isLinear(Float32List points, int startIndex, int endIndex) {
    if (approximatelyEqual(points[0], points[1], points[6], points[7])) {
      return Quad.isLinear(points, 0, 2);
    }
    final LineParameters lineParameters = LineParameters();
    lineParameters.cubicEndPointsAt(points, startIndex, endIndex);
    lineParameters.normalize();
    double tiniest = math.min(math.min(math.min(math.min(math.min(points[0], points[1]),
        points[2]), points[3]), points[4]), math.min(points[5], math.min(points[6], points[7])));
    double largest = math.max(math.max(math.max(math.max(math.max(points[0], points[1]),
        points[2]), points[3]), points[4]), math.max(points[5], math.max(points[6], points[7])));
    largest = math.max(largest, -tiniest);
    double distance = lineParameters.controlPtDistance(points, 1);
    if (!approximatelyZeroWhenComparedTo(distance, largest)) {
      return false;
    }
    distance = lineParameters.controlPtDistance(points, 2);
    return approximatelyZeroWhenComparedTo(distance, largest);
  }

  /// Get the rough scale of the cubic.
  ///
  /// Used to determine if curvature is extreme
  double calcPrecision() =>
      (math.sqrt(_lengthSquared(p1x - p0x, p1y - p0y))
          + math.sqrt(_lengthSquared(p2x - p1x, p2y - p1y))
          + math.sqrt(_lengthSquared(p3x - p2x, p3y - p2y))) / gPrecisionUnit;

  int findInflections(List<double> target) {
    final double ax = p1x - p0x;
    final double ay = p1y - p0y;
    final double bx = p2x - 2 * p1x + p0x;
    final double by = p2y - 2 * p1y + p0y;
    final double cx = p3x + 3 * (p1x - p2x) - p0x;
    final double cy = p3y + 3 * (p1y - p2y) - p0y;
    return Quad.rootsValidT(bx * cy - by * cx, ax * cy - ay * cx, ax * by - ay * bx, target);
  }

  /// Looking for F' dot F'' == 0
  ///
  /// A = b - a
  /// B = c - 2b + a
  /// C = d - 3c + 3b - a
  ///
  /// F' = 3Ct^2 + 6Bt + 3A
  /// F'' = 6Ct + 6B
  ///
  /// F' dot F'' -> CCt^3 + 3BCt^2 + (2BB + CA)t + AB
  int findMaxCurvature(List<double> curvature) {
    final double ax = p1x - p0x;
    final double ay = p1y - p0y;
    final double bx = p2x - 2 * p1x + p0x;
    final double by = p2y - 2 * p1y + p0y;
    final double cx = p3x + 3 * (p1x - p2x) - p0x;
    final double cy = p3y + 3 * (p1y - p2y) - p0y;
    double coeff0x = cx * cx;
    double coeff1x = 3 * bx * cx;
    double coeff2x = 2 * bx * bx + cx * ax;
    double coeff3x = ax * bx;
    double coeff0y = cy * cy;
    double coeff1y = 3 * by * cy;
    double coeff2y = 2 * by * by + cy * ay;
    double coeff3y = ay * by;
    return rootsValidT(coeff0x + coeff0y, coeff1x + coeff1y,
        coeff2x + coeff2y, coeff3x + coeff3y, curvature);
  }

  /// Returns valid roots for cubic.
  ///
  /// Numeric Solutions, 5.6.
  static int rootsValidT(double A, double B, double C, double D, List<double> t) {
    List<double> s = [];
    int realRoots = rootsReal(A, B, C, D, s);
    int foundRoots = Quad.addValidTs(s, realRoots, t);
    // For roots in the range -0.00005..0 , make sure t=0 is in result set.
    // For roots in the range 1..1.00005 , make sure t=1 is in result set.
    for (int index = 0; index < realRoots; ++index) {
      double tValue = s[index];
      if (!approximatelyOneOrLess(tValue) && SPath.between(1, tValue, 1.00005)) {
        bool isValid = true;
        for (int idx2 = 0; idx2 < foundRoots; ++idx2) {
          if (approximatelyEqualT(t[idx2], 1)) {
            isValid = false;
            break;
          }
        }
        if (isValid) {
          assert(foundRoots < 3);
          foundRoots++;
          t.add(1);
        }
      } else if (!approximatelyZeroOrMore(tValue) && SPath.between(-0.00005, tValue, 0)) {
        bool isValid = true;
        for (int idx2 = 0; idx2 < foundRoots; ++idx2) {
          if (approximatelyEqualT(t[idx2], 0)) {
            isValid = false;
          }
        }
        if (isValid) {
          assert(foundRoots < 3);
          foundRoots++;
          t.add(0);
        }
      }
    }
    return foundRoots;
  }

  // from http://www.cs.sunysb.edu/~qin/courses/geometry/4.pdf
  // c(t)  = a(1-t)³ + 3bt(1-t)² + 3c(1-t)² + dt³
  // c'(t) = -3a(1-t)² + 3b((1-t)² - 2t(1-t)) + 3c(2t(1-t) - t²) + 3dt²
  //       = 3(b-a)(1-t)² + 6(c-b)t(1-t) + 3(d-c)t²
  static double derivativeAtT(double a, double b, double c, double d, double t) {
    final double one_t = 1 - t;
    return 3 * ((b - a) * one_t * one_t + 2 * (c - b) * t * one_t + (d - c) * t * t);
  }

  /// Returns real roots of cubic.
  static int rootsReal(double A, double B, double C, double D, List<double> target) {
    if (approximatelyZero(A)
        && approximatelyZeroWhenComparedTo(A, B)
        && approximatelyZeroWhenComparedTo(A, C)
        && approximatelyZeroWhenComparedTo(A, D)) {  // we're just a quadratic
      // Simply a quadratic.
      return Quad.rootsReal(B, C, D, target);
    }
    if (approximatelyZeroWhenComparedTo(D, A)
        && approximatelyZeroWhenComparedTo(D, B)
        && approximatelyZeroWhenComparedTo(D, C)) {
      // One of the roots is zero.
      int count = Quad.rootsReal(A, B, C, target);
      for (int i = 0; i < count; ++i) {
        if (approximatelyZero(target[i])) {
          return count;
        }
      }
      count++;
      target.add(0);
      return count;
    }
    if (approximatelyZero(A + B + C + D)) {
      // 1 is one root.
      int count = Quad.rootsReal(A, A + B, -D, target);
      for (int i = 0; i < count; ++i) {
        if (almostDequalUlps(target[i], 1)) {
          return count;
        }
      }
      count++;
      target.add(1);
      return count;
    }
    final double invA = 1 / A;
    double a = B * invA;
    double b = C * invA;
    double c = D * invA;

    double a2 = a * a;
    double Q = (a2 - b * 3) / 9;
    double R = (2 * a2 * a - 9 * a * b + 27 * c) / 54;
    double R2 = R * R;
    double Q3 = Q * Q * Q;
    double R2MinusQ3 = R2 - Q3;
    double adiv3 = a / 3;
    double r;
    if (R2MinusQ3 < 0) {   // we have 3 real roots
      // the divide/root can, due to finite precisions, be slightly outside of -1...1
      double theta = math.acos((R / math.sqrt(Q3)).clamp(-1.0, 1.0));
      double neg2RootQ = -2 * math.sqrt(Q);

      r = neg2RootQ * math.cos(theta / 3) - adiv3;
      target.add(r);

      r = neg2RootQ * math.cos((theta + 2 * math.pi) / 3) - adiv3;
      if (!almostDequalUlps(target[0], r)) {
        target.add(r);
      }
      r = neg2RootQ * math.cos((theta - 2 * math.pi) / 3) - adiv3;
      if (!almostDequalUlps(target[0], r) && (target.length == 1
          || !almostDequalUlps(target[1], r))) {
        target.add(r);
      }
    } else {  // we have 1 real root
      double sqrtR2MinusQ3 = math.sqrt(R2MinusQ3);
      double A = R.abs() + sqrtR2MinusQ3;
      A = cubeRoot(A);
      if (R > 0) {
        A = -A;
      }
      if (A != 0) {
        A += Q / A;
      }
      r = A - adiv3;
      target.add(r);
      if (almostDequalUlps(R2, Q3)) {
        r = -A / 2 - adiv3;
        if (!almostDequalUlps(target[0], r)) {
          target.add(r);
        }
      }
    }
    return target.length;
  }

  /// Point on curve at [t].
  ui.Offset ptAtT(double t) {
    if (0 == t) {
      return ui.Offset(p0x, p0y);
    }
    if (1 == t) {
      return ui.Offset(p3x, p3y);
    }
    // c(T) = p0 * (1-t)(1-t)(1-t) + p1 * 3(1-t)(1-t)t + p2 * 3(1-t)t t + p3*t*t*t.
    double one_t = 1 - t;
    double one_tsq = one_t * one_t;
    double a = one_tsq * one_t;
    double b = 3 * one_tsq * t;
    double tsq = t * t;
    double c = 3 * one_tsq * tsq;
    double d = tsq * t;
    return ui.Offset(a * p0x + b * p1x + c * p2x + d * p3x,
        a * p0y + b * p1y + c * p2y + d * p3y);
  }

  static const int kXAxis = 0;
  static const int kYAxis = 0;

  int searchRoots(List<double> extremeTs, int extrema,
      double axisIntercept, int xAxis, List<double> validRoots) {
    extrema += findInflections(extremeTs);
    extremeTs.add(0);
    extrema++;
    extremeTs.add(1);
    assert(extrema < 6);
    extremeTs.sort();
    int validCount = 0;
    for (int index = 0; index < extrema; ) {
      double min = extremeTs[index];
      double max = extremeTs[++index];
      if (min == max) {
        continue;
      }
      double newT = binarySearch(min, max, axisIntercept, xAxis);
      if (newT >= 0) {
        if (validCount >= 3) {
          return 0;
        }
        validRoots[validCount++] = newT;
      }
    }
    return validCount;
  }

  // give up when changing t no longer moves point
  // also, copy point rather than recompute it when it does change
  double binarySearch(double min, double max, double axisIntercept,
      int xAxis) {
    double t = (min + max) / 2;
    double step = (t - min) / 2;
    ui.Offset cubicAtT = ptAtT(t);
    double calcPos = xAxis == kXAxis ? cubicAtT.dx : cubicAtT.dy;
    double calcDist = calcPos - axisIntercept;
    do {
      double priorT = math.max(min, t - step);
      ui.Offset lessPt = ptAtT(priorT);
      if (approximatelyEqualHalf(lessPt.dx, cubicAtT.dx)
          && approximatelyEqualHalf(lessPt.dy, cubicAtT.dy)) {
        return -1;  // binary search found no point at this axis intercept
      }
      double lessDist = (xAxis == kXAxis ? lessPt.dx : lessPt.dy) - axisIntercept;
      double lastStep = step;
      step /= 2;
      if (calcDist > 0 ? calcDist > lessDist : calcDist < lessDist) {
        t = priorT;
      } else {
        double nextT = t + lastStep;
        if (nextT > max) {
          return -1;
        }
        ui.Offset morePt = ptAtT(nextT);
        if (approximatelyEqualHalf(morePt.dx, cubicAtT.dx)
            && approximatelyEqualHalf(morePt.dy, cubicAtT.dy)) {
          return -1;  // binary search found no point at this axis intercept
        }
        double moreDist = xAxis == kXAxis ? morePt.dx : morePt.dy - axisIntercept;
        if (calcDist > 0 ? calcDist <= moreDist : calcDist >= moreDist) {
          continue;
        }
        t = nextT;
      }
      ui.Offset testAtT = ptAtT(t);
      cubicAtT = testAtT;
      calcPos = xAxis == kXAxis ? cubicAtT.dx : cubicAtT.dy;
      calcDist = calcPos - axisIntercept;
    } while (!approximatelyEqualT(calcPos, axisIntercept));
    return t;
  }

  ui.Offset dxdyAtT(double t) {
    double x = derivativeAtT(p0x, p1x, p2x, p3x, t);
    double y = derivativeAtT(p0y, p1y, p2y, p3y, t);
    ui.Offset result = ui.Offset(x, y);
    if (x == 0 && y == 0) {
      if (t == 0) {
        result = ui.Offset(p2x - p0x, p2y - p0y);
      } else if (t == 1) {
        result = ui.Offset(p3x - p1x, p3y - p1y);
      }
      if (result.dx == 0 && result.dy == 0 && zeroOrOne(t)) {
        result = ui.Offset(p3x - p0x, p3y - p0y);
      }
    }
    return result;
  }

  /// Computes if hull intersects this curve.
  ///
  /// Do a quick reject by rotating all points relative to a line formed by
  /// a pair of one cubic's points. If the 2nd cubic's points
  /// are on the line or on the opposite side from the 1st cubic's 'odd man', the
  /// curves at most intersect at the endpoints.
  /// if returning true, check contains true if cubic's hull collapsed, making the cubic linear
  ///  if returning false, check contains true if the the cubic pair have only the end point in common
  _HullIntersectResult hullIntersects(Float32List pts, int ptCount) {
    bool linear = true;
    List<int> hullOrder = [];
    int hullCount = convexHull(hullOrder);
    int end1 = hullOrder[0];
    int hullIndex = 0;
    double endPt0x = xAt(end1);
    double endPt0y = yAt(end1);
    do {
      hullIndex = (hullIndex + 1) % hullCount;
      int end2 = hullOrder[hullIndex];
      double endPt1x = xAt(end2);
      double endPt1y = yAt(end2);
      double origX = endPt0x;
      double origY = endPt0y;
      double adj = endPt1x - origX;
      double opp = endPt1y - origY;
      int oddManMask = otherTwo(end1, end2);
      int oddMan = end1 ^ oddManMask;
      double sign = (yAt(oddMan) - origY) * adj - (xAt(oddMan) - origX) * opp;
      int oddMan2 = end2 ^ oddManMask;
      double sign2 = (yAt(oddMan2) - origY) * adj - (xAt(oddMan2) - origX) * opp;
      if (sign * sign2 < 0) {
        continue;
      }
      if (approximatelyZero(sign)) {
        sign = sign2;
        if (approximatelyZero(sign)) {
          continue;
        }
      }
      linear = false;
      bool foundOutlier = false;
      for (int n = 0; n < ptCount; ++n) {
        double test = (pts[n * 2 + 1] - origY) * adj - (pts[n * 2] - origX) * opp;
        if (test * sign > 0 && !preciselyZero(test)) {
          foundOutlier = true;
          break;
        }
      }
      if (!foundOutlier) {
        return _HullIntersectResult(false, linear);
      }
      endPt0x = endPt1x;
      endPt0y = endPt1y;
      end1 = end2;
    } while (hullIndex != 0);
    return _HullIntersectResult(true, linear);
  }

  /// Given a cubic, find the convex hull described by the end and
  /// control points.
  ///
  /// The hull may have 3 or 4 points. Cubics that degenerate into a point or
  /// line are not considered.
  ///
  /// The hull is computed by assuming that three points, if unique and
  /// non-linear, form a triangle. The fourth point may replace one of the first
  /// three, may be discarded if in the triangle or on an edge, or may be
  /// inserted between any of the three to form a convex quadralateral.
  ///
  /// The indices returned in order describe the convex hull.
  int convexHull(List<int> order) {
    assert(order.isEmpty);
    int index;
    // Find top point.
    int yMin = 0;
    for (index = 1; index < 4; ++index) {
      if (yAt(yMin) > yAt(index) || (yAt(yMin) == yAt(index)
          && xAt(yMin) > xAt(index))) {
        yMin = index;
      }
    }
    order.add(yMin); // 0.
    int midX = -1;
    int backupYMin = -1;
    for (int pass = 0; pass < 2; ++pass) {
      for (index = 0; index < 4; ++index) {
        if (index == yMin) {
          // Skip top point / already added.
          continue;
        }
        // Rotate line from (yMin, index) to axis.
        // See if remaining two points are both above or below to find mid.
        int mask = otherTwo(yMin, index);
        int side1 = yMin ^ mask;
        int side2 = index ^ mask;
        Cubic? rotResult = rotate(this, yMin, index);
        if (rotResult == null) {
          order.add(side1);
          order.add(side2);
          return 3;
        }
        Cubic rotPath = rotResult;
        int sides = side(rotPath.yAt(side1) - rotPath.yAt(yMin));
        sides ^= side(rotPath.yAt(side2) - rotPath.yAt(yMin));
        if (sides == 2) { // '2' means one remaining point <0, one >0
          if (midX >= 0) {
            // one of the control points is equal to an end point
            order[0] = 0;
            order.add(3);
            if ((p1x == p0x && p1y == p0y) || (p1x == p3x && p1y == p3y)) {
              order.add(2);
              return 3;
            }
            if ((p2x == p0x && p2y == p0y) || (p2x == p3x && p2y == p3y)) {
              order.add(1);
              return 3;
            }
            // one of the control points may be very nearly but not exactly equal --
            double dist1_0 = _distanceSquared(1, 0);
            double dist1_3 = _distanceSquared(1, 3);
            double dist2_0 = _distanceSquared(2, 0);
            double dist2_3 = _distanceSquared(2, 3);
            double smallest1distSq = math.min(dist1_0, dist1_3);
            double smallest2distSq = math.min(dist2_0, dist2_3);
            if (approximatelyZero(math.min(smallest1distSq, smallest2distSq))) {
              order[2] = smallest1distSq < smallest2distSq ? 2 : 1;
              return 3;
            }
          }
          midX = index;
        } else if (sides == 0) { // '0' means both to one side or the other
          backupYMin = index;
        }
      }
      if (midX >= 0) {
        break;
      }
      if (backupYMin < 0) {
        break;
      }
      yMin = backupYMin;
      backupYMin = -1;
    }
    if (midX < 0) {
      midX = yMin ^ 3; // choose any other point
    }
    int mask = otherTwo(yMin, midX);
    int least = yMin ^ mask;
    int most = midX ^ mask;
    order.clear();
    order.add(yMin);
    order.add(least);

    // See if mid value is on same side of line (least, most) as yMin
    Cubic? midPathResult = rotate(this, least, most);
    if (midPathResult == null) { // ! if cbc[least]==cbc[most]
      order.add(midX); // 2.
      return 3;
    }
    Cubic midPath = midPathResult;
    int midSides = side(midPath.yAt(yMin) - midPath.yAt(least));
    midSides ^= side(midPath.yAt(midX) - midPath.yAt(least));
    if (midSides != 2) {  // if mid point is not between
      order[2] = most;
      return 3; // result is a triangle
    }
    order.add(midX); // 2.
    order.add(most); // 3.
    // Result is a quadralateral.
    return 4;
  }

  // Returns 0 if negative, 1 if zero, 2 if positive
  static int side(double x) => ((x > 0) ? 1 : 0) + (x >= 0 ? 1 : 0);

  double _distanceSquared(int pointIndex1, int pointIndex2) =>
      distanceSquared(xAt(pointIndex1), yAt(pointIndex1), xAt(pointIndex2),
          yAt(pointIndex2));
}

Cubic? rotate(Cubic cubic, int zero, int index) {
  Cubic? rotPath;
  double dy = cubic.yAt(index) - cubic.yAt(zero);
  double dx = cubic.xAt(index) - cubic.xAt(zero);
  if (approximatelyZero(dy)) {
    if (approximatelyZero(dx)) {
      return null;
    }
    rotPath = Cubic(cubic.p0x, cubic.p0y, cubic.p1x, cubic.p1y,
        cubic.p2x, cubic.p2y, cubic.p3x, cubic.p3y);
    if (dy != 0) {
      rotPath.setYAt(index, cubic.yAt(zero));
      int mask = otherTwo(index, zero);
      int side1 = index ^ mask;
      int side2 = zero ^ mask;
      if (approximatelyEqualT(cubic.yAt(side1), cubic.yAt(zero))) {
        rotPath.setYAt(side1, cubic.yAt(zero));
      }
      if (approximatelyEqualT(cubic.yAt(side2), cubic.yAt(zero))) {
        rotPath.setYAt(side2, cubic.yAt(zero));
      }
    }
    return rotPath;
  }
  for (int index = 0; index < 4; ++index) {
    rotPath?.setXAt(index, cubic.xAt(index) * dx + cubic.yAt(index) * dy);
    rotPath?.setYAt(index, cubic.yAt(index) * dx - cubic.xAt(index) * dy);
  }
  return rotPath;
}

/// Given the set [0, 1, 2, 3], and two of the four members, compute an
/// XOR mask that computes the other two. Note that:
///   one ^ two == 3 for (0, 3), (1, 2)
///   one ^ two <  3 for (0, 1), (0, 2), (1, 3), (2, 3)
///   3 - (one ^ two) is either 0, 1, or 2
///   1 >> (3 - (one ^ two)) is either 0 or 1
/// thus:
///   returned == 2 for (0, 3), (1, 2)
///   returned == 3 for (0, 1), (0, 2), (1, 3), (2, 3)
/// given that:
///   (0, 3) ^ 2 -> (2, 1)  (1, 2) ^ 2 -> (3, 0)
///   (0, 1) ^ 3 -> (3, 2)  (0, 2) ^ 3 -> (3, 1)  (1, 3) ^ 3 -> (2, 0)
///       (2, 3) ^ 3 -> (1, 0)
int otherTwo(int one, int two) {
  return 1 >> (3 - (one ^ two)) ^ 3;
}

/// Chops cubic at Y extrema points and writes result to [dest].
///
/// [points] and [dest] are allowed to share underlying storage as long.
int _chopCubicAtYExtrema(Float32List points, Float32List dest) {
  final double y0 = points[1];
  final double y1 = points[3];
  final double y2 = points[5];
  final double y3 = points[7];
  _QuadRoots _quadRoots = Cubic.findExtrema(y0, y1, y2, y3);
  final List<double> roots = _quadRoots.roots;
  if (roots.isEmpty) {
    // No roots, just use input cubic.
    return 0;
  }
  _chopCubicAt(roots, points, dest);
  final int rootCount = roots.length;
  if (rootCount > 0) {
    // Cleanup to ensure Y extrema are flat.
    dest[5] = dest[9] = dest[7];
    if (rootCount == 2) {
      dest[11] = dest[15] = dest[13];
    }
  }
  return rootCount;
}

/// Subdivides cubic curve for a list of t values.
void _chopCubicAt(
    List<double> tValues, Float32List points, Float32List outPts) {
  if (assertionsEnabled) {
    for (int i = 0; i < tValues.length - 1; i++) {
      final double tValue = tValues[i];
      assert(tValue > 0 && tValue < 1,
          'Not expecting to chop curve at start, end points');
    }
    for (int i = 0; i < tValues.length - 1; i++) {
      final double tValue = tValues[i];
      final double nextTValue = tValues[i + 1];
      assert(
          nextTValue > tValue, 'Expecting t value to monotonically increase');
    }
  }
  int rootCount = tValues.length;
  if (0 == rootCount) {
    for (int i = 0; i < 8; i++) {
      outPts[i] = points[i];
    }
  } else {
    // Chop curve at t value and loop through right side of curve
    // while normalizing t value based on prior t.
    double? t = tValues[0];
    int bufferPos = 0;
    for (int i = 0; i < rootCount; i++) {
      _chopCubicAtT(points, bufferPos, outPts, bufferPos, t!);
      if (i == rootCount - 1) {
        break;
      }
      bufferPos += 6;

      // watch out in case the renormalized t isn't in range
      if ((t = _validUnitDivide(
              tValues[i + 1] - tValues[i], 1.0 - tValues[i])) ==
          null) {
        // Can't renormalize last point, just create a degenerate cubic.
        outPts[bufferPos + 4] = outPts[bufferPos + 5] =
            outPts[bufferPos + 6] = points[bufferPos + 3];
        break;
      }
    }
  }
}

/// Subdivides cubic curve at [t] and writes to [outPts] at position [outIndex].
///
/// The cubic points are read from [points] at [bufferPos] offset.
void _chopCubicAtT(Float32List points, int bufferPos, Float32List outPts,
    int outIndex, double t) {
  assert(t > 0 && t < 1);
  final double p3y = points[bufferPos + 7];
  final double p0x = points[bufferPos + 0];
  final double p0y = points[bufferPos + 1];
  final double p1x = points[bufferPos + 2];
  final double p1y = points[bufferPos + 3];
  final double p2x = points[bufferPos + 4];
  final double p2y = points[bufferPos + 5];
  final double p3x = points[bufferPos + 6];
  // If startT == 0 chop at end point and return curve.
  final double ab1x = _interpolate(p0x, p1x, t);
  final double ab1y = _interpolate(p0y, p1y, t);
  final double bc1x = _interpolate(p1x, p2x, t);
  final double bc1y = _interpolate(p1y, p2y, t);
  final double cd1x = _interpolate(p2x, p3x, t);
  final double cd1y = _interpolate(p2y, p3y, t);
  final double abc1x = _interpolate(ab1x, bc1x, t);
  final double abc1y = _interpolate(ab1y, bc1y, t);
  final double bcd1x = _interpolate(bc1x, cd1x, t);
  final double bcd1y = _interpolate(bc1y, cd1y, t);
  final double abcd1x = _interpolate(abc1x, bcd1x, t);
  final double abcd1y = _interpolate(abc1y, bcd1y, t);

  // Return left side of curve.
  outPts[outIndex++] = p0x;
  outPts[outIndex++] = p0y;
  outPts[outIndex++] = ab1x;
  outPts[outIndex++] = ab1y;
  outPts[outIndex++] = abc1x;
  outPts[outIndex++] = abc1y;
  outPts[outIndex++] = abcd1x;
  outPts[outIndex++] = abcd1y;
  // Return right side of curve.
  outPts[outIndex++] = bcd1x;
  outPts[outIndex++] = bcd1y;
  outPts[outIndex++] = cd1x;
  outPts[outIndex++] = cd1y;
  outPts[outIndex++] = p3x;
  outPts[outIndex++] = p3y;
}

// Returns t at Y for cubic curve. null if y is out of range.
//
// Options are Newton Raphson (quadratic convergence with typically
// 3 iterations or bisection with 16 iterations.
double? _chopMonoAtY(Float32List _buffer, int bufferStartPos, double y) {
  // Translate curve points relative to y.
  final double ycrv0 = _buffer[1 + bufferStartPos] - y;
  final double ycrv1 = _buffer[3 + bufferStartPos] - y;
  final double ycrv2 = _buffer[5 + bufferStartPos] - y;
  final double ycrv3 = _buffer[7 + bufferStartPos] - y;
  // Positive and negative function parameters.
  double tNeg, tPos;
  // Set initial t points to converge from.
  if (ycrv0 < 0) {
    if (ycrv3 < 0) {
      // Start and end points out of range.
      return null;
    }
    tNeg = 0;
    tPos = 1.0;
  } else if (ycrv0 > 0) {
    tNeg = 1.0;
    tPos = 0;
  } else {
    // Start is at y.
    return 0.0;
  }

  // Bisection / linear convergance.
  final double tolerance = 1.0 / 65536;
  do {
    final double tMid = (tPos + tNeg) / 2.0;
    final double y01 = ycrv0 + (ycrv1 - ycrv0) * tMid;
    final double y12 = ycrv1 + (ycrv2 - ycrv1) * tMid;
    final double y23 = ycrv2 + (ycrv3 - ycrv2) * tMid;
    final double y012 = y01 + (y12 - y01) * tMid;
    final double y123 = y12 + (y23 - y12) * tMid;
    final double y0123 = y012 + (y123 - y012) * tMid;
    if (y0123 == 0) {
      return tMid;
    }
    if (y0123 < 0) {
      tNeg = tMid;
    } else {
      tPos = tMid;
    }
  } while (((tPos - tNeg).abs() > tolerance));
  return (tNeg + tPos) / 2;
}

double _evalCubicPts(double c0, double c1, double c2, double c3, double t) {
  double A = c3 + 3 * (c1 - c2) - c0;
  double B = 3 * (c2 - c1 - c1 + c0);
  double C = 3 * (c1 - c0);
  double D = c0;
  return polyEval4(A, B, C, D, t);
}

// Reusable class to compute bounds without object allocation.
class _CubicBounds {
  double minX = 0.0;
  double maxX = 0.0;
  double minY = 0.0;
  double maxY = 0.0;

  /// Sets resulting bounds as [minX], [minY], [maxX], [maxY].
  ///
  /// The cubic is defined by 4 points (8 floats) in [points].
  void calculateBounds(Float32List points, int pointIndex) {
    final double startX = points[pointIndex++];
    final double startY = points[pointIndex++];
    final double cpX1 = points[pointIndex++];
    final double cpY1 = points[pointIndex++];
    final double cpX2 = points[pointIndex++];
    final double cpY2 = points[pointIndex++];
    final double endX = points[pointIndex++];
    final double endY = points[pointIndex++];
    // Bounding box is defined by all points on the curve where
    // monotonicity changes.
    minX = math.min(startX, endX);
    minY = math.min(startY, endY);
    maxX = math.max(startX, endX);
    maxY = math.max(startY, endY);

    double extremaX;
    double extremaY;
    double a, b, c;

    // Check for simple case of strong ordering before calculating
    // extrema
    if (!(((startX < cpX1) && (cpX1 < cpX2) && (cpX2 < endX)) ||
        ((startX > cpX1) && (cpX1 > cpX2) && (cpX2 > endX)))) {
      // The extrema point is dx/dt B(t) = 0
      // The derivative of B(t) for cubic bezier is a quadratic equation
      // with multiple roots
      // B'(t) = a*t*t + b*t + c*t
      a = -startX + (3 * (cpX1 - cpX2)) + endX;
      b = 2 * (startX - (2 * cpX1) + cpX2);
      c = -startX + cpX1;

      // Now find roots for quadratic equation with known coefficients
      // a,b,c
      // The roots are (-b+-sqrt(b*b-4*a*c)) / 2a
      num s = (b * b) - (4 * a * c);
      // If s is negative, we have no real roots
      if ((s >= 0.0) && (a.abs() > SPath.scalarNearlyZero)) {
        if (s == 0.0) {
          // we have only 1 root
          final double t = -b / (2 * a);
          final double tprime = 1.0 - t;
          if ((t >= 0.0) && (t <= 1.0)) {
            extremaX = ((tprime * tprime * tprime) * startX) +
                ((3 * tprime * tprime * t) * cpX1) +
                ((3 * tprime * t * t) * cpX2) +
                (t * t * t * endX);
            minX = math.min(extremaX, minX);
            maxX = math.max(extremaX, maxX);
          }
        } else {
          // we have 2 roots
          s = math.sqrt(s);
          double t = (-b - s) / (2 * a);
          double tprime = 1.0 - t;
          if ((t >= 0.0) && (t <= 1.0)) {
            extremaX = ((tprime * tprime * tprime) * startX) +
                ((3 * tprime * tprime * t) * cpX1) +
                ((3 * tprime * t * t) * cpX2) +
                (t * t * t * endX);
            minX = math.min(extremaX, minX);
            maxX = math.max(extremaX, maxX);
          }
          // check 2nd root
          t = (-b + s) / (2 * a);
          tprime = 1.0 - t;
          if ((t >= 0.0) && (t <= 1.0)) {
            extremaX = ((tprime * tprime * tprime) * startX) +
                ((3 * tprime * tprime * t) * cpX1) +
                ((3 * tprime * t * t) * cpX2) +
                (t * t * t * endX);

            minX = math.min(extremaX, minX);
            maxX = math.max(extremaX, maxX);
          }
        }
      }
    }

    // Now calc extremes for dy/dt = 0 just like above
    if (!(((startY < cpY1) && (cpY1 < cpY2) && (cpY2 < endY)) ||
        ((startY > cpY1) && (cpY1 > cpY2) && (cpY2 > endY)))) {
      // The extrema point is dy/dt B(t) = 0
      // The derivative of B(t) for cubic bezier is a quadratic equation
      // with multiple roots
      // B'(t) = a*t*t + b*t + c*t
      a = -startY + (3 * (cpY1 - cpY2)) + endY;
      b = 2 * (startY - (2 * cpY1) + cpY2);
      c = -startY + cpY1;

      // Now find roots for quadratic equation with known coefficients
      // a,b,c
      // The roots are (-b+-sqrt(b*b-4*a*c)) / 2a
      double s = (b * b) - (4 * a * c);
      // If s is negative, we have no real roots
      if ((s >= 0.0) && (a.abs() > SPath.scalarNearlyZero)) {
        if (s == 0.0) {
          // we have only 1 root
          final double t = -b / (2 * a);
          final double tprime = 1.0 - t;
          if ((t >= 0.0) && (t <= 1.0)) {
            extremaY = ((tprime * tprime * tprime) * startY) +
                ((3 * tprime * tprime * t) * cpY1) +
                ((3 * tprime * t * t) * cpY2) +
                (t * t * t * endY);
            minY = math.min(extremaY, minY);
            maxY = math.max(extremaY, maxY);
          }
        } else {
          // we have 2 roots
          s = math.sqrt(s);
          final double t = (-b - s) / (2 * a);
          final double tprime = 1.0 - t;
          if ((t >= 0.0) && (t <= 1.0)) {
            extremaY = ((tprime * tprime * tprime) * startY) +
                ((3 * tprime * tprime * t) * cpY1) +
                ((3 * tprime * t * t) * cpY2) +
                (t * t * t * endY);
            minY = math.min(extremaY, minY);
            maxY = math.max(extremaY, maxY);
          }
          // check 2nd root
          final double t2 = (-b + s) / (2 * a);
          final double tprime2 = 1.0 - t2;
          if ((t2 >= 0.0) && (t2 <= 1.0)) {
            extremaY = ((tprime2 * tprime2 * tprime2) * startY) +
                ((3 * tprime2 * tprime2 * t2) * cpY1) +
                ((3 * tprime2 * t2 * t2) * cpY2) +
                (t2 * t2 * t2 * endY);
            minY = math.min(extremaY, minY);
            maxY = math.max(extremaY, maxY);
          }
        }
      }
    }
  }
}

/// Chops cubic spline at startT and stopT, writes result to buffer.
void _chopCubicBetweenT(
    List<double> points, double startT, double stopT, Float32List buffer) {
  assert(startT != 0 || stopT != 0);
  final double p3y = points[7];
  final double p0x = points[0];
  final double p0y = points[1];
  final double p1x = points[2];
  final double p1y = points[3];
  final double p2x = points[4];
  final double p2y = points[5];
  final double p3x = points[6];
  // If startT == 0 chop at end point and return curve.
  final bool chopStart = startT != 0;
  final double t = chopStart ? startT : stopT;

  final double ab1x = _interpolate(p0x, p1x, t);
  final double ab1y = _interpolate(p0y, p1y, t);
  final double bc1x = _interpolate(p1x, p2x, t);
  final double bc1y = _interpolate(p1y, p2y, t);
  final double cd1x = _interpolate(p2x, p3x, t);
  final double cd1y = _interpolate(p2y, p3y, t);
  final double abc1x = _interpolate(ab1x, bc1x, t);
  final double abc1y = _interpolate(ab1y, bc1y, t);
  final double bcd1x = _interpolate(bc1x, cd1x, t);
  final double bcd1y = _interpolate(bc1y, cd1y, t);
  final double abcd1x = _interpolate(abc1x, bcd1x, t);
  final double abcd1y = _interpolate(abc1y, bcd1y, t);
  if (!chopStart) {
    // Return left side of curve.
    buffer[0] = p0x;
    buffer[1] = p0y;
    buffer[2] = ab1x;
    buffer[3] = ab1y;
    buffer[4] = abc1x;
    buffer[5] = abc1y;
    buffer[6] = abcd1x;
    buffer[7] = abcd1y;
    return;
  }
  if (stopT == 1) {
    // Return right side of curve.
    buffer[0] = abcd1x;
    buffer[1] = abcd1y;
    buffer[2] = bcd1x;
    buffer[3] = bcd1y;
    buffer[4] = cd1x;
    buffer[5] = cd1y;
    buffer[6] = p3x;
    buffer[7] = p3y;
    return;
  }
  // We chopped at startT, now the right hand side of curve is at
  // abcd1, bcd1, cd1, p3x, p3y. Chop this part using endT;
  final double endT = (stopT - startT) / (1 - startT);
  final double ab2x = _interpolate(abcd1x, bcd1x, endT);
  final double ab2y = _interpolate(abcd1y, bcd1y, endT);
  final double bc2x = _interpolate(bcd1x, cd1x, endT);
  final double bc2y = _interpolate(bcd1y, cd1y, endT);
  final double cd2x = _interpolate(cd1x, p3x, endT);
  final double cd2y = _interpolate(cd1y, p3y, endT);
  final double abc2x = _interpolate(ab2x, bc2x, endT);
  final double abc2y = _interpolate(ab2y, bc2y, endT);
  final double bcd2x = _interpolate(bc2x, cd2x, endT);
  final double bcd2y = _interpolate(bc2y, cd2y, endT);
  final double abcd2x = _interpolate(abc2x, bcd2x, endT);
  final double abcd2y = _interpolate(abc2y, bcd2y, endT);
  buffer[0] = abcd1x;
  buffer[1] = abcd1y;
  buffer[2] = ab2x;
  buffer[3] = ab2y;
  buffer[4] = abc2x;
  buffer[5] = abc2y;
  buffer[6] = abcd2x;
  buffer[7] = abcd2y;
}

class _CubicPair {
  _CubicPair(this.first, this.second);
  final Cubic first;
  final Cubic second;
}
