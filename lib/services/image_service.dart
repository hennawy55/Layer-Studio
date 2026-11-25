import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImageService {
  /// Decodes an image and applies its EXIF orientation to the actual pixels.
  /// The returned image is physically upright and no longer relies on metadata.
  Future<img.Image> decode(String path) async {
    final bytes = await File(path).readAsBytes();
    return decodeBytes(bytes);
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

  /// Normalizes a raster image to an EXIF-free PNG without another lossy
  /// JPEG/WebP compression pass. The decoded pixel content is retained.
  Future<img.Image> normalizeToPng(String sourcePath, String destinationPath) async {
    final image = await decode(sourcePath);
    await writePng(image, destinationPath);
    return image;
  }

  Future<void> exportPng(img.Image image, String path) async {
    await writePng(image, path);
  }

  Future<void> exportJpeg(img.Image image, String path, {int quality = 95}) async {
    await File(path).writeAsBytes(
      img.encodeJpg(image, quality: quality.clamp(1, 100).toInt()),
      flush: true,
    );
  }

  Future<void> exportWebp(img.Image image, String path, {int quality = 95}) async {
    await File(path).writeAsBytes(
      img.encodeWebP(image, quality: quality.clamp(1, 100).toInt()),
      flush: true,
    );
  }
}
