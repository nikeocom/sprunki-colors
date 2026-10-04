import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

const maxImageSide = 1400;

Future<ui.Image> rgbaToImage(Uint8List rgba, int width, int height) {
  final copy = Uint8List.fromList(rgba);
  return _decode(copy, width, height);
}

Future<ui.Image> _decode(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<Uint8List> encodeRgbaPng(Uint8List rgba, int width, int height) async {
  final image = await rgbaToImage(rgba, width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class DecodedImage {
  const DecodedImage({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

Future<DecodedImage> decodeToRgba(Uint8List bytes) async {
  final probe = await ui.instantiateImageCodec(bytes);
  final probed = await probe.getNextFrame();
  var image = probed.image;
  final maxSide = math.max(image.width, image.height);
  if (maxSide > maxImageSide) {
    final scale = maxImageSide / maxSide;
    final targetWidth = math.max(1, (image.width * scale).round());
    final targetHeight = math.max(1, (image.height * scale).round());
    image.dispose();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final resized = await codec.getNextFrame();
    image = resized.image;
  }
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final decoded = DecodedImage(
    rgba: data!.buffer.asUint8List(),
    width: image.width,
    height: image.height,
  );
  image.dispose();
  return decoded;
}

Future<DecodedImage> rasterizeSvgAsset(String asset) async {
  final info = await vg.loadPicture(SvgAssetLoader(asset), null);
  try {
    final sourceWidth = math.max(1, info.size.width.round());
    final sourceHeight = math.max(1, info.size.height.round());
    final maxSide = math.max(sourceWidth, sourceHeight);
    final scale = maxImageSide / maxSide;
    final width = math.max(1, (sourceWidth * scale).round());
    final height = math.max(1, (sourceHeight * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(width / info.size.width, height / info.size.height);
    canvas.drawPicture(info.picture);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final decoded = DecodedImage(
      rgba: data!.buffer.asUint8List(),
      width: width,
      height: height,
    );
    image.dispose();
    return decoded;
  } finally {
    info.picture.dispose();
  }
}
