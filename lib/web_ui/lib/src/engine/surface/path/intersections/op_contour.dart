// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

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
  bool _operand = false;
  // True if operand (contour) needs to be xor'd for evenOdd.
  bool? _xor;

  bool get isXor => _xor!;

  int fCcw = -1;
  bool fReverse = false;

  List<OpSegment> get debugSegments => _segments;
  bool get operand => _operand;

  // Set by findTopSegment to mark a contour as processed (written to
  // output).
  bool _done = false;
  bool get done => _done;

  int get ccw => fCcw;
  set ccw(int value) {
    fCcw = value;
  }

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

  /// Joins [OpSpan](s) of all segments for this contour.
  void joinSegments() {
    for (int i = 0; i < count; ++i) {
      OpSegment segment = _segments[i];
      if (i == (count - 1)) {
        segment.joinEnds(_segments[0]);
      } else {
        segment.joinEnds(_segments[i + 1]);
      }
    }
  }

  void resetReverse() {
    if (count == 0) {
      return;
    }
    fCcw = -1;
    fReverse = false;
  }

  bool moveMultiples() {
    for (int i = 0; i < count; ++i) {
      OpSegment segment = _segments[i];
      if (!segment.moveMultiples()) {
        return false;
      }
    }
    return true;
  }

  bool moveNearby() {
    for (int i = 0; i < count; ++i) {
      OpSegment segment = _segments[i];
      if (!segment.moveNearby(fState)) {
        return false;
      }
    }
    return true;
  }

  void calcAngles() {
    for (int i = 0; i < count; ++i) {
      _segments[i].calcAngles();
    }
  }

  bool sortAngles() {
    for (int i = 0; i < count; ++i) {
      if (!_segments[i].sortAngles()) {
        return false;
      }
    }
    return true;
  }

  bool missingCoincidence() {
    assert(count > 0);
    bool result = false;
    for (int i = 0; i < count; ++i) {
      OpSegment segment = _segments[i];
      if (segment.missingCoincidence()) {
        result = true;
      }
    }
    return result;
  }

  void rayCheck(OpRayHit base, int opRayDir, List<OpRayHit> hits) {
    // If the bounds extreme is outside the best, we're done.
    double baseXY = (opRayDir & 1) == 0 ? base.fPt.dx : base.fPt.dy;
    double boundsXY = rectSide(bounds, opRayDir);
    bool checkLessThan = lessThan(opRayDir);
    if (!approximatelyEqualT(baseXY, boundsXY) &&
        (baseXY < boundsXY) == checkLessThan) {
      return;
    }
    for (OpSegment testSegment in _segments) {
      testSegment.rayCheck(base, opRayDir, hits);
    }
  }
}
