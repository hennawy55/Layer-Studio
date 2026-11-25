import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_svg/flutter_svg.dart';

import '../models/editor_layer.dart';
import '../models/editor_project.dart';

class RenderService {
  Future<ui.Image> _decodeUiImage(String path) async {
    if (path.toLowerCase().endsWith('.svg')) {
      final pictureInfo = await vg.loadPicture(SvgFileLoader(File(path)), null);
      try {
        final width = pictureInfo.size.width.ceil().clamp(1, 12000).toInt();
        final height = pictureInfo.size.height.ceil().clamp(1, 12000).toInt();
        return await pictureInfo.picture.toImage(width, height);
      } finally {
        pictureInfo.picture.dispose();
      }
    }

    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<Uint8List> renderPng(EditorProject project) async {
    final base = await _decodeUiImage(project.originalPath);
    final width = base.width;
    final height = base.height;

    if (width <= 0 || height <= 0 || width > 30000 || height > 30000 || width * height > 100000000) {
      base.dispose();
      throw const FormatException('Image dimensions are not supported.');
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(base, Offset.zero, Paint()..filterQuality = FilterQuality.high);
    final loadedImages = <ui.Image>[];

    try {
      for (final layer in project.layers) {
        if (!layer.visible || layer.opacity <= 0) continue;

        canvas.save();
        canvas.translate(layer.x * width, layer.y * height);
        canvas.rotate(layer.rotation);
        canvas.scale(layer.scale);
        canvas.scale(layer.flipX ? -1.0 : 1.0, layer.flipY ? -1.0 : 1.0);

        if (layer.type == LayerType.image && layer.assetPath != null) {
          final file = File(layer.assetPath!);
          if (await file.exists()) {
            final overlay = await _decodeUiImage(file.path);
            loadedImages.add(overlay);
            const displayWidth = 180.0;
            final displayHeight = overlay.height * displayWidth / overlay.width;
            final destination = Rect.fromCenter(
              center: Offset.zero,
              width: displayWidth,
              height: displayHeight,
            );
            final paint = Paint()
              ..filterQuality = FilterQuality.high
              ..color = Color.fromRGBO(255, 255, 255, layer.opacity.clamp(0.0, 1.0).toDouble());
            canvas.drawImageRect(
              overlay,
              Rect.fromLTWH(0, 0, overlay.width.toDouble(), overlay.height.toDouble()),
              destination,
              paint,
            );
          }
        } else if (layer.type == LayerType.text && layer.text.isNotEmpty) {
          final containsArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(layer.text);
          final painter = TextPainter(
            text: TextSpan(
              text: layer.text,
              style: TextStyle(
                fontFamily: layer.fontFamily,
                fontSize: layer.fontSize,
                color: Color(layer.color).withOpacity(layer.opacity.clamp(0.0, 1.0).toDouble()),
                fontWeight: layer.bold ? FontWeight.bold : FontWeight.normal,
                fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            textDirection: containsArabic ? TextDirection.rtl : TextDirection.ltr,
            textAlign: switch (layer.align) {
              'left' => TextAlign.left,
              'right' => TextAlign.right,
              _ => TextAlign.center,
            },
          )..layout(maxWidth: width.toDouble() * 2);

          painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
          painter.dispose();
        }

        canvas.restore();
      }

      final picture = recorder.endRecording();
      try {
        final rendered = await picture.toImage(width, height);
        try {
          final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('Unable to encode rendered image.');
          return data.buffer.asUint8List();
        } finally {
          rendered.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      for (final image in loadedImages) {
        image.dispose();
      }
      base.dispose();
    }
  }

  Future<Uint8List> render(
    EditorProject project, {
    required String extension,
    int jpegQuality = 95,
    int webpQuality = 95,
  }) async {
    final pngBytes = await renderPng(project);
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    if (normalized == 'png') return pngBytes;

    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) throw StateError('Unable to encode rendered image.');

    if (normalized == 'jpg' || normalized == 'jpeg') {
      return img.encodeJpg(decoded, quality: jpegQuality.clamp(1, 100).toInt());
    }
    if (normalized == 'webp') {
      return img.encodeWebP(
        decoded,
        lossless: false,
        quality: webpQuality.clamp(1, 100).toInt(),
      );
    }
    throw FormatException('Unsupported export format: $extension');
  }

  Future<void> export(
    EditorProject project,
    String path, {
    int jpegQuality = 95,
    int webpQuality = 95,
  }) async {
    final extension = path.toLowerCase().split('.').last;
    final bytes = await render(
      project,
      extension: extension,
      jpegQuality: jpegQuality,
      webpQuality: webpQuality,
    );
    await File(path).writeAsBytes(bytes, flush: true);
  }
}
