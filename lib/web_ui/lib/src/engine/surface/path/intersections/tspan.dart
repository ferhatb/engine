// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10

part of engine;

class TSpan {
  TSpan(this._fPart);

  TCurve _fPart;
  TCurve get part => _fPart;
  double _fStartT = 0;
  double _fEndT = 1;
  TCoincident fCoinStart = TCoincident();
  TCoincident fCoinEnd = TCoincident();
  ui.Rect fBounds = ui.Rect.zero;
  double fBoundsMax = 0;
  // True if line.
  bool fIsLinear = false;
  bool fIsLine = false;
  bool fCollapsed = false;
  bool fDeleted = false;
  bool fHasPerp = false;

  _TSpanBounded? fBounded;
  TSpan? _fPrev;
  TSpan? _fNext;

  double get startT => _fStartT;
  double get endT => _fEndT;

  void init(TCurve c) {
    _fStartT = 0;
    _fEndT = 1;
    fBounded = null;
    resetBounds(c);
  }

  void reset() {
    fBounded = null;
  }

  void resetBounds(TCurve curve) {
    fIsLinear = fIsLine = false;
    initBounds(curve);
  }

  bool initBounds(TCurve c) {
    if (_fStartT.isNaN || _fEndT.isNaN) {
      return false;
    }
    _fPart = c.subDivide(_fStartT, _fEndT);
    fBounds = _fPart.getTightBounds();
    fCoinStart.init();
    fCoinEnd.init();
    fBoundsMax = math.max(fBounds.width, fBounds.height);
    fCollapsed = _fPart.collapsed;
    fDeleted = false;
    fHasPerp = false;
    return fBounds.left <= fBounds.right && fBounds.top <= fBounds.bottom;
  }

  TSpan? get next => _fNext;

  ui.Offset get pointFirst => _fPart[0];
  ui.Offset get pointLast => _fPart[_fPart.pointLast];
  int get pointCount => _fPart.pointCount;

  void markCoincident() {
    fCoinStart!.markCoincident();
    fCoinEnd!.markCoincident();
  }

  TSpan? findOppSpan(TSpan opp) {
    _TSpanBounded? bounded = fBounded;
    while (bounded != null) {
      TSpan? test = bounded.fBounded;
      if (opp == test) {
        return test;
      }
      bounded = bounded._fNext;
    }
    return null;
  }

  /// Intersects span hulls.
  // OPTIMIZE ? If at_most_end_pts_in_common detects that one quad is
  // near linear,
  // use line intersection to guess a better split than 0.5.
  // OPTIMIZE Once at_most_end_pts_in_common detects linear, mark span
  // so all future splits are linear.
  int hullsIntersect(TSpan opp, HullCheckResult result) {
    if (!_rectIntersects(fBounds, opp.fBounds)) {
      return 0;
    }
    _hullCheck(opp, result);
    int hullSect = result.intersectionType;
    if (hullSect != HullCheckResult.kHullIsLinear) {
      return hullSect;
    }
    opp._hullCheck(this, result);
    hullSect = result.intersectionType;
    if (hullSect != HullCheckResult.kHullIsLinear) {
      return hullSect;
    }
    return -1;
  }

  void _hullCheck(TSpan opp, HullCheckResult result) {
    if (fIsLinear) {
      result.intersectionType = HullCheckResult.kHullIsLinear;
      return;
    }
    // First do a quick check of vectors from a shared point so we don't
    // have to do a full intersection if we can reject.
    if (_onlyEndPointsInCommon(opp, result)) {
      assert(result.ptsInCommon);
      result.intersectionType = HullCheckResult.kHullOnlyCommonEndPoint;
      return;
    }
    _HullIntersectResult iRes = _fPart.hullIntersects(opp._fPart);
    if (iRes.success) {
      if (!iRes.isLinear) {  // check set true if linear
        result.intersectionType = HullCheckResult.kHullIntersects;
        return;
      }
      fIsLinear = true;
      fIsLine = _fPart.controlsInside;
      result.intersectionType = result.ptsInCommon
          ? HullCheckResult.kHullIntersects
          : HullCheckResult.kHullIsLinear;
    } else {  // hull is not linear; check set true if intersected at the end points
      result.intersectionType = result.ptsInCommon
          ? HullCheckResult.kHullNoIntersection
          : HullCheckResult.kHullOnlyCommonEndPoint;
    }
  }

  int _linearIntersects(TCurve q2) {
    // Looks like q1 is near-linear.
    // The outside points are usually the extremes.
    int start = 0, end = _fPart.pointLast;
    if (!_fPart.controlsInside) {
      double dist = 0;  // if there's any question, compute distance to find best outsiders
      for (int outer = 0; outer < pointCount - 1; ++outer) {
        ui.Offset p0 = _fPart[outer];
        for (int inner = outer + 1; inner < pointCount; ++inner) {
          ui.Offset p1 = _fPart[inner];
          double test = distanceSquared(p0.dx, p0.dy, p1.dx, p1.dy);
          if (dist > test) {
            continue;
          }
          dist = test;
          start = outer;
          end = inner;
        }
      }
    }
    // see if q2 is on one side of the line formed by the extreme points
    ui.Offset pStart = _fPart[start];
    ui.Offset pEnd = _fPart[end];
    double origX = pStart.dx;
    double origY = pStart.dy;
    double adj = pEnd.dx - origX;
    double opp = pEnd.dy - origY;
    double maxPart = math.max(adj.abs(), opp.abs());
    double sign = 0;
    for (int n = 0; n < q2.pointCount; ++n) {
      ui.Offset q2p = q2[n];
      double dx = q2p.dy - origY;
      double dy = q2p.dx - origX;
      double maxVal = math.max(maxPart, math.max(dx.abs(), dy.abs()));
      double test = (q2p.dy - origY) * adj - (q2p.dx - origX) * opp;
      if (preciselyZeroWhenComparedTo(test, maxVal)) {
        return 1;
      }
      if (approximatelyZeroWhenComparedTo(test, maxVal)) {
        return 3;
      }
      if (n == 0) {
        sign = test;
        continue;
      }
      if (test * sign < 0) {
        return 1;
      }
    }
    return 0;
  }

  /// Checks if opp is only overlapping at common end points.
  bool _onlyEndPointsInCommon(TSpan opp, HullCheckResult result) {
    if (opp.pointFirst == pointFirst) {
      result.start = result.oppStart = true;
    } else if (opp.pointFirst == pointLast) {
      result.start = false;
      result.oppStart = true;
    } else if (opp.pointLast == pointFirst) {
      result.start = true;
      result.oppStart = false;
    } else if (opp.pointLast == pointLast) {
      result.start = result.oppStart = false;
    } else {
      result.ptsInCommon = false;
      return false;
    }
    result.ptsInCommon = true;
    int baseIndex = result.start ? 0 : _fPart.pointLast;
    Float32List otherPts = _fPart.otherPts(baseIndex);
    Float32List oppOtherPts = opp._fPart.otherPts(result.oppStart ? 0 : opp._fPart.pointLast);
    // Look at angles of vectors from shared point to other points on both
    // curves, if all of them are obtuse we know that their hulls can't
    // intersect.
    ui.Offset base = _fPart[baseIndex];
    for (int o1 = 0, len = pointCount - 1; o1 < len; ++o1) {
      double v1x = otherPts[o1 * 2] - base.dx;
      double v1y = otherPts[o1 * 2 + 1] - base.dy;
      for (int o2 = 0; o2 < opp.pointCount - 1; ++o2) {
        double v2x = oppOtherPts[o2 * 2] - base.dx;
        double v2y = oppOtherPts[o2 * 2 + 1] - base.dy;
        double dotProduct = v1x * v2x + v1y * v2y;
        if (dotProduct >= 0) {
          // Angle is acute.
          return false;
        }
      }
    }
    return true;
  }

  /// Checks if t is covered by span list.
  bool contains(double t) {
    TSpan? work = this;
    do {
      if (SPath.between(work!.startT, t, work!.endT)) {
        return true;
      }
    } while ((work = work.next) != null);
    return false;
  }

  bool linearsIntersect(TSpan span) {
    int result = _linearIntersects(span._fPart);
    if (result <= 1) {
      return result == 0 ? false : true;
    }
    assert(span.fIsLinear);
    result = span._linearIntersects(_fPart);
    return result == 0 ? false : true;
  }

  /// Add to linked list of bounded.
  void addBounded(TSpan span) {
    _TSpanBounded bounded = _TSpanBounded(span);
    bounded._fNext = fBounded;
    fBounded = bounded;
  }

  bool split(TSpan work) =>
      splitAt(work, (work.startT + work.endT) / 2);

  bool splitAt(TSpan work, double t) {
    _fStartT = t;
    _fEndT = work.endT;
    if (startT == endT) {
      fCollapsed = true;
      return false;
    }
    work._fEndT = t;
    if (work.startT == work.endT) {
      work.fCollapsed = true;
      return false;
    }
    _fPrev = work;
    _fNext = work._fNext;
    fIsLinear = work.fIsLinear;
    fIsLine = work.fIsLine;

    work._fNext = this;
    if (_fNext != null) {
      _fNext!._fPrev = this;
    }
    validate();
    _TSpanBounded? bounded = work.fBounded;
    fBounded = null;
    while (bounded != null) {
      addBounded(bounded!.fBounded!);
      bounded = bounded.next;
    }
    bounded = fBounded;
    while (bounded != null) {
      bounded!.fBounded!.addBounded(this);
      bounded = bounded!.next;
    }
    return true;
  }

  bool removeAllBounded() {
    bool deleteSpan = false;
    _TSpanBounded? bounded = fBounded;
    while (bounded != null) {
      TSpan opp = bounded.fBounded;
      deleteSpan |= opp.removeBounded(this);
      bounded = bounded.next;
    }
    return deleteSpan;
  }

  bool removeBounded(TSpan opp) {
    if (fHasPerp) {
        bool foundStart = false;
        bool foundEnd = false;
        _TSpanBounded? bounded = fBounded;
        while (bounded != null) {
          TSpan test = bounded.fBounded;
          if (opp != test) {
            foundStart |= SPath.between(test.startT, fCoinStart.perpT, test.endT);
            foundEnd |= SPath.between(test.startT, fCoinEnd.perpT, test.endT);
          }
          bounded = bounded.next;
        }
        if (!foundStart || !foundEnd) {
          fHasPerp = false;
          fCoinStart.init();
          fCoinEnd.init();
        }
    }
    _TSpanBounded? bounded = fBounded;
    _TSpanBounded? prev;
    while (bounded != null) {
      _TSpanBounded? boundedNext = bounded.next;
      if (opp == bounded.fBounded) {
        if (prev != null) {
          prev._fNext = boundedNext;
          return false;
        } else {
          fBounded = boundedNext;
          return fBounded == null;
        }
      }
      prev = bounded;
      bounded = boundedNext;
    }
    assert(false);
    return false;
  }
//  double closestBoundedT(const SkDPoint& pt) const;

  TSpan findOppT(double t) {
    TSpan? result = _oppT(t);
    assert(result != null);
    return result!;
  }
  bool hasOppT(double t) {
    return _oppT(t) != null;
  }

  TSpan? _oppT(double t) {
    _TSpanBounded? bounded = fBounded;
    while (bounded != null) {
      TSpan test = bounded.fBounded!;
      if (SPath.between(test.startT, t, test.endT)) {
        return test;
      }
      bounded = bounded.next;
    }
    return null;
  }

  bool get isBounded => fBounded != null;

  double linearT(ui.Offset pt) {
    ui.Offset len = pointLast - pointFirst;
    return len.dx.abs() > len.dy.abs()
        ? (pt.dx - pointFirst.dx) / len.dx
        : (pt.dy - pointFirst.dy) / len.dy;
  }

  void validate() {
    assert(this != _fPrev);
    assert(this != _fNext);
    assert(_fNext == null || _fNext != _fPrev);
    assert(_fNext == null || this == _fNext!._fPrev);
    assert(_fPrev == null || this == _fPrev!._fNext);
  }
}

class _TSpanBounded {
  _TSpanBounded(this.fBounded);
  TSpan fBounded;

  _TSpanBounded? _fNext;
  _TSpanBounded? get next => _fNext;
}
