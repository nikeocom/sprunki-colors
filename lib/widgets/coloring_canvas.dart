import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../painting/paint_controller.dart';

class ColoringCanvas extends StatefulWidget {
  const ColoringCanvas({
    super.key,
    required this.controller,
    required this.screenRadius,
  });

  final PaintController controller;
  final double screenRadius;

  @override
  State<ColoringCanvas> createState() => _ColoringCanvasState();
}

class _ColoringCanvasState extends State<ColoringCanvas> {
  final Map<int, Offset> _pointers = {};
  double _scale = 1;
  Offset _offset = Offset.zero;
  bool _fitted = false;
  bool _pinching = false;
  int? _paintPointer;
  int? _mousePanPointer;
  Offset? _mousePanLast;
  Offset? _pinchStartA;
  Offset? _pinchStartB;
  double _pinchStartScale = 1;
  Offset _pinchStartOffset = Offset.zero;
  double _panZoomStartScale = 1;
  Offset _panZoomFocalImage = Offset.zero;
  Offset _panZoomStartLocal = Offset.zero;

  void _fit(Size size) {
    if (_fitted || size.isEmpty) {
      return;
    }
    _fitted = true;
    final art = widget.controller.art;
    final sx = size.width / art.width;
    final sy = size.height / art.height;
    _scale = math.min(sx, sy) * 0.96;
    final drawnWidth = art.width * _scale;
    final drawnHeight = art.height * _scale;
    _offset = Offset(
      (size.width - drawnWidth) / 2,
      (size.height - drawnHeight) / 2,
    );
  }

  Offset _toImage(Offset local) => (local - _offset) / _scale;

  void _applyRadius() {
    widget.controller.strokeRadius = math.max(1, widget.screenRadius / _scale);
  }

  void _startPaint(Offset local) {
    _applyRadius();
    final image = _toImage(local);
    widget.controller.pointerDown(image.dx, image.dy);
  }

  void _movePaint(Offset local) {
    _applyRadius();
    final image = _toImage(local);
    widget.controller.pointerMove(image.dx, image.dy);
  }

  void _finishPaint() {
    widget.controller.pointerUp();
  }

  bool _isPanButton(int buttons) {
    return buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0;
  }

  void _onDown(PointerDownEvent event) {
    if (_isPanButton(event.buttons)) {
      _finishPaint();
      _mousePanPointer = event.pointer;
      _mousePanLast = event.localPosition;
      return;
    }
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _paintPointer = event.pointer;
      _pinching = false;
      _startPaint(event.localPosition);
      return;
    }
    if (_pointers.length >= 2) {
      _finishPaint();
      _paintPointer = null;
      _pinching = true;
      final points = _pointers.values.toList();
      _pinchStartA = points[0];
      _pinchStartB = points[1];
      _pinchStartScale = _scale;
      _pinchStartOffset = _offset;
    }
  }

  void _onMove(PointerMoveEvent event) {
    if (_mousePanPointer == event.pointer && _mousePanLast != null) {
      final delta = event.localPosition - _mousePanLast!;
      _mousePanLast = event.localPosition;
      setState(() => _offset += delta);
      return;
    }
    if (!_pointers.containsKey(event.pointer)) {
      return;
    }
    _pointers[event.pointer] = event.localPosition;
    if (_pinching && _pointers.length >= 2) {
      final points = _pointers.values.toList();
      _applyPinch(points[0], points[1]);
      return;
    }
    if (_paintPointer == event.pointer) {
      _movePaint(event.localPosition);
    }
  }

  void _applyPinch(Offset a, Offset b) {
    final startA = _pinchStartA;
    final startB = _pinchStartB;
    if (startA == null || startB == null) {
      return;
    }
    final startDistance = (startA - startB).distance;
    final distance = (a - b).distance;
    if (startDistance < 1 || distance < 1) {
      return;
    }
    final factor = distance / startDistance;
    final focus = (a + b) / 2;
    final startFocus = (startA + startB) / 2;
    final imageFocus = (startFocus - _pinchStartOffset) / _pinchStartScale;
    setState(() {
      _scale = (_pinchStartScale * factor).clamp(0.25, 6);
      _offset = focus - imageFocus * _scale;
    });
  }

  void _onUp(PointerEvent event) {
    if (_mousePanPointer == event.pointer) {
      _mousePanPointer = null;
      _mousePanLast = null;
    }
    _pointers.remove(event.pointer);
    if (_pinching) {
      if (_pointers.length < 2) {
        _pinching = false;
        _paintPointer = null;
      }
      return;
    }
    if (_paintPointer == event.pointer) {
      _finishPaint();
      _paintPointer = null;
    }
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (event.kind == PointerDeviceKind.trackpad) {
      setState(() => _offset -= event.scrollDelta);
      return;
    }
    final factor = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
    final image = _toImage(event.localPosition);
    setState(() {
      _scale = (_scale * factor).clamp(0.25, 6);
      _offset = event.localPosition - image * _scale;
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _finishPaint();
    _panZoomStartScale = _scale;
    _panZoomStartLocal = event.localPosition;
    _panZoomFocalImage = _toImage(event.localPosition);
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final focal = _panZoomStartLocal + event.localPan;
    setState(() {
      _scale = (_panZoomStartScale * event.scale).clamp(0.25, 6);
      _offset = focal - _panZoomFocalImage * _scale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _fit(size);
        final controller = widget.controller;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          onPointerSignal: _onSignal,
          onPointerPanZoomStart: _onPanZoomStart,
          onPointerPanZoomUpdate: _onPanZoomUpdate,
          child: CustomPaint(
            painter: _SheetPainter(
              lineImage: controller.lineImage,
              colorImage: controller.colorImage,
              imageWidth: controller.art.width.toDouble(),
              imageHeight: controller.art.height.toDouble(),
              offset: _offset,
              scale: _scale,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _SheetPainter extends CustomPainter {
  const _SheetPainter({
    required this.lineImage,
    required this.colorImage,
    required this.imageWidth,
    required this.imageHeight,
    required this.offset,
    required this.scale,
  });

  final ui.Image? lineImage;
  final ui.Image? colorImage;
  final double imageWidth;
  final double imageHeight;
  final Offset offset;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    final page = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    canvas.drawRect(page, Paint()..color = Colors.white);
    final colors = colorImage;
    if (colors != null) {
      canvas.drawImage(colors, Offset.zero, Paint());
    }
    final lines = lineImage;
    if (lines != null) {
      canvas.drawImage(lines, Offset.zero, Paint());
    }
    canvas.drawRect(
      page,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / scale
        ..color = Colors.black26,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SheetPainter oldDelegate) {
    return oldDelegate.lineImage != lineImage ||
        oldDelegate.colorImage != colorImage ||
        oldDelegate.offset != offset ||
        oldDelegate.scale != scale;
  }
}
