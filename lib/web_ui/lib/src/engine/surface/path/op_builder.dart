// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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
class OpEdgeBuilder {
  OpEdgeBuilder(this.path, this.globalState, {this.allowOpenContours = false}) {
    init();
  }

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
          break;
        case SPath.kLineVerb:
          double x = _forceSmallToZero(points[2]);
          double y = _forceSmallToZero(points[3]);

          break;
        case SPath.kCubicVerb:
          break;
        case SPath.kQuadVerb:
          break;
        case SPath.kConicVerb:
          break;
        case SPath.kCloseVerb:
          break;
        default:
          throw UnimplementedError('Unknown path verb $verb');
      }
    }
    throw UnimplementedError('');
  }

  void _closeContour(double curveEndX, double curveEndY, double curveStartX, double curveStartY) {
    if (!SkDPoint::ApproximatelyEqual(curveEnd, curveStart)) {
        *fPathVerbs.append() = SkPath::kLine_Verb;
        *fPathPts.append() = curveStart;
    } else {
        int verbCount = fPathVerbs.count();
        int ptsCount = fPathPts.count();
        if (SkPath::kLine_Verb == fPathVerbs[verbCount - 1]
                && fPathPts[ptsCount - 2] == curveStart) {
            fPathVerbs.pop();
            fPathPts.pop();
        } else {
            fPathPts[ptsCount - 1] = curveStart;
        }
    }
    *fPathVerbs.append() = SkPath::kClose_Verb;
}

  bool finish() {
    throw UnimplementedError('');
  }

  SurfacePath path;
  OpGlobalState globalState;
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
}

double _forceSmallToZero(double value) =>
    value.abs() < kFltEpsilonOrderableErr ? 0 : value;

class OpContourBuilder {

}

class OpContour {
}
