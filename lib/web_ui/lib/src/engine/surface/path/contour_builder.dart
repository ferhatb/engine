// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

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
  OpContourBuilder() : _fContour = OpContour();

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
  OpContour();

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
  OpContour? _next;
  // First half of build is marked false, second half true.
  bool? _operand;
  // True if operand (contour) needs to be xor'd for evenOdd.
  bool? _xor;

  List<OpSegment> get debugSegments => _segments;
}

class OpSegment {
  OpSegment(this.points, this.verb, this.parent, this.weight, this.bounds);

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

  final Float32List points;
  final int verb;
  final OpContour parent;
  final double weight;
  final ui.Rect bounds;
}

/// Base class for segment span.
class OpSpanBase {
  OpSpanBase(this.fSegment);
  /// List of points and t values associated with the start of this span.
  List<OpPtT>? fPtT;
  /// List of coincident spans that end here (may point to itself).
  List<OpSpanBase>? fCoinEnd;
  final OpSegment fSegment;
  /// Points to next angle from span start to end.
  ///
  /// HandleCoincidences calculates angles for all contours/segments and sorts
  /// by angles.
  /// Segment calcAngles, iterates through each span and sets the fromAngle.
  OpAngle? fFromAngle;
  /// Previous intersection point.
  OpSpan? _fPrev;
}

class OpSpan extends OpSpanBase {
  OpSpan(OpSegment fSegment) : super(fSegment);
  /// Linked list of spans coincident with this one.
  OpSpan? fCoincident;
  /// Next angle from span start to end.
  OpAngle? toAngle;
  /// Next intersection point
  OpSpanBase? fNext;
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
class OpPtT {
  final double fT;
  final ui.Offset fPt;
  final OpSpanBase _parent;

  OpPtT(this._parent, this.fPt, this.fT);
  OpSpanBase get span => _parent;
}
