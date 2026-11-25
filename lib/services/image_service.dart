import 'dart:io';
import 'package:image/image.dart' as img;

class ImageService {
  Future<img.Image> decode(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or invalid image.');
    }
    return decoded;
  }

  Future<void> exportPng(img.Image image, String path) async {
    await File(path).writeAsBytes(img.encodePng(image), flush: true);
  }

  Future<void> exportJpeg(img.Image image, String path, {int quality = 95}) async {
    await File(path).writeAsBytes(
      img.encodeJpg(image, quality: quality.clamp(1, 100).toInt().toInt()),
      flush: true,
    );
  }

  Future<void> exportWebp(img.Image image, String path, {int quality = 95}) async {
    await File(path).writeAsBytes(
      img.encodeWebP(image, quality: quality.clamp(1, 100)),
      flush: true,
    );
  }
}
