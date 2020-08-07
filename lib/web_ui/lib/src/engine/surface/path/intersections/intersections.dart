// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Compute intersection of 2 contours.
///
/// [_IntersectionHelper] on both contours loops through segments and performs
/// segment to segment intersection that inserts point and t values into
/// [Intersections].
///
/// For intersections other than with lines, quad/conic/cubic curves are
/// converted to [TCurve] and use [TSect] to compute intersections.
///
///
bool addIntersectTs(OpContour test, OpContour next, OpCoincidence coincidence) {
  if (test != next) {
    if (almostLessUlps(test.bounds.bottom, next.bounds.top)) {
      return false;
    }
    if (!_boundsIntersects(test.bounds, next.bounds)) {
      return true;
    }
  }
  final _IntersectionHelper wt = _IntersectionHelper(test);
  final OpSegment wtSegment = wt.segment!;
  final ui.Rect wtBounds = wt.bounds;
  do {
    final _IntersectionHelper wn = _IntersectionHelper(next);
    final OpSegment wnSegment = wn.segment!;
    final ui.Rect wnBounds = wn.bounds;
    if (test == next && !wn.startAfter(wt)) {
      continue;
    }
    do {
      if (!_boundsIntersects(wt.bounds, wn.bounds)) {
        continue;
      }
      int pts = 0;
      final Intersections ts = Intersections();
      bool swap = false;
      Quad? quad1, quad2;
      Conic? conic1, conic2;
      Cubic? cubic1, cubic2;
      switch (wt.segmentType) {
        case _SegmentType.kHorizontalLineSegment:
          swap = true;
          switch (wn.segmentType) {
            case _SegmentType.kHorizontalLineSegment:
            case _SegmentType.kVerticalLineSegment:
            case _SegmentType.kLineSegment:
              pts = ts.lineHorizontal(wnSegment.points, wtBounds.left,
                  wtBounds.right, wtBounds.top, wt.xFlipped);
              break;
            case _SegmentType.kQuadSegment:
              pts = ts.quadHorizontal(wnSegment.points, wtBounds.left,
                  wtBounds.right, wtBounds.top, wt.xFlipped);
              break;
            case _SegmentType.kConicSegment:
              pts = ts.conicHorizontal(wnSegment.points, wnSegment.weight, wtBounds.left,
                  wtBounds.right, wtBounds.top, wt.xFlipped);
              break;
            case _SegmentType.kCubicSegment:
              pts = ts.cubicHorizontal(wnSegment.points, wtBounds.left,
                  wtBounds.right, wtBounds.top, wt.xFlipped);
              break;
            default:
              assert(false);
          }
          break;
        case _SegmentType.kVerticalLineSegment:
          swap = true;
          switch (wn.segmentType) {
            case _SegmentType.kHorizontalLineSegment:
            case _SegmentType.kVerticalLineSegment:
            case _SegmentType.kLineSegment: {
              pts = ts.lineVertical(wnSegment.points, wtBounds.top,
                  wtBounds.bottom, wtBounds.left, wt.yFlipped);
              break;
            }
            case _SegmentType.kQuadSegment: {
              pts = ts.quadVertical(wnSegment.points, wtBounds.top,
                  wtBounds.bottom, wtBounds.left, wt.yFlipped);
              break;
            }
            case _SegmentType.kConicSegment: {
              pts = ts.conicVertical(wnSegment.points, wnSegment.weight,
                  wtBounds.top, wtBounds.bottom, wtBounds.left, wt.yFlipped);
              break;
            }
            case _SegmentType.kCubicSegment: {
              pts = ts.cubicVertical(wnSegment.points, wtBounds.top,
                  wtBounds.bottom, wtBounds.left, wt.yFlipped);
              break;
            }
            default:
              assert(false);
          }
          break;
        case _SegmentType.kLineSegment:
          switch (wn.segmentType) {
            case _SegmentType.kHorizontalLineSegment:
              pts = ts.lineHorizontal(wtSegment.points, wnBounds.left,
                  wnBounds.right, wnBounds.top, wn.xFlipped);
              break;
            case _SegmentType.kVerticalLineSegment:
              pts = ts.lineVertical(wtSegment.points, wnBounds.top,
                  wnBounds.bottom, wnBounds.left, wn.yFlipped);
              break;
            case _SegmentType.kLineSegment:
              pts = ts.lineLine(wtSegment.points, wnSegment.points);
              break;
            case _SegmentType.kQuadSegment:
              swap = true;
              pts = ts.quadLine(wnSegment.points, wtSegment.points);
              break;
            case _SegmentType.kConicSegment:
              swap = true;
              pts = ts.conicLine(wnSegment.points, wnSegment.weight,
                  wtSegment.points);
              break;
            case _SegmentType.kCubicSegment:
              swap = true;
              pts = ts.cubicLine(wnSegment.points, wtSegment.points);
              break;
            default:
              assert(false);
          }
          break;
        case _SegmentType.kQuadSegment:
          switch (wn.segmentType) {
            case _SegmentType.kHorizontalLineSegment:
              pts = ts.quadHorizontal(wtSegment.points, wnBounds.left,
                  wnBounds.right, wnBounds.top, wn.xFlipped);
              break;
            case _SegmentType.kVerticalLineSegment:
              pts = ts.quadVertical(wtSegment.points, wnBounds.top,
                  wnBounds.bottom, wnBounds.left, wn.yFlipped);
              break;
            case _SegmentType.kLineSegment:
              pts = ts.quadLine(wtSegment.points, wnSegment.points);
              break;
            case _SegmentType.kQuadSegment: {
              quad1 = Quad(wtSegment.points);
              quad2 = Quad(wnSegment.points);
              pts = ts.intersectQuad(quad1!, quad2!);
              break;
            }
            case _SegmentType.kConicSegment: {
              swap = true;
              conic2 = Conic.fromPoints(wnSegment.points, wnSegment.weight);
              quad1 = Quad(wtSegment.points);
              pts = ts.intersectConicQuad(conic2!, quad1!);
              break;
            }
            case _SegmentType.kCubicSegment: {
              swap = true;
              cubic2 = Cubic.fromPoints(wnSegment.points);
              quad1 = Quad(wtSegment.points);
              pts = ts.intersectCubicQuad(cubic2!, quad1!);
              break;
            }
            default:
              assert(false);
          }
          break;
        case _SegmentType.kConicSegment:
          switch (wn.segmentType) {
            case _SegmentType.kHorizontalLineSegment:
              pts = ts.conicHorizontal(wtSegment.points, wtSegment.weight, wnBounds.left,
                      wnBounds.right, wnBounds.top, wn.xFlipped);
              break;
            case _SegmentType.kVerticalLineSegment:
              pts = ts.conicVertical(wtSegment.points, wtSegment.weight, wnBounds.top,
                      wnBounds.bottom, wnBounds.left, wn.yFlipped);
              break;
            case _SegmentType.kLineSegment:
              pts = ts.conicLine(wtSegment.points, wtSegment.weight, wnSegment.points);
              break;
            case _SegmentType.kQuadSegment:
              conic1 = Conic.fromPoints(wtSegment.points, wtSegment.weight);
              quad2 = Quad(wnSegment.points);
              pts = ts.intersectConicQuad(conic1!, quad2!);
              break;
            case _SegmentType.kConicSegment:
              conic1 = Conic.fromPoints(wtSegment.points, wtSegment.weight);
              conic2 = Conic.fromPoints(wnSegment.points, wnSegment.weight);
              pts = ts.intersectConic(conic1!, conic2!);
              break;
            case _SegmentType.kCubicSegment:
              swap = true;
              cubic2 = Cubic.fromPoints(wnSegment.points);
              conic1 = Conic.fromPoints(wtSegment.points, wtSegment.weight);
              pts = ts.intersectCubicConic(cubic2!, conic1!);
              break;
          }
          break;
        case _SegmentType.kCubicSegment:
          switch (wn.segmentType) {
            case _SegmentType.kHorizontalLineSegment:
              pts = ts.cubicHorizontal(wtSegment.points, wnBounds.left,
                      wnBounds.right, wnBounds.top, wn.xFlipped);
              break;
            case _SegmentType.kVerticalLineSegment:
              pts = ts.cubicVertical(wtSegment.points, wnBounds.top,
                      wnBounds.bottom, wnBounds.left, wn.yFlipped);
              break;
            case _SegmentType.kLineSegment:
              pts = ts.cubicLine(wtSegment.points, wnSegment.points);
              break;
            case _SegmentType.kQuadSegment:
              cubic1 = Cubic.fromPoints(wtSegment.points);
              quad2 = Quad(wnSegment.points);
              pts = ts.intersectCubicQuad(cubic1!, quad2!);
              break;
            case _SegmentType.kConicSegment:
              cubic1 = Cubic.fromPoints(wtSegment.points);
              conic2 = Conic.fromPoints(wnSegment.points, wnSegment.weight);
              pts = ts.intersectCubicConic(cubic1!, conic2!);
              break;
            case _SegmentType.kCubicSegment:
              cubic1 = Cubic.fromPoints(wtSegment.points);
              cubic2 = Cubic.fromPoints(wnSegment.points);
              pts = ts.intersectCubic(cubic1!, cubic2!);
              break;
            default:
              assert(false);
          }
          break;
        default:
          assert(false);
      }
      int coinIndex = -1;
      List<OpPtT?> coinPtT = <OpPtT?>[null, null];
      for (int pt = 0; pt < pts; ++pt) {
        assert(ts.fT0[pt] >= 0 && ts.fT0[pt] <= 1);
        assert(ts.fT1[pt] >= 0 && ts.fT1[pt] <= 1);
        // if t value is used to compute pt in addT, error may creep in and
        // rect intersections may result in non-rects. if pt value from
        // intersection is passed in, current tests break. As a workaround,
        // pass in pt value from intersection only if pt.x and pt.y is integral.
        double iPtX = ts.ptX[pt];
        double iPtY = ts.ptY[pt];
        bool iPtIsIntegral = iPtX == iPtX.floor() && iPtY == iPtY.floor();
        OpPtT testTAt = iPtIsIntegral ? wt.segment!.addTAtPoint(
            swap == 0 ? ts.fT0[pt] : ts.fT1[pt], iPtX, iPtY)
              : wt.segment!.addT(swap == 0 ? ts.fT0[pt] : ts.fT1[pt]);
        wn.segment!.debugValidate();
        OpPtT nextTAt = iPtIsIntegral ? wn.segment!.addTAtPoint(
            swap == 1 ? ts.fT0[pt] : ts.fT1[pt], iPtX, iPtY)
              : wn.segment!.addT(swap == 1 ? ts.fT0[pt] : ts.fT1[pt]);
        /// Skip adding/merging nextTAt in case an existing testTAt was found
        /// and it is already in testTAt loop.
        if (!testTAt.contains(nextTAt)) {
          // oppPrev is null if pair.
          OpPtT? oppPrev = testTAt.oppPrev(nextTAt);
          if (oppPrev != null) {
            // testTAt and nextTAt already share a pt-t loop.
            testTAt.span.mergeMatches(nextTAt.span);
            // Insert new pt-t into link list.
            testTAt.addOpp(nextTAt, oppPrev);
          }
          if (testTAt.fPt != nextTAt.fPt) {
            /// Mark spans unaligned if they are at different points.
            testTAt.span.unaligned();
            nextTAt.span.unaligned();
          }
          wt.segment!.debugValidate();
          wn.segment!.debugValidate();
        }
        if (!ts.isCoincident(pt)) {
          continue;
        }
        if (coinIndex < 0) {
          coinPtT[0] = testTAt;
          coinPtT[1] = nextTAt;
          coinIndex = pt;
          continue;
        }
        if (coinPtT[0]!.span == testTAt.span) {
          coinIndex = -1;
          continue;
        }
        if (coinPtT[1]!.span == nextTAt.span) {
          coinIndex = -1;  // coincidence span collapsed
          continue;
        }
        if (swap) {
            OpPtT? temp = coinPtT[0];
            coinPtT[0] = coinPtT[1];
            coinPtT[1] = temp;
            temp = nextTAt;
            nextTAt = testTAt;
            testTAt = temp;
        }
        assert(coinPtT[0]!.span.t < testTAt.span.t);
        if (coinPtT[0]!.span.deleted) {
          coinIndex = -1;
          continue;
        }
        if (testTAt.span.deleted) {
          coinIndex = -1;
          continue;
        }
        coincidence.add(coinPtT[0]!, testTAt, coinPtT[1]!, nextTAt);
        coinIndex = -1;
      }
      assert(coinIndex < 0);  // expect coincidence to be paired
    } while (wn.advance());
  } while (wt.advance());
  return true;
}

class _SegmentType {
  static const int kHorizontalLineSegment = -1;
  static const int kVerticalLineSegment = 0;
  static const int kLineSegment = SPathVerb.kLine;
  static const int kQuadSegment = SPathVerb.kQuad;
  static const int kConicSegment = SPathVerb.kConic;
  static const int kCubicSegment = SPathVerb.kCubic;
}

class _IntersectionHelper {
  _IntersectionHelper(this.contour);
  final OpContour contour;
  OpSegment? _segment;

  OpSegment? get segment => _segment;

  bool startAfter(_IntersectionHelper after) {
    _segment = after.segment?.next;
    return _segment != null;
  }

  /// Moves to next segment.
  bool advance() {
    _segment = _segment?.next;
    return _segment != null;
  }

  int get segmentType {
    OpSegment seg = _segment!;
    int type = seg.verb;
    if (type != _SegmentType.kLineSegment) {
      return type;
    }
    if (seg.isHorizontal) {
      return _SegmentType.kHorizontalLineSegment;
    }
    if (seg.isVertical) {
      return _SegmentType.kVerticalLineSegment;
    }
    return _SegmentType.kLineSegment;
  }

  bool get xFlipped => bounds.left != _segment!.points[0];

  bool get yFlipped => bounds.top != _segment!.points[1];

  /// Bounds of current segment.
  ui.Rect get bounds => _segment!.bounds;
}

class Intersections {
  int fIsCoincident0 = 0; // bit set for first curve's coincident T
  int fIsCoincident1 = 0; // bit set for second curve's coincident T
  static const int kMaxPoints = 13;
  final Float64List fT0 = Float64List(kMaxPoints);
  final Float64List fT1 = Float64List(kMaxPoints);
  final Float64List ptX = Float64List(kMaxPoints);
  final Float64List ptY = Float64List(kMaxPoints);
  // Near point flag.
  List<bool> fNearlySame = [false, false];
  // Alternative near point.
  final Float64List pt2x = Float64List(2);
  final Float64List pt2y = Float64List(2);
  int fUsed = 0;
  int fSwap = 0;
  int _fMax = 0;
  bool fAllowNear = true;

  Intersections() {
    reset();
  }

  void reset() {
    fAllowNear = true;
    fUsed = 0;
    fIsCoincident0 = fIsCoincident1 = 0;
  }

  void setMax(int max) {
    assert(max <= kMaxPoints);
    _fMax = max;
  }

  /// Insert t values of both curves at point [px],[py] into sorted list of
  /// T values.
  ///
  /// If t values are roughly equal to existing entries, replace with new
  /// point.
  int insert(double one, double two, double px, double py) {
    if (fIsCoincident0 == 3 && SPath.between(fT0[0], one, fT0[1])) {
      // Don't allow a mix of coincident and non-coincident intersections.
      return -1;
    }
    assert(fUsed <= 1 || fT0[0] <= fT0[1], 'T values should be sorted');
    int index = 0;
    for (; index < fUsed; ++index) {
      double oldOne = fT0[index];
      double oldTwo = fT1[index];
      if (one == oldOne && two == oldTwo) {
        return -1;
      }
      if (moreRoughlyEqual(oldOne, one) && moreRoughlyEqual(oldTwo, two)) {
        // If prior T was 0 or 1, ensure that new T is not 0 or 1 for both
        // curves, otherwise skip since one,two is already in list of T's.
        if ((!preciselyZero(one) || preciselyZero(oldOne))
            && (!preciselyEqual(one, 1) || preciselyEqual(oldOne, 1))
            && (!preciselyZero(two) || preciselyZero(oldTwo))
            && (!preciselyEqual(two, 1) || preciselyEqual(oldTwo, 1))) {
          return -1;
        }
        assert(one >= 0 && one <= 1);
        assert(two >= 0 && two <= 1);
        // Remove this and re-insert below in case replacing would make list
        // unsorted.
        int remaining = fUsed - index - 1;
        for (int rmIndex = index; rmIndex < (index + remaining); rmIndex++) {
          ptX[index] = ptX[index + 1];
          ptY[index] = ptY[index + 1];
          fT0[index] = fT0[index + 1];
          fT1[index] = fT1[index + 1];
        }
        int clearMask = ~((1 << index) - 1);
        fIsCoincident0 -= (fIsCoincident0 >> 1) & clearMask;
        fIsCoincident1 -= (fIsCoincident1 >> 1) & clearMask;
        --fUsed;
        break;
      }
    }
    /// Find insertion point with t > one.
    for (index = 0; index < fUsed; ++index) {
      if (fT0[index] > one) {
        break;
      }
    }
    if (fUsed >= _fMax) {
      assert(false);
      fUsed = 0;
      return 0;
    }
    int remaining = fUsed - index;
    if (remaining > 0) {
      for (int moveIndex = index + remaining - 1; moveIndex >= index; --moveIndex) {
        ptX[moveIndex + 1] = ptX[moveIndex];
        ptY[moveIndex + 1] = ptY[moveIndex];
        fT0[moveIndex + 1] = fT0[moveIndex];
        fT1[moveIndex + 1] = fT1[moveIndex];
      }
      ptX[index] = px;
      ptY[index] = py;
      fT0[index] = one;
      fT1[index] = two;
      int clearMask = ~((1 << index) - 1);
      fIsCoincident0 += fIsCoincident0 & clearMask;
      fIsCoincident1 += fIsCoincident1 & clearMask;
    } else {
      ptX[index] = px;
      ptY[index] = py;
    }
    if (one < 0 || one > 1) {
        return -1;
    }
    if (two < 0 || two > 1) {
        return -1;
    }
    fT0[index] = one;
    fT1[index] = two;
    ++fUsed;
    assert(fUsed <= kMaxPoints);
    return index;
  }

  int insertAtOffset(double one, double two, ui.Offset offset) =>
    insert(one, two, offset.dx, offset.dy);

  // Insert with an alternate intersection point when they are very close.
  void insertNear(double one, double two, double x0, double y0, double x1, double y1) {
    assert(one == 0 || one == 1);
    assert(two == 0 || two == 1);
    assert(x0 != x1 || y0 != y1);
    fNearlySame[one != 0 ? 1 : 0] = true;
    insert(one, two, x0, y0);
    pt2x[one != 0 ? 1 : 0] = x1;
    pt2y[one != 0 ? 1 : 0] = y1;
  }

  /// Create intersection by merging intersections [a] with
  /// intersections [b] as alternate point.
  void merge(Intersections a, int aIndex, Intersections b, int bIndex) {
    reset();
    fT0[0] = a.fT0[aIndex];
    fT1[0] = b.fT0[bIndex];
    ptX[0] = a.ptX[aIndex];
    ptY[0] = a.ptY[aIndex];
    pt2x[0] = b.ptX[bIndex];
    pt2y[0] = b.ptY[bIndex];
    fUsed = 1;
  }

  int lineHorizontal(Float32List points, double left, double right, double y,
      bool flipped) {
    final DLine line = DLine.fromPoints(points);
    _fMax = 2;
    return horizontal(line, left, right, y, flipped);
  }

  /// Intersect horizontal line with a line.
  int horizontal(DLine line, double left, double right, double y,
      bool flipped) {
    // Clean up parallel at the end will limit the result to 2 at the most.
    _fMax = 3;
    // See if end points intersect the opposite line.
    double t;
    if ((t = line.exactPoint(left, y)) >= 0) {
      insert(t, flipped ? 1 : 0, left, y);
    }
    if (left != right) {
      if ((t = line.exactPoint(right, y)) >= 0) {
        insert(t, flipped ? 0 : 1, right, y);
      }
      double lx = line.x0;
      double ly = line.y0;
      if ((t = DLine.exactPointH(lx, ly, left, right, y)) >= 0) {
        insert(0, flipped ? 1 - t : t, lx, ly);
      }
      lx = line.x1;
      ly = line.y1;
      if ((t = DLine.exactPointH(lx, ly, left, right, y)) >= 0) {
        insert(1, flipped ? 1 - t : t, lx, ly);
      }
    }
    int result = _horizontalCoincident(line, y);
    if (result == 1 && fUsed == 0) {
      fT0[0] = _horizontalIntercept(line, y);
      double xIntercept = line.x0 + fT0[0] * (line.x1 - line.x0);
      if (SPath.between(left, xIntercept, right)) {
        fT1[0] = (xIntercept - left) / (right - left);
        if (flipped) {
          // Invert t values.
          for (int index = 0; index < result; ++index) {
            fT1[index] = 1 - fT1[index];
          }
        }
        ptX[0] = xIntercept;
        ptY[0] = y;
        fUsed = 1;
      }
    } else if (fAllowNear || result == 2) {
      if ((t = line.nearPoint(left, y)) >= 0) {
        insert(t, flipped ? 1 : 0, left, y);
      }
      if (left != right) {
        if ((t = line.nearPoint(right, y)) >= 0) {
          insert(t, flipped ? 0 : 1, right, y);
        }
        double lx = line.x0;
        double ly = line.y0;
        if ((t = DLine.nearPointH(lx, ly, left, right, y)) >= 0) {
          insert(0, flipped ? 1 - t : t, lx, ly);
        }
        lx = line.x1;
        ly = line.y1;
        if ((t = DLine.nearPointH(lx, ly, left, right, y)) >= 0) {
          insert(1, flipped ? 1 - t : t, lx, ly);
        }
      }
    }
    cleanUpParallelLines(result == 2);
    return fUsed;
  }

  static int verticalCoincident(DLine line, double x) {
    double min = math.min(line.x0, line.x1);
    double max = math.max(line.x0, line.x1);
    if (!preciselyBetween(min, x, max)) {
      return 0;
    }
    return (almostEqualUlps(min, max)) ? 2 : 1;
  }

  double verticalIntercept(DLine line, double x) {
    assert(line.x1 != line.x0);
    return pinT((x - line.x0) / (line.x1 - line.x0));
  }

  int lineVertical(Float32List points, double top, double bottom, double x,
      bool flipped) {
    DLine line = DLine.fromPoints(points);
    _fMax = 2;
    return vertical(line, top, bottom, x, flipped);
  }

  int vertical(DLine line, double top, double bottom, double x, bool flipped) {
    // Parallel cleanup will reduce to at most 2.
    _fMax = 3;
    // See if end points intersect the opposite line
    double t;
    if ((t = line.exactPoint(x, top)) >= 0) {
      insert(t, flipped ? 1 : 0, x, top);
    }
    if (top != bottom) {
      if ((t = line.exactPoint(x, bottom)) >= 0) {
        insert(t, flipped ? 0 : 1, x, bottom);
      }
      if ((t = DLine.exactPointV(line.x0, line.y0, top, bottom, x)) >= 0) {
        insert(0, flipped ? 1 - t : t, line.x0, line.y0);
      }
      if ((t = DLine.exactPointV(line.x1, line.y1, top, bottom, x)) >= 0) {
        insert(1, flipped ? 1 - t : t, line.x1, line.y1);
      }
    }
    int result = verticalCoincident(line, x);
    if (result == 1 && fUsed == 0) {
      fT0[0] = verticalIntercept(line, x);
      double yIntercept = line.y0 + fT0[0] * (line.y1 - line.y0);
      if (SPath.between(top, yIntercept, bottom)) {
        fT1[0] = (yIntercept - top) / (bottom - top);
        if (flipped) {
            // OPTIMIZATION: instead of swapping, pass original line, use [1].fY - [0].fY
            for (int index = 0; index < result; ++index) {
              fT1[index] = 1 - fT1[index];
            }
        }
        ptX[0] = x;
        ptY[0] = yIntercept;
        fUsed = 1;
      }
    }
    if (fAllowNear || result == 2) {
      if ((t = line.nearPoint(x, top)) >= 0) {
        insert(t, flipped ? 1 : 0, x, top);
      }
      if (top != bottom) {
        if ((t = line.nearPoint(x, bottom)) >= 0) {
          insert(t, flipped ? 0 : 1, x, bottom);
        }
        if ((t = DLine.nearPointV(line.x0, line. y0, top, bottom, x)) >= 0) {
          insert(0, flipped ? 1 - t : t, line.x0, line. y0);
        }
        if ((t = DLine.nearPointV(line.x1, line.y1, top, bottom, x)) >= 0) {
          insert(1, flipped ? 1 - t : t, line.x1, line. y1);
        }
      }
    }
    cleanUpParallelLines(result == 2);
    assert(fUsed <= 2);
    return fUsed;
  }

  // Intersection for lines that are both non horizontal/vertical.
  int intersectLines(DLine a, DLine b) {
    // Parallel cleanup will ensure this is no more than 2 at the end.
    _fMax = 3;
    // See if end points intersect the opposite line.
    double t;
    if ((t = b.exactPoint(a.x0, a.y0)) >= 0) {
      insert(0, t, a.x0, a.y0);
    }
    if ((t = b.exactPoint(a.x1, a.y1)) >= 0) {
      insert(1, t, a.x1, a.y1);
    }
    if ((t = a.exactPoint(b.x0, b.y0)) >= 0) {
      insert(t, 0, b.x0, b.y0);
    }
    if ((t = a.exactPoint(b.x1, b.y1)) >= 0) {
      insert(t, 1, b.x1, b.y1);
    }
    // Determine the intersection point of two line segments.
    // Return false if the lines don't intersect.
    double axLen = a.x1 - a.x0;
    double ayLen = a.y1 - a.y0;
    double bxLen = b.x1 - b.x0;
    double byLen = b.y1 - b.y0;
    // Slopes match when denominator goes to zero:
    //                   axLen / ayLen ==                   bxLen / byLen
    // (ayLen * byLen) * axLen / ayLen == (ayLen * byLen) * bxLen / byLen
    //          byLen  * axLen         ==  ayLen          * bxLen
    //          byLen  * axLen         -   ayLen          * bxLen == 0 ( == denom )
    //
    double axByLen = axLen * byLen;
    double ayBxLen = ayLen * bxLen;
    // Detect parallel lines the same way here and in SkOpAngle operator <
    // so that non-parallel means they are also sortable.
    bool notParallel = fAllowNear ? notAlmostEqualUlpsPin(axByLen, ayBxLen)
            : notAlmostDequalUlps(axByLen, ayBxLen);
    if (notParallel && fUsed == 0) {
        double ab0y = a.y0 - b.y0;
        double ab0x = a.x0 - b.x0;
        double numerA = ab0y * bxLen - byLen * ab0x;
        double numerB = ab0y * axLen - ayLen * ab0x;
        double denom = axByLen - ayBxLen;
        if (SPath.between(0, numerA, denom) && SPath.between(0, numerB, denom)) {
          fT0[0] = numerA / denom;
          fT1[0] = numerB / denom;
          computePoints(a, 1);
        }
    }
    // Allow tracking that both sets of end points are near each other --
    // the lines are entirely coincident -- even when the end points are not
    // exactly the same.
    // Mark this as a 'wild card' for the end points, so that either point is
    // considered totally coincident. Then, avoid folding the lines over each
    // other, but allow either end to mate to the next set of lines.
    if (fAllowNear || !notParallel) {
        List<double> aNearB = [0, 0];
        List<double> bNearA = [0, 0];
        List<bool> aNotB = [false, false];
        List<bool> bNotA = [false, false];
        int nearCount = 0;
        aNearB[0] = t = b.nearPoint(a.x0, a.y0);
        aNotB[0] = b.unequal;
        nearCount += t >= 0 ? 1 : 0;
        bNearA[0] = t = a.nearPoint(b.x0, b.y0);
        bNotA[0] = a.unequal;
        nearCount += t >= 0 ? 1: 0;
        aNearB[1] = t = b.nearPoint(a.x1, a.y1);
        aNotB[1] = b.unequal;
        nearCount += t >= 0 ? 1 : 0;
        bNearA[1] = t = a.nearPoint(b.x1, b.y1);
        bNotA[1] = a.unequal;
        nearCount += t >= 0 ? 1: 0;
        if (nearCount > 0) {
          // Skip if each segment contributes to one end point.
          if (nearCount != 2 || aNotB[0] == aNotB[1]) {
            for (int iA = 0; iA < 2; ++iA) {
              if (!aNotB[iA]) {
                  continue;
              }
              int nearer = aNearB[iA] > 0.5 ? 1 : 0;
              if (!bNotA[nearer]) {
                continue;
              }
              insertNear(iA.toDouble(), nearer.toDouble(),
                  iA == 0 ? a.x0 : a.x1, iA == 0 ? a.y0 : a.y1,
                  nearer == 0 ? b.x0 : b.x1, nearer == 0 ? b.y0 : b.y1);
                aNearB[iA] = -1;
                bNearA[nearer] = -1;
                nearCount -= 2;
            }
          }
          if (nearCount > 0) {
            if (aNearB[0] >= 0) {
              insert(0, aNearB[0], a.x0, a.y0);
            }
            if (aNearB[1] >= 0) {
              insert(1, aNearB[1], a.x1, a.y1);
            }
            if (bNearA[0] >= 0) {
              insert(bNearA[0], 0, b.x0, b.y0);
            }
            if (bNearA[1] >= 0) {
              insert(bNearA[1], 1, b.x1, b.y1);
            }
          }
        }
    }
    cleanUpParallelLines(!notParallel);
    assert(fUsed <= 2);
    return fUsed;
  }

  int lineLine(Float32List a, Float32List b) {
    _fMax = 2;
    return intersectLines(DLine.fromPoints(a), DLine.fromPoints(b));
  }

  /// Remove points due to parallel lines overlapping each other.
  void cleanUpParallelLines(bool parallel) {
    // Remove all points between first and last.
    while (fUsed > 2) {
      removeOne(1);
    }
    if (fUsed == 2 && !parallel) {
      bool startMatch = fT0[0] == 0 || zeroOrOne(fT1[0]);
      bool endMatch = fT0[1] == 1 || zeroOrOne(fT1[1]);
      if ((!startMatch && !endMatch) || approximatelyEqualT(fT0[0], fT0[1])) {
        assert(startMatch || endMatch);
        if (startMatch && endMatch && (fT0[0] != 0 || !zeroOrOne(fT1[0]))
            && fT0[1] == 1 && zeroOrOne(fT1[1])) {
          removeOne(0);
        } else {
          removeOne(endMatch ? 1 : 0);
        }
      }
    }
    if (fUsed == 2) {
      fIsCoincident0 = fIsCoincident1 = 0x03;
    }
  }

  /// Remove point at index and adjust coincidence bit masks.
  void removeOne(int index) {
    int remaining = --fUsed - index;
    if (remaining <= 0) {
      return;
    }
    for (int rmIndex = index; rmIndex < (index + remaining); rmIndex++) {
      ptX[index] = ptX[index + 1];
      ptY[index] = ptY[index + 1];
      fT0[index] = fT0[index + 1];
      fT1[index] = fT1[index + 1];
    }
    if (index == 0) {
      // Just shift right.
      fIsCoincident0 = fIsCoincident0 >> 1;
      fIsCoincident1 = fIsCoincident1 >> 1;
    }
    int leftMask = 0xFFFFFFFF << (index + 1);
    int rightMask = (0xFFFFFFFF << index) ^ 0xFFFFFFFF;
    fIsCoincident0 = ((fIsCoincident0 & leftMask) >> 1) | (fIsCoincident0 & rightMask);
    fIsCoincident1 = ((fIsCoincident1 & leftMask) >> 1) | (fIsCoincident1 & rightMask);
  }

  void allowNear(bool allow) {
    fAllowNear = allow;
  }

  /// Checks if end points have been added for curve one.
  bool hasT(double t) {
    assert(t == 0 || t == 1);
    return fUsed > 0 && (t == 0 ? fT0[0] == 0 : fT0[fUsed - 1] == 1);
  }

  /// Checks if end points have been added for curve two.
  bool hasOppT(double t) {
    assert(t == 0 || t == 1);
    return fUsed > 0 && (fT1[0] == t || fT1[fUsed - 1] == t);
  }

  int quadHorizontal(Float32List points, double left, double right, double y,
      bool flipped) {
    _fMax = 2;
    DLine line = DLine(left, y, right, y);
    Quad quad = Quad(points);
    final LineQuadraticIntersections q = LineQuadraticIntersections(quad,
        line, this);
    return q.horizontalIntersect(y, left, right, flipped);
  }

  int quadVertical(Float32List points, double top, double bottom, double x,
      bool flipped) {
    _fMax = 2;
    DLine line = DLine(x, top, x, bottom);
    Quad quad = Quad(points);
    LineQuadraticIntersections q = LineQuadraticIntersections(quad, line, this);
    return q.verticalIntersect(x, top, bottom, flipped);
  }

  int quadLine(Float32List points, Float32List linePoints) {
    _fMax = 2;
    LineQuadraticIntersections q = LineQuadraticIntersections(Quad(points),
        DLine.fromPoints(linePoints), this);
    q.allowNear(fAllowNear);
    return q.intersect();
  }

  int conicHorizontal(Float32List points, double weight, double left,
      double right, double y, bool flipped) {
    Conic conic = Conic.fromPoints(points, weight);
    _fMax = 2;
    DLine line = DLine(left, y, right, y);
    final LineConicIntersections c = LineConicIntersections(conic, line, this);
    return c.horizontalIntersect(y, left, right, flipped);
  }

  int conicVertical(Float32List points, double weight, double top,
      double bottom, double x, bool flipped) {
    Conic conic = Conic.fromPoints(points, weight);
    _fMax = 2;
    DLine line = DLine(x, top, x, bottom);
    final LineConicIntersections c = LineConicIntersections(conic, line, this);
    return c.verticalIntersect(x, top, bottom, flipped);
  }

  int conicLine(Float32List points, double weight, Float32List linePoints) {
    _fMax = 3; // 2;  permit small coincident segment + non-coincident intersection
    return intersectConicWithLine(Conic.fromPoints(points, weight),
        DLine.fromPoints(linePoints));
  }

  int cubicHorizontal(Float32List points, double left, double right, double y,
      bool flipped) {
    _fMax = 3;
    Cubic cubic = Cubic.fromPoints(points);
    DLine line = DLine(left, y, right, y);
    LineCubicIntersections c = LineCubicIntersections(cubic, line, this);
    return c.horizontalIntersect(y, left, right, flipped);
  }

  int cubicVertical(Float32List points, double top, double bottom, double x,
      bool flipped) {
    _fMax = 3;
    Cubic cubic = Cubic.fromPoints(points);
    DLine line = DLine(x, top, x, bottom);
    LineCubicIntersections c = LineCubicIntersections(cubic, line, this);
    return c.verticalIntersect(x, top, bottom, flipped);
  }

  int cubicLine(Float32List points, Float32List linePoints) {
    Cubic cubic = Cubic.fromPoints(points);
    DLine line = DLine.fromPoints(linePoints);
    LineCubicIntersections c = LineCubicIntersections(cubic, line, this);
    c.allowNear(fAllowNear);
    return c.intersect();
  }

  int intersectConicWithLine(Conic conic, DLine line) {
    final LineConicIntersections c = LineConicIntersections(conic, line, this);
    c.allowNear(fAllowNear);
    return c.intersect();
  }

  int intersectRayLine(DLine a, DLine b) {
    _fMax = 2;
    final double aLenX = a.x1 - a.x0;
    final double aLenY = a.y1 - a.y0;
    final double bLenX = b.x1 - b.x0;
    final double bLenY = b.y1 - b.y0;
    // Slopes match when denom goes to zero:
    //                   axLen / ayLen ==                   bxLen / byLen
    // (ayLen * byLen) * axLen / ayLen == (ayLen * byLen) * bxLen / byLen
    //          byLen  * axLen         ==  ayLen          * bxLen
    //          byLen  * axLen         -   ayLen          * bxLen == 0 ( == denom )
    final double denom = bLenY * aLenX - aLenY * bLenX;
    int used = 0;
    if (!approximatelyZero(denom)) {
      final double ab0X = a.x0 - b.x0;
      final double ab0Y = a.y0 - b.y0;
      final double numerA = (ab0Y * bLenX - bLenY * ab0X) / denom;
      final double numerB = (ab0Y * aLenX - aLenY * ab0X) / denom;
      fT0[0] = numerA;
      fT1[0] = numerB;
      used = 1;
    } else {
      // See if the axis intercepts match:
      //            ay - ax * ayLen / axLen  ==          by - bx * ayLen / axLen
      //   axLen * (ay - ax * ayLen / axLen) == axLen * (by - bx * ayLen / axLen)
      //   axLen *  ay - ax * ayLen          == axLen *  by - bx * ayLen
      if (!almostEqualUlps(aLenX * a.y0 - aLenY * a.x0,
          aLenX * b.y0 - aLenY * b.x0)) {
        return fUsed = 0;
      }
      // There's no great answer for intersection points for coincident rays,
      // but return something default.
      fT0[0] = fT1[0] = 0;
      fT1[0] = fT1[1] = 1;
      used = 2;
    }
    computePoints(a, used);
    return fUsed;
  }

  int intersectRayQuad(Quad quad, DLine line) {
    LineQuadraticIntersections q = LineQuadraticIntersections(quad, line,
        this);
    List<double> roots = [];
    fUsed = q.intersectRay(roots);
    for (int i = 0; i < roots.length; i++) {
      fT0[i] = roots[i];
    }
    for (int index = 0; index < fUsed; ++index) {
      double t = fT0[index];
      final ui.Offset pointAtT = quad.ptAtT(t);
      ptX[index] = pointAtT.dx;
      ptY[index] = pointAtT.dy;
    }
    return fUsed;
  }

  int intersectRayConic(Conic conic, DLine line) {
    LineConicIntersections c = LineConicIntersections(conic, line, this);
    fUsed = c.intersectRay(fT0);
    for (int index = 0; index < fUsed; ++index) {
      final ui.Offset pointAtT = conic.ptAtT(fT0[index]);
      ptX[index] = pointAtT.dx;
      ptY[index] = pointAtT.dy;
    }
    return fUsed;
  }

  int intersectRayCubic(Cubic cubic, DLine line) {
    LineCubicIntersections c = LineCubicIntersections(cubic, line, this);
    fUsed = c.intersectRay(fT0);
    for (int index = 0; index < fUsed; ++index) {
      final ui.Offset pointAtT = cubic.ptAtT(fT0[index]);
      ptX[index] = pointAtT.dx;
      ptY[index] = pointAtT.dy;
    }
    return fUsed;
  }

  void computePoints(DLine line, int used) {
    double t = fT0[0];
    ptX[0] = line.ptAtTx(t);
    ptY[0] = line.ptAtTy(t);
    if ((fUsed = used) == 2) {
      t = fT0[1];
      ptX[1] = line.ptAtTx(t);
      ptY[1] = line.ptAtTy(t);
    }
  }

  /// Flip t values of second curve (to 1 - t).
  void flip() {
    for (int index = 0; index < fUsed; ++index) {
      fT1[index] = 1 - fT1[index];
    }
  }

  /// Coincidence for point at [index].
  bool isCoincident(int index) => (fIsCoincident0 & (1 << index)) != 0;

  /// Sets coincidence for point at [index].
  void setCoincident(int index) {
    assert(index >= 0);
    int bit = 1 << index;
    fIsCoincident0 |= bit;
    fIsCoincident1 |= bit;
  }

  int intersectQuad(Quad q1, Quad q2) {
    TQuad quad1 = TQuad(q1);
    TQuad quad2 = TQuad(q2);
    TSect sect1 = TSect(quad1);
    TSect sect2 = TSect(quad2);
    TSect.binarySearch(sect1, sect2, this);
    return fUsed;
  }

  int intersectConicQuad(Conic c, Quad q) {
    TConic conic = TConic(c);
    TQuad quad = TQuad(q);
    TSect sect1 = TSect(conic);
    TSect sect2 = TSect(quad);
    TSect.binarySearch(sect1, sect2, this);
    return fUsed;
  }

  int intersectConic(Conic c1, Conic c2) {
    TConic conic1 = TConic(c1);
    TConic conic2 = TConic(c2);
    TSect sect1 = TSect(conic1);
    TSect sect2 = TSect(conic2);
    TSect.binarySearch(sect1, sect2, this);
    return fUsed;
  }

  int intersectCubicQuad(Cubic c, Quad q) {
    TCubic cubic = TCubic(c);
    TQuad quad = TQuad(q);
    TSect sect1 = TSect(cubic);
    TSect sect2 = TSect(quad);
    TSect.binarySearch(sect1, sect2, this);
    return fUsed;
  }

  int intersectCubicConic(Cubic cu, Conic co) {
    TCubic cubic = TCubic(cu);
    TConic conic = TConic(co);
    TSect sect1 = TSect(cubic);
    TSect sect2 = TSect(conic);
    TSect.binarySearch(sect1, sect2, this);
    return fUsed;
  }

  int intersectCubic(Cubic c1, Cubic c2) {
    TCubic cubic1 = TCubic(c1);
    TCubic cubic2 = TCubic(c2);
    TSect sect1 = TSect(cubic1);
    TSect sect2 = TSect(cubic2);
    TSect.binarySearch(sect1, sect2, this);
    return fUsed;
  }
}

/// Number of points the line is coincident with line at [y].
int _horizontalCoincident(DLine line, double y) {
    double min = line.y0;
    double max = line.y1;
    if (min > max) {
      double temp = min;
      min = max;
      max = temp;
    }
    if (min > y || max < y) {
      // Out of bounds.
      return 0;
    }
    // If line is horizontal and vertical points are almost equal, treat the
    // line as on line at y.
    if (almostEqualUlps(min, max) && max - min < (line.x0 - line.x1).abs()) {
      // Coincident at 2 points.
        return 2;
    }
    // 1 point only.
    return 1;
}

/// T value where line intercepts [y].
double _horizontalIntercept(DLine line, double y) {
  assert(line.y1 != line.y0,
      'Should only be called for vertical lines');
  // t = deltaYLine / (deltaY from start of line to y).
  return pinT((y - line.y0) / (line.y1 - line.y0));
}

class CurveDistance {
  /// Computes nearest point distance of point to curve.
  ///
  /// Assumes that the perpendicular to the point is the closest ray to the
  /// curve. This case (where the line and the curve are nearly coincident)
  /// may be the only case that counts.
  static double nearPoint(Float32List points, int verb, double weight,
      double x, double y, double oppX, double oppY) {
    int count = pathOpsVerbToPoints(verb);
    double minX = points[0];
    double maxX = minX;
    for (int index = 1; index <= count; ++index) {
      final double px = points[index * 2];
      minX = math.min(minX, px);
      maxX = math.max(maxX, px);
    }
    if (!almostBetweenUlps(minX, x, maxX)) {
      return -1;
    }
    double minY = points[1];
    double maxY = minY;
    for (int index = 1; index <= count; ++index) {
      final double py = points[index * 2 + 1];
      minY = math.min(minY, py);
      maxY = math.max(maxY, py);
    }
    if (!almostBetweenUlps(minY, y, maxY)) {
      return -1;
    }
    Intersections i = Intersections();
    DLine perpendicular = DLine(x, y, x + oppY - y, y + x - oppX);
    intersectRay(points, verb, weight, perpendicular, i);
    int minIndex = -1;
    double minDist = kFltMax;
    for (int index = 0; index < i.fUsed; ++index) {
      final double dist = math.sqrt(distanceSquared(x, y,
          i.ptX[index], i.ptY[index]));
      if (minDist > dist) {
        minDist = dist;
        minIndex = index;
      }
    }
    if (minIndex < 0) {
      return -1;
    }
    double largest = math.max(math.max(maxX, maxY), -math.min(minX, minY));
    // Check if distance is within ULPS.
    if (!almostEqualUlpsPin(largest, largest + minDist)) {
      return -1;
    }
    return pinT(i.fT0[minIndex]);
  }
}

void intersectRay(Float32List points, int verb, double weight, DLine line,
    Intersections intersections) {
  switch (verb) {
    case SPathVerb.kLine:
      intersections.intersectRayLine(DLine.fromPoints(points), line);
      break;
    case SPathVerb.kQuad:
      intersections.intersectRayQuad(Quad(points), line);
      break;
    case SPathVerb.kConic:
      intersections.intersectRayConic(Conic.fromPoints(points, weight), line);
      break;
    case SPathVerb.kCubic:
      intersections.intersectRayCubic(Cubic.fromPoints(points), line);
      break;
    default:
      assert(false);
      break;
  }
}
