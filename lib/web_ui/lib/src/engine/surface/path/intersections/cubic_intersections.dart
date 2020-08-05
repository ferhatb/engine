// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Find the interection of a line and cubic by solving for valid t values.
///
/// Analogous to line-quadratic intersection, solve line-cubic intersection by
/// representing the cubic as:
///   x = a(1-t)^3 + 2b(1-t)^2t + c(1-t)t^2 + dt^3
///   y = e(1-t)^3 + 2f(1-t)^2t + g(1-t)t^2 + ht^3
/// and the line as:
///   y = i*x + j  (if the line is more horizontal)
/// or:
///   x = i*y + j  (if the line is more vertical)
///
/// Then using Mathematica, solve for the values of t where the cubic intersects the
/// line:
///
///   (in) Resultant[
///         a*(1 - t)^3 + 3*b*(1 - t)^2*t + 3*c*(1 - t)*t^2 + d*t^3 - x,
///         e*(1 - t)^3 + 3*f*(1 - t)^2*t + 3*g*(1 - t)*t^2 + h*t^3 - i*x - j, x]
///   (out) -e     +   j     +
///        3 e t   - 3 f t   -
///        3 e t^2 + 6 f t^2 - 3 g t^2 +
///          e t^3 - 3 f t^3 + 3 g t^3 - h t^3 +
///      i ( a     -
///        3 a t + 3 b t +
///        3 a t^2 - 6 b t^2 + 3 c t^2 -
///          a t^3 + 3 b t^3 - 3 c t^3 + d t^3 )
///
/// if i goes to infinity, we can rewrite the line in terms of x. Mathematica:
///
///   (in) Resultant[
///         a*(1 - t)^3 + 3*b*(1 - t)^2*t + 3*c*(1 - t)*t^2 + d*t^3 - i*y - j,
///         e*(1 - t)^3 + 3*f*(1 - t)^2*t + 3*g*(1 - t)*t^2 + h*t^3 - y,       y]
///   (out)  a     -   j     -
///        3 a t   + 3 b t   +
///        3 a t^2 - 6 b t^2 + 3 c t^2 -
///          a t^3 + 3 b t^3 - 3 c t^3 + d t^3 -
///      i ( e     -
///        3 e t   + 3 f t   +
///        3 e t^2 - 6 f t^2 + 3 g t^2 -
///          e t^3 + 3 f t^3 - 3 g t^3 + h t^3 )
///
/// Solving this with Mathematica produces an expression with hundreds of terms;
/// instead, use Numeric Solutions recipe to solve the cubic.
///
/// The near-horizontal case, in terms of:  Ax^3 + Bx^2 + Cx + D == 0
///     A =   (-(-e + 3*f - 3*g + h) + i*(-a + 3*b - 3*c + d)     )
///     B = 3*(-( e - 2*f +   g    ) + i*( a - 2*b +   c    )     )
///     C = 3*(-(-e +   f          ) + i*(-a +   b          )     )
///     D =   (-( e                ) + i*( a                ) + j )
///
/// The near-vertical case, in terms of:  Ax^3 + Bx^2 + Cx + D == 0
///     A =   ( (-a + 3*b - 3*c + d) - i*(-e + 3*f - 3*g + h)     )
///     B = 3*( ( a - 2*b +   c    ) - i*( e - 2*f +   g    )     )
///     C = 3*( (-a +   b          ) - i*(-e +   f          )     )
///     D =   ( ( a                ) - i*( e                ) - j )
///
/// For horizontal lines:
/// (in) Resultant[
///       a*(1 - t)^3 + 3*b*(1 - t)^2*t + 3*c*(1 - t)*t^2 + d*t^3 - j,
///       e*(1 - t)^3 + 3*f*(1 - t)^2*t + 3*g*(1 - t)*t^2 + h*t^3 - y, y]
/// (out)  e     -   j     -
///      3 e t   + 3 f t   +
///      3 e t^2 - 6 f t^2 + 3 g t^2 -
///        e t^3 + 3 f t^3 - 3 g t^3 + h t^3
class LineCubicIntersections {
  LineCubicIntersections(this.cubic, this.line, this.i);
  final Cubic cubic;
  final DLine line;
  final Intersections i;
  bool fAllowNear = true;

  void allowNear(bool allow) {
    fAllowNear = allow;
  }

  void checkCoincident() {
    int last = i.fUsed - 1;
    for (int index = 0; index < last; ) {
      double cubicMidT = (i.fT0[index] + i.fT0[index + 1]) / 2;
      ui.Offset cubicMidPt = cubic.ptAtT(cubicMidT);
      double t = line.nearPoint(cubicMidPt.dx, cubicMidPt.dy);
      if (t < 0) {
        ++index;
        continue;
      }
      if (i.isCoincident(index)) {
        i.removeOne(index);
        --last;
      } else if (i.isCoincident(index + 1)) {
        i.removeOne(index + 1);
        --last;
      } else {
        i.setCoincident(index++);
      }
      i.setCoincident(index);
    }
  }

  // Intersect with ray and return roots.
  int intersectRay(List<double> roots) {
    final double lineX = line.x0;
    final double lineY = line.y0;
    double adj = line.x1 - lineX;
    double opp = line.y1 - lineY;
    double c0 = (cubic.p0y - lineY) * adj - (cubic.p0x - lineX) * opp;
    double c1 = (cubic.p1y - lineY) * adj - (cubic.p1x - lineX) * opp;
    double c2 = (cubic.p2y - lineY) * adj - (cubic.p2x - lineX) * opp;
    double c3 = (cubic.p3y - lineY) * adj - (cubic.p3x - lineX) * opp;
    // Solve roots.
    _CubicCoeff coeff = _CubicCoeff(c0, c1, c2, c3);
    int count = Cubic.rootsValidT(coeff.A, coeff.B, coeff.C, coeff.D, roots);
    for (int index = 0; index < count; ++index) {
      Cubic c = Cubic(c0, 0, c1, 0, c2, 0, c3, 0);
      ui.Offset calcPt = c.ptAtT(roots[index]);
      if (!approximatelyZero(calcPt.dx)) {
        c.p0y = (cubic.p0y - lineY) * opp - (cubic.p0x - lineX) * adj;
        c.p1y = (cubic.p1y - lineY) * opp - (cubic.p1x - lineX) * adj;
        c.p2y = (cubic.p2y - lineY) * opp - (cubic.p2x - lineX) * adj;
        c.p3y = (cubic.p3y - lineY) * opp - (cubic.p3x - lineX) * adj;
        _QuadRoots tRoots = Cubic.findExtrema(c.p0y, c.p1y, c.p2y, c.p3y);
        List<double> extremeTs = tRoots.roots;
        count = c.searchRoots(extremeTs, extremeTs.length, 0,
            Cubic.kXAxis, roots);
        break;
      }
    }
    return count;
  }

  int intersect() {
      _addExactEndPoints();
      if (fAllowNear) {
        _addNearEndPoints();
      }
      List<double> rootVals = [];
      int roots = intersectRay(rootVals);
      for (int index = 0; index < roots; ++index) {
        double cubicT = rootVals[index];
        double lineT = findLineT(cubicT);
        ui.Offset pt = cubic.ptAtT(cubicT);
        _CurveLinePinT pinResult = pinTs(cubicT, lineT, pt.dx, pt.dy);
        pt = ui.Offset(pinResult.px, pinResult.py);
        cubicT = pinResult.curveT;
        lineT = pinResult.lineT;
        if (pinResult.success && uniqueAnswer(cubicT, pt.dx, pt.dy)) {
            i.insert(cubicT, lineT, pt.dx, pt.dy);
        }
      }
      checkCoincident();
      return i.fUsed;
  }

  static int _horizontalIntersect(Cubic c, double axisIntercept, List<double> roots) {
    _CubicCoeff coeff = _CubicCoeff(c.p0y, c.p1y, c.p2y, c.p3y);
    double A = coeff.A;
    double B = coeff.B;
    double C = coeff.C;
    double D = coeff.D - axisIntercept;
    int count = Cubic.rootsValidT(A, B, C, D, roots);
    for (int index = 0; index < count; ++index) {
      ui.Offset calcPt = c.ptAtT(roots[index]);
      if (!approximatelyEqualT(calcPt.dy, axisIntercept)) {
        _QuadRoots tRoots = Cubic.findExtrema(c.p0y, c.p1y, c.p2y, c.p3y);
        List<double> extremeTs = tRoots.roots;
        count = c.searchRoots(extremeTs, extremeTs.length, axisIntercept,
            Cubic.kYAxis, roots);
        break;
      }
    }
    return count;
  }

  int horizontalIntersect(double axisIntercept, double left, double right, bool flipped) {
    _addExactHorizontalEndPoints(left, right, axisIntercept);
    if (fAllowNear) {
      _addNearHorizontalEndPoints(left, right, axisIntercept);
    }
    List<double> roots = [];
    int count = _horizontalIntersect(cubic, axisIntercept, roots);
    for (int index = 0; index < count; ++index) {
      double cubicT = roots[index];
      ui.Offset pt = ui.Offset(cubic.ptAtT(cubicT).dx, axisIntercept);
      double lineT = (pt.dx - left) / (right - left);
      _CurveLinePinT pinResult = pinTs(cubicT, lineT, pt.dx, pt.dy);
      pt = ui.Offset(pinResult.px, pinResult.py);
      cubicT = pinResult.curveT;
      lineT = pinResult.lineT;
      if (pinResult.success && uniqueAnswer(cubicT, pt.dx, pt.dy)) {
        i.insert(cubicT, lineT, pt.dx, pt.dy);
      }
    }
    if (flipped) {
      i.flip();
    }
    checkCoincident();
    return i.fUsed;
  }

  /// Check if conicT or (existingT to conicT midpoint) is already in
  /// intersections within tolerance.
  bool uniqueAnswer(double cubicT, double px, double py) {
    for (int inner = 0; inner < i.fUsed; ++inner) {
      if (i.ptX[inner] != px || i.ptY[inner] != py) {
        continue;
      }
      double existingCubicT = i.fT0[inner];
      if (cubicT == existingCubicT) {
        return false;
      }
      // check if midway on conic is also same point. If so, discard this
      double cubicMidT = (existingCubicT + cubicT) / 2;
      ui.Offset cubicMidPt = cubic.ptAtT(cubicMidT);
      if (approximatelyEqualPoints(cubicMidPt.dx, cubicMidPt.dy, px, py)) {
        return false;
      }
    }
    return true;
  }

  static int _verticalIntersect(Cubic c, double axisIntercept, List<double> roots) {
    _CubicCoeff coeff = _CubicCoeff(c.p0x, c.p1x, c.p2x, c.p3x);
    double A = coeff.A;
    double B = coeff.B;
    double C = coeff.C;
    double D = coeff.D - axisIntercept;
    int count = Cubic.rootsValidT(A, B, C, D, roots);
    for (int index = 0; index < count; ++index) {
      ui.Offset calcPt = c.ptAtT(roots[index]);
      if (!approximatelyEqualT(calcPt.dx, axisIntercept)) {
        _QuadRoots tRoots = Cubic.findExtrema(c.p0x, c.p1x, c.p2x, c.p3x);
        List<double> extremeTs = tRoots.roots;
        count = c.searchRoots(extremeTs, extremeTs.length, axisIntercept,
            Cubic.kXAxis, roots);
        break;
      }
    }
    return count;
  }

  int verticalIntersect(double axisIntercept, double top, double bottom, bool flipped) {
      _addExactVerticalEndPoints(top, bottom, axisIntercept);
      if (fAllowNear) {
        _addNearVerticalEndPoints(top, bottom, axisIntercept);
      }
      List<double> roots = [];
      int count = _verticalIntersect(cubic, axisIntercept, roots);
      for (int index = 0; index < count; ++index) {
        double cubicT = roots[index];
        ui.Offset pt = ui.Offset(axisIntercept, cubic.ptAtT(cubicT).dy);
        double lineT = (pt.dy - top) / (bottom - top);
        _CurveLinePinT pinResult = pinTs(cubicT, lineT, pt.dx, pt.dy);
        pt = ui.Offset(pinResult.px, pinResult.py);
        cubicT = pinResult.curveT;
        lineT = pinResult.lineT;
        if (pinResult.success && uniqueAnswer(cubicT, pt.dx, pt.dy)) {
          i.insert(cubicT, lineT, pt.dx, pt.dy);
        }
      }
      if (flipped) {
        i.flip();
      }
      checkCoincident();
      return i.fUsed;
  }

  void _addExactEndPoints() {
    for (int cIndex = 0; cIndex < Cubic.kPointCount; cIndex += Conic.kPointLast) {
      final double px = cubic.xAt(cIndex);
      final double py = cubic.yAt(cIndex);
      double lineT = line.exactPoint(px, py);
      if (lineT < 0) {
        continue;
      }
      double cubicT = (cIndex >> 1).toDouble();
      i.insert(cubicT, lineT, px, py);
    }
  }

  /// Note that this does not look for endpoints of the line that are near the cubic.
  /// These points are found later when check ends looks for missing points.
  void _addNearEndPoints() {
    for (int cIndex = 0; cIndex < Cubic.kPointCount; cIndex += Cubic.kPointLast) {
      double cubicT = (cIndex >> 1).toDouble();
      if (i.hasT(cubicT)) {
        continue;
      }
      final double px = cubic.xAt(cIndex);
      final double py = cubic.yAt(cIndex);
      double lineT = line.nearPoint(px, py);
      if (lineT < 0) {
        continue;
      }
      i.insert(cubicT, lineT, px, py);
    }
    _addLineNearEndPoints();
  }

  void _addLineNearEndPoints() {
    if (!i.hasOppT(0)) {
      double cubicT = CurveDistance.nearPoint(cubic.toPoints(),
          SPathVerb.kCubic, 1.0, line.x0, line.y0, line.x1, line.y1);
      if (cubicT >= 0) {
        i.insert(cubicT, 0, line.x0, line.y0);
      }
    }
    if (!i.hasOppT(1)) {
      double cubicT = CurveDistance.nearPoint(cubic.toPoints(),
          SPathVerb.kConic, 1.0, line.x1, line.y1, line.x0, line.y0);
      if (cubicT >= 0) {
        i.insert(cubicT, 1, line.x1, line.y1);
      }
    }
  }

  void _addExactHorizontalEndPoints(double left, double right, double y) {
    for (int cIndex = 0; cIndex < Cubic.kPointCount; cIndex += Cubic.kPointLast) {
      final double px = cubic.xAt(cIndex);
      final double py = cubic.yAt(cIndex);
      double lineT = DLine.exactPointH(px, py, left, right, y);
      if (lineT < 0) {
        continue;
      }
      double cubicT = (cIndex >> 1).toDouble();
      i.insert(cubicT, lineT, px, py);
    }
  }

  void _addNearHorizontalEndPoints(double left, double right, double y) {
    for (int cIndex = 0; cIndex < Cubic.kPointCount; cIndex += Cubic.kPointLast) {
      double cubicT = (cIndex >> 1).toDouble();
      if (i.hasT(cubicT)) {
        continue;
      }
      final double px = cubic.xAt(cIndex);
      final double py = cubic.yAt(cIndex);
      double lineT = DLine.nearPointH(px, py, left, right, y);
      if (lineT < 0) {
        continue;
      }
      i.insert(cubicT, lineT, px, py);
    }
    _addLineNearEndPoints();
  }

  void _addExactVerticalEndPoints(double top, double bottom, double x) {
    for (int cIndex = 0; cIndex < Cubic.kPointCount; cIndex += Cubic.kPointLast) {
      final double px = cubic.xAt(cIndex);
      final double py = cubic.yAt(cIndex);
      double lineT = DLine.exactPointV(px, py, top, bottom, x);
      if (lineT < 0) {
        continue;
      }
      double cubicT = (cIndex >> 1).toDouble();
      i.insert(cubicT, lineT, px, py);
    }
  }

  void _addNearVerticalEndPoints(double top, double bottom, double x) {
    for (int cIndex = 0; cIndex < Cubic.kPointCount; cIndex += Cubic.kPointLast) {
      double cubicT = (cIndex >> 1).toDouble();
      if (i.hasT(cubicT)) {
        continue;
      }
      final double px = cubic.xAt(cIndex);
      final double py = cubic.yAt(cIndex);
      double lineT = DLine.nearPointV(px, py, top, bottom, x);
      if (lineT < 0) {
          continue;
      }
      i.insert(cubicT, lineT, px, py);
    }
    _addLineNearEndPoints();
  }

  double findLineT(double t) {
      ui.Offset xy = cubic.ptAtT(t);
      double dx = line.x1 - line.x0;
      double dy = line.y1 - line.y0;
      if (dx.abs() > dy.abs()) {
          return (xy.dx - line.x0) / dx;
      }
      return (xy.dy - line.y0) / dy;
  }

  /// If point is close to end points of cubic or line pin T values to 0 and 1.
  ///
  /// px,py should be initialized to point on curve at cubicT.
  _CurveLinePinT pinTs(double curveT, double lineT, double px, double py) {
    _CurveLinePinT result = _CurveLinePinT(curveT, lineT, px, py);
    if (!approximatelyOneOrLess(lineT)) {
      return result;
    }
    if (!approximatelyZeroOrMoreDouble(lineT)) {
      return result;
    }
    double qT = curveT = pinT(curveT);
    double lT = lineT = pinT(lineT);

    double lx = line.ptAtTx(lT);
    double ly = line.ptAtTx(lT);
    ui.Offset qPt = cubic.ptAtT(qT);
    if (!roughlyEqualPoints(lx, ly, qPt.dx, qPt.dy)) {
      return result;
    }
    // If points are roughly equal but not approximately equal, need to do
    // a binary search like quad/quad intersection to find more precise t
    // values.
    if (lT == 0 || lT == 1) {
      result.px = lx;
      result.py = ly;
    } else if (qT != curveT) {
      result.px = qPt.dx;
      result.py = qPt.dy;
    }
    double gridPx = px;
    double gridPy = py;
    if (approximatelyEqual(gridPx, gridPy, line.x0, line.y0)) {
      result.px = line.x0;
      result.py = line.y0;
      result.lineT = 0;
    } else if (approximatelyEqual(gridPx, gridPy, line.x1, line.y1)) {
      result.px = line.x1;
      result.py = line.y1;
      result.lineT = 1;
    }
    if (gridPx == cubic.p0x && gridPy == cubic.p0y) {
      result.px = cubic.p0x;
      result.py = cubic.p0y;
      result.curveT = 0;
    } else if (gridPx == cubic.p3x && gridPy == cubic.p3y) {
      result.px = cubic.p3x;
      result.py = cubic.p3y;
      result.curveT = 1;
    }
    result.success = true;
    return result;
  }
}

/// Calculates cubic coefficients to solve roots.
class _CubicCoeff {
  _CubicCoeff._(this.A, this.B, this.C, this.D);
  factory _CubicCoeff(double c0, double c1, double c2, double c3) {
    final double d = c0;
    double c = 3 * c1;
    double b = 3 * c2;
    double a = c3;
    a -= d - c + b;       // A =   -a + 3*b - 3*c + d
    b += 3 * d - 2 * c;   // B =  3*a - 6*b + 3*c
    c -= 3 * d;           // C = -3*a + 3*b
    return _CubicCoeff._(a, b, c, d);
  }
  final double A;
  final double B;
  final double C;
  final double D;
}
