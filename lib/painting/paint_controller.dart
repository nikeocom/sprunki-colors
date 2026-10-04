import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'raster.dart';
import 'stroke_engine.dart';

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

  bool get canUndo => _stroke == null && sheet.canUndo;
  bool get canRedo => _stroke == null && sheet.canRedo;

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
      }
    }
    final ix = x.floor();
    final iy = y.floor();
    if (ix < 0 || iy < 0 || ix >= art.width || iy >= art.height) {
      _stroke = null;
      return;
    }
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
      return;
    }
    sheet.checkpoint();
    stroke.mask = mask;
    _flush(stroke);
    if (stroke.closed) {
      _stroke = null;
      unawaited(_commit());
    }
    notifyListeners();
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
    unawaited(_upload());
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
    final generation = ++_imageGeneration;
    final copy = Uint8List.fromList(sheet.pixels);
    final image = await rgbaToImage(copy, art.width, art.height);
    if (_disposed || generation != _imageGeneration) {
      image.dispose();
      return;
    }
    colorImage?.dispose();
    colorImage = image;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stroke = null;
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
