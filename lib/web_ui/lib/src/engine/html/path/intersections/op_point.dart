// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Contains point, T pair for a curve span.
///
/// Subset of op span used by terminal span (where t = 1).
class OpPtT {
  final double fT;
  final ui.Offset fPt;
  final OpSpanBase _parent;
  bool _fDeleted = false;
  /// Set if at some point a coincident span pointed here.
  bool _fCoincident = false;
  OpPtT? _fNext;
  // Contains winding data.
  OpSpanBase? _fSpan;

  OpPtT(this._parent, this.fPt, this.fT);
  OpSpanBase get span => _parent;
  OpPtT? get next => _fNext;

  /// Segment that owns this intersection point.
  OpSegment get segment => _parent.fSegment;

  /// Add [opp] to linked list.
  void addOpp(OpPtT opp, OpPtT oppPrev) {
    OpPtT? oldNext = _fNext;
    assert(this != opp);
    _fNext = opp;
    assert(oppPrev != oldNext);
    oppPrev._fNext = oldNext;
  }

  /// Inserts [OpPtT] after this point.
  void insert(OpPtT span) {
    assert(span != this);
    span._fNext = _fNext;
    _fNext = span;
  }

  OpPtT starter(OpPtT end) {
    return fT < end.fT ? this : end;
  }

  OpPtT ender(OpPtT end) {
    return fT < end.fT ? end : this;
  }

  bool containsSegmentAtT(OpSegment segment, double t) {
    OpPtT ptT = this;
    OpPtT stopPtT = ptT;
    while ((ptT = ptT.next!) != stopPtT) {
      if (ptT.fT == t && ptT.segment == segment) {
        return true;
      }
    }
    return false;
  }

  bool contains(OpPtT check) {
    assert(this != check);
    OpPtT ptT = this;
    final OpPtT stopPtT = ptT;
    while ((ptT = ptT.next!) != stopPtT) {
      if (ptT == check) {
        return true;
      }
    }
    return false;
  }


  OpPtT? containsSegment(OpSegment check) {
    assert(segment != check);
    OpPtT ptT = this;
    OpPtT stopPtT = ptT;
    while ((ptT = ptT.next!) != stopPtT) {
      if (ptT.segment == check && !ptT.deleted) {
        return ptT;
      }
    }
    return null;
  }

  bool ptAlreadySeen(OpPtT check) {
    while (this != check) {
      if (fPt == check.fPt) {
        return true;
      }
      check = check.next!;
    }
    return false;
  }

  void setDeleted() {
    _fDeleted = true;
  }

  bool get deleted => _fDeleted;

  void setCoincident() {
    assert(!_fDeleted);
    _fCoincident = true;
  }

  /// Sets span to provide winding data.
  void setSpan(OpSpanBase span) {
    _fSpan = span;
  }

  bool get coincident => _fCoincident;

  OpPtT? prev() {
    OpPtT result = this;
    OpPtT? nextPt = this;
    while ((nextPt = nextPt!.next) != this) {
      result = nextPt!;
    }
    assert(result.next == this);
    return result;
  }

  // Returns null if this is already in the opp ptT loop.
  OpPtT? oppPrev(OpPtT opp) {
    // Find the fOpp ptr to opp
    OpPtT? oppPrev = opp.next;
    if (oppPrev == this) {
      return null;
    }
    /// Loop through opp.
    while (oppPrev!.next != opp) {
      oppPrev = oppPrev.next;
      if (oppPrev == this) {
        return null;
      }
    }
    return oppPrev;
  }

  /// Returns any point or sibling for the same span that is not deleted yet.
  OpPtT? active() {
    if (!_fDeleted) {
      return this;
    }
    OpPtT ptT = this;
    OpPtT stopPtT = ptT;
    while ((ptT = ptT.next!) != stopPtT) {
      if (ptT._fSpan == _fSpan && !ptT._fDeleted) {
        return ptT;
      }
    }
    return null; // should never return deleted; caller must abort
  }

  void debugValidate() {
    OpPhase phase = segment.parent.fState.phase;
    if (phase == OpPhase.kIntersecting || phase == OpPhase.kFixWinding) {
      return;
    }
    assert(_fNext != null);
    assert(_fNext != this);
    assert(_fNext!._fNext != null);
    assert(debugLoopLimit(false) == 0);
  }

  int debugLoopLimit(bool report) {
    int loop = 0;
    OpPtT? next = this;
    do {
      for (int check = 1; check < loop - 1; ++check) {
        OpPtT? checkPtT = _fNext;
        OpPtT? innerPtT = checkPtT;
        for (int inner = check + 1; inner < loop; ++inner) {
          innerPtT = innerPtT!.next;
          if (checkPtT == innerPtT) {
            if (report) {
              print("Invalid ptT loop");
            }
            return loop;
          }
        }
      }
      // There's nothing wrong with extremely large loop counts -- but this
      // may appear to hang by taking a very long time to figure out that no
      // loop entry is a duplicate and it's likely that a large loop count is
      // indicative of a bug somewhere.
      if (++loop > 1000) {
          print('OpPtT loop count exceeds 1000');
          return 1000;
      }
    } while ((next = next!.next) != null && next != this);
    return 0;
  }

  OpPtT? find(OpSegment segment) {
    OpPtT ptT = this;
    OpPtT stopPtT = ptT;
    do {
      if (ptT.segment == segment && !ptT.deleted) {
        return ptT;
      }
      ptT = ptT.next!;
    } while (stopPtT != ptT);
    return null;
  }

  static bool overlaps(OpPtT s1, OpPtT e1, OpPtT s2, OpPtT e2,
    List<OpPtT?> overlapPoints) {
    OpPtT start1 = s1.fT < e1.fT ? s1 : e1;
    OpPtT start2 = s2.fT < e2.fT ? s2 : e2;
    overlapPoints[0] = SPath.between(s1.fT, start2.fT, e1.fT) ? start2
            : SPath.between(s2.fT, start1.fT, e2.fT) ? start1 : null;
    OpPtT end1 = s1.fT < e1.fT ? e1 : s1;
    OpPtT end2 = s2.fT < e2.fT ? e2 : s2;
    overlapPoints[1] = SPath.between(s1.fT, end2.fT, e1.fT) ? end2
            : SPath.between(s2.fT, end1.fT, e2.fT) ? end1 : null;
    if (overlapPoints[0] == overlapPoints[1]) {
      assert(start1.fT >= end2.fT || start2.fT >= end1.fT);
      return false;
    }
    assert(null == overlapPoints[0] || overlapPoints[0] != overlapPoints[1]);
    return overlapPoints[0] != null && overlapPoints[1] != null;
  }
}
