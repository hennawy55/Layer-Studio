import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/logo_asset.dart';
import 'image_service.dart';

class LogoLibraryStore {
  final _uuid = const Uuid();
  final _images = ImageService();
  late Directory _root;
  late File _index;

  Future<void> initialize() async {
    final base = await getApplicationSupportDirectory();
    _root = Directory(p.join(base.path, 'LayerStudio', 'logo-library'));
    await _root.create(recursive: true);
    _index = File(p.join(_root.path, 'logos.json'));
    if (!await _index.exists()) {
      await _write(const []);
    }
  }

  Future<List<LogoAsset>> listLogos() async {
    if (!await _index.exists()) return [];
    try {
      final decoded = jsonDecode(await _index.readAsString()) as List<dynamic>;
      final logos = <LogoAsset>[];
      for (final item in decoded) {
        try {
          final logo = LogoAsset.fromJson(item as Map<String, dynamic>);
          if (await File(logo.path).exists()) logos.add(logo);
        } catch (_) {
          // Ignore a damaged entry without hiding the rest of the library.
        }
      }
      logos.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return logos;
    } catch (_) {
      return [];
    }
  }

  Future<LogoAsset> addLogo(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('The selected logo does not exist.');
    }

    final extension = p.extension(source.path).toLowerCase();
    const supported = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif', '.svg'};
    if (!supported.contains(extension)) {
      throw const FormatException('Choose a PNG, JPG, WebP, BMP, GIF or SVG file.');
    }

    final id = _uuid.v4();
    late final String storedPath;
    if (extension == '.svg') {
      storedPath = p.join(_root.path, '$id.svg');
      await source.copy(storedPath);
    } else {
      storedPath = p.join(_root.path, '$id.png');
      final normalized = await _images.decode(source.path);
      await _images.writePng(normalized, storedPath);
    }

    final logo = LogoAsset(
      id: id,
      name: p.basenameWithoutExtension(source.path),
      path: storedPath,
    );
    final logos = await listLogos();
    logos.add(logo);
    await _write(logos);
    return logo;
  }

  Future<void> deleteLogo(String id) async {
    final logos = await listLogos();
    LogoAsset? target;
    for (final logo in logos) {
      if (logo.id == id) {
        target = logo;
        break;
      }
    }
    if (target == null) return;
    final file = File(target.path);
    if (await file.exists()) await file.delete();
    await _write(logos.where((logo) => logo.id != id).toList());
  }

  Future<void> _write(List<LogoAsset> logos) async {
    final temp = File('${_index.path}.tmp');
    await temp.writeAsString(
      jsonEncode(logos.map((logo) => logo.toJson()).toList()),
      flush: true,
    );
    if (await _index.exists()) await _index.delete();
    await temp.rename(_index.path);
  }
}
