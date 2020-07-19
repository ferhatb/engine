// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of engine;

/// Chops a non-monotonic quadratic curve, returns subdivisions and writes
/// result into [buffer].
void _chopQuadAtT(Float32List buffer, double t, Float32List curve1, Float32List curve2) {
  final double x0 = buffer[0];
  final double y0 = buffer[1];
  final double x1 = buffer[2];
  final double y1 = buffer[3];
  final double x2 = buffer[4];
  final double y2 = buffer[5];
  // Chop quad at t value by interpolating along p0-p1 and p1-p2.
  double p01x = x0 + (t * (x1 - x0));
  double p01y = y0 + (t * (y1 - y0));
  double p12x = x1 + (t * (x2 - x1));
  double p12y = y1 + (t * (y2 - y1));
  double cx = p01x + (t * (p12x - p01x));
  double cy = p01y + (t * (p12y - p01y));
  curve1[0] = buffer[0];
  curve1[1] = buffer[0];
  curve1[2] = p01x;
  curve1[3] = p01y;
  curve1[4] = cx;
  curve1[5] = cy;
  curve2[0] = cx;
  curve2[1] = cy;
  buffer[6] = p12x;
  buffer[7] = p12y;
  buffer[8] = x2;
  buffer[9] = y2;
}