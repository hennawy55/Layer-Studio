import 'editor_layer.dart';

class EditorProject {
  EditorProject({
    required this.id,
    required this.name,
    required this.originalPath,
    required this.width,
    required this.height,
    required this.createdAt,
    required this.updatedAt,
    List<EditorLayer>? layers,
  }) : layers = layers ?? [];

  final String id;
  String name;
  String originalPath;
  int width;
  int height;
  DateTime createdAt;
  DateTime updatedAt;
  List<EditorLayer> layers;

  Map<String, dynamic> toJson() => {
    'format': 'layerstudio',
    'formatVersion': 1,
    'id': id,
    'name': name,
    'originalPath': originalPath,
    'width': width,
    'height': height,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'layers': layers.map((e) => e.toJson()).toList(),
  };

  factory EditorProject.fromJson(Map<String, dynamic> json) => EditorProject(
    id: json['id'] as String,
    name: json['name'] as String,
    originalPath: json['originalPath'] as String,
    width: json['width'] as int,
    height: json['height'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    layers: (json['layers'] as List<dynamic>? ?? [])
        .map((e) => EditorLayer.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
