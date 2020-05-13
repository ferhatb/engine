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
    fBoundsIsDirty = true;    // this also invalidates fIsFinite
    fSegmentMask = 0;
    fIsOval = false;
    fIsRRect = false;
    // The next two values don't matter unless fIsOval or fIsRRect are true.
    fRRectOrOvalIsCCW = false;
    fRRectOrOvalStartIdx = 0xAC;
    assert(() {
      debugValidate();
      return true;
    }());
  }

  /// Gets a path ref with no verbs or points.
  static PathRef createEmpty() => _empty;
  static final PathRef _empty = PathRef()..computeBounds();
  static PathRef gEmpty = null;

  ///  Returns true if all of the points in this path are finite, meaning
  ///  there are no infinities and no NaNs.
  bool get isFinite {
    if (fBoundsIsDirty) {
      computeBounds();
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
  ui.RRect getRRect() => fIsRRect ? _getRRect() : null;
  bool get isRectCCW => fRRectOrOvalIsCCW;

  bool get hasComputedBounds => !fBoundsIsDirty;

  /// Returns the bounds of the path's points. If the path contains 0 or 1
  /// points, the bounds is set to (0,0,0,0), and isEmpty() will return true.
  /// Note: this bounds may be larger than the actual shape, since curves
  /// do not extend as far as their control points.
  ui.Rect getBounds() {
    if (fBoundsIsDirty) {
      computeBounds();
    }
    return fBounds;
  }

  // Reconstructs RRect from path commands.
  //
  // Expect 4 Conics and lines between.
  // Use conic points to calculate corner radius.
  ui.RRect _getRRect() {
    ui.Rect bounds = getBounds();
    final int verbCount = fVerbs.length;
    int pointIndex = 0;
    for (int verbIndex = 0; verbIndex < verbCount; verbIndex++) {
      final int verb = fVerbs[verbIndex];
      if (verb == SPath.kDoneVerb) {
        break;
      }
      if (verb == SPath.kConicVerb) {
        
      } else {
        assert((verb == SPath.kLineVerb &&
                (fPoints[pointIndex].dx != fPoints[pointIndex + 1].dx ||
                fPoints[pointIndex].dy != fPoints[pointIndex + 1]))
                || verb ==SPath.kCloseVerb);
      }
    }
    SkVector radii[4] = {{0, 0}, {0, 0}, {0, 0}, {0, 0}};
    Iter iter(*this);
    SkPoint pts[4];
    uint8_t verb = iter.next(pts);
    SkASSERT(SkPath::kMove_Verb == verb);
    while ((verb = iter.next(pts)) != SkPath::kDone_Verb) {
        if (SkPath::kConic_Verb == verb) {
            SkVector v1_0 = pts[1] - pts[0];
            SkVector v2_1 = pts[2] - pts[1];
            SkVector dxdy;
            if (v1_0.fX) {
                SkASSERT(!v2_1.fX && !v1_0.fY);
                dxdy.set(SkScalarAbs(v1_0.fX), SkScalarAbs(v2_1.fY));
            } else if (!v1_0.fY) {
                SkASSERT(!v2_1.fX || !v2_1.fY);
                dxdy.set(SkScalarAbs(v2_1.fX), SkScalarAbs(v2_1.fY));
            } else {
                SkASSERT(!v2_1.fY);
                dxdy.set(SkScalarAbs(v2_1.fX), SkScalarAbs(v1_0.fY));
            }
            SkRRect::Corner corner =
                    pts[1].fX == bounds.fLeft ?
                        pts[1].fY == bounds.fTop ?
                            SkRRect::kUpperLeft_Corner : SkRRect::kLowerLeft_Corner :
                    pts[1].fY == bounds.fTop ?
                            SkRRect::kUpperRight_Corner : SkRRect::kLowerRight_Corner;
            SkASSERT(!radii[corner].fX && !radii[corner].fY);
            radii[corner] = dxdy;
        } else {
            SkASSERT((verb == SkPath::kLine_Verb
                    && (!(pts[1].fX - pts[0].fX) || !(pts[1].fY - pts[0].fY)))
                    || verb == SkPath::kClose_Verb);
        }
    }
    SkRRect rrect;
    rrect.setRectRadii(bounds, radii);
    return ui.RRect.fromRectAndCorners(rect);
  }

  /// Transforms a path ref by a matrix, allocating a new one only if
  /// necessary.
  static void createTransformedCopy(PathRef dst, PathRef src, Matrix4 matrix) {
    // TODO
  }

  /// Rollsback a path ref to zero verbs and points with the assumption that
  /// the path ref will be repopulated with approximately the same number of
  /// verbs and points. A new path ref is created only if necessary.
  static void rewind(PathRef pathRef) {
    // TODO
  }

  int countPoints() => fPoints.length;
  int countVerbs() => fVerbs.length;
  int countWeights() => fConicWeights.length;

  /// Returns a pointer one beyond the first logical verb (last verb in memory order).
  int verbsBegin() return fVerbs.begin();

  /// Returns a const pointer to the first verb in memory (which is the last logical verb).
  int verbsEnd() { return fVerbs.end(); }

  /// Returns a const pointer to the first point.
  List<ui.Offset> get points => fPoints;

  /// Shortcut for this->points() + this->countPoints()
  // TODO const SkPoint* pointsEnd() const { return this->points() + this->countPoints(); }

  List<double> conicWeights() {
    // TODO
  }
  List<double> conicWeightsEnd() {
    // TODO
  }

  /// Convenience methods for getting to a verb or point by index.
  int atVerb(int index) { return fVerbs[index]; }
  ui.Offset atPoint(int index) { return ui.Offset(fPoints[index].dx, fPoints[index].dy); }

  bool operator==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType)
      return false;
    // TODO
  }

  /// Writes the path points and verbs to a buffer.
  void writeToBuffer(SkWBuffer buffer) {
    // TODO
  }

  /// Gets the number of bytes that would be written in writeBuffer()
  int writeSize() {
    // TODO
  }

  void interpolate(PathRef ending, double weight, PathRef out) {
    // TODO
  }

  void copy(PathRef ref, int additionalReserveVerbs,
      int additionalReservePoints) {
    // TODO
  }

  // Doesn't read fSegmentMask, but (re)computes it from the verbs array
  int computeSegmentMask() {
    // TODO
  }

  // Return true if the computed bounds are finite.
  static bool _computePtBounds(ui.Rect bounds, PathRef ref) {
      return bounds.setBoundsCheck(ref.points, ref.countPoints());
  }

  // called, if dirty, by getBounds()
  void computeBounds() {
    debugValidate();
    // TODO(mtklein): remove fBoundsIsDirty and fIsFinite,
    // using an inverted rect instead of fBoundsIsDirty and always recalculating fIsFinite.
    assert(fBoundsIsDirty);

    fIsFinite = _computePtBounds(&fBounds, this);
    fBoundsIsDirty = false;
  }

  void setBounds(ui.Rect rect) {
    assert(rect.left <= rect.right && rect.top <= rect.bottom);
    fBounds = rect;
    fBoundsIsDirty = false;
    fIsFinite = _isRectFinite(fBounds);
  }

  /// Makes additional room but does not change the counts.
  void incReserve(int additionalVerbs, int additionalPoints) {
    debugValidate();
    fPoints.setReserve(fPoints.count() + additionalPoints);
    fVerbs.setReserve(fVerbs.count() + additionalVerbs);
    debugValidate();
  }

  /// Resets the path ref with verbCount verbs and pointCount points, all
  /// uninitialized. Also allocates space for reserveVerb additional verbs
  /// and reservePoints additional points.
  void resetToSize(int verbCount, int pointCount, int conicCount,
                     [int reserveVerbs = 0, int reservePoints = 0]) {
    debugValidate();
    fBoundsIsDirty = true;      // this also invalidates fIsFinite
    fGenerationID = 0;

    fSegmentMask = 0;
    fIsOval = false;
    fIsRRect = false;

    fPoints.setReserve(pointCount + reservePoints);
    fPoints.setCount(pointCount);
    fVerbs.setReserve(verbCount + reserveVerbs);
    fVerbs.setCount(verbCount);
    fConicWeights.setCount(conicCount);
    debugValidate();
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
      case SPath.kDone_Verb:
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
    fIsOval = false;
    fIsRRect = false;

    fVerbs.add(verb);
    if (SPath.kConicVerb == verb) {
      fConicWeights.add(weight);
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
      case SPath.kDone_Verb:
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
    fIsOval = false;
    fIsRRect = false;

    fVerbs.add(verb);
    if (SPath.kConicVerb == verb) {
      for (int i = pCnt; i > 0; --i) {
        fConicWeights.add(null);
      }
    }
    int pts = fPoints.length;
    for (int i = pCnt; i > 0; --i) {
      fPoints.add(null);
    }
    debugValidate();
    return pts;
  }

  /// Concatenates all verbs from 'path' onto our own verbs array. Increases the point count by the
  /// number of points in 'path', and the conic weight count by the number of conics in 'path'.
  ///
  /// Returns pointers to the uninitialized points and conic weights data.
  int growForVerbsInPath(PathRef path) {
    // TODO
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

  void setIsRRect(bool isRRect, bool isCCW, int start) {
    fIsRRect = isRRect;
    fRRectOrOvalIsCCW = isCCW;
    fRRectOrOvalStartIdx = start;
  }

  List<ui.Offset> getPoints() {
    debugValidate();
    return fPoints;
  }

  static const int kMinSize = 256;

  ui.Rect   fBounds;

  List<ui.Offset>  fPoints;
  List<int>  fVerbs;
  List<double> fConicWeights;

  bool fBoundsIsDirty;
  bool fIsFinite;    // only meaningful if bounds are valid

  bool fIsOval;
  bool fIsRRect;
  // Both the circle and rrect special cases have a notion of direction and starting point
  // The next two variables store that information for either.
  bool fRRectOrOvalIsCCW;
  int  fRRectOrOvalStartIdx;
  int  fSegmentMask;

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
            pointY < boundsTop || pointY > boundsBottom)) {
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

  bool debugValidate() {
    assert(isValid);
  }

};

typedef SkIDChangeListener = void Function();

class SkWBuffer {
}

// Return true if all components of offset are finite.
bool _isPointFinite(ui.Offset offset) {
  double accum = 0;
  accum *= offset.dx;
  accum *= offset.dy;
  return !accum.isNaN;
}

bool _isRectFinite(ui.Rect rect) {
    double accum = 0;
    accum *= rect.left;
    accum *= rect.top;
    accum *= rect.right;
    accum *= rect.bottom;
    return !accum.isNaN;
}
