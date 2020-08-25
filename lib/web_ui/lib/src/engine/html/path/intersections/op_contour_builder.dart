// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

const bool kDebugWinding = true;
const bool kDebugCoincidence = true;
const bool kDebugCoincidenceOrder = true;
const bool kDebugSort = true;
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

//  void rayCheck(OpRayHit base, int opRaydir, List<OpRayHit> hits) {
//    // if the bounds extreme is outside the best, we're done
//    double baseXY = (opRayDir & 1) == 0 ? base.fPt.dx : base.fPt.dy;
//    double boundsXY = rectSide(bounds, opRaydir);
//    bool checkLessThan = lessThan(opRaydir);
//    if (!approximatelyEqualT(baseXY, boundsXY) && (baseXY < boundsXY) == checkLessThan) {
//      return;
//    }
//    OpSegment? testSegment = fHead;
//    do {
//      testSegment!.rayCheck(base, opRayDir, hits);
//    } while ((testSegment = testSegment.next) != null);
//  }

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
