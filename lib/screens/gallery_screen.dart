import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/builtin_pages.dart';
import '../painting/raster.dart';
import '../painting/stroke_engine.dart';
import '../storage/progress_store.dart';
import 'paint_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final ProgressStore _store = ProgressStore();
  List<PageRef> _imports = const [];
  Map<String, Uint8List> _colors = const {};
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final imports = await _store.listImports();
      final colors = <String, Uint8List>{};
      for (final page in [...builtinPages, ...imports.map(_toPage)]) {
        final saved = await _store.loadColors(page.id);
        if (saved != null) {
          colors[page.id] = saved;
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _imports = imports.map(_toPage).toList();
        _colors = colors;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _imports = const [];
        _colors = const {};
      });
    }
  }

  PageRef _toPage(StoredImport item) {
    return PageRef(id: item.id, title: item.title, filePath: item.filePath);
  }

  Future<void> _open(PageRef page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => PaintScreen(page: page)));
    await _reload();
  }

  Future<void> _import() async {
    if (_importing) {
      return;
    }
    setState(() => _importing = true);
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Открыть картинку',
        type: FileType.image,
      );
      if (picked == null || !mounted) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final decoded = await decodeToRgba(bytes);
      final art = prepareArt(decoded.rgba, decoded.width, decoded.height);
      if (!art.walls.contains(1)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('На картинке нет тёмного контура')),
          );
        }
        return;
      }
      final rawName = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
      final title = rawName.isEmpty ? 'Картинка' : rawName;
      final id = 'import_${DateTime.now().millisecondsSinceEpoch}';
      final png = await encodeRgbaPng(art.lineRgba, art.width, art.height);
      await _store.saveImport(id, title, png);
      await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не получилось открыть картинку')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _delete(PageRef page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить картинку?'),
        content: Text(page.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _store.deleteImport(page.id);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [...builtinPages, ..._imports];
    return Scaffold(
      appBar: AppBar(title: const Text('Раскраска')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _importing ? null : _import,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Открыть картинку'),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1200 ? 4 : (width >= 840 ? 3 : 2);
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: pages.length,
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    return _PageCard(
                      page: page,
                      colors: _colors[page.id],
                      onTap: () => _open(page),
                      onDelete: page.isImported ? () => _delete(page) : null,
                    );
                  },
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Фанатская раскраска по мотивам SPRUNKI, не официальное приложение.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.page,
    required this.colors,
    required this.onTap,
    this.onDelete,
  });

  final PageRef page;
  final Uint8List? colors;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.white),
                    if (colors != null)
                      Positioned.fill(
                        child: Image.memory(colors!, fit: BoxFit.contain),
                      ),
                    if (page.asset != null)
                      Positioned.fill(
                        child: SvgPicture.asset(
                          page.asset!,
                          fit: BoxFit.contain,
                        ),
                      )
                    else if (page.filePath != null)
                      Positioned.fill(
                        child: Image.file(
                          File(page.filePath!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    if (onDelete != null)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          tooltip: 'Удалить',
                          onPressed: onDelete,
                          icon: const Icon(Icons.close),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                page.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
