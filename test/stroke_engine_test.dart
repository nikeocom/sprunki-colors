import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprunki_paint/painting/stroke_engine.dart';

void main() {
  test('stroke inside a circle stays inside until the gesture ends', () {
    const width = 120;
    const height = 120;
    final walls = _circleWalls(width, height);
    final inside = floodFillRegion(walls, width, height, 60, 60);
    expect(inside, isNotNull);
    expect(inside![60 * width + 60], 1);
    expect(inside[10 * width + 10], 0);

    final pixels = Uint8List(width * height * 4);
    paintPolyline(
      pixels: pixels,
      mask: inside,
      width: width,
      height: height,
      points: const [CanvasPoint(60, 60), CanvasPoint(5, 5)],
      radius: 30,
      red: 255,
      green: 0,
      blue: 0,
      erase: false,
    );

    expect(_alpha(pixels, width, 60, 60), greaterThan(200));
    expect(_alpha(pixels, width, 5, 5), 0);
    expect(_alpha(pixels, width, 60, 8), 0);

    final outside = floodFillRegion(walls, width, height, 8, 8)!;
    paintPolyline(
      pixels: pixels,
      mask: outside,
      width: width,
      height: height,
      points: const [CanvasPoint(8, 8)],
      radius: 6,
      red: 0,
      green: 200,
      blue: 0,
      erase: false,
    );

    expect(_alpha(pixels, width, 8, 8), greaterThan(200));
    expect(pixels[(8 * width + 8) * 4 + 1], greaterThan(150));
    expect(pixels[(60 * width + 60) * 4], greaterThan(200));
    expect(pixels[(60 * width + 60) * 4 + 1], 0);
  });

  test('a one pixel gap does not leak after the outline is thickened', () {
    const width = 100;
    const height = 100;
    final raw = Uint8List(width * height);
    for (var x = 20; x <= 80; x++) {
      raw[20 * width + x] = 1;
      raw[80 * width + x] = 1;
    }
    raw[20 * width + 50] = 0;
    for (var y = 20; y <= 80; y++) {
      raw[y * width + 20] = 1;
      raw[y * width + 80] = 1;
    }
    final walls = dilateWalls(raw, width, height);
    final inside = floodFillRegion(walls, width, height, 50, 50)!;
    final outside = floodFillRegion(walls, width, height, 5, 5)!;
    expect(inside[5 * width + 5], 0);
    expect(outside[50 * width + 50], 0);
  });

  test('tapping the outline does not start a region', () {
    const width = 120;
    const height = 120;
    final walls = _circleWalls(width, height);
    final wallIndex = walls.indexOf(1);
    expect(
      floodFillRegion(
        walls,
        width,
        height,
        wallIndex % width,
        wallIndex ~/ width,
      ),
      isNull,
    );
  });

  test('eraser and undo stay inside the active region', () {
    const width = 120;
    const height = 120;
    final walls = _circleWalls(width, height);
    final sheet = ColorSheet(width: width, height: height, walls: walls);
    final inside = floodFillRegion(walls, width, height, 60, 60)!;
    sheet.checkpoint();
    paintPolyline(
      pixels: sheet.pixels,
      mask: inside,
      width: width,
      height: height,
      points: const [CanvasPoint(60, 60)],
      radius: 50,
      red: 255,
      green: 0,
      blue: 0,
      erase: false,
    );
    expect(_alpha(sheet.pixels, width, 60, 40), greaterThan(0));

    sheet.checkpoint();
    paintPolyline(
      pixels: sheet.pixels,
      mask: inside,
      width: width,
      height: height,
      points: const [CanvasPoint(60, 60)],
      radius: 8,
      red: 0,
      green: 0,
      blue: 0,
      erase: true,
    );
    expect(_alpha(sheet.pixels, width, 60, 60), 0);
    expect(_alpha(sheet.pixels, width, 60, 40), greaterThan(0));
    expect(_alpha(sheet.pixels, width, 8, 8), 0);

    sheet.undo();
    expect(_alpha(sheet.pixels, width, 60, 60), greaterThan(200));
  });
}

Uint8List _circleWalls(int width, int height) {
  final raw = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final dx = x - 60;
      final dy = y - 60;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance >= 36 && distance <= 40) {
        raw[y * width + x] = 1;
      }
    }
  }
  return dilateWalls(raw, width, height);
}

int _alpha(Uint8List pixels, int width, int x, int y) {
  return pixels[(y * width + x) * 4 + 3];
}
