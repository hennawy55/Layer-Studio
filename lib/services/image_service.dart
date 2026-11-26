import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageDimensions {
  const ImageDimensions({required this.width, required this.height});

  final int width;
  final int height;
}

/// Runs decoding, EXIF baking and encoding away from the Flutter UI isolate.
/// JPEG sources stay JPEG to avoid the very large size of lossless PNG copies;
/// transparent and other raster sources are retained as PNG.
Map<String, Object> _normalizeRasterInBackground(Map<String, Object> input) {
  final sourceBytes = input['bytes'] as Uint8List;
  final asJpeg = input['asJpeg'] as bool;
  final quality = input['quality'] as int;
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const FormatException('Unsupported or invalid image.');
  }

  final upright = img.bakeOrientation(decoded);
  final encoded = asJpeg
      ? img.encodeJpg(upright, quality: quality.clamp(1, 100).toInt())
      : img.encodePng(upright);

  return <String, Object>{
    'bytes': Uint8List.fromList(encoded),
    'width': upright.width,
    'height': upright.height,
  };
}

class ImageService {
  /// Normalizes a raster file on a worker isolate and writes an EXIF-free copy.
  Future<ImageDimensions> normalizeToFile(
    String sourcePath,
    String destinationPath, {
    bool asJpeg = false,
    int jpegQuality = 95,
  }) async {
    final sourceBytes = await File(sourcePath).readAsBytes();
    final result = await compute<Map<String, Object>, Map<String, Object>>(
      _normalizeRasterInBackground,
      <String, Object>{
        'bytes': sourceBytes,
        'asJpeg': asJpeg,
        'quality': jpegQuality,
      },
      debugLabel: 'normalize-image',
    );
    await File(destinationPath).writeAsBytes(
      result['bytes'] as Uint8List,
      flush: true,
    );
    return ImageDimensions(
      width: result['width'] as int,
      height: result['height'] as int,
    );
  }

  Future<img.Image> decode(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or invalid image.');
    }
    return img.bakeOrientation(decoded);
  }

  img.Image decodeBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or invalid image.');
    }
    return img.bakeOrientation(decoded);
  }

  Future<void> writePng(img.Image image, String path) async {
    await File(path).writeAsBytes(img.encodePng(image), flush: true);
  }

  Future<void> writeJpeg(
    img.Image image,
    String path, {
    int quality = 95,
  }) async {
    await File(path).writeAsBytes(
      img.encodeJpg(image, quality: quality.clamp(1, 100).toInt()),
      flush: true,
    );
  }

  Future<img.Image> normalizeToPng(
    String sourcePath,
    String destinationPath,
  ) async {
    final image = await decode(sourcePath);
    await writePng(image, destinationPath);
    return image;
  }

  Future<void> exportPng(img.Image image, String path) async {
    await writePng(image, path);
  }

  Future<void> exportJpeg(
    img.Image image,
    String path, {
    int quality = 95,
  }) async {
    await writeJpeg(image, path, quality: quality);
  }

  Future<void> exportWebp(
    img.Image image,
    String path, {
    int quality = 95,
  }) async {
    await File(path).writeAsBytes(
      img.encodeWebP(image, quality: quality.clamp(1, 100).toInt()),
      flush: true,
    );
  }
}
