// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:test/test.dart';
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
}
