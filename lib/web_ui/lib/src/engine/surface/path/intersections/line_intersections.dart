// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

class LineQuadraticIntersections {
  final Intersections intersections;
  final Float32List quadPoints;
  final DLine line;
  bool fAllowNear = false;

  LineQuadraticIntersections(this.quadPoints, this.line, this.intersections);

  void checkCoincident() {
    int last = intersections.fUsed - 1;
    Quad quad = Quad(quadPoints);
    for (int index = 0; index < last;) {
      double quadMidT = (intersections.fT0[index] + intersections.fT0[index + 1]) / 2;
      final ui.Offset quadMidPt = quad.ptAtT(quadMidT);
      double t = line.nearPoint(quadMidPt.dx, quadMidPt.dy);
      if (t < 0) {
        ++index;
        continue;
      }
      if (intersections.isCoincident(index)) {
        intersections.removeOne(index);
        --last;
      } else if (intersections.isCoincident(index + 1)) {
        intersections.removeOne(index + 1);
        --last;
      } else {
        intersections.setCoincident(index++);
      }
      intersections.setCoincident(index);
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

  int horizontalIntersect(double axisIntercept, double left, double right, bool flipped) {
    addExactHorizontalEndPoints(left, right, axisIntercept);
    if (fAllowNear) {
      addNearHorizontalEndPoints(left, right, axisIntercept);
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
          intersections.insert(quadT, lineT, pt.dx, pt.dy);
        }
      }
    }
    if (flipped) {
      intersections.flip();
    }
    checkCoincident();
    return intersections.fUsed;
  }

  /// Check if quadT and point already exists in intersections.
  bool isUniqueAnswer(double quadT, ui.Offset pt) {
    for (int inner = 0; inner < intersections.fUsed; ++inner) {
      if (intersections.ptX[inner] != pt.dx || intersections.ptY[inner] != pt.dy) {
        // Not same point, move to next.
        continue;
      }
      double existingQuadT = intersections.fT0[inner];
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

  void addLineNearEndPoints() {
    for (int lIndex = 0; lIndex < 2; ++lIndex) {
      double lineT = lIndex.toDouble();
      if (intersections.hasOppT(lineT)) {
        continue;
      }
      final double lineStartX = lIndex == 0 ? line.x0 : line.x1;
      final double lineStartY = lIndex == 0 ? line.y0 : line.y1;
      double quadT = lIndex == 0
          ? Curve.nearPoint(quadPoints, SPathVerb.kQuad, 1,
          lineStartX, lineStartY, line.x1, line.y1)
          : Curve.nearPoint(quadPoints, SPathVerb.kQuad, 1,
          lineStartX, lineStartY, line.x0, line.y0);
      if (quadT < 0) {
        continue;
      }
      intersections.insert(quadT, lineT, lineStartX, lineStartY);
    }
  }

  void addExactHorizontalEndPoints(double left, double right, double y) {
    for (int qIndex = 0; qIndex < 3; qIndex += 2) {
      double qx = quadPoints[qIndex * 2];
      double qy = quadPoints[qIndex * 2 + 1];
      double lineT = DLine.exactPointH(qx, qy, left, right, y);
      if (lineT < 0) {
        continue;
      }
      double quadT = (qIndex >> 1).toDouble();
      intersections.insert(quadT, lineT, qx, qy);
    }
  }

  void addNearHorizontalEndPoints(double left, double right, double y) {
    for (int qIndex = 0; qIndex < 3; qIndex += 2) {
      double quadT = (qIndex >> 1).toDouble();
      if (intersections.hasT(quadT)) {
        continue;
      }
      final double qx = quadPoints[qIndex * 2];
      final double qy = quadPoints[qIndex * 2 + 1];
      double lineT = DLine.nearPointH(qx, qy, left, right, y);
      if (lineT < 0) {
        continue;
      }
      intersections.insert(quadT, lineT, qx, qy);
    }
    addLineNearEndPoints();
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
    if (i.intersections.fUsed > 0 && approximatelyEqualT(i.intersections.fT1[0],
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
