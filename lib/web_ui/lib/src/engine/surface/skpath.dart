// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
part of engine;

class SPathSegmentMask {
  static const int kLine_SkPathSegmentMask   = 1 << 0;
  static const int kQuad_SkPathSegmentMask   = 1 << 1;
  static const int kConic_SkPathSegmentMask  = 1 << 2;
  static const int kCubic_SkPathSegmentMask  = 1 << 3;
};

class SPathVerb {
  static const int kMove = 1;  // 1 point
  static const int kLine = 2;  // 2 points
  static const int kQuad = 3;  // 3 points
  static const int kConic = 4; // 3 points + 1 weight
  static const int kCubic = 5; // 4 points
  static const int kClose = 6; // 0 points
};

class SPath {
  static const int kMoveVerb = SPathVerb.kMove;
  static const int kLineVerb = SPathVerb.kLine;
  static const int kQuadVerb = SPathVerb.kQuad;
  static const int kConicVerb = SPathVerb.kConic;
  static const int kCubicVerb = SPathVerb.kCubic;
  static const int kCloseVerb = SPathVerb.kClose;
  static const int kDoneVerb = SPathVerb.kClose + 1;

  static const int kLineSegmentMask   = SPathSegmentMask.kLine_SkPathSegmentMask;
  static const int kQuadSegmentMask   = SPathSegmentMask.kQuad_SkPathSegmentMask;
  static const int kConicSegmentMask  = SPathSegmentMask.kConic_SkPathSegmentMask;
  static const int kCubicSegmentMask  = SPathSegmentMask.kCubic_SkPathSegmentMask;
}
