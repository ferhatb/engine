// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10

part of engine;

const int kCoincidentSpanCount = 9;

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
  // Linked list of deleted TSpan for reuse.
  TSpan? fDeleted;
  bool fRemovedStartT = false;
  bool fRemovedEndT = false;
  _TSectDebug? debugInfo;

  void resetRemovedEnds() {
    fRemovedStartT = fRemovedEndT = false;
  }

  /// Adds a new span.
  TSpan addOne() {
    TSpan result;
    // Reuse a delete TSpan is possible.
    if (fDeleted != null) {
      result = fDeleted!;
      fDeleted = result.next;
    } else {
      // Allocate new TSpan
      result = TSpan(fCurve);
    }
    result.reset();
    result..fHasPerp = false;
    result.fDeleted = false;

    ++fActiveCount;
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
    } while ((test = test!.next) != null);
    return false;
  }

  TSpan? boundsMax() {
    TSpan? test = fHead;
    TSpan largest = fHead!;
    bool lCollapsed = largest.fCollapsed;
    int safetyNet = 10000;
    while ((test = test!.next) != null) {
      if (--safetyNet == 0) {
        fHung = true;
        return null;
      }
      bool tCollapsed = test!.fCollapsed;
      if ((lCollapsed && !tCollapsed) || (lCollapsed == tCollapsed &&
        largest.fBoundsMax < test!.fBoundsMax)) {
        largest = test!;
        lCollapsed = test!.fCollapsed;
      }
    }
    return largest;
  }

  ui.Offset get pointLast {
    return fCurve[fCurve.pointLast];
  }

  static void binarySearch(TSect sect1, TSect sect2, Intersections intersections) {
    assert(sect1.debugInfo!.fOppSect == sect2);
    assert(sect2.debugInfo!.fOppSect == sect1);
    intersections.reset();
    intersections.setMax(sect1.fCurve.maxIntersections + 4);  // Extra for slop
    TSpan span1 = sect1.fHead!;
    TSpan span2 = sect2.fHead!;
    List<int> res = sect1.intersects(span1,sect2,span2);
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
                || (!largest1.fCollapsed && largest2.fCollapsed)))) {
        if (sect2.fHung) {
          return;
        }
        if (largest1.fCollapsed) {
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
        if (largest2.fCollapsed) {
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
        sect1.computePerpendiculars(sect2, sect1.fHead, sect1.tail);
        if (sect2.fHead == null) {
          return;
        }
        sect2.computePerpendiculars(sect1, sect2.fHead, sect2.tail);
        if (!sect1.removeByPerpendicular(sect2)) {
          return;
        }
        sect1.validate();
        sect2.validate();
        if (sect1.collapsed > sect1.fCurve.maxIntersections) {
          break;
        }
      }
      if (sect1.fHead == null || sect2.fHead == null) {
        break;
      }
    } while (true);
    TSpan? coincident = sect1.fCoincident;
    if (coincident != null) {
      // if there is more than one coincident span, check loosely to see if they should be joined
      if (coincident.next) {
          sect1.mergeCoincidence(sect2);
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
    TSpan result1 = sect1.fHead!;
    // check heads and tails for zero and ones and insert them if we haven't already done so
    TSpan head1 = result1;
    if ((zeroOneSet & kFirstS1Set) == 0 && approximatelyLessThanZero(head1.startT)) {
      ui.Offset start1 = sect1.fCurve[0];
      if (head1.isBounded()) {
        double t = head1.closestBoundedT(start1);
        ui.Offset pt = sect2.fCurve.ptAtT(t);
        if (approximatelyEqualPoints(pt.dx, pt.dy, start1.dx, start1.dy)) {
          intersections.insert(0, t, start1.dx, start1.dy);
        }
      }
    }
    TSpan head2 = sect2.fHead;
    if (!(zeroOneSet & kFirstS2Set) && approximatelyLessThanZero(head2.startT)) {
      ui.Offset start2 = sect2.fCurve[0];
      if (head2.isBounded()) {
        double t = head2.closestBoundedT(start2);
        ui.Offset pt = sect1.fCurve.ptAtT(t);
        if (approximatelyEqualPoints(pt.dx, pt.dy, start2.dx, start2.dy)) {
            intersections.insert(t, 0, start2.dx, start2.dy);
        }
      }
    }
    if ((zeroOneSet & kLastS1Set) == 0) {
      TSpan? tail1 = sect1.tail;
      if (tail1 == null) {
        return;
      }
      if (approximatelyGreaterThanOne(tail1.endT)) {
          ui.Offset end1 = sect1.pointLast;
          if (tail1.isBounded) {
              double t = tail1.closestBoundedT(end1);
              ui.Offset pt = sect2.fCurve.ptAtT(t);
              if (approximatelyEqualPoints(pt.dx, pt.dy, end1.dx, end1.dy)) {
                  intersections->insert(1, t, end1);
              }
          }
      }
    }
    if (!(zeroOneSet & kLastS2Set)) {
        TSpan? tail2 = sect2.tail;
        if (tail2 == null) {
          return;
        }
        if (approximatelyGreaterThanOne(tail2.endT)) {
            ui.Offset end2 = sect2.pointLast;
            if (tail2.isBounded()) {
                double t = tail2.closestBoundedT(end2);
                if (sect1->fCurve.ptAtT(t).approximatelyEqual(end2)) {
                    intersections->insert(t, 1, end2);
                }
            }
        }
    }
    SkClosestSect closest;
    do {
        while (result1 && result1->fCoinStart.isMatch() && result1->fCoinEnd.isMatch()) {
            result1 = result1->fNext;
        }
        if (!result1) {
            break;
        }
        SkTSpan* result2 = sect2->fHead;
        bool found = false;
        while (result2) {
            found |= closest.find(result1, result2  SkDEBUGPARAMS(intersections));
            result2 = result2->fNext;
        }
    } while ((result1 = result1->fNext));
    closest.finish(intersections);
    // if there is more than one intersection and it isn't already coincident, check
    int last = intersections->used() - 1;
    for (int index = 0; index < last; ) {
        if (intersections->isCoincident(index) && intersections->isCoincident(index + 1)) {
            ++index;
            continue;
        }
        double midT = ((*intersections)[0][index] + (*intersections)[0][index + 1]) / 2;
        SkDPoint midPt = sect1->fCurve.ptAtT(midT);
        // intersect perpendicular with opposite curve
        SkTCoincident perp;
        perp.setPerp(sect1->fCurve, midT, midPt, sect2->fCurve);
        if (!perp.isMatch()) {
            ++index;
            continue;
        }
        if (intersections->isCoincident(index)) {
            intersections->removeOne(index);
            --last;
        } else if (intersections->isCoincident(index + 1)) {
            intersections->removeOne(index + 1);
            --last;
        } else {
            intersections->setCoincident(index++);
        }
        intersections->setCoincident(index);
    }
    SkOPOBJASSERT(intersections, intersections->used() <= sect1->fCurve.maxIntersections());
  }

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

  // while the intersection points are sufficiently far apart:
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
    // if the ends of each line intersect the opposite curve, the lines are coincident
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
      TSpan test = testBounded.fBounded!;
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
          this.removeSpan(span);
        }
        if (test.removeBounded(span)) {
          opp.removeSpan(test);
        }
      }
      testBounded = next;
    }
    return true;
  }

  bool removeSpan(TSpan span) {
    _removedEndCheck(span);
    if (!_unlinkSpan(span)) {
      return false;
    }
    return _markSpanGone(span);
  }

  void removeAllBut(TSpan keep, TSpan span, TSect opp) {
    _TSpanBounded? testBounded = span.fBounded;
    while (testBounded != null) {
      TSpan bounded = testBounded.fBounded!;
      _TSpanBounded? next = testBounded.next;
      // may have been deleted when opp did 'remove all but'
      if (bounded != keep && !bounded.fDeleted) {
        span.removeBounded(bounded);
        if (bounded.removeBounded(span)) {
          opp.removeSpan(bounded);
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

  bool _markSpanGone(TSpan span) {
    if (--fActiveCount < 0) {
      return false;
    }
    span._fNext = fDeleted;
    fDeleted = span;
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
        assert(span!.startT >= last);
        last = span!.endT;
        ++count;
        next = span!.next;
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
        result = next!;
      }
    }
    return result;
  }

  bool coincidentCheck(SkTSect* sect2) {
    SkTSpan* first = fHead;
    if (!first) {
        return false;
    }
    SkTSpan* last, * next;
    do {
        int consecutive = this->countConsecutiveSpans(first, &last);
        next = last->fNext;
        if (consecutive < COINCIDENT_SPAN_COUNT) {
            continue;
        }
        this->validate();
        sect2->validate();
        this->computePerpendiculars(sect2, first, last);
        this->validate();
        sect2->validate();
        // check to see if a range of points are on the curve
        SkTSpan* coinStart = first;
        do {
            bool success = this->extractCoincident(sect2, coinStart, last, &coinStart);
            if (!success) {
                return false;
            }
        } while (coinStart && !last->fDeleted);
        if (!fHead || !sect2->fHead) {
            break;
        }
        if (!next || next->fDeleted) {
            break;
        }
    } while ((first = next));
    return true;
}

  void SkTSect::coincidentForce(SkTSect* sect2,
        double start1s, double start1e) {
    SkTSpan* first = fHead;
    SkTSpan* last = this->tail();
    SkTSpan* oppFirst = sect2->fHead;
    SkTSpan* oppLast = sect2->tail();
    if (!last || !oppLast) {
        return;
    }
    bool deleteEmptySpans = this->updateBounded(first, last, oppFirst);
    deleteEmptySpans |= sect2->updateBounded(oppFirst, oppLast, first);
    this->removeSpanRange(first, last);
    sect2->removeSpanRange(oppFirst, oppLast);
    first->fStartT = start1s;
    first->fEndT = start1e;
    first->resetBounds(fCurve);
    first->fCoinStart.setPerp(fCurve, start1s, fCurve[0], sect2->fCurve);
    first->fCoinEnd.setPerp(fCurve, start1e, this->pointLast(), sect2->fCurve);
    bool oppMatched = first->fCoinStart.perpT() < first->fCoinEnd.perpT();
    double oppStartT = first->fCoinStart.perpT() == -1 ? 0 : std::max(0., first->fCoinStart.perpT());
    double oppEndT = first->fCoinEnd.perpT() == -1 ? 1 : std::min(1., first->fCoinEnd.perpT());
    if (!oppMatched) {
        using std::swap;
        swap(oppStartT, oppEndT);
    }
    oppFirst->fStartT = oppStartT;
    oppFirst->fEndT = oppEndT;
    oppFirst->resetBounds(sect2->fCurve);
    this->removeCoincident(first, false);
    sect2->removeCoincident(oppFirst, true);
    if (deleteEmptySpans) {
        this->deleteEmptySpans();
        sect2->deleteEmptySpans();
    }
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
      if (test.fCollapsed) {
        ++result;
      }
      test = test.next;
    }
    return result;
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
