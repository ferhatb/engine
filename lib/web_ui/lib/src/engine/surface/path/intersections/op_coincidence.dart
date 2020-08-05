// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

class OpCoincidence {
  OpCoincidence(this.globalState);

  OpGlobalState globalState;
  CoincidentSpans? fHead;
  CoincidentSpans? fTop;

  bool get isEmpty => fHead == null && fTop == null;

  /// Adds a new coincident pair
  void add(OpPtT coinPtTStart, OpPtT coinPtTEnd, OpPtT oppPtTStart,
      OpPtT oppPtTEnd) {
    // OPTIMIZE: caller should have already sorted
    if (!ordered(coinPtTStart, oppPtTStart)) {
      if (oppPtTStart.fT < oppPtTEnd.fT) {
        add(oppPtTStart, oppPtTEnd, coinPtTStart, coinPtTEnd);
      } else {
        add(oppPtTEnd, oppPtTStart, coinPtTEnd, coinPtTStart);
      }
      return;
    }
    // choose the ptT at the front of the list to track
    coinPtTStart = coinPtTStart.span.ptT;
    coinPtTEnd = coinPtTEnd.span.ptT;
    oppPtTStart = oppPtTStart.span.ptT;
    oppPtTEnd = oppPtTEnd.span.ptT;
    assert(coinPtTStart.fT < coinPtTEnd.fT);
    assert(oppPtTStart.fT != oppPtTEnd.fT);
    assert(!coinPtTStart.deleted);
    assert(!coinPtTEnd.deleted);
    assert(!oppPtTStart.deleted);
    assert(!oppPtTEnd.deleted);
    CoincidentSpans coinRec = CoincidentSpans(globalState);
    coinRec.setRange(fHead!, coinPtTStart, coinPtTEnd, oppPtTStart, oppPtTEnd);
    fHead = coinRec;
  }

  static bool ordered(OpPtT ptT1, OpPtT ptT2) =>
      _ordered(ptT1.segment, ptT2.segment);

  static bool _ordered(OpSegment coinSeg, OpSegment oppSeg) {
    if (coinSeg.verb < oppSeg.verb) {
      return true;
    }
    if (coinSeg.verb > oppSeg.verb) {
      return false;
    }
    // Verbs are the same, check if points are ordered.
    int count = (pathOpsVerbToPoints(coinSeg.verb) + 1) * 2;
    Float32List cPoints = coinSeg.points;
    Float32List oPoints = oppSeg.points;
    for (int index = 0; index < count; ++index) {
      double cVal = cPoints[index];
      double oVal = cPoints[index];
      if (cVal < oVal) {
        return true;
      }
      if (cVal > oVal) {
        return false;
      }
    }
    return true;
  }

  void fixUp(OpPtT deleted, OpPtT kept) {
    assert(deleted != kept);
    if (fHead != null) {
      _fixUp(fHead!, deleted, kept);
    }
    if (fTop != null) {
      _fixUp(fHead!, deleted, kept);
    }
  }

  void _fixUp(CoincidentSpans coin, OpPtT deleted, OpPtT kept) {
    CoincidentSpans head = coin;
    do {
      if (coin.coinPtTStart == deleted) {
        if (coin.coinPtTEnd.span == kept.span) {
          release(head, coin);
          continue;
        }
        coin.setCoinPtTStart(kept);
      }
      if (coin.coinPtTEnd == deleted) {
        if (coin.coinPtTStart.span == kept.span) {
          release(head, coin);
          continue;
        }
        coin.setCoinPtTEnd(kept);
      }
      if (coin.oppPtTStart == deleted) {
        if (coin.oppPtTEnd.span == kept.span) {
          release(head, coin);
          continue;
        }
        coin.setOppPtTStart(kept);
      }
      if (coin.oppPtTEnd == deleted) {
        if (coin.oppPtTStart.span == kept.span) {
          release(head, coin);
          continue;
        }
        coin.setOppPtTEnd(kept);
      }
      CoincidentSpans? next = coin.next;
      if (next == null) {
        break;
      }
      coin = next!;
    } while (true);
  }

  bool release(CoincidentSpans coin, CoincidentSpans remove) {
    CoincidentSpans head = coin;
    CoincidentSpans? walk = coin;
    CoincidentSpans? prev;
    CoincidentSpans? next;
    do {
      next = walk!.next;
      if (walk == remove) {
        if (prev != null) {
          prev._fNext = next;
        } else if (head == fHead) {
          fHead = next;
        } else {
          fTop = next;
        }
        break;
      }
      prev = walk;
    } while ((walk = next) != null);
    return walk != null;
  }

  void markCollapsed(OpPtT test) {
    _markCollapsed(fHead, test);
    _markCollapsed(fTop, test);
  }

  void _markCollapsed(CoincidentSpans? coin, OpPtT test) {
    CoincidentSpans? head = coin;
    while (coin != null) {
      if (coin.collapsed(test)) {
        if (zeroOrOne(coin.coinPtTStart.fT) && zeroOrOne(coin.coinPtTEnd.fT)) {
          coin.coinPtTStart.segment.markAllDone();
        }
        if (zeroOrOne(coin!.oppPtTStart.fT) && zeroOrOne(coin!.oppPtTEnd.fT)) {
          coin.oppPtTStart.segment.markAllDone();
        }
        release(head!, coin);
      }
      coin = coin.next;
    }
  }

  void releaseDeleted() {
    _releaseDeleted(fHead);
    _releaseDeleted(fTop);
  }

  void _releaseDeleted(CoincidentSpans? coin) {
    if (coin == null) {
      return;
    }
    CoincidentSpans head = coin!;
    CoincidentSpans? prev;
    CoincidentSpans? next;
    do {
      next = coin!.next;
      if (coin!.coinPtTStart.deleted) {
        assert(coin!.flipped() ? coin!.oppPtTEnd.deleted :
        coin!.oppPtTStart.deleted);
        if (prev != null) {
          prev._fNext = next;
        } else if (head == fHead) {
          fHead = next;
        } else {
          fTop = next;
        }
      } else {
        assert(coin!.flipped() ? !coin!.oppPtTEnd.deleted :
        !coin!.oppPtTStart.deleted);
        prev = coin;
      }
    } while ((coin = next) != null);
  }
}

/// Coincidence for a span pair.
class CoincidentSpans {
  CoincidentSpans(this.globalState);
  final OpGlobalState globalState;

  // Set the range of this span.
  void setRange(CoincidentSpans next, OpPtT coinPtTStart,
      OpPtT coinPtTEnd, OpPtT oppPtTStart, OpPtT oppPtTEnd) {
    assert(OpCoincidence.ordered(coinPtTStart, oppPtTStart));
    _fNext = next;
    setStarts(coinPtTStart, oppPtTStart);
    setEnds(coinPtTEnd, oppPtTEnd);
  }

  CoincidentSpans? _fNext, _fHead;

  /// Start point/t of first segment. t value is smaller than [_fCoinPtTEnd].
  OpPtT? _fCoinPtTStart;
  /// End point/t of first segment.
  OpPtT? _fCoinPtTEnd;
  /// Opposing segment point/t value for [_fCoinPtTStart].
  OpPtT? _fOppPtTStart;
  /// Opposing segment point/t value for [_fCoinPtTEnd].
  OpPtT? _fOppPtTEnd;

  OpPtT get coinPtTEnd => _fCoinPtTEnd!;
  OpPtT get coinPtTStart => _fCoinPtTStart!;
  OpPtT get oppPtTStart => _fOppPtTStart!;
  OpPtT get oppPtTEnd => _fOppPtTEnd!;

  /// Whether coincident span's start and end are the same.
  bool collapsed(OpPtT test) =>
      (_fCoinPtTStart == test && _fCoinPtTEnd!.contains(test))
          || (_fCoinPtTEnd == test && _fCoinPtTStart!.contains(test))
          || (_fOppPtTStart == test && _fOppPtTEnd!.contains(test))
          || (_fOppPtTEnd == test && _fOppPtTStart!.contains(test));

  /// Checks if both points are within t range of spans.
  bool contains(OpPtT s, OpPtT e) {
    if (s.fT > e.fT) {
      OpPtT tmp = e;
      e = s;
      s = tmp;
    }
    /// Points are either on one or opposing segment.
    if (s.segment == _fCoinPtTStart!.segment) {
      return _fCoinPtTStart!.fT <= s.fT && e.fT <= _fCoinPtTEnd!.fT;
    } else {
      assert(s.segment == _fOppPtTStart!.segment);
      /// Opposing segment may have different t value order.
      double oppTs = _fOppPtTStart!.fT;
      double oppTe = _fOppPtTEnd!.fT;
      if (oppTs > oppTe) {
        return oppTs <= e.fT && s.fT <= oppTe;
      } else {
        return oppTs <= s.fT && e.fT <= oppTe;
      }
    }
  }

  /// Corrects end points for all CoincidentSpans.
  void correctEnds() {
    CoincidentSpans? coin = _fHead;
    if (coin == null) {
      return;
    }
    do {
      coin!._correctEnds();
    } while ((coin = coin?.next) != null);
  }

  // sets the span's point to the ptT referenced by the previous-next or
  // next-previous.
  void _correctEnds() {
    OpPtT origPtT = _fCoinPtTStart!;
    OpSpanBase origSpan = origPtT.span;
    OpSpan? prevSpan = origSpan.prev;
    OpPtT? testPtT = prevSpan != null ? prevSpan!.next!.ptT : origSpan.upCast.next!.prev!.ptT;
    setCoinPtTStart(testPtT!);
    origPtT = _fCoinPtTEnd!;
    origSpan = origPtT.span;
    prevSpan = origSpan.prev;
    testPtT = prevSpan != null ? prevSpan!.next!.ptT : origSpan.upCast.next!.prev!.ptT;
    setCoinPtTEnd(testPtT);
    origPtT = _fOppPtTStart!;
    origSpan = origPtT.span;
    prevSpan = origSpan.prev;
    testPtT = prevSpan != null ? prevSpan!.next!.ptT : origSpan.upCast.next!.prev!.ptT;
    setOppPtTStart(testPtT);
    origPtT = _fOppPtTEnd!;
    origSpan = origPtT.span;
    prevSpan = origSpan.prev;
    testPtT = prevSpan != null ? prevSpan!.next!.ptT : origSpan.upCast.next!.prev!.ptT;
    setOppPtTEnd(testPtT);
  }

  /// Expand the range by checking adjacent spans for coincidence using
  bool expand() {
    bool expanded = false;
    OpSegment segment = coinPtTStart!.segment;
    OpSegment oppSegment = oppPtTStart!.segment;
    do {
      OpSpan start = coinPtTStart.span.upCast;
      OpSpan? prev = start.prev;
      OpPtT? oppPtT;
      if (prev == null || null == (oppPtT = prev!.contains(oppSegment))) {
        break;
      }
      double midT = (prev!.t + start.t) / 2;
      if (!segment.isClose(midT, oppSegment)) {
        break;
      }
      setStarts(prev.ptT, oppPtT!);
      expanded = true;
    } while (true);
    do {
      OpSpanBase end = coinPtTEnd.span;
      OpSpanBase? next = end.isFinal() ? null : end.upCast.next;
      if (next != null && next.deleted) {
        break;
      }
      OpPtT? oppPtT;
      if (next == null || null == (oppPtT = next?.contains(oppSegment))) {
        break;
      }
      double midT = (end.t + next.t) / 2;
      if (!segment.isClose(midT, oppSegment)) {
        break;
      }
      setEnds(next.ptT, oppPtT!);
      expanded = true;
    } while (true);
    return expanded;
  }

//  bool extend(const SkOpPtT* coinPtTStart, const SkOpPtT* coinPtTEnd,
//  const SkOpPtT* oppPtTStart, const SkOpPtT* oppPtTEnd);
  bool flipped() => _fOppPtTStart!.fT > _fOppPtTEnd!.fT;
//
//  SkCoincidentSpans* next() { return fNext; }
//  const SkCoincidentSpans* next() const { return fNext; }
//  SkCoincidentSpans** nextPtr() { return &fNext; }
//  const SkOpPtT* oppPtTStart() const;
//  const SkOpPtT* oppPtTEnd() const;
//  // These return non-const pointers so that, as copies, they can be added
//  // to a new span pair
//  SkOpPtT* oppPtTStartWritable() const { return const_cast<SkOpPtT*>(fOppPtTStart); }
//  SkOpPtT* oppPtTEndWritable() const { return const_cast<SkOpPtT*>(fOppPtTEnd); }
//  bool ordered(bool* result) const;
//
//  void set(SkCoincidentSpans* next, const SkOpPtT* coinPtTStart, const SkOpPtT* coinPtTEnd,
//  const SkOpPtT* oppPtTStart, const SkOpPtT* oppPtTEnd);

  void setCoinPtTEnd(OpPtT ptT) {
    assert(ptT == ptT.span.ptT);
    assert(_fCoinPtTStart == null || ptT.fT != _fCoinPtTStart!.fT);
    assert(_fCoinPtTStart == null || _fCoinPtTStart!.segment == ptT.segment);
    _fCoinPtTEnd = ptT;
    ptT.setCoincident();
  }

  void setCoinPtTStart(OpPtT ptT) {
    assert(ptT == ptT.span.ptT);
    assert(_fCoinPtTEnd == null || ptT.fT != _fCoinPtTEnd!.fT);
    assert(_fCoinPtTEnd == null || _fCoinPtTEnd!.segment == ptT.segment);
    _fCoinPtTStart = ptT;
    ptT.setCoincident();
  }

  void setEnds(OpPtT coinPtTEnd, OpPtT oppPtTEnd) {
    setCoinPtTEnd(coinPtTEnd);
    setOppPtTEnd(oppPtTEnd);
  }

  void setOppPtTEnd(OpPtT ptT) {
    assert(ptT == ptT.span.ptT);
    assert(_fOppPtTStart == null || ptT.fT != _fOppPtTStart!.fT);
    assert(_fOppPtTStart == null || _fOppPtTStart!.segment == ptT.segment);
    _fOppPtTEnd = ptT;
    ptT.setCoincident();
  }

  void setOppPtTStart(OpPtT ptT) {
    assert(ptT == ptT.span.ptT);
    assert(_fOppPtTEnd == null || ptT.fT != _fOppPtTEnd!.fT);
    assert(_fOppPtTEnd == null || _fOppPtTEnd!.segment == ptT.segment);
    _fOppPtTStart = ptT;
    ptT.setCoincident();
  }

  void setStarts(OpPtT coinPtTStart, OpPtT oppPtTStart) {
    setCoinPtTStart(coinPtTStart);
    setOppPtTStart(oppPtTStart);
  }

  set next(CoincidentSpans? value) {
    _fNext = value;
  }
  CoincidentSpans? get next => _fNext;

  set head(CoincidentSpans? value) {
    _fHead = value;
  }
  CoincidentSpans? get head => _fHead;
}
