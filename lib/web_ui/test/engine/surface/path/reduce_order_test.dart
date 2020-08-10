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
      expect(result, ReduceOrderResult.kLine);
    });

    test('Should reduce order for empty line', () {
      int result = ReduceOrder.reduceLine(offsetListToPoints(
          [Offset(20, 30), Offset(20, 30)]
      ));
      expect(result, ReduceOrderResult.kPoint);
    });

    test('Should not reduce order for non-line quadratic', () {
      List<List<Offset>> testData = <List<Offset>>[
        [Offset(1, 1), Offset(2, 2), Offset(1, 1.000003)],
        [Offset(1, 0), Offset(2, 6), Offset(3, 0)],
      ];
      for (int i = 0; i < testData.length; i++) {
        Float32List points = offsetListToPoints(testData[i]);
        int result = ReduceOrder.quad(points, points);
        expect(result, ReduceOrderResult.kQuad);
      }
    });

    test('Quadratic lines', () {
      for (int index = 0; index < quadraticLinesCount; ++index) {
        Float32List quad = offsetListToPoints(quadraticLines[index]);
        int order = ReduceOrder.quad(quad, quad);
        expect(order, ReduceOrderResult.kLine, reason:
            'Was expecting line, [$index] line quad order=$order');
      }
    });

    test('Quadratic mod lines', () {
      for (int index = 0; index < quadraticModEpsilonLinesCount; ++index) {
        Float32List quad = offsetListToPoints(quadraticModEpsilonLines[index]);
        int order = ReduceOrder.quad(quad, quad);
        expect(order == ReduceOrderResult.kLine ||
            order == ReduceOrderResult.kQuad, true,
            reason: 'Unexpected order, [$index] line quad order=$order');
      }
    });

    test('Cubic degenerates', () {
      for (int index = 0; index < pointDegeneratesCount; ++index) {
        Float32List points = offsetListToPoints(pointDegenerates[index]);
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order, ReduceOrderResult.kPoint, reason:
          'Expected pointDegenerates[$index] '
              'order=${ReduceOrderResult.kPoint} got $order');
      }
    });

    test('Cubic not point degenerates', () {
      for (int index = 0; index < notPointDegeneratesCount; ++index) {
        Float32List points = offsetListToPoints(notPointDegenerates[index]);
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order != ReduceOrderResult.kPoint, true, reason:
          'Expected notPointDegenerates[$index] '
              'order!=${ReduceOrderResult.kPoint} got $order');
      }
    });

    test('Cubic should reduce to lines', () {
      for (int index = 0; index < cubicLinesCount; ++index) {
        Float32List points = offsetListToPoints(cubicLines[index]);
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order, ReduceOrderResult.kLine, reason:
        'Expected cubicLines[$index] '
            'order==${ReduceOrderResult.kLine} got $order');
      }
    });

    test('Cubic should not reduce to line', () {
      for (int index = 0; index < notLinesCount; ++index) {
        Float32List points = offsetListToPoints(notLines[index]);
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order != ReduceOrderResult.kLine, true, reason:
        'Expected notLines[$index] '
            'order!=${ReduceOrderResult.kLine} got $order');
      }
    });

    test('Cubic should support lines modulated by epsilon', () {
      for (int index = 0; index < modEpsilonLinesCount; ++index) {
        Float32List points = offsetListToPoints(modEpsilonLines[index]);
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order != ReduceOrderResult.kLine, true, reason:
          'Expected modEpsilonLines[$index] '
              'order!=${ReduceOrderResult.kLine} got $order');
      }
    });

    test('Cubic should support lines modulated by less than epsilon', () {
      for (int index = 0; index < lessEpsilonLinesCount; ++index) {
        Float32List points = offsetListToPoints(lessEpsilonLines[index]);
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order, ReduceOrderResult.kLine, reason:
        'Expected lessEpsilonLines[$index] '
            'order==${ReduceOrderResult.kLine} got $order');
      }
    });

    test('Cubic should support lines modulated by negative epsilon', () {
      for (int index = 0; index < negEpsilonLinesCount; ++index) {
        Float32List points = offsetListToPoints(negEpsilonLines[index]);
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order, ReduceOrderResult.kLine, reason:
        'Expected negEpsilonLines[$index] '
            'order==${ReduceOrderResult.kLine} got $order');
      }
    });

    test('Cubic from quads should reduce to point', () {
      for (int index = 0; index < quadraticPointsCount; ++index) {
        Float32List points = quadPointsToCubic(offsetListToPoints(
            quadraticPoints[index]));
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order, ReduceOrderResult.kPoint, reason:
          'Expected quadraticPoints[$index] '
              'order==${ReduceOrderResult.kPoint} got $order');
      }
    });

    test('Cubic from quads should reduce to lines', () {
      for (int index = 0; index < quadraticLinesCount; ++index) {
        Float32List points = quadPointsToCubic(offsetListToPoints(
            quadraticLines[index]));
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order, ReduceOrderResult.kLine, reason:
        'Expected quadraticLines[$index] '
            'order==${ReduceOrderResult.kLine} got $order');
      }
    });

    test('Cubic from quads modulated by epsilon should reduce to quad', () {
      for (int index = 0; index < quadraticModEpsilonLinesCount; ++index) {
        Float32List points = quadPointsToCubic(offsetListToPoints(
            quadraticModEpsilonLines[index]));
        Float32List reduction = Float32List(8);
        int order = ReduceOrder.cubic(points, reduction);
        expect(order, ReduceOrderResult.kQuad, reason:
        'Expected quadraticModEpsilonLines[$index] '
            'order!=${ReduceOrderResult.kQuad} got $order');
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

Float32List quadPointsToCubic(Float32List quadPoints) {
  Float32List cubic = Float32List(8);
  cubic[0] = quadPoints[0];
  cubic[1] = quadPoints[1];

  cubic[4] = quadPoints[2];
  cubic[5] = quadPoints[3];

  cubic[6] = quadPoints[4];
  cubic[7] = quadPoints[5];

  cubic[2] = (cubic[0] + cubic[4] * 2) / 3;
  cubic[3] = (cubic[1] + cubic[5] * 2) / 3;
  cubic[4] = (cubic[6] + cubic[4] * 2) / 3;
  cubic[5] = (cubic[7] + cubic[5] * 2) / 3;
  return cubic;
}
