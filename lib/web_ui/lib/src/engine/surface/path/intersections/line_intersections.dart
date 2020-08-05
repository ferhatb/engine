// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

class LineQuadraticIntersections {
  final Intersections i;
  final Quad quad;
  final Float32List quadPoints;
  final DLine line;
  bool fAllowNear = false;

  LineQuadraticIntersections._(this.quad, this.quadPoints, this.line, this.i);

  factory LineQuadraticIntersections(Quad quad, DLine line, Intersections i)
    => LineQuadraticIntersections._(quad, quad.points, line, i);

  void allowNear(bool allow) {
    fAllowNear = allow;
  }

  void checkCoincident() {
    int last = i.fUsed - 1;
    for (int index = 0; index < last;) {
      double quadMidT = (i.fT0[index] + i.fT0[index + 1]) / 2;
      final ui.Offset quadMidPt = quad.ptAtT(quadMidT);
      double t = line.nearPoint(quadMidPt.dx, quadMidPt.dy);
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

  int intersectRay(List<double> roots) {
    assert(roots.length == 2);
    // solve by rotating line+quad so line is horizontal, then finding the roots
    // set up matrix to rotate quad to x-axis
    //      |cos(a) -sin(a)|
    //      |sin(a)  cos(a)|
    //      note that cos(a) = A(djacent) / Hypoteneuse
    //                sin(a) = O(pposite) / Hypoteneuse
    //      since we are computing Ts, we can ignore hypoteneuse, the scale factor:
    //      |  A     -O    |
    //      |  O      A    |
    //      A = line[1].fX - line[0].fX (adjacent side of the right triangle)
    //      O = line[1].fY - line[0].fY (opposite side of the right triangle)
    //      for each of the three points (e.g. n = 0 to 2)
    //      quad[n].fY' = (quad[n].fY - line[0].fY) * A - (quad[n].fX - line[0].fX) * O
    //
    double adj = line.x1 - line.x0;
    double opp = line.y1 - line.y0;
    double A = (quadPoints[1] - line.y0) * adj - (quadPoints[0] - line.x0) * opp;
    double B = (quadPoints[3] - line.y0) * adj - (quadPoints[2] - line.x0) * opp;
    double C = (quadPoints[5] - line.y0) * adj - (quadPoints[4] - line.x0) * opp;
    A += C - 2 * B;  // A = a - 2*b + c
    B -= C;  // B = -(b - c)
    return Quad.rootsValidT(A, 2 * B, C, roots);
  }

  int intersect() {
    _addExactEndPoints();
    if (fAllowNear) {
      _addNearEndPoints();
    }
    List<double> roots = [];
    int count = intersectRay(roots);
    for (int index = 0; index < count; ++index) {
      double quadT = roots[index];
      double lineT = findLineT(quadT);
      ui.Offset pt = quad.ptAtT(quadT);
      final _QuadPin quadPin = _QuadPin(this, quadT, lineT, pt, true);
      if (quadPin.pinned && uniqueAnswer(quadT, pt.dx, pt.dy)) {
        i.insert(quadT, lineT, pt.dx, pt.dy);
      }
    }
    checkCoincident();
    return i.fUsed;
  }

  double findLineT(double t) {
    ui.Offset xy = quad.ptAtT(t);
    double dx = line.x1 - line.x0;
    double dy = line.y1 - line.y0;
    if (dx.abs() > dy.abs()) {
      return (xy.dx - line.x0) / dx;
    }
    return (xy.dy - line.y0) / dy;
  }

  int horizontalIntersect(double axisIntercept, double left, double right, bool flipped) {
    _addExactHorizontalEndPoints(left, right, axisIntercept);
    if (fAllowNear) {
      _addNearHorizontalEndPoints(left, right, axisIntercept);
    }
    List<double> rootVals = [];
    int roots = computeHorizontalIntersect(axisIntercept, rootVals);
    for (int index = 0; index < roots; ++index) {
      double quadT = rootVals[index];
      ui.Offset pt = Quad(quadPoints).ptAtT(quadT);
      double lineT = (pt.dx - left) / (right - left);
      final _QuadPin quadPin = _QuadPin(this, quadT, lineT, pt, true);
      if (quadPin.pinned) {
        quadT = quadPin.quadT;
        lineT = quadPin.lineT;
        pt = quadPin.pt;
        if (isUniqueAnswer(quadT, pt)) {
          i.insert(quadT, lineT, pt.dx, pt.dy);
        }
      }
    }
    if (flipped) {
      i.flip();
    }
    checkCoincident();
    return i.fUsed;
  }

  int _verticalIntersect(double axisIntercept, List<double> roots) {
    double D = quadPoints[4];  // f
    double E = quadPoints[2];  // e
    double F = quadPoints[0];  // d
    D += F - 2 * E;         // D = d - 2*e + f
    E -= F;                 // E = -(d - e)
    F -= axisIntercept;
    return Quad.rootsValidT(D, 2 * E, F, roots);
  }

  int verticalIntersect(double axisIntercept, double top, double bottom, bool flipped) {
      _addExactVerticalEndPoints(top, bottom, axisIntercept);
      if (fAllowNear) {
          _addNearVerticalEndPoints(top, bottom, axisIntercept);
      }
      List<double> roots = [];
      int count = _verticalIntersect(axisIntercept, roots);
      for (int index = 0; index < count; ++index) {
        double quadT = roots[index];
        ui.Offset pt = quad.ptAtT(quadT);
        double lineT = (pt.dy - top) / (bottom - top);
        _CurveLinePinT pinResult = pinTs(quadT, lineT, pt.dx, pt.dy);
        pt = ui.Offset(pinResult.px, pinResult.py);
        quadT = pinResult.curveT;
        lineT = pinResult.lineT;
        if (pinResult.success && uniqueAnswer(quadT, pt.dx, pt.dy)) {
          i.insert(quadT, lineT, pt.dx, pt.dy);
        }
      }
      if (flipped) {
          i.flip();
      }
      checkCoincident();
      return i.fUsed;
  }

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
    if (lT == 0 || lT == 1) {
      result.px = line.ptAtTx(lT);;
      result.py = line.ptAtTy(lT);;
    } else if (qT != curveT) {
      ui.Offset qPt = quad.ptAtT(qT);
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
    if (i.fUsed > 0 && approximatelyEqualT(i.fT1[0], lineT)) {
      return result;
    }
    double p0x = quadPoints[0];
    double p0y = quadPoints[1];
    double p2x = quadPoints[4];
    double p2y = quadPoints[5];
    if (gridPx == p0x && gridPy == p0y) {
      result.px = p0x;
      result.py = p0y;
      result.curveT = 0;
    } else if (gridPx == p2x && gridPy == p2y) {
      result.px = p2x;
      result.py = p2y;
      result.curveT = 1;
    }
    return result;
  }

  /// Check if conicT or (existingT to conicT midpoint) is already in
  /// intersections within tolerance.
  bool uniqueAnswer(double cubicT, double px, double py) {
    for (int inner = 0; inner < i.fUsed; ++inner) {
      if (i.ptX[inner] != px || i.ptY[inner] != py) {
        continue;
      }
      double existingQuadT = i.fT0[inner];
      if (cubicT == existingQuadT) {
        return false;
      }
      // check if midway on conic is also same point. If so, discard this
      double quadMidT = (existingQuadT + cubicT) / 2;
      ui.Offset quadMidPt = quad.ptAtT(quadMidT);
      if (approximatelyEqualPoints(quadMidPt.dx, quadMidPt.dy, px, py)) {
        return false;
      }
    }
    return true;
  }

  // Add endpoints first to get zero and one t values exactly.
  void _addExactEndPoints() {
    for (int qIndex = 0; qIndex < Quad.kPointCount; qIndex += Quad.kPointLast) {
      final double px = quad.xAt(qIndex);
      final double py = quad.yAt(qIndex);
      double lineT = line.exactPoint(px, py);
      if (lineT < 0) {
        continue;
      }
      double cubicT = (qIndex >> 1).toDouble();
      i.insert(cubicT, lineT, px, py);
    }
  }

  /// Note that this does not look for endpoints of the line that are near the cubic.
  /// These points are found later when check ends looks for missing points.
  void _addNearEndPoints() {
    for (int cIndex = 0; cIndex < Quad.kPointCount; cIndex += Quad.kPointLast) {
      double curveT = (cIndex >> 1).toDouble();
      if (i.hasT(curveT)) {
        continue;
      }
      final double px = quad.xAt(cIndex);
      final double py = quad.yAt(cIndex);
      double lineT = line.nearPoint(px, py);
      if (lineT < 0) {
        continue;
      }
      i.insert(curveT, lineT, px, py);
    }
    _addLineNearEndPoints();
  }

  void _addLineNearEndPoints() {
    if (!i.hasOppT(0)) {
      double curveT = CurveDistance.nearPoint(
          quadPoints,
          SPathVerb.kQuad,
          1.0,
          line.x0,
          line.y0,
          line.x1,
          line.y1);
      if (curveT >= 0) {
        i.insert(curveT, 0, line.x0, line.y0);
      }
    }
    if (!i.hasOppT(1)) {
      double curveT = CurveDistance.nearPoint(
          quadPoints,
          SPathVerb.kQuad,
          1.0,
          line.x1,
          line.y1,
          line.x0,
          line.y0);
      if (curveT >= 0) {
        i.insert(curveT, 1, line.x1, line.y1);
      }
    }
  }

  void _addExactVerticalEndPoints(double top, double bottom, double x) {
    for (int qIndex = 0; qIndex < Quad.kPointCount; qIndex += Quad.kPointLast) {
      final double px = quad.xAt(qIndex);
      final double py = quad.yAt(qIndex);
      double lineT = DLine.exactPointV(px, py, top, bottom, x);
      if (lineT < 0) {
        continue;
      }
      double curveT = (qIndex >> 1).toDouble();
      i.insert(curveT, lineT, px, py);
    }
  }

  void _addNearVerticalEndPoints(double top, double bottom, double x) {
    for (int qIndex = 0; qIndex < Quad.kPointCount; qIndex += Quad.kPointLast) {
      double quadT = (qIndex >> 1).toDouble();
      if (i.hasT(quadT)) {
        continue;
      }
      final double px = quad.xAt(qIndex);
      final double py = quad.yAt(qIndex);
      double lineT = DLine.nearPointV(px, py, top, bottom, x);
      if (lineT < 0) {
        continue;
      }
      i.insert(quadT, lineT, px, py);
    }
    _addLineNearEndPoints();
  }

  /// Check if quadT and point already exists in intersections.
  bool isUniqueAnswer(double quadT, ui.Offset pt) {
    for (int inner = 0; inner < i.fUsed; ++inner) {
      if (i.ptX[inner] != pt.dx || i.ptY[inner] != pt.dy) {
        // Not same point, move to next.
        continue;
      }
      double existingQuadT = i.fT0[inner];
      if (quadT == existingQuadT) {
        // Already contains same point and t value, not unique.
        return false;
      }
      // Check if midway on quad is also same point. If so, discard this
      double quadMidT = (existingQuadT + quadT) / 2;
      final ui.Offset quadMidPt = Quad(quadPoints).ptAtT(quadMidT);
      if (approximatelyEqualD(quadMidPt.dx, quadMidPt.dy, pt.dx, pt.dy)) {
        return false;
      }
    }
    return true;
  }

  int computeHorizontalIntersect(double axisIntercept, List<double> roots) {
    double D = quadPoints[5];  // f
    double E = quadPoints[3];  // e
    double F = quadPoints[1];  // d
    D += F - 2 * E;         // D = d - 2*e + f
    E -= F;                 // E = -(d - e)
    F -= axisIntercept;
    return Quad.rootsValidT(D, 2 * E, F, roots);
  }

  void _addExactHorizontalEndPoints(double left, double right, double y) {
    for (int qIndex = 0; qIndex < 3; qIndex += 2) {
      double qx = quadPoints[qIndex * 2];
      double qy = quadPoints[qIndex * 2 + 1];
      double lineT = DLine.exactPointH(qx, qy, left, right, y);
      if (lineT < 0) {
        continue;
      }
      double quadT = (qIndex >> 1).toDouble();
      i.insert(quadT, lineT, qx, qy);
    }
  }

  void _addNearHorizontalEndPoints(double left, double right, double y) {
    for (int qIndex = 0; qIndex < 3; qIndex += 2) {
      double quadT = (qIndex >> 1).toDouble();
      if (i.hasT(quadT)) {
        continue;
      }
      final double qx = quadPoints[qIndex * 2];
      final double qy = quadPoints[qIndex * 2 + 1];
      double lineT = DLine.nearPointH(qx, qy, left, right, y);
      if (lineT < 0) {
        continue;
      }
      i.insert(quadT, lineT, qx, qy);
    }
    _addLineNearEndPoints();
  }
}

/// Pins quad and line end points on intersection and computes new pinned point.
class _QuadPin {
  _QuadPin._(this.quadT, this.lineT, this.pt, this.pinned);

  factory _QuadPin(LineQuadraticIntersections i,
      double quadT, double lineT, ui.Offset pt, bool pointInitialized) {
    if (!approximatelyOneOrLessDouble(lineT) || !approximatelyZeroOrMoreDouble(lineT)) {
      return _QuadPin._(quadT, lineT, pt, false);
    }
    double qT = quadT = pinT(quadT);
    double lT = lineT = pinT(lineT);
    if (lT == 0 || lT == 1 || (pointInitialized && qT != 0 && qT != 1)) {
      pt = ui.Offset(i.line.ptAtTx(lT), i.line.ptAtTy(lT));
    } else if (pointInitialized) {
      pt = Quad(i.quadPoints).ptAtT(qT);
    }
    if (approximatelyEqualD(pt.dx, pt.dy, i.line.x0, i.line.y0)) {
      pt = ui.Offset(i.line.x0, i.line.y0);
      lineT = 0;
    } else if (approximatelyEqualD(pt.dx, pt.dy, i.line.x1, i.line.y1)) {
      pt = ui.Offset(i.line.x1, i.line.y1);
      lineT = 1;
    }
    if (i.i.fUsed > 0 && approximatelyEqualT(i.i.fT1[0],
        lineT)) {
      return _QuadPin._(quadT, lineT, pt, false);
    }
    if (pt.dx == i.quadPoints[0] && pt.dy == i.quadPoints[1]) {
      pt = ui.Offset(i.quadPoints[0], i.quadPoints[1]);
      quadT = 0;
    } else if (pt.dx == i.quadPoints[4] && pt.dy == i.quadPoints[5]) {
      pt = ui.Offset(i.quadPoints[4], i.quadPoints[5]);
      quadT = 1;
    }
    return _QuadPin._(quadT, lineT, pt, true);
  }

  final ui.Offset pt;
  final bool pinned;
  final double lineT;
  final double quadT;
}

class LineConicIntersections {
  final Conic conic;
  final DLine line;
  final Intersections i;
  bool fAllowNear = true;

  LineConicIntersections(this.conic, this.line, this.i) {
    // Allow short partial coincidence plus discrete intersection.
    i.fMax = 4;
  }

  void allowNear(bool allow) {
    fAllowNear = allow;
  }

  void checkCoincident() {
    int last = i.fUsed - 1;
    for (int index = 0; index < last; ) {
      double conicMidT = (i.fT0[index] + i.fT0[index + 1]) / 2;
      ui.Offset conicMidPt = conic.ptAtT(conicMidT);
      double t = line.nearPoint(conicMidPt.dx, conicMidPt.dy);
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

  int _horizontalIntersect(double axisIntercept, List<double> roots) {
    return validT(conic.p0y, conic.p1y, conic.p2y, axisIntercept, roots);
  }

  /// Find T and roots for intersection at axis with conic.
  int validT(double r0, double r1, double r2, double axisIntercept, List<double> roots) {
    double A = r2;
    double B = r1 * conic.fW - axisIntercept * conic.fW + axisIntercept;
    double C = r0;
    A += C - 2 * B;  // A = a + c - 2*(b*w - xCept*w + xCept)
    B -= C;  // B = b*w - w * xCept + xCept - a
    C -= axisIntercept;
    return Quad.rootsValidT(A, 2 * B, C, roots);
  }

  /// For general line intersect with conic (non horizontal/vertical).
  int intersect() {
    _addExactEndPoints();
    if (fAllowNear) {
      _addNearEndPoints();
    }
    List<double> rootVals = [];
    int roots = intersectRay(rootVals);
    for (int index = 0; index < roots; ++index) {
      double conicT = rootVals[index];
      double lineT = findLineT(conicT);
      ui.Offset pt = conic.ptAtT(conicT);
      _CurveLinePinT pinResult = pinTs(conicT, lineT, pt.dx, pt.dy);
      pt = ui.Offset(pinResult.px, pinResult.py);
      conicT = pinResult.curveT;
      lineT = pinResult.lineT;
      if (pinResult.success && uniqueAnswer(conicT, pt.dx, pt.dy)) {
        i.insert(conicT, lineT, pt.dx, pt.dy);
      }
    }
    checkCoincident();
    return i.fUsed;
  }

  int intersectRay(List<double> roots) {
    final double lineX = line.x0;
    final double lineY = line.y0;
    double adj = line.x1 - lineX;
    double opp = line.y1 - lineY;
    double r0 = (conic.p0y - lineY) * adj - (conic.p0x - lineX) * opp;
    double r1 = (conic.p1y - lineY) * adj - (conic.p1x - lineX) * opp;
    double r2 = (conic.p2y - lineY) * adj - (conic.p2x - lineX) * opp;
    return validT(r0, r1, r2, 0, roots);
  }

  /// Given conic t, find t for line at same point.
  double findLineT(double t) {
    ui.Offset pt = conic.ptAtT(t);
    double dx = line.x1 - line.x0;
    double dy = line.y1 - line.y0;
    if (dx.abs() > dy.abs()) {
      return (pt.dx - line.x0) / dx;
    }
    return (pt.dy - line.y0) / dy;
  }

  /// Insert intersection given a line at [axisIntercept] from [left] to
  /// [right].
  int horizontalIntersect(double axisIntercept, double left, double right, bool flipped) {
    addExactHorizontalEndPoints(left, right, axisIntercept);
    if (fAllowNear) {
      addNearHorizontalEndPoints(left, right, axisIntercept);
    }
    List<double> roots = [];
    int count = _horizontalIntersect(axisIntercept, roots);
    for (int index = 0; index < count; ++index) {
      double conicT = roots[index];
      ui.Offset pt = conic.ptAtT(conicT);
      assert(closeTo(pt.dy, axisIntercept, conic.p0y, conic.p1y, conic.p2y));
      double lineT = (pt.dx - left) / (right - left);
      _CurveLinePinT pinResult = pinTs(conicT, lineT, pt.dx, pt.dy);
      pt = ui.Offset(pinResult.px, pinResult.py);
      conicT = pinResult.curveT;
      lineT = pinResult.lineT;
      if (pinResult.success && uniqueAnswer(conicT, pt.dx, pt.dy)) {
        i.insert(conicT, lineT, pt.dx, pt.dy);
      }
    }
    if (flipped) {
      i.flip();
    }
    checkCoincident();
    return i.fUsed;
  }

  int _verticalIntersect(double axisIntercept, List<double> roots) {
    return validT(conic.p0x, conic.p1x, conic.p2x, axisIntercept, roots);
  }

  int verticalIntersect(double axisIntercept, double top, double bottom, bool flipped) {
    addExactVerticalEndPoints(top, bottom, axisIntercept);
    if (fAllowNear) {
      addNearVerticalEndPoints(top, bottom, axisIntercept);
    }
    List<double> roots = [];
    int count = _verticalIntersect(axisIntercept, roots);
    for (int index = 0; index < count; ++index) {
      double conicT = roots[index];
      ui.Offset pt = conic.ptAtT(conicT);
      assert(closeTo(pt.dx, axisIntercept, conic.p0x, conic.p1x, conic.p2x));
      double lineT = (pt.dy - top) / (bottom - top);
      _CurveLinePinT pinResult = pinTs(conicT, lineT, pt.dx, pt.dy);
      pt = ui.Offset(pinResult.px, pinResult.py);
      conicT = pinResult.curveT;
      lineT = pinResult.lineT;
      if (pinResult.success && uniqueAnswer(conicT, pt.dx, pt.dy)) {
        i.insert(conicT, lineT, pt.dx, pt.dy);
      }
    }
    if (flipped) {
      i.flip();
    }
    checkCoincident();
    return i.fUsed;
  }

  void addExactVerticalEndPoints(double top, double bottom, double x) {
    for (int cIndex = 0; cIndex < Conic.kPointCount;
        cIndex += Conic.kPointLast) {
      final double px = conic.xAt(cIndex);
      final double py = conic.yAt(cIndex);
      double lineT = DLine.exactPointV(px, py, top, bottom, x);
      if (lineT < 0) {
        continue;
      }
      double conicT = (cIndex >> 1).toDouble();
      i.insert(conicT, lineT, px, py);
    }
  }

  void addNearVerticalEndPoints(double top, double bottom, double x) {
    for (int cIndex = 0; cIndex < Conic.kPointCount; cIndex += Conic.kPointLast) {
      double conicT = (cIndex >> 1).toDouble();
      if (i.hasT(conicT)) {
        continue;
      }
      final double px = conic.xAt(cIndex);
      final double py = conic.yAt(cIndex);
      double lineT = DLine.nearPointV(px, py, top, bottom, x);
      if (lineT < 0) {
        continue;
      }
      i.insert(conicT, lineT, px, py);
    }
    _addLineNearEndPoints();
  }

  void addExactHorizontalEndPoints(double left, double right, double y) {
    for (int cIndex = 0; cIndex < Conic.kPointCount; cIndex += Conic.kPointLast) {
      final double px = conic.xAt(cIndex);
      final double py = conic.yAt(cIndex);
      double lineT = DLine.exactPointH(px, py, left, right, y);
      if (lineT < 0) {
        continue;
      }
      double conicT = (cIndex >> 1).toDouble();
      i.insert(conicT, lineT, px, py);
    }
  }

  void addNearHorizontalEndPoints(double left, double right, double y) {
    for (int cIndex = 0; cIndex < Conic.kPointCount; cIndex += Conic.kPointLast) {
      double conicT = (cIndex >> 1).toDouble();
      if (i.hasT(conicT)) {
        continue;
      }
      final double px = conic.xAt(cIndex);
      final double py = conic.yAt(cIndex);
      double lineT = DLine.nearPointH(px, py, left, right, y);
      if (lineT < 0) {
        continue;
      }
      i.insert(conicT, lineT, px, py);
    }
    _addLineNearEndPoints();
  }

  void _addLineNearEndPoints() {
    if (!i.hasOppT(0)) {
      double conicT = CurveDistance.nearPoint(conic.toPoints(),
          SPathVerb.kConic, conic.fW, line.x0, line.y0, line.x1, line.y1);
      if (conicT >= 0) {
        i.insert(conicT, 0, line.x0, line.y0);
      }
    }
    if (!i.hasOppT(1)) {
      double conicT = CurveDistance.nearPoint(conic.toPoints(),
          SPathVerb.kConic, conic.fW, line.x1, line.y1, line.x0, line.y0);
      if (conicT >= 0) {
        i.insert(conicT, 1, line.x1, line.y1);
      }
    }
  }

  void _addExactEndPoints() {
    for (int cIndex = 0; cIndex < Conic.kPointCount;
    cIndex += Conic.kPointLast) {
      final double px = conic.xAt(cIndex);
      final double py = conic.yAt(cIndex);
      double lineT = line.exactPoint(px, py);
      if (lineT < 0) {
        continue;
      }
      double conicT = (cIndex >> 1).toDouble();
      i.insert(conicT, lineT, px, py);
    }
  }

  void _addNearEndPoints() {
    for (int cIndex = 0; cIndex < Conic.kPointCount; cIndex += Conic.kPointLast) {
      double conicT = (cIndex >> 1).toDouble();
      if (i.hasT(conicT)) {
        continue;
      }
      final double px = conic.xAt(cIndex);
      final double py = conic.yAt(cIndex);
      double lineT = line.nearPoint(px, py);
      if (lineT < 0) {
        continue;
      }
      i.insert(conicT, lineT, px, py);
    }
    _addLineNearEndPoints();
  }

  /// If point is close to end points of conic or line pin T values to 0 and 1.
  ///
  /// px,py should be initialized to point on curve at conicT.
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
    if (lT == 0 || lT == 1) {
      result.px = line.ptAtTx(lT);
      result.py = line.ptAtTy(lT);
    } else if (qT != curveT) {
      // Adjust to pinned T value.
      ui.Offset offset = conic.ptAtT(qT);
      result.px = offset.dx;
      result.py = offset.dy;
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
    if (i.fUsed > 0 && approximatelyEqualT(i.fT0[0], result.lineT)) {
      return result;
    }
    if (gridPx == conic.p0x && gridPy == conic.p0y) {
      result.px = conic.p0x;
      result.py = conic.p0y;
      result.curveT = 0;
    } else if (gridPx == conic.p2x && gridPy == conic.p2y) {
      result.px = conic.p2x;
      result.py = conic.p2y;
      result.curveT = 1;
    }
    result.success = true;
    return result;
  }

  /// Check if conicT or (existingT to conicT midpoint) is already in
  /// intersections within tolerance.
  bool uniqueAnswer(double conicT, double px, double py) {
    for (int inner = 0; inner < i.fUsed; ++inner) {
      if (i.ptX[inner] != px || i.ptY[inner] != py) {
        continue;
      }
      double existingConicT = i.fT0[inner];
      if (conicT == existingConicT) {
        return false;
      }
      // check if midway on conic is also same point. If so, discard this
      double conicMidT = (existingConicT + conicT) / 2;
      ui.Offset conicMidPt = conic.ptAtT(conicMidT);
      if (approximatelyEqualPoints(conicMidPt.dx, conicMidPt.dy, px, py)) {
        return false;
      }
    }
    return true;
  }

  /// Used to validate distance between points is zero taking into account
  /// magnitude of curve for debug builds.
  static bool closeTo(double a, double b, double c0, double c1, double c2) {
    double largest = math.max(-math.min(math.min(c0, c1), c2),
        math.max(math.max(c0, c1), c2));
    return approximatelyZeroWhenComparedTo(a - b, largest);
  }
}

class _CurveLinePinT {
  _CurveLinePinT(this.curveT, this.lineT, this.px, this.py);
  double px, py;
  double lineT;
  double curveT;
  bool success = false;
}

