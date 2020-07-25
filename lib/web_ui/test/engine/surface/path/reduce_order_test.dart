// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ui/ui.dart' hide window;
import 'package:ui/src/engine.dart';
import 'cubic_test_data.dart';

void main() {
  group('ReduceOrder', () {
    test('Should not reduce order for line', () {
      int result = ReduceOrder.reduceLine(offsetListToPoints(
          [Offset(10, 10), Offset(20, 30)]
      ));
      expect(result, SPathVerb.kLine);
    });

    test('Should reduce order for empty line', () {
      int result = ReduceOrder.reduceLine(offsetListToPoints(
          [Offset(20, 30), Offset(20, 30)]
      ));
      expect(result, SPathVerb.kMove);
    });

    test('Should not reduce order for non-line quadratic', () {
      List<List<Offset>> testData = <List<Offset>>[
        [Offset(1, 1), Offset(2, 2), Offset(1, 1.000003)],
        [Offset(1, 0), Offset(2, 6), Offset(3, 0)],
      ];
      for (int i = 0; i < testData.length; i++) {
        Float32List points = offsetListToPoints(testData[i]);
        int result = ReduceOrder.quad(points, points);
        expect(result, SPathVerb.kQuad);
      }
    });

    test('Quadratic lines', () {
      for (int index = 0; index < quadraticLinesCount; ++index) {
        Float32List quad = offsetListToPoints(quadraticLines[index]);
        int order = ReduceOrder.quad(quad, quad);
        expect(order, 2, reason: 'Was expecting line, [$index] line quad order=$order');
      }
    });

    test('Quadratic mod lines', () {
      for (int index = 0; index < quadraticModEpsilonLinesCount; ++index) {
        Float32List quad = offsetListToPoints(quadraticModEpsilonLines[index]);
        int order = ReduceOrder.quad(quad, quad);
        expect(order == 2 || order == 3, true, reason:
            'Unexpected order, [$index] line quad order=$order');
      }
    });

    test('Cubic degenerates', () {
      for (int index = 0; index < pointDegeneratesCount; ++index) {
        Float32List points = offsetListToPoints(pointDegenerates[index]);
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order, 1, reason:
          'Expected pointDegenerates order=1 got $order');
      }
    });
  });
}

/// Test data for quadratic order reduction.
List<List<Offset>> quadraticPoints = <List<Offset>>[
  [Offset(0, 0), Offset(1, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(0, 1), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 1), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(1, 1)],
];

int quadraticPointsCount = quadraticPoints.length;

List<List<Offset>> quadraticLines = <List<Offset>>[
  [Offset(0, 0), Offset(0, 0), Offset(1, 0)],
  [Offset(1, 0), Offset(0, 0), Offset(0, 0)],
  [Offset(1, 0), Offset(2, 0), Offset(3, 0)],
  [Offset(0, 0), Offset(0, 0), Offset(0, 1)],
  [Offset(0, 1), Offset(0, 0), Offset(0, 0)],
  [Offset(0, 1), Offset(0, 2), Offset(0, 3)],
  [Offset(0, 0), Offset(0, 0), Offset(1, 1)],
  [Offset(1, 1), Offset(0, 0), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(3, 3)],
  [Offset(1, 1), Offset(3, 3), Offset(3, 3)],
  [Offset(1, 1), Offset(1, 1), Offset(2, 2)],
  [Offset(1, 1), Offset(1, 1), Offset(3, 3)],
  [Offset(1, 1), Offset(2, 2), Offset(4, 4)],  // no coincident
  [Offset(1, 1), Offset(3, 3), Offset(4, 4)],
  [Offset(1, 1), Offset(3, 3), Offset(2, 2)],
  [Offset(1, 1), Offset(4, 4), Offset(2, 2)],
  [Offset(1, 1), Offset(4, 4), Offset(3, 3)],
  [Offset(2, 2), Offset(1, 1), Offset(3, 3)],
  [Offset(2, 2), Offset(1, 1), Offset(4, 4)],
  [Offset(2, 2), Offset(3, 3), Offset(1, 1)],
  [Offset(2, 2), Offset(3, 3), Offset(4, 4)],
  [Offset(2, 2), Offset(4, 4), Offset(1, 1)],
  [Offset(2, 2), Offset(4, 4), Offset(3, 3)],
];

int quadraticLinesCount = quadraticLines.length;

const double F = kFltEpsilon * 32;
const double H = kFltEpsilon * 32;
const double J = kFltEpsilon * 32;
const double K = kFltEpsilon * 32;

List<List<Offset>> quadraticModEpsilonLines = <List<Offset>>[
  [Offset(0, F), Offset(0, 0), Offset(1, 0)],
  [Offset(0, 0), Offset(1, 0), Offset(0, F)],
  [Offset(1, 0), Offset(0, F), Offset(0, 0)],
  [Offset(1, H), Offset(2, 0), Offset(3, 0)],
  [Offset(0, F), Offset(0, 0), Offset(1, 1)],
  [Offset(0, 0), Offset(1, 1), Offset(F, 0)],
  [Offset(1, 1), Offset(F, 0), Offset(0, 0)],
  [Offset(1, 1+J), Offset(2, 2), Offset(3, 3)],
  [Offset(1, 1), Offset(3, 3), Offset(3+F, 3)],
  [Offset(1, 1), Offset(1+F, 1), Offset(2, 2)],
  [Offset(1, 1), Offset(2, 2), Offset(1, 1+K)],
  [Offset(1, 1), Offset(1, 1+F), Offset(3, 3)],
  [Offset(1+H, 1), Offset(2, 2), Offset(4, 4)],  // no coincident
  [Offset(1, 1+K), Offset(3, 3), Offset(4, 4)],
  [Offset(1, 1), Offset(3+F, 3), Offset(2, 2)],
  [Offset(1, 1), Offset(4, 4+F), Offset(2, 2)],
  [Offset(1, 1), Offset(4, 4), Offset(3+F, 3)],
  [Offset(2, 2), Offset(1, 1), Offset(3, 3+F)],
  [Offset(2+F, 2), Offset(1, 1), Offset(4, 4)],
  [Offset(2, 2+F), Offset(3, 3), Offset(1, 1)],
  [Offset(2, 2), Offset(3+F, 3), Offset(4, 4)],
  [Offset(2, 2), Offset(4, 4+F), Offset(1, 1)],
  [Offset(2, 2), Offset(4, 4), Offset(3+F, 3)],
];

int quadraticModEpsilonLinesCount = quadraticModEpsilonLines.length;
