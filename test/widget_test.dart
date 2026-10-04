import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprunki_paint/data/builtin_pages.dart';
import 'package:sprunki_paint/main.dart';
import 'package:sprunki_paint/painting/paint_controller.dart';
import 'package:sprunki_paint/painting/raster.dart';
import 'package:sprunki_paint/painting/stroke_engine.dart';
import 'package:sprunki_paint/screens/paint_screen.dart';
import 'package:sprunki_paint/storage/progress_store.dart';

void main() {
  testWidgets('gallery lists the coloring pages', (tester) async {
    await tester.pumpWidget(const SprunkiPaintApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Орен'), findsOneWidget);
    expect(find.text('Пинки'), findsOneWidget);
    expect(find.textContaining('SPRUNKI'), findsOneWidget);
    expect(find.text('Открыть картинку'), findsOneWidget);
  });

  testWidgets('paint screen shows brushes for a page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaintScreen(
          page: builtinPages.first,
          store: _MemoryStore(),
          loadArt: () async => prepareArt(Uint8List(32 * 32 * 4), 32, 32),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Ластик'), findsOneWidget);
    expect(find.text('Яркая'), findsOneWidget);
    expect(find.text('Орен'), findsOneWidget);
  });

  testWidgets('undo enables when the first stroke ends', (tester) async {
    const side = 16;
    final controller = PaintController(
      art: PreparedArt(
        width: side,
        height: side,
        walls: Uint8List(side * side),
        lineRgba: Uint8List(side * side * 4),
      ),
      flood: (walls, width, height, x, y) async {
        return floodFillRegion(walls, width, height, x, y);
      },
    );
    addTearDown(controller.dispose);
    var notices = 0;
    controller.addListener(() => notices++);

    controller.pointerDown(8, 8);
    controller.pointerMove(10, 8);
    controller.pointerMove(12, 6);
    expect(controller.livePointCount, 3);
    await tester.pump();
    expect(controller.sheet.canUndo, isTrue);
    expect(controller.canUndo, isFalse);
    expect(controller.sheet.pixels[(8 * side + 12) * 4 + 3], greaterThan(0));

    final beforeLift = notices;
    controller.pointerUp();
    expect(controller.canUndo, isTrue);
    expect(notices, greaterThan(beforeLift));
    await tester.pump();
  });

  testWidgets('svg raster keeps a closed outline', (tester) async {
    final decoded = await tester.runAsync(
      () => rasterizeSvgAsset('assets/pages/oren.svg'),
    );
    expect(decoded, isNotNull);
    expect(decoded!.width, greaterThan(500));
    final art = prepareArt(decoded.rgba, decoded.width, decoded.height);
    expect(art.walls.contains(1), isTrue);
    expect(art.walls[0], 0);
    final faceX = (300 * decoded.width / 600).round();
    final faceY = (450 * decoded.height / 800).round();
    expect(art.walls[faceY * art.width + faceX], 0);
    final face = floodFillRegion(
      art.walls,
      art.width,
      art.height,
      faceX,
      faceY,
    );
    final background = floodFillRegion(art.walls, art.width, art.height, 4, 4);
    expect(face, isNotNull);
    expect(background, isNotNull);
    expect(face![4 * art.width + 4], 0);
    expect(background![faceY * art.width + faceX], 0);
  });

  testWidgets('new coloring pages rasterize', (tester) async {
    for (final asset in [
      'assets/pages/vedro.svg',
      'assets/pages/veneria.svg',
      'assets/pages/pinkie.svg',
      'assets/pages/gruppa_1.svg',
      'assets/pages/gruppa_2.svg',
    ]) {
      final decoded = await tester.runAsync(() => rasterizeSvgAsset(asset));
      expect(decoded, isNotNull, reason: asset);
      final art = prepareArt(decoded!.rgba, decoded.width, decoded.height);
      expect(art.walls.contains(1), isTrue, reason: asset);
      expect(art.walls.contains(0), isTrue, reason: asset);
    }
  });
}

class _MemoryStore extends ProgressStore {
  @override
  Future<Uint8List?> loadColors(String id) async => null;

  @override
  Future<void> saveColors(String id, Uint8List png) async {}
}
