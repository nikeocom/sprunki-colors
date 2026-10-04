import 'package:flutter/material.dart';

class Palette {
  const Palette({required this.id, required this.title, required this.colors});

  final String id;
  final String title;
  final List<Color> colors;
}

const palettes = <Palette>[
  Palette(
    id: 'bright',
    title: 'Яркая',
    colors: [
      Color(0xFFFF7A00),
      Color(0xFFFF3B30),
      Color(0xFFFFD400),
      Color(0xFF7CFF00),
      Color(0xFF00C853),
      Color(0xFF00B0FF),
      Color(0xFF2962FF),
      Color(0xFFAA00FF),
      Color(0xFFFF4081),
      Color(0xFF8D6E63),
      Color(0xFF212121),
      Color(0xFFFFFFFF),
    ],
  ),
  Palette(
    id: 'pastel',
    title: 'Пастель',
    colors: [
      Color(0xFFFFCC80),
      Color(0xFFFFAB91),
      Color(0xFFFFF59D),
      Color(0xFFC5E1A5),
      Color(0xFF80CBC4),
      Color(0xFF81D4FA),
      Color(0xFF9FA8DA),
      Color(0xFFCE93D8),
      Color(0xFFF8BBD0),
      Color(0xFFBCAAA4),
      Color(0xFF90A4AE),
      Color(0xFFFFFFFF),
    ],
  ),
  Palette(
    id: 'neon',
    title: 'Неон',
    colors: [
      Color(0xFFCCFF00),
      Color(0xFF39FF14),
      Color(0xFF00FFF0),
      Color(0xFF00B3FF),
      Color(0xFF7A5CFF),
      Color(0xFFFF00E5),
      Color(0xFFFF2E97),
      Color(0xFFFF5A00),
      Color(0xFFFFFF00),
      Color(0xFFFF1744),
      Color(0xFF111111),
      Color(0xFFFFFFFF),
    ],
  ),
  Palette(
    id: 'crayon',
    title: 'Карандаши',
    colors: [
      Color(0xFFE53935),
      Color(0xFFFB8C00),
      Color(0xFFFDD835),
      Color(0xFF43A047),
      Color(0xFF1E88E5),
      Color(0xFF8E24AA),
      Color(0xFFEC407A),
      Color(0xFF6D4C41),
      Color(0xFF78909C),
      Color(0xFFF48FB1),
      Color(0xFF212121),
      Color(0xFFFFFFFF),
    ],
  ),
];

const brushRadii = <double>[8, 18, 36];

int colorChannel(double channel) => (channel * 255).round().clamp(0, 255);
