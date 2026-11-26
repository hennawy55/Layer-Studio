import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;

import '../models/editor_layer.dart';
import '../models/editor_project.dart';

class RenderService {
  static const int _maxExportPixels = 50000000;
  static const int _maxExportSide = 30000;

  Future<ui.Image> _decodeUiImage(String path) async {
    if (path.toLowerCase().endsWith('.svg')) {
      final pictureInfo = await vg.loadPicture(SvgFileLoader(File(path)), null);
      try {
        final sourceWidth = pictureInfo.size.width.ceil();
        final sourceHeight = pictureInfo.size.height.ceil();
        if (sourceWidth <= 0 ||
            sourceHeight <= 0 ||
            sourceWidth > 12000 ||
            sourceHeight > 12000 ||
            sourceWidth * sourceHeight > _maxExportPixels) {
          throw const FormatException('Image dimensions are not supported.');
        }
        return await pictureInfo.picture.toImage(sourceWidth, sourceHeight);
      } finally {
        pictureInfo.picture.dispose();
      }
    }

    // Read the encoded image header first. This rejects huge files before
    // allocating a full-resolution decoded bitmap.
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 ||
          height <= 0 ||
          width > _maxExportSide ||
          height > _maxExportSide ||
          width * height > _maxExportPixels) {
        throw const FormatException(
          'This image is too large to export safely on this device.',
        );
      }

      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  Color _effectiveTextColor(EditorLayer layer) {
    final base = Color(layer.color);
    if (layer.overlayOpacity <= 0) return base;
    return Color.alphaBlend(
      Color(layer.overlayColor).withValues(
        alpha: (layer.overlayOpacity * Color(layer.overlayColor).a)
            .clamp(0.0, 1.0)
            .toDouble(),
      ),
      base,
    );
  }

  TextPainter _makeTextPainter(
    EditorLayer layer, {
    required Color color,
    Paint? foreground,
    bool includeShadow = true,
  }) {
    final containsArabic = RegExp(r'[؀-ۿ]').hasMatch(layer.text);
    final shadows = includeShadow &&
            (layer.shadowBlur > 0 ||
                layer.shadowOffsetX != 0 ||
                layer.shadowOffsetY != 0)
        ? [
            Shadow(
              color: Color(layer.shadowColor).withValues(
                alpha: (Color(layer.shadowColor).a * layer.opacity)
                    .clamp(0.0, 1.0)
                    .toDouble(),
              ),
              blurRadius: layer.shadowBlur,
              offset: Offset(layer.shadowOffsetX, layer.shadowOffsetY),
            ),
          ]
        : const <Shadow>[];

    final style = TextStyle(
      fontFamily: layer.fontFamily,
      fontSize: layer.fontSize,
      color: foreground == null ? color : null,
      foreground: foreground,
      fontWeight: layer.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      shadows: shadows,
    );

    return TextPainter(
      text: TextSpan(text: layer.text, style: style),
      textDirection: containsArabic ? TextDirection.rtl : TextDirection.ltr,
      textAlign: switch (layer.align) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      },
    );
  }

  void _drawText(Canvas canvas, EditorLayer layer, int imageWidth) {
    if (layer.text.isEmpty) return;

    if (layer.strokeWidth > 0) {
      final strokePainter = _makeTextPainter(
        layer,
        color: Colors.transparent,
        includeShadow: false,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = layer.strokeWidth * 2
          ..color = Color(layer.strokeColor).withValues(
            alpha: (Color(layer.strokeColor).a * layer.opacity)
                .clamp(0.0, 1.0)
                .toDouble(),
          ),
      )..layout(maxWidth: imageWidth.toDouble() * 2);

      strokePainter.paint(
        canvas,
        Offset(-strokePainter.width / 2, -strokePainter.height / 2),
      );
      strokePainter.dispose();
    }

    final fillPainter = _makeTextPainter(
      layer,
      color: _effectiveTextColor(layer).withValues(
        alpha: (_effectiveTextColor(layer).a * layer.opacity)
            .clamp(0.0, 1.0)
            .toDouble(),
      ),
    )..layout(maxWidth: imageWidth.toDouble() * 2);

    fillPainter.paint(
      canvas,
      Offset(-fillPainter.width / 2, -fillPainter.height / 2),
    );
    fillPainter.dispose();
  }

  void _drawImageLayer(
    Canvas canvas,
    EditorLayer layer,
    ui.Image overlay,
    int canvasWidth,
    int canvasHeight,
  ) {
    final aspectRatio = overlay.width / overlay.height;
    final displayWidth = math.min(
      canvasWidth * .30,
      canvasHeight * .30 * aspectRatio,
    );
    final displayHeight = displayWidth / aspectRatio;
    final source = Rect.fromLTWH(
      0,
      0,
      overlay.width.toDouble(),
      overlay.height.toDouble(),
    );
    final destination = Rect.fromCenter(
      center: Offset.zero,
      width: displayWidth,
      height: displayHeight,
    );

    if (layer.shadowBlur > 0 ||
        layer.shadowOffsetX != 0 ||
        layer.shadowOffsetY != 0) {
      final shadowPaint = Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = ColorFilter.mode(
          Color(layer.shadowColor).withValues(
            alpha: (Color(layer.shadowColor).a * layer.opacity)
                .clamp(0.0, 1.0)
                .toDouble(),
          ),
          BlendMode.srcIn,
        )
        ..maskFilter = layer.shadowBlur > 0
            ? MaskFilter.blur(BlurStyle.normal, layer.shadowBlur)
            : null;

      canvas.drawImageRect(
        overlay,
        source,
        destination.shift(Offset(layer.shadowOffsetX, layer.shadowOffsetY)),
        shadowPaint,
      );
    }

    // Fewer high-quality passes keep thick logo outlines from dominating export time.
    if (layer.strokeWidth > 0) {
      final strokePaint = Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = ColorFilter.mode(
          Color(layer.strokeColor).withValues(
            alpha: (Color(layer.strokeColor).a * layer.opacity)
                .clamp(0.0, 1.0)
                .toDouble(),
          ),
          BlendMode.srcIn,
        );
      const samples = 12;
      for (var i = 0; i < samples; i++) {
        final angle = (i / samples) * 6.283185307179586;
        final dx = layer.strokeWidth * math.cos(angle);
        final dy = layer.strokeWidth * math.sin(angle);
        canvas.drawImageRect(
          overlay,
          source,
          destination.shift(Offset(dx, dy)),
          strokePaint,
        );
      }
    }

    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..color = Colors.white.withValues(
        alpha: layer.opacity.clamp(0.0, 1.0).toDouble(),
      );
    if (layer.overlayOpacity > 0) {
      paint.colorFilter = ColorFilter.mode(
        Color(layer.overlayColor).withValues(
          alpha: (layer.overlayOpacity * Color(layer.overlayColor).a)
              .clamp(0.0, 1.0)
              .toDouble(),
        ),
        BlendMode.srcATop,
      );
    }

    canvas.drawImageRect(overlay, source, destination, paint);
  }

  Future<ui.Image> _compose(EditorProject project) async {
    final base = await _decodeUiImage(project.originalPath);
    final width = base.width;
    final height = base.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final loadedImages = <ui.Image>[];

    try {
      canvas.drawImage(
        base,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );

      for (final layer in project.layers) {
        if (!layer.visible || layer.opacity <= 0) continue;

        canvas.save();
        try {
          canvas.translate(layer.x * width, layer.y * height);
          canvas.rotate(layer.rotation);
          canvas.scale(layer.scale);
          canvas.scale(
            layer.flipX ? -1.0 : 1.0,
            layer.flipY ? -1.0 : 1.0,
          );

          if (layer.type == LayerType.image && layer.assetPath != null) {
            final file = File(layer.assetPath!);
            if (await file.exists()) {
              final overlay = await _decodeUiImage(file.path);
              loadedImages.add(overlay);
              _drawImageLayer(canvas, layer, overlay, width, height);
            }
          } else if (layer.type == LayerType.text) {
            _drawText(canvas, layer, width);
          }
        } finally {
          canvas.restore();
        }
      }

      final picture = recorder.endRecording();
      try {
        return await picture.toImage(width, height);
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

  Future<Uint8List> renderPng(EditorProject project) async {
    final rendered = await _compose(project);
    try {
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('Unable to encode rendered image.');
      }
      return data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } finally {
      rendered.dispose();
    }
  }

  Future<Uint8List> render(
    EditorProject project, {
    required String extension,
    int jpegQuality = 95,
    int webpQuality = 95,
  }) async {
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    if (normalized == 'png') return renderPng(project);

    if (normalized != 'jpg' &&
        normalized != 'jpeg' &&
        normalized != 'webp') {
      throw FormatException('Unsupported export format: $extension');
    }

    // JPEG/WebP are encoded from raw pixels. This avoids creating a large
    // intermediate PNG and decoding it again on memory-constrained phones.
    final rendered = await _compose(project);
    try {
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        throw StateError('Unable to read rendered image pixels.');
      }

      final raster = img.Image.fromBytes(
        width: rendered.width,
        height: rendered.height,
        bytes: data.buffer,
        bytesOffset: data.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      if (normalized == 'jpg' || normalized == 'jpeg') {
        return Uint8List.fromList(
          img.encodeJpg(
            raster,
            quality: jpegQuality.clamp(1, 100).toInt(),
          ),
        );
      }
      return Uint8List.fromList(
        img.encodeWebP(
          raster,
          lossless: false,
          quality: webpQuality.clamp(1, 100).toInt(),
        ),
      );
    } finally {
      rendered.dispose();
    }
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
