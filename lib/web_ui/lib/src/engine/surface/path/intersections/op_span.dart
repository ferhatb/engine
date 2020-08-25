// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Base class for segment span.
class OpSpanBase {
  OpSpanBase(this.fSegment, this._fPrev);

  void init(double t, ui.Offset pt) {
    fPtT = OpPtT(this, pt, t);
    fCoinEnd = this;
  }

  /// List of points and t values associated with the start of this span.
  OpPtT? fPtT;
  /// List of coincident spans that end here (may point to itself).
  OpSpanBase? fCoinEnd;
  final OpSegment fSegment;
  /// Points to next angle from span start to end.
  ///
  /// HandleCoincidences calculates angles for all contours/segments and sorts
  /// by angles.
  /// Segment calcAngles, iterates through each span and sets the fromAngle.
  OpAngle? _fromAngle;
  /// Previous intersection point.
  OpSpan? _fPrev;
  /// Number of times intersections have been added to this span.
  int _fSpanAdds = 0;
  bool _fAligned = true;
  bool fChased = false;

  /// Returns first intersection point at start of this span.
  OpPtT get ptT => fPtT!;

  OpSpan get upCast => this as OpSpan;

  OpSegment get segment => fSegment;

  void bumpSpanAdds() {
    ++_fSpanAdds;
  }

  int get spanAddsCount => _fSpanAdds;

  OpSpan? get prev => _fPrev;

  bool isFinal() => fPtT == 1;

  bool get deleted => fPtT!.deleted;

  void unaligned() {
    _fAligned = false;
  }

  double get t {
    return fPtT!.fT;
  }

  /// Returns t direction to get closer to [end] span.
  int step(OpSpanBase end) {
    return t < end.t ? 1 : -1;
  }

  OpSpan? upCastable() {
    return isFinal() ? null : upCast;
  }

  OpSpan starter(OpSpanBase end) {
    OpSpanBase result = t < end.t ? this : end;
    return result.upCast;
  }

  bool get simple {
    fPtT!.debugValidate();
    return fPtT!.next?.next == fPtT;
  }

  set fromAngle(OpAngle? angle) {
    _fromAngle = angle;
  }

  OpAngle? get fromAngle => _fromAngle;

  bool addOpp(OpSpanBase opp) {
    OpPtT? oppPrev = ptT.oppPrev(opp.ptT);
    if (oppPrev == null) {
      return true;
    }
    if (!mergeMatches(opp)) {
      return false;
    }
    ptT.addOpp(opp.ptT, oppPrev);
    checkForCollapsedCoincidence();
    return true;
  }

  // Look to see if pt-t linked list contains same segment more than once
  // if so, and if each pt-t is directly pointed to by spans in that segment,
  // merge them keep the points, but remove spans so that the segment doesn't
  // have 2 or more spans pointing to the same pt-t loop at different
  // loop elements.
  bool mergeMatches(OpSpanBase opp) {
    OpPtT? test = fPtT;
    OpPtT? testNext;
    OpPtT stop = test!;
    int safetyHatch = 1000000;
    do {
      if (0 != --safetyHatch) {
        return false;
      }
      testNext = test!.next;
      if (test.deleted) {
        continue;
      }
      OpSpanBase testBase = test.span;
      assert(testBase.ptT == test);
      OpSegment segment = test.segment;
      if (segment.done()) {
        continue;
      }
      OpPtT inner = opp.ptT;
      OpPtT innerStop = inner;
      do {
          if (inner.segment != segment || inner.deleted) {
            // Not same segment or deleted, skip this point.
            continue;
          }
          OpSpanBase innerBase = inner.span;
          assert(innerBase.ptT == inner);
          // When the intersection is first detected, the span base is marked
          // if there are more than one point in the intersection.
          if (!zeroOrOne(inner.fT)) {
            // Release any inner points not at start or end t.
            innerBase.upCast.release(test);
          } else {
            assert(inner.fT != test.fT);
            if (!zeroOrOne(test.fT)) {
              testBase.upCast.release(inner);
            } else {
              /// Both inner and test t is 0 or 1.
              segment.markAllDone();  // mark segment as collapsed
              test.setDeleted();
              inner.setDeleted();
            }
          }
          if (assertionsEnabled) {
            // Assert if another undeleted entry points to segment
            OpPtT? debugInner = inner;
            while ((debugInner = debugInner!.next) != innerStop) {
              if (debugInner!.segment != segment) {
                continue;
              }
              if (debugInner.deleted) {
                continue;
              }
              assert(false);
            }
          }
          break;
      } while ((inner = inner.next!) != innerStop);
    } while ((test = testNext) != stop);
    checkForCollapsedCoincidence();
    return true;
  }

  // This pair of spans share a common t value or point; merge them and
  // eliminate duplicates this does not compute the best t or pt value; this
  // merely moves all data into a single list
  void merge(OpSpan span) {
    OpPtT spanPtT = span.ptT;
    assert(t != spanPtT.fT);
    assert(!zeroOrOne(spanPtT.fT));
    span.release(ptT);
    if (contains(span)) {
      assert(false, 'merge failure, should have been found earlier');
      return;  // merge is already in the ptT loop
    }
    OpPtT remainder = spanPtT.next!;
    ptT.insert(spanPtT);
    while (remainder != spanPtT) {
      OpPtT? next = remainder.next;
      OpPtT? compare = spanPtT.next;
      bool tryNextRemainder = false;
      while (compare != spanPtT) {
        OpPtT? nextC = compare!.next;
        if (nextC!.span == remainder.span && nextC.fT == remainder.fT) {
          tryNextRemainder = true;
          break;
        }
        compare = nextC;
      }
      if (!tryNextRemainder) {
        spanPtT.insert(remainder);
      }
      remainder = next!;
    }
    _fSpanAdds += span._fSpanAdds;
  }

  void checkForCollapsedCoincidence() {
    OpCoincidence coins = globalState().coincidence!;
    if (coins.isEmpty) {
      return;
    }
    // the insert above may have put both ends of a coincident run in the same
    // span for each coincident ptT in loop; see if its opposite in is also in
    // the loop this implementation is the motivation for marking that a ptT
    // is referenced by a coincident span.
    OpPtT head = ptT;
    OpPtT test = head;
    do {
      if (!test.coincident) {
        continue;
      }
      coins.markCollapsed(test);
    } while ((test = test.next!) != head);
    coins.releaseDeleted();
  }

  /// Checks if any pt-t on this span is on [segment].
  OpPtT? containsPointsOnSegment(OpSegment segment) {
    OpPtT start = fPtT!;
    OpPtT walk = start;
    while ((walk = walk.next!) != start) {
      if (walk.deleted) {
        continue;
      }
      if (walk.segment == segment && walk.span.ptT == walk) {
        return walk;
      }
    }
    return null;
  }

  bool contains(OpSpanBase span) {
    OpPtT? start = fPtT;
    OpPtT? check = span.fPtT;
    assert(start != check);
    OpPtT? walk = start;
    while ((walk = walk!.next) != start) {
      if (walk == check) {
        return true;
      }
    }
    return false;
  }

  OpPtT? containsSegment(OpSegment segment) {
    OpPtT? start = fPtT;
    OpPtT? walk = start;
    while ((walk = walk!.next) != start) {
      if (walk!.deleted) {
        continue;
      }
      if (walk.segment == segment && walk.span.ptT == walk) {
        return walk;
      }
    }
    return null;
  }

  void insertCoinEnd(OpSpanBase coin) {
    if (containsCoinEnd(coin)) {
      assert(coin.containsCoinEnd(this));
      return;
    }
    debugValidate();
    assert(this != coin);
    OpSpanBase? coinNext = coin.fCoinEnd;
    coin.fCoinEnd = fCoinEnd;
    fCoinEnd = coinNext;
    debugValidate();
  }

  bool containsCoinEnd(OpSpanBase coin) {
    assert(this != coin);
    OpSpanBase? next = this;
    while ((next = next!.fCoinEnd) != this) {
      if (next == coin) {
        return true;
      }
    }
    return false;
  }

  bool containsCoinEndSegment(OpSegment seg) {
    assert(this.segment != seg);
    OpSpanBase? next = this;
    while ((next = next!.fCoinEnd) != this) {
      if (next!.segment == seg) {
        return true;
      }
    }
    return false;
  }

  static const int kCollapsedError = -1;
  static const int kNotCollapsed = 0;
  static const int kCollapsed = 1;

  int collapsed(double s, double e) {
    OpPtT? start = fPtT;
    OpPtT? startNext;
    OpPtT? walk = start;
    double min = walk!.fT;
    double max = min;
    OpSegment segment = this.segment;
    int safetyNet = 100000;
    while ((walk = walk!.next) != start) {
      if (0 == --safetyNet) {
        return kCollapsedError;
      }
      if (walk == startNext) {
        return kCollapsedError;
      }
      if (walk!.segment != segment) {
        continue;
      }
      min = math.min(min, walk.fT);
      max = math.max(max, walk.fT);
      if (SPath.between(min, s, max) && SPath.between(min, e, max)) {
        return kCollapsed;
      }
      startNext = start!.next;
    }
    return kNotCollapsed;
  }

  OpGlobalState globalState() => fSegment.parent.fState;

  void debugValidate() {
    OpPtT? ptT = fPtT;
    assert(ptT!.span == this);
    do {
      ptT!.debugValidate();
      ptT = ptT.next;
    } while (ptT != fPtT);
    assert(debugCoinEndLoopCheck());
    if (!isFinal()) {
      assert(upCast.debugCoinLoopCheck());
    }
    fromAngle?.debugValidate();
    if (!isFinal() && upCast.toAngle != null) {
      upCast.toAngle!.debugValidate();
    }
  }

  bool debugCoinEndLoopCheck() {
    int loop = 0;
    OpSpanBase? next = this;
    OpSpanBase? nextCoin;
    do {
      nextCoin = next!.fCoinEnd;
      assert(nextCoin == this || nextCoin!.fCoinEnd != nextCoin);
      // Once we have more than 2 spans, start checking for loops.
      for (int check = 1; check < loop - 1; ++check) {
        OpSpanBase? checkCoin = fCoinEnd;
        OpSpanBase? innerCoin = checkCoin;
        for (int inner = check + 1; inner < loop; ++inner) {
          innerCoin = innerCoin!.fCoinEnd;
          if (checkCoin == innerCoin) {
            print('Bad coincident end loop');
            return false;
          }
        }
      }
      ++loop;
    } while ((next = nextCoin) != null && next != this);
    return true;
  }
}

class OpSpan extends OpSpanBase {
  OpSpan(OpSegment fSegment, OpSpan? prev) : super(fSegment, prev) {
    fSegment.bumpCount();
  }

  void init(double t, ui.Offset pT) {
    super.init(t, pT);
    fCoincident = this;
  }

  /// Linked list of spans coincident with this one.
  OpSpan? fCoincident;
  /// Next angle from span start to end.
  OpAngle? _toAngle;
  /// Next intersection point
  OpSpanBase? _fNext;
  int fWindSum = kMinS32;
  int fOppSum = kMinS32;
  int fWindValue = 1;
  int fOppValue = 0;
  int fTopTTry = 0;
  bool fChased = false;
  bool fDone = false;
  bool fAlreadyAdded = false;

  /// Returns following span.
  OpSpanBase? get next => _fNext;

  /// If span has been processed.
  bool get done => fDone;
  /// Marks span as processed.
  set done(bool value) {
    fDone = value;
  }

  void setWindValue(int windValue) {
    assert(!isFinal());
    assert(windValue >= 0);
    assert(fWindSum == kMinS32);
    assert(windValue != 0 || !fDone);
    fWindValue = windValue;
  }

  int windValue() {
    assert(!isFinal());
    return fWindValue;
  }

  int oppValue() {
    assert(!isFinal());
    return fOppValue;
  }

  int get windSum {
    assert(!isFinal());
    return fWindSum;
  }
  set windSum(int value) {
    fWindSum = value;
  }

  int get oppSum {
    assert(!isFinal());
    return fOppSum;
  }
  set oppSum(int value) {
    fOppSum = value;
  }

  void setOppValue(int oppValue) {
    assert(!isFinal());
    assert(fOppSum == kMinS32);
    assert(oppValue != 0 || !fDone);
    fOppValue = oppValue;
  }

  // Points to next angle from span start to end.
  set toAngle(OpAngle? angle) {
    assert(!isFinal());
    _toAngle = angle;
  }

  OpAngle? get toAngle => _toAngle;

  /// Release this span given that [kept] is preserved.
  void release(OpPtT kept) {
    assert(kept.span != this);
    assert(!isFinal());
    OpSpan prev = this.prev!;
    OpSpanBase next = this.next!;
    prev._fNext = next;
    next._fPrev = prev;
    fSegment.release(this);
    OpCoincidence? coincidence = globalState().coincidence;
    coincidence?.fixUp(ptT, kept);
    ptT.setDeleted();
    OpPtT stopPtT = ptT;
    OpPtT testPtT = stopPtT;
    OpSpanBase keptSpan = kept.span;
    do {
      if (this == testPtT.span) {
        testPtT.setSpan(keptSpan);
      }
    } while ((testPtT = testPtT.next!) != stopPtT);
  }

  bool get isCanceled {
    assert(!isFinal());
    return fWindValue == 0 && fOppValue == 0;
  }

  void insertCoincidence(OpSpan coin) {
    if (containsCoincidence(coin)) {
      assert(coin.containsCoincidence(this));
      return;
    }
    debugValidate();
    assert(this != coin);
    OpSpan? coinNext = coin.fCoincident;
    coin.fCoincident = this.fCoincident;
    this.fCoincident = coinNext;
    debugValidate();
  }

  // Please keep this in sync with debugInsertCoincidence()
  bool insertCoincidenceSegment(OpSegment seg, bool flipped, bool ordered) {
    if (containsCoincidenceSegment(seg)) {
      return true;
    }
    OpPtT? next = fPtT;
    while ((next = next!.next) != fPtT) {
      if (next!.segment == seg) {
          OpSpan? span;
          OpSpanBase base = next.span;
          if (!ordered) {
              OpPtT? spanEndPtT = next.containsSegment(seg);
              if (null == spanEndPtT) {
                return false;
              }
              OpSpanBase spanEnd = spanEndPtT.span;
              OpPtT start = base.ptT.starter(spanEnd.ptT);
              if (null == start.span.upCastable()) {
                return false;
              }
              span = start.span.upCast;
          } else if (flipped) {
            span = base.prev;
            if (null == span) {
              return false;
            }
          } else {
            if (null == base.upCastable()) {
              return false;
            }
            span = base.upCast;
          }
          insertCoincidence(span);
          return true;
      }
    }
    assert(false, 'if we get here, the span is missing its opposite segment');
    return true;
}

  bool containsCoincidence(OpSpan coin) {
    assert(this != coin);
    OpSpan? next = this;
    while ((next = next!.fCoincident) != this) {
      if (next == coin) {
        return true;
      }
    }
    return false;
  }

  bool containsCoincidenceSegment(OpSegment seg) {
    assert(segment != seg);
    OpSpan? next = fCoincident;
    do {
      if (next!.segment == seg) {
        return true;
      }
    } while ((next = next.fCoincident) != this);
    return false;
  }

  bool debugCoinLoopCheck() {
    int loop = 0;
    OpSpan? next = this;
    OpSpan? nextCoin;
    do {
      nextCoin = next!.fCoincident;
      assert(nextCoin == this || nextCoin!.fCoincident != nextCoin);
      for (int check = 1; check < loop - 1; ++check) {
        OpSpan? checkCoin = fCoincident;
        OpSpan? innerCoin = checkCoin;
        for (int inner = check + 1; inner < loop; ++inner) {
          innerCoin = innerCoin!.fCoincident;
          if (checkCoin == innerCoin) {
            print('Bad coincident loop');
            return false;
          }
        }
      }
      ++loop;
    } while ((next = nextCoin) != null && next != this);
    return true;
  }

  double _dxdy(ui.Offset offset, int opRayDir) => (opRayDir & 1) != 0 ? offset.dy : offset.dx;
  double _dydx(ui.Offset offset, int opRayDir) => (opRayDir & 1) == 0 ? offset.dy : offset.dx;

  bool sortableTop(List<OpContour> contourList) {
    int dirOffset = fTopTTry & 1;
    double t = generateT(fTopTTry++);
    OpRayHit hitBase = OpRayHit.fromT(this, t);
    List<OpRayHit> hitList = [hitBase];
    int opRayDir = hitBase.direction;
    if (hitBase.fSlope.dx == 0 && hitBase.fSlope.dy == 0) {
        return false;
    }
    opRayDir += dirOffset;
    if (hitBase.fSpan.segment.verb > SPathVerb.kLine
        && 0 == _dydx(hitBase.fSlope, opRayDir)) {
      return false;
    }
    for (OpContour contour in contourList) {
      if (contour.count != 0) {
        contour.rayCheck(hitBase, opRayDir, hitList);
      }
    }

    // Sort hits.
    List<OpRayHit> sorted = [];
    sorted.addAll(hitList);
    int count = sorted.length;
    int xyIndex = opRayDir & 1 != 0 ? 1 : 0;
    sorted.sort(xyIndex == 1
            ? lessThan(opRayDir) != 0 ? _hitCompareY : _reverseHitCompareY
            : lessThan(opRayDir) != 0 ? _hitCompareX : _reverseHitCompareX);
    // Verify windings.
    ui.Offset? last;
    int wind = 0;
    int oppWind = 0;
    for (int index = 0; index < count; ++index) {
      OpRayHit hit = sorted[index];
      if (!hit.fValid) {
        return false;
      }
      bool ccw = _isCounterClockwise(hit.fSlope, opRayDir);
      OpSpan? span = hit.fSpan;
      if (span == null) {
        return false;
      }
      OpSegment hitSegment = span.segment;
      if (span.windValue == 0 && span.oppValue == 0) {
        continue;
      }
      if (last != null && approximatelyEqualPoints(last.dx, last.dy, hit.fPt.dx, hit.fPt.dy)) {
        return false;
      }
      if (index < count - 1) {
        ui.Offset next = sorted[index + 1].fPt;
        if (approximatelyEqualPoints(next.dx, next.dy, hit.fPt.dx, hit.fPt.dy)) {
          return false;
        }
      }
      bool operand = hitSegment.operand;
      if (operand != 0) {
        int temp = wind;
        wind = oppWind;
        oppWind = temp;
      }
      int lastWind = wind;
      int lastOpp = oppWind;
      int windValue = ccw ? -span.windValue() : span.windValue();
      int oppValue = ccw ? -span.oppValue() : span.oppValue();
      wind += windValue;
      oppWind += oppValue;
      bool sumSet = false;
      int spanSum = span.windSum;
      int windSum = OpSegment.useInnerWinding(lastWind, wind) ? wind : lastWind;
      if (spanSum == kMinS32) {
        span.windSum = windSum;
        sumSet = true;
      }
      int oSpanSum = span.oppSum;
      int oppSum = OpSegment.useInnerWinding(lastOpp, oppWind) ? oppWind : lastOpp;
      if (oSpanSum == kMinS32) {
        span.oppSum = oppSum;
      }
      if (sumSet) {
        OpGlobalState state = globalState();
        if (state.phase == OpPhase.kFixWinding) {
          hitSegment.parent.ccw = ccw ? 1 : 0;
        } else {
          hitSegment.markAndChaseWindingOpp(state, span, span!.next!, windSum, oppSum);
          hitSegment.markAndChaseWindingOpp(state, span.next, span, windSum, oppSum);
        }
      }
      if (operand != 0) {
        int temp = wind;
        wind = oppWind;
        oppWind = temp;
      }
      last = hit.fPt;
      globalState().bumpNested();
    }
    return true;
  }
}

/// Using seed value [tTry] (number of tries) generates a t value to use for
/// sorting.
///
/// T values are generated as pow(0.5, n) * n. Where n = seed/2 and we
/// alternate direction based on seed mod 2.
double generateT(int seed) {
  double t = 0.5;
  int tBase = seed >> 1;
  int tBits = 0;
  while ((seed >>= 1) != 0) {
    t /= 2;
    ++tBits;
  }
  if (tBits != 0) {
    int tIndex = (tBase - 1) & ((1 << tBits) - 1);
    t += t * 2 * tIndex;
  }
  return t;
}

class OpRayDir {
  static const int kLeft = 1;
  static const int kTop = 2;
  static const int kRight = 3;
  static const int kBottom = 4;
}

class OpRayHit {
  OpRayHit(this.fPt, this.fSlope, this.fSpan, this.fT, this.fValid, this.direction);

  factory OpRayHit.fromT(OpSpan span, double t) {
    double fT = span.ptT.fT * (1 - t) + span.next!.ptT.fT * t;
    OpSegment segment = span.segment;
    ui.Offset fSlope = segment.dxdyAtT(fT);
    ui.Offset fPt = segment.ptAtT(fT);
    int direction = fSlope.dx.abs() < fSlope.dy.abs() ? OpRayDir.kLeft : OpRayDir.kTop;
    return OpRayHit(fPt, fSlope, span, fT, true, direction);
  }
  final OpSpan fSpan;
  int direction;

  OpRayHit? fNext;
  ui.Offset fPt;
  double fT;
  ui.Offset fSlope;
  bool fValid;
}


int _hitCompareX(OpRayHit a, OpRayHit b) {
  double v1 = a.fPt.dx;
  double v2 = b.fPt.dx;
  return (v1 < v2) ? -1 : (v1 > v2) ? 1 : 0;
}

int _hitCompareY(OpRayHit a, OpRayHit b) {
  double v1 = a.fPt.dy;
  double v2 = b.fPt.dy;
  return (v1 < v2) ? -1 : (v1 > v2) ? 1 : 0;
}

int _reverseHitCompareX(OpRayHit a, OpRayHit b) {
  double v2 = a.fPt.dx;
  double v1 = b.fPt.dx;
  return (v1 < v2) ? -1 : (v1 > v2) ? 1 : 0;
}

int _reverseHitCompareY(OpRayHit a, OpRayHit b) {
  double v2 = a.fPt.dy;
  double v1 = b.fPt.dy;
  return (v1 < v2) ? -1 : (v1 > v2) ? 1 : 0;
}

bool _isCounterClockwise(ui.Offset slope, int opRayDir) {
  bool vPartPos = ((opRayDir & 1) == 0 ? slope.dy : slope.dx) > 0;
  bool leftBottom = ((opRayDir + 1) & 2) != 0;
  return vPartPos == leftBottom;
}
