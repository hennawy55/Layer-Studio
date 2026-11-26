class LogoAsset {
  const LogoAsset({
    required this.id,
    required this.name,
    required this.path,
  });

  final String id;
  final String name;
  final String path;

  bool get isSvg => path.toLowerCase().endsWith('.svg');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
      };

  factory LogoAsset.fromJson(Map<String, dynamic> json) => LogoAsset(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
      );
}
