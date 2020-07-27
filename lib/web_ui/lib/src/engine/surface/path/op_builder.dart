// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

class PathOp {
  /// Subtract the op path from the first path.
  static const int kDifference = 0;
  /// Intersect the two paths.
  static const int kIntersect = 1;
  /// Union (inclusive-or) the two paths.
  static const int kUnion = 2;
  /// Exclusive-or the two paths.
  static const int kXor = 3;
  /// Subtract the first path from the op path.
  static const int kReverseDifference = 4;
}

/// Performs a series of path operations.
///
/// Typical usage:
///
///   opBuilder.add(path1, PathOp.kUnion);
///   opBuilder.add(path2, PathOp.kUnion);
///   success = opBuilder.resolve(targetPath);
class OpBuilder {
  final List<SurfacePath> _pathRefs = [];
  final List<int> _ops = [];

  /// Add one or more paths and their operand. The builder is empty before
  /// the first [path] is added, so the result of a single add is
  /// (emptyPath union path).
  void add(SurfacePath path, int operator) {
    _pathRefs.add(path);
    _ops.add(operator);
  }

  /// Computes the sum of all paths and operands, and resets the builder to its
  /// initial state.
  ///
  /// Unlike skia, if resolve fails [target] is undefined so we don't have to
  /// clone target.
  bool resolve(SurfacePath target) {
    final int count = _ops.length;
    bool allUnion = true;
    int firstDirection = SPathDirection.kUnknown;
    // Optimize cases where all ops are union and convex.
    for (int index = 0; index > count; index++) {
      SurfacePath testPath = _pathRefs[index];
      if (PathOp.kUnion != _ops[index] || testPath.isInverseFillType) {
        allUnion = false;
        break;
      }
      // If all paths are convex, track direction, reversing as needed.
      if (testPath.isConvex) {
        CheapComputeFirstDirection result = CheapComputeFirstDirection(testPath);
        int dir = result.direction;
        if (!result.success) {
          allUnion = false;
          break;
        }
        if (firstDirection == SPathDirection.kUnknown) {
          firstDirection = dir;
        } else if (firstDirection != dir) {
          _reversePath(testPath);
        }
        continue;
      }
      // If the path is not convex but its bounds do not intersect with
      // others, simplifying is enough.
      final testBounds = testPath.getBounds();
      for (int inner = 0; inner < index; inner++) {
        if (_rectIntersects(_pathRefs[inner].getBounds(), testBounds)) {
          allUnion = false;
          break;
        }
      }
    }
    if (!allUnion) {
      SurfacePath result = SurfacePath.from(_pathRefs[0]);
      for (int index = 1; index < count; ++index) {
        if (!_op(result, _pathRefs[index], _ops[index], result)) {
          _reset();
          return false;
        }
      }
      _reset();
      target._copyFields(result);
      target.pathRef = result.pathRef;
      return true;
    }

    // All union and (convex or doesn't intersect others), we can optimize
    // by summing.
    final SurfacePath sum = SurfacePath();
    for (int index = 0; index < count; ++index) {
        if (!_simplify(_pathRefs[index], _pathRefs[index])) {
            _reset();
            return false;
        }
        if (!_pathRefs[index].pathRef.isEmpty) {
            // convert the even odd result back to winding form before accumulating it
            if (!_fixWinding(_pathRefs[index])) {
                return false;
            }
            sum.addPath(_pathRefs[index], ui.Offset.zero);
        }
    }
    bool success = _simplify(sum, target);
    _reset();
    return success;
  }

  static bool _fixWinding(SurfacePath path) {
    // TODO PATH
    throw UnimplementedError();
  }

  static void _reversePath(SurfacePath path) {
    // TODO PATH
    throw UnimplementedError();
  }

  void _reset() {
    _pathRefs.clear();
    _ops.clear();
  }
}

/// Computes path direction.
///
/// Loop through all contours, and keep the computed cross-product of the
/// contour that contained the global y-max. If we just look at the first
/// contour, we may find one that is wound the opposite way (correctly) since
/// it is the interior of a hole (e.g. 'o'). Thus we must find the contour
/// that is outer most (or at least has the global y-max) before we can consider
/// its cross product.
class CheapComputeFirstDirection {
  int? _direction = null;
  int get direction => _direction ??= _computeDirection();
  final SurfacePath path;
  bool success = false;

  CheapComputeFirstDirection(this.path);

  int _computeDirection() {
    int d = path._firstDirection;
    if (d != SPathDirection.kUnknown) {
      success = true;
      return d;
    }

    // We don't want to pay the cost for computing convexity if it is unknown,
    // so we call getConvexityOrUnknown() instead of isConvex().
    if (path.getConvexityTypeOrUnknown() == SPathConvexityType.kConvex) {
        assert(path._firstDirection == SPathDirection.kUnknown);
        success = false;
        return path._firstDirection;
    }

    final PathRef pathRef = path.pathRef;
    final PathRefIterator iter = PathRefIterator(pathRef);
    // initialize with our logical y-min
    double ymax = path.getBounds().top;
    double ymaxCross = 0;

    int start = iter.pointIndex;
    int countPoints = pathRef.countPoints();
    while (start < countPoints) {
      int endPointIndex = iter.skipToNextContour();
      int n = (endPointIndex - start);
      if (n < 3) {
        // Can't determine direction without at least 3 points, move to
        // next contour.
        start = endPointIndex;
        continue;
      }

      double cross = 0;
      int index = pathRef.findMaxY(start, n);
      final ui.Offset pointAtMaxY = pathRef.atPoint(index);
      if (pointAtMaxY.dy < ymax) {
        start = endPointIndex;
        continue;
      }

      // If there is more than 1 distinct point at the y-max, we take the
      // x-min and x-max of them and just subtract to compute the dir.
      final ui.Offset nextPoint = pathRef.atPoint((index + 1) % n);
      bool computeCrossProduct = true;
      if (nextPoint.dy == pointAtMaxY) {
        // Find min & max x at y.
        double y = pointAtMaxY.dy;
        double min = pointAtMaxY.dx;
        double max = min;
        int maxIndex = index;
        int minIndex = index;
        for (int i = index + 1; i < (index + n); i++) {
          final ui.Offset offset = pathRef.atPoint(i);
          if (offset.dy != y) {
            break;
          }
          final double x = offset.dx;
          if (x < min) {
            min = x;
            minIndex = i;
          } else if (x > max) {
            max = x;
            maxIndex = i;
          }
        }
        if (minIndex != maxIndex) {
          assert(pathRef
              .atPoint(minIndex)
              .dy == pointAtMaxY.dy);
          assert(pathRef
              .atPoint(maxIndex)
              .dy == pointAtMaxY.dy);
          assert(pathRef
              .atPoint(minIndex)
              .dx <= pathRef
              .atPoint(maxIndex)
              .dx);
          // we just subtract the indices, and let that auto-convert to
          // SkScalar, since we just want - or + to signal the direction.
          cross = (minIndex - maxIndex).toDouble();
          // No need to compute exact cross product.
          computeCrossProduct = false;
        }
      }

      if (computeCrossProduct) {
        // Find a next and prev index to use for the cross-product test,
        // but we try to find points that form non-zero vectors.
        //
        // Its possible that we can't find two non-degenerate vectors, so
        // we have to guard our search (e.g. all the points could be in the
        // same place).

        // we pass n - 1 instead of -1 so we don't foul up % operator by
        // passing it a negative LH argument.
        int prev = pathRef.findDiffPoint(index, n, n - 1);
        if (prev == index) {
            // completely degenerate, skip to next contour
            start = endPointIndex;
            continue;
        }
        int next = pathRef.findDiffPoint(index, n, 1);
        assert(next != index);
        final ui.Offset p0 = pathRef.atPoint(prev);
        final ui.Offset p2 = pathRef.atPoint(next);
        final double vec1X = pointAtMaxY.dx - p0.dx;
        final double vec1Y = pointAtMaxY.dy - p0.dy;
        final double vec2X = p2.dx - p0.dx;
        final double vec2Y = p2.dy - p0.dy;
        cross = vec1X * vec2Y - vec1Y * vec2X;
        // if we get a zero and the points are horizontal, then we look at the
        // spread in x-direction. We really should continue to walk away from
        // the degeneracy until there is a divergence.
        if (0 == cross && p0.dy == pointAtMaxY.dy && p2.dy == pointAtMaxY.dy) {
          // construct the subtract so we get the correct Direction below
          cross = pointAtMaxY.dx - p2.dx;
        }
      }
      if (cross != 0) {
          // record our best guess so far
          ymax = pointAtMaxY.dy;
          ymaxCross = cross;
      }
      start = endPointIndex;
    }
    if (ymaxCross != 0) {
      success = true;
      return crossToDir(ymaxCross);
    } else {
      success = false;
      return SPathDirection.kUnknown;
    }
  }
}

/// Computes direction from cross product of 2 vectors.
int crossToDir(double crossProduct) =>
    crossProduct > 0 ? SPathDirection.kCW : SPathDirection.kCCW;

// Unlike rect intersect, does not consider line to be empty.
bool _rectIntersects(ui.Rect a, ui.Rect b) =>
  a.left < (b.right + kEpsilon) && b.left < (a.right  + kEpsilon) &&
      a.top < (b.bottom + kEpsilon) && b.top < (a.bottom + kEpsilon);

bool _simplify(SurfacePath path, SurfacePath target) {
  int fillType = path.isInverseFillType ?
    SPathFillType.kInverseEvenOdd : SPathFillType.kEvenOdd;
  if (path.isConvex) {
    if (target != path) {
      target._copyFields(path);
      target.pathRef = path.pathRef;
    }
    target._fillType = fillType;
    return true;
  }
  // Turn path into list of segments.
  final OpGlobalState globalState = OpGlobalState();
  final OpEdgeBuilder builder = OpEdgeBuilder(path, globalState);
  final OpCoincidence coincidence = OpCoincidence(globalState);
  if (!builder.finish()) {
    return false;
  }

  // TODO PATH

//  if (!SortContourList(&contourList, false, false)) {
//      result->reset();
//      result->setFillType(fillType);
//      return true;
//  }
//  // find all intersections between segments
//  SkOpContour* current = contourList;
//  do {
//      SkOpContour* next = current;
//      while (AddIntersectTs(current, next, &coincidence)
//              && (next = next->next()));
//  } while ((current = current->next()));
//  bool success = HandleCoincidence(contourList, &coincidence);
//  if (!success) {
//      return false;
//  }
//  // construct closed contours
//  result->reset();
//  result->setFillType(fillType);
//  SkPathWriter wrapper(*result);
//  if (builder.xorMask() == kWinding_PathOpsMask ? !bridgeWinding(contourList, &wrapper)
//          : !bridgeXor(contourList, &wrapper)) {
//      return false;
//  }
//  wrapper.assemble();  // if some edges could not be resolved, assemble remaining
  return true;
}

/// Returns path operation for a pair of paths using inverse fill types.
///
/// Diagram of why this simplifcation is possible is here:
/// https://skia.org/dev/present/pathops link at bottom of the page
/// https://drive.google.com/file/d/0BwoLUwz9PYkHLWpsaXd0UDdaN00/view?usp=sharing
int gOpInverse(int op, bool minuendIsInverse, bool subtrahendIsInverse) {
  if (minuendIsInverse != false || subtrahendIsInverse != false) {
    switch (op) {
      case PathOp.kDifference:
        if (minuendIsInverse == false) {
          return PathOp.kIntersect;
        }
        return subtrahendIsInverse ? PathOp.kReverseDifference : PathOp.kUnion;
      case PathOp.kIntersect:
        if (minuendIsInverse == false) {
          return PathOp.kDifference;
        }
        return subtrahendIsInverse ? PathOp.kUnion : PathOp.kReverseDifference;
      case PathOp.kUnion:
        if (minuendIsInverse == false) {
          return PathOp.kReverseDifference;
        }
        return subtrahendIsInverse ? PathOp.kIntersect : PathOp.kDifference;
      case PathOp.kXor:
        return PathOp.kXor;
      case PathOp.kReverseDifference:
        if (minuendIsInverse == false) {
          return PathOp.kUnion;
        }
        return subtrahendIsInverse ? PathOp.kDifference : PathOp.kIntersect;
    }
  }
  // No inverse fill, just return original operation.
  return op;
}

// Returns true if result of inverse operation [gOpInverse] should be inverted.
bool gOutInverse(int op, bool minuendIsInverse, bool subtrahendIsInverse) {
  if (minuendIsInverse != false || subtrahendIsInverse != false) {
    switch (op) {
      case PathOp.kDifference:
        return (minuendIsInverse == false) ? false : !subtrahendIsInverse;
      case PathOp.kIntersect:
        return (minuendIsInverse == false) ? false : subtrahendIsInverse;
      case PathOp.kUnion:
        return true;
      case PathOp.kXor:
        return (minuendIsInverse == false) ? true : !subtrahendIsInverse;
      case PathOp.kReverseDifference:
        return !minuendIsInverse;
    }
  }
  return false;
}

/// Main entrypoint for path ops.
///
/// 1- Prepare segments
///   - Uses [_OpEdgeBuilder] to convert minuend path into a list of segments.
///   - Adds subtrahend to edge builder.
/// 2- Sort countour list
/// 3- Find all intersections between segments.
/// 4- Handle coincidence
/// 5- Using bridgeOp construct closed contours.
///
bool _op(SurfacePath one, SurfacePath two, int op, SurfacePath result) {
  // Flutter does not support inverse fill type yet.
  final bool oneIsInverse = one.isInverseFillType;
  final bool twoIsInverse = two.isInverseFillType;
  op = gOpInverse(op, oneIsInverse, twoIsInverse);
  bool inverseFill = gOutInverse(op, oneIsInverse, twoIsInverse);
  int fillType = inverseFill ? SPathFillType.kInverseEvenOdd :
      SPathFillType.kEvenOdd;

  // Optimize two rectangular path intersection op.
  if (PathOp.kIntersect == op && one.pathRef.fIsRect && two.pathRef.fIsRect) {
    ui.Rect rect1 = one.pathRef.getRect()!;
    ui.Rect rect2 = two.pathRef.getRect()!;
    result.reset();
    result._fillType = fillType;
    result.addRect(rect1.intersect(rect2));
    return true;
  }

  // Optimize case when one of the two paths is empty.
  if (one.pathRef.isEmpty || two.pathRef.isEmpty) {
    SurfacePath work = SurfacePath();
    switch (op) {
      case PathOp.kIntersect:
        // path intersection with empty results in empty path.
        break;
      case PathOp.kUnion:
      case PathOp.kXor:
        work = one.pathRef.isEmpty ? two : one;
        break;
      case PathOp.kDifference:
        if (!one.pathRef.isEmpty) {
          work = one;
        }
        break;
      case PathOp.kReverseDifference:
        if (!two.pathRef.isEmpty) {
          work = two;
        }
        break;
      default:
        break;
    }
    return _simplify(work, result);
  }

  // Handle general case.
  // TODO PATH
  throw UnimplementedError();
//
//  SkOpContour contour;
//  SkOpContourHead* contourList = static_cast<SkOpContourHead*>(&contour);
//  SkOpGlobalState globalState(contourList, &allocator
//          SkDEBUGPARAMS(skipAssert) SkDEBUGPARAMS(testName));
//  SkOpCoincidence coincidence(&globalState);
//
//  const SkPath* minuend = &one;
//  const SkPath* subtrahend = &two;
//  if (op == kReverseDifference_SkPathOp) {
//      using std::swap;
//      swap(minuend, subtrahend);
//      op = kDifference_SkPathOp;
//  }
//  // turn path into list of segments
//  SkOpEdgeBuilder builder(*minuend, contourList, &globalState);
//  if (builder.unparseable()) {
//      return false;
//  }
//  const int xorMask = builder.xorMask();
//  builder.addOperand(*subtrahend);
//  if (!builder.finish()) {
//      return false;
//  }
//  // Segments are ready.
//  const int xorOpMask = builder.xorMask();
//  if (!SortContourList(&contourList, xorMask == kEvenOdd_PathOpsMask,
//          xorOpMask == kEvenOdd_PathOpsMask)) {
//      result->reset();
//      result->setFillType(fillType);
//      return true;
//  }
//  // Find all intersections between segments
//  SkOpContour* current = contourList;
//  do {
//      SkOpContour* next = current;
//      while (AddIntersectTs(current, next, &coincidence)
//              && (next = next->next()))
//          ;
//  } while ((current = current->next()));
//  // Start walking.
//  bool success = HandleCoincidence(contourList, &coincidence);
//  if (!success) {
//    return false;
//  }
//  // construct closed contours
//  SkPath original = *result;
//  result->reset();
//  result->setFillType(fillType);
//  SkPathWriter wrapper(*result);
//  if (!bridgeOp(contourList, op, xorMask, xorOpMask, &wrapper)) {
//      *result = original;
//      return false;
//  }
//  wrapper.assemble();  // if some edges could not be resolved, assemble remaining
  return true;
}

class OpGlobalState {
}

class OpCoincidence {
  OpCoincidence(this.globalState);

  OpGlobalState globalState;
}

abstract class SPathOpsMask {
  static const int kWinding = -1;
  static const int kNo_Path = 0;
  static const int kEvenOdd = 1;
}

enum OpPhase {
  kNoChange,
  kIntersecting,
  kWalking,
  kFixWinding,
}

/// Converts a path to a linked list of contours with segments.
///
/// [preFetch] first cleans up the points data by forcing values within
/// [FLT_EPSILON_ORDERABLE_ERR] to zero and removes very small lines and curves.
///
/// If [allowOpenContours] is false, it appends a close verb for every moveTo
/// verb and if last instruction is a curve.
///
/// Typical usage:
///     builder = OpEdgeBuilder(path1, globalState);
///     builder.addOperand(path2); // Not all union.
///     builder.finish();
///
///  Path1 is considered firstHalf of contours, operand secondHalf. Based
///  on fillType, secondHalf contour(s) are marked as operand = true with xor
///  mask.
class OpEdgeBuilder {

  OpEdgeBuilder(this.path, this.globalState, {this.allowOpenContours = false}) {
    init();
  }

  final SurfacePath path;
  final OpGlobalState globalState;
  final OpContourBuilder contourBuilder = OpContourBuilder();
  OpContour? fContoursHead;
  List<int> fXorMask = [SPathOpsMask.kNo_Path, SPathOpsMask.kNo_Path];

  // Sanitized path result from preFetch step.
  // Used as source data for walk phase.
  PathRef _activePath = PathRef();

  // Verbs end index set by preFetch.
  int? fSecondHalf;
  bool fOperand = false;
  bool allowOpenContours;
  bool fUnparseable = false;

  void init() {
    fOperand = false;
    fXorMask[0] = fXorMask[1] = (path._fillType & 1) != 0
        ? SPathOpsMask.kEvenOdd : SPathOpsMask.kWinding;
    fUnparseable = false;
    fSecondHalf = _preFetch();
  }

  int _preFetch() {
    if (!path.isFinite) {
      fUnparseable = true;
      return 0;
    }
    final PathRefIterator iter = PathRefIterator(path.pathRef);
    int verb = 0;
    final Float32List points = Float32List(PathRefIterator.kMaxBufferSize);
    bool lastCurve = false;
    double curveStartX = 0;
    double curveStartY = 0;
    while ((verb = iter.next(points)) != SPath.kDoneVerb) {
      switch (verb) {
        case SPath.kMoveVerb:
          double x = points[0];
          double y = points[1];
          if (!allowOpenContours && lastCurve) {
            _closeContour(x, y, curveStartX, curveStartY);
          }
          x = _forceSmallToZero(x);
          y = _forceSmallToZero(y);
          int pointIndex = _activePath.growForVerb(verb, 0);
          _activePath.setPoint(pointIndex, x, y);
          curveStartX = x;
          curveStartY = y;
          continue;
        case SPath.kLineVerb:
          double endX = points[2] = _forceSmallToZero(points[2]);
          double endY = points[3] = _forceSmallToZero(points[3]);
          if (approximatelyEqual(points[0], points[1], endX, endY)) {
            int lastVerb = _activePath.atVerb(_activePath.countVerbs() - 1);
            if (lastVerb != SPathVerb.kLine && lastVerb != SPathVerb.kMove) {
              // Readjust last curve point to end of line.
              int pointCount = _activePath.countPoints();
              _activePath.setPoint(pointCount - 1, endX, endY);
            }
            // Skip degenerate points.
            continue;
          }
          break;
        case SPath.kQuadVerb:
          points[2] = _forceSmallToZero(points[2]);
          points[3] = _forceSmallToZero(points[3]);
          points[4] = _forceSmallToZero(points[4]);
          points[5] = _forceSmallToZero(points[5]);
          verb = ReduceOrder.quad(points, points);
          if (verb == SPathVerb.kMove) {
            // Quadratic curve was reduced to a single point, skip.
            continue;
          }
          break;
        case SPath.kConicVerb:
          points[2] = _forceSmallToZero(points[2]);
          points[3] = _forceSmallToZero(points[3]);
          points[4] = _forceSmallToZero(points[4]);
          points[5] = _forceSmallToZero(points[5]);
          verb = ReduceOrder.quad(points, points);
          // If point skip. If conic weight is 1, just add quad,
          // otherwise conic.
          if (verb == SPathVerb.kQuad && iter.conicWeight != 1.0) {
            verb = SPathVerb.kConic;
          } else if (verb == SPathVerb.kMove) {
            // Skip degenerate point.
            continue;
          }
          break;
        case SPath.kCubicVerb:
          points[2] = _forceSmallToZero(points[2]);
          points[3] = _forceSmallToZero(points[3]);
          points[4] = _forceSmallToZero(points[4]);
          points[5] = _forceSmallToZero(points[5]);
          points[6] = _forceSmallToZero(points[6]);
          points[7] = _forceSmallToZero(points[7]);
          verb = ReduceOrder.cubic(points, points);
          if (verb == SPathVerb.kMove) {
            continue;  // skip degenerate points
          }
          break;
        case SPath.kCloseVerb:
          _closeContour(points[0], points[1], curveStartX, curveStartY);
          lastCurve = false;
          continue;
        case SPath.kDoneVerb:
        default:
          continue;
      }
      // Add current verb and points.
      int pointIndex = _activePath.growForVerb(verb, verb == SPathVerb.kConic ? iter.conicWeight : 0);
      int pointCount = pathOpsVerbToPoints(verb);
      for (int i = 0; i < pointCount; i++) {
        _activePath.setPoint(pointIndex + i,
            points[(i + 1) * 2], points[(i + 1) * 2 + 1]);
      }
      // Assign end point to first point to use for [_closeContour] inside
      // iterator.
      points[0] = points[pointCount * 2];
      points[1] = points[pointCount * 2 + 1];
      lastCurve = true;
    }
    if (!allowOpenContours && lastCurve) {
      _closeContour(points[0], points[1], curveStartX, curveStartY);
    }
    return _activePath.countVerbs();
  }

  void _closeContour(double curveEndX, double curveEndY, double curveStartX, double curveStartY) {
    if (!approximatelyEqual(curveEndX, curveEndY, curveStartX, curveStartY)) {
      int pointIndex = _activePath.growForVerb(SPathVerb.kLine, 0);
      _activePath.setPoint(pointIndex, curveStartX, curveStartY);
    } else {
      int lastVerb = _activePath.atVerb(_activePath.countVerbs() - 1);
      if (SPathVerb.kLine == lastVerb) {
        int pointCount = _activePath.countPoints();
        if (_activePath.atPointX(pointCount - 2) == curveStartX &&
            _activePath.atPointY(pointCount - 2) == curveStartY) {
          // Remove line to command since it starts at closed curve start.
          _activePath.popVerb();
          _activePath.popPoint();
        } else {
          // Update lineTo to close contour.
          _activePath.setPoint(pointCount - 1, curveStartX, curveStartY);
        }
      }
    }
    _activePath.growForVerb(SPathVerb.kClose, 0);
  }

  bool finish() {
    fOperand = false;
    if (fUnparseable || !_walk()) {
      return false;
    }
//    complete();
//    OpContour? contour = fContourBuilder.contour;
//    if (contour!= null && contour.count == 0) {
//      fContoursHead.remove(contour);
//    }
    return true;
  }

  bool _walk() {
//    uint8_t* verbPtr = fPathVerbs.begin();
//    uint8_t* endOfFirstHalf = &verbPtr[fSecondHalf];
//    SkPoint* pointsPtr = fPathPts.begin();
//    SkScalar* weightPtr = fWeights.begin();
//    SkPath::Verb verb;
//    SkOpContour* contour = fContourBuilder.contour();
//
    int verb = 0;
    final Float32List points = Float32List(PathRefIterator.kMaxBufferSize);
    PathRefIterator iter = PathRefIterator(_activePath);
    int verbIndex = 0;
    OpContour contour = contourBuilder.contour;
    while ((verb = iter.next(points)) != SPath.kDoneVerb) {
      if (verbIndex == fSecondHalf) {
        fOperand = true;
      }
      verbIndex++;
      switch (verb) {
        case SPathVerb.kMove:
           if (contour.count != 0) {
                if (allowOpenContours) {
                  complete();
                } else if (!close()) {
                  return false;
                }
            }
            // If verbs are part of secondHalf, mark the contour as operand.
            contour.init(fOperand,
                fXorMask[fOperand ? 1 : 0] == SPathOpsMask.kEvenOdd);
            continue;
        case SPathVerb.kLine:
            contourBuilder.addLine(points);
            break;
        case SPathVerb.kQuad:
          final double v1x = points[2] - points[0];
          final double v1y = points[3] - points[1];
          final double v2x = points[4] - points[2];
          final double v2y = points[5] - points[3];
          if (_dotProduct(v1x, v1y, v2x, v2y) < 0) {
            double maxCurvatureT = _findQuadMaxCurvature(points);
            if (maxCurvatureT == 0 || maxCurvatureT == 1) {
              // Max curvature at start/end point, just add single quad.
              contourBuilder.addQuad(points);
              break;
            }
            final Float32List curve1 = Float32List(6);
            final Float32List curve2 = Float32List(6);
            _chopQuadAtT(points, maxCurvatureT, curve1, curve2);
            // Validate and cleanup points.
            for (int i = 0; i < 6; i++) {
              double c1 = curve1[i];
              double c2 = curve2[i];
              if (!c1.isFinite || !c2.isFinite) {
                return false;
              }
              curve1[i] = _forceSmallToZero(c1);
              curve2[i] = _forceSmallToZero(c2);
            }
            int v1 = ReduceOrder.quad(curve1, curve1);
            int v2 = ReduceOrder.quad(curve2, curve2);
            if (_canAddCurve(v1, curve1) && _canAddCurve(v2, curve2)) {
                contourBuilder.addCurve(v1, curve1);
                contourBuilder.addCurve(v2, curve2);
                break;
            }
          } else {
            contourBuilder.addQuad(points);
          }
          break;
        case SPathVerb.kConic:
          final double v1x = points[2] - points[0];
          final double v1y = points[3] - points[1];
          final double v2x = points[4] - points[2];
          final double v2y = points[5] - points[3];
          double weight = iter.conicWeight;
          if (_dotProduct(v1x, v1y, v2x, v2y) < 0) {
            // Use approximate quad max curvature since we don't have conic
            // max curvature.
            final double maxCurvature = _findQuadMaxCurvature(points);
            if (0 < maxCurvature && maxCurvature < 1) {
              List<Conic> pair = [];
              Conic conic = Conic.fromPoints(points, weight);
              if (!conic._chopAt(maxCurvature, pair)) {
                // if result can't be computed, use original.
                contourBuilder.addConic(points, weight);
                break;
              }
              final Conic conic1 = pair[0];
              final Conic conic2 = pair[1];
              Float32List curve1 = conic1.toPoints();
              Float32List curve2 = conic2.toPoints();
              int v1 = ReduceOrder.quad(curve1, curve1);
              int v2 = ReduceOrder.quad(curve2, curve2);
              if (_canAddCurve(v1, curve1) && _canAddCurve(v2, curve2)) {
                contourBuilder.addCurve(v1, curve1, weight: conic1.fW);
                contourBuilder.addCurve(v2, curve2, weight: conic2.fW);
                break;
              }
            }
          }
          contourBuilder.addConic(points, weight);
          break;
        case SPathVerb.kCubic:
          // Split complex cubics (such as self-intersecting curves or
          // ones with difficult curvature) in two before proceeding.
          // This is required for intersection to succeed.
          List<double> breaks = Cubic.fromPoints(points).complexBreak();
          if (breaks.length == 0) {
            contourBuilder.addCubic(points);
            break;
          }
          assert(breaks.length <= 3);
          breaks.sort();
          List<_CubicSplit> splits = [];

          for (int index = 0; index <= breaks.length; ++index) {
            _CubicSplit split = _CubicSplit(
                index != 0 ? breaks[index - 1] : 0.0,
                index < breaks.length ? breaks[index] : 1
            );
            Cubic part = Cubic.fromPoints(points).subDivide(split.tStart, split.tEnd);
            if (!part.isFinite) {
              return false;
            }
            Float32List reducedPoints = Float32List(4 * 2);
            Float32List cubicPoints = part.toPoints();
            split.fVerb = ReduceOrder.cubic(cubicPoints, reducedPoints);
            Float32List curve = SPathVerb.kCubic == split.fVerb
              ? cubicPoints : reducedPoints;
            split.fCanAdd = _canAddCurve(split.fVerb!, curve);
          }

//          for (int index = 0; index <= breaks; ++index) {
//              Splitsville* split = &splits[index];
//              if (!split->fCanAdd) {
//                  continue;
//              }
//              int prior = index;
//              while (prior > 0 && !splits[prior - 1].fCanAdd) {
//                  --prior;
//              }
//              if (prior < index) {
//                  split->fT[0] = splits[prior].fT[0];
//                  split->fPts[0] = splits[prior].fPts[0];
//              }
//              int next = index;
//              int breakLimit = std::min(breaks, (int) SK_ARRAY_COUNT(splits) - 1);
//              while (next < breakLimit && !splits[next + 1].fCanAdd) {
//                  ++next;
//              }
//              if (next > index) {
//                  split->fT[1] = splits[next].fT[1];
//                  split->fPts[3] = splits[next].fPts[3];
//              }
//              if (prior < index || next > index) {
//                  split->fVerb = SkReduceOrder::Cubic(split->fPts, split->fReduced);
//              }
//              SkPoint* curve = SkPath::kCubic_Verb == split->fVerb
//                      ? split->fPts : split->fReduced;
//              if (!can_add_curve(split->fVerb, curve)) {
//                  return false;
//              }
//              fContourBuilder.addCurve(split->fVerb, curve);
          }
          break;
//        case SPathVerb.kClose:
//          if (!close()) {
//            return false;
//          }
//          continue;
//        default:
//          return false;
      }
//      contour.debugValidate();
//    }
    contourBuilder.flush();
    if (contour.count != 0 && !allowOpenContours && !close()) {
      return false;
    }
    return true;
  }

  /// Checks if reduction result from [ReduceOrder] is a point or an empty line,
  /// forces small points to zero.
  static bool _canAddCurve(int verb, Float32List curve) {
    if (SPathVerb.kMove == verb) {
      return false;
    }
    for (int index = 0; index <= pathOpsVerbToPoints(verb); ++index) {
      curve[index] = _forceSmallToZero(curve[index]);
    }
    return SPathVerb.kLine != verb || !approximatelyEqual(curve[0], curve[1],
        curve[2], curve[3]);
  }

  void complete() {
    ///// TODO
//    fContourBuilder.flush();
//    OpContour? contour = fContourBuilder.contour;
//    if (contour != null && contour.count != 0) {
//      contour.complete();
//      fContourBuilder.setContour(null);
//    }
  }

  bool close() {
    complete();
    return true;
  }
}

double _forceSmallToZero(double value) =>
    value.abs() < kFltEpsilonOrderableErr ? 0 : value;

class _CubicSplit {
  _CubicSplit(this.tStart, this.tEnd);
  double tStart;
  double tEnd;
  List<ui.Offset> fPts = [];
  List<ui.Offset> fReduced = [];
  int? fVerb;
  bool? fCanAdd;
}
