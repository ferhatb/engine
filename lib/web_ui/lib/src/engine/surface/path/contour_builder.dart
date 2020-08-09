// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

const bool kDebugCoincidenceOrder = true;
const bool kDebugValidate = true;

/// Builds an OpContour.
///
/// A path is converted into a list of [OpContour]s.
/// A contour consist of multiple [OpSegment]s.
/// Each [OpSegment] contains 1 or more spans.
/// A span contains multiple [OpPtT] points.
///
/// OpContourBuilder eliminates lines that follow each other and are exactly
/// opposite before constructing OpContour segments.
class OpContourBuilder {
  OpContourBuilder(OpGlobalState globalState) : _fContour = OpContour(globalState);

  void addConic(Float32List points, double weight) {
    flush();
    contour.addConic(points, weight);
  }

  void addCubic(Float32List points) {
    flush();
    contour.addCubic(points);
  }

  void addQuad(Float32List points) {
    flush();
    contour.addQuad(points);
  }

  void addCurve(int verb, Float32List points, {double weight = 1}) {
    switch(verb) {
      case SPathVerb.kLine:
        addLine(points);
        break;
      case SPathVerb.kQuad:
        addQuad(_clonePoints(points, 3));
        break;
      case SPathVerb.kConic:
        addConic(_clonePoints(points, 3), weight);
        break;
      case SPathVerb.kCubic:
        addCubic(_clonePoints(points, 4));
        break;
    }
  }

  void addLine(Float32List points) {
    // If last line added is the exact opposite, eliminate both lines.
    if (_fLastIsLine) {
      if (points[3] == _lastLinePoints[1] && points[2] == _lastLinePoints[0] &&
          points[1] == _lastLinePoints[3] && points[0] == _lastLinePoints[2]) {
        // Eliminate.
        _fLastIsLine = false;
        return;
      } else {
        // Write out prior line.
        flush();
      }
    }
    _lastLinePoints[0] = points[0];
    _lastLinePoints[1] = points[1];
    _lastLinePoints[2] = points[2];
    _lastLinePoints[3] = points[3];
    _fLastIsLine = true;
  }

  /// Flushes any queued contour segments.
  void flush() {
    if (!_fLastIsLine) {
      return;
    }
    contour.addLine(_clonePoints(_lastLinePoints, 2));
    _fLastIsLine = false;
  }

  OpContour get contour => _fContour;
  OpContour _fContour;
  Float32List _lastLinePoints = Float32List(4);

  /// Whether last segment on contour is a line.
  bool _fLastIsLine = false;
}

Float32List _clonePoints(Float32List points, int pointCount) {
  final int size = pointCount * 2;
  final Float32List clone = Float32List(size);
  for (int i = 0; i < size; i++) {
    clone[i] = points[i];
  }
  return clone;
}

class OpContour {
  OpContour(this.fState);

  void init(bool operand, bool xor) {
    _operand = operand;
    _xor = xor;
  }

  void addConic(Float32List points, double weight) {
    _segments.add(OpSegment.conic(points, weight, this));
  }

  void addCubic(Float32List points) {
    _segments.add(OpSegment.cubic(points, this));
  }

  void addLine(Float32List points) {
    _segments.add(OpSegment.line(points, this));
  }

  void addQuad(Float32List points) {
    _segments.add(OpSegment.quad(points, this));
  }

  /// Number of segments.
  int get count => _segments.length;

  final List<OpSegment> _segments = [];
  // First half of build is marked false, second half true.
  bool? _operand;
  // True if operand (contour) needs to be xor'd for evenOdd.
  bool? _xor;

  List<OpSegment> get debugSegments => _segments;

  void complete() {
    setBounds();
    // Setup next pointers on segments.
    for (int i = 0, len = _segments.length - 1; i < len; i++) {
      _segments[i]._next = _segments[i + 1];
    }
  }

  /// Updates bounds of contour based on segment bounds.
  void setBounds() {
    assert(count > 0);
    OpSegment segment = _segments[0];
    ui.Rect bounds = segment.bounds;
    double minX = bounds.left;
    double maxX = bounds.right;
    double minY = bounds.top;
    double maxY = bounds.bottom;
    for (int i = 1; i < _segments.length; i++) {
      segment = _segments[i];
      bounds = segment.bounds;
      if (bounds.left < minX) {
        minX = bounds.left;
      }
      if (bounds.top < minY) {
        minY = bounds.top;
      }
      if (bounds.right > maxX) {
        maxX = bounds.right;
      }
      if (bounds.bottom > maxY) {
        maxY = bounds.bottom;
      }
    }
    _bounds = ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  ui.Rect get bounds => _bounds!;

  ui.Rect? _bounds;
  final OpGlobalState fState;
}

/// Represents a group of points that form a line or curve that are part of
/// a contour.
///
/// Provides access to [next] segment following a segment in the contour.
class OpSegment {
  OpSegment(this.points, this.verb, this.parent, this.weight, this.bounds) {
    fHead =
        OpSpan(this, null)
          ..init(0, ui.Offset(points[0], points[1]));
  }

  /// Linked list of spans formed by adding intersection points.
  OpSpanBase? fHead;
  final Float32List points;
  final int verb;
  final OpContour parent;
  final double weight;
  final ui.Rect bounds;
  OpSegment? _next;
  /// Span count.
  int fCount = 0;
  /// Number of processed spans.
  int fDoneCount = 0;

  void bumpCount() {
    fCount++;
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
  OpPtT addT(double t) {
    ui.Offset pt = ptAtT(t);
    return addTAtPoint(t, pt.dx, pt.dy);
  }

  /// Updates spans for an intersection point [ptX],[ptY] at [t].
  OpPtT addTAtPoint(double t, double ptX, double ptY) {
    OpSpanBase? spanBase = fHead;
    while (spanBase != null) {
      OpPtT result = spanBase.ptT;
      /// If t already exist in span list, bump counter and return existing
      /// span. [match] ensures that point at T is approximately equal.
      if (t == result.fT || (!zeroOrOne(t) && match(result, this, t, ptX, ptY))) {
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
        span._fNext = result.span;
        span.bumpSpanAdds();
        return span.ptT;
      }
      spanBase = spanBase.upCast.next;
    }
    assert(false);
    return OpPtT(fHead!, ui.Offset.zero, double.nan);
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
    if (!approximatelyEqualPoints(testPtX, testPtY, basePoint.dx, basePoint.dy)) {
      return false;
    }
    return this != testParent ||
        !ptsDisjoint(base.fT, basePoint.dx, basePoint.dy, testT, testPtX, testPtY);
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
}

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
  OpAngle? fFromAngle;
  /// Previous intersection point.
  OpSpan? _fPrev;
  /// Number of times intersections have been added to this span.
  int fSpanAdds = 0;
  bool _fAligned = true;
  bool fChased = false;

  /// Returns first intersection point at start of this span.
  OpPtT get ptT => fPtT!;

  OpSpan get upCast => this as OpSpan;

  void bumpSpanAdds() {
    ++fSpanAdds;
  }

  OpSpan? get prev => _fPrev;

  bool isFinal() => fPtT == 1;

  bool get deleted => fPtT!.deleted;

  void unaligned() {
    _fAligned = false;
  }

  double get t {
    return fPtT!.fT;
  }

  OpSpan? upCastable() {
    return isFinal() ? null : upCast;
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
  OpPtT? contains(OpSegment segment) {
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
  OpGlobalState globalState() => fSegment.parent.fState;
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
  OpAngle? toAngle;
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
}

// Angle between two spans.
class OpAngle {
  OpAngle(this.start, this.end);

  final OpSpanBase start;
  final OpSpanBase end;

  /// Next angle (linked list).
  OpAngle? next;
}

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
}
