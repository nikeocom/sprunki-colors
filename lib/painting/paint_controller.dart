import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'raster.dart';
import 'stroke_engine.dart';

class StrokePreview {
  const StrokePreview({
    required this.points,
    required this.radius,
    required this.red,
    required this.green,
    required this.blue,
    required this.erase,
    required this.mask,
    required this.serial,
  });

  final List<ui.Offset> points;
  final double radius;
  final int red;
  final int green;
  final int blue;
  final bool erase;
  final ui.Image mask;
  final int serial;
}

class _LiveStroke {
  final List<CanvasPoint> pending = [];
  Uint8List? mask;
  bool closed = false;
  CanvasPoint? lastPainted;
}

class PaintController extends ChangeNotifier {
  PaintController({
    required this.art,
    Uint8List? colors,
    this.onStrokeCommitted,
    Future<Uint8List?> Function(
      Uint8List walls,
      int width,
      int height,
      int x,
      int y,
    )?
    flood,
  }) : sheet = ColorSheet(
         width: art.width,
         height: art.height,
         walls: art.walls,
         pixels: colors,
       ),
       _flood = flood ?? _isolateFlood;

  final PreparedArt art;
  final ColorSheet sheet;
  final Future<void> Function()? onStrokeCommitted;
  final Future<Uint8List?> Function(
    Uint8List walls,
    int width,
    int height,
    int x,
    int y,
  )
  _flood;

  ui.Image? colorImage;
  ui.Image? lineImage;

  _LiveStroke? _stroke;
  bool _disposed = false;
  int _imageGeneration = 0;
  int _epoch = 0;
  int _previewSerial = 0;
  final List<ui.Offset> _previewPoints = [];
  ui.Image? _previewMask;
  double _previewRadius = 1;
  int _previewRed = 0;
  int _previewGreen = 0;
  int _previewBlue = 0;
  bool _previewErase = false;

  bool get canUndo => _stroke == null && sheet.canUndo;
  bool get canRedo => _stroke == null && sheet.canRedo;
  bool get hasActiveStroke => _stroke != null;
  bool get showLiveStroke => _previewPoints.isNotEmpty && _previewMask != null;
  int get livePointCount => _previewPoints.length;
  int get previewSerial => _previewSerial;

  StrokePreview? get strokePreview {
    final mask = _previewMask;
    if (mask == null || _previewPoints.isEmpty) {
      return null;
    }
    return StrokePreview(
      points: _previewPoints,
      radius: _previewRadius,
      red: _previewRed,
      green: _previewGreen,
      blue: _previewBlue,
      erase: _previewErase,
      mask: mask,
      serial: _previewSerial,
    );
  }

  Future<void> loadImages() async {
    lineImage = await rgbaToImage(art.lineRgba, art.width, art.height);
    colorImage = await rgbaToImage(sheet.pixels, sheet.width, sheet.height);
    if (_disposed) {
      lineImage?.dispose();
      colorImage?.dispose();
      return;
    }
    notifyListeners();
  }

  void pointerDown(double x, double y) {
    final previous = _stroke;
    if (previous != null) {
      previous.closed = true;
      if (previous.mask != null) {
        _flush(previous);
        unawaited(_commit());
        unawaited(_upload());
      }
      _stroke = null;
    }
    final ix = x.floor();
    final iy = y.floor();
    if (ix < 0 || iy < 0 || ix >= art.width || iy >= art.height) {
      notifyListeners();
      return;
    }
    _startPreview(x, y);
    final stroke = _LiveStroke()..pending.add(CanvasPoint(x, y));
    _stroke = stroke;
    unawaited(_resolveMask(stroke, ix, iy));
  }

  void pointerMove(double x, double y) {
    final stroke = _stroke;
    if (stroke == null || stroke.closed) {
      return;
    }
    stroke.pending.add(CanvasPoint(x, y));
    _rememberPreviewPoint(x, y);
    if (stroke.mask != null) {
      _flush(stroke);
    }
  }

  void pointerUp() {
    final stroke = _stroke;
    if (stroke == null) {
      return;
    }
    stroke.closed = true;
    if (stroke.mask != null) {
      _flush(stroke);
      _stroke = null;
      unawaited(_commit());
      unawaited(_upload());
      notifyListeners();
    }
  }

  Future<void> _resolveMask(_LiveStroke stroke, int x, int y) async {
    Uint8List? mask;
    try {
      mask = await _flood(art.walls, art.width, art.height, x, y);
    } catch (_) {
      mask = null;
    }
    if (_disposed || _stroke != stroke) {
      return;
    }
    if (mask == null) {
      _stroke = null;
      notifyListeners();
      return;
    }
    sheet.checkpoint();
    stroke.mask = mask;
    _flush(stroke);
    if (stroke.closed) {
      _stroke = null;
      unawaited(_commit());
      unawaited(_upload());
    } else {
      unawaited(_loadPreviewMask(stroke, mask));
    }
    notifyListeners();
  }

  void _startPreview(double x, double y) {
    _epoch++;
    _previewPoints.clear();
    _previewMask?.dispose();
    _previewMask = null;
    _rememberPreviewPoint(x, y);
  }

  void _rememberPreviewPoint(double x, double y) {
    _previewPoints.add(ui.Offset(x, y));
    _previewRadius = strokeRadius;
    _previewRed = paintRed;
    _previewGreen = paintGreen;
    _previewBlue = paintBlue;
    _previewErase = erasing;
    _previewSerial++;
  }

  Future<void> _loadPreviewMask(_LiveStroke stroke, Uint8List mask) async {
    final rgba = Uint8List(art.width * art.height * 4);
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0) {
        continue;
      }
      final offset = i * 4;
      rgba[offset] = 255;
      rgba[offset + 1] = 255;
      rgba[offset + 2] = 255;
      rgba[offset + 3] = 255;
    }
    final image = await rgbaToImage(rgba, art.width, art.height);
    if (_disposed || _stroke != stroke) {
      image.dispose();
      return;
    }
    _previewMask?.dispose();
    _previewMask = image;
    _previewSerial++;
    notifyListeners();
  }

  void _clearPreview() {
    if (_previewPoints.isEmpty && _previewMask == null) {
      return;
    }
    _previewPoints.clear();
    _previewMask?.dispose();
    _previewMask = null;
    _previewSerial++;
  }

  void _flush(_LiveStroke stroke) {
    final mask = stroke.mask;
    if (mask == null || stroke.pending.isEmpty) {
      return;
    }
    final points = <CanvasPoint>[
      if (stroke.lastPainted != null) stroke.lastPainted!,
      ...stroke.pending,
    ];
    stroke.pending.clear();
    paintPolyline(
      pixels: sheet.pixels,
      mask: mask,
      width: art.width,
      height: art.height,
      points: points,
      radius: strokeRadius,
      red: paintRed,
      green: paintGreen,
      blue: paintBlue,
      erase: erasing,
    );
    stroke.lastPainted = points.last;
  }

  int paintRed = 255;
  int paintGreen = 122;
  int paintBlue = 0;
  bool erasing = false;
  double strokeRadius = 18;

  void undo() {
    if (!canUndo) {
      return;
    }
    sheet.undo();
    unawaited(_upload());
    unawaited(_commit());
    notifyListeners();
  }

  void redo() {
    if (!canRedo) {
      return;
    }
    sheet.redo();
    unawaited(_upload());
    unawaited(_commit());
    notifyListeners();
  }

  void clear() {
    if (_stroke != null) {
      return;
    }
    sheet.clear();
    unawaited(_upload());
    unawaited(_commit());
    notifyListeners();
  }

  Future<Uint8List> exportPng() async {
    await _upload();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final width = art.width.toDouble();
    final height = art.height.toDouble();
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final color = colorImage;
    final lines = lineImage;
    if (color != null) {
      canvas.drawImage(color, ui.Offset.zero, ui.Paint());
    }
    if (lines != null) {
      canvas.drawImage(lines, ui.Offset.zero, ui.Paint());
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(art.width, art.height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> _commit() async {
    final callback = onStrokeCommitted;
    if (callback == null) {
      return;
    }
    await callback();
  }

  Future<void> _upload() async {
    final epoch = _epoch;
    final generation = ++_imageGeneration;
    final copy = Uint8List.fromList(sheet.pixels);
    final image = await rgbaToImage(copy, art.width, art.height);
    if (_disposed || generation != _imageGeneration) {
      image.dispose();
      return;
    }
    colorImage?.dispose();
    colorImage = image;
    if (epoch == _epoch && _stroke == null) {
      _clearPreview();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stroke = null;
    _clearPreview();
    colorImage?.dispose();
    lineImage?.dispose();
    super.dispose();
  }
}

Future<Uint8List?> _isolateFlood(
  Uint8List walls,
  int width,
  int height,
  int x,
  int y,
) {
  return compute(floodFillEntry, {
    'walls': walls,
    'width': width,
    'height': height,
    'x': x,
    'y': y,
  });
}
