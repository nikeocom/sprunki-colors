import 'package:flutter/material.dart';

import 'screens/gallery_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SprunkiPaintApp());
}

class SprunkiPaintApp extends StatelessWidget {
  const SprunkiPaintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Раскраска',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7A18)),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      home: const GalleryScreen(),
    );
  }
}
