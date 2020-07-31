// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ui/ui.dart' hide window;
import 'package:ui/src/engine.dart';

void main() {
  test('Conic line intersection', () {
    for (int index = 0; index < lineConicTestCount; ++index) {
      TestCase testCase = lineConicTests[index];
      Conic conic = testCase.conic;
      DLine line = testCase.line;
      ReduceOrder reducer;
      Float32List reduced = Float32List(6);
      int order1 = ReduceOrder.conic(conic.toPoints(), conic.fW, reduced);
      expect(order1, ReduceOrderResult.kConic);

      int order2 = ReduceOrder.reduceLine(
          offsetListToPoints(testCase.linePoints));
      expect(order2, ReduceOrderResult.kLine);

      Intersections intersections = Intersections();
      bool flipped = doIntersect(intersections, conic, line);
      int result =intersections.fUsed;
      expect(result, testCase.expectedResult);
      if (intersections.fUsed <= 0) {
        continue;
      }
      for (int pt = 0; pt < result; ++pt) {
        double tt1 = intersections.fT0[pt];
        expect(tt1 >= 0 && tt1 <= 1, true);
        Offset t1 = conic.ptAtT(tt1);
        double tt2 = intersections.fT1[pt];
        expect(tt2 >= 0 && tt2 <= 1, true);
        double t2x = line.ptAtTx(tt2);
        double t2y = line.ptAtTy(tt2);
        expect(approximatelyEqualPoints(t1.dx, t1.dy, t2x, t2y), true,
          reason: 'Expected conic and line point equal at $tt1,$tt2'
              ' ${t1.dx}, ${t1.dy}, $t2x, $t2y'
        );
        for (Offset expectedPoint in testCase.expectedPoints) {
          approximatelyEqualPoints(t1.dx, t1.dy, expectedPoint.dx,
              expectedPoint.dy);
        }
      }
    }
  });

  test('Conic Line intersection one offs', () {
    for (int index = 0; index < lineConicTestCount; ++index) {
      TestCase testCase = lineConicTests[index];
      Conic conic = testCase.conic;
      DLine line = testCase.line;
      Intersections intersections = Intersections();
      bool flipped = doIntersect(intersections, conic, line);
      int result = intersections.fUsed;
      for (int inner = 0; inner < result; ++inner) {
        double conicT = intersections.fT0[inner];
        Offset conicXY = conic.ptAtT(conicT);
        double lineT = intersections.fT1[inner];
        double lineX = line.ptAtTx(lineT);
        double lineY = line.ptAtTy(lineT);
        expect(approximatelyEqualPoints(conicXY.dx, conicXY.dy, lineX, lineY),
            true);
      }
    }
  });
}

List<TestCase> oneOffs = [
  TestCase(
    [Offset(30.6499996,25.6499996), Offset(30.6499996,20.6499996), Offset(25.6499996,20.6499996)],
    0.707107008,
    [Offset(25.6499996,20.6499996), Offset(45.6500015,20.6499996)],
    0,
    [Offset.zero]
  ),
];

int oneOffsCount = oneOffs.length;


class TestCase {
  TestCase(this.conicPoints, this.conicWeight, this.linePoints,
      this.expectedResult, this.expectedPoints);
  final List<Offset> conicPoints;
  final double conicWeight;
  final List<Offset> linePoints;
  // Number of intersections.
  final int expectedResult;
  // Intersection points.
  final List<Offset> expectedPoints;

  Conic get conic => Conic.fromPoints(
      offsetListToPoints(conicPoints), conicWeight);

  DLine get line => DLine.fromPoints(offsetListToPoints(linePoints));
}

List<TestCase> lineConicTests = [
  TestCase(
    [Offset(30.6499996,25.6499996), Offset(30.6499996,20.6499996), Offset(25.6499996,20.6499996)],
    0.707107008,
    [Offset(25.6499996,20.6499996), Offset(45.6500015,20.6499996)],
    1,
    [Offset(25.6499996,20.6499996)]
  ),
];

int lineConicTestCount = lineConicTests.length;

bool doIntersect(Intersections intersections, Conic conic, DLine line) {
  int result;
  bool flipped = false;
  if (line.x0 == line.x1) {
    double top = line.y0;
    double bottom = line.y1;
    flipped = top > bottom;
    if (flipped) {
      bottom = line.y0;
      top = line.y1;
    }
    result = intersections.conicVertical(conic.toPoints(), conic.fW, top, bottom, line.x0, flipped);
  } else if (line.y0 == line.y1) {
    double left = line.x0;
    double right = line.x1;
    flipped = left > right;
    if (flipped) {
      left = line.x1;
      right = line.x0;
    }
    result = intersections.conicHorizontal(conic.toPoints(), conic.fW, left, right, line.y0, flipped);
  } else {
    intersections.intersectConicWithLine(conic, line);
    result = intersections.fUsed;
  }
  return flipped;
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
