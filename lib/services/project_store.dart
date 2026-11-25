import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/editor_project.dart';

class ProjectStore {
  late Directory root;
  final _uuid = const Uuid();

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

  Future<EditorProject> create(String imagePath, int width, int height) async {
    final now = DateTime.now();
    final project = EditorProject(
      id: _uuid.v4(),
      name: 'Untitled project',
      originalPath: imagePath,
      width: width,
      height: height,
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
        result.add(EditorProject.fromJson(data));
      } catch (_) {
        // Skip damaged project metadata without blocking other projects.
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> delete(String id) async {
    final folder = Directory(p.join(root.path, id));
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  Future<String> newId() async => _uuid.v4();
}
