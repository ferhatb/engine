// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of engine;

/// The CanvasKit implementation of [ui.ImageFilter].
///
/// Currently only supports `blur`.
class CkImageFilter extends ResurrectableSkiaObject implements ui.ImageFilter {
  CkImageFilter.blur({double sigmaX = 0.0, double sigmaY = 0.0})
      : _sigmaX = sigmaX,
        _sigmaY = sigmaY;

  final double _sigmaX;
  final double _sigmaY;

  SkImageFilter? _skImageFilter;

  @override
  js.JsObject createDefault() => _initSkiaObject();

  @override
  js.JsObject resurrect() => _initSkiaObject();

  js.JsObject _initSkiaObject() {
    final SkImageFilter skImageFilter = canvasKitJs.SkImageFilter.MakeBlur(
      _sigmaX,
      _sigmaY,
      canvasKitJs.TileMode.Clamp,
      null,
    );
    _skImageFilter = skImageFilter;
    return _jsObjectWrapper.wrapSkImageFilter(skImageFilter);
  }

  @override
  bool operator ==(Object other) {
    return other is CkImageFilter
        && other._sigmaX == _sigmaX
        && other._sigmaY == _sigmaY;
  }

  @override
  int get hashCode => ui.hashValues(_sigmaX, _sigmaY);

  @override
  String toString() {
    return 'ImageFilter.blur($_sigmaX, $_sigmaY)';
  }
}
