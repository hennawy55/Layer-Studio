import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;

import '../models/editor_layer.dart';
import '../models/editor_project.dart';

class ExportDimensions {
  const ExportDimensions(this.width, this.height);

  final int width;
  final int height;

  bool matches(int sourceWidth, int sourceHeight) =>
      width == sourceWidth && height == sourceHeight;
}

class RenderService {
  // Keep Android export surfaces within a practical memory budget.
  static int get _maxExportPixels =>
      Platform.isAndroid ? 16000000 : 50000000;
  static int get _maxExportSide => Platform.isAndroid ? 12000 : 30000;

  static ExportDimensions exportDimensions(int width, int height) =>
      fitDimensions(
        width,
        height,
        maxPixels: _maxExportPixels,
        maxSide: _maxExportSide,
      );

  @visibleForTesting
  static ExportDimensions fitDimensions(
    int width,
    int height, {
    required int maxPixels,
    required int maxSide,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        maxPixels <= 0 ||
        maxSide <= 0) {
      throw const FormatException('Image dimensions or export limits are invalid.');
    }

    final scale = math.min(
      1.0,
      math.min(
        maxSide / math.max(width, height),
        math.sqrt(maxPixels / (width * height)),
      ),
    );
    var outputWidth = math.max(1, (width * scale).floor());
    var outputHeight = math.max(1, (height * scale).floor());

    while (outputWidth * outputHeight > maxPixels ||
        math.max(outputWidth, outputHeight) > maxSide) {
      if (outputWidth >= outputHeight) {
        outputWidth--;
      } else {
        outputHeight--;
      }
    }

    return ExportDimensions(outputWidth, outputHeight);
  }

  Future<ui.Image> _decodeUiImage(String path, {int? targetWidth}) async {
    if (path.toLowerCase().endsWith('.svg')) {
      final pictureInfo = await vg.loadPicture(SvgFileLoader(File(path)), null);
      try {
        final sourceWidth = pictureInfo.size.width.ceil();
        final sourceHeight = pictureInfo.size.height.ceil();
        if (sourceWidth <= 0 || sourceHeight <= 0) {
          throw const FormatException('Image dimensions are not supported.');
        }
        final requestedWidth = targetWidth == null
            ? sourceWidth
            : math.min(sourceWidth, targetWidth);
        final fitted = exportDimensions(requestedWidth, sourceHeight);
        return await pictureInfo.picture.toImage(
          fitted.width,
          fitted.height,
        );
      } finally {
        pictureInfo.picture.dispose();
      }
    }

    // Read the encoded image header so the codec can decode directly to a
    // safe output size instead of allocating the full-resolution bitmap.
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0) {
        throw const FormatException('Image dimensions are invalid.');
      }

      // Downsample before allocating the decoded bitmap. Large source photos
      // are no longer rejected solely because of their original pixel count.
      final requestedWidth = targetWidth == null
          ? width
          : math.min(width, targetWidth);
      final fitted = exportDimensions(requestedWidth, height);
      final codec = await descriptor.instantiateCodec(
        targetWidth: fitted.width,
      );
      try {
        final image = (await codec.getNextFrame()).image;
        if (image.width * image.height > _maxExportPixels ||
            math.max(image.width, image.height) > _maxExportSide) {
          image.dispose();
          throw const FormatException(
            'The image decoder could not safely resize this image.',
          );
        }
        return image;
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
    double renderScale = 1,
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
              blurRadius: layer.shadowBlur * renderScale,
              offset: Offset(
                layer.shadowOffsetX * renderScale,
                layer.shadowOffsetY * renderScale,
              ),
            ),
          ]
        : const <Shadow>[];

    final style = TextStyle(
      fontFamily: layer.fontFamily,
      fontSize: layer.fontSize * renderScale,
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

  void _drawText(
    Canvas canvas,
    EditorLayer layer,
    int imageWidth, {
    required double renderScale,
  }) {
    if (layer.text.isEmpty) return;

    if (layer.strokeWidth > 0) {
      final strokePainter = _makeTextPainter(
        layer,
        color: Colors.transparent,
        includeShadow: false,
        renderScale: renderScale,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = layer.strokeWidth * renderScale * 2
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
      renderScale: renderScale,
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
    int canvasHeight, {
    required double renderScale,
  }) {
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
            ? MaskFilter.blur(BlurStyle.normal, layer.shadowBlur * renderScale)
            : null;

      canvas.drawImageRect(
        overlay,
        source,
        destination.shift(Offset(
          layer.shadowOffsetX * renderScale,
          layer.shadowOffsetY * renderScale,
        )),
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
        final dx = layer.strokeWidth * renderScale * math.cos(angle);
        final dy = layer.strokeWidth * renderScale * math.sin(angle);
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
    final renderScale = math.min(
      width / math.max(1, project.width),
      height / math.max(1, project.height),
    );
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
              final targetWidth = (width * .30 * layer.scale * 1.25)
                  .round()
                  .clamp(1, 12000)
                  .toInt();
              final overlay = await _decodeUiImage(
                file.path,
                targetWidth: targetWidth,
              );
              loadedImages.add(overlay);
              _drawImageLayer(
                canvas,
                layer,
                overlay,
                width,
                height,
                renderScale: renderScale,
              );
            }
          } else if (layer.type == LayerType.text) {
            _drawText(
              canvas,
              layer,
              width,
              renderScale: renderScale,
            );
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
