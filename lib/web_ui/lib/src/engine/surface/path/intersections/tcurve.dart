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
  TCurve subDivide(double t1, double t2);

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
  Float32List otherPts(int oddMan) => quad.otherPts(oddMan);
  @override
  int get pointCount => Quad.kPointCount;
  @override
  int get pointLast => Quad.kPointLast;
  @override
  ui.Offset ptAtT(double t) => quad.ptAtT(t);
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
  bool collapsed() => conic.collapsed();
  bool controlsInside() => conic.controlsInside();
  ui.Offset dxdyAtT(double t) => conic.dxdyAtT(t);

  int intersectRay(Intersections i, DLine line) => i.intersectRayConic(conic, line);
  bool get isConic => true;
  int get maxIntersections => 4;
  Float32List otherPts(int oddMan) => conic.otherPts(oddMan);
  int get pointCount => Conic.kPointCount;
  int get pointLast => Conic.kPointLast;
  ui.Offset ptAtT(double t) => conic.ptAtT(t);

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
  Float32List otherPts(int oddMan) => cubic.otherPts(oddMan);
  @override
  int get pointCount => Cubic.kPointCount;
  @override
  int get pointLast => Cubic.kPointLast;
  @override
  ui.Offset ptAtT(double t) => cubic.ptAtT(t);
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

class _HullIntersectResult {
  _HullIntersectResult(this.success, this.isLinear);
  final bool success;
  final bool isLinear;
}
