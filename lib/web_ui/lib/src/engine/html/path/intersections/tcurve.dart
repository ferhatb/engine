// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10

part of engine;

/// Wraps Quad/Conic/Cubic curves to provide consistent interface for
/// computing intersections between curves.
abstract class TCurve {
  ui.Offset operator [](int index);

  /// Whether control points are approximately equal and curve collapses
  /// into point.
  bool collapsed();

  /// Checks angles between points to determine if curve points are inside
  /// vectors at start and end control points.
  bool controlsInside();
  /// Slope of curve at t.
  ui.Offset dxdyAtT(double t);

  _HullIntersectResult hullIntersectsQuad(Quad curve); // Returns success, isLinearResult.
  _HullIntersectResult hullIntersectsConic(Conic curve); // Returns success, isLinearResult.
  _HullIntersectResult hullIntersectsCubic(Cubic curve); // Returns success, isLinearResult.
  _HullIntersectResult hullIntersects(TCurve curve); // Returns success, isLinearResult.

  int intersectRay(Intersections i, DLine line);
  bool get isConic;
  /// Maximum number of intersections with a ray.
  int get maxIntersections;
  /// To calculate hull, based on [oddMan] returns other curve points.
  Float32List otherPts(int oddMan);
  int get pointCount;
  int get pointLast;
  ui.Offset ptAtT(double t);
  ui.Rect getTightBounds();
  void setPoint(int pointIndex, double x, double y);
  TCurve subDivide(double t1, double t2);
  TCurve clone();
  void offset(int verb, ui.Offset offset);

  /// Checks if line is parallel to curve by intersecting lines perpendicular at
  /// line end points with curve and checking if they are approximately equal
  /// i.e. very close to curvature on both start and end.
  ///
  /// ! For now only works for Conics.
  static bool isParallel(DLine thisLine, TCurve opp) {
    if (!(opp is TConic)) {
      return false;
    }
    int finds = 0;
    DLine perpLine = DLine(thisLine.x1 + (thisLine.y1 - thisLine.y0),
        thisLine.y1 + (thisLine.x0 - thisLine.x1), thisLine.x1, thisLine.y1);
    Intersections perpRayI = Intersections();
    opp.intersectRay(perpRayI, perpLine);
    for (int pIndex = 0; pIndex < perpRayI.fUsed; ++pIndex) {
      if (approximatelyEqualPoints(perpRayI.ptX[pIndex], perpRayI.ptY[pIndex],
          perpLine.x1, perpLine.y1)) {
        finds++;
      }
    }
    perpLine = DLine(thisLine.x0, thisLine.y0,
        thisLine.x0 + (thisLine.y1 - thisLine.y0),
        thisLine.y0 + (thisLine.x0 - thisLine.x1));
        opp.intersectRay(perpRayI, perpLine);
    for (int pIndex = 0; pIndex < perpRayI.fUsed; ++pIndex) {
      if (approximatelyEqualPoints(perpRayI.ptX[pIndex], perpRayI.ptY[pIndex],
          perpLine.x0, perpLine.y0)) {
        finds++;
      }
    }
    return finds >= 2;
  }
}

class TQuad implements TCurve {
  final Quad quad;
  TQuad(this.quad);

  double _xAt(int index) => quad.points[index * 2];
  double _yAt(int index) => quad.points[index * 2 + 1];
  @override
  ui.Offset operator [](int index) => ui.Offset(_xAt(index), _yAt(index));
  @override
  TCurve clone() => TQuad(quad.clone());
  @override
  bool collapsed() => quad.collapsed();
  @override
  bool controlsInside() => quad.controlsInside();
  @override
  ui.Offset dxdyAtT(double t) => quad.dxdyAtT(t);
  @override
  int intersectRay(Intersections i, DLine line) => i.intersectRayQuad(quad, line);
  @override
  bool get isConic => false;
  @override
  int get maxIntersections => 4;
  @override
  void offset(int verb, ui.Offset offset) => quad.offset(offset);
  @override
  Float32List otherPts(int oddMan) => quad.otherPts(oddMan);
  @override
  int get pointCount => Quad.kPointCount;
  @override
  int get pointLast => Quad.kPointLast;
  @override
  ui.Offset ptAtT(double t) => quad.ptAtT(t);
  @override
  void setPoint(int pointIndex, double x, double y) => quad.setPoint(pointIndex, x, y);
  @override
  ui.Rect getTightBounds() {
    final _QuadBounds quadBounds = _QuadBounds();
    quadBounds.calculateBounds(quad.points, 0);
    return ui.Rect.fromLTRB(quadBounds.minX, quadBounds.minY, quadBounds.maxX,
        quadBounds.maxY);
  }
  @override
  TCurve subDivide(double t1, double t2) => TQuad(quad.subDivide(t1, t2));
  @override
  _HullIntersectResult hullIntersectsQuad(Quad curve) => curve.hullIntersectsQuad(quad);
  @override
  _HullIntersectResult hullIntersectsConic(Conic curve) => curve.hullIntersectsQuad(quad);
  @override
  _HullIntersectResult hullIntersectsCubic(Cubic curve) => curve.hullIntersects(quad.points, Quad.kPointCount);
  @override
  _HullIntersectResult hullIntersects(TCurve curve) => curve.hullIntersectsQuad(quad);
}

class TConic implements TCurve {
  final Conic conic;
  TConic(this.conic);

  ui.Offset operator [](int index) => ui.Offset(conic.xAt(index), conic.yAt(index));
  @override
  TCurve clone() => TConic(conic.clone());
  @override
  bool collapsed() => conic.collapsed();
  @override
  bool controlsInside() => conic.controlsInside();
  @override
  ui.Offset dxdyAtT(double t) => conic.dxdyAtT(t);
  @override
  int intersectRay(Intersections i, DLine line) => i.intersectRayConic(conic, line);
  @override
  bool get isConic => true;
  @override
  int get maxIntersections => 4;
  @override
  void offset(int verb, ui.Offset offset) => conic.offset(offset);
  @override
  Float32List otherPts(int oddMan) => conic.otherPts(oddMan);
  @override
  int get pointCount => Conic.kPointCount;
  @override
  int get pointLast => Conic.kPointLast;
  @override
  ui.Offset ptAtT(double t) => conic.ptAtT(t);
  @override
  void setPoint(int pointIndex, double x, double y) => conic.setPoint(pointIndex, x, y);
  @override
  ui.Rect getTightBounds() {
    final _ConicBounds conicBounds = _ConicBounds();
    conicBounds.calculateBounds(conic.toPoints(), conic.fW, 0);
    return ui.Rect.fromLTRB(conicBounds.minX, conicBounds.minY,
        conicBounds.maxX, conicBounds.maxY);
  }
  @override
  TCurve subDivide(double t1, double t2) => TConic(conic.subDivide(t1, t2));
  @override
  _HullIntersectResult hullIntersectsQuad(Quad curve) => curve.hullIntersectsConic(conic);
  @override
  _HullIntersectResult hullIntersectsConic(Conic curve) => Quad(conic.toPoints()).hullIntersectsQuad(Quad(curve.toPoints()));
  @override
  _HullIntersectResult hullIntersectsCubic(Cubic curve) => curve.hullIntersects(conic.toPoints(), Conic.kPointCount);
  @override
  _HullIntersectResult hullIntersects(TCurve curve) => curve.hullIntersectsConic(conic);
}

class TCubic implements TCurve {
  final Cubic cubic;
  TCubic(this.cubic);
  @override
  ui.Offset operator [](int index) => ui.Offset(cubic.xAt(index), cubic.yAt(index));
  @override
  TCurve clone() => TCubic(cubic.clone());
  @override
  bool collapsed() => cubic.collapsed();
  @override
  bool controlsInside() => cubic.controlsInside();
  @override
  ui.Offset dxdyAtT(double t) => cubic.dxdyAtT(t);
  @override
  int intersectRay(Intersections i, DLine line) => i.intersectRayCubic(cubic, line);
  @override
  bool get isConic => false;
  @override
  int get maxIntersections => 9;
  @override
  void offset(int verb, ui.Offset offset) => cubic.offset(offset);
  @override
  Float32List otherPts(int oddMan) => cubic.otherPts(oddMan);
  @override
  int get pointCount => Cubic.kPointCount;
  @override
  int get pointLast => Cubic.kPointLast;
  @override
  ui.Offset ptAtT(double t) => cubic.ptAtT(t);
  @override
  void setPoint(int pointIndex, double x, double y) => cubic.setPoint(pointIndex, x, y);
  @override
  ui.Rect getTightBounds() {
    final _CubicBounds cubicBounds = _CubicBounds();
    cubicBounds.calculateBounds(cubic.toPoints(), 0);
    return ui.Rect.fromLTRB(cubicBounds.minX, cubicBounds.minY,
        cubicBounds.maxX, cubicBounds.maxY);
  }
  @override
  TCurve subDivide(double t1, double t2) => TCubic(cubic.subDivide(t1, t2));
  @override
  _HullIntersectResult hullIntersectsQuad(Quad curve) => cubic.hullIntersects(curve.points, Quad.kPointCount);
  @override
  _HullIntersectResult hullIntersectsConic(Conic curve) => curve.hullIntersectsQuad(Quad(curve.toPoints()));
  @override
  _HullIntersectResult hullIntersectsCubic(Cubic curve) => cubic.hullIntersects(curve.toPoints(), Cubic.kPointCount);
  @override
  _HullIntersectResult hullIntersects(TCurve curve) => curve.hullIntersectsCubic(cubic);
}

class TLine implements TCurve {
  final DLine line;
  TLine(this.line);
  @override
  ui.Offset operator [](int index) => ui.Offset(line.xAt(index), line.yAt(index));
  @override
  TCurve clone() => TLine(line.clone());
  @override
  bool collapsed() => throw UnsupportedError('');
  @override
  bool controlsInside() => throw UnsupportedError('');
  @override
  ui.Offset dxdyAtT(double t) => ui.Offset(line.x1 - line.x0, line.y1 - line.y0);
  @override
  int intersectRay(Intersections i, DLine ray) => i.intersectRayLine(line, ray);
  @override
  bool get isConic => false;
  @override
  int get maxIntersections => 0;
  @override
  void offset(int verb, ui.Offset offset) => line.offset(offset);
  @override
  Float32List otherPts(int oddMan) => throw UnsupportedError('');
  @override
  int get pointCount => 2;
  @override
  int get pointLast => 1;
  @override
  ui.Offset ptAtT(double t) => ui.Offset(line.x0 * (1 - t) + line.x1 * t,
      line.y0 * (1 - t) + line.y1 * t) ;
  @override
  void setPoint(int pointIndex, double x, double y) => line.setPoint(pointIndex, x, y);
  @override
  ui.Rect getTightBounds() => throw UnsupportedError('');
  @override
  TCurve subDivide(double t1, double t2) {
    double p1x = line.x0 * (1 - t1) + line.x1 * t1;
    double p1y = line.y0 * (1 - t1) + line.y1 * t1;
    double p2x = line.x0 * (1 - t2) + line.x1 * t2;
    double p2y = line.y0 * (1 - t2) + line.y1 * t2;
    return TLine(DLine(p1x, p1y, p2x, p2y));
  }
  @override
  _HullIntersectResult hullIntersectsQuad(Quad curve) =>
      throw UnsupportedError('');
  @override
  _HullIntersectResult hullIntersectsConic(Conic curve) => throw UnsupportedError('');
  @override
  _HullIntersectResult hullIntersectsCubic(Cubic curve) => throw UnsupportedError('');
  @override
  _HullIntersectResult hullIntersects(TCurve curve) => throw UnsupportedError('');
}

class _HullIntersectResult {
  _HullIntersectResult(this.success, this.isLinear);
  final bool success;
  final bool isLinear;
}

/// Provide 2 consecutive sweep vectors on curve.
class CurveSweep {
  CurveSweep(this.fCurve);
  TCurve fCurve;
  List<ui.Offset> fSweep = [ui.Offset.zero, ui.Offset.zero];

  bool fIsCurve = true;
  // Cleared when a cubic's control point isn't between the sweep vectors.
  bool fOrdered = true;

  /// True if sweep vectors are at least 16 ulps apart so we can reason
  /// about curve direction.
  bool isCurve() { return fIsCurve!; }
  bool isOrdered() { return fOrdered!; }

  void setCurveHullSweep(int verb) {
    fOrdered = true;
    fSweep[0] = fCurve[1] - fCurve[0];
    if (SPathVerb.kLine == verb) {
      fSweep[1] = fSweep[0];
      fIsCurve = false;
      return;
    }
    fSweep[1] = fCurve[2] - fCurve[0];
    // OPTIMIZE: I do the following float check a lot -- probably need a
    // central place for this val-is-small-compared-to-curve check
    double maxVal = 0;
    for (int index = 0; index <= pathOpsVerbToPoints(verb); ++index) {
      ui.Offset pt = fCurve[index];
      maxVal = math.max(maxVal, math.max(pt.dx.abs(), pt.dy.abs()));
    }

    if (SPathVerb.kCubic != verb) {
      if (roughlyZeroWhenComparedTo(fSweep[0].dx, maxVal)
            && roughlyZeroWhenComparedTo(fSweep[0].dy, maxVal)) {
        fSweep[0] = fSweep[1];
      }
      fIsCurve = crossCheck(fSweep[0], fSweep[1]) != 0;
      return;
    }
    // Handle cubic curve.
    ui.Offset thirdSweep = fCurve[3] - fCurve[0];
    if (fSweep[0].dx == 0 && fSweep[0].dy == 0) {
        fSweep[0] = fSweep[1];
        fSweep[1] = thirdSweep;
        if (roughlyZeroWhenComparedTo(fSweep[0].dx, maxVal)
                && roughlyZeroWhenComparedTo(fSweep[0].dy, maxVal)) {
          fSweep[0] = fSweep[1];
          // End point and first control point and roughly equal, force
          // equal.
          final ui.Offset p = fCurve[3];
          fCurve.setPoint(1, p.dx, p.dy);
        }
        fIsCurve = crossCheck(fSweep[0], fSweep[1]) != 0;
        return;
    }
    double s1x3 = crossCheck(fSweep[0], thirdSweep);
    double s3x2 = crossCheck(thirdSweep, fSweep[1]);
    if (s1x3 * s3x2 < 0) {
      // Check if third vector is not on or between first two vectors.
      double s2x1 = crossCheck(fSweep[1], fSweep[0]);
      assert(s1x3 * s2x1 < 0 || s1x3 * s3x2 < 0);
      if (s3x2 * s2x1 < 0) {
        assert(s2x1 * s1x3 > 0);
        fSweep[0] = fSweep[1];
        fOrdered = false;
      }
      fSweep[1] = thirdSweep;
    }
    fIsCurve = crossCheck(fSweep[0], fSweep[1]) != 0;
  }
}

// Similar to cross, considers nearly coincident to be zero using
// ulps epsilon == 16.
double crossCheck(ui.Offset a, ui.Offset b) {
  double xy = a.dx * b.dy;
  double yx = a.dy * b.dx;
  return almostEqualUlps(xy, yx) ? 0 : xy - yx;
}
