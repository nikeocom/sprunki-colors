import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/builtin_pages.dart';
import '../data/palettes.dart';
import '../painting/paint_controller.dart';
import '../painting/raster.dart';
import '../painting/stroke_engine.dart';
import '../storage/progress_store.dart';
import '../widgets/coloring_canvas.dart';

class PaintScreen extends StatefulWidget {
  const PaintScreen({super.key, required this.page, this.store, this.loadArt});

  final PageRef page;
  final ProgressStore? store;
  final Future<PreparedArt> Function()? loadArt;

  @override
  State<PaintScreen> createState() => PaintScreenState();
}

class PaintScreenState extends State<PaintScreen> {
  final ProgressStore _store = ProgressStore();
  PaintController? _controller;
  String? _error;
  int _paletteIndex = 0;
  int _sizeIndex = 1;
  int _colorIndex = 0;
  bool _erasing = false;
  int _saveGeneration = 0;
  bool _savingFile = false;

  ProgressStore get store => widget.store ?? _store;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final PreparedArt art;
      if (widget.loadArt != null) {
        art = await widget.loadArt!();
      } else if (widget.page.asset != null) {
        final decoded = await rasterizeSvgAsset(widget.page.asset!);
        art = prepareArt(decoded.rgba, decoded.width, decoded.height);
      } else {
        final decoded = await decodeToRgba(
          await File(widget.page.filePath!).readAsBytes(),
        );
        art = prepareArt(decoded.rgba, decoded.width, decoded.height);
      }
      Uint8List? colors;
      try {
        final saved = await store.loadColors(widget.page.id);
        if (saved != null) {
          final layer = await decodeToRgba(saved);
          if (layer.width == art.width && layer.height == art.height) {
            colors = layer.rgba;
          }
        }
      } catch (_) {
        colors = null;
      }
      final controller = PaintController(
        art: art,
        colors: colors,
        onStrokeCommitted: _persist,
      );
      _applyBrush(controller);
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.addListener(_onController);
      setState(() => _controller = controller);
      unawaited(controller.loadImages());
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Не получилось открыть лист');
    }
  }

  void _onController() {
    if (mounted) {
      setState(() {});
    }
  }

  void _applyBrush(PaintController controller) {
    final color = palettes[_paletteIndex].colors[_colorIndex];
    controller
      ..erasing = _erasing
      ..paintRed = colorChannel(color.r)
      ..paintGreen = colorChannel(color.g)
      ..paintBlue = colorChannel(color.b);
  }

  Future<void> _persist() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final generation = ++_saveGeneration;
    final copy = Uint8List.fromList(controller.sheet.pixels);
    try {
      final png = await encodeRgbaPng(
        copy,
        controller.art.width,
        controller.art.height,
      );
      if (generation != _saveGeneration) {
        return;
      }
      await store.saveColors(widget.page.id, png);
    } catch (_) {
      // The drawing stays in memory if the disk is unavailable.
    }
  }

  Future<void> _export() async {
    final controller = _controller;
    if (controller == null || _savingFile) {
      return;
    }
    setState(() => _savingFile = true);
    try {
      final png = await controller.exportPng();
      if (!mounted) {
        return;
      }
      final name = _fileName();
      if (Platform.isAndroid) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(png, flush: true);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], title: widget.page.title),
        );
      } else {
        await FilePicker.saveFile(
          fileName: name,
          bytes: png,
          mimeType: 'image/png',
          dialogTitle: 'Сохранить',
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не получилось сохранить файл')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingFile = false);
      }
    }
  }

  String _fileName() {
    final cleaned = widget.page.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    return '${cleaned.isEmpty ? 'раскраска' : cleaned}.png';
  }

  Future<void> _clear() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Стереть раскраску?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Стереть'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.clear();
    }
  }

  void _selectColor(int index) {
    setState(() {
      _colorIndex = index;
      _erasing = false;
    });
    final controller = _controller;
    if (controller != null) {
      _applyBrush(controller);
    }
  }

  void _selectEraser() {
    setState(() => _erasing = true);
    final controller = _controller;
    if (controller != null) {
      controller.erasing = true;
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onController);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFFE8E4F2),
      appBar: AppBar(
        title: Text(widget.page.title),
        actions: [
          IconButton(
            tooltip: 'Отмена',
            onPressed: controller != null && controller.canUndo
                ? controller.undo
                : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Повтор',
            onPressed: controller != null && controller.canRedo
                ? controller.redo
                : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'Стереть',
            onPressed: controller == null ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Сохранить',
            onPressed: controller == null || _savingFile ? null : _export,
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      body: controller == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final tablet = constraints.maxWidth >= 840;
                final tools = _ToolPanel(
                  compact: !tablet,
                  paletteIndex: _paletteIndex,
                  colorIndex: _colorIndex,
                  sizeIndex: _sizeIndex,
                  erasing: _erasing,
                  onPalette: (index) => setState(() {
                    _paletteIndex = index;
                    _colorIndex = 0;
                    _erasing = false;
                    _applyBrush(controller);
                  }),
                  onColor: _selectColor,
                  onSize: (index) => setState(() => _sizeIndex = index),
                  onEraser: _selectEraser,
                );
                final canvas = ColoringCanvas(
                  controller: controller,
                  screenRadius: brushRadii[_sizeIndex],
                );
                if (tablet) {
                  return Row(
                    children: [
                      SizedBox(width: 248, child: tools),
                      const VerticalDivider(width: 1),
                      Expanded(child: canvas),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: canvas),
                    tools,
                  ],
                );
              },
            ),
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    required this.compact,
    required this.paletteIndex,
    required this.colorIndex,
    required this.sizeIndex,
    required this.erasing,
    required this.onPalette,
    required this.onColor,
    required this.onSize,
    required this.onEraser,
  });

  final bool compact;
  final int paletteIndex;
  final int colorIndex;
  final int sizeIndex;
  final bool erasing;
  final ValueChanged<int> onPalette;
  final ValueChanged<int> onColor;
  final ValueChanged<int> onSize;
  final VoidCallback onEraser;

  @override
  Widget build(BuildContext context) {
    final palette = palettes[paletteIndex];
    final paletteChips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < palettes.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(palettes[i].title),
                selected: i == paletteIndex,
                onSelected: (_) => onPalette(i),
              ),
            ),
        ],
      ),
    );
    final sizes = Row(
      children: [
        for (var i = 0; i < brushRadii.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _SizeButton(
              radius: 6.0 + i * 5,
              selected: i == sizeIndex && !erasing,
              onTap: () => onSize(i),
            ),
          ),
        const Spacer(),
        FilterChip(
          label: const Text('Ластик'),
          selected: erasing,
          onSelected: (_) => onEraser(),
        ),
      ],
    );
    final colors = [
      for (var i = 0; i < palette.colors.length; i++)
        _ColorButton(
          color: palette.colors[i],
          selected: i == colorIndex && !erasing,
          onTap: () => onColor(i),
        ),
    ];

    final body = compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              paletteChips,
              const SizedBox(height: 8),
              sizes,
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: colors.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => colors[index],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              paletteChips,
              const SizedBox(height: 16),
              sizes,
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: colors),
            ],
          );

    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: compact ? body : SingleChildScrollView(child: body),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Кисть',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? Colors.black : Colors.black26,
              width: selected ? 4 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeButton extends StatelessWidget {
  const _SizeButton({
    required this.radius,
    required this.selected,
    required this.onTap,
  });

  final double radius;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? const Color(0xFFFFE0C2) : const Color(0xFFF3F3F3),
          border: Border.all(
            color: selected ? const Color(0xFFFF7A00) : Colors.black12,
            width: selected ? 3 : 1,
          ),
        ),
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
