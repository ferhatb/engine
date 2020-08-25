// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Represents a group of points that form a line or curve that are part of
/// a contour.
///
/// Provides access to [next] segment following a segment in the contour.
class OpSegment {
  OpSegment(this.points, this.verb, this.parent, this.weight, this.bounds) {
    fHead = OpSpan(this, null)
      ..init(0, ui.Offset(points[0], points[1]));
  }

  final Float32List points;
  final int verb;
  final OpContour parent;
  final double weight;
  final ui.Rect bounds;

  /// Linked list of spans formed by adding intersection points.
  OpSpan? fHead;
  OpSpanBase? fTail; // the tail span always has its t set to one.

  OpSegment? _next;

  /// Links tail of this segment to [start]'s [OpSpan].
  void joinEnds(OpSegment start) {
    fTail!.ptT.addOpp(start.fHead!.ptT, start.fHead!.ptT);
  }

  /// Span count.
  int fCount = 0;

  /// Number of processed spans.
  int fDoneCount = 0;

  /// Set if original path had even-odd fill.
  bool fXor = false;

  /// Set if opposite path had even-odd fill.
  bool fOppXor = false;

  // Used for missing coincidence check.
  bool fVisited = false;

  void bumpCount() {
    fCount++;
  }

  bool get operand => parent.operand;

  bool get oppXor => fOppXor;

  bool get isXor => fXor;

  void resetVisited() {
    fVisited = false;
  }

  /// Constructs conic segment and stores bounds.
  factory OpSegment.conic(Float32List points, double weight, OpContour parent) {
    final _ConicBounds conicBounds = _ConicBounds();
    conicBounds.calculateBounds(points, weight, 0);
    return OpSegment(points, SPathVerb.kConic, parent, weight,
        ui.Rect.fromLTRB(conicBounds.minX, conicBounds.minY,
            conicBounds.maxX, conicBounds.maxY));
  }

  /// Constructs quadratic segment and stores bounds.
  factory OpSegment.quad(Float32List points, OpContour parent) {
    final _QuadBounds quadBounds = _QuadBounds();
    quadBounds.calculateBounds(points, 0);
    return OpSegment(points, SPathVerb.kQuad, parent, 1.0,
        ui.Rect.fromLTRB(quadBounds.minX, quadBounds.minY,
            quadBounds.maxX, quadBounds.maxY));
  }

  /// Constructs cubic segment and stores bounds.
  factory OpSegment.cubic(Float32List points, OpContour parent) {
    final _CubicBounds cubicBounds = _CubicBounds();
    cubicBounds.calculateBounds(points, 0);
    return OpSegment(points, SPathVerb.kCubic, parent, 1.0,
        ui.Rect.fromLTRB(cubicBounds.minX, cubicBounds.minY,
            cubicBounds.maxX, cubicBounds.maxY));
  }

  /// Constructs line segment and stores bounds.
  factory OpSegment.line(Float32List points, OpContour parent) {
    ui.Rect bounds = ui.Rect.fromLTRB(math.min(points[0], points[2]),
        math.min(points[1], points[3]), math.max(points[0], points[2]),
        math.max(points[1], points[3]));
    return OpSegment(points, SPathVerb.kLine, parent, 1.0, bounds);
  }

  bool get isHorizontal => bounds.top == bounds.bottom;

  bool get isVertical => bounds.left == bounds.right;

  /// Returns next segment in parent contour.
  OpSegment? get next => _next;

  // Look for two different spans that point to the same opposite segment.
  bool visited() {
    if (!fVisited) {
      fVisited = true;
      return false;
    }
    return true;
  }

  /// Point on curve at t.
  ui.Offset ptAtT(double t) {
    switch (verb) {
      case SPathVerb.kLine:
        return DLine.fromPoints(points).ptAtT(t);
      case SPathVerb.kQuad:
        return Quad(points).ptAtT(t);
      case SPathVerb.kConic:
        return Conic.fromPoints(points, weight).ptAtT(t);
      case SPathVerb.kCubic:
        return Cubic.fromPoints(points).ptAtT(t);
      default:
        assert(false);
        break;
    }
    return ui.Offset.zero;
  }

  /// Slope of curve at t.
  ui.Offset dxdyAtT(double t) {
    switch (verb) {
      case SPathVerb.kLine:
        return ui.Offset(points[2] - points[0], points[3] - points[1]);
      case SPathVerb.kQuad:
        return Quad(points).dxdyAtT(t);
      case SPathVerb.kConic:
        return Conic.fromPoints(points, weight).dxdyAtT(t);
      case SPathVerb.kCubic:
        return Cubic.fromPoints(points).dxdyAtT(t);
      default:
        assert(false);
        break;
    }
    return ui.Offset.zero;
  }

  /// Updates spans for an intersection point at t.
  OpPtT? addT(double t) {
    ui.Offset pt = ptAtT(t);
    return addTAtPoint(t, pt.dx, pt.dy);
  }

  /// Used by [addExpanded] to determine if addT allocates a new span.
  bool _allocatedOpSpan = false;

  /// Updates spans for an intersection point [ptX],[ptY] at [t].
  OpPtT? addTAtPoint(double t, double ptX, double ptY) {
    OpSpanBase? spanBase = fHead;
    while (spanBase != null) {
      OpPtT result = spanBase.ptT;

      /// If t already exist in span list, bump counter and return existing
      /// span. [match] ensures that point at T is approximately equal.
      if (t == result.fT ||
          (!zeroOrOne(t) && match(result, this, t, ptX, ptY))) {
        spanBase.bumpSpanAdds();
        return result;
      }

      /// Check for possible insertion point (in t ordered list).
      if (t < result.fT) {
        /// Previous always exists since fHead points to t=0 for start point.
        OpSpan prev = result.span.prev!;
        // Insert after previous.
        OpSpan span = OpSpan(this, prev)
          ..init(t, ui.Offset(ptX, ptY));
        _allocatedOpSpan = true;
        span._fNext = result.span;
        span.bumpSpanAdds();
        return span.ptT;
      }
      spanBase = spanBase.upCast.next;
    }
    assert(false);
    return null;
  }

  bool contains(double newT) {
    OpSpanBase? spanBase = fHead;
    do {
      if (spanBase!.ptT.containsSegmentAtT(this, newT)) {
        return true;
      }
      if (spanBase == fTail) {
        break;
      }
      spanBase = spanBase.upCast.next;
    } while (true);
    return false;
  }

  OpPtT? existing(double t, OpSegment? opp) {
    OpSpanBase? test = fHead;
    OpPtT? testPtT;
    ui.Offset pt = ptAtT(t);
    do {
      testPtT = test!.ptT;
      if (testPtT.fT == t) {
        break;
      }
      if (!match(testPtT, this, t, pt.dx, pt.dy)) {
        if (t < testPtT.fT) {
          return null;
        }
        continue;
      }
      if (opp == null) {
        return testPtT;
      }
      OpPtT? loop = testPtT.next;
      bool foundMatch = false;
      while (loop != testPtT) {
        if (loop!.segment == this && loop.fT == t && loop.fPt == pt) {
          foundMatch = true;
          break;
        }
        loop = loop.next;
      }
      if (foundMatch) {
        break;
      }
      return null;
    } while ((test = test.upCast.next) != null);
    return (opp != null && test!.containsSegment(opp) == null) ? null : testPtT;
  }

  // Break the span so that the coincident part does not change the angle of
  // the remainder.
  _SegmentBreakResult addExpanded(double newT, OpSpanBase test) {
    if (contains(newT)) {
      return _SegmentBreakResult.success(false);
    }
    if (!SPath.between(0, newT, 1)) {
      return _SegmentBreakResult.fail(false);
    }
    _allocatedOpSpan = false;
    OpPtT? newPtT = addT(newT);
    bool startOver = false;
    startOver |= _allocatedOpSpan;
    if (newPtT == null) {
      return _SegmentBreakResult.fail(startOver);
    }
    // newPtT.fPt = ptAtT(newT);
    assert(newPtT.fPt == ptAtT(newT));
    OpPtT? oppPrev = test.ptT.oppPrev(newPtT);
    if (oppPrev != null) {
      OpSpanBase writableTest = test;
      writableTest.mergeMatches(newPtT.span);
      writableTest.ptT.addOpp(newPtT, oppPrev);
      writableTest.checkForCollapsedCoincidence();
    }
    return _SegmentBreakResult.success(startOver);
  }

  /// Test if OpPtT is approximately equal to a test point on same or other
  /// [testSegment].
  bool match(OpPtT base, OpSegment testParent, double testT,
      double testPtX, double testPtY) {
    assert(this == base.segment);
    if (this == testParent) {
      if (preciselyEqual(base.fT, testT)) {
        return true;
      }
    }
    ui.Offset basePoint = base.fPt;
    if (!approximatelyEqualPoints(
        testPtX, testPtY, basePoint.dx, basePoint.dy)) {
      return false;
    }
    return this != testParent ||
        !ptsDisjoint(
            base.fT, basePoint.dx, basePoint.dy, testT, testPtX, testPtY);
  }

  /// Check if points although approximately equal are disjoint due to a
  /// loopback by calculating mid point between t values to make sure they are
  /// still close.
  bool ptsDisjoint(double t1, double pt1X, double pt1Y,
      double t2, double pt2X, double pt2Y) {
    if (verb == SPathVerb.kLine) {
      return false;
    }
    // Quadratics and cubics can loop back to nearly a line so that an opposite
    // curve hits in two places with very different t values.
    double midT = (t1 + t2) / 2;
    ui.Offset midPt = ptAtT(midT);
    double seDistSq = math.max(distanceSquared(pt1X, pt1Y, pt2X, pt2Y) * 2,
        kFltEpsilon * 2);
    return distanceSquared(midPt.dx, midPt.dy, pt1X, pt1Y) > seDistSq ||
        distanceSquared(midPt.dx, midPt.dy, pt2X, pt2Y) > seDistSq;
  }

  // If a span has more than one intersection, merge the other segments' span
  // as needed.
  bool moveMultiples() {
    debugValidate();
    OpSpanBase? test = fHead;
    do {
      int addCount = test!.spanAddsCount;
      if (addCount <= 1) {
        continue;
      }
      if (!_moveMultiples(test, addCount)) {
        return false;
      }
    } while ((test = test.isFinal() ? null : test.upCast.next) != null);
    debugValidate();
    return true;
  }

  bool _moveMultiples(OpSpanBase test, int addCount) {
    OpPtT startPtT = test.ptT;
    OpPtT testPtT = startPtT;
    int safetyHatch = 1000000;
    do { // Iterate through all spans associated with start.
      if (--safetyHatch == 0) {
        return false;
      }
      if (_moveMultiplesAt(startPtT, testPtT, addCount)) {
        return true;
      }
    } while ((testPtT = testPtT.next!) != startPtT);
    return true;
  }

  bool _moveMultiplesAt(OpPtT startPtT, OpPtT testPtT, int addCount) {
    OpSpanBase oppSpan = testPtT.span;
    if (oppSpan.spanAddsCount == addCount) {
      return false;
    }
    if (oppSpan.deleted) {
      return false;
    }
    OpSegment oppSegment = oppSpan.segment;
    if (oppSegment == this) {
      return false;
    }
    // Find range of spans to consider merging.
    OpSpanBase? oppPrev = oppSpan;
    OpSpanBase oppFirst = oppSpan;
    while ((oppPrev = oppPrev!.prev) != null) {
      if (!roughlyEqual(oppPrev!.t, oppSpan.t)) {
        break;
      }
      if (oppPrev.spanAddsCount == addCount || oppPrev.deleted) {
        continue;
      }
      oppFirst = oppPrev;
    }
    OpSpanBase? oppNext = oppSpan;
    OpSpanBase oppLast = oppSpan;
    while ((oppNext = oppNext!.isFinal() ? null : oppNext.upCast.next) !=
        null) {
      if (!roughlyEqual(oppNext!.t, oppSpan.t)) {
        break;
      }
      if (oppNext.spanAddsCount == addCount || oppNext.deleted) {
        continue;
      }
      oppLast = oppNext;
    }
    if (oppFirst == oppLast) {
      // Nothing to merge.
      return false;
    }
    // Merge from oppFirst to oppLast.
    OpSpanBase? oppTest = oppFirst;
    do {
      if (oppTest == oppSpan) {
        continue;
      }
      // Check to see if the candidate meets specific criteria:
      //    it contains spans of segments in test's loop but not
      //    including 'this'.
      OpPtT oppStartPtT = oppTest!.ptT;
      OpPtT? oppPtT = oppStartPtT;
      while ((oppPtT = oppPtT!.next) != oppStartPtT) {
        OpSegment oppPtTSegment = oppPtT!.segment;
        if (oppPtTSegment == this) {
          break;
        }
        OpPtT? matchPtT = startPtT;
        bool foundMatch = false;
        do {
          if (matchPtT!.segment == oppPtTSegment) {
            foundMatch = true;
            break;
          }
        } while ((matchPtT = matchPtT.next) != startPtT);
        if (foundMatch) {
          oppSegment.debugValidate();
          oppTest.mergeMatches(oppSpan);
          oppTest.addOpp(oppSpan);
          oppSegment.debugValidate();
          return true;
        } else {
          break;
        }
      }
    } while (oppTest != oppLast && (oppTest = oppTest!.upCast.next) != null);
    return false;
  }

  // Please keep this function in sync with debugMoveNearby()
  // Move nearby t values and pts so they all hang off the same span. Alignment happens later.
  bool moveNearby(OpGlobalState globalState) {
    debugValidate();
    // release undeleted spans pointing to this seg that are linked to the primary span
    OpSpanBase? spanBase = fHead;
    // The largest count for a regular test is 50; for a fuzzer, 500.
    int escapeHatch = 9999;
    do {
      OpPtT ptT = spanBase!.ptT;
      OpPtT headPtT = ptT;
      while ((ptT = ptT.next!) != headPtT) {
        if (--escapeHatch == 0) {
          return false;
        }
        OpSpanBase test = ptT.span;
        if (ptT.segment == this && !ptT.deleted && test != spanBase
            && test.ptT == ptT) {
          if (test.isFinal()) {
            if (spanBase == fHead) {
              clearAll(globalState);
              return true;
            }
            spanBase.upCast.release(ptT);
          } else if (test.prev != null) {
            test.upCast.release(headPtT);
          }
          break;
        }
      }
      spanBase = spanBase.upCast.next!;
    } while (!spanBase.isFinal());
    // This loop looks for adjacent spans which are near by
    spanBase = fHead;
    do { // iterate through all spans associated with start
      OpSpanBase test = spanBase!.upCast.next!;
      bool found;
      int res = spansNearby(spanBase, test);
      if (res == _kSpansNearbyFailed) {
        return false;
      }
      if (res == _kSpansNearbyFound) {
        if (test.isFinal()) {
          if (spanBase.prev != null) {
            test.merge(spanBase.upCast);
          } else {
            clearAll(globalState);
            return true;
          }
        } else {
          spanBase.merge(test.upCast);
        }
      }
      spanBase = test;
    } while (!spanBase.isFinal());
    debugValidate();
    return true;
  }

  static const int _kSpansNearbyFailed = -1;
  static const int _kSpansNearbyNone = 0;
  static const int _kSpansNearbyFound = 1;

  // Check for adjacent spans that may have points close by.
  int spansNearby(OpSpanBase refSpan, OpSpanBase checkSpan) {
    OpPtT refHead = refSpan.ptT;
    OpPtT checkHead = checkSpan.ptT;
    // If the first pt pair from adjacent spans are far apart,
    // assume that all are far enough apart.
    if (!_wayRoughlyEqual(refHead.fPt, checkHead.fPt)) {
      return _kSpansNearbyNone;
    }
    // Check only unique points.
    double distSqBest = kScalarMax;
    OpPtT? refBest = null;
    OpPtT? checkBest = null;
    OpPtT ref = refHead;
    bool doneChecking = false;
    do {
      if (ref.deleted) {
        continue;
      }
      while (ref.ptAlreadySeen(refHead)) {
        ref = ref.next!;
        if (ref == refHead) {
          doneChecking = true;
          break;
        }
      }
      if (doneChecking) {
        break;
      }

      OpPtT check = checkHead;
      OpSegment refSeg = ref.segment;
      int escapeHatch = 100000; // defend against infinite loops.
      bool checkedHead = false;
      do {
        if (check.deleted) {
          continue;
        }
        while (check.ptAlreadySeen(checkHead)) {
          check = check.next!;
          if (check == checkHead) {
            checkedHead = true;
            break;
          }
        }
        if (checkedHead) {
          break;
        }
        // Both reference and checkSpan have already seen.
        // Calculate distance.
        double distSq = distanceSquared(
            ref.fPt.dx, ref.fPt.dy, check.fPt.dx, check.fPt.dy);
        if (distSqBest > distSq && (refSeg != check.segment
            || !refSeg.opPtsDisjoint(ref, check))) {
          distSqBest = distSq;
          refBest = ref;
          checkBest = check;
        }
        if (--escapeHatch <= 0) {
          return _kSpansNearbyFailed;
        }
      } while ((check = check.next!) != checkHead);
      if (doneChecking) {
        break;
      }
    } while ((ref = ref.next!) != refHead);
    // Distance check complete.
    bool found = checkBest != null && refBest!.segment.match(refBest,
        checkBest.segment, checkBest.fT, checkBest.fPt.dx, checkBest.fPt.dy);
    return found ? _kSpansNearbyFound : _kSpansNearbyNone;
  }

  bool opPtsDisjoint(OpPtT span, OpPtT test) {
    assert(this == span.segment);
    assert(this == test.segment);
    return ptsDisjoint(
        span.fT, span.fPt.dx, span.fPt.dy, test.fT, test.fPt.dx, test.fPt.dy);
  }

  void clearAll(OpGlobalState globalState) {
    OpSpan? span = fHead as OpSpan;
    do {
      clearOne(span!);
    } while ((span = span.next?.upCastable()) != null);
    globalState.coincidence?.releaseCoinsOnSegment(this);
  }


  void clearOne(OpSpan span) {
    span.setWindValue(0);
    span.setOppValue(0);
    markDone(span);
  }

  void debugValidate() {
    if (kDebugValidate) {
      OpSpanBase span = fHead!;
      double lastT = -1;
      OpSpanBase? prev;
      int count = 0;
      int done = 0;
      do {
        if (!span.isFinal()) {
          ++count;
          done += span.upCast.done ? 1 : 0;
        }
        assert(span.fSegment == this);
        assert(prev == null || prev.upCast.next == span);
        assert(prev == null || prev == span.prev);
        prev = span;
        double t = span.ptT.fT;
        assert(lastT < t);
        lastT = t;
        OpSpanBase? next = span.upCast.next;
        if (next == null) {
          break;
        }
        span = next;
      } while (!span.isFinal());
      assert(count == fCount);
      assert(done == fDoneCount);
      assert(count >= fDoneCount);
      assert(span.isFinal());
    }
  }

  bool done() {
    assert(fDoneCount <= fCount);
    return fDoneCount == fCount;
  }

  /// Checks if point at t is roughlyEqual to intersection points of
  /// perpendicular ray from this point to opposing segment.
  ///
  /// TODO: check if we can use [CurveDistance.nearPoint] instead.
  bool isClose(double t, OpSegment opp) {
    ui.Offset cPt = ptAtT(t);
    ui.Offset dxdy = dxdyAtT(t);
    DLine perp = DLine(cPt.dx, cPt.dy, cPt.dx + dxdy.dy, cPt.dy - dxdy.dx);
    Intersections i = Intersections();
    intersectRay(points, verb, weight, perp, i);
    int used = i.fUsed;
    for (int index = 0; index < used; ++index) {
      if (roughlyEqualPoints(cPt.dx, cPt.dy, i.ptX[index], i.ptY[index])) {
        return true;
      }
    }
    return false;
  }

  void markAllDone() {
    OpSpan? span = fHead as OpSpan;
    do {
      markDone(span!);
    } while ((span = span.next?.upCastable()) != null);
  }

  void markDone(OpSpan span) {
    assert(this == span.fSegment);
    if (span.done) {
      return;
    }
    span.done = true;
    ++fDoneCount;
    debugValidate();
  }

  void release(OpSpan span) {
    if (span.done) {
      --fDoneCount;
    }
    --fCount;
    assert(fCount >= fDoneCount);
  }

  int collapsed(double s, double e) {
    OpSpanBase? span = fHead;
    do {
      int result = span!.collapsed(s, e);
      if (OpSpanBase.kNotCollapsed != result) {
        return result;
      }
    } while (span.upCastable() != null && (span = span.upCast.next) != null);
    return OpSpanBase.kNotCollapsed;
  }

  // Look for pairs of undetected coincident curves
  // assumes that segments going in have visited flag clear
  // Even though pairs of curves correct detect coincident runs, a run may be missed
  // if the coincidence is a product of multiple intersections. For instance, given
  // curves A, B, and C:
  // A-B intersect at a point 1; A-C and B-C intersect at point 2, so near
  // the end of C that the intersection is replaced with the end of C.
  // Even though A-B correctly do not detect an intersection at point 2,
  // the resulting run from point 1 to point 2 is coincident on A and B.
  bool missingCoincidence() {
    if (done()) {
      return false;
    }
    OpSpan? prior;
    OpSpanBase? spanBase = fHead;
    bool result = false;
    int safetyNet = 100000;
    do {
      OpPtT ptT = spanBase!.ptT;
      OpPtT? spanStopPtT = ptT;
      assert(ptT.span == spanBase);
      while ((ptT = ptT.next!) != spanStopPtT) {
        if (0 == --safetyNet) {
          return false;
        }
        if (ptT.deleted) {
          continue;
        }
        OpSegment opp = ptT.span.segment;
        if (opp.done()) {
          continue;
        }
        // when opp is encounted the 1st time, continue; on 2nd encounter, look for coincidence
        if (!opp.visited()) {
          continue;
        }
        if (spanBase == fHead) {
          continue;
        }
        if (ptT.segment == this) {
          continue;
        }
        OpSpan? span = spanBase.upCastable();
        // FIXME?: this assumes that if the opposite segment is coincident then no more
        // coincidence needs to be detected. This may not be true.
        if (span != null && span.containsCoincidenceSegment(opp)) {
          continue;
        }
        if (spanBase.containsCoinEndSegment(opp)) {
          continue;
        }
        OpPtT? priorPtT;
        OpPtT? priorStopPtT;
        // find prior span containing opp segment
        OpSegment? priorOpp;
        OpSpan? priorTest = spanBase.prev;
        while (null == priorOpp && priorTest != null) {
          priorStopPtT = priorPtT = priorTest.ptT;
          while ((priorPtT = priorPtT!.next) != priorStopPtT) {
            if (priorPtT!.deleted) {
              continue;
            }
            OpSegment segment = priorPtT.span.segment;
            if (segment == opp) {
              prior = priorTest;
              priorOpp = opp;
              break;
            }
          }
          priorTest = priorTest.prev;
        }
        if (null == priorOpp) {
          continue;
        }
        if (priorPtT == ptT) {
          continue;
        }
        OpPtT oppStart = prior!.ptT;
        OpPtT oppEnd = spanBase.ptT;
        bool swapped = priorPtT!.fT > ptT.fT;
        if (swapped) {
          OpPtT? tempP = priorPtT;
          priorPtT = ptT;
          ptT = tempP!;
          tempP = oppStart;
          oppStart = oppEnd;
          oppEnd = tempP;
        }
        OpCoincidence coincidences = parent.fState.coincidence!;
        OpPtT rootPriorPtT = priorPtT.span.ptT;
        OpPtT rootPtT = ptT.span.ptT;
        OpPtT rootOppStart = oppStart.span.ptT;
        OpPtT rootOppEnd = oppEnd.span.ptT;
        if (!coincidences.contains(rootPriorPtT, rootPtT, rootOppStart, rootOppEnd)) {
          if (testForCoincidence(rootPriorPtT, rootPtT, prior, spanBase, opp)) {
            // mark coincidence
            if (!coincidences.extend(rootPriorPtT, rootPtT, rootOppStart, rootOppEnd)) {
              coincidences.add(rootPriorPtT, rootPtT, rootOppStart, rootOppEnd);
            }
            if (kDebugCoincidence) {
              assert(coincidences.contains(rootPriorPtT, rootPtT, rootOppStart, rootOppEnd));
            }
            result = true;
          }
        }
        if (swapped) {
          OpPtT tempP = priorPtT;
          priorPtT = ptT;
          ptT = tempP;
        }
      }
    } while ((spanBase = spanBase.isFinal() ? null : spanBase.upCast.next) != null);
    _clearVisited(fHead);
    return result;
  }

  bool testForCoincidence(OpPtT priorPtT, OpPtT ptT,
      OpSpanBase prior, OpSpanBase spanBase, OpSegment opp) {
    // Average t, find mid point.
    double midT = (prior.t + spanBase.t) / 2;
    ui.Offset midPt = ptAtT(midT);
    bool coincident = true;
    // if the mid pt is not near either end pt, project perpendicular through opp seg
    if (!approximatelyEqualPoints(priorPtT.fPt.dx, priorPtT.fPt.dy, midPt.dx, midPt.dy)
        && !approximatelyEqualPoints(ptT.fPt.dx, ptT.fPt.dy, midPt.dx, midPt.dy)) {
      if (priorPtT.span == ptT.span) {
        return false;
      }
      coincident = false;

      // Find intersection from perpendicular ray from midpoint on curve to
      // opposing curve.
      Intersections i = Intersections();
      TCurve tCurve = tCurveFromSegment(this);
      TCurve curvePart = tCurve.subDivide(prior.ptT.fT, spanBase.ptT.fT);
      ui.Offset dxdy = curvePart.dxdyAtT(0.5);
      ui.Offset partMidPt = curvePart.ptAtT(0.5);
      DLine ray = DLine(midPt.dx, midPt.dy, partMidPt.dx + dxdy.dy,
          partMidPt.dy - dxdy.dx);
      TCurve oppPart = tCurveFromSegment(opp).subDivide(priorPtT.span.ptT.fT, ptT.span.ptT.fT);
      oppPart.intersectRay(i, ray);
      // Measure distance and see if it's small enough to denote coincidence.
      for (int index = 0; index < i.fUsed; ++index) {
        if (!SPath.between(0, i.fT0[index], 1)) {
          continue;
        }
        double oppPtX = i.ptX[index];
        double oppPtY = i.ptY[index];
        if (approximatelyEqualPoints(oppPtX, oppPtY, midPt.dx, midPt.dy)) {
          // the coincidence can occur at almost any angle
          coincident = true;
        }
      }
    }
    return coincident;
  }

  // Reset visited flags.
  void _clearVisited(OpSpanBase? span) {
    do {
      OpPtT ptT = span!.ptT;
      OpPtT stopPtT = ptT;
      while ((ptT = ptT.next!) != stopPtT) {
        OpSegment opp = ptT.segment;
        opp.resetVisited();
      }
    } while (!span.isFinal() && (span = span.upCast.next) != null);
  }

  void calcAngles() {
    OpSpan head = fHead!;
    bool activePrior = head.isCanceled;
    if (activePrior && head.simple) {
      addStartSpan();
    }
    OpSpan prior = head;
    OpSpanBase spanBase = head.next!;
    while (spanBase != fTail) {
      if (activePrior) {
        OpAngle priorAngle = OpAngle(spanBase, prior);
        spanBase.fromAngle = priorAngle;
      }
      OpSpan span = spanBase.upCast;
      bool active = !span.isCanceled;
      OpSpanBase? next = span.next;
      if (active) {
        OpAngle angle = OpAngle(span, next!);
        span.toAngle = angle;
      }
      activePrior = active;
      prior = span;
      spanBase = next!;
    }
    if (activePrior && !fTail!.simple) {
      addEndSpan();
    }
  }

  bool sortAngles() {
    OpSpanBase? span = fHead;
    do {
      OpAngle? fromAngle = span!.fromAngle;
      OpAngle? toAngle = span.isFinal() ? null : span.upCast.toAngle;
      if (null == fromAngle && null == toAngle) {
        continue;
      }
      OpAngle? baseAngle = fromAngle;
      if (fromAngle != null && toAngle != null) {
        if (!fromAngle.insert(toAngle)) {
          return false;
        }
      } else if (null == fromAngle) {
        baseAngle = toAngle;
      }
      OpPtT? ptT = span.ptT;
      OpPtT? stopPtT = ptT;
      int safetyNet = 1000000;
      do {
        if (0 == --safetyNet) {
          return false;
        }
        OpSpanBase oSpan = ptT!.span;
        if (oSpan == span) {
          continue;
        }
        // ptT in loop is on opposite span.
        OpAngle? oAngle = oSpan.fromAngle;
        if (oAngle != null) {
          if (!oAngle.loopContains(baseAngle!)) {
            baseAngle.insert(oAngle);
          }
        }
        if (!oSpan.isFinal()) {
          oAngle = oSpan.upCast.toAngle;
          if (oAngle != null) {
            if (!oAngle.loopContains(baseAngle!)) {
              baseAngle.insert(oAngle);
            }
          }
        }
      } while ((ptT = ptT.next) != stopPtT);
      if (baseAngle!.loopCount() == 1) {
        span.fromAngle = null;
        if (toAngle != null) {
          span.upCast.toAngle = null;
        }
        baseAngle = null;
      }
      if (kDebugSort) {
        assert(null != baseAngle || baseAngle!.loopCount() > 1);
      }
    } while (!span.isFinal() && (span = span.upCast.next) != null);
    return true;
  }

  OpAngle addStartSpan() {
    OpAngle angle = new OpAngle(fHead!, fHead!.next!);
    fHead!.toAngle = angle;
    return angle;
  }


  OpAngle addEndSpan() {
    OpSpanBase tail = fTail!;
    OpAngle angle = OpAngle(tail, tail.prev!);
    tail.fromAngle = angle;
    return angle;
  }

  OpSpan? findSortableTop(List<OpContour> contourList) {
    OpSpan? span = fHead;
    OpSpanBase? next;
    do {
      next = span!.next;
      if (span.done) {
        continue;
      }
      if (span.fWindSum != kMinS32) {
        return span;
      }
      if (span.sortableTop(contourList)) {
        return span;
      }
    } while (!next!.isFinal() && (span = next.upCast) != null);
    return null;
  }

  void rayCheck(OpRayHit base, int opRayDir, List<OpRayHit> hits) {
    if (!sidewaysOverlap(bounds, base.fPt, opRayDir)) {
      return;
    }
    double baseXY = (opRayDir & 1) == 0 ? base.fPt.dx : base.fPt.dy;
    double boundsXY = rectSide(bounds, opRayDir);
    bool checkLessThan = lessThan(opRayDir);
    if (!approximatelyEqualT(baseXY, boundsXY) && (baseXY < boundsXY) == checkLessThan) {
      return;
    }
    List<double> tVals = [];
    double baseYX = (opRayDir & 1) == 0 ? base.fPt.dy : base.fPt.dx;
    int xyIndex = (opRayDir & 1) == 0 ? 0 : 1;
    int roots = curveIntercept(verb * 2 + xyIndex, points, weight, baseYX, tVals);
    for (int index = 0; index < roots; ++index) {
      double t = tVals[index];
      if (base.fSpan.segment == this && approximatelyEqualT(base.fT, t)) {
        continue;
      }
      ui.Offset slope = ui.Offset.zero;
      ui.Offset pt;
      bool valid = false;
      if (approximatelyZero(t)) {
        pt = ui.Offset(points[0], points[1]);
      } else if (approximatelyEqualT(t, 1)) {
        int pointCount_1 = pathOpsVerbToPoints(verb);
        pt = ui.Offset(points[pointCount_1 * 2], points[pointCount_1 * 2 + 1]);
      } else {
        assert(SPath.between(0, t, 1));
        pt = ptAtT(t);
        if (approximatelyEqualPoints(pt.dx, pt.dy, base.fPt.dx, base.fPt.dy)) {
          if (base.fSpan.segment == this) {
            continue;
          }
        } else {
          double ptXY = (opRayDir & 1) == 0 ? pt.dx : pt.dy;
          if (!approximatelyEqualT(baseXY, ptXY) && (baseXY < ptXY) == checkLessThan) {
            continue;
          }
          slope = dxdyAtT(t);
          if (verb == SPathVerb.kCubic && base.fSpan.segment == this
                  && roughlyEqual(base.fT, t)
                  && roughlyEqualPoints(pt.dx, pt.dy, base.fPt.dx, base.fPt.dy)) {
            continue;
          }
          if ((opRayDir & 1) == 0) {
            if (slope.dy.abs() * 10000 > slope.dx.abs()) {
              valid = true;
            }
          } else {
            if (slope.dx.abs() * 10000 > slope.dy.abs()) {
              valid = true;
            }
          }
        }
      }
      OpSpan? span = windingSpanAtT(t);
      if (span == null) {
        valid = false;
      } else if (0 == span.windValue() && 0 == span.oppValue()) {
        continue;
      }
      hits.insert(0, OpRayHit(pt, slope, span!, t, valid, 0));
    }
  }

  OpSpan? windingSpanAtT(double tHit) {
    OpSpan? span = fHead;
    OpSpanBase? next;
    do {
      next = span!.next;
      if (approximatelyEqualT(tHit, next!.t)) {
        return null;
      }
      if (tHit < next.t) {
        return span;
      }
    } while (!next.isFinal() && (span = next.upCast) != null);
    return null;
  }

  // return outerWinding * innerWinding > 0
  //      || ((outerWinding + innerWinding < 0) ^ ((outerWinding - innerWinding) < 0)))
  static bool useInnerWinding(int outerWinding, int innerWinding) {
    assert(outerWinding != kMaxS32);
    assert(innerWinding != kMaxS32);
    int absOut = outerWinding.abs();
    int absIn = innerWinding.abs();
    bool result = absOut == absIn ? outerWinding < 0 : absOut < absIn;
    return result;
  }

  /// [markAngle] requires last span as result so it can set
  /// [OpAngle.fLastMarked].
  _MarkAndChaseResult markAndChaseWinding(OpSpanBase? start, OpSpanBase end, int winding) {
    OpSpan? spanStart = start!.starter(end);
    int step = start.step(end);
    bool success = markWinding(spanStart!, winding);
    OpSpanBase? last;
    OpSegment other = this;
    int safetyNet = 100000;
    while (other != null) {
      _NextChase next = other.nextChase(start!, step, spanStart!, last);
      start = next.start;
      step = next.step;
      spanStart = next.start!.upCast;
      last = next.last;
      if (next.segment == null) {
        break;
      } else {
        other = next.segment!;
      }
      if (0 == --safetyNet) {
        return _MarkAndChaseResult(false, last);
      }
      if (spanStart.windSum != kMinS32) {
        // assert(spanStart.windSum  == winding);   // FIXME: is this assert too aggressive?
        assert(null == last);
        break;
      }
      other.markWinding(spanStart, winding);
    }
    return _MarkAndChaseResult(success, last);
  }

  _MarkAndChaseResult markAndChaseWindingOpp(OpGlobalState globalState,
      OpSpanBase? start, OpSpanBase end,
        int winding, int oppWinding) {
    OpSpan? spanStart = start!.starter(end);
    int step = start.step(end);
    bool success = markWindingOpp(spanStart!, winding, oppWinding);
    OpSpanBase? last;
    OpSegment other = this;
    int safetyNet = 100000;
    while (other != null) {
      _NextChase next = other.nextChase(start!, step, spanStart!, last);
      start = next.start;
      step = next.step;
      spanStart = next.start!.upCast;
      last = next.last;
      if (next.segment == null) {
        break;
      } else {
        other = next.segment!;
      }
      if (0 == --safetyNet) {
        return _MarkAndChaseResult(false, last);
      }
      if (spanStart.windSum != kMinS32) {
        if (operand == other.operand) {
          if (spanStart.windSum != winding || spanStart.oppSum != oppWinding) {
            globalState.setWindingFailed();
            // ... but let it succeed anyway
            return _MarkAndChaseResult(true, last);
          }
        } else {
          if (spanStart.windSum != oppWinding || spanStart.oppSum != winding) {
            return _MarkAndChaseResult(false, last);
          }
        }
        assert(last != null);
        break;
      }
      if (operand == other.operand) {
        other.markWindingOpp(spanStart, winding, oppWinding);
      } else {
        other.markWindingOpp(spanStart, oppWinding, winding);
      }
    }
    return _MarkAndChaseResult(success, last);
  }

  _NextChase nextChase(OpSpanBase startSpan, int step, OpSpan minSpan,
        OpSpanBase? last) {
    _NextChase result = _NextChase(startSpan, step, minSpan, last);
    OpSpanBase origStart = startSpan;
    OpSpanBase endSpan = (step > 0 ? origStart.upCast.next : origStart.prev)!;
    OpAngle? angle = step > 0 ? endSpan.fromAngle : endSpan.upCast.toAngle;
    OpSpanBase? foundSpan;
    OpSpanBase? otherEnd;
    OpSegment? other;
    if (angle == null) {
      if (endSpan.ptT.fT != 0 && endSpan.ptT.fT != 1) {
        return result;
      }
      OpPtT otherPtT = endSpan.ptT.next!;
      other = otherPtT.segment;
      foundSpan = otherPtT.span;
      otherEnd = step > 0
              ? foundSpan.upCastable() != null ? foundSpan.upCast.next : null
              : foundSpan.prev;
    } else {
      int loopCount = angle.loopCount();
      if (loopCount > 2) {
        result.last = endSpan;
        return result;
      }
      OpAngle? next = angle.next;
      if (null == next) {
        return result;
      }
      if (kDebugWinding) {
        OpContour contour1 = angle.segment.parent;
        OpContour contour2 = next.segment.parent;
        if (angle.debugSign() != next.debugSign() && !contour1.isXor
            && !contour2.isXor) {
          print("PathOp mismatched angle signs");
        }
      }
      other = next.segment;
      foundSpan = endSpan = next.start!;
      otherEnd = next.end;
    }
    if (null == otherEnd) {
      return result;
    }
    int foundStep = foundSpan.step(otherEnd);
    if (step != foundStep) {
      result.last = endSpan;
      return result;
    }
    assert(result.start != null);
    OpSpan origMin = step < 0 ? origStart.prev! : origStart.upCast;
    OpSpan foundMin = foundSpan.starter(otherEnd);
    if (foundMin.windValue != origMin.windValue
            || foundMin.oppValue != origMin.oppValue) {
      result.last = endSpan;
      result.segment = null;
      return result;
    }
    result.start = foundSpan;
    result.step = foundStep;
    result.minSpan = foundMin;
    result.segment = other;
    return result;
  }

  /// Sets the winding value of a span (thats not done) on this segment.
  bool markWinding(OpSpan span, int winding) {
    assert(this == span.segment);
    assert(winding != 0);
    if (span.done) {
      return false;
    }
    span.windSum = winding;
    debugValidate();
    return true;
  }

  /// Sets the winding and opposite winding value of a span (thats not done)
  /// on this segment.
  bool markWindingOpp(OpSpan span, int winding, int oppWinding) {
    assert(this == span.segment);
    assert(winding != 0 || oppWinding != 0);
    if (span.done) {
      return false;
    }
    span.windSum = winding;
    span.oppSum = oppWinding;
    debugValidate();
    return true;
  }

  bool activeWinding(OpSpanBase start, OpSpanBase end) {
    int sumWinding = updateWinding(end, start);
    return _activeWinding(start, end, WindingStat());
  }

  bool _activeWinding(OpSpanBase start, OpSpanBase end, WindingStat stat) {
    setUpWinding(start, end, stat);
    bool from = stat.maxWinding != 0;
    bool to = stat.sumWinding  != 0;
    return from != to;
  }

  void setUpWinding(OpSpanBase start, OpSpanBase end, WindingStat windingStat) {
    int deltaSum = spanSign(start, end);
    windingStat.maxWinding = windingStat.sumWinding;
    if (windingStat.sumWinding == kMinS32) {
      return;
    }
    windingStat.sumWinding -= deltaSum;
  }

  /// Returns winding signed value for start or end based on t.
  static int spanSign(OpSpanBase start, OpSpanBase end) {
    int result = start.t < end.t ? -start.upCast.windValue()
        : end.upCast.windValue();
    return result;
  }

  int updateWinding(OpSpanBase start, OpSpanBase end) {
    OpSpan lesser = start.starter(end)!;
    int winding = lesser.windSum;
    if (winding == kMinS32) {
      winding = lesser.computeWindSum();
    }
    if (winding == kMinS32) {
      return winding;
    }
    int spanWinding = OpSegment.spanSign(start, end);
    if (winding != 0 && useInnerWinding(winding - spanWinding, winding)
        && winding != kMaxS32) {
      winding -= spanWinding;
    }
    return winding;
  }
}

TCurve tCurveFromSegment(OpSegment seg) {
  switch (seg.verb) {
    case SPathVerb.kQuad:
      return TQuad(Quad(seg.points));
    case SPathVerb.kConic:
      return TConic(Conic.fromPoints(seg.points, seg.weight));
    case SPathVerb.kCubic:
      return TCubic(Cubic.fromPoints(seg.points));
    case SPathVerb.kLine:
    default:
      return TLine(DLine.fromPoints(seg.points));
  }
}

class _DCurve {
  _DCurve(this.verb, this.points, this.weight);
  final int verb;
  final Float32List points;
  final double weight;
}

class _SegmentBreakResult {
  _SegmentBreakResult.success(this.startOver) : success = true;
  _SegmentBreakResult.fail(this.startOver) : success = false;
  final bool success;
  final bool startOver;
}

// Very light weight check, should only be used for inequality check.
bool _wayRoughlyEqual(ui.Offset a, ui.Offset b) {
  double magnitude = math.max(a.dx.abs(), math.max(a.dy.abs(),
      math.max(b.dx.abs(), b.dy.abs())));
  ui.Offset delta = a - b;
  double largestDiff = math.max(delta.dx, delta.dy);
  return roughlyZeroWhenComparedTo(largestDiff, magnitude);
}

bool sidewaysOverlap(ui.Rect rect, ui.Offset pt, int opRayDir) {
  if ((opRayDir & 1) != 0) {
    return approximatelyBetween(rect.top, pt.dy, rect.bottom);
  } else {
    return approximatelyBetween(rect.left, pt.dx, rect.right);
  }
}

double rectSide(ui.Rect r, int opRayDir) {
  switch (opRayDir) {
    case OpRayDir.kLeft:
      return r.left;
    case OpRayDir.kTop:
      return r.top;
    case OpRayDir.kRight:
      return r.right;
    case OpRayDir.kBottom:
      return r.bottom;
  }
  assert(false);
  return 0;
}

bool lessThan(int opRayDir) => (opRayDir & 2) == 0;

int curveIntercept(int lineInterceptIndex, Float32List points, double weight, double intercept, List<double> roots) {
  switch(lineInterceptIndex) {
    case 2:
      if (points[1] == points[3]) {
        return 0;
      }
      final DLine line = DLine.fromPoints(points);
      roots.add(_horizontalIntercept(line, intercept));
      return SPath.between(0, roots[0], 1) ? 1 : 0;
    case 3:
      if (points[0] == points[2]) {
        return 0;
      }
      final DLine line = DLine.fromPoints(points);
      roots.add(_verticalIntercept(line, intercept));
      return SPath.between(0, roots[0], 1) ? 1 : 0;
    case 4:
      return LineQuadraticIntersections.computeHorizontalIntersect(points, intercept, roots);
    case 5:
      return LineQuadraticIntersections.computeVerticalIntersect(points, intercept, roots);
    case 6:
      return LineConicIntersections.computeHorizontalIntersect(Conic.fromPoints(points, weight), intercept, roots);
    case 7:
      return LineConicIntersections.computeVerticalIntersect(Conic.fromPoints(points, weight), intercept, roots);
    case 8:
      return LineCubicIntersections.computeHorizontalIntersect(Cubic.fromPoints(points), intercept, roots);
    case 9:
      return LineCubicIntersections.computeVerticalIntersect(Cubic.fromPoints(points), intercept, roots);
  }
  assert(false);
  return 0;
}

class _NextChase {
  _NextChase(this.start, this.step, this.minSpan, this.last);

  OpSpanBase? start;
  int step;
  OpSpan? minSpan;
  OpSpanBase? last;

  /// Next segment.
  OpSegment? segment;
}

class _MarkAndChaseResult {
  _MarkAndChaseResult(this.success, this.last);
  final bool success;
  final OpSpanBase? last;
}

class WindingStat {
  int maxWinding = 0;
  int sumWinding = 0;
}
