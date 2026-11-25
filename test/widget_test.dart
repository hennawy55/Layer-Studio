import 'package:flutter_test/flutter_test.dart';
import 'package:layer_studio/models/editor_layer.dart';

void main() {
  test('EditorLayer JSON round trip preserves transform and text', () {
    final layer = EditorLayer(
      id: 'test',
      type: LayerType.text,
      text: 'مرحبا Hello',
      x: .25,
      y: .75,
      scale: 1.4,
      rotation: .2,
      opacity: .8,
    );
    final restored = EditorLayer.fromJson(layer.toJson());
    expect(restored.text, 'مرحبا Hello');
    expect(restored.x, .25);
    expect(restored.y, .75);
    expect(restored.scale, 1.4);
    expect(restored.opacity, .8);
  });
}
