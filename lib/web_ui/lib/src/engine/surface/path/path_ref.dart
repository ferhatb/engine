// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
part of engine;

/// Holds the path verbs and points.
///
/// This is a Dart port of Skia SkPathRef class.
///
/// The points and verbs are stored in a single allocation. The points are at
/// the beginning of the allocation while the verbs are stored at end of the
/// allocation, in reverse order. Thus the points and verbs both grow into the
/// middle of the allocation until they meet.
///
/// Unlike native skia GenID is not supported since we don't have requirement
/// to update caches due to content changes.
class PathRef {
  // Value to use to check against to insert move(0,0) when a command
  // is added without moveTo.
  static const int kInitialLastMoveToIndex = -1;

  // SerializationOffsets
  static const int kLegacyRRectOrOvalStartIdx_SerializationShift = 28; // requires 3 bits, ignored.
  static const int kLegacyRRectOrOvalIsCCW_SerializationShift = 27;    // requires 1 bit, ignored.
  static const int kLegacyIsRRect_SerializationShift = 26;             // requires 1 bit, ignored.
  static const int kIsFinite_SerializationShift = 25;                  // requires 1 bit
  static const int kLegacyIsOval_SerializationShift = 24;              // requires 1 bit, ignored.
  static const int kSegmentMask_SerializationShift = 0;                // requires 4 bits (deprecated)

  PathRef() {
    _resetFields();
  }

  void _resetFields() {
    fBoundsIsDirty = true;    // this also invalidates fIsFinite
    fSegmentMask = 0;
    fIsOval = false;
    fIsRRect = false;
    _rrect = null;
    fIsRect = false;
    // The next two values don't matter unless fIsOval or fIsRRect are true.
    fRRectOrOvalIsCCW = false;
    fRRectOrOvalStartIdx = 0xAC;
    assert(() {
      debugValidate();
      return true;
    }());
  }

  void setPoint(int pointIndex, double x, double y) {
    fPoints[pointIndex] = ui.Offset(x, y);
  }


  // TODO: optimize, for now we do a deepcopy.
  PathRef._shallowCopy(PathRef ref) {
    copy(ref, 0, 0);
  }

  /// Gets a path ref with no verbs or points.
  static PathRef createEmpty() => _empty;
  static final PathRef _empty = PathRef().._computeBounds();
  static PathRef gEmpty = null;

  /// Returns a const pointer to the first point.
  ui.Rect   fBounds;
  List<ui.Offset> fPoints = [];
  List<int> fVerbs = [];

  List<ui.Offset> get points => fPoints;
  //Float32List get conicWeights => _conicWeights;
  //Float32List _conicWeights;
  List<double> _conicWeights;

  int countPoints() => fPoints.length;
  int countVerbs() => fVerbs.length;
  int countWeights() => _conicWeights?.length ?? 0;

  /// Convenience methods for getting to a verb or point by index.
  int atVerb(int index) { return fVerbs[index]; }
  ui.Offset atPoint(int index) { return ui.Offset(fPoints[index].dx, fPoints[index].dy); }
  double atWeight(int index) { return _conicWeights[index]; }

  ///  Returns true if all of the points in this path are finite, meaning
  ///  there are no infinities and no NaNs.
  bool get isFinite {
    if (fBoundsIsDirty) {
      _computeBounds();
    }
    return fIsFinite;
  }

  ///  Returns a mask, where each bit corresponding to a SegmentMask is
  ///  set if the path contains 1 or more segments of that type.
  ///  Returns 0 for an empty path (no segments).
  int get segmentMasks => fSegmentMask;

  /// Returns start index if the path is an oval or -1 if not.
  ///
  /// Tracking whether a path is an oval is considered an
  /// optimization for performance and so some paths that are in
  // fact ovals can report false.
  int get isOval => fIsOval ? fRRectOrOvalStartIdx : -1;
  bool get isOvalCCW => fRRectOrOvalIsCCW;

  int get isRRect => fIsRRect ? fRRectOrOvalStartIdx : -1;
  int get isRect => fIsRect ? fRRectOrOvalStartIdx : -1;
  ui.RRect _rrect;
  ui.RRect getRRect() => fIsRRect ? _getRRect() : null;
  ui.Rect getRect() => fIsRect ? _getRect() : null;
  bool get isRectCCW => fRRectOrOvalIsCCW;

  bool get hasComputedBounds => !fBoundsIsDirty;

  /// Returns the bounds of the path's points. If the path contains 0 or 1
  /// points, the bounds is set to (0,0,0,0), and isEmpty() will return true.
  /// Note: this bounds may be larger than the actual shape, since curves
  /// do not extend as far as their control points.
  ui.Rect getBounds() {
    if (fBoundsIsDirty) {
      _computeBounds();
    }
    return fBounds;
  }

  ui.Rect _getRect() {
    // Reconstructs Rect from path commands.
    return ui.Rect.fromLTRB(atPoint(0).dx, atPoint(0).dy,
        atPoint(1).dx, atPoint(2).dy);
  }

  // Reconstructs RRect from path commands.
  //
  // Expect 4 Conics and lines between.
  // Use conic points to calculate corner radius.
  ui.RRect _getRRect() {
    ui.Rect bounds = getBounds();
    // Radii x,y of 4 corners
    final List<ui.Radius> radii = List<ui.Radius>(4);
    final PathRefIterator iter = PathRefIterator(this);
    final Float32List pts = Float32List(10);
    int verb = iter.next(pts);
    assert(SPath.kMoveVerb == verb);
    int cornerIndex = 0;
    while ((verb = iter.next(pts)) != SPath.kDoneVerb) {
        if (SPath.kConicVerb == verb) {
          final double controlPx = pts[2];
          final double controlPy = pts[3];
          double vector1_0x = controlPx - pts[0];
          double vector1_0y = controlPy - pts[1];
          double vector2_1x = pts[4] - pts[2];
          double vector2_1y = pts[5] - pts[3];
          double dx, dy;
          // Depending on the corner we have control point at same
          // horizontal position as startpoint or same vertical position.
          // The location delta of control point specifies corner radius.
          if (vector1_0x != 0.0) {
            // For CW : Top right or bottom left corners.
            assert(vector2_1x == 0.0 && vector1_0y == 0.0);
            dx = vector1_0x.abs();
            dy = vector2_1y.abs();
          } else if (vector1_0y != 0.0) {
            assert(vector2_1x == 0.0 || vector2_1y == 0.0);
            dx = vector2_1x.abs();
            dy = vector1_0y.abs();
          } else {
            assert(vector2_1y == 0.0);
            dx = vector1_0x.abs();
            dy = vector1_0y.abs();
          }
          final int checkCornerIndex = (controlPx == bounds.left) ?
              ((controlPy == bounds.top) ? _Corner.kUpperLeft : _Corner.kLowerLeft)
              : (controlPy == bounds.top ? _Corner.kUpperRight : _Corner.kLowerRight);
          assert(checkCornerIndex == cornerIndex);
          assert(radii[cornerIndex] == null);
          radii[cornerIndex] = ui.Radius.elliptical(dx, dy);
          ++cornerIndex;
        } else {
          assert((verb == SPath.kLineVerb
              && ((pts[2] - pts[0]) == 0 || (pts[3] - pts[1]) == 0))
              || verb == SPath.kCloseVerb);
        }
    }
    return ui.RRect.fromRectAndCorners(bounds, topLeft: radii[_Corner.kUpperLeft],
        topRight: radii[_Corner.kUpperRight], bottomRight: radii[_Corner.kLowerRight],
        bottomLeft: radii[_Corner.kLowerLeft]);
  }

  bool operator==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return equals(other);
  }

  bool equals(PathRef ref) {
    // We explicitly check fSegmentMask as a quick-reject. We could skip it,
    // since it is only a cache of info in the fVerbs, but its a fast way to
    // notice a difference
    if (fSegmentMask != ref.fSegmentMask) {
      return false;
    }

    final int pointCount = countPoints();
    if (pointCount != ref.countPoints()) {
      return false;
    }
    for (int i = 0; i < pointCount; i++) {
      if (fPoints[i] != ref.fPoints[i]) {
        return false;
      }
    }

    if (_conicWeights == null) {
      if (ref._conicWeights != null) {
        return false;
      }
    } else {
      if (ref._conicWeights == null) {
        return false;
      }
      final int weightCount = _conicWeights.length;
      if (ref._conicWeights.length != weightCount) {
        return false;
      }
      for (int i = 0; i < weightCount; i++) {
        if (_conicWeights[i] != ref._conicWeights[i]) {
          return false;
        }
      }
    }
    final int verbCount = countVerbs();
    if (verbCount != ref.countVerbs()) {
      return false;
    }
    for (int i = 0; i < verbCount; i++) {
      if (fVerbs[i] != ref.fVerbs[i]) {
        return false;
      }
    }
    if (ref.countVerbs() == 0) {
      assert(ref.countPoints() == 0);
    }
    return true;
  }

  /// Copies contents from [ref].
  void copy(PathRef ref, int additionalReserveVerbs,
      int additionalReservePoints) {
    ref.debugValidate();
    final int verbCount = ref.countVerbs();
    final int pointCount = ref.countPoints();
    final int weightCount = ref.countWeights();
    resetToSize(verbCount, pointCount, weightCount,
        additionalReserveVerbs, additionalReservePoints);

    for (int i = 0; i < verbCount; i++) {
      fVerbs[i] = ref.fVerbs[i];
    }
    for (int i = 0; i < pointCount; i++) {
      fPoints[i] = ref.fPoints[i];
    }
//    if (ref.fConicWeights != null) {
//      js_util.callMethod(fConicWeights, 'set', [ref.fConicWeights]);
//    }
    if (weightCount != 0) {
      _conicWeights = [];
      for (int i = 0; i < weightCount; i++) {
        _conicWeights.add(ref._conicWeights[i]);
      }
    }
    fBoundsIsDirty = ref.fBoundsIsDirty;
    if (!fBoundsIsDirty) {
      fBounds = ref.fBounds;
      fIsFinite = ref.fIsFinite;
    }
    fSegmentMask = ref.fSegmentMask;
    fIsOval = ref.fIsOval;
    fIsRRect = ref.fIsRRect;
    fIsRect = ref.fIsRect;
    _rrect = ref._rrect;
    fRRectOrOvalIsCCW = ref.fRRectOrOvalIsCCW;
    fRRectOrOvalStartIdx = ref.fRRectOrOvalStartIdx;
    debugValidate();
  }

  void _append(PathRef source) {
    final int pointCount = source.countPoints();
    for (int i = 0; i < pointCount; i++) {
      fPoints.add(source.fPoints[i]);
    }
    final int verbCount = source.countVerbs();
    for (int i = 0; i < verbCount; i++) {
      fVerbs.add(source.fVerbs[i]);
    }
    final int weightCount = source.countWeights();
    if (weightCount != 0) {
      _conicWeights ??= [];
      for (int i = 0; i < weightCount; i++) {
        _conicWeights.add(source._conicWeights[i]);
      }
    }
    fBoundsIsDirty = true;
  }

  // Doesn't read fSegmentMask, but (re)computes it from the verbs array
  int computeSegmentMask() {
    List<int> verbs = fVerbs;
    int mask = 0;
    int verbCount = countVerbs();
    for (int i = 0; i < verbCount; ++i) {
      switch (verbs[i]) {
        case SPath.kLineVerb:  mask |= SPath.kLineSegmentMask; break;
        case SPath.kQuadVerb:  mask |= SPath.kQuadSegmentMask; break;
        case SPath.kConicVerb: mask |= SPath.kConicSegmentMask; break;
        case SPath.kCubicVerb: mask |= SPath.kCubicSegmentMask; break;
        default: break;
      }
    }
    return mask;
  }

  // This is incorrectly defined as instance method on SkPathRef although
  // SkPath instance method first makes a copy of itself into out and
  // then interpolates based on weight.
  static void interpolate(PathRef ending, double weight, PathRef out) {
    assert(out.countPoints() == ending.countPoints());
    final int count = out.countPoints();
    final List<ui.Offset> outValues = out.fPoints;
    final List<ui.Offset> inValues = ending.fPoints;
    for (int index = 0; index < count; ++index) {
      outValues[index] = outValues[index] * weight + inValues[index] * (1.0 - weight);
    }
    out.fBoundsIsDirty = true;
    out._preEdit();
  }

  // called, if dirty, by getBounds()
  void _computeBounds() {
    debugValidate();
    assert(fBoundsIsDirty);
    int pointCount = countPoints();
    fBoundsIsDirty = false;
    if (pointCount == 0) {
      fBounds = ui.Rect.zero;
      fIsFinite = true;
    } else {
      double minX, maxX, minY, maxY;
      minX = maxX = fPoints[0].dx;
      minY = maxY = fPoints[0].dy;
      fIsFinite = minX.isFinite && minY.isFinite;
      for (int i = 1; i < pointCount; i++) {
        final double x = fPoints[i].dx;
        final double y = fPoints[i].dy;
        if (x.isNaN || y.isNaN) {
          fIsFinite =false;
          fBounds = ui.Rect.zero;
          return;
        }
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
      fBounds = ui.Rect.fromLTRB(minX, minY, maxX, maxY);
    }
  }

  /// Makes additional room but does not change the counts.
  void incReserve(int additionalVerbs, int additionalPoints) {
    debugValidate();
    _setfPointsReserve(countPoints() + additionalPoints);
    _setfVerbsReserve(countVerbs() + additionalVerbs);
    debugValidate();
  }

  /// Sets to initial state preserving internal storage.
  void rewind() {
    fPoints.clear();
    fVerbs.clear();
    _conicWeights?.clear();
    _resetFields();
  }

  /// Resets the path ref with verbCount verbs and pointCount points, all
  /// uninitialized. Also allocates space for reserveVerb additional verbs
  /// and reservePoints additional points.
  void resetToSize(int verbCount, int pointCount, int conicCount,
                     [int reserveVerbs = 0, int reservePoints = 0]) {
    debugValidate();
    fBoundsIsDirty = true;      // this also invalidates fIsFinite

    fSegmentMask = 0;
    _preEdit();

    _setfPointsReserve(pointCount + reservePoints);
    _setfPointsCount(pointCount);
    _setfVerbsReserve(verbCount + reserveVerbs);
    _setfVerbsCount(verbCount);
    _setfConicWeightsCount(conicCount);
    debugValidate();
  }

  void _setfPointsReserve(int count) {
    // TODO
  }

  void _setfVerbsReserve(int count) {
    // TODO
  }

  void _setfConicWeightsCount(int count) {
    // TODO
  }

  void _setfPointsCount(int count) {
    if (count == 0) {
      fPoints.clear();
      return;
    }
    if (count > fPoints.length) {
      for (int i = count - fPoints.length ; i > 0; i--) {
        fPoints.add(null);
      }
    } else if (count < fPoints.length) {
      fPoints.removeRange(count, fPoints.length);
    }
    fBoundsIsDirty = true;
  }

  void _setfVerbsCount(int count) {
    if (count == 0) {
      fVerbs.clear();
      return;
    }
    if (count > fVerbs.length) {
      for (int i = count - fVerbs.length ; i > 0; i--) {
        fVerbs.add(null);
      }
    } else if (count < fVerbs.length) {
      fVerbs.removeRange(count, fVerbs.length);
    }
  }

  /// Increases the verb count 1, records the new verb, and creates room for the requisite number
  /// of additional points. A pointer to the first point is returned. Any new points are
  /// uninitialized.
  int growForVerb(int verb, double weight) {
    debugValidate();
    int pCnt;
    int mask = 0;
    switch (verb) {
      case SPath.kMoveVerb:
        pCnt = 1;
        break;
      case SPath.kLineVerb:
        mask = SPath.kLineSegmentMask;
        pCnt = 1;
        break;
      case SPath.kQuadVerb:
        mask = SPath.kQuadSegmentMask;
        pCnt = 2;
        break;
      case SPath.kConicVerb:
        mask = SPath.kConicSegmentMask;
        pCnt = 2;
        break;
      case SPath.kCubicVerb:
        mask = SPath.kCubicSegmentMask;
        pCnt = 3;
        break;
      case SPath.kCloseVerb:
        pCnt = 0;
        break;
      case SPath.kDoneVerb:
        if (assertionsEnabled) {
          throw Exception("growForVerb called for kDone");
        }
        pCnt = 0;
        break;
      default:
        if (assertionsEnabled) {
          throw Exception("default is not reached");
        }
        pCnt = 0;
        break;
    }

    fSegmentMask |= mask;
    fBoundsIsDirty = true;  // this also invalidates fIsFinite
    _preEdit();
    fVerbs.add(verb);
    if (SPath.kConicVerb == verb) {
      _conicWeights ??= [];
      _conicWeights.add(weight);
    }
    int pts = fPoints.length;
    for (int i = pCnt; i > 0; --i) {
      fPoints.add(null);
    }
    debugValidate();
    return pts;
  }

  /// Increases the verb count by numVbs and point count by the required amount.
  /// The new points are uninitialized. All the new verbs are set to the
  /// specified verb. If 'verb' is kConic_Verb, 'weights' will return a
  /// pointer to the uninitialized conic weights.
  ///
  /// This is an optimized version for [SPath.addPolygon].
  int growForRepeatedVerb(int /*SkPath::Verb*/ verb, int numVbs) {
    debugValidate();
    _preEdit();
    int pCnt;
    int mask = 0;
    switch (verb) {
      case SPath.kMoveVerb:
          pCnt = numVbs;
          break;
      case SPath.kLineVerb:
          mask = SPath.kLineSegmentMask;
          pCnt = numVbs;
          break;
      case SPath.kQuadVerb:
          mask = SPath.kQuadSegmentMask;
          pCnt = 2 * numVbs;
          break;
      case SPath.kConicVerb:
          mask = SPath.kConicSegmentMask;
          pCnt = 2 * numVbs;
          break;
      case SPath.kCubicVerb:
          mask = SPath.kCubicSegmentMask;
          pCnt = 3 * numVbs;
          break;
      case SPath.kCloseVerb:
          pCnt = 0;
          break;
      case SPath.kDoneVerb:
          if (assertionsEnabled) {
              throw Exception("growForVerb called for kDone");
          }
          pCnt = 0;
          break;
      default:
          if (assertionsEnabled) {
              throw Exception("default is not reached");
          }
          pCnt = 0;
          break;
    }

    fSegmentMask |= mask;
    fBoundsIsDirty = true;  // this also invalidates fIsFinite
    _preEdit();

    if (SPath.kConicVerb == verb) {
      _conicWeights = [];
      for (int i = pCnt; i > 0; --i) {
        _conicWeights.add(null);
      }
    }
    int pts = fPoints.length;
    for (int i = pCnt; i > 0; --i) {
      fVerbs.add(verb);
      fPoints.add(null);
    }
    debugValidate();
    return pts;
  }

  /// Concatenates all verbs from 'path' onto our own verbs array. Increases the point count by the
  /// number of points in 'path', and the conic weight count by the number of conics in 'path'.
  ///
  /// Returns pointers to the uninitialized points and conic weights data.
  void growForVerbsInPath(PathRef path) {
    debugValidate();
    _preEdit();
    fSegmentMask |= path.fSegmentMask;
    fBoundsIsDirty = true;  // this also invalidates fIsFinite

    int numVerbs = path.countVerbs();
    if (numVerbs != 0) {
      fVerbs.addAll(path.fVerbs);
      //memcpy(fVerbs.append(numVerbs), path.fVerbs.begin(), numVerbs * sizeof(fVerbs[0]));
    }

    final int numPts = path.countPoints();
    if (numPts != 0) {
      fPoints.addAll(path.fPoints);
    }

    final int numConics = path.countWeights();
    if (numConics != 0) {
      _conicWeights ??= [];
      _conicWeights.addAll(path._conicWeights);
    }

    debugValidate();
  }

  /// Resets higher level curve detection before a new edit is started.
  ///
  /// SurfacePath.addOval, addRRect will set these flags after the verbs and
  /// points are added.
  void _preEdit() {
    fIsOval = false;
    fIsRRect = false;
    fIsRect = false;
  }

  /// Private, non-const-ptr version of the public function verbsMemBegin().
  // uint8_t* verbsBeginWritable() { return fVerbs.begin(); }

  /// Called the first time someone calls CreateEmpty to actually create the singleton.
  // friend SkPathRef* sk_create_empty_pathref();

  void setIsOval(bool isOval, bool isCCW, int start) {
    fIsOval = isOval;
    fRRectOrOvalIsCCW = isCCW;
    fRRectOrOvalStartIdx = start;
  }

  void setIsRRect(bool isRRect, bool isCCW, int start, ui.RRect rrect) {
    fIsRRect = isRRect;
    _rrect = rrect;
    fRRectOrOvalIsCCW = isCCW;
    fRRectOrOvalStartIdx = start;
  }

  void setIsRect(bool isRect, bool isCCW, int start) {
    fIsRect = isRect;
    fRRectOrOvalIsCCW = isCCW;
    fRRectOrOvalStartIdx = start;
  }

  List<ui.Offset> getPoints() {
    debugValidate();
    return fPoints;
  }

  static const int kMinSize = 256;

  bool fBoundsIsDirty = true;
  bool fIsFinite;    // only meaningful if bounds are valid

  bool fIsOval = false;
  bool fIsRRect = false;
  bool fIsRect = false;
  // Both the circle and rrect special cases have a notion of direction and starting point
  // The next two variables store that information for either.
  bool fRRectOrOvalIsCCW = false;
  int  fRRectOrOvalStartIdx = -1;
  int  fSegmentMask = 0;

  bool get isValid {
    if (fIsOval || fIsRRect) {
      // Currently we don't allow both of these to be set.
      if (fIsOval == fIsRRect) {
          return false;
      }
      if (fIsOval) {
        if (fRRectOrOvalStartIdx >= 4) {
          return false;
        }
      } else {
        if (fRRectOrOvalStartIdx >= 8) {
          return false;
        }
      }
    }
    if (fIsRect) {
      if (fIsOval || fIsRRect) {
        return false;
      }
      if (fRRectOrOvalStartIdx >= 4) {
        return false;
      }
    }

    if (!fBoundsIsDirty && !fBounds.isEmpty) {
      bool isFinite = true;
      final double boundsLeft = fBounds.left;
      final double boundsTop = fBounds.top;
      final double boundsRight = fBounds.right;
      final double boundsBottom = fBounds.bottom;
      for (int i = 0; i < fPoints.length; ++i) {
        final double pointX = fPoints[i].dx;
        final double pointY = fPoints[i].dy;
        final bool pointIsFinite = _isPointFinite(fPoints[i]);
        if (pointIsFinite &&
            (pointX < boundsLeft || pointY < boundsTop ||
                pointX > boundsRight || pointY > boundsBottom)) {
          return false;
        }
        if (!pointIsFinite) {
          isFinite = false;
        }
      }
      if (fIsFinite != isFinite) {
        // Inconsistent state. Cached [fIsFinite] doesn't match what we found.
        return false;
      }
    }
    return true;
  }

  bool get isEmpty => countVerbs() == 0;

  void debugValidate() {
    assert(isValid);
  }
}

// Return true if all components of offset are finite.
bool _isPointFinite(ui.Offset offset) {
  double accum = 0;
  accum *= offset.dx;
  accum *= offset.dy;
  return !accum.isNaN;
}

class PathRefIterator {
  final PathRef pathRef;
  int _conicWeightIndex = -1;
  int _verbIndex = 0;
  int _pointIndex = 0;

  PathRefIterator(this.pathRef) {
    _pointIndex = 0;
    if (!pathRef.isFinite) {
      // Don't allow iteration through non-finite points, prepare to return
      // done verb.
      _verbIndex = pathRef.countVerbs();
    }
  }

  // Returns next verb and reads associated points into [outPts].
  int next(Float32List outPts) {
    if (_verbIndex == pathRef.countVerbs()) {
      return SPath.kDoneVerb;
    }
    int verb = pathRef.fVerbs[_verbIndex++];
    switch(verb) {
      case SPath.kMoveVerb:
        final ui.Offset offset = pathRef.points[_pointIndex++];
        outPts[0] = offset.dx;
        outPts[1] = offset.dy;
        break;
      case SPath.kLineVerb:
        final ui.Offset start = pathRef.points[_pointIndex - 1];
        final ui.Offset offset = pathRef.points[_pointIndex++];
        outPts[0] = start.dx;
        outPts[1] = start.dy;
        outPts[2] = offset.dx;
        outPts[3] = offset.dy;
        break;
      case SPath.kConicVerb:
        _conicWeightIndex++;
        final ui.Offset start = pathRef.points[_pointIndex - 1];
        final ui.Offset p1 = pathRef.points[_pointIndex++];
        final ui.Offset p2 = pathRef.points[_pointIndex++];
        outPts[0] = start.dx;
        outPts[1] = start.dy;
        outPts[2] = p1.dx;
        outPts[3] = p1.dy;
        outPts[4] = p2.dx;
        outPts[5] = p2.dy;
        break;
      case SPath.kQuadVerb:
        final ui.Offset start = pathRef.points[_pointIndex - 1];
        final ui.Offset p1 = pathRef.points[_pointIndex++];
        final ui.Offset p2 = pathRef.points[_pointIndex++];
        outPts[0] = start.dx;
        outPts[1] = start.dy;
        outPts[2] = p1.dx;
        outPts[3] = p1.dy;
        outPts[4] = p2.dx;
        outPts[5] = p2.dy;
        break;
      case SPath.kCubicVerb:
        final ui.Offset start = pathRef.points[_pointIndex - 1];
        final ui.Offset p1 = pathRef.points[_pointIndex++];
        final ui.Offset p2 = pathRef.points[_pointIndex++];
        final ui.Offset p3 = pathRef.points[_pointIndex++];
        outPts[0] = start.dx;
        outPts[1] = start.dy;
        outPts[2] = p1.dx;
        outPts[3] = p1.dy;
        outPts[4] = p2.dx;
        outPts[5] = p2.dy;
        outPts[6] = p3.dx;
        outPts[7] = p3.dy;
        break;
      case SPath.kCloseVerb:
        break;
      case SPath.kDoneVerb:
        assert(_verbIndex == pathRef.countVerbs());
        break;
      default:
        throw FormatException('Unsupport Path verb $verb');
    }
    return verb;
  }

  double get conicWeight => pathRef._conicWeights[_conicWeightIndex];

  int peek() => _verbIndex < pathRef.countVerbs() ? pathRef.fVerbs[_verbIndex]
      : SPath.kDoneVerb;
}

class _Corner {
  static const int kUpperLeft = 0;
  static const int kUpperRight = 1;
  static const int kLowerRight = 2;
  static const int kLowerLeft = 3;
}
