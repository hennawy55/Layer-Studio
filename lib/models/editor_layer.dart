import 'dart:convert';

enum LayerType { text, image }

class EditorLayer {
  EditorLayer({
    required this.id,
    required this.type,
    this.text = '',
    this.assetPath,
    this.assetWidth = 0,
    this.assetHeight = 0,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.visible = true,
    this.locked = false,
    this.fontFamily = 'Cairo',
    this.fontSize = 48,
    this.color = 0xFFFFFFFF,
    this.bold = false,
    this.italic = false,
    this.flipX = false,
    this.flipY = false,
    this.strokeColor = 0xFF000000,
    this.strokeWidth = 0,
    this.overlayColor = 0xFFFFFFFF,
    this.overlayOpacity = 0,
    this.shadowColor = 0xFF000000,
    this.shadowBlur = 0,
    this.shadowOffsetX = 0,
    this.shadowOffsetY = 0,
    this.align = 'center',
  });

  final String id;
  final LayerType type;
  String text;
  String? assetPath;
  int assetWidth;
  int assetHeight;
  double x;
  double y;
  double scale;
  double rotation;
  double opacity;
  bool visible;
  bool locked;
  String fontFamily;
  double fontSize;
  int color;
  bool bold;
  bool italic;
  bool flipX;
  bool flipY;
  int strokeColor;
  double strokeWidth;
  int overlayColor;
  double overlayOpacity;
  int shadowColor;
  double shadowBlur;
  double shadowOffsetX;
  double shadowOffsetY;
  String align;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'assetPath': assetPath,
    'assetWidth': assetWidth,
    'assetHeight': assetHeight,
    'x': x,
    'y': y,
    'scale': scale,
    'rotation': rotation,
    'opacity': opacity,
    'visible': visible,
    'locked': locked,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'color': color,
    'bold': bold,
    'italic': italic,
    'flipX': flipX,
    'flipY': flipY,
    'strokeColor': strokeColor,
    'strokeWidth': strokeWidth,
    'overlayColor': overlayColor,
    'overlayOpacity': overlayOpacity,
    'shadowColor': shadowColor,
    'shadowBlur': shadowBlur,
    'shadowOffsetX': shadowOffsetX,
    'shadowOffsetY': shadowOffsetY,
    'align': align,
  };

  factory EditorLayer.fromJson(Map<String, dynamic> json) => EditorLayer(
    id: json['id'] as String,
    type: LayerType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => LayerType.text,
    ),
    text: json['text'] as String? ?? '',
    assetPath: json['assetPath'] as String?,
    assetWidth: json['assetWidth'] as int? ?? 0,
    assetHeight: json['assetHeight'] as int? ?? 0,
    x: (json['x'] as num?)?.toDouble() ?? .5,
    y: (json['y'] as num?)?.toDouble() ?? .5,
    scale: (json['scale'] as num?)?.toDouble() ?? 1,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    visible: json['visible'] as bool? ?? true,
    locked: json['locked'] as bool? ?? false,
    fontFamily: json['fontFamily'] as String? ?? 'Cairo',
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 48,
    color: json['color'] as int? ?? 0xFFFFFFFF,
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
    flipX: json['flipX'] as bool? ?? false,
    flipY: json['flipY'] as bool? ?? false,
    strokeColor: json['strokeColor'] as int? ?? 0xFF000000,
    strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0,
    overlayColor: json['overlayColor'] as int? ?? 0xFFFFFFFF,
    overlayOpacity: (json['overlayOpacity'] as num?)?.toDouble() ?? 0,
    shadowColor: json['shadowColor'] as int? ?? 0xFF000000,
    shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 0,
    shadowOffsetX: (json['shadowOffsetX'] as num?)?.toDouble() ?? 0,
    shadowOffsetY: (json['shadowOffsetY'] as num?)?.toDouble() ?? 0,
    align: json['align'] as String? ?? 'center',
  );

  EditorLayer copy() => EditorLayer.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}
