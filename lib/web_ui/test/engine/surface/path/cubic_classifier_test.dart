// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ui/ui.dart' hide window;
import 'package:ui/src/engine.dart';

void main() {
  group('CubicClassifier', () {
    test('Should detect serpentine curves', () {
      List<List<Offset>> samples = [
        [
          Offset(149.325, 107.705),
          Offset(149.325, 103.783),
          Offset(151.638, 100.127),
          Offset(156.263, 96.736)
        ],
        [
          Offset(225.694, 223.15),
          Offset(209.831, 224.837),
          Offset(195.994, 230.237),
          Offset(184.181, 239.35)
        ],
        [
          Offset(4.873, 5.581),
          Offset(5.083, 5.2783),
          Offset(5.182, 4.8593),
          Offset(5.177, 4.3242)
        ],
      ];
      for (int sampleIndex = 0; sampleIndex < samples.length; ++sampleIndex) {
        CubicClassifier classifier =
            CubicClassifier.classify(offsetListToPoints(samples[sampleIndex]));
        expect(classifier.cubicType, CubicType.kSerpentine);
      }
    });
    test('Should detect curve type around rect', () {
      testAroundRect(0, 0, 1, 1);
    });
  });
}

List<int> expectations = [
  CubicType.kLoop,
  CubicType.kCuspAtInfinity,
  CubicType.kLocalCusp,
  CubicType.kLocalCusp,
  CubicType.kCuspAtInfinity,
  CubicType.kLoop,
  CubicType.kCuspAtInfinity,
  CubicType.kLoop,
  CubicType.kCuspAtInfinity,
  CubicType.kLoop,
  CubicType.kLocalCusp,
  CubicType.kLocalCusp,
  CubicType.kLocalCusp,
  CubicType.kLocalCusp,
  CubicType.kLoop,
  CubicType.kCuspAtInfinity,
  CubicType.kLoop,
  CubicType.kCuspAtInfinity,
  CubicType.kLoop,
  CubicType.kCuspAtInfinity,
  CubicType.kLocalCusp,
  CubicType.kLocalCusp,
  CubicType.kCuspAtInfinity,
  CubicType.kLoop,
];

/// Places cubic control points around rect edges to test [CubicType]
/// against expectations.
void testAroundRect(double x1, double y1, double x2, double y2,
    {bool isUndefined = false}) {
  List<Offset> points = [
    Offset(x1, y1),
    Offset(x2, y1),
    Offset(x2, y2),
    Offset(x1, y2)
  ];
  List<Offset> bezier = [points[0], points[1], points[2], points[3]];
  for (int i = 0; i < 4; ++i) {
    bezier[0] = points[i];
    for (int j = 0; j < 3; ++j) {
      int jidx = (j < i) ? j : j + 1;
      bezier[1] = points[jidx];
      for (int k = 0, kidx = 0; k < 2; ++k, ++kidx) {
        for (int n = 0; n < 2; ++n) {
          kidx = (kidx == i || kidx == jidx) ? kidx + 1 : kidx;
        }
        bezier[2] = points[kidx];
        for (int l = 0; l < 4; ++l) {
          if (l != i && l != jidx && l != kidx) {
            bezier[3] = points[l];
            break;
          }
        }
        CubicClassifier classifier =
            CubicClassifier.classify(offsetListToPoints(bezier));
        if (!isUndefined) {
          expect(classifier.cubicType, expectations[i * 6 + j * 2 + k],
              reason: '${bezier[0]} ${bezier[1]} ${bezier[2]} ${bezier[3]} '
                  'expected: ${expectations[i * 6 + j * 2 + k]}, '
                  'got: ${classifier.cubicType}');
        }
      }
    }
  }
  for (int i = 0; i < 4; ++i) {
    bezier[0] = points[i];
    for (int j = 0; j < 3; ++j) {
      int jidx = (j < i) ? j : j + 1;
      bezier[1] = points[jidx];
      bezier[2] = points[jidx];
      for (int k = 0, kidx = 0; k < 2; ++k, ++kidx) {
        for (int n = 0; n < 2; ++n) {
          kidx = (kidx == i || kidx == jidx) ? kidx + 1 : kidx;
        }
        bezier[3] = points[kidx];
        CubicClassifier classifier =
            CubicClassifier.classify(offsetListToPoints(bezier));
        if (!isUndefined) {
          expect(classifier.cubicType, CubicType.kSerpentine,
              reason: '${bezier[0]} ${bezier[1]} ${bezier[2]} ${bezier[3]} '
                  'expected: ${CubicType.kSerpentine}, '
                  'got: ${classifier.cubicType}');
        }
      }
    }
  }
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
