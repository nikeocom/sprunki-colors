import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class StoredImport {
  const StoredImport({
    required this.id,
    required this.title,
    required this.filePath,
  });

  final String id;
  final String title;
  final String filePath;
}

class ProgressStore {
  Future<Directory> _folder(String name) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/sprunki_paint/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> saveColors(String id, Uint8List png) async {
    final dir = await _folder('progress');
    await File('${dir.path}/$id.png').writeAsBytes(png, flush: true);
  }

  Future<Uint8List?> loadColors(String id) async {
    final dir = await _folder('progress');
    final file = File('${dir.path}/$id.png');
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<void> deleteColors(String id) async {
    final dir = await _folder('progress');
    final file = File('${dir.path}/$id.png');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<StoredImport> saveImport(
    String id,
    String title,
    Uint8List png,
  ) async {
    final dir = await _folder('imports');
    final image = File('${dir.path}/$id.png');
    final label = File('${dir.path}/$id.txt');
    await image.writeAsBytes(png, flush: true);
    await label.writeAsString(title, flush: true);
    return StoredImport(id: id, title: title, filePath: image.path);
  }

  Future<List<StoredImport>> listImports() async {
    final dir = await _folder('imports');
    final files = await dir.list().toList();
    final imports = <StoredImport>[];
    for (final entity in files) {
      if (entity is! File || !entity.path.endsWith('.png')) {
        continue;
      }
      final id = entity.uri.pathSegments.last.replaceAll('.png', '');
      final label = File('${dir.path}/$id.txt');
      final title = await label.exists()
          ? (await label.readAsString()).trim()
          : id;
      imports.add(
        StoredImport(
          id: id,
          title: title.isEmpty ? 'Картинка' : title,
          filePath: entity.path,
        ),
      );
    }
    imports.sort((a, b) => b.id.compareTo(a.id));
    return imports;
  }

  Future<void> deleteImport(String id) async {
    final dir = await _folder('imports');
    final image = File('${dir.path}/$id.png');
    final label = File('${dir.path}/$id.txt');
    if (await image.exists()) {
      await image.delete();
    }
    if (await label.exists()) {
      await label.delete();
    }
    await deleteColors(id);
  }
}
