// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of engine;

/// Defines canvas interface common across canvases that the [SceneBuilder]
/// renders to.
///
/// This can be used either as an interface or super-class.
abstract class EngineCanvas {
  /// The element that is attached to the DOM.
  html.Element get rootElement;

  void dispose() {
    clear();
  }

  void clear();

  void save();

  void restore();

  void translate(double dx, double dy);

  void scale(double sx, double sy);

  void rotate(double radians);

  void skew(double sx, double sy);

  void transform(Float64List matrix4);

  void clipRect(ui.Rect rect);

  void clipRRect(ui.RRect rrect);

  void clipPath(ui.Path path);

  void drawColor(ui.Color color, ui.BlendMode blendMode);

  void drawLine(ui.Offset p1, ui.Offset p2, SurfacePaintData paint);

  void drawPaint(SurfacePaintData paint);

  void drawRect(ui.Rect rect, SurfacePaintData paint);

  void drawRRect(ui.RRect rrect, SurfacePaintData paint);

  void drawDRRect(ui.RRect outer, ui.RRect inner, SurfacePaintData paint);

  void drawOval(ui.Rect rect, SurfacePaintData paint);

  void drawCircle(ui.Offset c, double radius, SurfacePaintData paint);

  void drawPath(ui.Path path, SurfacePaintData paint);

  void drawShadow(
      ui.Path path, ui.Color color, double elevation, bool transparentOccluder);

  void drawImage(ui.Image image, ui.Offset p, SurfacePaintData paint);

  void drawImageRect(
      ui.Image image, ui.Rect src, ui.Rect dst, SurfacePaintData paint);

  void drawParagraph(EngineParagraph paragraph, ui.Offset offset);

  void drawVertices(ui.Vertices vertices, ui.BlendMode blendMode,
      SurfacePaintData paint);

  void endOfPaint();
}

/// Adds an [offset] transformation to a [transform] matrix and returns the
/// combined result.
///
/// If the given offset is zero, returns [transform] matrix as is. Otherwise,
/// returns a new [Matrix4] object representing the combined transformation.
Matrix4 transformWithOffset(Matrix4 transform, ui.Offset offset) {
  if (offset == ui.Offset.zero) {
    return transform;
  }

  // Clone to avoid mutating transform.
  final Matrix4 effectiveTransform = transform.clone();
  effectiveTransform.translate(offset.dx, offset.dy, 0.0);
  return effectiveTransform;
}

class _SaveStackEntry {
  _SaveStackEntry({
    @required this.transform,
    @required this.clipStack,
  });

  final Matrix4 transform;
  final List<_SaveClipEntry> clipStack;
}

/// Tagged union of clipping parameters used for canvas.
class _SaveClipEntry {
  final ui.Rect rect;
  final ui.RRect rrect;
  final ui.Path path;
  final Matrix4 currentTransform;
  _SaveClipEntry.rect(this.rect, this.currentTransform)
      : rrect = null,
        path = null;
  _SaveClipEntry.rrect(this.rrect, this.currentTransform)
      : rect = null,
        path = null;
  _SaveClipEntry.path(this.path, this.currentTransform)
      : rect = null,
        rrect = null;
}

html.Element _drawParagraphElement(
  EngineParagraph paragraph,
  ui.Offset offset, {
  Matrix4 transform,
}) {
  assert(paragraph._isLaidOut);

  final html.Element paragraphElement = paragraph._paragraphElement.clone(true);

  final html.CssStyleDeclaration paragraphStyle = paragraphElement.style;
  paragraphStyle
    ..position = 'absolute'
    ..whiteSpace = 'pre-wrap'
    ..overflowWrap = 'break-word'
    ..overflow = 'hidden'
    ..height = '${paragraph.height}px'
    ..width = '${paragraph.width}px';

  if (transform != null) {
    paragraphStyle
      ..transformOrigin = '0 0 0'
      ..transform =
          matrix4ToCssTransform3d(transformWithOffset(transform, offset));
  }

  final ParagraphGeometricStyle style = paragraph._geometricStyle;

  // TODO(flutter_web): https://github.com/flutter/flutter/issues/33223
  if (style.ellipsis != null &&
      (style.maxLines == null || style.maxLines == 1)) {
    paragraphStyle
      ..whiteSpace = 'pre'
      ..textOverflow = 'ellipsis';
  }
  return paragraphElement;
}
