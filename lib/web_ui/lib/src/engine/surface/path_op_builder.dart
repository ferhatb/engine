// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
part of engine;

/// Perform a series of path operations, optimized for unioning many
/// paths together.
class PathOpBuilder {
  /// Add one or more paths and their operand. The builder is empty before the
  /// first path is added, so the result of a single add is (emptyPath OP path).
  void add(SurfacePath path, ui.PathOperation operator) {
  }

  /// Computes the sum of all paths and operands, and resets the builder to its
  ///    initial state.
  bool resolve(SurfacePath result) {
    return false;
  }

  List<SurfacePath> fPathRefs;
  List<ui.PathOperation> fOps;
  static bool _fixWinding(SurfacePath path) {
    throw new UnimplementedError();
  }
  static void _reversePath(SurfacePath path) {
    //Offset path._lastPoint();
  }

  void _reset() {
  }
}

/// Set this path to the result of applying the Op to this path and the
/// specified path: this = (this op operand).
///
/// The resulting path will be constructed from non-overlapping contours.
/// The curve order is reduced where possible so that cubics may be turned
/// into quadratics, and quadratics maybe turned into lines.
///
/// Returns true if operation was able to produce a result;
/// otherwise, result is unmodified.
/// For difference operator [one] is minuend and [two] is subtrahend.
SurfacePath Op(SurfacePath one, SurfacePath two, ui.PathOperation op) {
  throw new UnimplementedError();
}

/// Set this path to a set of non-overlapping contours that describe the
/// same area as the original path.
/// The curve order is reduced where possible so that cubics may
/// be turned into quadratics, and quadratics maybe turned into lines.
///
/// Returns true if operation was able to produce a result;
/// otherwise, result is unmodified.
SurfacePath Simplify(SurfacePath path) {
  throw new UnimplementedError();
}

/// Set the resulting rectangle to the tight bounds of the path.
ui.Rect TightBounds(SurfacePath path) {
  throw new UnimplementedError();
}

/// Set the result with fill type winding to area equivalent to path.
/// Returns true if successful. Does not detect if path contains contours which
/// contain self-crossings or cross other contours; in these cases, may return
/// true even though result does not fill same area as path.
///
/// Returns true if operation was able to produce a result;
/// otherwise, result is unmodified. The result may be the input.
SurfacePath AsWinding(SurfacePath path) {
  throw new UnimplementedError();
}
