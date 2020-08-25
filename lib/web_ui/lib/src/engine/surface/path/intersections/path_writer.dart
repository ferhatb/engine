// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// Constructs a path one contour at a time.
///
/// If contour is closed, it copies it to final output SurfacePath.
/// Otherwise, keeps the partial contour for later assembly.
///
/// Typical usage:
///   writer = SPathWriter(SurfacePath());
///   writer.conicTo/cubicTo/quadTo/deferredMove/deferredLine
///   writer.assemble();
///
class SPathWriter {
  SPathWriter(this.fPath);

  // Path under construction.
  SurfacePath fCurrent = SurfacePath();
  // Contours with mismatched starts and ends.
  List<SurfacePath> fPartials = [];
  // Possible points for partial starts and ends.
  List<OpPtT> fEndPtTs = [];
  // Closed contour target.
  final SurfacePath fPath;
  // Deferred move and line points.
  OpPtT? fDeferMove, fDeferLine;
  // First line in current contour.
  OpPtT? fFirstPtT;


}