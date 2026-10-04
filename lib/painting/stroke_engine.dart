import 'dart:math' as math;
import 'dart:typed_data';

class CanvasPoint {
  const CanvasPoint(this.x, this.y);

  final double x;
  final double y;
}

class PreparedArt {
  const PreparedArt({
    required this.width,
    required this.height,
    required this.walls,
    required this.lineRgba,
  });

  final int width;
  final int height;
  final Uint8List walls;
  final Uint8List lineRgba;
}

class ColorSheet {
  ColorSheet({
    required this.width,
    required this.height,
    required this.walls,
    Uint8List? pixels,
  }) : pixels = _matchingPixels(pixels, width, height);

  final int width;
  final int height;
  final Uint8List walls;
  Uint8List pixels;

  final List<Uint8List> _undo = [];
  final List<Uint8List> _redo = [];

  static const maxHistory = 15;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void checkpoint() {
    _undo.add(Uint8List.fromList(pixels));
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) {
      return;
    }
    _redo.add(Uint8List.fromList(pixels));
    pixels = _undo.removeLast();
  }

  void redo() {
    if (_redo.isEmpty) {
      return;
    }
    _undo.add(Uint8List.fromList(pixels));
    pixels = _redo.removeLast();
  }

  void clear() {
    checkpoint();
    pixels = Uint8List(width * height * 4);
  }
}

bool isDarkPixel(int r, int g, int b, int a) {
  if (a < 40) {
    return false;
  }
  final lum = (r * 30 + g * 59 + b * 11) ~/ 100;
  return lum < 190;
}

PreparedArt prepareArt(Uint8List rgba, int width, int height) {
  final rawWalls = Uint8List(width * height);
  final lines = Uint8List(rgba.length);
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    if (!isDarkPixel(rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3])) {
      continue;
    }
    rawWalls[i] = 1;
    lines[o + 3] = 255;
  }
  return PreparedArt(
    width: width,
    height: height,
    walls: dilateWalls(rawWalls, width, height),
    lineRgba: lines,
  );
}

Uint8List dilateWalls(Uint8List walls, int width, int height) {
  final out = Uint8List.fromList(walls);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (walls[y * width + x] == 0) {
        continue;
      }
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= height) {
          continue;
        }
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= width) {
            continue;
          }
          out[ny * width + nx] = 1;
        }
      }
    }
  }
  return out;
}

Uint8List? floodFillRegion(
  Uint8List walls,
  int width,
  int height,
  int x,
  int y,
) {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    return null;
  }
  if (walls[y * width + x] != 0) {
    return null;
  }

  final mask = Uint8List(width * height);
  final stack = <int>[y * width + x];
  while (stack.isNotEmpty) {
    final seed = stack.removeLast();
    var sx = seed % width;
    final sy = seed ~/ width;
    final row = sy * width;
    if (mask[row + sx] != 0 || walls[row + sx] != 0) {
      continue;
    }
    while (sx > 0 && walls[row + sx - 1] == 0 && mask[row + sx - 1] == 0) {
      sx--;
    }
    var spanUp = false;
    var spanDown = false;
    while (sx < width && walls[row + sx] == 0 && mask[row + sx] == 0) {
      mask[row + sx] = 1;
      if (sy > 0) {
        final up = row - width + sx;
        if (walls[up] == 0 && mask[up] == 0) {
          if (!spanUp) {
            stack.add(up);
            spanUp = true;
          }
        } else {
          spanUp = false;
        }
      }
      if (sy + 1 < height) {
        final down = row + width + sx;
        if (walls[down] == 0 && mask[down] == 0) {
          if (!spanDown) {
            stack.add(down);
            spanDown = true;
          }
        } else {
          spanDown = false;
        }
      }
      sx++;
    }
  }
  return mask;
}

Uint8List? floodFillEntry(Map<String, Object> args) {
  return floodFillRegion(
    args['walls']! as Uint8List,
    args['width']! as int,
    args['height']! as int,
    args['x']! as int,
    args['y']! as int,
  );
}

void paintPolyline({
  required Uint8List pixels,
  required Uint8List mask,
  required int width,
  required int height,
  required List<CanvasPoint> points,
  required double radius,
  required int red,
  required int green,
  required int blue,
  required bool erase,
}) {
  if (points.isEmpty || radius <= 0) {
    return;
  }
  var previous = points.first;
  _stamp(
    pixels: pixels,
    mask: mask,
    width: width,
    height: height,
    x: previous.x,
    y: previous.y,
    radius: radius,
    red: red,
    green: green,
    blue: blue,
    erase: erase,
  );
  for (final point in points.skip(1)) {
    final dx = point.x - previous.x;
    final dy = point.y - previous.y;
    final distance = math.sqrt(dx * dx + dy * dy);
    final step = math.max(1.0, radius / 3);
    final count = math.max(1, (distance / step).ceil());
    for (var i = 1; i <= count; i++) {
      final t = i / count;
      _stamp(
        pixels: pixels,
        mask: mask,
        width: width,
        height: height,
        x: previous.x + dx * t,
        y: previous.y + dy * t,
        radius: radius,
        red: red,
        green: green,
        blue: blue,
        erase: erase,
      );
    }
    previous = point;
  }
}

void _stamp({
  required Uint8List pixels,
  required Uint8List mask,
  required int width,
  required int height,
  required double x,
  required double y,
  required double radius,
  required int red,
  required int green,
  required int blue,
  required bool erase,
}) {
  final radiusSquared = radius * radius;
  final inner = radius * 0.65;
  final left = math.max(0, (x - radius).floor());
  final top = math.max(0, (y - radius).floor());
  final right = math.min(width - 1, (x + radius).ceil());
  final bottom = math.min(height - 1, (y + radius).ceil());

  for (var py = top; py <= bottom; py++) {
    for (var px = left; px <= right; px++) {
      final dx = px + 0.5 - x;
      final dy = py + 0.5 - y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared > radiusSquared) {
        continue;
      }
      final index = py * width + px;
      if (mask[index] == 0) {
        continue;
      }
      final distance = math.sqrt(distanceSquared);
      final cover = distance <= inner
          ? 1.0
          : ((radius - distance) / (radius - inner)).clamp(0.0, 1.0);
      final srcA = (255 * cover).round();
      if (srcA <= 0) {
        continue;
      }
      final offset = index * 4;
      if (erase) {
        final dstA = pixels[offset + 3];
        final nextA = dstA * (255 - srcA) ~/ 255;
        pixels[offset + 3] = nextA;
        if (nextA == 0) {
          pixels[offset] = 0;
          pixels[offset + 1] = 0;
          pixels[offset + 2] = 0;
        }
        continue;
      }
      final dstA = pixels[offset + 3];
      final outA = srcA + dstA * (255 - srcA) ~/ 255;
      if (outA == 0) {
        continue;
      }
      pixels[offset] =
          (red * srcA + pixels[offset] * dstA * (255 - srcA) ~/ 255) ~/ outA;
      pixels[offset + 1] =
          (green * srcA + pixels[offset + 1] * dstA * (255 - srcA) ~/ 255) ~/
          outA;
      pixels[offset + 2] =
          (blue * srcA + pixels[offset + 2] * dstA * (255 - srcA) ~/ 255) ~/
          outA;
      pixels[offset + 3] = outA;
    }
  }
}

Uint8List _matchingPixels(Uint8List? pixels, int width, int height) {
  final expected = width * height * 4;
  if (pixels != null && pixels.length == expected) {
    return pixels;
  }
  return Uint8List(expected);
}
