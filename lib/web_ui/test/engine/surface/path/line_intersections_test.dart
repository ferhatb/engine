// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:ui/ui.dart' hide window;
import 'package:ui/src/engine.dart';


void main() {
  group('Line intersections', () {
    test('should intersect at least at one point with near allowed', () {
      for (int index = 0; index < testCount; index++) {
        List<List<Offset>> testCase = tests[index];
        final DLine line1 = lineFromTestData(testCase, 0);
        final DLine line2 = lineFromTestData(testCase, 1);
        testOne(line1, line2, true);
      }
    });

    test('with one coincident', () {
      for (int index = 0; index < coincidentTestsCount; index++) {
        List<List<Offset>> testCase = coincidentTests[index];
        final DLine line1 = lineFromTestData(testCase, 0);
        final DLine line2 = lineFromTestData(testCase, 1);
        testOneCoincident(line1, line2);
      }
    });

    test('should not intersect', () {
      for (int index = 0; index < noIntersectCount; index++) {
        List<List<Offset>> testCase = noIntersect[index];
        final DLine line1 = lineFromTestData(testCase, 0);
        final DLine line2 = lineFromTestData(testCase, 1);
        Intersections i = Intersections();
        int pts = i.intersectLines(line1, line2);
        assert(pts == 0);
        assert(pts == i.fUsed);
      }
    });

    test('should intersect (exact) at least at one point', () {
      List<List<Offset>> testCase = tests[0];
      final DLine line1 = lineFromTestData(testCase, 0);
      final DLine line2 = lineFromTestData(testCase, 1);
      testOne(line1, line2, false);
    });
  });
}

void checkResults(DLine line1, DLine line2, Intersections ts, bool nearAllowed) {
  for (int i = 0; i < ts.fUsed; ++i) {
    double result1x = line1.ptAtTx(ts.fT0[i]);
    double result1y = line1.ptAtTy(ts.fT0[i]);
    double result2x = line2.ptAtTx(ts.fT1[i]);
    double result2y = line2.ptAtTy(ts.fT1[i]);
    if (nearAllowed && roughlyEqualPoints(result1x, result1y, result2x, result2y)) {
      continue;
    }
    if (!approximatelyEqualPoints(result1x, result1y, result2x, result2y) && !ts.fNearlySame[i]) {
      assert(ts.fUsed != 1);
      result2x = line2.ptAtTx(ts.fT1[i ^ 1]);
      result2y = line2.ptAtTy(ts.fT1[i ^ 1]);
      if (!approximatelyEqualPoints(result1x, result1y, result2x, result2y)) {
        print('.');
      }
      expect(approximatelyEqualPoints(result1x, result1y, result2x, result2y), true);
      expect(approximatelyEqualPoints(result1x, result1y, ts.ptX[i], ts.ptY[i]), true);
    }
  }
}

void testOne(DLine line1, DLine line2, bool nearAllowed) {
    Intersections i = Intersections();
    i.allowNear(nearAllowed);
    int pts = i.intersectLines(line1, line2);
    assert(pts != 0);
    assert(pts == i.fUsed);
    checkResults(line1, line2, i, nearAllowed);
    if ((line1.x0 == line1.x1 && line1.y0 == line1.y1) ||
        (line2.x0 == line2.x1 && line2.y0 == line2.y1)) {
      return;
    }
    if (line1.y0 == line1.y1) {
      // Horizontal.
      double left = math.min(line1.x0, line1.x1);
      double right = math.max(line1.x0, line1.x1);
      Intersections ts = Intersections();
      ts.horizontal(line2, left, right, line1.y0, line1.x0 != left);
      checkResults(line2, line1, ts, false);
    }
    if (line2.y0 == line2.y1) {
      // Line2 Horizontal.
      double left = math.min(line2.x0, line2.x1);
      double right = math.max(line2.x0, line2.x1);
      Intersections ts = Intersections();
      ts.horizontal(line1, left, right, line2.y0, line2.x0 != left);
      checkResults(line1, line2, ts, false);
    }
    if (line1.x0 == line1.x1) {
      // Vertical.
      double top = math.min(line1.y0, line1.y1);
      double bottom = math.max(line1.y0, line1.y1);
      Intersections ts = Intersections();
      ts.vertical(line2, top, bottom, line1.x0, line1.y0 != top);
      checkResults(line2, line1, ts, false);
    }
    if (line2.x0 == line2.x1) {
      // Second line vertical.
      double top = math.min(line2.y0, line2.y1);
      double bottom = math.max(line2.y0, line2.y1);
      Intersections ts = Intersections();
      ts.vertical(line1, top, bottom, line2.x0, line2.y0 != top);
      checkResults(line1, line2, ts, false);
    }
}

void testOneCoincident(DLine line1, DLine line2) {
  Intersections ts = Intersections();
  int pts = ts.intersectLines(line1, line2);
  expect(pts, 2);
  expect(pts, ts.fUsed);
  checkResults(line1, line2, ts, false);
  if ((line1.x0 == line1.x1 && line1.y0 == line1.y1) ||
      (line2.x0 == line2.x1 && line2.y0 == line2.y1)) {
    return;
  }
  if (line1.y0 == line1.y1) {
    // Horizontal.
    double left = math.min(line1.x0, line1.x1);
    double right = math.max(line1.x0, line1.x1);
    Intersections ts = Intersections();
    ts.horizontal(line2, left, right, line1.y0, line1.x0 != left);
    assert(pts == 2);
    assert(2 == ts.fUsed);
    checkResults(line2, line1, ts, false);
  }
  if (line2.y0 == line2.y1) {
    // Line2 Horizontal.
    double left = math.min(line2.x0, line2.x1);
    double right = math.max(line2.x0, line2.x1);
    Intersections ts = Intersections();
    ts.horizontal(line1, left, right, line2.y0, line2.x0 != left);
    assert(pts == 2);
    assert(2 == ts.fUsed);
    checkResults(line1, line2, ts, false);
  }
  if (line1.x0 == line1.x1) {
    // Vertical.
    double top = math.min(line1.y0, line1.y1);
    double bottom = math.max(line1.y0, line1.y1);
    Intersections ts = Intersections();
    ts.vertical(line2, top, bottom, line1.x0, line1.y0 != top);
    assert(pts == 2);
    assert(pts == ts.fUsed);
    checkResults(line2, line1, ts, false);
  }
  if (line2.x0 == line2.x1) {
    // Second line vertical.
    double top = math.min(line2.y0, line2.y1);
    double bottom = math.max(line2.y0, line2.y1);
    Intersections ts = Intersections();
    ts.vertical(line1, top, bottom, line2.x0, line2.y0 != top);
    assert(pts == 2);
    assert(pts == ts.fUsed);
    checkResults(line1, line2, ts, false);
  }
}

DLine lineFromTestData(List<List<Offset>>testCase, int lineIndex) {
  List<Offset> lineData = testCase[lineIndex];
  return DLine(lineData[0].dx, lineData[0].dy, lineData[1].dx, lineData[1].dy);
}

/// Test cases with pairs of lines.
List<List<List<Offset>>> tests = [
  [
    [Offset(0.00010360032320022583, 1.0172703415155411), Offset(0.00014114845544099808, 1.0200891587883234)],
    [Offset(0.00010259449481964111, 1.017270140349865), Offset(0.00018215179443359375, 1.022890567779541)]
  ],
  [[Offset(30,20), Offset(30,50)], [Offset(24,30), Offset(36,30)]],
  [[Offset(323,193), Offset(-317,193)], [Offset(0,994), Offset(0,0)]],
  [[Offset(90,230), Offset(160,60)], [Offset(60,120), Offset(260,120)]],
  [[Offset(90,230), Offset(160,60)], [Offset(181.176468,120), Offset(135.294128,120)]],
  [[Offset(181.1764678955078125, 120), Offset(186.3661956787109375, 134.7042236328125)],
  [Offset(175.8309783935546875, 141.5211334228515625), Offset(187.8782806396484375, 133.7258148193359375)]],
  [[Offset(192, 4), Offset(243, 4)], [Offset(246, 4), Offset(189, 4)]],
  [[Offset(246, 4), Offset(189, 4)], [Offset(192, 4), Offset(243, 4)]],
  [[Offset(5, 0), Offset(0, 5)], [Offset(5, 4), Offset(1, 4)]],
  [[Offset(0, 0), Offset(1, 0)], [Offset(1, 0), Offset(0, 0)]],
  [[Offset(0, 0), Offset(0, 0)], [Offset(0, 0), Offset(1, 0)]],
  [[Offset(0, 1), Offset(0, 1)], [Offset(0, 0), Offset(0, 2)]],
  [[Offset(0, 0), Offset(1, 0)], [Offset(0, 0), Offset(2, 0)]],
  [[Offset(1, 1), Offset(2, 2)], [Offset(0, 0), Offset(3, 3)]],
  [[Offset(166.86950047022856, 112.69654129527828), Offset(166.86948801592692, 112.69655741235339)],
   [Offset(166.86960700313026, 112.6965477747386), Offset(166.86925794355412, 112.69656471103423)]]
];

int testCount = tests.length;

List<List<List<Offset>>> noIntersect = [
  [[Offset((2 - 1e-6), 2), Offset((2 - 1e-6), 4)], [Offset(2,1), Offset(2,3)]],
  [[Offset(0, 0), Offset(1, 0)], [Offset(3, 0), Offset(2, 0)]],
  [[Offset(0, 0), Offset(0, 0)], [Offset(1, 0), Offset(2, 0)]],
  [[Offset(0, 1), Offset(0, 1)], [Offset(0, 3), Offset(0, 2)]],
  [[Offset(0, 0), Offset(1, 0)], [Offset(2, 0), Offset(3, 0)]],
  [[Offset(1, 1), Offset(2, 2)], [Offset(4, 4), Offset(3, 3)]],
];

int noIntersectCount = noIntersect.length;

List<List<List<Offset>>> coincidentTests = [
  [[Offset(-1.48383003e-006,-83), Offset(4.2268899e-014,-60)],
  [Offset(9.5359502e-007,-60), Offset(5.08227985e-015,-83)]],

  [[Offset( 10105, 2510 ), Offset( 10123, 2509.98999)],
  [Offset(10105, 2509.98999), Offset( 10123, 2510 )]],

[[Offset( 0, 482.5 ), Offset( -4.4408921e-016, 682.5)],
[Offset(0,683), Offset(0,482)]],

[[Offset(1.77635684e-015,312), Offset(-1.24344979e-014,348)],
[Offset(0,348), Offset(0,312)]],

[[Offset(979.304871, 561), Offset(1036.69507, 291)],
[Offset(985.681519, 531), Offset(982.159790, 547.568542)]],

[[Offset(232.159805, 547.568542), Offset(235.681549, 531)],
[Offset(286.695129,291), Offset(229.304855,561)]],

[[Offset(186.3661956787109375, 134.7042236328125), Offset(187.8782806396484375, 133.7258148193359375)],
[Offset(175.8309783935546875, 141.5211334228515625), Offset(187.8782806396484375, 133.7258148193359375)]],

[[Offset(235.681549, 531.000000), Offset(280.318420, 321.000000)],
[Offset(286.695129, 291.000000), Offset(229.304855, 561.000000)]],
];

int coincidentTestsCount = coincidentTests.length;
