// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ui/ui.dart' hide window;
import 'package:ui/src/engine.dart';

void main() {
  group('ContourBuilder', () {
    test('Should add lines, quad, conic and cubics', () {
      OpContourBuilder builder = OpContourBuilder(OpGlobalState());
      builder.addQuad(offsetListToPoints(
          [Offset(11, 50), Offset(30, 0), Offset(60, 50)]));
      builder.addLine(offsetListToPoints(
          [Offset(12, 50), Offset(80, 100)]));
      builder.addCubic(offsetListToPoints(
          [Offset(13, 50), Offset(30, 0), Offset(40, 10), Offset(60, 50)]));
      builder.addConic(offsetListToPoints(
          [Offset(14, 50), Offset(30, 0), Offset(60, 50)]), 0.2);
      builder.flush();
      final OpContour contour = builder.contour;
      expect(contour.count, 4);
      expect(contour.debugSegments[0].verb, SPathVerb.kQuad);
      expect(contour.debugSegments[0].points[0], 11);
      expect(contour.debugSegments[1].verb, SPathVerb.kLine);
      expect(contour.debugSegments[1].points[0], 12);
      expect(contour.debugSegments[2].verb, SPathVerb.kCubic);
      expect(contour.debugSegments[2].points[0], 13);
      expect(contour.debugSegments[3].verb, SPathVerb.kConic);
      expect(contour.debugSegments[3].points[0], 14);
      expect(contour.debugSegments[3].weight, 0.2);
    });

    test('Should eliminate opposite lines', () {
      OpContourBuilder builder = OpContourBuilder(OpGlobalState());
      builder.addQuad(offsetListToPoints(
          [Offset(10, 50), Offset(30, 0), Offset(60, 50)]));
      builder.addLine(offsetListToPoints(
          [Offset(60, 50), Offset(80, 100)]));
      builder.addLine(offsetListToPoints(
          [Offset(80, 100), Offset(60, 50)]));
      builder.flush();
      final OpContour contour = builder.contour;
      expect(contour.count, 1);
      expect(contour.debugSegments.first.verb, SPathVerb.kQuad);
    });

    test('Should not eliminate non-opposing lines', () {
      OpContourBuilder builder = OpContourBuilder(OpGlobalState());
      builder.addQuad(offsetListToPoints(
          [Offset(10, 50), Offset(30, 0), Offset(60, 50)]));
      builder.addLine(offsetListToPoints(
          [Offset(60, 50), Offset(80, 100)]));
      builder.addLine(offsetListToPoints(
          [Offset(80, 100), Offset(61, 50)]));
      builder.flush();
      final OpContour contour = builder.contour;
      expect(contour.count, 3);
    });
  });
}

/// Helper function to convert list of offsets to typed array.
Float32List offsetListToPoints(List<Offset> offsets) {
  Float32List points = Float32List(offsets.length * 2);
  int pointIndex = 0;
  for (int p = 0; p < offsets.length; p++) {
    points[pointIndex++] = offsets[p].dx;
    points[pointIndex++] = offsets[p].dy;
  }
  return points;
}
