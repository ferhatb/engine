// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
part of engine;

int reuseCount = 0;

class _ReusableElement {
  final String op;
  final html.Element element;
  _ReusableElement(this.op, this.element);
}

/// A canvas that renders to DOM elements and CSS properties.
class DomCanvas extends EngineCanvas with SaveElementStackTracking {
  @override
  final html.Element rootElement = html.Element.tag('flt-dom-canvas');
  // Finger print of drawing commands provided by [RecordingCanvas].
  final String rcFingerPrint;

  bool _reuse = false;
  int _reuseIndex = 0;
  bool needsAppend = false;

  List<_ReusableElement> _ops = [];
  List<_ReusableElement> _reusableList = [];
  void addReusable(String operation, html.Element element) {
    _ops.add(_ReusableElement(operation, element));
  }

  DomCanvas({this.rcFingerPrint}) {
    rootElement.style
      ..position = 'absolute'
      ..top = '0'
      ..right = '0'
      ..bottom = '0'
      ..left = '0';
  }

  /// Prepare to reuse child elements.
  void reuse() {
    _reuse = true;
    _reuseIndex = 0;
  }

  /// Prepare to reuse this canvas by clearing it's current contents.
  @override
  void clear() {
    super.clear();
    // TODO(yjbanov): we should measure if reusing old elements is beneficial.
    domRenderer.clearDom(rootElement);
  }

  @override
  void clipRect(ui.Rect rect) {
    throw UnimplementedError();
  }

  @override
  void clipRRect(ui.RRect rrect) {
    throw UnimplementedError();
  }

  @override
  void clipPath(ui.Path path) {
    throw UnimplementedError();
  }

  @override
  void drawColor(ui.Color color, ui.BlendMode blendMode) {
    // TODO(yjbanov): implement blendMode
    final _ReusableElement reusable = _reusableList.isEmpty ? null : _reusableList[_reuseIndex];
    html.Element box;
    if (_reuse && reusable != null && reusable.op == _FingerPrints.drawColor) {
      box = reusable.element;
      ++_reuseIndex;
    } else {
      box = html.Element.tag('draw-color');
      needsAppend = true;
    }
    box.style
      ..position = 'absolute'
      ..top = '0'
      ..right = '0'
      ..bottom = '0'
      ..left = '0'
      ..backgroundColor = colorToCssString(color);
    if (needsAppend) {
      currentElement.append(box);
    }
    addReusable(_FingerPrints.drawColor, box);
  }

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawPaint(SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawRect(ui.Rect rect, SurfacePaintData paint) {
    html.Element rectangle;
    final _ReusableElement reusable = _reusableList.isEmpty ? null : _reusableList[_reuseIndex];
    if (_reuse && reusable != null && reusable.op == _FingerPrints.drawRect) {
      rectangle = reusable.element;
      ++_reuseIndex;
    } else {
      rectangle = html.Element.tag('draw-rect');
      needsAppend = true;
    }
    _drawRect(rect, paint, rectangle);
    addReusable(_FingerPrints.drawRect, rectangle);
  }

  html.Element _drawRect(ui.Rect rect, SurfacePaintData paint, html.Element rectangle) {
    assert(paint.shader == null);
    assert(() {
      rectangle.setAttribute('flt-rect', '$rect');
      rectangle.setAttribute('flt-paint', '$paint');
      return true;
    }());

    String effectiveTransform;
    final bool isStroke = paint.style == ui.PaintingStyle.stroke;
    final double strokeWidth = paint.strokeWidth ?? 0.0;
    final double left = math.min(rect.left, rect.right);
    final double right = math.max(rect.left, rect.right);
    final double top = math.min(rect.top, rect.bottom);
    final double bottom = math.max(rect.top, rect.bottom);
    if (currentTransform.isIdentity()) {
      if (isStroke) {
        effectiveTransform =
            'translate(${left - (strokeWidth / 2.0)}px, ${top - (strokeWidth / 2.0)}px)';
      } else {
        effectiveTransform = 'translate(${left}px, ${top}px)';
      }
    } else {
      // Clone to avoid mutating _transform.
      final Matrix4 translated = currentTransform.clone();
      if (isStroke) {
        translated.translate(
            left - (strokeWidth / 2.0), top - (strokeWidth / 2.0));
      } else {
        translated.translate(left, top);
      }
      effectiveTransform = matrix4ToCssTransform(translated);
    }
    final html.CssStyleDeclaration style = rectangle.style;
    style
      ..position = 'absolute'
      ..transformOrigin = '0 0 0'
      ..transform = effectiveTransform;

    final String cssColor =
        paint.color == null ? '#000000' : colorToCssString(paint.color);

    if (paint.maskFilter != null) {
      style.filter = 'blur(${paint.maskFilter.webOnlySigma}px)';
    }

    if (isStroke) {
      style
        ..width = '${right - left - strokeWidth}px'
        ..height = '${bottom - top - strokeWidth}px'
        ..border = '${strokeWidth}px solid $cssColor';
    } else {
      style
        ..width = '${right - left}px'
        ..height = '${bottom - top}px'
        ..backgroundColor = cssColor;
    }
    if (needsAppend) {
      currentElement.append(rectangle);
    }
  }

  @override
  void drawRRect(ui.RRect rrect, SurfacePaintData paint) {
    html.Element element;
    final _ReusableElement reusable = _reusableList.isEmpty ? null : _reusableList[_reuseIndex];
    if (_reuse && reusable != null && reusable.op == _FingerPrints.drawRRect) {
      element = reusable.element;
      ++_reuseIndex;
    } else {
      element = html.Element.tag('draw-rrect');
      needsAppend = true;
    }
    _drawRect(rrect.outerRect, paint, element);
    addReusable(_FingerPrints.drawRRect, element);
  }

  @override
  void drawDRRect(ui.RRect outer, ui.RRect inner, SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawOval(ui.Rect rect, SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawCircle(ui.Offset c, double radius, SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawPath(ui.Path path, SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawShadow(ui.Path path, ui.Color color, double elevation,
      bool transparentOccluder) {
    throw UnimplementedError();
  }

  @override
  void drawImage(ui.Image image, ui.Offset p, SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawImageRect(
      ui.Image image, ui.Rect src, ui.Rect dst, SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) {
    final html.Element paragraphElement =
        _drawParagraphElement(paragraph, offset, transform: currentTransform);
    html.Element element;
    final _ReusableElement reusable = _reusableList.isEmpty ? null : _reusableList[_reuseIndex];
    if (_reuse && reusable != null && reusable.op == _FingerPrints.drawParagraph) {
      element = reusable.element;
      ++_reuseIndex;
      currentElement.append(element.innerHtml == paragraphElement.innerHtml ?
          element : paragraphElement);
    } else {
      element = paragraphElement;
      currentElement.append(paragraphElement);
    }
    needsAppend = true;
    addReusable(_FingerPrints.drawParagraph, element);
  }

  @override
  void drawVertices(
      ui.Vertices vertices, ui.BlendMode blendMode, SurfacePaintData paint) {
    throw UnimplementedError();
  }

  @override
  void drawPoints(ui.PointMode pointMode, Float32List points,
      double strokeWidth, ui.Color color) {
    throw UnimplementedError();
  }

  static int reuseCount = 0;

  @override
  void endOfPaint() {
    needsAppend = false;
    if (_reuse) {
//      reuseCount += _reuseIndex;
//      print(reuseCount);
      for (int i = _reuseIndex, len = _reusableList.length; i < len; i++) {
        _reusableList[i].element.remove();
      }
    }
    _reusableList = _ops;
    _ops = [];
  }
}

class _FingerPrints {
  static const String drawColor = 'C';
  static const String drawRect = 'r';
  static const String drawRRect = 'R';
  static const String drawParagraph = 'P';
}
