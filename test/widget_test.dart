import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprunki_paint/data/builtin_pages.dart';
import 'package:sprunki_paint/main.dart';
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
    final face = floodFillRegion(art.walls, art.width, art.height, faceX, faceY);
    final background = floodFillRegion(art.walls, art.width, art.height, 4, 4);
    expect(face, isNotNull);
    expect(background, isNotNull);
    expect(face![4 * art.width + 4], 0);
    expect(background![faceY * art.width + faceX], 0);
  });
}

class _MemoryStore extends ProgressStore {
  @override
  Future<Uint8List?> loadColors(String id) async => null;

  @override
  Future<void> saveColors(String id, Uint8List png) async {}
}
