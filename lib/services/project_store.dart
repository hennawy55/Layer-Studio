import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/editor_project.dart';
import 'image_service.dart';

class ProjectStore {
  late Directory root;
  final _uuid = const Uuid();
  final _imageService = ImageService();

  Future<void> initialize() async {
    final base = await getApplicationSupportDirectory();
    root = Directory(p.join(base.path, 'LayerStudio', 'projects'));
    await root.create(recursive: true);
  }

  Future<Directory> _folder(String id) async {
    final folder = Directory(p.join(root.path, id));
    await folder.create(recursive: true);
    return folder;
  }

  Future<EditorProject> create(String imagePath) async {
    // Decode and bake EXIF orientation before measuring or displaying the
    // source image. Store a lossless PNG so Android and Windows render it
    // identically, independent of platform EXIF handling.
    final normalized = await _imageService.decode(imagePath);

    final id = _uuid.v4();
    final folder = await _folder(id);
    final assets = Directory(p.join(folder.path, 'assets'));
    await assets.create(recursive: true);

    final originalCopy = File(p.join(assets.path, 'original.png'));
    await _imageService.writePng(normalized, originalCopy.path);

    final now = DateTime.now();
    final project = EditorProject(
      id: id,
      name: 'Untitled project',
      originalPath: originalCopy.path,
      width: normalized.width,
      height: normalized.height,
      createdAt: now,
      updatedAt: now,
    );
    await save(project);
    return project;
  }

  Future<void> save(EditorProject project) async {
    project.updatedAt = DateTime.now();
    final folder = await _folder(project.id);
    final temp = File(p.join(folder.path, 'project.json.tmp'));
    final target = File(p.join(folder.path, 'project.json'));
    await temp.writeAsString(jsonEncode(project.toJson()), flush: true);
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
  }

  Future<List<EditorProject>> listProjects() async {
    final result = <EditorProject>[];
    if (!await root.exists()) return result;

    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'project.json'));
      if (!await file.exists()) continue;

      try {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final project = EditorProject.fromJson(data);
        if (await File(project.originalPath).exists()) {
          result.add(project);
        }
      } catch (_) {
        // Skip damaged project metadata without blocking other projects.
      }
    }

    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> delete(String id) async {
    final folder = Directory(p.join(root.path, id));
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  }

  Future<String> newId() async => _uuid.v4();
}
