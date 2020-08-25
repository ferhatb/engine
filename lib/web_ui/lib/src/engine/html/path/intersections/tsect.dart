// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10

part of engine;

const int kCoincidentSpanCount = 9;

/// Finds intersections between 2 curves (quadratic and cubic).
///
/// Usage:
///   TCubic cubic = TCubic(c);
///    TQuad quad = TQuad(q);
///    TSect sect1 = TSect(cubic);
///    TSect sect2 = TSect(quad);
///    TSect.binarySearch(sect1, sect2, this);
///
/// Adds intersections and coincidence results to [Intersections].
class TSect {
  TSect(TCurve c) : fCurve = c {
    fHead = addOne()
      ..init(c);
    if (assertionsEnabled) {
      debugInfo = _TSectDebug();
    }
  }

  TCurve fCurve;
  int fActiveCount = 0;
  bool fHung = false;
  TSpan? fHead;
  TSpan? fCoincident;
  // List of deleted [TSpan](s) for reuse or recovery (if collapsed).
  List<TSpan> deletedSpans = [];
  bool fRemovedStartT = false;
  bool fRemovedEndT = false;
  _TSectDebug? debugInfo;

  void resetRemovedEnds() {
    fRemovedStartT = fRemovedEndT = false;
  }

  /// Creates a new span by reusing a deleted span or allocating a new one.
  TSpan addOne() {
    TSpan result;
    // Reuse a delete TSpan is possible.
    if (deletedSpans.isNotEmpty) {
      result = deletedSpans.removeLast();
    } else {
      // Allocate new TSpan
      result = TSpan(fCurve);
    }
    result.reset();
    result.fHasPerp = false;
    result.fDeleted = false;
    ++fActiveCount;
    return result;
  }

  /// Add t for perpendicular.
  void addForPerp(TSpan span, double t) {
    if (!span.hasOppT(t)) {
      // Find span at t and prior.
      TSpan? priorSpan;
      TSpan? test = fHead;
      while (test != null && test.endT < t) {
        priorSpan = test;
        test = test.next;
      }
      TSpan? opp = test != null && test.startT <= t ? test : null;
      if (opp == null) {
        opp = addFollowing(priorSpan);
      }
      opp.addBounded(span);
      span.addBounded(opp);
    }
    validate();
  }

  /// Append to prior or insert before head.
  TSpan addFollowing(TSpan? prior) {
    TSpan result = addOne();
    result._fStartT = prior != null ? prior.endT : 0;
    TSpan? next = prior != null ? prior.next : fHead;
    result._fEndT = next != null ? next.startT : 1;
    result._fPrev = prior;
    result._fNext = next;
    if (prior != null) {
      prior._fNext = result;
    } else {
      fHead = result;
    }
    if (next != null) {
      next._fPrev = result;
    }
    result.resetBounds(fCurve);
    // World may not be consistent to call validate here
    result.validate();
    return result;
  }

  bool hasBounded(TSpan span) {
    TSpan? test = fHead;
    if (test == null) {
      return false;
    }
    do {
      if (test!.findOppSpan(span) != null) {
        return true;
      }
    } while ((test = test.next) != null);
    return false;
  }

  TSpan? boundsMax() {
    TSpan? test = fHead;
    TSpan largest = fHead!;
    bool lCollapsed = largest.collapsed;
    int safetyNet = 10000;
    while ((test = test!.next) != null) {
      if (--safetyNet == 0) {
        fHung = true;
        return null;
      }
      bool tCollapsed = test!.collapsed;
      if ((lCollapsed && !tCollapsed) || (lCollapsed == tCollapsed &&
        largest.fBoundsMax < test.fBoundsMax)) {
        largest = test;
        lCollapsed = test.collapsed;
      }
    }
    return largest;
  }

  ui.Offset get pointLast {
    return fCurve[fCurve.pointLast];
  }

  static void binarySearch(TSect sect1, TSect sect2,
      Intersections intersections) {
    assert(sect1.debugInfo!.fOppSect == sect2);
    assert(sect2.debugInfo!.fOppSect == sect1);
    intersections.reset();
    intersections.setMax(sect1.fCurve.maxIntersections + 4);  // Extra for slop
    TSpan span1 = sect1.fHead!;
    TSpan span2 = sect2.fHead!;
    List<int> res = sect1.intersects(span1, sect2, span2);
    int sect = res[0];
    int oppSect = res[1];
    assert(SPath.between(0, sect.toDouble(), 2));
    if (sect == HullCheckResult.kHullNoIntersection) {
      return;
    }
    if (sect == HullCheckResult.kHullOnlyCommonEndPoint &&
        oppSect == HullCheckResult.kHullOnlyCommonEndPoint) {
      endsEqual(sect1, sect2, intersections);
      return;
    }
    span1.addBounded(span2);
    span2.addBounded(span1);
    const int kMaxCoinLoopCount = 8;
    int coinLoopCount = kMaxCoinLoopCount;
    double start1s = 0;
    double start1e = 0;
    do {
      // Find the largest bounds
      TSpan? largest1 = sect1.boundsMax();
      if (largest1 == null) {
        if (sect1.fHung) {
          return;
        }
        break;
      }
      TSpan? largest2 = sect2.boundsMax();
      // split it
      if (largest2 == null ||
          (largest1 != null && (largest1.fBoundsMax > largest2.fBoundsMax
                || (!largest1.collapsed && largest2.collapsed)))) {
        if (sect2.fHung) {
          return;
        }
        if (largest1.collapsed) {
          break;
        }
        sect1.resetRemovedEnds();
        sect2.resetRemovedEnds();
        // trim parts that don't intersect the opposite
        TSpan half1 = sect1.addOne();
        if (!half1.split(largest1)) {
          break;
        }
        if (!sect1.trim(largest1, sect2)) {
          return;
        }
        if (!sect1.trim(half1, sect2)) {
          return;
        }
      } else {
        if (largest2.collapsed) {
          break;
        }
        sect1.resetRemovedEnds();
        sect2.resetRemovedEnds();
        // Trim parts that don't intersect the opposite.
        TSpan half2 = sect2.addOne();
        if (!half2.split(largest2)) {
            break;
        }
        if (!sect2.trim(largest2, sect1)) {
          return;
        }
        if (!sect2.trim(half2, sect1)) {
          return;
        }
      }
      sect1.validate();
      sect2.validate();
      // If there are 9 or more continuous spans on both sects, suspect
      // coincidence
      if (sect1.fActiveCount >= kCoincidentSpanCount
          && sect2.fActiveCount >= kCoincidentSpanCount) {
        if (coinLoopCount == kMaxCoinLoopCount) {
          start1s = sect1.fHead!.startT;
          start1e = sect1.tail()!.endT;
        }
        if (!sect1.coincidentCheck(sect2)) {
          return;
        }
        sect1.validate();
        sect2.validate();
        if ((--coinLoopCount) != 0 && sect1.fHead != null && sect2.fHead != null) {
          // All known working cases resolve in two tries. Sadly,
          // cubicConicTests[0] gets stuck in a loop. It adds an extension to
          // allow a coincident end perpendicular to track its intersection in
          // the opposite curve. However, the bounding box of the extension
          // does not intersect the original curve, so the extension is
          // discarded, only to be added again the next time around.
          sect1.coincidentForce(sect2, start1s, start1e);
          sect1.validate();
          sect2.validate();
        }
      }
      if (sect1.fActiveCount >= kCoincidentSpanCount
          && sect2.fActiveCount >= kCoincidentSpanCount) {
        if (sect1.fHead == null) {
          return;
        }
        sect1.computePerpendiculars(sect2, sect1.fHead!, sect1.tail());
        if (sect2.fHead == null) {
          return;
        }
        sect2.computePerpendiculars(sect1, sect2.fHead!, sect2.tail());
        if (!sect1.removeByPerpendicular(sect2)) {
          return;
        }
        sect1.validate();
        sect2.validate();
        if (sect1.collapsed() > sect1.fCurve.maxIntersections) {
          break;
        }
      }
      if (sect1.fHead == null || sect2.fHead == null) {
        break;
      }
    } while (true);
    TSpan? coincident = sect1.fCoincident;
    if (coincident != null) {
      // If there is more than one coincident span, check loosely to see if
      // they should be joined.
      if (coincident.next != null) {
          sect1._mergeCoincidence(sect2);
          coincident = sect1.fCoincident;
      }
      assert(sect2.fCoincident != null);  // courtesy check : coincidence only looks at sect 1
      do {
        if (coincident == null) {
          return;
        }
        if (!coincident.fCoinStart.isMatch) {
          continue;
        }
        if (!coincident.fCoinEnd.isMatch) {
          continue;
        }
        double perpT = coincident.fCoinStart.perpT;
        if (perpT < 0) {
          return;
        }
        int index = intersections.insertCoincident(coincident.startT,
            perpT, coincident.pointFirst);
        if ((intersections.insertCoincident(coincident.endT,
            coincident.fCoinEnd.perpT, coincident.pointLast) < 0) &&
            index >= 0) {
          intersections.clearCoincidence(index);
        }
      } while ((coincident = coincident.next) != null);
    }
    int zeroOneSet = endsEqual(sect1, sect2, intersections);
    // if the final iteration contains an end (0 or 1),
    if (sect1.fRemovedStartT && (zeroOneSet & kFirstS1Set) == 0) {
      // Intersect perpendicular with opposite curve.
      TCoincident perp = TCoincident();
      perp.setPerp(sect1.fCurve, 0, sect1.fCurve[0], sect2.fCurve);
      if (perp.isMatch) {
        intersections.insert(0, perp.perpT, perp.perpPt.dx, perp.perpPt.dy);
      }
    }
    if (sect1.fRemovedEndT && (zeroOneSet & kLastS1Set) == 0) {
        TCoincident perp = TCoincident();
        perp.setPerp(sect1.fCurve, 1, sect1.pointLast, sect2.fCurve);
        if (perp.isMatch) {
          intersections.insert(1, perp.perpT, perp.perpPt.dx, perp.perpPt.dy);
        }
    }
    if (sect2.fRemovedStartT && (zeroOneSet & kFirstS2Set) == 0) {
        TCoincident perp = TCoincident();
        perp.setPerp(sect2.fCurve, 0, sect2.fCurve[0], sect1.fCurve);
        if (perp.isMatch) {
          intersections.insert(perp.perpT, 0, perp.perpPt.dx, perp.perpPt.dy);
        }
    }
    if (sect2.fRemovedEndT && (zeroOneSet & kLastS2Set) == 0) {
        TCoincident perp = TCoincident();
        perp.setPerp(sect2.fCurve, 1, sect2.pointLast, sect1.fCurve);
        if (perp.isMatch) {
            intersections.insert(perp.perpT, 1, perp.perpPt.dx, perp.perpPt.dy);
        }
    }
    if (sect1.fHead == null || sect2.fHead == null) {
      return;
    }
    sect1.recoverCollapsed();
    sect2.recoverCollapsed();
    TSpan? result1 = sect1.fHead;
    // check heads and tails for zero and ones and insert them if we haven't already done so
    TSpan? head1 = result1;
    if ((zeroOneSet & kFirstS1Set) == 0 && approximatelyLessThanZero(head1!.startT)) {
      ui.Offset start1 = sect1.fCurve[0];
      if (head1.isBounded) {
        double t = head1.closestBoundedT(start1);
        ui.Offset pt = sect2.fCurve.ptAtT(t);
        if (approximatelyEqualPoints(pt.dx, pt.dy, start1.dx, start1.dy)) {
          intersections.insert(0, t, start1.dx, start1.dy);
        }
      }
    }
    TSpan head2 = sect2.fHead!;
    if ((zeroOneSet & kFirstS2Set) == 0 && approximatelyLessThanZero(head2.startT)) {
      ui.Offset start2 = sect2.fCurve[0];
      if (head2.isBounded) {
        double t = head2.closestBoundedT(start2);
        ui.Offset pt = sect1.fCurve.ptAtT(t);
        if (approximatelyEqualPoints(pt.dx, pt.dy, start2.dx, start2.dy)) {
            intersections.insert(t, 0, start2.dx, start2.dy);
        }
      }
    }
    if ((zeroOneSet & kLastS1Set) == 0) {
      TSpan? tail1 = sect1.tail();
      if (tail1 == null) {
        return;
      }
      if (approximatelyGreaterThanOne(tail1.endT)) {
        ui.Offset end1 = sect1.pointLast;
        if (tail1.isBounded) {
            double t = tail1.closestBoundedT(end1);
            ui.Offset pt = sect2.fCurve.ptAtT(t);
            if (approximatelyEqualPoints(pt.dx, pt.dy, end1.dx, end1.dy)) {
                intersections.insert(1, t, end1.dx, end1.dy);
            }
        }
      }
    }
    if ((zeroOneSet & kLastS2Set) == 0) {
      TSpan? tail2 = sect2.tail();
      if (tail2 == null) {
        return;
      }
      if (approximatelyGreaterThanOne(tail2.endT)) {
        ui.Offset end2 = sect2.pointLast;
        if (tail2.isBounded) {
          double t = tail2.closestBoundedT(end2);
          ui.Offset pt = sect1.fCurve.ptAtT(t);
          if (approximatelyEqualPoints(pt.dx, pt.dy, end2.dx, end2.dy)) {
            intersections.insert(t, 1, end2.dx, end2.dy);
          }
        }
      }
    }
    ClosestSect closest = ClosestSect();
    do {
      while (result1 != null && result1.fCoinStart.isMatch && result1.fCoinEnd.isMatch) {
        result1 = result1.next;
      }
      if (result1 == null) {
          break;
      }
      TSpan? result2 = sect2.fHead;
      bool found = false;
      while (result2 != null) {
        found |= closest.find(result1, result2);
        result2 = result2.next;
      }
    } while ((result1 = result1.next) != null);
    closest.finish(intersections);
    // if there is more than one intersection and it isn't already coincident,
    // check.
    int last = intersections.fUsed - 1;
    for (int index = 0; index < last; ) {
      if (intersections.isCoincident(index) && intersections.isCoincident(index + 1)) {
        ++index;
        continue;
      }
      double midT = (intersections.fT0[index] + intersections.fT0[index + 1]) / 2;
      ui.Offset midPt = sect1.fCurve.ptAtT(midT);
      // intersect perpendicular with opposite curve
      TCoincident perp = TCoincident();
      perp.setPerp(sect1.fCurve, midT, midPt, sect2.fCurve);
      if (!perp.isMatch) {
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
    assert(intersections.fUsed <= sect1.fCurve.maxIntersections);
  }

  /// Checks if [span] hull intersects opposite span.
  List<int> intersects(TSpan span, TSect opp, TSpan oppSpan) {
    int oppResult = 0;
    HullCheckResult result = HullCheckResult();
    int hullResult = span.hullsIntersect(oppSpan, result);
    if (hullResult != HullCheckResult.kHullIsLinear) {
      if (hullResult == HullCheckResult.kHullOnlyCommonEndPoint) {
        // One point in common.
        if (span.fBounded == null || span.fBounded!.next == null) {
          assert(span.fBounded == null || span.fBounded!.fBounded == oppSpan);
          if (result.start) {
            span._fEndT = span._fStartT;
          } else {
            span._fStartT = span._fEndT;
          }
        } else {
          hullResult = HullCheckResult.kHullIntersects;
        }
        if (oppSpan.fBounded == null || oppSpan.fBounded?.next == null) {
          if (oppSpan.fBounded != null && oppSpan.fBounded!.fBounded != span) {
            return [0, oppResult];
          }
          if (result.oppStart) {
            oppSpan._fEndT = oppSpan._fStartT;
          } else {
            oppSpan._fStartT = oppSpan._fEndT;
          }
          oppResult = HullCheckResult.kHullOnlyCommonEndPoint;
        } else {
          oppResult = HullCheckResult.kHullIntersects;
        }
      } else {
        oppResult = HullCheckResult.kHullIntersects;
      }
      return [hullResult, oppResult];
    }
    /// Handle linear.
    if (span.fIsLine && oppSpan.fIsLine) {
        Intersections i = Intersections();
        int sects = linesIntersect(span, opp, oppSpan, i);
        if (sects == 2) {
          return [HullCheckResult.kHullIntersects,
            HullCheckResult.kHullIntersects];
        }
        if (sects != 0) {
          return [HullCheckResult.kHullIsLinear, oppResult];
        }
        // Reduce to start only, remove end point.
        _removedEndCheck(span);
        span._fStartT = span._fEndT = i.fT0[0];
        opp._removedEndCheck(oppSpan);
        oppSpan._fStartT = oppSpan._fEndT = i.fT1[0];
        return [HullCheckResult.kHullOnlyCommonEndPoint,
          HullCheckResult.kHullOnlyCommonEndPoint];
    }
    if (span.fIsLinear || oppSpan.fIsLinear) {
      int sects = span.linearsIntersect(oppSpan) ?
        HullCheckResult.kHullIntersects : HullCheckResult.kHullNoIntersection;
      return [sects, sects];
    }
    return [HullCheckResult.kHullIntersects,
        HullCheckResult.kHullIntersects];
  }

  // While the intersection points are sufficiently far apart:
  // construct the tangent lines from the intersections
  // find the point where the tangent line intersects the opposite curve
  int linesIntersect(TSpan span, TSect opp, TSpan oppSpan, Intersections i) {
    Intersections thisRayI = Intersections();
    Intersections oppRayI = Intersections();
    ui.Offset p0 = span.pointFirst;
    ui.Offset p1 = span.pointLast;
    DLine thisLine = DLine(p0.dx, p0.dy, p1.dx, p1.dy);
    p0 = oppSpan.pointFirst;
    p1 = oppSpan.pointLast;
    DLine oppLine = DLine(p0.dx, p0.dy, p1.dx, p1.dy);
    int loopCount = 0;
    double bestDistSq = double.maxFinite;
    if (opp.fCurve.intersectRay(thisRayI, thisLine) == 0) {
      return 0;
    }
    if (fCurve.intersectRay(oppRayI, oppLine) == 0) {
      return 0;
    }
    // If the ends of each line intersect the opposite curve,
    // the lines are coincident.
    if (thisRayI.fUsed > 1) {
      int ptMatches = 0;
      for (int tIndex = 0; tIndex < thisRayI.fUsed; ++tIndex) {
        for (int lIndex = 0; lIndex < DLine.kPointCount; ++lIndex) {
          if (approximatelyEqualPoints(thisRayI.ptX[tIndex], thisRayI.ptY[tIndex],
              thisLine.xAt(lIndex), thisLine.yAt(lIndex))) {
            ++ptMatches;
          }
        }
      }
      // !This optimization only works for opp conic for now.
      if (ptMatches == 2 || TCurve.isParallel(thisLine, opp.fCurve)) {
        return 2;
      }
    }
    if (oppRayI.fUsed > 1) {
      int ptMatches = 0;
      for (int oIndex = 0; oIndex < oppRayI.fUsed; ++oIndex) {
        for (int lIndex = 0; lIndex < DLine.kPointCount; ++lIndex) {
          if (approximatelyEqualPoints(
              oppRayI.ptX[oIndex], oppRayI.ptY[oIndex],
              oppLine.xAt(lIndex), oppLine.yAt(lIndex))) {
            ++ptMatches;
          }
        }
      }
      // !This optimization only works for opp conic for now.
      if (ptMatches == 2 || TCurve.isParallel(oppLine, fCurve)) {
          return 2;
      }
    }
    do {
      // pick the closest pair of points
      double closest = double.maxFinite;
      int closeIndex = 0;
      int oppCloseIndex = 0;
      for (int index = 0; index < oppRayI.fUsed; ++index) {
          if (!roughlyBetween(span.startT, oppRayI.fT0[index], span.endT)) {
            continue;
          }
          for (int oIndex = 0; oIndex < thisRayI.fUsed; ++oIndex) {
              if (!roughlyBetween(oppSpan.startT, thisRayI.fT0[oIndex], oppSpan.endT)) {
                  continue;
              }
              double distSq = distanceSquared(thisRayI.ptX[index],
                  thisRayI.ptY[index], oppRayI.ptX[oIndex], oppRayI.ptY[oIndex]);
              if (closest > distSq) {
                  closest = distSq;
                  closeIndex = index;
                  oppCloseIndex = oIndex;
              }
          }
      }
      if (closest == double.maxFinite) {
        break;
      }
      final double oppIPtX = thisRayI.ptX[oppCloseIndex];
      final double oppIPtY = thisRayI.ptY[oppCloseIndex];
      final double iPtX = oppRayI.ptX[closeIndex];
      final double iPtY = oppRayI.ptY[closeIndex];
      if (SPath.between(span.startT, oppRayI.fT0[closeIndex], span.endT)
              && SPath.between(oppSpan.startT, thisRayI.fT0[oppCloseIndex], oppSpan.endT)
              && approximatelyEqualPoints(oppIPtX, oppIPtY, iPtX, iPtY)) {
        i.merge(oppRayI, closeIndex, thisRayI, oppCloseIndex);
        return i.fUsed;
      }
      double distSq = distanceSquared(oppIPtX, oppIPtY, iPtX, iPtY);
      if (bestDistSq < distSq || ++loopCount > 5) {
          return 0;
      }
      bestDistSq = distSq;
      double oppStart = oppRayI.fT0[closeIndex];
      ui.Offset startP = fCurve.ptAtT(oppStart);
      ui.Offset slope = fCurve.dxdyAtT(oppStart);
      thisLine = DLine(startP.dx, startP.dy, startP.dx + slope.dx, startP.dy + slope.dy);
      if (0 == opp.fCurve.intersectRay(thisRayI, thisLine)) {
        break;
      }
      double start = thisRayI.fT0[oppCloseIndex];
      startP = opp.fCurve.ptAtT(start);
      slope = opp.fCurve.dxdyAtT(start);
      oppLine = DLine(startP.dx, startP.dy, startP.dx + slope.dx, startP.dy + slope.dy);
      if (0 == fCurve.intersectRay(oppRayI, oppLine)) {
        break;
      }
    } while (true);
    // Convergence may fail if the curves are nearly coincident.
    TCoincident oCoinS = TCoincident();
    TCoincident oCoinE = TCoincident();
    oCoinS.setPerp(opp.fCurve, oppSpan.startT, oppSpan.pointFirst, fCurve);
    oCoinE.setPerp(opp.fCurve, oppSpan.endT, oppSpan.pointLast, fCurve);
    double tStart = oCoinS.perpT;
    double tEnd = oCoinE.perpT;
    bool swap = tStart > tEnd;
    if (swap) {
      double temp = tEnd;
      tEnd = tStart;
      tStart = temp;
    }
    tStart = math.max(tStart, span.startT);
    tEnd = math.min(tEnd, span.endT);
    if (tStart > tEnd) {
      return 0;
    }
    ui.Offset perpS, perpE;
    if (tStart == span.startT) {
      TCoincident coinS = TCoincident();
      coinS.setPerp(fCurve, span.startT, span.pointFirst, opp.fCurve);
      perpS = span.pointFirst - coinS.perpPt;
    } else if (swap) {
      perpS = oCoinE.perpPt - oppSpan.pointLast;
    } else {
      perpS = oCoinS.perpPt - oppSpan.pointFirst;
    }
    if (tEnd == span.endT) {
      TCoincident coinE = TCoincident();
      coinE.setPerp(fCurve, span.endT, span.pointLast, opp.fCurve);
      perpE = span.pointLast - coinE.perpPt;
    } else if (swap) {
      perpE = oCoinS.perpPt - oppSpan.pointFirst;
    } else {
      perpE = oCoinE.perpPt - oppSpan.pointLast;
    }
    double dotProd = perpS.dx * perpE.dx + perpS.dy * perpE.dy;
    if (dotProd >= 0) {
      // Perpendicular lines have acute angle
      return 0;
    }
    TCoincident coinW = TCoincident();
    double workT = tStart;
    double tStep = tEnd - tStart;
    ui.Offset? workPt;
    do {
      tStep *= 0.5;
      if (preciselyZero(tStep)) {
        return 0;
      }
      workT += tStep;
      workPt = fCurve.ptAtT(workT);
      coinW.setPerp(fCurve, workT, workPt, opp.fCurve);
      double perpT = coinW.perpT;
      if (coinW.isMatch ? !SPath.between(oppSpan.startT, perpT, oppSpan.endT)
          : perpT < 0) {
          continue;
      }
      ui.Offset perpW = workPt - coinW.perpPt;
      double dotSW = perpS.dx * perpW.dx + perpS.dy * perpW.dy;
      if ((dotSW >= 0) == (tStep < 0)) {
        tStep = -tStep;
      }
      ui.Offset pt = coinW.perpPt;
      if (approximatelyEqualPoints(workPt.dx, workPt.dy, pt.dx, pt.dy)) {
        break;
      }
    } while (true);
    double oppTTest = coinW.perpT;
    if (!opp.fHead!.contains(oppTTest)) {
      return 0;
    }
    i.setMax(1);
    i.insert(workT, oppTTest, workPt.dx, workPt.dy);
    return 1;
  }

  static const int kFirstS1Set = 1;
  static const int kLastS1Set = 2;
  static const int kFirstS2Set = 4;
  static const int kLastS2Set = 8;

  /// If first or last points are equal inserts points, if they are not
  /// equal but close uses [insertNear] to insert [sect1] but marks it near
  /// opposing.
  static int endsEqual(TSect sect1, TSect sect2, Intersections intersections) {
    int zeroOneSet = 0;
    ui.Offset sect1P0 = sect1.fCurve[0];
    ui.Offset sect2P0 = sect2.fCurve[0];
    ui.Offset pointLast1 = sect1.pointLast;
    ui.Offset pointLast2 = sect2.pointLast;
    if (sect1P0 == sect2P0) {
      zeroOneSet |= kFirstS1Set | kFirstS2Set;
      intersections.insertAtOffset(0, 0, sect1P0);
    }
    if (sect1P0 == pointLast2) {
      zeroOneSet |= kFirstS1Set | kLastS2Set;
      intersections.insertAtOffset(0, 1, sect1P0);
    }
    if (pointLast1 == sect2P0) {
      zeroOneSet |= kLastS1Set | kFirstS2Set;
      intersections.insertAtOffset(1, 0, sect1.pointLast);
    }
    if (pointLast1 == sect2.pointLast) {
      zeroOneSet |= kLastS1Set | kLastS2Set;
      intersections.insertAtOffset(1, 1, sect1.pointLast);
    }
    // check for zero
    if ((zeroOneSet & (kFirstS1Set | kFirstS2Set)) == 0
        && approximatelyEqualPoints(sect1P0.dx, sect1P0.dy, sect2P0.dx, sect2P0.dy)) {
      zeroOneSet |= kFirstS1Set | kFirstS2Set;
      intersections.insertNear(0, 0, sect1P0.dx, sect1P0.dy, sect2P0.dx, sect2P0.dy);
    }
    if ((zeroOneSet & (kFirstS1Set | kLastS2Set)) == 0
    && approximatelyEqualPoints(sect1P0.dx, sect1P0.dy, pointLast2.dx, pointLast2.dy)) {
      zeroOneSet |= kFirstS1Set | kLastS2Set;
      intersections.insertNear(0, 1, sect1P0.dx, sect1P0.dy, pointLast2.dx, pointLast2.dy);
    }
    // check for one
    if ((zeroOneSet & (kLastS1Set | kFirstS2Set)) == 0
        && approximatelyEqualPoints(pointLast1.dx, pointLast1.dy, sect2P0.dx, sect2P0.dy)) {
      zeroOneSet |= kLastS1Set | kFirstS2Set;
      intersections.insertNear(1, 0, pointLast1.dx, pointLast1.dy, sect2P0.dx, sect2P0.dy);
    }
    if ((zeroOneSet & (kLastS1Set | kLastS2Set)) == 0
        && approximatelyEqualPoints(pointLast1.dx, pointLast1.dy, pointLast2.dx, pointLast2.dy)) {
      zeroOneSet |= kLastS1Set | kLastS2Set;
      intersections.insertNear(1, 1, pointLast1.dx, pointLast1.dy, pointLast2.dx, pointLast2.dy);
    }
    return zeroOneSet;
  }


  /// Each span has a range of opposite spans it intersects.
  /// After the span is split in two, adjust the range to its new size.
  bool trim(TSpan span, TSect opp) {
    if (!span.initBounds(fCurve)) {
      assert(false);
      return false;
    }
    _TSpanBounded? testBounded = span.fBounded;
    while (testBounded != null) {
      TSpan test = testBounded.fBounded;
      _TSpanBounded? next = testBounded.next;
      List<int> res = intersects(span, opp, test);
      int sects = res[0];
      int oppSects = res[1];
      if (sects >= 1) {
        if (oppSects == 2) {
          test.initBounds(opp.fCurve);
          opp.removeAllBut(span, test, this);
        }
        if (sects == 2) {
          span.initBounds(fCurve);
          this.removeAllBut(test, span, opp);
          return true;
        }
      } else {
        if (span.removeBounded(test)) {
          this._removeSpan(span);
        }
        if (test.removeBounded(span)) {
          opp._removeSpan(test);
        }
      }
      testBounded = next;
    }
    return true;
  }

  bool _removeSpan(TSpan span) {
    _removedEndCheck(span);
    if (!_unlinkSpan(span)) {
      return false;
    }
    return _markSpanGone(span);
  }

  void removeAllBut(TSpan keep, TSpan span, TSect opp) {
    _TSpanBounded? testBounded = span.fBounded;
    while (testBounded != null) {
      TSpan bounded = testBounded.fBounded;
      _TSpanBounded? next = testBounded.next;
      // may have been deleted when opp did 'remove all but'
      if (bounded != keep && !bounded.fDeleted) {
        span.removeBounded(bounded);
        if (bounded.removeBounded(span)) {
          opp._removeSpan(bounded);
        }
      }
      testBounded = next;
    }
    assert(!span.fDeleted);
    assert(span.findOppSpan(keep) != null);
    assert(keep.findOppSpan(span) != null);
  }

  bool _unlinkSpan(TSpan span) {
    TSpan? prev = span._fPrev;
    TSpan? next = span._fNext;
    if (prev != null) {
      prev._fNext = next;
      if (next != null) {
        next._fPrev = prev;
        if (next.startT > next.endT) {
          return false;
        }
        next.validate();
      }
    } else {
      fHead = next;
      if (next != null) {
        next._fPrev = null;
      }
    }
    return true;
  }

  /// Recycles span to be used for later allocations.
  bool _markSpanGone(TSpan span) {
    if (--fActiveCount < 0) {
      return false;
    }
    deletedSpans.add(span);
    assert(!span.fDeleted);
    span.fDeleted = true;
    return true;
  }

  /// Update fRemoveStartT/endT flags when a span is removed.
  void _removedEndCheck(TSpan span) {
    if (span.startT == 0) {
      fRemovedStartT = true;
    }
    if (1 == span.endT) {
      fRemovedEndT = true;
    }
  }

  void validate() {
    int count = 0;
    double last = 0;
    if (fHead != null) {
      TSpan? span = fHead;
      assert(span!._fPrev == null);
      TSpan? next;
      do {
        span!.validate();
        assert(span.startT >= last);
        last = span.endT;
        ++count;
        next = span.next;
        assert(next != span);
      } while ((span = next) != null);
    }
    assert(count == fActiveCount);
  }

  TSpan? tail() {
    TSpan result = fHead!;
    TSpan? next = fHead;
    int safetyNet = 100000;
    while ((next = next!.next) != null) {
      if (--safetyNet != 0) {
        return null;
      }
      if (next!.endT > result.endT) {
        result = next;
      }
    }
    return result;
  }

  bool coincidentCheck(TSect sect2) {
    TSpan? first = fHead;
    if (first == null) {
      return false;
    }
    TSpan? last, next;
    do {
        /// Count number of spans with consecutive t ranges (no gaps).
        int consecutive = 1;
        last = first;
        do {
          TSpan? next = last?.next;
          if (next == null) {
            break;
          }
          if (next.startT > last!.endT) {
            // Found gap, break.
            break;
          }
          ++consecutive;
          last = next;
        } while (true);
        // Move to next consecutive range.
        next = last!.next;
        // Skip if larger than max coincident spans.
        if (consecutive < kCoincidentSpanCount) {
          continue;
        }
        validate();
        sect2.validate();
        computePerpendiculars(sect2, first!, last);
        this.validate();
        sect2.validate();
        // Check to see if a range of points are on the curve.
        TSpan? coinStart = first;
        do {
          _CoincidentResult res = extractCoincident(sect2, coinStart, last);
          if (!res.success) {
            return false;
          }
          coinStart = res.coin;
        } while (coinStart != null && !last.fDeleted);
        if (fHead == null || sect2.fHead == null) {
          break;
        }
        if (next == null || next.fDeleted) {
          break;
        }
    } while ((first = next) != null);
    return true;
  }

  void coincidentForce(TSect sect2, double start1s, double start1e) {
    TSpan first = fHead!;
    TSpan? last = tail();
    TSpan oppFirst = sect2.fHead!;
    TSpan? oppLast = sect2.tail();
    if (last == null || oppLast == null) {
      return;
    }
    bool deleteEmptySpans = updateBounded(first, last, oppFirst);
    deleteEmptySpans |= sect2.updateBounded(oppFirst, oppLast, first);
    _removeSpanRange(first, last);
    sect2._removeSpanRange(oppFirst, oppLast);
    first._fStartT = start1s;
    first._fEndT = start1e;
    first.resetBounds(fCurve);
    first.fCoinStart.setPerp(fCurve, start1s, fCurve[0], sect2.fCurve);
    first.fCoinEnd.setPerp(fCurve, start1e, pointLast, sect2.fCurve);
    bool oppMatched = first.fCoinStart.perpT < first.fCoinEnd.perpT;
    double oppStartT = first.fCoinStart.perpT == -1 ? 0 : math.max(0, first.fCoinStart.perpT);
    double oppEndT = first.fCoinEnd.perpT == -1 ? 1 : math.min(1, first.fCoinEnd.perpT);
    if (!oppMatched) {
      double temp = oppStartT;
      oppStartT = oppEndT;
      oppEndT = temp;
    }
    oppFirst._fStartT = oppStartT;
    oppFirst._fEndT = oppEndT;
    oppFirst.resetBounds(sect2.fCurve);
    removeCoincident(first, false);
    sect2.removeCoincident(oppFirst, true);
    if (deleteEmptySpans) {
      _deleteEmptySpans();
      sect2._deleteEmptySpans();
    }
  }

  _CoincidentResult extractCoincident(TSect sect2, TSpan? first, TSpan? last) {
    _FindCoincidentResult res = findCoincidentRun(first, last);
    first = res.first;
    last = res.last;
    if (first == null || last == null) {
      return _CoincidentResult(true, null);
    }
    // March outwards to find limit of coincidence from here to previous and
    // next spans.
    double startT = first.startT;
    double oppStartT = 0;
    double oppEndT = 0;
    TSpan? prev = first._fPrev;
    assert(first.fCoinStart.isMatch);
    TSpan? oppFirst = first.findOppT(first.fCoinStart.perpT);
    assert(last.fCoinEnd.isMatch);
    bool oppMatched = first.fCoinStart.perpT < first.fCoinEnd.perpT;
    double coinStart = 0;
    TSpan? cutFirst;
    if (prev != null && prev.endT == startT) {
      _SearchCoinResult searchRes = binarySearchCoin(sect2, startT, prev.startT - startT);
      coinStart = searchRes.t;
      oppStartT = searchRes.oppT;
      oppFirst = searchRes.oppFirst;
      if (searchRes.success && prev.startT < coinStart && coinStart < startT
            && null != (cutFirst = prev.oppT(oppStartT))) {
        oppFirst = cutFirst;
        first = addSplitAt(prev, coinStart);
        first.markCoincident();
        prev.fCoinEnd.markCoincident();
        if (oppFirst!.startT < oppStartT && oppStartT < oppFirst.endT) {
          TSpan oppHalf = sect2.addSplitAt(oppFirst, oppStartT);
          if (oppMatched) {
            oppFirst.fCoinEnd.markCoincident();
            oppHalf.markCoincident();
            oppFirst = oppHalf;
          } else {
            oppFirst.markCoincident();
            oppHalf.fCoinStart.markCoincident();
          }
        }
      }
    }
    if (oppFirst == null) {
      return _CoincidentResult.failure();
    }
    // TODO: if we're not at the end, find end of coin
    TSpan oppLast;
    assert(last.fCoinEnd.isMatch);
    oppLast = last.findOppT(last.fCoinEnd.perpT);
    if (!oppMatched) {
      TSpan swapSpan = oppFirst;
      oppFirst = oppLast;
      oppLast = swapSpan;
      double swapT = oppStartT;
      oppStartT = oppEndT;
      oppEndT = swapT;
    }
    assert(oppStartT < oppEndT);
    assert(coinStart == first.startT);
    if (oppFirst == null) {
      return _CoincidentResult(true, null);
    }
    assert(oppStartT == oppFirst.startT);
    if (oppLast == null) {
      return _CoincidentResult(true, null);
    }
    assert(oppEndT == oppLast.endT);
    // Reduce coincident runs to single entries
    validate();
    sect2.validate();
    bool deleteEmptySpans = updateBounded(first, last, oppFirst);
    deleteEmptySpans |= sect2.updateBounded(oppFirst, oppLast, first);
    _removeSpanRange(first, last);
    sect2._removeSpanRange(oppFirst, oppLast);
    first._fEndT = last.endT;
    first.resetBounds(fCurve);
    first.fCoinStart.setPerp(fCurve, first.startT, first.pointFirst, sect2.fCurve);
    first.fCoinEnd.setPerp(fCurve, first.endT, first.pointLast, sect2.fCurve);
    oppStartT = first.fCoinStart.perpT;
    oppEndT = first.fCoinEnd.perpT;
    if (SPath.between(0, oppStartT, 1) && SPath.between(0, oppEndT, 1)) {
      if (!oppMatched) {
        double swapTemp = oppStartT;
        oppStartT = oppEndT;
        oppEndT = swapTemp;
      }
      oppFirst._fStartT = oppStartT;
      oppFirst._fEndT = oppEndT;
      oppFirst.resetBounds(sect2.fCurve);
    }
    last = first.next;
    if (!removeCoincident(first, false)) {
      return _CoincidentResult.failure();
    }
    if (!sect2.removeCoincident(oppFirst, true)) {
      return _CoincidentResult.failure();
    }
    if (deleteEmptySpans) {
      if (!_deleteEmptySpans() || !sect2._deleteEmptySpans()) {
        return _CoincidentResult.failure();
      }
    }
    validate();
    sect2.validate();
    return _CoincidentResult(last != null, last != null &&
       !last.fDeleted && fHead != null && sect2.fHead != null ? last : null);
  }

  _FindCoincidentResult findCoincidentRun(TSpan? first, TSpan? last) {
    TSpan? work = first;
    TSpan? lastCandidate;
    first = null;
    // Find the first fully coincident span.
    do {
      if (work!.fCoinStart.isMatch) {
        assert(work.hasOppT(work.fCoinStart.perpT));
        if (!work.fCoinEnd.isMatch) {
          break;
        }
        lastCandidate = work;
        if (first == null) {
          first = work;
        }
      } else if (first != null && work.collapsed) {
        last = lastCandidate;
        return _FindCoincidentResult(first, last);
      } else {
        lastCandidate = null;
        assert(first == null);
      }
      if (work == last) {
        return _FindCoincidentResult(first, last);
      }
      work = work.next;
      if (work == null) {
        _FindCoincidentResult(null, last);
      }
    } while (true);
    if (lastCandidate != null) {
      last = lastCandidate;
    }
    return _FindCoincidentResult(first, last);
  }

  _SearchCoinResult binarySearchCoin(TSect sect2, double tStart, double tStep) {
    _SearchCoinResult searchResult = _SearchCoinResult();
    TSpan work = TSpan(fCurve);
    double result = work._fStartT = work._fEndT = tStart;
    ui.Offset last = fCurve.ptAtT(tStart);
    ui.Offset? oppPt;
    bool flip = false;
    bool contained = false;
    bool down = tStep < 0;
    TCurve opp = sect2.fCurve;
    do {
      tStep *= 0.5;
      work._fStartT += tStep;
      if (flip) {
        tStep = -tStep;
        flip = false;
      }
      work.initBounds(fCurve);
      if (work.collapsed) {
        return searchResult;
      }
      ui.Offset pointFirst = work.pointFirst;
      if (approximatelyEqualPoints(last.dx, last.dy, pointFirst.dx, pointFirst.dy)) {
        break;
      }
      last = pointFirst;
      work.fCoinStart.setPerp(fCurve, work.startT, last, opp);
      if (work.fCoinStart.isMatch) {
        double oppTTest = work.fCoinStart.perpT;
          if (sect2.fHead!.contains(oppTTest)) {
              searchResult.oppT = oppTTest;
              oppPt = work.fCoinStart.perpPt;
              contained = true;
              if (down ? result <= work.startT : result >= work.startT) {
                  searchResult.oppFirst = null;
                  return searchResult;
              }
              result = work.startT;
              continue;
          }
      }
      tStep = -tStep;
      flip = true;
    } while (true);
    if (!contained) {
      return searchResult;
    }
    if (approximatelyEqualPoints(last.dx, last.dy, fCurve[0].dx, fCurve[0].dy)) {
      result = 0;
    } else if (approximatelyEqualPoints(last.dx, last.dy, pointLast.dx, pointLast.dy)) {
      result = 1;
    }
    if (approximatelyEqualPoints(oppPt!.dx, oppPt.dy, opp[0].dx, opp[0].dy)) {
      searchResult.oppT = 0;
    } else if (approximatelyEqualPoints(oppPt.dx, oppPt.dy, sect2.pointLast.dx, sect2.pointLast.dy)) {
      searchResult.oppT = 1;
    }
    searchResult.t = result;
    return searchResult;
  }

  void _mergeCoincidence(TSect sect2) {
    double smallLimit = 0;
    do {
      // Find the smallest unprocessed span
      TSpan? smaller;
      TSpan? test = fCoincident;
      do {
        if (test == null) {
          return;
        }
        if (test.startT < smallLimit) {
          continue;
        }
        if (smaller != null && smaller.endT < test.startT) {
          continue;
        }
        smaller = test;
      } while ((test = test.next) != null);
      if (smaller == null) {
        return;
      }
      smallLimit = smaller.endT;
      // Find next larger span.
      TSpan? prior;
      TSpan? larger;
      TSpan? largerPrior;
      test = fCoincident;
      do {
        if (test!.startT < smaller.endT) {
            continue;
        }
        assert(test.startT != smaller.endT);
        if (larger != null && larger.startT < test.startT) {
          continue;
        }
        largerPrior = prior;
        larger = test;
        prior = test;
        test = test.next;
      } while (test != null);
      if (larger == null) {
        continue;
      }
      // Check middle t value to see if it is coincident as well
      double midT = (smaller.endT + larger.startT) / 2;
      ui.Offset midPt = fCurve.ptAtT(midT);
      TCoincident coin = TCoincident();
      coin.setPerp(fCurve, midT, midPt, sect2.fCurve);
      if (coin.isMatch) {
        smaller._fEndT = larger._fEndT;
        smaller.fCoinEnd = larger.fCoinEnd;
        if (largerPrior != null) {
          largerPrior._fNext = larger._fNext;
          largerPrior.validate();
        } else {
          fCoincident = larger.next;
        }
      }
    } while (true);
  }

  void computePerpendiculars(TSect sect2,
        TSpan first, TSpan? last) {
    if (last == null) {
      return;
    }
    TCurve opp = sect2.fCurve;
    TSpan? w = first;
    TSpan? prior;
    do {
      TSpan work = w!;
      if (!work.fHasPerp && !work.collapsed) {
        if (prior != null) {
          work.fCoinStart = prior.fCoinEnd;
        } else {
          work.fCoinStart.setPerp(fCurve, work.startT, work.pointFirst, opp);
        }
        if (work.fCoinStart.isMatch) {
          double perpT = work.fCoinStart.perpT;
          if (sect2.coincidentHasT(perpT)) {
            work.fCoinStart.init();
          } else {
            sect2.addForPerp(work, perpT);
          }
        }
        work.fCoinEnd.setPerp(fCurve, work.endT, work.pointLast, opp);
        if (work.fCoinEnd.isMatch) {
            double perpT = work.fCoinEnd.perpT;
            if (sect2.coincidentHasT(perpT)) {
                work.fCoinEnd.init();
            } else {
                sect2.addForPerp(work, perpT);
            }
        }
        work.fHasPerp = true;
      }
      if (work == last) {
        break;
      }
      prior = work;
      w = w.next;
      assert(w != null);
    } while (true);
  }

  bool coincidentHasT(double t) {
    TSpan? test = fCoincident;
    while (test != null) {
      if (SPath.between(test.startT, t, test.endT)) {
        return true;
      }
      test = test.next;
    }
    return false;
  }

  int collapsed() {
    int result = 0;
    TSpan? test = fHead;
    while (test != null) {
      if (test.collapsed) {
        ++result;
      }
      test = test.next;
    }
    return result;
  }

  /// Recover deleted spans that are collapsed.
  void recoverCollapsed() {
    for (int index = 0; index < deletedSpans.length; ++index) {
      TSpan deleted = deletedSpans[index];
      if (deleted.collapsed) {
        // Find first span that exceeds deleted startT.
        TSpan? spanPtr = fHead;
        while (spanPtr != null && spanPtr.endT <= deleted.startT) {
          spanPtr = spanPtr.next;
        }
        deleted._fNext = spanPtr;
        if (spanPtr == fHead) {
          fHead = deleted;
        } else {
          spanPtr!._fPrev!._fNext = deleted;
        }
      }
      deletedSpans.removeAt(index);
      index--;
    }
  }

  bool updateBounded(TSpan first, TSpan last, TSpan oppFirst) {
    TSpan? test = first;
    TSpan? finalSpan = last.next;
    bool deleteSpan = false;
    do {
      deleteSpan |= test!.removeAllBounded();
    } while ((test = test.next) != finalSpan && test != null);
    first.fBounded = null;
    first.addBounded(oppFirst);
    // cannot call validate until remove span range is called
    return deleteSpan;
  }

  void _removeSpanRange(TSpan first, TSpan last) {
    if (first == last) {
      return;
    }
    TSpan? span = first;
    TSpan? finalSpan = last.next;
    TSpan? next = span!.next;
    while ((span = next) != null && span != finalSpan) {
      next = span!.next;
      _markSpanGone(span);
    }
    if (finalSpan != null) {
      finalSpan._fPrev = first;
    }
    first._fNext = finalSpan;
    first.validate();
  }

  bool removeByPerpendicular(TSect opp) {
    TSpan? test = fHead;
    TSpan? next;
    do {
        next = test!.next;
        if (test.fCoinStart.perpT < 0 || test.fCoinEnd.perpT < 0) {
          // Span has no perpendicular skip.
          continue;
        }
        ui.Offset startV = test.fCoinStart.perpPt - test.pointFirst;
        ui.Offset endV = test.fCoinEnd.perpPt - test.pointLast;
        double dot = startV.dx * endV.dx + startV.dy * endV.dy;
        if (dot <= 0) {
          // Obtuse , skip.
          continue;
        }
        if (!_removeSpans(test, opp)) {
          return false;
        }
    } while ((test = next) != null);
    return true;
  }

  TSpan addSplitAt(TSpan span, double t) {
    TSpan result = addOne();
    result.splitAt(span, t);
    result.initBounds(fCurve);
    span.initBounds(fCurve);
    return result;
  }

  bool removeCoincident(TSpan span, bool isBetween) {
    if (!_unlinkSpan(span)) {
      return false;
    }
    if (isBetween || SPath.between(0, span.fCoinStart.perpT, 1)) {
      --fActiveCount;
      span._fNext = fCoincident;
      fCoincident = span;
    } else {
      _markSpanGone(span);
    }
    return true;
  }

  bool _deleteEmptySpans() {
    TSpan? test;
    TSpan? next = fHead;
    int safetyHatch = 1000;
    while ((test = next) != null) {
      next = test!.next;
      if (test.fBounded == null) {
        if (!_removeSpan(test)) {
          return false;
        }
      }
      if (--safetyHatch < 0) {
        return false;
      }
    }
    return true;
  }

  bool _removeSpans(TSpan span, TSect opp) {
    _TSpanBounded? bounded = span.fBounded;
    while (bounded != null) {
      TSpan spanBounded = bounded.fBounded;
      _TSpanBounded? next = bounded.next;
      if (span.removeBounded(spanBounded)) {  // shuffles last into position 0
      _removeSpan(span);
      }
      if (spanBounded.removeBounded(span)) {
        opp._removeSpan(spanBounded);
      }
      if (span.fDeleted && opp.hasBounded(span)) {
        return false;
      }
      bounded = next;
    }
    return true;
  }
}


/// Caches perpendicular intersection t and point.
class TCoincident {
  TCoincident();

  ui.Offset fPerpPt = ui.Offset(double.nan, double.nan);
  double fPerpT = -1;  // perpendicular intersection on opposite curve
  bool fMatch = false;

  void init() {
    fPerpPt = ui.Offset(double.nan, double.nan);
    fPerpT = -1;  // perpendicular intersection on opposite curve
    fMatch = false;
  }

  bool get isMatch => fMatch;

  void markCoincident() {
    if (!fMatch) {
      fPerpT = -1;
    }
    fMatch = true;
  }

  ui.Offset get perpPt => fPerpPt;
  double get perpT => fPerpT;

  /// Calculate intersection t and point for [c] and perpendicular line from
  /// [c1] at t.
  void setPerp(TCurve c1, double t, ui.Offset cPt, TCurve c2) {
    final ui.Offset dxdy = c1.dxdyAtT(t);
    final DLine perp = DLine(cPt.dx, cPt.dy, cPt.dx + dxdy.dy, cPt.dy - dxdy.dx);
    Intersections i = Intersections();
    int used = c2.intersectRay(i, perp);
    // only keep closest
    if (used == 0 || used == 3) {
      init();
      return;
    }
    fPerpT = i.fT0[0];
    fPerpPt = ui.Offset(i.ptX[0], i.ptY[0]);
    assert(used <= 2);
    if (used == 2) {
      double distSq = distanceSquared(fPerpPt.dx, fPerpPt.dy, cPt.dx, cPt.dy);
      double x2 = i.ptX[1];
      double y2 = i.ptY[1];
      double dist2Sq = distanceSquared(x2, y2, cPt.dx, cPt.dy);
      if (dist2Sq < distSq) {
        fPerpT = i.fT0[1];
        fPerpPt = ui.Offset(x2, y2);
      }
    }
    fMatch = approximatelyEqualPoints(cPt.dx, cPt.dy, fPerpPt.dx, fPerpPt.dy);
  }
}

class _TSectDebug {
  TSect? fOppSect;
}

class HullCheckResult {
  // Intersection types:
  static const int kHullNoIntersection = 0;
  static const int kHullIntersects = 1;
  static const int kHullOnlyCommonEndPoint = 2;
  static const int kHullIsLinear = -1;

  bool start = false;
  bool oppStart = false;
  bool ptsInCommon = false;
  int intersectionType = kHullNoIntersection;
}

class _CoincidentResult {
  _CoincidentResult(this.success, this.coin);
  _CoincidentResult.failure() : success = false, coin = null;

  final bool success;
  final TSpan? coin;
}

class _FindCoincidentResult {
  _FindCoincidentResult(this.first, this.last);
  final TSpan? first;
  final TSpan? last;
}

class _SearchCoinResult {
  bool success = false;
  double t = 0;
  double oppT = 0;
  TSpan? oppFirst;
}

/// Creates a sorted list of span pairs by distance.
///
/// Usage:
///   for each span pair , find(span1, span2)
///   call finish(intersections) to add pairs to list of intersections.
class ClosestSect {
  ClosestSect() : fUsed = 0;

  bool find(TSpan span1, TSpan span2) {
    ClosestRecord record = ClosestRecord(span1, span2);
    record.findEnd(0, 0);
    record.findEnd(0, span2.part.pointLast);
    record.findEnd(span1.part.pointLast, 0);
    record.findEnd(span1.part.pointLast, span2.part.pointLast);
    if (record.fClosest == kFltMax) {
      return false;
    }
    for (int index = 0; index < fUsed; ++index) {
      ClosestRecord test = _fClosest[index];
      if (test.matesWith(record)) {
        if (test.fClosest > record.fClosest) {
          // Take closer span1,span2.
          test.merge(record);
        }
        // Sort startT,endT ranges.
        test.update(record);
        return false;
      }
    }
    // New pair doesn't mate with existing records, append a new one.
    ++fUsed;
    _fClosest.add(record);
    return true;
  }

  /// Sort span pairs by distance and add to intersections.
  void finish(Intersections intersections) {
    List<ClosestRecord> sortedList = List.from(_fClosest);
    sortedList.sort((ClosestRecord r1, ClosestRecord r2) {
      double res = r1.fClosest - r2.fClosest;
      return (res < 0) ? -1 : res == 0 ? 0 : 1;
    });
    for (ClosestRecord test in sortedList) {
      test.addIntersection(intersections);
    }
  }
  List<ClosestRecord> _fClosest = [];
  int fUsed;
}

class ClosestRecord {
  ClosestRecord(this.fC1Span, this.fC2Span);

  void addIntersection(Intersections intersections) {
    double r1t = fC1Index != 0 ? fC1Span.endT : fC1Span.startT;
    double r2t = fC2Index != 0 ? fC2Span.endT : fC2Span.startT;
    ui.Offset pt = fC1Span.part[fC1Index];
    intersections.insert(r1t, r2t, pt.dx, pt.dy);
  }

  void findEnd(int c1Index, int c2Index) {
      TCurve c1 = fC1Span.part;
      TCurve c2 = fC2Span.part;
      ui.Offset p1 = c1[c1Index];
      ui.Offset p2 = c2[c2Index];
      if (!approximatelyEqualPoints(p1.dx, p1.dy, p2.dx, p2.dy)) {
          return;
      }
      double dist = distanceSquared(p1.dx, p1.dy, p2.dx, p2.dy);
      if (fClosest < dist) {
        return;
      }
      fC1StartT = fC1Span.startT;
      fC1EndT = fC1Span.endT;
      fC2StartT = fC2Span.startT;
      fC2EndT = fC2Span.endT;
      fC1Index = c1Index;
      fC2Index = c2Index;
      fClosest = dist;
  }

  /// Checks if either span is identical or has same but reversed T ranges.
  bool matesWith(ClosestRecord mate) {
    TSpan span1 = fC1Span;
    TSpan span2 = fC2Span;
    assert(span1 == mate.fC1Span || span1.endT <= mate.fC1Span.startT
            || mate.fC1Span.endT <= span1.startT);
    assert(span2 == mate.fC2Span || span2.endT <= mate.fC2Span.startT
            || mate.fC2Span.endT <= span2.startT);
    return span1 == mate.fC1Span || span1.endT == mate.fC1Span.startT
      || span1.startT == mate.fC1Span.endT
      || span2 == mate.fC2Span
      || span2.endT == mate.fC2Span.startT
      || span2.startT == mate.fC2Span.endT;
  }

  void merge(ClosestRecord mate) {
    fC1Span = mate.fC1Span;
    fC2Span = mate.fC2Span;
    fClosest = mate.fClosest;
    fC1Index = mate.fC1Index;
    fC2Index = mate.fC2Index;
  }

  void update(ClosestRecord mate) {
    fC1StartT = math.min(fC1StartT!, mate.fC1StartT!);
    fC1EndT = math.max(fC1EndT!, mate.fC1EndT!);
    fC2StartT = math.min(fC2StartT!, mate.fC2StartT!);
    fC2EndT = math.max(fC2EndT!, mate.fC2EndT!);
  }

  TSpan fC1Span;
  TSpan fC2Span;
  double? fC1StartT;
  double? fC1EndT;
  double? fC2StartT;
  double? fC2EndT;
  double fClosest = kFltMax;
  int fC1Index = -1;
  int fC2Index = -1;
}
