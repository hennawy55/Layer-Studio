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
    final extension = p.extension(imagePath).toLowerCase();
    final keepJpeg = extension == '.jpg' || extension == '.jpeg';

    final id = _uuid.v4();
    final folder = await _folder(id);
    final assets = Directory(p.join(folder.path, 'assets'));
    await assets.create(recursive: true);

    try {
      final originalCopy = File(
        p.join(assets.path, keepJpeg ? 'original.jpg' : 'original.png'),
      );
      final dimensions = await _imageService.normalizeToFile(
        imagePath,
        originalCopy.path,
        asJpeg: keepJpeg,
        jpegQuality: 96,
      );

      final now = DateTime.now();
      final project = EditorProject(
        id: id,
        name: 'Untitled project',
        originalPath: originalCopy.path,
        width: dimensions.width,
        height: dimensions.height,
        formatVersion: 2,
        createdAt: now,
        updatedAt: now,
      );
      await save(project);
      return project;
    } catch (_) {
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> save(EditorProject project) async {
    project.updatedAt = DateTime.now();
    final folder = await _folder(project.id);
    final temp = File(p.join(folder.path, 'project.json.tmp'));
    final target = File(p.join(folder.path, 'project.json'));
    await temp.writeAsString(jsonEncode(project.toJson()), flush: true);
    if (!await target.exists()) {
      await temp.rename(target.path);
      return;
    }

    final backup = File('${target.path}.bak');
    if (await backup.exists()) await backup.delete();
    await target.rename(backup.path);
    try {
      await temp.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<List<EditorProject>> listProjects() async {
    final result = <EditorProject>[];
    if (!await root.exists()) return result;

    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'project.json'));
      if (!await file.exists()) continue;

      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final project = EditorProject.fromJson(data);
        if (await File(project.originalPath).exists()) {
          result.add(project);
        }
      } catch (_) {
        // Skip one damaged project without preventing other projects loading.
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
