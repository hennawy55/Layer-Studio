import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:layer_studio/models/editor_layer.dart';
import 'package:layer_studio/models/editor_project.dart';
import 'package:layer_studio/models/logo_asset.dart';
import 'package:layer_studio/services/image_service.dart';

void main() {
  test('EditorLayer JSON round trip preserves transform and effects', () {
    final layer = EditorLayer(
      id: 'test',
      type: LayerType.text,
      text: 'مرحبا Hello',
      assetPath: 'assets/overlay.png',
      assetWidth: 1200,
      assetHeight: 800,
      x: .25,
      y: .75,
      scale: 1.4,
      rotation: .2,
      opacity: .8,
      strokeColor: 0xFF112233,
      strokeWidth: 3.5,
      overlayColor: 0xAAFF0000,
      overlayOpacity: .45,
      shadowColor: 0x99000000,
      shadowBlur: 8,
      shadowOffsetX: 4,
      shadowOffsetY: -2,
    );
    final restored = EditorLayer.fromJson(layer.toJson());

    expect(restored.text, 'مرحبا Hello');
    expect(restored.assetPath, 'assets/overlay.png');
    expect(restored.assetWidth, 1200);
    expect(restored.assetHeight, 800);
    expect(restored.x, .25);
    expect(restored.y, .75);
    expect(restored.scale, 1.4);
    expect(restored.opacity, .8);
    expect(restored.strokeColor, 0xFF112233);
    expect(restored.strokeWidth, 3.5);
    expect(restored.overlayColor, 0xAAFF0000);
    expect(restored.overlayOpacity, .45);
    expect(restored.shadowColor, 0x99000000);
    expect(restored.shadowBlur, 8);
    expect(restored.shadowOffsetX, 4);
    expect(restored.shadowOffsetY, -2);
  });

  test('New projects use version 2 and preserve that version in JSON', () {
    final now = DateTime(2026, 11, 26);
    final project = EditorProject(
      id: 'p1',
      name: 'Test',
      originalPath: '/tmp/original.jpg',
      width: 1200,
      height: 800,
      createdAt: now,
      updatedAt: now,
    );

    expect(project.formatVersion, 2);
    expect(EditorProject.fromJson(project.toJson()).formatVersion, 2);
  });

  test('Old project metadata remains marked for one-time migration', () {
    final now = DateTime(2025, 1, 1);
    final legacy = EditorProject.fromJson({
      'format': 'layerstudio',
      'formatVersion': 1,
      'id': 'legacy',
      'name': 'Old project',
      'originalPath': '/tmp/old.png',
      'width': 100,
      'height': 80,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'layers': [],
    });

    expect(legacy.formatVersion, 1);
  });

  test('Logo asset JSON round trip preserves its saved reference', () {
    const logo = LogoAsset(
      id: 'logo-1',
      name: 'Brand mark',
      path: '/logos/brand-mark.svg',
    );

    final restored = LogoAsset.fromJson(logo.toJson());
    expect(restored.id, logo.id);
    expect(restored.name, logo.name);
    expect(restored.path, logo.path);
    expect(restored.isSvg, isTrue);
  });

  test('Image normalization applies all EXIF orientations exactly once', () async {
    final directory = await Directory.systemTemp.createTemp('layer-studio-test-');
    addTearDown(() => directory.delete(recursive: true));

    for (var orientation = 1; orientation <= 8; orientation++) {
      final source = File('${directory.path}/camera-$orientation.jpg');
      final target = File('${directory.path}/upright-$orientation.jpg');
      final raw = img.Image(width: 2, height: 3);
      raw.exif.imageIfd.orientation = orientation;
      await source.writeAsBytes(img.encodeJpg(raw));

      final dimensions = await ImageService().normalizeToFile(
        source.path,
        target.path,
        asJpeg: true,
      );
      final normalized = img.decodeImage(await target.readAsBytes());
      final swapsAxes = orientation >= 5;

      expect(
        dimensions.width,
        swapsAxes ? 3 : 2,
        reason: 'EXIF orientation $orientation width',
      );
      expect(
        dimensions.height,
        swapsAxes ? 2 : 3,
        reason: 'EXIF orientation $orientation height',
      );
      expect(normalized?.width, dimensions.width);
      expect(normalized?.height, dimensions.height);
      expect(
        normalized?.exif.imageIfd.hasOrientation,
        isFalse,
        reason: 'EXIF orientation $orientation must be removed after baking',
      );
    }
  });
}
