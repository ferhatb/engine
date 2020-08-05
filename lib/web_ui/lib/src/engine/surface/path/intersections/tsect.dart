// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10

part of engine;

class TSect {
  TCurve fCurve;
  int fActiveCount = 0;
  bool fHung = false;
  TSpan? fHead;
  // fCoincident
  // fDeleted
  TSect(this.fCurve) {
    resetRemoveEnds();
    //fHead.addOne();
    // fHead.init()
  }

  static void binarySearch(TSect sect1, TSect sect2, Intersections intersections) {
    // TODO
    assert(sect1.fOppSect == sect2);
    assert(sect2.fOppSect == sect1);
//    intersections.reset();
//    intersections.setMax(sect1.fCurve.maxIntersections + 4);  // Extra for slop
//    TSpan span1 = sect1.fHead!;
//    TSpan span2 = sect2.fHead!;
//    int oppSect, sect = sect1.intersects(span1, sect2, span2, &oppSect);
////    SkASSERT(between(0, sect, 2));
//    if (!sect) {
//        return;
//    }
//    if (sect == 2 && oppSect == 2) {
//        (void) EndsEqual(sect1, sect2, intersections);
//        return;
//    }
//    span1->addBounded(span2, &sect1->fHeap);
//    span2->addBounded(span1, &sect2->fHeap);
//    const int kMaxCoinLoopCount = 8;
//    int coinLoopCount = kMaxCoinLoopCount;
//    double start1s SK_INIT_TO_AVOID_WARNING;
//    double start1e SK_INIT_TO_AVOID_WARNING;
//    do {
//        // find the largest bounds
//        SkTSpan* largest1 = sect1->boundsMax();
//        if (!largest1) {
//            if (sect1->fHung) {
//                return;
//            }
//            break;
//        }
//        SkTSpan* largest2 = sect2->boundsMax();
//        // split it
//        if (!largest2 || (largest1 && (largest1->fBoundsMax > largest2->fBoundsMax
//                || (!largest1->fCollapsed && largest2->fCollapsed)))) {
//            if (sect2->fHung) {
//                return;
//            }
//            if (largest1->fCollapsed) {
//                break;
//            }
//            sect1->resetRemovedEnds();
//            sect2->resetRemovedEnds();
//            // trim parts that don't intersect the opposite
//            SkTSpan* half1 = sect1->addOne();
//            SkDEBUGCODE(half1->debugSetGlobalState(sect1->globalState()));
//            if (!half1->split(largest1, &sect1->fHeap)) {
//                break;
//            }
//            if (!sect1->trim(largest1, sect2)) {
//                SkOPOBJASSERT(intersections, 0);
//                return;
//            }
//            if (!sect1->trim(half1, sect2)) {
//                SkOPOBJASSERT(intersections, 0);
//                return;
//            }
//        } else {
//            if (largest2->fCollapsed) {
//                break;
//            }
//            sect1->resetRemovedEnds();
//            sect2->resetRemovedEnds();
//            // trim parts that don't intersect the opposite
//            SkTSpan* half2 = sect2->addOne();
//            SkDEBUGCODE(half2->debugSetGlobalState(sect2->globalState()));
//            if (!half2->split(largest2, &sect2->fHeap)) {
//                break;
//            }
//            if (!sect2->trim(largest2, sect1)) {
//                SkOPOBJASSERT(intersections, 0);
//                return;
//            }
//            if (!sect2->trim(half2, sect1)) {
//                SkOPOBJASSERT(intersections, 0);
//                return;
//            }
//        }
//        sect1->validate();
//        sect2->validate();
//#if DEBUG_T_SECT_LOOP_COUNT
//        intersections->debugBumpLoopCount(SkIntersections::kIterations_DebugLoop);
//#endif
//        // if there are 9 or more continuous spans on both sects, suspect coincidence
//        if (sect1->fActiveCount >= COINCIDENT_SPAN_COUNT
//                && sect2->fActiveCount >= COINCIDENT_SPAN_COUNT) {
//            if (coinLoopCount == kMaxCoinLoopCount) {
//                start1s = sect1->fHead->fStartT;
//                start1e = sect1->tail()->fEndT;
//            }
//            if (!sect1->coincidentCheck(sect2)) {
//                return;
//            }
//            sect1->validate();
//            sect2->validate();
//#if DEBUG_T_SECT_LOOP_COUNT
//            intersections->debugBumpLoopCount(SkIntersections::kCoinCheck_DebugLoop);
//#endif
//            if (!--coinLoopCount && sect1->fHead && sect2->fHead) {
//                /* All known working cases resolve in two tries. Sadly, cubicConicTests[0]
//                   gets stuck in a loop. It adds an extension to allow a coincident end
//                   perpendicular to track its intersection in the opposite curve. However,
//                   the bounding box of the extension does not intersect the original curve,
//                   so the extension is discarded, only to be added again the next time around. */
//                sect1->coincidentForce(sect2, start1s, start1e);
//                sect1->validate();
//                sect2->validate();
//            }
//        }
//        if (sect1->fActiveCount >= COINCIDENT_SPAN_COUNT
//                && sect2->fActiveCount >= COINCIDENT_SPAN_COUNT) {
//            if (!sect1->fHead) {
//                return;
//            }
//            sect1->computePerpendiculars(sect2, sect1->fHead, sect1->tail());
//            if (!sect2->fHead) {
//                return;
//            }
//            sect2->computePerpendiculars(sect1, sect2->fHead, sect2->tail());
//            if (!sect1->removeByPerpendicular(sect2)) {
//                return;
//            }
//            sect1->validate();
//            sect2->validate();
//#if DEBUG_T_SECT_LOOP_COUNT
//            intersections->debugBumpLoopCount(SkIntersections::kComputePerp_DebugLoop);
//#endif
//            if (sect1->collapsed() > sect1->fCurve.maxIntersections()) {
//                break;
//            }
//        }
//#if DEBUG_T_SECT_DUMP
//        sect1->dumpBoth(sect2);
//#endif
//        if (!sect1->fHead || !sect2->fHead) {
//            break;
//        }
//    } while (true);
//    SkTSpan* coincident = sect1->fCoincident;
//    if (coincident) {
//        // if there is more than one coincident span, check loosely to see if they should be joined
//        if (coincident->fNext) {
//            sect1->mergeCoincidence(sect2);
//            coincident = sect1->fCoincident;
//        }
//        SkASSERT(sect2->fCoincident);  // courtesy check : coincidence only looks at sect 1
//        do {
//            if (!coincident) {
//                return;
//            }
//            if (!coincident->fCoinStart.isMatch()) {
//                continue;
//            }
//            if (!coincident->fCoinEnd.isMatch()) {
//                continue;
//            }
//            double perpT = coincident->fCoinStart.perpT();
//            if (perpT < 0) {
//                return;
//            }
//            int index = intersections->insertCoincident(coincident->fStartT,
//                    perpT, coincident->pointFirst());
//            if ((intersections->insertCoincident(coincident->fEndT,
//                    coincident->fCoinEnd.perpT(),
//                    coincident->pointLast()) < 0) && index >= 0) {
//                intersections->clearCoincidence(index);
//            }
//        } while ((coincident = coincident->fNext));
//    }
//    int zeroOneSet = EndsEqual(sect1, sect2, intersections);
////    if (!sect1->fHead || !sect2->fHead) {
//        // if the final iteration contains an end (0 or 1),
//        if (sect1->fRemovedStartT && !(zeroOneSet & kZeroS1Set)) {
//            SkTCoincident perp;   // intersect perpendicular with opposite curve
//            perp.setPerp(sect1->fCurve, 0, sect1->fCurve[0], sect2->fCurve);
//            if (perp.isMatch()) {
//                intersections->insert(0, perp.perpT(), perp.perpPt());
//            }
//        }
//        if (sect1->fRemovedEndT && !(zeroOneSet & kOneS1Set)) {
//            SkTCoincident perp;
//            perp.setPerp(sect1->fCurve, 1, sect1->pointLast(), sect2->fCurve);
//            if (perp.isMatch()) {
//                intersections->insert(1, perp.perpT(), perp.perpPt());
//            }
//        }
//        if (sect2->fRemovedStartT && !(zeroOneSet & kZeroS2Set)) {
//            SkTCoincident perp;
//            perp.setPerp(sect2->fCurve, 0, sect2->fCurve[0], sect1->fCurve);
//            if (perp.isMatch()) {
//                intersections->insert(perp.perpT(), 0, perp.perpPt());
//            }
//        }
//        if (sect2->fRemovedEndT && !(zeroOneSet & kOneS2Set)) {
//            SkTCoincident perp;
//            perp.setPerp(sect2->fCurve, 1, sect2->pointLast(), sect1->fCurve);
//            if (perp.isMatch()) {
//                intersections->insert(perp.perpT(), 1, perp.perpPt());
//            }
//        }
////    }
//    if (!sect1->fHead || !sect2->fHead) {
//        return;
//    }
//    sect1->recoverCollapsed();
//    sect2->recoverCollapsed();
//    SkTSpan* result1 = sect1->fHead;
//    // check heads and tails for zero and ones and insert them if we haven't already done so
//    const SkTSpan* head1 = result1;
//    if (!(zeroOneSet & kZeroS1Set) && approximately_less_than_zero(head1->fStartT)) {
//        const SkDPoint& start1 = sect1->fCurve[0];
//        if (head1->isBounded()) {
//            double t = head1->closestBoundedT(start1);
//            if (sect2->fCurve.ptAtT(t).approximatelyEqual(start1)) {
//                intersections->insert(0, t, start1);
//            }
//        }
//    }
//    const SkTSpan* head2 = sect2->fHead;
//    if (!(zeroOneSet & kZeroS2Set) && approximately_less_than_zero(head2->fStartT)) {
//        const SkDPoint& start2 = sect2->fCurve[0];
//        if (head2->isBounded()) {
//            double t = head2->closestBoundedT(start2);
//            if (sect1->fCurve.ptAtT(t).approximatelyEqual(start2)) {
//                intersections->insert(t, 0, start2);
//            }
//        }
//    }
//    if (!(zeroOneSet & kOneS1Set)) {
//        const SkTSpan* tail1 = sect1->tail();
//        if (!tail1) {
//            return;
//        }
//        if (approximately_greater_than_one(tail1->fEndT)) {
//            const SkDPoint& end1 = sect1->pointLast();
//            if (tail1->isBounded()) {
//                double t = tail1->closestBoundedT(end1);
//                if (sect2->fCurve.ptAtT(t).approximatelyEqual(end1)) {
//                    intersections->insert(1, t, end1);
//                }
//            }
//        }
//    }
//    if (!(zeroOneSet & kOneS2Set)) {
//        const SkTSpan* tail2 = sect2->tail();
//        if (!tail2) {
//            return;
//        }
//        if (approximately_greater_than_one(tail2->fEndT)) {
//            const SkDPoint& end2 = sect2->pointLast();
//            if (tail2->isBounded()) {
//                double t = tail2->closestBoundedT(end2);
//                if (sect1->fCurve.ptAtT(t).approximatelyEqual(end2)) {
//                    intersections->insert(t, 1, end2);
//                }
//            }
//        }
//    }
//    SkClosestSect closest;
//    do {
//        while (result1 && result1->fCoinStart.isMatch() && result1->fCoinEnd.isMatch()) {
//            result1 = result1->fNext;
//        }
//        if (!result1) {
//            break;
//        }
//        SkTSpan* result2 = sect2->fHead;
//        bool found = false;
//        while (result2) {
//            found |= closest.find(result1, result2  SkDEBUGPARAMS(intersections));
//            result2 = result2->fNext;
//        }
//    } while ((result1 = result1->fNext));
//    closest.finish(intersections);
//    // if there is more than one intersection and it isn't already coincident, check
//    int last = intersections->used() - 1;
//    for (int index = 0; index < last; ) {
//        if (intersections->isCoincident(index) && intersections->isCoincident(index + 1)) {
//            ++index;
//            continue;
//        }
//        double midT = ((*intersections)[0][index] + (*intersections)[0][index + 1]) / 2;
//        SkDPoint midPt = sect1->fCurve.ptAtT(midT);
//        // intersect perpendicular with opposite curve
//        SkTCoincident perp;
//        perp.setPerp(sect1->fCurve, midT, midPt, sect2->fCurve);
//        if (!perp.isMatch()) {
//            ++index;
//            continue;
//        }
//        if (intersections->isCoincident(index)) {
//            intersections->removeOne(index);
//            --last;
//        } else if (intersections->isCoincident(index + 1)) {
//            intersections->removeOne(index + 1);
//            --last;
//        } else {
//            intersections->setCoincident(index++);
//        }
//        intersections->setCoincident(index);
//    }
//    SkOPOBJASSERT(intersections, intersections->used() <= sect1->fCurve.maxIntersections());
  }
}
