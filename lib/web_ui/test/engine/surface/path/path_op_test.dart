// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ui/ui.dart' hide window;
import 'package:ui/src/engine.dart';

void main() {
  group('PathOp', (){
    // See https://drive.google.com/file/d/0BwoLUwz9PYkHLWpsaXd0UDdaN00/view
    test('Should compute operation for inverse fills', () {
      expect(gOpInverse(PathOp.kDifference, false, false), PathOp.kDifference);
      expect(gOutInverse(PathOp.kDifference, false, false), false);
      expect(gOpInverse(PathOp.kDifference, false, true), PathOp.kIntersect);
      expect(gOutInverse(PathOp.kDifference, false, true), false);
      expect(gOpInverse(PathOp.kDifference, true, false), PathOp.kUnion);
      expect(gOutInverse(PathOp.kDifference, true, false), true);
      expect(gOpInverse(PathOp.kDifference, true, true), PathOp.kReverseDifference);
      expect(gOutInverse(PathOp.kDifference, true, true), false);

      expect(gOpInverse(PathOp.kIntersect, false, false), PathOp.kIntersect);
      expect(gOutInverse(PathOp.kIntersect, false, false), false);
      expect(gOpInverse(PathOp.kIntersect, false, true), PathOp.kDifference);
      expect(gOutInverse(PathOp.kIntersect, false, true), false);
      expect(gOpInverse(PathOp.kIntersect, true, false), PathOp.kReverseDifference);
      expect(gOutInverse(PathOp.kIntersect, true, false), false);
      expect(gOpInverse(PathOp.kIntersect, true, true), PathOp.kUnion);
      expect(gOutInverse(PathOp.kIntersect, true, true), true);

      expect(gOpInverse(PathOp.kUnion, false, false), PathOp.kUnion);
      expect(gOutInverse(PathOp.kUnion, false, false), false);
      expect(gOpInverse(PathOp.kUnion, false, true), PathOp.kReverseDifference);
      expect(gOutInverse(PathOp.kUnion, false, true), true);
      expect(gOpInverse(PathOp.kUnion, true, false), PathOp.kDifference);
      expect(gOutInverse(PathOp.kUnion, true, false), true);
      expect(gOpInverse(PathOp.kUnion, true, true), PathOp.kIntersect);
      expect(gOutInverse(PathOp.kUnion, true, true), true);

      expect(gOpInverse(PathOp.kXor, false, false), PathOp.kXor);
      expect(gOutInverse(PathOp.kXor, false, false), false);
      expect(gOpInverse(PathOp.kXor, false, true), PathOp.kXor);
      expect(gOutInverse(PathOp.kXor, false, true), true);
      expect(gOpInverse(PathOp.kXor, true, false), PathOp.kXor);
      expect(gOutInverse(PathOp.kXor, true, false), true);
      expect(gOpInverse(PathOp.kXor, true, true), PathOp.kXor);
      expect(gOutInverse(PathOp.kXor, true, true), false);

      expect(gOpInverse(PathOp.kReverseDifference, false, false), PathOp.kReverseDifference);
      expect(gOutInverse(PathOp.kReverseDifference, false, false), false);
      expect(gOpInverse(PathOp.kReverseDifference, false, true), PathOp.kUnion);
      expect(gOutInverse(PathOp.kReverseDifference, false, true), true);
      expect(gOpInverse(PathOp.kReverseDifference, true, false), PathOp.kIntersect);
      expect(gOutInverse(PathOp.kReverseDifference, true, false), false);
      expect(gOpInverse(PathOp.kReverseDifference, true, true), PathOp.kDifference);
      expect(gOutInverse(PathOp.kReverseDifference, true, true), false);
    });
  });
//  group('OpEdgeBuilder', (){
//    test('Should close open contours', () {
//      final SurfacePath path = SurfacePath();
//      // Write an open triangle contour.
//      path.moveTo(100, 20);
//      path.lineTo(150, 120);
//      path.lineTo(50, 120);
//      // Without closing, write another contour.
//      path.moveTo(100, 220);
//      path.lineTo(150, 320);
//      path.lineTo(50, 320);
//      final OpGlobalState globalState = OpGlobalState();
//      final OpEdgeBuilder edgeBuilder = OpEdgeBuilder(path, globalState);
//      // Verify that both contours are closed.
//      ....
//    });
//  });

  group('LineParameters', () {
    test('Should compute distances for cubic curves', () {
      // tests to verify that distance calculations are coded correctly
      List<List<Offset>> cubicPoints = [
        [Offset(0, 0), Offset(1, 1), Offset(2, 2), Offset(0, 3)],
        [Offset(0, 0), Offset(1, 1), Offset(2, 2), Offset(3, 0)],
        [Offset(0, 0), Offset(5, 0), Offset(-2, 4), Offset(3, 4)],
        [Offset(0, 2), Offset(1, 0), Offset(2, 0), Offset(3, 0)],
        [Offset(0, .2), Offset(1, 0), Offset(2, 0), Offset(3, 0)],
        [Offset(0, .02), Offset(1, 0), Offset(2, 0), Offset(3, 0)],
        [Offset(0, .002), Offset(1, 0), Offset(2, 0), Offset(3, 0)],
        [Offset(0, .0002), Offset(1, 0), Offset(2, 0), Offset(3, 0)],
        [Offset(0, .00002), Offset(1, 0), Offset(2, 0), Offset(3, 0)],
        [Offset(0, kFltEpsilon * 2), Offset(1, 0), Offset(2, 0), Offset(3, 0)],
      ];

      List<List<double>> cubicAnswers = [
        [1, 2],
        [1, 2],
        [4, 4],
        [1.1094003924, 0.5547001962],
        [0.133038021, 0.06651901052],
        [0.0133330370, 0.006666518523],
        [0.001333333037, 0.0006666665185],
        [0.000133333333, 6.666666652e-05],
        [1.333333333e-05, 6.666666667e-06],
        [1.5894571940104115e-07, 7.9472859700520577e-08],
      ];

      int testCount = cubicPoints.length;
      for (int index = 0; index < testCount; ++index) {
        final LineParameters lineParameters = LineParameters();
        Float32List cubic = offsetListToPoints(cubicPoints[index]);
        lineParameters.cubicEndPointsAt(cubic, 0, 3);
        List<double> denormalizedDistance = [
          lineParameters.controlPtDistance(cubic, 1),
          lineParameters.controlPtDistance(cubic, 2)
        ];
        double normalSquared = lineParameters.normalSquared;
        int inner;
        for (inner = 0; inner < 2; ++inner) {
          double distSq = denormalizedDistance[inner];
          distSq *= distSq;
          double cubicAnswersSq = cubicAnswers[index][inner];
          cubicAnswersSq *= cubicAnswersSq;
          if (almostEqualUlps(distSq, normalSquared * cubicAnswersSq)) {
            continue;
          }
          lineParameters.normalize();
          List<double> normalizedDistance = [
            lineParameters.controlPtDistance(cubic, 1),
            lineParameters.controlPtDistance(cubic, 2)
          ];
          for (inner = 0; inner < 2; ++inner) {
            if (almostEqualUlps(normalizedDistance[inner].abs(),
                cubicAnswers[index][inner])) {
              continue;
            }
            assert(false, 'LineParameters test case $index failed');
          }
        }
      }
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

// Intersection tests.
List<List<List<Offset>>> quadraticTests = [
  [  // one intersection
    [Offset(0, 0), Offset(0, 1), Offset(1, 1)],
    [Offset(0, 1), Offset(0, 0), Offset(1, 0)]
  ],
  [  // four intersections
    [Offset(1, 0), Offset(2, 6), Offset(3, 0)],
    [Offset(0, 1), Offset(6, 2), Offset(0, 3)]
  ]
];

int quadraticTestsCount = quadraticTests.length;
