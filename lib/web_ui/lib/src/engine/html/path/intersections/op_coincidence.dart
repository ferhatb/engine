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

  /// If A is coincident with B and B includes an endpoint, and A's matching
  /// point is not the endpoint (i.e., there's an implied line connecting
  /// B-end and A) then assume that the same implied line may intersect another
  /// curve close to B.
  ///
  /// Since we only care about coincidence that was undetected, look at the ptT
  /// list on B-segment adjacent to the B-end/A ptT loop (not in the loop, but
  /// next door) and see if the A matching point is close enough to form another
  /// coincident pair. If so, check for a new coincident span between B-end/A
  /// ptT loop and the adjacent ptT loop.
  bool addEndMovedSpans() {
    CoincidentSpans? span = fHead;
    if (span == null) {
      return true;
    }
    fTop = span;
    fHead = null;
    do {
      bool startPointsMatch = span!.coinPtTStart.fPt == span.oppPtTStart.fPt;
      if (!startPointsMatch) {
        if (1 == span.coinPtTStart.fT) {
          return false;
        }
        bool onEnd = span.coinPtTStart.fT == 0;
        bool oppOnEnd = zeroOrOne(span.oppPtTStart.fT);
        if (onEnd) {
          if (!oppOnEnd) {
            // if both are on end, any nearby intersect was already found.
            if (!_addEndMovedSpansOpPt(span.oppPtTStart)) {
              return false;
            }
          }
        } else if (oppOnEnd) {
          if (!_addEndMovedSpansOpPt(span.coinPtTStart)) {
            return false;
          }
        }
      }
      bool endPointsMatch = span.coinPtTEnd.fPt == span.oppPtTEnd.fPt;
      if (!endPointsMatch) {
        bool onEnd = span.coinPtTEnd.fT == 1;
        bool oOnEnd = zeroOrOne(span.oppPtTEnd.fT);
        if (onEnd) {
          if (!oOnEnd) {
            if (!_addEndMovedSpansOpPt(span.oppPtTEnd)) {
                return false;
            }
          }
        } else if (oOnEnd) {
          if (!_addEndMovedSpansOpPt(span.coinPtTEnd)) {
            return false;
          }
        }
      }
    } while ((span = span.next) != null);
    restoreHead();
    return true;
  }

  /// Restore head by setting it to fTop.
  void restoreHead() {
    if (fHead == null) {
      fHead = fTop;
    } else {
      // Find the last element that has next == null.
      CoincidentSpans? walk = fHead;
      while (walk!.next != null) {
        walk = walk.next;
      }
      walk.next = fTop;
    }
    fTop = null;
    // Segments may have collapsed in the meantime;
    // remove empty referenced segments (that are done).
    if (fHead == null) {
      return;
    }
    CoincidentSpans? prev;
    CoincidentSpans? walk = fHead;
    while (walk != null) {
      if (walk.coinPtTStart.segment.done() || walk.oppPtTStart.segment.done()) {
        if (prev == null) {
          fHead = walk.next;
          prev = null;
        } else {
          prev.next = walk.next;
        }
      } else {
        prev = walk;
      }
      walk = walk.next;
    }
  }

  bool _addEndMovedSpansOpPt(OpPtT ptT) {
    if (ptT.span.upCastable == null) {
      return false;
    }
    OpSpan base = ptT.span.upCast;
    OpSpan? prev = base.prev;
    if (prev == null) {
      return false;
    }
    if (!prev.isCanceled) {
      if (!_addEndMovedSpans(base, base.prev!)) {
        return false;
      }
    }
    if (!base.isCanceled) {
      if (!_addEndMovedSpans(base, base.next!)) {
        return false;
      }
    }
    return true;
  }

  bool _addEndMovedSpans(OpSpan base, OpSpanBase testSpan) {
    OpPtT testPtT = testSpan.ptT;
    OpPtT stopPtT = testPtT;
    OpSegment baseSeg = base.segment;
    int escapeHatch = 100000;  // this is 100 times larger than the debugLoopLimit test
    while ((testPtT = testPtT.next!) != stopPtT) {
      if (--escapeHatch <= 0) {
        return false;  // if triggered (likely by a fuzz-generated test) too complex to succeed
      }
      OpSegment testSeg = testPtT.segment;
      if (testPtT.deleted) {
        continue;
      }
      if (testSeg == baseSeg) {
        continue;
      }
      if (testPtT.span.ptT != testPtT) {
        continue;
      }
      if (containsSegment(baseSeg, testSeg, testPtT.fT)) {
        continue;
      }
      // Intersect perp with base.ptT with testPtT.segment.
      ui.Offset dxdy = baseSeg.dxdyAtT(base.t);
      ui.Offset pt = base.ptT.fPt;
      DLine ray = DLine(pt.dx, pt.dy, pt.dx + dxdy.dy, pt.dy - dxdy.dx);
      Intersections i = Intersections();
      intersectRay(testSeg.points, testSeg.verb, testSeg.weight, ray, i);

      for (int index = 0; index < i.fUsed; ++index) {
        double t = i.fT0[index];
        if (!SPath.between(0, t, 1)) {
          continue;
        }
        double oppPtX = i.ptX[index];
        double oppPtY = i.ptY[index];
        if (!approximatelyEqualPoints(oppPtX, oppPtY, pt.dx, pt.dy)) {
          continue;
        }
        OpPtT? oppStart = testSeg.addT(t);
        if (oppStart == testPtT) {
          continue;
        }
        oppStart!.span.addOpp(base);
        if (oppStart.deleted) {
          continue;
        }
        OpSegment coinSeg = base.segment;
        OpSegment oppSeg = oppStart.segment;
        double coinTs, coinTe, oppTs, oppTe;
        if (_ordered(coinSeg, oppSeg)) {
          coinTs = base.t;
          coinTe = testSpan.t;
          oppTs = oppStart.fT;
          oppTe = testPtT.fT;
        } else {
          OpSegment temp = coinSeg;
          coinSeg = oppSeg;
          oppSeg = temp;
          coinTs = oppStart.fT;
          coinTe = testPtT.fT;
          oppTs = base.t;
          oppTe = testSpan.t;
        }
        if (coinTs > coinTe) {
          double temp = coinTs;
          coinTs = coinTe;
          coinTe = temp;
          temp = oppTs;
          oppTs = oppTe;
          oppTe = temp;
        }
        bool added;
        int res = addOrOverlap(coinSeg, oppSeg, coinTs, coinTe, oppTs, oppTe);
        if (res== kAddFailed) {
          return false;
        }
      }
    }
    return true;
  }

  // Return values for [addMissing].
  static const int kAddMissingFailed = -1;
  static const int kAddMissingSuccess = 0;
  static const int kAddMissingSuccessAndAdded = 1;

  static const bool fuzzingEnabled = false;

  /// Detects overlaps of different coincident runs on same segment.
  /// does not detect overlaps for pairs without any segments in common.
  /// Returns true if caller should loop again.
  int addMissing() {
    CoincidentSpans? outer = fHead;
    if (outer == null) {
      return kAddMissingSuccess;
    }
    fTop = outer;
    fHead = null;
    bool added = false;
    do {
      // addifmissing can modify the list that this is walking
      // save head so that walker can iterate over old data unperturbed
      // addifmissing adds to head freely then add saved head in the end
      OpPtT ocs = outer!.coinPtTStart;
      if (ocs.deleted) {
        return kAddMissingFailed;
      }
      OpSegment outerCoin = ocs.segment;
      if (outerCoin.done()) {
        return kAddMissingFailed;
      }
      OpPtT oos = outer.oppPtTStart;
      if (oos.deleted) {
        return kAddMissingSuccess;
      }
      OpSegment outerOpp = oos.segment;
      assert(!outerOpp.done());
      OpSegment outerCoinWritable = outerCoin;
      OpSegment outerOppWritable = outerOpp;
      CoincidentSpans? inner = outer;
      int safetyNet = 1000;
      while ((inner = inner!.next) != null) {
        if (fuzzingEnabled) {
          if (0 == --safetyNet) {
            return kAddMissingFailed;
          }
        }
        debugValidate();
        OpPtT ics = inner!.coinPtTStart;
        if (ics.deleted) {
          return kAddMissingFailed;
        }
        OpSegment innerCoin = ics.segment;
        if (innerCoin.done()) {
          return kAddMissingFailed;
        }
        OpPtT ios = inner.oppPtTStart;
        if (ios.deleted) {
          return kAddMissingFailed;
        }
        OpSegment innerOpp = ios.segment;
        assert(!innerOpp.done());
        OpSegment innerCoinWritable = innerCoin;
        OpSegment innerOppWritable = innerOpp;
        if (outerCoin == innerCoin) {
          OpPtT oce = outer.coinPtTEnd;
          if (oce.deleted) {
            return kAddMissingSuccess;
          }
          OpPtT ice = inner.coinPtTEnd;
          if (ice.deleted) {
            return kAddMissingFailed;
          }
          if (outerOpp != innerOpp) {
            List<double> res = _coinOverlap(ocs, oce, ics, ice);
            double overS = res[0];
            double overE = res[1];
            if (overS < overE) {
              int addResult = addIfMissing(
                  ocs.starter(oce), ics.starter(ice),
                  overS, overE, outerOppWritable, innerOppWritable,
                  ocs.ender(oce), ics.ender(ice));
              if (addResult == kAddFailed) {
                return kAddMissingFailed;
              }
              added = (addResult == kAddSuccessAndAdded);
            }
          }
        } else if (outerCoin == innerOpp) {
          OpPtT oce = outer.coinPtTEnd;
          if (oce.deleted) {
            return kAddMissingFailed;
          }
          OpPtT ioe = inner.oppPtTEnd;
          if (ioe.deleted) {
            return kAddMissingFailed;
          }
          if (outerOpp != innerCoin) {
            List<double> res = _coinOverlap(ocs, oce, ios, ioe);
            double overS = res[0];
            double overE = res[1];
            if (overS < overE) {
              int addResult = addIfMissing(
                  ocs.starter(oce), ios.starter(ioe),
                  overS, overE, outerOppWritable, innerCoinWritable,
                  ocs.ender(oce), ios.ender(ioe));
              if (addResult == kAddFailed) {
                return kAddMissingFailed;
              }
              added = (addResult == kAddSuccessAndAdded);
            }
          }
        } else if (outerOpp == innerCoin) {
          OpPtT ooe = outer.oppPtTEnd;
          if (ooe.deleted) {
            return kAddMissingFailed;
          }
          OpPtT ice = inner.coinPtTEnd;
          if (ice.deleted) {
            return kAddMissingFailed;
          }
          assert(outerCoin != innerOpp);
          List<double> res = _coinOverlap(oos, ooe, ics, ice);
            double overS = res[0];
            double overE = res[1];
            if (overS < overE) {
            int addResult = addIfMissing(
                oos.starter(ooe), ics.starter(ice),
                overS, overE, outerCoinWritable, innerOppWritable,
                oos.ender(ooe), ics.ender(ice));
            if (addResult == kAddFailed) {
              return kAddMissingFailed;
            }
            added = (addResult == kAddSuccessAndAdded);
          }
        } else if (outerOpp == innerOpp) {
          OpPtT ooe = outer.oppPtTEnd;
          if (ooe.deleted) {
            return kAddMissingFailed;
          }
          OpPtT ioe = inner.oppPtTEnd;
          if (ioe.deleted) {
            return kAddMissingSuccess;
          }
          assert(outerCoin != innerCoin);
          List<double> res = _coinOverlap(oos, ooe, ios, ioe);
            double overS = res[0];
            double overE = res[1];
            if (overS < overE) {
            int addResult = addIfMissing(
                oos.starter(ooe), ios.starter(ioe),
                overS, overE, outerCoinWritable, innerCoinWritable,
                oos.ender(ooe), ios.ender(ioe));
            if (addResult == kAddFailed) {
              return kAddMissingFailed;
            }
            added = (addResult == kAddSuccessAndAdded);
          }
        }
        debugValidate();
      }
    } while ((outer = outer.next) != null);
    restoreHead();
    return added ? kAddMissingSuccessAndAdded : kAddMissingSuccess;
  }

  // Note that over1s, over1e, over2s, over2e are ordered.
  int addIfMissing(OpPtT over1s, OpPtT over2s,
        double tStart, double tEnd, OpSegment coinSeg, OpSegment oppSeg,
        OpPtT over1e, OpPtT over2e) {
    assert(tStart < tEnd);
    assert(over1s.fT < over1e.fT);
    assert(SPath.between(over1s.fT, tStart, over1e.fT));
    assert(SPath.between(over1s.fT, tEnd, over1e.fT));
    assert(over2s.fT < over2e.fT);
    assert(SPath.between(over2s.fT, tStart, over2e.fT));
    assert(SPath.between(over2s.fT, tEnd, over2e.fT));
    assert(over1s.segment == over1e.segment);
    assert(over2s.segment == over2e.segment);
    assert(over1s.segment == over2s.segment);
    assert(over1s.segment != coinSeg);
    assert(over1s.segment != oppSeg);
    assert(coinSeg != oppSeg);
    double coinTs, coinTe, oppTs, oppTe;
    coinTs = _tRange(over1s, tStart, coinSeg, over1e);
    coinTe = _tRange(over1s, tEnd, coinSeg, over1e);
    int result = coinSeg.collapsed(coinTs, coinTe);
    if (OpSpanBase.kNotCollapsed != result) {
      return OpSpanBase.kCollapsed == result ? kAddSuccess : kAddFailed;
    }
    oppTs = _tRange(over2s, tStart, oppSeg, over2e);
    oppTe = _tRange(over2s, tEnd, oppSeg, over2e);
    result = oppSeg.collapsed(oppTs, oppTe);
    if (OpSpanBase.kNotCollapsed != result) {
      return OpSpanBase.kCollapsed == result ? kAddSuccess : kAddFailed;
    }
    if (coinTs > coinTe) {
      double temp = coinTs;
      coinTs = coinTe;
      coinTe = temp;
      temp = oppTs;
      oppTs = oppTe;
      oppTe = temp;
    }
    return addOrOverlap(coinSeg, oppSeg, coinTs, coinTe, oppTs, oppTe);
  }

  // given a t span, map the same range on the coincident span
  // the curves may not scale linearly, so interpolation may only happen within
  // known points remap over1s, over1e, cointPtTStart, coinPtTEnd to smallest
  // range that captures over1s then repeat to capture over1e.
  double _tRange(OpPtT overS, double t, OpSegment coinSeg, OpPtT overE) {
    OpSpanBase? work = overS.span;
    OpPtT? foundStart;
    OpPtT? foundEnd;
    OpPtT? coinStart;
    OpPtT? coinEnd;
    do {
      OpPtT? contained = work!.containsSegment(coinSeg);
      if (contained == null) {
        if (work.isFinal()) {
          break;
        }
        continue;
      }
      if (work.t <= t) {
        coinStart = contained;
        foundStart = work.ptT;
      }
      if (work.t >= t) {
          coinEnd = contained;
          foundEnd = work.ptT;
          break;
      }
      assert(work.ptT != overE);
    } while ((work = work.upCast.next) != null);
    if (coinStart == null || coinEnd == null) {
      return 1;
    }
    // while overS->fT <=t and overS contains coinSeg
    double denom = foundEnd!.fT - foundStart!.fT;
    double sRatio = denom != 0 ? (t - foundStart.fT) / denom : 1;
    return coinStart.fT + (coinEnd.fT - coinStart.fT) * sRatio;
  }

  int kAddFailed = -1;
  int kAddSuccess = 0;
  int kAddSuccessAndAdded = 1;

  // If this is called by addEndMovedSpans(), a returned false propogates out to
  // an abort.
  // If this is called by AddIfMissing(), a returned false indicates there was
  // nothing to add.
  int addOrOverlap(OpSegment coinSeg, OpSegment oppSeg,
        double coinTs, double coinTe, double oppTs, double oppTe) {
    List<CoincidentSpans> overlaps = [];
    if (fTop == null) {
      return kAddFailed;
    }
    if (!checkOverlap(fTop!, coinSeg, oppSeg, coinTs, coinTe, oppTs, oppTe, overlaps)) {
      return kAddSuccess;
    }
    if (fHead != null && !checkOverlap(fHead!, coinSeg, oppSeg, coinTs,
            coinTe, oppTs, oppTe, overlaps)) {
      return kAddSuccess;
    }
    CoincidentSpans? overlap = overlaps.isNotEmpty ? overlaps[0] : null;
    // Combine overlaps before continuing.
    for (int index = 1, len = overlaps.length; index < len; ++index) {
      CoincidentSpans test = overlaps[index];
      if (overlap!.coinPtTStart.fT > test.coinPtTStart.fT) {
        overlap.setCoinPtTStart(test.coinPtTStart);
      }
      if (overlap.coinPtTEnd.fT < test.coinPtTEnd.fT) {
        overlap.setCoinPtTEnd(test.coinPtTEnd);
      }
      if (overlap.flipped()
            ? overlap.oppPtTStart.fT < test.oppPtTStart.fT
            : overlap.oppPtTStart.fT > test.oppPtTStart.fT) {
        overlap.setOppPtTStart(test.oppPtTStart);
      }
      if (overlap.flipped()
            ? overlap.oppPtTEnd.fT > test.oppPtTEnd.fT
            : overlap.oppPtTEnd.fT < test.oppPtTEnd.fT) {
        overlap.setOppPtTEnd(test.oppPtTEnd);
      }
      if (fHead == null || !release(fHead!, test)) {
        bool res = release(fTop!, test);
        assert(res);
      }
    }
    OpPtT? cs = coinSeg.existing(coinTs, oppSeg);
    OpPtT? ce = coinSeg.existing(coinTe, oppSeg);
    if (overlap != null && cs != null && ce != null && overlap.contains(cs, ce)) {
      return kAddSuccess;
    }
    if (cs == ce && cs != null) {
      return kAddFailed;
    }
    OpPtT? os = oppSeg.existing(oppTs, coinSeg);
    OpPtT? oe = oppSeg.existing(oppTe, coinSeg);
    if (overlap != null && os != null && oe != null && overlap.contains(os, oe)) {
      return kAddSuccess;
    }
    if (cs != null && cs.deleted) {
      return kAddFailed;
    }
    if (os != null && os.deleted) {
      return kAddFailed;
    }
    if (ce != null && ce.deleted) {
      return kAddFailed;
    }
    if (oe != null && oe.deleted) {
      return kAddFailed;
    }
    OpPtT? csExisting = cs == null ? coinSeg.existing(coinTs, null) : null;
    OpPtT? ceExisting = ce == null ? coinSeg.existing(coinTe, null) : null;
    if (csExisting != null && csExisting == ceExisting) {
      return kAddFailed;
    }
    if (ceExisting != null && (ceExisting == cs ||
            ceExisting.contains(csExisting ?? cs!))) {
      return kAddFailed;
    }
    OpPtT? osExisting = os == null ? oppSeg.existing(oppTs, null) : null;
    OpPtT? oeExisting = oe == null ? oppSeg.existing(oppTe, null) : null;
    if (osExisting != null && osExisting == oeExisting) {
      return kAddFailed;
    }
    if (osExisting != null && (osExisting == oe ||
            osExisting.contains(oeExisting ?? oe!))) {
      return kAddFailed;
    }
    if (oeExisting != null && (oeExisting == os ||
            oeExisting.contains(osExisting ?? os!))) {
      return kAddFailed;
    }
    debugValidate();
    if (cs == null || os == null) {
      OpPtT? csWritable = cs ?? coinSeg.addT(coinTs);
      if (csWritable == ce) {
        return kAddSuccess;
      }
      OpPtT? osWritable = os ?? oppSeg.addT(oppTs);
      if (csWritable == null || osWritable == null) {
        return kAddFailed;
      }
      csWritable.span.addOpp(osWritable.span);
      cs = csWritable;
      os = osWritable.active();
      if (os == null) {
        // All opposing deleted, fail.
        return kAddFailed;
      }
      if ((ce != null && ce.deleted) || (oe != null && oe.deleted)) {
        return kAddFailed;
      }
    }
    if (ce == null || oe == null) {
      OpPtT? ceWritable = ce ?? coinSeg.addT(coinTe);
      OpPtT? oeWritable = oe ?? oppSeg.addT(oppTe);
      if (null == ceWritable!.span.addOpp(oeWritable!.span)) {
        return kAddFailed;
      }
      ce = ceWritable;
      oe = oeWritable;
    }
    debugValidate();
    if (cs.deleted) {
      return kAddFailed;
    }
    if (os.deleted) {
      return kAddFailed;
    }
    if (ce.deleted) {
      return kAddFailed;
    }
    if (oe.deleted) {
      return kAddFailed;
    }
    if (cs.contains(ce) || os.contains(oe)) {
      return kAddFailed;
    }
    bool result = true;
    if (overlap != null) {
      if (overlap.coinPtTStart.segment == coinSeg) {
        result = overlap.extend(cs, ce, os, oe);
      } else {
        if (os.fT > oe.fT) {
          OpPtT temp = cs;
          cs = ce;
          ce = temp;
          temp = os;
          os = oe;
          oe = temp;
        }
        result = overlap.extend(os, oe, cs, ce);
      }
    } else {
      add(cs, ce, os, oe);
    }
    debugValidate();
    return (result) ? kAddSuccessAndAdded : kAddSuccess;
  }

  // return true if span overlaps existing and needs to adjust the coincident list
  bool checkOverlap(CoincidentSpans check,
    OpSegment coinSeg, OpSegment oppSeg,
        double coinTs, double coinTe, double oppTs, double oppTe,
        List<CoincidentSpans> overlaps) {
    /// Make sure segments and oppT values are ordered.
    if (!_ordered(coinSeg, oppSeg)) {
      if (oppTs < oppTe) {
        return checkOverlap(check, oppSeg, coinSeg, oppTs, oppTe, coinTs, coinTe,
          overlaps);
      }
      return checkOverlap(check, oppSeg, coinSeg, oppTe, oppTs, coinTe, coinTs, overlaps);
    }
    bool swapOpp = oppTs > oppTe;
    if (swapOpp) {
      double temp = oppTs;
      oppTs = oppTe;
      oppTe = temp;
    }
    CoincidentSpans? walk = check;
    do {
      if (walk!.coinPtTStart.segment != coinSeg) {
        continue;
      }
      if (walk.oppPtTStart.segment != oppSeg) {
        continue;
      }
      double checkTs = walk.coinPtTStart.fT;
      double checkTe = walk.coinPtTEnd.fT;
      bool coinOutside = coinTe < checkTs || coinTs > checkTe;
      double oCheckTs = walk.oppPtTStart.fT;
      double oCheckTe = walk.oppPtTEnd.fT;
      if (swapOpp) {
        if (oCheckTs <= oCheckTe) {
            return false;
        }
        double temp = oCheckTs;
        oCheckTs = oCheckTe;
        oCheckTe = temp;
      }
      bool oppOutside = oppTe < oCheckTs || oppTs > oCheckTe;
      if (coinOutside && oppOutside) {
          continue;
      }
      bool coinInside = coinTe <= checkTe && coinTs >= checkTs;
      bool oppInside = oppTe <= oCheckTe && oppTs >= oCheckTs;
      if (coinInside && oppInside) {  // already included, do nothing
          return false;
      }
      overlaps.add(walk); // partial overlap, extend existing entry
    } while ((walk = walk.next) != null);
    return true;
  }

  // Expand the range by checking adjacent spans for coincidence.
  bool expand() {
    CoincidentSpans? coin = fHead;
    if (coin == null) {
      return false;
    }
    bool expanded = false;
    do {
      if (coin!.expand()) {
        // Check to see if multiple spans expanded so they are now identical
        CoincidentSpans? test = fHead;
        do {
          if (coin == test) {
            continue;
          }
          if (coin.coinPtTStart == test!.coinPtTStart
              && coin.oppPtTStart == test.oppPtTStart) {
            release(fHead!, test);
            break;
          }
        } while ((test = test!.next) != null);
        expanded = true;
      }
    } while ((coin = coin.next) != null);
    return expanded;
  }

  bool contains(OpPtT coinPtTStart, OpPtT coinPtTEnd,
        OpPtT oppPtTStart, OpPtT oppPtTEnd) {
    CoincidentSpans? test = fHead;
    if (test == null) {
      return false;
    }
    OpSegment coinSeg = coinPtTStart.segment;
    OpSegment oppSeg = oppPtTStart.segment;
    if (!ordered(coinPtTStart, oppPtTStart)) {
        OpSegment swapSeg = coinSeg;
        coinSeg = oppSeg;
        oppSeg = swapSeg;
        OpPtT swapP = coinPtTStart;
        coinPtTStart = oppPtTStart;
        oppPtTStart = swapP;
        swapP = coinPtTEnd;
        coinPtTEnd = oppPtTEnd;
        oppPtTEnd = swapP;
        if (coinPtTStart.fT > coinPtTEnd.fT) {
          swapP = coinPtTStart;
          coinPtTStart = coinPtTEnd;
          coinPtTEnd = swapP;
          swapP = oppPtTStart;
          oppPtTStart = oppPtTEnd;
          oppPtTEnd = swapP;
        }
    }
    double oppMinT = math.min(oppPtTStart.fT, oppPtTEnd.fT);
    double oppMaxT = math.max(oppPtTStart.fT, oppPtTEnd.fT);
    do {
      if (coinSeg != test!.coinPtTStart.segment) {
        continue;
      }
      if (coinPtTStart.fT < test.coinPtTStart.fT) {
        continue;
      }
      if (coinPtTEnd.fT > test.coinPtTEnd.fT) {
        continue;
      }
      if (oppSeg != test.oppPtTStart.segment) {
        continue;
      }
      if (oppMinT < math.min(test.oppPtTStart.fT, test.oppPtTEnd.fT)) {
        continue;
      }
      if (oppMaxT > math.max(test.oppPtTStart.fT, test.oppPtTEnd.fT)) {
        continue;
      }
      return true;
    } while ((test = test.next) != null);
    return false;
  }

  bool containsSegment(OpSegment seg, OpSegment opp, double oppT) {
    if (_contains(fHead, seg, opp, oppT)) {
      return true;
    }
    if (_contains(fTop, seg, opp, oppT)) {
      return true;
    }
    return false;
  }

  bool _contains(CoincidentSpans? coin, OpSegment seg, OpSegment opp,
      double oppT) {
    if (coin == null) {
      return false;
    }
    do {
      if (coin!.coinPtTStart.segment == seg && coin.oppPtTStart.segment == opp
          && SPath.between(coin.oppPtTStart.fT, oppT, coin.oppPtTEnd.fT)) {
        return true;
      }
      if (coin.oppPtTStart.segment == seg && coin.coinPtTStart.segment == opp
          && SPath.between(coin.coinPtTStart.fT, oppT, coin.coinPtTEnd.fT)) {
          return true;
      }
    } while ((coin = coin.next) != null);
    return false;
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
      double oVal = oPoints[index];
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
      coin = next;
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

  void releaseCoinsOnSegment(OpSegment deleted) {
    CoincidentSpans? coin = fHead;
    if (coin == null) {
      return;
    }
    do {
      if (coin!.coinPtTStart.segment == deleted
              || coin.coinPtTEnd.segment == deleted
              || coin.oppPtTStart.segment == deleted
              || coin.oppPtTEnd.segment == deleted) {
        release(fHead!, coin);
      }
    } while ((coin = coin.next) != null);
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
        if (zeroOrOne(coin.oppPtTStart.fT) && zeroOrOne(coin.oppPtTEnd.fT)) {
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
    CoincidentSpans head = coin;
    CoincidentSpans? prev;
    CoincidentSpans? next;
    do {
      next = coin!.next;
      if (coin.coinPtTStart.deleted) {
        assert(coin.flipped() ? coin.oppPtTEnd.deleted :
        coin.oppPtTStart.deleted);
        if (prev != null) {
          prev._fNext = next;
        } else if (head == fHead) {
          fHead = next;
        } else {
          fTop = next;
        }
      } else {
        assert(coin.flipped() ? !coin.oppPtTEnd.deleted :
        !coin.oppPtTStart.deleted);
        prev = coin;
      }
    } while ((coin = next) != null);
  }

  // For each coincident pair, match the spans
  // if the spans don't match, add the missing pt to the segment and loop it
  // in the opposite span.
  bool addExpanded() {
    CoincidentSpans? coin = fHead;
    if (coin == null) {
      return true;
    }
    do {
      OpPtT startPtT = coin!.coinPtTStart;
      OpPtT oStartPtT = coin.oppPtTStart;
      double priorT = startPtT.fT;
      double oPriorT = oStartPtT.fT;
      if (!startPtT.contains(oStartPtT)) {
        return false;
      }
      assert(coin.coinPtTEnd.contains(coin.oppPtTEnd));
      OpSpanBase start = startPtT.span;
      OpSpanBase oStart = oStartPtT.span;
      OpSpanBase end = coin.coinPtTEnd.span;
      OpSpanBase oEnd = coin.oppPtTEnd.span;
      if (!oEnd.deleted) {
        return false;
      }
      if (start.upCastable() == null) {
        return false;
      }
      OpSpanBase? test = start.upCast.next;
      if (!coin.flipped() && oStart.upCastable() == null) {
        return false;
      }
      OpSpanBase? oTest = coin.flipped() ? oStart.prev : oStart.upCast.next;
      if (oTest == null) {
        return false;
      }
      OpSegment seg = start.segment;
      OpSegment oSeg = oStart.segment;
      while (test != end || oTest != oEnd) {
        OpPtT? containedOpp = test!.ptT.containsSegment(oSeg);
        OpPtT? containedThis = oTest!.ptT.containsSegment(seg);
        if (containedOpp == null || containedThis == null) {
          // Choose the ends, or the first common pt-t list shared by both.
          double nextT, oNextT;
          if (containedOpp != null) {
              nextT = test.t;
              oNextT = containedOpp.fT;
          } else if (containedThis != null) {
              nextT = containedThis.fT;
              oNextT = oTest.t;
          } else {
              // iterate through until a pt-t list found that contains the other
              OpSpanBase? walk = test;
              OpPtT? walkOpp;
              do {
                  if (null == walk!.upCastable()) {
                    return false;
                  }
                  walk = walk.upCast.next;
              } while ((walkOpp = walk!.ptT.containsSegment(oSeg)) == null
                      && walk != coin.coinPtTEnd.span);
              if (walkOpp == null) {
                return false;
              }
              nextT = walk.t;
              oNextT = walkOpp.fT;
          }
          // use t ranges to guess which one is missing
          double startRange = nextT - priorT;
          if (startRange == 0) {
            return false;
          }
          double startPart = (test.t - priorT) / startRange;
          double oStartRange = oNextT - oPriorT;
          if (oStartRange == 0) {
            return false;
          }
          double oStartPart = (oTest.t - oPriorT) / oStartRange;
          if (startPart == oStartPart) {
            return false;
          }
          bool addToOpp = containedOpp == null &&
              containedThis == null ? startPart < oStartPart : true;
          _SegmentBreakResult res;
          if (addToOpp) {
            res = oSeg.addExpanded( oPriorT + oStartRange * startPart, test);
          } else {
            res = seg.addExpanded(priorT + startRange * oStartPart, oTest);
          }
          bool success = res.success;
          bool startOver = res.startOver;
          if (!success) {
            return false;
          }
          if (startOver) {
              test = start;
              oTest = oStart;
          }
          end = coin.coinPtTEnd.span;
          oEnd = coin.oppPtTEnd.span;
        }
        if (test != end) {
          if (test.upCastable() == null) {
            return false;
          }
          priorT = test.t;
          test = test.upCast.next;
        }
        if (oTest != oEnd) {
          oPriorT = oTest.t;
          if (coin.flipped()) {
            oTest = oTest.prev;
          } else {
            if (oTest.upCastable() == null) {
              return false;
            }
            oTest = oTest.upCast.next;
          }
          if (oTest == null) {
            return false;
          }
        }
      }
    } while ((coin = coin.next) != null);
    return true;
  }

  void correctEnds() {
    CoincidentSpans? coin = fHead;
    if (coin == null) {
      return;
    }
    do {
      coin!.correctEnds();
    } while ((coin = coin.next) != null);
  }

  static const bool debugCoincidenceEnabled = true;

  void debugValidate() {
    if (debugCoincidenceEnabled)
    _debugValidate(fHead!, fTop);
    _debugValidate(fTop!, null);
  }

  static void _debugValidate(CoincidentSpans head, CoincidentSpans? opt) {
    // look for pts inside coincident spans that are not inside the opposite spans
    CoincidentSpans? coin = head;
    while (coin != null) {
      assert(_ordered(coin.coinPtTStart.segment, coin.oppPtTStart.segment));
      assert(coin.coinPtTStart.span.ptT == coin.coinPtTStart);
      assert(coin.coinPtTEnd.span.ptT == coin.coinPtTEnd);
      assert(coin.oppPtTStart.span.ptT == coin.oppPtTStart);
      assert(coin.oppPtTEnd.span.ptT == coin.oppPtTEnd);
      coin = coin.next;
    }
    _debugCheckOverlapTop(head, opt);
  }

  // Checks to make sure coincident spans don't overlap.
  static void _debugCheckOverlapTop(CoincidentSpans head, CoincidentSpans? opt) {
    CoincidentSpans? test = head;
    while (test != null) {
      CoincidentSpans? next = test.next;
      _debugCheckOverlap(test, next);
      _debugCheckOverlap(test, opt);
      test = next;
    }
  }

  static void _debugCheckOverlap(CoincidentSpans test,
      CoincidentSpans? list) {
    if (list == null) {
      return;
    }
    OpSegment coinSeg = test.coinPtTStart.segment;
    assert(coinSeg == test.coinPtTEnd.segment,
      'Start and end points should be on same segment');
    OpSegment oppSeg = test.oppPtTStart.segment;
    assert(oppSeg == test.oppPtTEnd.segment,
      'Start and end points should be on same segment');
    assert(coinSeg != test.oppPtTStart.segment,
      'Opposite should not be on same segment');
    double tcs = test.coinPtTStart.fT;
    assert(SPath.between(0, tcs, 1),
      'start point should be at valid t');
    double tce = test.coinPtTEnd.fT;
    assert(SPath.between(0, tce, 1),
      'end point should be at valid t');
    assert(tcs < tce, 'start and end points should be sorted by t');
    double tos = test.oppPtTStart.fT;
    assert(SPath.between(0, tos, 1));
    double toe = test.oppPtTEnd.fT;
    assert(SPath.between(0, toe, 1));
    assert(tos != toe, 'Start and end points should not overlap in t');
    if (tos > toe) {
      // Sort start/end t of opposite.
      double temp = tos;
      tos = toe;
      toe = temp;
    }
    do {
      double lcs, lce, los, loe;
      if (coinSeg == list!.coinPtTStart.segment) {
        if (oppSeg != list.oppPtTStart.segment) {
          /// start segments match but opposing segments dont.
          continue;
        }
        lcs = list.coinPtTStart.fT;
        lce = list.coinPtTEnd.fT;
        los = list.oppPtTStart.fT;
        loe = list.oppPtTEnd.fT;
        if (los > loe) {
          double temp = los;
          los = loe;
          loe = temp;
        }
      } else if (coinSeg == list.oppPtTStart.segment) {
        if (oppSeg != list.coinPtTStart.segment) {
          continue;
        }
        lcs = list.oppPtTStart.fT;
        lce = list.oppPtTEnd.fT;
        if (lcs > lce) {
          double temp = lcs;
          lcs = lce;
          lce = temp;
        }
        los = list.coinPtTStart.fT;
        loe = list.coinPtTEnd.fT;
      } else {
        continue;
      }
      // [CoincidenceSpans] are on identical pair of segments.
      // assert no overlap on either side.
      assert(tce < lcs || lce < tcs);
      assert(toe < los || loe < tos);
    } while ((list = list.next) != null);
  }


  /// Sets up the coincidence links in the segments when the coincidence crosses
  /// multiple spans.
  bool mark(OpPhase phase) {
    globalState.phase = phase;
    CoincidentSpans? coin = fHead;
    if (coin == null) {
      return true;
    }
    do {
      OpSpanBase startBase = coin!.coinPtTStart.span;
      if (null == startBase.upCastable) {
        return false;
      }
      OpSpan start = startBase.upCast;
      if (start.deleted) {
        return false;
      }
      OpSpanBase end = coin.coinPtTEnd.span;
      assert(!end.deleted);
      OpSpanBase oStart = coin.oppPtTStart.span;
      assert(!oStart.deleted);
      OpSpanBase oEnd = coin.oppPtTEnd.span;
      if (oEnd.deleted) {
        return false;
      }
      bool flipped = coin.flipped();
      if (flipped) {
        OpSpanBase temp = oStart;
        oStart = oEnd;
        oEnd = temp;
      }
      // Coin and opp spans may not match up. Mark the ends, and then let
      // the interior get marked as many times as the spans allow.
      if (null == oStart.upCastable()) {
        return false;
      }
      start.insertCoincidence(oStart.upCast);
      end.insertCoinEnd(oEnd);
      OpSegment segment = start.segment;
      OpSegment oSegment = oStart.segment;
      OpSpanBase? next = start;
      OpSpanBase? oNext = oStart;
      int orderedResult = coin.ordered();
      if (orderedResult == CoincidentSpans.kOrderedFailed) {
        return false;
      }
      bool ordered = orderedResult == CoincidentSpans.kSuccessOrdered;
      while ((next = next!.upCast.next) != end) {
        if (null == next!.upCastable()) {
          return false;
        }
        if (null == next.upCast.insertCoincidenceSegment(oSegment, flipped, ordered)) {
          return false;
        }
      }
      while ((oNext = oNext!.upCast.next) != oEnd) {
        if (null == oNext!.upCastable()) {
          return false;
        }
        if (null == oNext.upCast.insertCoincidenceSegment(segment, flipped, ordered)) {
          return false;
        }
      }
    } while ((coin = coin.next) != null);
    return true;
  }

  // If there is an existing pair that overlaps the addition, extend it.
  bool extend(OpPtT coinPtTStart, OpPtT coinPtTEnd,
        OpPtT oppPtTStart, OpPtT oppPtTEnd) {
    CoincidentSpans? test = fHead;
    if (test == null) {
      return false;
    }
    OpSegment coinSeg = coinPtTStart.segment;
    OpSegment oppSeg = oppPtTStart.segment;
    if (!_ordered(coinPtTStart.segment, oppPtTStart.segment)) {
        OpSegment tempSeg = coinSeg;
        coinSeg = oppSeg;
        oppSeg = tempSeg;
        OpPtT temp = coinPtTStart;
        coinPtTStart = oppPtTStart;
        oppPtTStart = temp;
        temp = coinPtTEnd;
        coinPtTEnd = oppPtTEnd;
        oppPtTEnd = temp;
        if (coinPtTStart.fT > coinPtTEnd.fT) {
          temp = coinPtTStart;
          coinPtTStart = coinPtTEnd;
          coinPtTEnd = temp;
          temp = oppPtTStart;
          oppPtTStart = oppPtTEnd;
          oppPtTEnd = temp;
        }
    }
    double oppMinT = math.min(oppPtTStart.fT, oppPtTEnd.fT);
    double oppMaxT = 0;
    if (assertionsEnabled) {
      oppMaxT = math.max(oppPtTStart.fT, oppPtTEnd.fT);
    }
    do {
      if (coinSeg != test!.coinPtTStart.segment) {
        continue;
      }
      if (oppSeg != test.oppPtTStart.segment) {
        continue;
      }
      double oppTStart = test.oppPtTStart.fT;
      double oppTtEnd = test.oppPtTEnd.fT;
      double oTestMinT = math.min(oppTStart, oppTtEnd);
      double oTestMaxT = math.max(oppTStart, oppTtEnd);
      // if debug check triggers, caller failed to check if extended already exists
      assert(test.coinPtTStart.fT > coinPtTStart.fT
              || coinPtTEnd.fT > test.coinPtTEnd.fT
              || oTestMinT > oppMinT || oppMaxT > oTestMaxT);
      if ((test.coinPtTStart.fT <= coinPtTEnd.fT
              && coinPtTStart.fT <= test.coinPtTEnd.fT)
              || (oTestMinT <= oTestMaxT && oppMinT <= oTestMaxT)) {
          test.extend(coinPtTStart, coinPtTEnd, oppPtTStart, oppPtTEnd);
          return true;
      }
    } while ((test = test.next) != null);
    return false;
  }

  // walk span sets in parallel, moving winding from one to the other
  bool apply() {
    CoincidentSpans? coin = fHead;
    if (null == coin) {
      return true;
    }
    do {
      OpSpanBase startSpan = coin!.coinPtTStart.span;
      if (null == startSpan.upCastable()) {
        return false;
      }
      OpSpan start = startSpan.upCast;
      if (start.deleted) {
        continue;
      }
      OpSpanBase end = coin.coinPtTEnd.span;
      if (start != start.starter(end)) {
        return false;
      }
      bool flipped = coin.flipped();
      OpSpanBase oStartBase = (flipped ? coin.oppPtTEnd : coin.oppPtTStart).span;
      if (null == oStartBase.upCastable()) {
        return false;
      }
      OpSpan oStart = oStartBase.upCast;
      if (oStart.deleted) {
        continue;
      }
      OpSpanBase oEnd = (flipped ? coin.oppPtTStart : coin.oppPtTEnd).span;
      assert(oStart == oStart.starter(oEnd));
      OpSegment segment = start.segment;
      OpSegment oSegment = oStart.segment;
      bool operandSwap = segment.operand != oSegment.operand;
      if (flipped) {
        if (oEnd.deleted) {
          continue;
        }
        do {
          OpSpanBase? oNext = oStart.next;
          if (oNext == oEnd) {
            break;
          }
          if (null == oNext!.upCastable()) {
            return false;
          }
          oStart = oNext.upCast;
        } while (true);
      }
      do {
        int windValue = start.windValue();
        int oppValue = start.oppValue();
        int oWindValue = oStart.windValue();
        int oOppValue = oStart.oppValue();
        // winding values are added or subtracted depending on direction and wind type
        // same or opposite values are summed depending on the operand value
        int windDiff = operandSwap ? oOppValue : oWindValue;
        int oWindDiff = operandSwap ? oppValue : windValue;
        if (!flipped) {
            windDiff = -windDiff;
            oWindDiff = -oWindDiff;
        }
        bool addToStart = windValue != 0 && (windValue > windDiff || (windValue == windDiff
                && oWindValue <= oWindDiff));
        if (addToStart ? start.done : oStart.done) {
          addToStart ^= true;
        }
        if (addToStart) {
          if (operandSwap) {
            int temp = oWindValue;
            oWindValue = oOppValue;
            oOppValue = temp;
          }
          if (flipped) {
            windValue -= oWindValue;
            oppValue -= oOppValue;
          } else {
            windValue += oWindValue;
            oppValue += oOppValue;
          }
          if (segment.isXor) {
            windValue &= 1;
          }
          if (segment.oppXor) {
            oppValue &= 1;
          }
          oWindValue = oOppValue = 0;
        } else {
          if (operandSwap) {
            int temp = windValue;
            windValue = oppValue;
            oppValue = temp;
          }
          if (flipped) {
            oWindValue -= windValue;
            oOppValue -= oppValue;
          } else {
            oWindValue += windValue;
            oOppValue += oppValue;
          }
          if (oSegment.isXor) {
              oWindValue &= 1;
          }
          if (oSegment.oppXor) {
              oOppValue &= 1;
          }
          windValue = oppValue = 0;
        }
        if (windValue <= -1) {
          return false;
        }
        start.setWindValue(windValue);
        start.setOppValue(oppValue);
        if (oWindValue <= -1) {
          return false;
        }
        oStart.setWindValue(oWindValue);
        oStart.setOppValue(oOppValue);
        if (windValue !=0 && oppValue != 0) {
          segment.markDone(start);
        }
        if (oWindValue != 0 && oOppValue != 0) {
          oSegment.markDone(oStart);
        }
        OpSpanBase? next = start.next;
        OpSpanBase? oNext = flipped ? oStart.prev : oStart.next;
        if (next == end) {
          break;
        }
        if (null == next!.upCastable()) {
          return false;
        }
        start = next.upCast;
        // if the opposite ran out too soon, just reuse the last span
        if (null == oNext || null == oNext.upCastable()) {
          oNext = oStart;
        }
        oStart = oNext.upCast;
      } while (true);
    } while ((coin = coin.next) != null);
    return true;
  }

  bool findOverlaps(OpCoincidence overlaps) {
    overlaps.fHead = overlaps.fTop = null;
    CoincidentSpans? outer = fHead;
    while (outer != null) {
      OpSegment outerCoin = outer.coinPtTStart.segment;
      OpSegment outerOpp = outer.oppPtTStart.segment;
      CoincidentSpans? inner = outer;
      while ((inner = inner!.next) != null) {
        OpSegment innerCoin = inner!.coinPtTStart.segment;
        if (outerCoin == innerCoin) {
          continue;  // both winners are the same segment, so there's no additional overlap
        }
        OpSegment innerOpp = inner.oppPtTStart.segment;
        List<OpPtT?> overlapPoints = <OpPtT?>[null, null];
        if ((outerOpp == innerCoin && OpPtT.overlaps(outer.oppPtTStart,
            outer.oppPtTEnd, inner.coinPtTStart, inner.coinPtTEnd, overlapPoints))
            || (outerCoin == innerOpp && OpPtT.overlaps(outer.coinPtTStart,
                outer.coinPtTEnd, inner.oppPtTStart, inner.oppPtTEnd,
                overlapPoints))
            || (outerOpp == innerOpp && OpPtT.overlaps(outer.oppPtTStart,
                outer.oppPtTEnd, inner.oppPtTStart, inner.oppPtTEnd,
                overlapPoints))) {
          if (!overlaps.addOverlap(outerCoin, outerOpp, innerCoin, innerOpp,
                  overlapPoints[0]!, overlapPoints[1]!)) {
              return false;
          }
        }
      }
      outer = outer.next;
    }
    return true;
  }

  bool addOverlap(OpSegment seg1, OpSegment seg1o,
        OpSegment seg2, OpSegment seg2o,
        OpPtT overS, OpPtT overE) {
    OpPtT? s1 = overS.find(seg1);
    OpPtT? e1 = overE.find(seg1);
    if (null == s1 || null == e1) {
      return false;
    }
    if (s1.starter(e1).span.upCast.windValue != 0) {
      s1 = overS.find(seg1o);
      e1 = overE.find(seg1o);
      if (null == s1 || null == e1) {
        return false;
      }
      if (s1.starter(e1).span.upCast.windValue != 0) {
        return true;
      }
    }
    OpPtT? s2 = overS.find(seg2);
    OpPtT? e2 = overE.find(seg2);
    if (null == s2 || null == e2) {
      return false;
    }
    if (s2.starter(e2).span.upCast.windValue != 0) {
      s2 = overS.find(seg2o);
      e2 = overE.find(seg2o);
      if (null == s2 || null == e2) {
        return false;
      }
      if (s2.starter(e2).span.upCast.windValue != 0) {
        return true;
      }
    }
    if (s1.segment == s2.segment) {
      return true;
    }
    if (s1.fT > e1.fT) {
      OpPtT temp = s1;
      s1 = e1;
      e1 = temp;
      temp = s2;
      s2 = e2;
      e2 = temp;
    }
    add(s1, e1, s2, e2);
    return true;
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
    } while ((coin = coin.next) != null);
  }

  // sets the span's point to the ptT referenced by the previous-next or
  // next-previous.
  void _correctEnds() {
    OpPtT origPtT = _fCoinPtTStart!;
    OpSpanBase origSpan = origPtT.span;
    OpSpan? prevSpan = origSpan.prev;
    OpPtT? testPtT = prevSpan != null ? prevSpan.next!.ptT : origSpan.upCast.next!.prev!.ptT;
    setCoinPtTStart(testPtT!);
    origPtT = _fCoinPtTEnd!;
    origSpan = origPtT.span;
    prevSpan = origSpan.prev;
    testPtT = prevSpan != null ? prevSpan.next!.ptT : origSpan.upCast.next!.prev!.ptT;
    setCoinPtTEnd(testPtT);
    origPtT = _fOppPtTStart!;
    origSpan = origPtT.span;
    prevSpan = origSpan.prev;
    testPtT = prevSpan != null ? prevSpan.next!.ptT : origSpan.upCast.next!.prev!.ptT;
    setOppPtTStart(testPtT);
    origPtT = _fOppPtTEnd!;
    origSpan = origPtT.span;
    prevSpan = origSpan.prev;
    testPtT = prevSpan != null ? prevSpan.next!.ptT : origSpan.upCast.next!.prev!.ptT;
    setOppPtTEnd(testPtT);
  }

  /// Expand the range by checking adjacent spans for coincidence using
  bool expand() {
    bool expanded = false;
    OpSegment segment = coinPtTStart.segment;
    OpSegment oppSegment = oppPtTStart.segment;
    do {
      OpSpan start = coinPtTStart.span.upCast;
      OpSpan? prev = start.prev;
      OpPtT? oppPtT;
      if (prev == null || null == (oppPtT = prev.containsPointsOnSegment(oppSegment))) {
        break;
      }
      double midT = (prev.t + start.t) / 2;
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
      if (next == null || null == (oppPtT = next.containsPointsOnSegment(oppSegment))) {
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

  bool flipped() => _fOppPtTStart!.fT > _fOppPtTEnd!.fT;

  // Increase the range of this span.
  bool extend(OpPtT coinPtTStart, OpPtT coinPtTEnd,
      OpPtT oppPtTStart, OpPtT oppPtTEnd) {
    bool result = false;
    if (_fCoinPtTStart!.fT > coinPtTStart.fT || (flipped()
        ? _fOppPtTStart!.fT < oppPtTStart.fT : _fOppPtTStart!.fT > oppPtTStart.fT)) {
      setStarts(coinPtTStart, oppPtTStart);
      result = true;
    }
    if (_fCoinPtTEnd!.fT < coinPtTEnd.fT || (flipped()
        ? _fOppPtTEnd!.fT > oppPtTEnd.fT : _fOppPtTEnd!.fT < oppPtTEnd.fT)) {
      setEnds(coinPtTEnd, oppPtTEnd);
      result = true;
    }
    return result;
  }

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


  static const int kOrderedFailed = -1;
  static const int kSuccessNotOrdered = 0;
  static const int kSuccessOrdered = 1;

  // A coincident span is unordered if the pairs of points in the main and
  // opposite curves' t values do not ascend or descend. For instance, if a
  // tightly arced quadratic is coincident with another curve, it may intersect
  // it out of order.
  int ordered() {
    OpSpanBase start = coinPtTStart.span;
    OpSpanBase end = coinPtTEnd.span;
    OpSpanBase? next = start.upCast.next;
    if (next == end) {
      return kSuccessOrdered;
    }
    bool isFlipped = flipped();
    OpSegment oppSeg = oppPtTStart.segment;
    double oppLastT = oppPtTStart.fT;
    do {
      OpPtT? opp = next!.containsSegment(oppSeg);
      if (opp == null) {
        return kOrderedFailed;
      }
      if ((oppLastT > opp.fT) != isFlipped) {
        return kSuccessNotOrdered;
      }
      oppLastT = opp.fT;
      if (next == end) {
          break;
      }
      if (null == next.upCastable()) {
          return kSuccessNotOrdered;
      }
      next = next.upCast.next;
    } while (true);
    return kSuccessOrdered;
  }
}

/// Checks for overlap. overS < overE means it does overlap.
List<double> _coinOverlap(OpPtT coin1s, OpPtT coin1e, OpPtT coin2s, OpPtT coin2e) {
  assert(coin1s.segment == coin2s.segment);
  double overS = math.max(math.min(coin1s.fT, coin1e.fT), math.min(coin2s.fT, coin2e.fT));
  double overE = math.min(math.max(coin1s.fT, coin1e.fT), math.max(coin2s.fT, coin2e.fT));
  return [overS, overE];
}
