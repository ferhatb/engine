// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Angle between two consecutive spans.
///
/// Pre-computes tangent and start/end sectors of spans to be able to
/// order segments.
class OpAngle {
  OpAngle(this.start, this.end) {
    _init();
  }

  final OpSpanBase? start;
  final OpSpanBase? end;
  OpSpanBase? fComputedEnd;
  OpSpanBase? fLastMarked;

  // If sectors can't be pre-computed in constructor,
  // delays computation of sector until segment length is computed.
  bool _needsComputeSector = false;
  bool fComputedSector = false;
  bool fCheckCoincidence = false;
  bool fTangentsAmbiguous = false;
  TCurve? fOriginalCurvePart;
  CurveSweep? fPart;

  // Used to sort a pair of lines or line-like sections.
  LineParameters fTangentHalf = LineParameters();
  double fSide = 0;

  bool fUnorderable = false;

  /// Next angle (linked list).
  OpAngle? _next;
  OpAngle? get next => _next;

  int fSectorMask = 0;
  int fSectorStart = 0;
  int fSectorEnd = 0;

  bool get unorderable => fUnorderable;

  OpSegment get segment => start!.segment;

  void _init() {
    fComputedEnd = end;
    assert(start != end);
    _next = null;
    _needsComputeSector = false;
    fComputedSector = false;
    fCheckCoincidence = false;
    fTangentsAmbiguous = false;
    _setSpans();
    _setSector();
  }

  void _setSpans() {
    assert(start != end);
    fLastMarked = null;
    fUnorderable = start == null;
    if (fUnorderable) {
      return;
    }
    OpSegment segment = start!.segment;
    TCurve tCurve = tCurveFromSegment(segment);
    TCurve curvePart = tCurve.subDivide(start!.ptT.fT, end!.ptT.fT);
    fOriginalCurvePart = curvePart.clone();
    int verb = segment.verb;
    fPart = CurveSweep(curvePart)
      ..setCurveHullSweep(verb);
    if (SPathVerb.kLine != verb && !fPart!.isCurve()) {
      ui.Offset p = fPart!.fCurve[pathOpsVerbToPoints(verb)];
      fPart!.fCurve.setPoint(1, p.dx, p.dy);
      fOriginalCurvePart!.setPoint(1, fPart!.fCurve[1].dx, fPart!.fCurve[1].dy);
      fTangentHalf.lineEndOffsets(fPart!.fCurve[0], fPart!.fCurve[1]);
      fSide = 0;
    }
    switch (verb) {
      case SPathVerb.kLine:
        assert(start != end);
        ui.Offset cP1 = tCurve[start!.ptT.fT < end!.ptT.fT ? 1 : 0];
        fTangentHalf.lineEndOffsets(start!.ptT.fPt, cP1);
        fSide = 0;
        return;
      case SPathVerb.kQuad:
      case SPathVerb.kConic:
        LineParameters tangentPart = LineParameters();
        tangentPart.quadEndPoints((curvePart as TQuad).quad.points);
        ui.Offset p = curvePart[2];
        fSide = -tangentPart.pointDistance(
            p.dx, p.dy); // not normalized -- compare sign only
        break;
      case SPathVerb.kCubic:
        LineParameters tangentPart = LineParameters();
        Cubic cubic = (curvePart as TCubic).cubic;
        tangentPart.cubicPart(cubic.toPoints());
        ui.Offset p = curvePart[3];
        fSide = -tangentPart.pointDistance(p.dx, p.dy);
        List<double> testTs = [];
        int testCount = cubic.findInflections(testTs);
        double startT = start!.ptT.fT;
        double endT = end!.ptT.fT;
        double limitT = endT;
        int index;
        for (index = 0; index < testCount; ++index) {
          if (!SPath.between(startT, testTs[index], limitT)) {
            testTs[index] = -1;
          }
        }
        testTs[testCount++] = startT;
        testTs[testCount++] = endT;
        testTs.sort();
        double bestSide = 0;
        int testCases = (testCount << 1) - 1;
        index = 0;
        while (testTs[index] < 0) {
          ++index;
        }
        index <<= 1;
        for (; index < testCases; ++index) {
          int testIndex = index >> 1;
          double testT = testTs[testIndex];
          if ((index & 1) != 0) {
            testT = (testT + testTs[testIndex + 1]) / 2;
          }
          // OPTIMIZE: could avoid call for t == startT, endT
          ui.Offset pt = cubic.ptAtT(testT);
          LineParameters tangentPart = LineParameters();
          tangentPart.cubicEndPoints(cubic.toPoints());
          double testSide = tangentPart.pointDistance(pt.dx, pt.dy);
          if (bestSide.abs() < testSide.abs()) {
            bestSide = testSide;
          }
        }
        fSide = -bestSide; // compare sign only
        break;
      default:
        assert(false);
        break;
    }
  }

  void _setSector() {
    if (null == start) {
      fUnorderable = true;
      return;
    }
    OpSegment segment = start!.segment;
    int verb = segment.verb;
    CurveSweep part = fPart!;
    fSectorStart = findSector(verb, part.fSweep[0].dx, part.fSweep[0].dy);
    if (fSectorStart < 0) {
      fSectorStart = fSectorEnd = -1;
      fSectorMask = 0;
      _needsComputeSector = true; // can't determine sector until segment length can be found
      return;
    }
    if (!fPart!
        .isCurve()) { // if it's a line or line-like, note that both sectors are the same
      assert(fSectorStart >= 0);
      fSectorEnd = fSectorStart;
      fSectorMask = 1 << fSectorStart;
      return;
    }
    assert(SPathVerb.kLine != verb);
    fSectorEnd = findSector(verb, fPart!.fSweep[1].dx, fPart!.fSweep[1].dy);
    if (fSectorEnd < 0) {
      fSectorStart = fSectorEnd = -1;
      fSectorMask = 0;
      _needsComputeSector = true; // can't determine sector until segment length can be found
      return;
    }
    if (fSectorEnd == fSectorStart
    && (fSectorStart & 3) != 3) { // if the sector has no span, it can't be an exact angle
      fSectorMask = 1 << fSectorStart;
      return;
    }
    bool crossesZero = _checkCrossesZero();
    int startSector = math.min(fSectorStart, fSectorEnd);
    bool curveBendsCCW = (fSectorStart == startSector) ^ crossesZero;
    // bump the start and end of the sector span if they are on exact compass points
    if ((fSectorStart & 3) == 3) {
      fSectorStart = (fSectorStart + (curveBendsCCW ? 1 : 31)) & 0x1f;
    }
    if ((fSectorEnd & 3) == 3) {
      fSectorEnd = (fSectorEnd + (curveBendsCCW ? 31 : 1)) & 0x1f;
    }
    crossesZero = _checkCrossesZero();
    startSector = math.min(fSectorStart, fSectorEnd);
    int end = math.max(fSectorStart, fSectorEnd);
    if (!crossesZero) {
      fSectorMask = 0xFFFFFFFF >> (31 - end + startSector) << startSector;
    } else {
      fSectorMask = 0xFFFFFFFF -1 >> (31 - startSector) | (0xFFFFFFFF << end);
    }
  }

  // The original angle span is too short to get meaningful sector information.
  // Lengthen it until it is long enough to be meaningful or leave it unset if
  // lengthening it would cause it to intersect one of the adjacent angles
  //
  // Returns success if angle is orderable.
  bool computeSector() {
    if (fComputedSector) {
      return !fUnorderable;
    }
    fComputedSector = true;
    bool stepUp = start!.t < end!.t;
    OpSpanBase? checkEnd = end;
    if (checkEnd!.isFinal() && stepUp) {
      // Can't lengthen end since it is already at t = 1
      fUnorderable = true;
      return false;
    }
    do {
      // Advance end
      OpSegment other = checkEnd!.segment;
      OpSpanBase? oSpan = other.fHead;
      bool foundSpan = false;
      do {
        if (oSpan!.segment != segment) {
          continue;
        }
        if (oSpan == checkEnd) {
          continue;
        }
        if (approximatelyEqualT(oSpan.t, checkEnd.t)) {
          continue;
        }
        // Found oSpan that is on same segment and t values are not close.
        foundSpan = true;
        break;
      } while (!oSpan.isFinal() && (oSpan = oSpan.upCast.next) != null);
      if (foundSpan) {
        break;
      }
      checkEnd = stepUp ? !checkEnd.isFinal()
          ? checkEnd.upCast.next : null
          : checkEnd.prev;
    } while (checkEnd != null);
    OpSpanBase? computedEnd = stepUp ?
    checkEnd != null ? checkEnd.prev : end!.segment.fHead
        : checkEnd != null ? checkEnd.upCast.next : end!.segment.fTail;
    if (checkEnd == end || computedEnd == end || computedEnd == start) {
      fUnorderable = true;
      return false;
    }
    if (stepUp != (start!.t < computedEnd!.t)) {
      fUnorderable = true;
      return false;
    }

    OpAngle computedAngle = OpAngle(start, computedEnd);
    computedAngle._copyTo(this);
    return !fUnorderable;
  }

  // Copy all fields except start, end spans.
  void _copyTo(OpAngle target) {
    target.fLastMarked = fLastMarked;
    target._needsComputeSector = _needsComputeSector;
    target.fComputedSector = fComputedSector;
    target.fCheckCoincidence = fCheckCoincidence;
    target.fTangentsAmbiguous = fTangentsAmbiguous;
    target.fOriginalCurvePart = fOriginalCurvePart;
    target.fPart = fPart;
    target.fTangentHalf = fTangentHalf;
    target.fSide = fSide;
    target.fUnorderable = fUnorderable;
    target._next = _next;
    target.fSectorMask = fSectorMask;
    target.fSectorStart = fSectorStart;
    target.fSectorEnd = fSectorEnd;
  }

  ///      y<0 y==0 y>0  x<0 x==0 x>0 xy<0 xy==0 xy>0
  ///  0    x                      x               x
  ///  1    x                      x          x
  ///  2    x                      x    x
  ///  3    x                  x        x
  ///  4    x             x             x
  ///  5    x             x                   x
  ///  6    x             x                        x
  ///  7         x        x                        x
  ///  8             x    x                        x
  ///  9             x    x                   x
  ///  10            x    x             x
  ///  11            x         x        x
  ///  12            x             x    x
  ///  13            x             x          x
  ///  14            x             x               x
  ///  15        x                 x               x
  int findSector(int verb, double x, double y) {
    double absX = x.abs();
    double absY = y.abs();
    double xy = SPathVerb.kLine == verb ||
        almostEqualUlps(absX, absY) ? 0 : absX - absY;
    int index = x < 0 ? 0 : (x > 0 ? 2 : 1);
    index += y < 0 ? 0 : y > 0 ? 6 : 3;
    index += xy < 0 ? 0 : xy > 0 ? 18 : 9;
    return sedecimant[index] * 2 + 1;
  }

  /// Maps x and y sign to sedecimant. The list is triplets for (x<0, x=0, x>0).
  ///
  /// Sedecimant = partitioning into 16.
  static const List<int> sedecimant = [
    // abs(x) <  abs(y)
    4,  3,  2,
    7, -1, 15,
    10, 11, 12,
    // abs(x) == abs(y)
    5, -1,  1,
    -1, -1, -1,
    9, -1, 13,
    // abs(x) > abs(y)
    6,  3,  0,
    7, -1, 15,
    8, 11, 14
  ];

  // Checks if section start to end sweep crosses sector 0 to determine
  // if curve bends clockwise or ccw.
  bool _checkCrossesZero() {
    int start = math.min(fSectorStart, fSectorEnd);
    int end = math.max(fSectorStart, fSectorEnd);
    bool crossesZero = end - start > 16;
    return crossesZero;
  }

  int loopCount() {
    int count = 0;
    OpAngle first = this;
    OpAngle? next = first;
    do {
      next = next!._next;
      ++count;
    } while (next != null && next != first);
    return count;
  }

  bool loopContains(OpAngle angle) {
    if (null == _next) {
      return false;
    }
    OpAngle first = this;
    OpAngle? loop = this;
    OpSegment tSegment = angle.start!.segment;
    double tStart = angle.start!.ptT!.fT;
    double tEnd = angle.end!.ptT!.fT;
    do {
        OpSegment lSegment = loop!.start!.segment;
        if (lSegment != tSegment) {
            continue;
        }
        double lStart = loop.start!.ptT.fT;
        if (lStart != tEnd) {
            continue;
        }
        double lEnd = loop.end!.ptT.fT;
        if (lEnd == tStart) {
            return true;
        }
    } while ((loop = loop._next) != first);
    return false;
  }

  // TODO: optimize: if this loops to only one other angle, after first
  // compare fails, insert on other side.
  // TODO: optimize: return where insertion succeeded. Then, start next
  // insertion on opposite side.
  bool insert(OpAngle angle) {
    if (angle._next != null) {
      if (loopCount() >= angle.loopCount()) {
        if (!merge(angle)) {
          return true;
        }
      } else if (_next != null) {
        if (!angle.merge(this)) {
          return true;
        }
      } else {
        angle.insert(this);
      }
      return true;
    }
    bool singleton = null == _next;
    if (singleton) {
      _next = this;
    }
    OpAngle next = _next!;
    if (next._next == this) {
      if (singleton || angle.after(this)) {
        _next = angle;
        angle._next = next;
      } else {
        next._next = angle;
        angle._next = this;
      }
      debugValidateNext();
      return true;
    }
    OpAngle last = this;
    bool flipAmbiguity = false;
    do {
      assert(last._next == next);
      if (angle.after(last) ^ (angle.fTangentsAmbiguous & flipAmbiguity)) {
        last._next = angle;
        angle._next = next;
        debugValidateNext();
        return true;
      }
      last = next;
      if (last == this) {
        if (flipAmbiguity) {
          return false;
        }
        // We're in a loop. If a sort was ambiguous, flip it to end the
        // loop.
        flipAmbiguity = true;
      }
      next = next._next!;
    } while (true);
  }

  bool merge(OpAngle angle) {
    assert(_next != null);
    assert(angle._next != null);
    OpAngle working = angle;
    do {
      if (this == working) {
        return false;
      }
      working = working._next!;
    } while (working != angle);

    do {
      OpAngle next = working._next!;
      working._next = null;
      insert(working);
      working = next;
    } while (working != angle);
    // it's likely that a pair of the angles are unorderable
    debugValidateNext();
    return true;
  }

  /// Checks if angle is between test and test.next angles.
  ///
  /// Quarter angle values for sector
  ///
  /// 31   x > 0, y == 0              horizontal line (to the right)
  /// 0    x > 0, y == epsilon        quad/cubic horizontal tangent eventually going +y
  /// 1    x > 0, y > 0, x > y        nearer horizontal angle
  /// 2                  x + e == y   quad/cubic 45 going horiz
  /// 3    x > 0, y > 0, x == y       45 angle
  /// 4                  x == y + e   quad/cubic 45 going vert
  /// 5    x > 0, y > 0, x < y        nearer vertical angle
  /// 6    x == epsilon, y > 0        quad/cubic vertical tangent eventually going +x
  /// 7    x == 0, y > 0              vertical line (to the top)
  ///
  ///                                       8  7  6
  ///                                  9       |       5
  ///                               10         |          4
  ///                             11           |            3
  ///                           12  \          |           / 2
  ///                          13              |              1
  ///                         14               |               0
  ///                         15 --------------+------------- 31
  ///                         16               |              30
  ///                          17              |             29
  ///                           18  /          |          \ 28
  ///                             19           |           27
  ///                               20         |         26
  ///                                  21      |      25
  ///                                      22 23 24
  ///
  ///
  ///
  bool after(OpAngle test) {
    OpAngle lh = test;
    OpAngle? rh = lh._next;
    assert(lh != rh);
    CurveSweep part = fPart!;
    CurveSweep lhPart = lh.fPart!;
    CurveSweep rhPart = rh!.fPart!;
    part.fCurve = fOriginalCurvePart!.clone();
    lhPart.fCurve = lh.fOriginalCurvePart!.clone();
    ui.Offset alignOffset = part.fCurve[0] - lhPart.fCurve[0];
    if (alignOffset.dx != 0 || alignOffset.dy != 0) {
      lhPart.fCurve.offset(lh.segment.verb, alignOffset);
    }
    rhPart.fCurve = rh.fOriginalCurvePart!.clone();
    alignOffset = part.fCurve[0] - rhPart.fCurve[0];
    if (alignOffset.dx != 0 || alignOffset.dy != 0) {
      rhPart.fCurve.offset(rh!.segment.verb, alignOffset);
    }
    if (lh._needsComputeSector && !lh.computeSector()) {
      return true;
    }
    if (_needsComputeSector && !computeSector()) {
      return true;
    }
    if (rh._needsComputeSector && !rh.computeSector()) {
      return true;
    }

    bool ltrOverlap = ((lh.fSectorMask | rh.fSectorMask) & fSectorMask) != 0;
    bool lrOverlap = (lh.fSectorMask & rh.fSectorMask) != 0;
    int lrOrder;  // set to -1 if either order works
    if (!lrOverlap) {  // no lh/rh sector overlap
      if (!ltrOverlap) {  // no lh/this/rh sector overlap
        return (lh.fSectorEnd > rh.fSectorStart)
          ^ (fSectorStart > lh.fSectorEnd) ^ (fSectorStart > rh.fSectorStart);
      }
      int lrGap = (rh.fSectorStart - lh.fSectorStart + 32) & 0x1f;
      // A tiny change can move the start +/- 4. The order can only be determined
      // if lr gap is not 12 to 20 or -12 to -20.
      //               -31 ..-21      1
      //               -20 ..-12     -1
      //               -11 .. -1      0
      //                 0          shouldn't get here
      //                11 ..  1      1
      //                12 .. 20     -1
      //                21 .. 31      0
      //
      lrOrder = lrGap > 20 ? 0 : lrGap > 11 ? -1 : 1;
    } else {
      lrOrder = lh.orderable(rh);
      if (!ltrOverlap && lrOrder >= 0) {
        return lrOrder == 0;
      }
    }
    int ltOrder;
    assert((lh.fSectorMask & fSectorMask) != 0 ||
        (rh.fSectorMask & fSectorMask)!= 0 || -1 == lrOrder);
    if ((lh.fSectorMask & fSectorMask) != 0) {
      ltOrder = lh.orderable(this);
    } else {
      int ltGap = (fSectorStart - lh.fSectorStart + 32) & 0x1f;
      ltOrder = ltGap > 20 ? 0 : ltGap > 11 ? -1 : 1;
    }
    int trOrder;
    if ((rh.fSectorMask & fSectorMask) != 0) {
      trOrder = orderable(rh);
    } else {
      int trGap = (rh.fSectorStart - fSectorStart + 32) & 0x1f;
      trOrder = trGap > 20 ? 0 : trGap > 11 ? -1 : 1;
    }
    if (alignmentSameSide(lh, ltOrder)) {
      ltOrder ^= 1;
    }
    if (alignmentSameSide(rh, trOrder)) {
      trOrder ^= 1;
    }
    if (lrOrder >= 0 && ltOrder >= 0 && trOrder >= 0) {
      return lrOrder != 0 ? (ltOrder & trOrder) != 0 : (ltOrder | trOrder) != 0;
    }
    // There's not enough information to sort. Get the pairs of angles in opposite
    // planes.
    // If an order is < 0, the pair is already in an opposite plane. Check the
    // remaining pairs.
    if (ltOrder == 0 && lrOrder == 0) {
      assert(trOrder < 0);
      bool lrOpposite = lh.oppositePlanes(rh);
      bool ltOpposite = lh.oppositePlanes(this);
      assert(lrOpposite != ltOpposite);
      return ltOpposite;
    } else if (ltOrder == 1 && trOrder == 0) {
      assert(lrOrder < 0);
      bool trOpposite = oppositePlanes(rh);
      return trOpposite;
    } else if (lrOrder == 1 && trOrder == 1) {
      assert(ltOrder < 0);
      bool lrOpposite = lh.oppositePlanes(rh);
      return lrOpposite;
    }
    // If a pair couldn't be ordered, there's not enough information to
    // determine the sort.
    // Refer to:  https://docs.google.com/drawings/d/1KV-8SJTedku9fj4K6fd1SB-8divuV_uivHVsSgwXICQ
    if (fUnorderable || lh.fUnorderable || rh.fUnorderable) {
      // Limit to lines; should work with curves, but wait for a failing test to
      // verify.
      if (!part.isCurve() && !lhPart.isCurve() && !rhPart.isCurve()) {
        // see if original raw data is orderable
        // if two share a point, check if third has both points in same half plane
        int ltShare = lh.fOriginalCurvePart![0] == fOriginalCurvePart![0] ? 1 : 0;
        int lrShare = lh.fOriginalCurvePart![0] == rh.fOriginalCurvePart![0] ? 1 : 0;
        int trShare = fOriginalCurvePart![0] == rh.fOriginalCurvePart![0] ? 1 : 0;
        // if only one pair are the same, the third point touches neither of the pair
        if (ltShare + lrShare + trShare == 1) {
          if (lrShare != 0) {
            int ltOOrder = lh.linesOnOriginalSide(this);
            int rtOOrder = rh.linesOnOriginalSide(this);
            if ((rtOOrder ^ ltOOrder) == 1) {
              return ltOOrder != 0;
            }
          } else if (trShare != 0) {
            int tlOOrder = linesOnOriginalSide(lh);
            int rlOOrder = rh.linesOnOriginalSide(lh);
            if ((tlOOrder ^ rlOOrder) == 1) {
              return rlOOrder != 0;
            }
          } else {
            assert(ltShare != 0);
            int trOOrder = rh.linesOnOriginalSide(this);
            int lrOOrder = lh.linesOnOriginalSide(rh);
            // result must be 0 and 1 or 1 and 0 to be valid
            if ((lrOOrder ^ trOOrder) == 1) {
              return trOOrder != 0;
            }
          }
        }
      }
    }
    if (lrOrder < 0) {
      if (ltOrder < 0) {
        return trOrder != 0;
      }
      return ltOrder != 0;
    }
    return lrOrder == 0;
  }

  // Returns true if angles are on opposite planes.
  bool oppositePlanes(OpAngle rh) {
    int startSpan = (rh.fSectorStart - fSectorStart).abs();
    return startSpan >= 8;
  }

  int orderable(OpAngle rh) {
    int result;
    if (!fPart!.isCurve()) {
      if (!rh.fPart!.isCurve()) {
        double leftX = fTangentHalf!.dx;
        double leftY = fTangentHalf.dy;
        double rightX = rh.fTangentHalf.dx;
        double rightY = rh.fTangentHalf.dy;
        double x_ry = leftX * rightY;
        double rx_y = rightX * leftY;
        if (x_ry == rx_y) {
          if (leftX * rightX < 0 || leftY * rightY < 0) {
              return 1;  // exactly 180 degrees apart
          }
          fUnorderable = true;
          rh.fUnorderable = true;
          return -1;
        }
        if (kDebugCoincidence) {
          assert(x_ry != rx_y,
              'indicates an undetected coincidence that is '
              'worth finding earlier');
        }
        return x_ry < rx_y ? 1 : 0;
      }
      if ((result = lineOnOneSide(rh, false)) >= 0) {
        return result;
      }
      if (fUnorderable || approximatelyZero(rh.fSide)) {
        fUnorderable = true;
        rh.fUnorderable = true;
        return -1;
      }
    } else if (!rh.fPart!.isCurve()) {
      if ((result = rh.lineOnOneSide(this, false)) >= 0) {
        return result != 0 ? 0 : 1;
      }
      if (rh.fUnorderable || approximatelyZero(fSide)) {
        fUnorderable = true;
        rh.fUnorderable = true;
        return -1;
      }
    } else if ((result = convexHullOverlaps(rh)) >= 0) {
      return result;
    }
    return endsIntersect(rh) ? 1 : 0;
  }

  // Given a line, see if the opposite curve's convex hull is all on one side
  // returns -1= not on one side    0 = this CW of test   1 = this CCW of test
  int lineOnOneSide(OpAngle test, bool useOriginal) {
    CurveSweep curveSweep = fPart!;
    assert(curveSweep.isCurve());
    assert(test.fPart!.isCurve());
    ui.Offset origin = curveSweep.fCurve[0];
    ui.Offset line = curveSweep.fCurve[1] - origin;
    int result = _lineOnOneSide(origin, line, test, useOriginal);
    if (kLineNotOnOneSideNotOrderable == result) {
      fUnorderable = true;
      result = -1;
    }
    return result;
  }

  static const int kLineSideClockwise = 0;
  static const int kLineSideCounterClockwise = 1;
  static const int kLineNotOnOneSide = -1;
  static const int kLineNotOnOneSideNotOrderable = -2;

  int _lineOnOneSide(ui.Offset origin, ui.Offset line, OpAngle test,
        bool useOriginal) {
    // Compute cross product between line and vectors to test curve points.
    List<double> crosses = <double>[0, 0, 0];
    int testVerb = test.segment.verb;
    int iMax = pathOpsVerbToPoints(testVerb);
    TCurve testCurve = useOriginal ? test.fOriginalCurvePart! : test.fPart!.fCurve;
    for (int index = 1; index <= iMax; ++index) {
        double xy1 = line.dx * (testCurve[index].dy - origin.dy);
        double xy2 = line.dy * (testCurve[index].dx - origin.dx);
        crosses[index - 1] = almostBequalUlps(xy1, xy2) ? 0 : xy1 - xy2;
    }
    if (crosses[0] * crosses[1] < 0) {
      return kLineNotOnOneSide;
    }
    if (SPathVerb.kCubic == testVerb) {
      if (crosses[0] * crosses[2] < 0 || crosses[1] * crosses[2] < 0) {
        return kLineNotOnOneSide;
      }
    }
    if (crosses[0] != 0) {
      return crosses[0] < 0 ? kLineSideCounterClockwise : kLineSideClockwise;
    }
    if (crosses[1] != 0) {
      return crosses[1] < 0 ? kLineSideCounterClockwise : kLineSideClockwise;
    }
    if (SPathVerb.kCubic == testVerb && crosses[2] != 0) {
      return crosses[2] < 0 ? kLineSideCounterClockwise : kLineSideClockwise;
    }
    return kLineNotOnOneSideNotOrderable;
  }

  int convexHullOverlaps(OpAngle rh) {
    List<ui.Offset> sweep = fPart!.fSweep;
    List<ui.Offset> tweep = rh.fPart!.fSweep;
    double s0xs1 = crossCheck(sweep[0], sweep[1]);
    double s0xt0 = crossCheck(sweep[0], tweep[0]);
    double s1xt0 = crossCheck(sweep[1], tweep[0]);
    bool tBetweenS = s0xs1 > 0 ? s0xt0 > 0 && s1xt0 < 0 : s0xt0 < 0 && s1xt0 > 0;
    double s0xt1 = crossCheck(sweep[0], tweep[1]);
    double s1xt1 = crossCheck(sweep[1], tweep[1]);
    tBetweenS |= s0xs1 > 0 ? s0xt1 > 0 && s1xt1 < 0 : s0xt1 < 0 && s1xt1 > 0;
    double t0xt1 = crossCheck(tweep[0], tweep[1]);
    if (tBetweenS) {
      return -1;
    }
    if ((s0xt0 == 0 && s1xt1 == 0) || (s1xt0 == 0 && s0xt1 == 0)) {
      // s0 to s1 equals t0 to t1.
      return -1;
    }
    bool sBetweenT = t0xt1 > 0 ? s0xt0 < 0 && s0xt1 > 0 : s0xt0 > 0 && s0xt1 < 0;
    sBetweenT |= t0xt1 > 0 ? s1xt0 < 0 && s1xt1 > 0 : s1xt0 > 0 && s1xt1 < 0;
    if (sBetweenT) {
      return -1;
    }
    // If all of the sweeps are in the same half plane, then the order of any
    // pair is enough.
    if (s0xt0 >= 0 && s0xt1 >= 0 && s1xt0 >= 0 && s1xt1 >= 0) {
      return 0;
    }
    if (s0xt0 <= 0 && s0xt1 <= 0 && s1xt0 <= 0 && s1xt1 <= 0) {
      return 1;
    }
    // If the outside sweeps are greater than 180 degress:
    // first assume the inital tangents are the ordering
    // if the midpoint direction matches the inital order, that is enough
    ui.Offset m0 = segment.ptAtT(midT()) - fPart!.fCurve[0];
    ui.Offset m1 = rh.segment.ptAtT(rh.midT()) - rh.fPart!.fCurve[0];
    double m0xm1 = crossCheck(m0, m1);
    if (s0xt0 > 0 && m0xm1 > 0) {
      return 0;
    }
    if (s0xt0 < 0 && m0xm1 < 0) {
      return 1;
    }
    if (tangentsDiverge(rh, s0xt0)) {
      return s0xt0 < 0 ? 1 : 0;
    }
    return m0xm1 < 0 ? 1 : 0;
  }

  double midT() => (start!.ptT.fT + end!.ptT.fT) / 2.0;

  bool tangentsDiverge(OpAngle rh, double s0xt0) {
    if (s0xt0 == 0) {
      return false;
    }
    // If the ctrl tangents are not nearly parallel, use them
    // solve for opposite direction displacement scale factor == m
    // initial dir = v1.cross(v2) == v2.x * v1.y - v2.y * v1.x
    // displacement of q1[1] : dq1 = { -m * v1.y, m * v1.x } + q1[1]
    // straight angle when : v2.x * (dq1.y - q1[0].y) == v2.y * (dq1.x - q1[0].x)
    //                       v2.x * (m * v1.x + v1.y) == v2.y * (-m * v1.y + v1.x)
    // - m * (v2.x * v1.x + v2.y * v1.y) == v2.x * v1.y - v2.y * v1.x
    // m = (v2.y * v1.x - v2.x * v1.y) / (v2.x * v1.x + v2.y * v1.y)
    // m = v1.cross(v2) / v1.dot(v2)
    List<ui.Offset> sweep = fPart!.fSweep;
    List<ui.Offset> tweep = rh.fPart!.fSweep;
    double s0dt0 = _dotProduct(sweep[0].dx, sweep[0].dy, tweep[0].dx, tweep[0].dy);
    if (s0dt0 == 0) {
      return true;
    }
    // Compute sweep distance to longest curve point distance ratio.
    double m = s0xt0 / s0dt0;
    ui.Offset sPoint = sweep[0];
    ui.Offset tPoint = tweep[0];
    double sDist = math.sqrt(_lengthSquared(sPoint.dx, sPoint.dy)) * m;
    double tDist = math.sqrt(_lengthSquared(tPoint.dx, tPoint.dy)) * m;
    bool useS = sDist.abs() < tDist.abs();
    double mFactor = (useS ? distEndRatio(sDist) : rh.distEndRatio(tDist)).abs();
    fTangentsAmbiguous = mFactor >= 50 && mFactor < 200;
    return mFactor < 50; // Empirically found limit
  }

  double distEndRatio(double dist) {
    double longest = 0;
    OpSegment seg = segment;
    int ptCount = pathOpsVerbToPoints(seg.verb);
    Float32List points = seg.points;
    for (int idx1 = 0; idx1 <= ptCount - 1; ++idx1) {
      for (int idx2 = idx1 + 1; idx2 <= ptCount; ++idx2) {
        if (idx1 == idx2) {
            continue;
        }
        double dx = points[idx2 * 2] - points[idx1 * 2];
        double dy = points[idx2 * 2 + 1] - points[idx1 * 2];
        double lenSq = _lengthSquared(dx, dy);
        longest = math.max(longest, lenSq);
      }
    }
    return math.sqrt(longest) / dist;
  }

  // To sort the angles, all curves are translated to have the same starting
  // point. If the curve's control point in its original position is on one
  // side of a compared line, and translated is on the opposite side, returns
  // true so previously computed order can be reversed.
  bool alignmentSameSide(OpAngle test, int order) {
    if (order < 0) {
      return false;
    }
    // Only do this for lines.
    if (fPart!.isCurve()) {
      return false;
    }
    if (test.fPart!.isCurve()) {
      return false;
    }
    ui.Offset xOrigin = test.fPart!.fCurve[0];
    ui.Offset oOrigin = test.fOriginalCurvePart![0];
    if (xOrigin == oOrigin) {
      // If point return.
      return false;
    }
    int iMax = pathOpsVerbToPoints(segment.verb);
    ui.Offset xLine = test.fPart!.fCurve[1] - xOrigin;
    ui.Offset oLine = test.fOriginalCurvePart![1] - oOrigin;
    for (int index = 1; index <= iMax; ++index) {
      ui.Offset testPt = fPart!.fCurve[index];
      double xCross = crossCheck(oLine, testPt - xOrigin);
      double oCross = crossCheck(xLine, testPt - oOrigin);
      if (oCross * xCross < 0) {
        return true;
      }
    }
    return false;
  }

  int linesOnOriginalSide(OpAngle test) {
    // Only works with lines.
    assert(!fPart!.isCurve());
    assert(!test.fPart!.isCurve());
    ui.Offset origin = fOriginalCurvePart![0];
    ui.Offset line = fOriginalCurvePart![1] - origin;
    List<double> dots = [0.0, 0.0];
    List<double> crosses = [0.0, 0.0];
    TCurve testCurve = test.fOriginalCurvePart!;
    for (int index = 0; index < 2; ++index) {
      ui.Offset testLine = testCurve[index] - origin;
      double xy1 = line.dx * testLine.dy;
      double xy2 = line.dy * testLine.dx;
      dots[index] = line.dx * testLine.dx + line.dy * testLine.dy;
      crosses[index] = almostBequalUlps(xy1, xy2) ? 0 : xy1 - xy2;
    }
    if (crosses[0] * crosses[1] < 0) {
      return -1;
    }
    if (crosses[0] != 0) {
      return crosses[0] < 0 ? 1 : 0;
    }
    if (crosses[1] != 0) {
      return crosses[1] < 0 ? 1 : 0;
    }
    if ((dots[0] == 0 && dots[1] < 0) || (dots[0] < 0 && dots[1] == 0)) {
      return 2;  // 180 degrees apart
    }
    fUnorderable = true;
    return -1;
  }

  bool endsIntersect(OpAngle rh) {
    int lVerb = segment.verb;
    int rVerb = rh.segment.verb;
    int lPts = pathOpsVerbToPoints(lVerb);
    int rPts = pathOpsVerbToPoints(rVerb);
    TCurve curve = fPart!.fCurve;
    TCurve rhCurve = rh.fPart!.fCurve;
    List<DLine> rays = [DLine.offsets(curve[0], rhCurve[rPts]),
            DLine.offsets(curve[0], curve[lPts])];
    if (end!.contains(rh.end!)) {
      return checkParallel(rh);
    }
    List<double> smallTs = [-1.0, -1.0];
    List<bool> limited = [false, false];
    for (int index = 0; index < 2; ++index) {
      int cVerb = index != 0 ? rVerb : lVerb;
      // If the curve is a line, then the line and the ray intersect only
      // at their crossing.
      if (cVerb == SPathVerb.kLine) {
        continue;
      }
      OpSegment seg = index != 0 ? rh.segment : segment;
      Intersections i = Intersections();

      intersectRay(seg.points, cVerb, seg.weight, rays[index], i);

      double tStart = index != 0 ? rh.start!.ptT.fT : start!.ptT.fT;
      double tEnd = index != 0 ? rh.fComputedEnd!.ptT.fT : fComputedEnd!.ptT.fT;
      bool testAscends = tStart < (index != 0 ? rh.fComputedEnd!.ptT.fT
          : fComputedEnd!.ptT.fT);
      double t = testAscends ? 0 : 1;
      for (int idx2 = 0; idx2 < i.fUsed; ++idx2) {
        double testT = i.fT0[idx2];
        if (!approximatelyBetweenOrderable(tStart, testT, tEnd)) {
          continue;
        }
        if (approximatelyEqualOrderable(tStart, testT)) {
          continue;
        }
        smallTs[index] = t = testAscends ? math.max(t, testT) : math.min(t, testT);
        limited[index] = approximatelyEqualOrderable(t, tEnd);
      }
    }
    bool sRayLonger = false;
    ui.Offset sCept = ui.Offset.zero;
    double sCeptT = -1;
    int sIndex = -1;
    bool useIntersect = false;
    for (int index = 0; index < 2; ++index) {
      if (smallTs[index] < 0) {
          continue;
      }
      OpSegment seg = index != 0 ? rh.segment : segment;
      ui.Offset dPt = seg.ptAtT(smallTs[index]);
      DLine ray = rays[index];
      ui.Offset cept = dPt - ui.Offset(ray.x0, ray.y0);
      // If this point is on the curve, it should have been detected earlier by
      // ordinary curve intersection. This may be hard to determine in general,
      // but for lines, the point could be close to or equal to its end,
      // but shouldn't be near the start.
      double dx = ray.x1 - ray.x0;
      double dy = ray.y1 - ray.y0;
      double ceptLengthSq = _lengthSquared(cept.dx, cept.dy);
      double rayLengthSq = _lengthSquared(dx, dy);
      if ((index != 0 ? lPts : rPts) == 1) {
        if (ceptLengthSq * 2 < rayLengthSq) {
          continue;
        }
      }
      ui.Offset end = ui.Offset(dx, dy);
      if (cept.dx * dx < 0 || cept.dy * dy < 0) {
        continue;
      }
      double rayDist = math.sqrt(ceptLengthSq);
      double endDist = math.sqrt(rayLengthSq);
      bool rayLonger = rayDist > endDist;
      if (limited[0] && limited[1] && rayLonger) {
        useIntersect = true;
        sRayLonger = rayLonger;
        sCept = cept;
        sCeptT = smallTs[index];
        sIndex = index;
        break;
      }
      double delta = (rayDist - endDist).abs();
      TCurve curve = index != 0 ? rh.fPart!.fCurve : fPart!.fCurve;
      double minX, minY, maxX, maxY;
      minX = maxX = curve[0].dx;
      minY = maxY = curve[0].dy;
      int ptCount = index != 0 ? rPts : lPts;
      for (int idx2 = 1; idx2 <= ptCount; ++idx2) {
        minX = math.min(minX, curve[idx2].dx);
        minY = math.min(minY, curve[idx2].dy);
        maxX = math.max(maxX, curve[idx2].dx);
        maxY = math.max(maxY, curve[idx2].dy);
      }
      double maxWidth = math.max(maxX - minX, maxY - minY);
      delta = delta / maxWidth;
      // This fixes skbug.com/8380
      // Larger changes (like changing the constant in the next block) cause
      // other tests to fail as documented in the bug.
      // This could probably become a more general test: e.g., if translating
      // the curve causes the cross product of any control point or end point
      // to change sign with regard to the opposite curve's hull, treat the
      // curves as parallel.
      // Moreso, this points to the general fragility of this approach of
      // assigning winding by sorting the angles of curves sharing a common
      // point, as mentioned in the bug.
      if (delta < 4e-3 && delta > 1e-3 && !useIntersect && fPart!.isCurve()
              && rh.fPart!.isCurve() && fOriginalCurvePart![0] != fPart!.fCurve[0]) {
        // Check if original curve is on one side of hull; translated is on the
        // other.
        ui.Offset origin = rh.fOriginalCurvePart![0];
        int count = pathOpsVerbToPoints(rh.segment.verb);
        ui.Offset line = rh.fOriginalCurvePart![count] - origin;
        int originalSide = rh._lineOnOneSide(origin, line, this, true);
        if (originalSide >= 0) {
          int translatedSide = rh._lineOnOneSide(origin, line, this, false);
          if (originalSide != translatedSide) {
            continue;
          }
        }
      }
      if (delta > 1e-3 && (useIntersect ^= true)) {
        sRayLonger = rayLonger;
        sCept = cept;
        sCeptT = smallTs[index];
        sIndex = index;
      }
    }
    if (useIntersect) {
      TCurve curve = sIndex != 0 ? rh.fPart!.fCurve : fPart!.fCurve;
      OpSegment seg = sIndex != 0 ? rh.segment : segment;
      double tStart = sIndex != 0 ? rh.start!.ptT.fT : start!.ptT.fT;
      ui.Offset mid = seg.ptAtT(tStart + (sCeptT - tStart) / 2) - curve[0];
      double septDir = crossCheck(mid, sCept);
      if (septDir == 0) {
        return checkParallel(rh);
      }
      return sRayLonger ^ (sIndex == 0) ^ (septDir < 0);
    } else {
      return checkParallel(rh);
    }
  }

  bool checkParallel(OpAngle rh) {
    List<ui.Offset> sweep = fPart!.isOrdered() ?
      fPart!.fSweep : [fPart!.fCurve[1] - fPart!.fCurve[0]];
    List<ui.Offset> tweep = rh.fPart!.isOrdered() ?
      rh.fPart!.fSweep : [rh.fPart!.fCurve[1] - rh.fPart!.fCurve[0]];
    double s0xt0 = crossCheck(sweep[0] , tweep[0]);
    if (tangentsDiverge(rh, s0xt0)) {
      return s0xt0 < 0;
    }
    // Compute the perpendicular to the endpoints and see where it intersects
    // the opposite curve if the intersections within the t range, do a cross
    // check on those.
    bool inside = false;
    bool? res;
    if (!end!.contains(rh.end!)) {
      res = endToSide(rh);
      if (res == null) {
        return false;
      } else {
        inside = res;
      }
      res = rh.endToSide(this);
      if (res == null) {
        return !inside;
      }
    }

    res = midToSide(rh);
    if (res != null) {
      inside = res;
    }
    if (res != null) {
      return inside;
    }
    res = rh.midToSide(this);
    if (res != null) {
      inside = res;
    }
    if (res != null) {
      return !inside;
    }
    // compute the cross check from the mid T values (last resort)
    ui.Offset m0 = segment.ptAtT(midT()) - fPart!.fCurve[0];
    ui.Offset m1 = rh.segment.ptAtT(rh.midT()) - rh.fPart!.fCurve[0];
    double m0xm1 = crossCheck(m0, m1);
    if (m0xm1 == 0) {
      fUnorderable = true;
      rh.fUnorderable = true;
      return true;
    }
    return m0xm1 < 0;
  }

  bool? endToSide(OpAngle rh) {
    OpSegment seg = segment;
    int verb = seg.verb;
    ui.Offset slopeAtEnd = segment.dxdyAtT(end!.ptT.fT);
    ui.Offset rayStartPoint = end!.ptT.fPt;
    DLine rayEnd = DLine(rayStartPoint.dx, rayStartPoint.dy,
        rayStartPoint.dx + slopeAtEnd.dy, rayStartPoint.dy - slopeAtEnd.dx);

    Intersections iEnd = Intersections();
    OpSegment oppSegment = rh.segment;
    int oppVerb = oppSegment.verb;
    intersectRay(oppSegment.points, oppSegment.verb,
      oppSegment.weight, rayEnd, iEnd);
    _ClosestIntersection res = iEnd.closestTo(rh.start!.ptT.fT, rh.end!.ptT.fT,
        rayEnd.x0, rayEnd.y0);
    if (!res.foundClosest) {
      return null;
    }
    double endDist = res.distanceSquared;
    if (0 == endDist) {
      return null;
    }
    ui.Offset startPoint = start!.ptT.fPt;
    // OPTIMIZATION: multiple times in the code we find the max scalar
    double minX, minY, maxX, maxY;
    TCurve curve = rh.fPart!.fCurve;
    minX = maxX = curve[0].dx;
    minY = maxY = curve[0].dy;
    int oppPts = pathOpsVerbToPoints(oppVerb);
    for (int idx2 = 1; idx2 <= oppPts; ++idx2) {
        minX = math.min(minX, curve[idx2].dx);
        minY = math.min(minY, curve[idx2].dy);
        maxX = math.max(maxX, curve[idx2].dx);
        maxY = math.max(maxY, curve[idx2].dy);
    }
    double maxWidth = math.max(maxX - minX, maxY - minY);
    endDist /= maxWidth;
    if (!(endDist >= 5e-12)) {  // empirically found
      return null; // ! above catches NaN
    }
    ui.Offset endPt = ui.Offset(rayEnd.x0, rayEnd.y0);
    ui.Offset oppPt = ui.Offset(iEnd.ptX[res.intersectionPointIndex],
        iEnd.ptY[res.intersectionPointIndex]);
    ui.Offset vLeft = endPt - startPoint;
    ui.Offset  vRight = oppPt - startPoint;
    double dir = crossNoNormalCheck(vLeft, vRight);
    if (0 == dir) {
      return null;
    }
    // sin(theta) < 0 => theta > pi.
    return dir < 0;
  }

  bool? midToSide(OpAngle rh) {
    OpSegment seg = segment;
    int verb = seg.verb;
    ui.Offset startPt = start!.ptT.fPt;
    ui.Offset endPt = end!.ptT.fPt;
    ui.Offset dStartPt = startPt;
    double midX = (startPt.dx + endPt.dx) / 2;
    double midY = (startPt.dy + endPt.dy) / 2;
    DLine rayMid = DLine(midX, midY,
        midX + (endPt.dy - startPt.dy),
        midY + (endPt.dx - startPt.dx));
    Intersections iMid = Intersections();
    intersectRay(seg.points, verb, seg.weight, rayMid, iMid);
    int iOutside = iMid.mostOutside(start!.ptT.fT, end!.ptT.fT, dStartPt);
    if (iOutside < 0) {
      return null;
    }
    OpSegment oppSegment = rh.segment;
    int oppVerb = oppSegment.verb;
    Intersections oppMid = Intersections();
    intersectRay(oppSegment.points, oppVerb, oppSegment.weight, rayMid, oppMid);
    int oppOutside = oppMid.mostOutside(rh.start!.ptT.fT, rh.end!.ptT.fT, dStartPt);
    if (oppOutside < 0) {
      return null;
    }
    ui.Offset iSide = ui.Offset(iMid.ptX[iOutside], iMid.ptY[iOutside]) - dStartPt;
    ui.Offset oppSide = ui.Offset(oppMid.ptX[oppOutside], oppMid.ptY[oppOutside]) - dStartPt;
    double dir = crossCheck(iSide, oppSide);
    if (0 == dir) {
      return null;
    }
    return dir < 0;
 }

  // Checks cross product, allowing tinier numbers.
  double crossNoNormalCheck(ui.Offset v1, ui.Offset v2) {
    double xy = v1.dx * v2.dy;
    double yx = v1.dy * v2.dx;
    return almostEqualUlpsNoNormalCheck(xy, yx) ? 0 : xy - yx;
  }

  void debugValidate() {
    OpAngle first = this;
    OpAngle? next = this;
    int wind = 0;
    int opp = 0;
    int lastXor = -1;
    int lastOppXor = -1;
    do {
      if (next!.unorderable) {
        return;
      }
      OpSpan minSpan = next.start!.starter(next.end!);
      if (minSpan.windValue() == kMinS32) {
        return;
      }
      bool op = next!.segment.operand;
      bool isXor = next.segment.isXor;
      bool oppXor = next.segment.oppXor;
      bool useXor = op ? oppXor : isXor;
      assert(lastXor == -1 || lastXor == (useXor ? 1 : 0));
      lastXor = useXor ? 1 : 0;
      wind += next.debugSign() * (op ? minSpan.oppValue() : minSpan.windValue());
      if (useXor) {
        wind &= 1;
      }
      useXor = op ? isXor : oppXor;
      assert(lastOppXor == -1 || lastOppXor == (useXor ? 1 : 0));
      lastOppXor = useXor ? 1 : 0;
      opp += next.debugSign() * (op ? minSpan.windValue() : minSpan.oppValue());
      if (useXor) {
        opp &= 1;
      }
      next = next.next;
    } while (next != null && next != first);
  }

  int debugSign() {
    assert(start!.ptT.fT != end!.ptT.fT);
    return start!.ptT.fT < end!.ptT.fT ? -1 : 1;
  }

  void debugValidateNext() {
    // TODO
  }
}
