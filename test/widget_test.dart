import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:layer_studio/models/editor_layer.dart';

void main() {
  test('EditorLayer JSON round trip preserves transform and text', () {
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

  test('EXIF orientation is baked into raster pixel dimensions', () {
    final raw = img.Image(width: 2, height: 3);
    raw.exif.imageIfd.orientation = 6;

    final upright = img.bakeOrientation(raw);

    expect(upright.width, 3);
    expect(upright.height, 2);
    expect(upright.exif.imageIfd.hasOrientation, isFalse);
  });
}
