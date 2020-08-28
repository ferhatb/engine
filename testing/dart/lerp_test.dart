// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
import 'dart:ui';

import 'package:test/test.dart';

void main() {
  test('lerpDouble should return null if and only if both inputs are null', () {
    expect(lerpDouble(null, null, 1.0), isNull);
    expect(lerpDouble(5.0, null, 0.25), isNotNull);
    expect(lerpDouble(null, 5.0, 0.25), isNotNull);
  });

  test('lerpDouble should treat a null input as 0 if the other input is non-null', () {
    expect(lerpDouble(null, 10.0, 0.25), 2.5);
    expect(lerpDouble(10.0, null, 0.25), 7.5);
  });

  test('lerpDouble should handle interpolation values < 0.0', () {
    expect(lerpDouble(0.0, 10.0, -5.0), -50.0);
    expect(lerpDouble(10.0, 0.0, -5.0), 60.0);
  });

  test('lerpDouble should return the start value at 0.0', () {
    expect(lerpDouble(2.0, 10.0, 0.0), 2.0);
    expect(lerpDouble(10.0, 2.0, 0.0), 10.0);
  });

  test('lerpDouble should interpolate between two values', () {
    expect(lerpDouble(0.0, 10.0, 0.25), 2.5);
    expect(lerpDouble(10.0, 0.0, 0.25), 7.5);
  });

  test('lerpDouble should return the end value at 1.0', () {
    expect(lerpDouble(2.0, 10.0, 1.0), 10.0);
    expect(lerpDouble(10.0, 2.0, 1.0), 2.0);
  });

  test('lerpDouble should handle interpolation values > 1.0', () {
    expect(lerpDouble(0.0, 10.0, 5.0), 50.0);
    expect(lerpDouble(10.0, 0.0, 5.0), -40.0);
  });
}
