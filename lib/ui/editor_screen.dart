import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/editor_layer.dart';
import '../models/editor_project.dart';
import '../services/image_service.dart';
import '../state/app_state.dart';
import 'package:provider/provider.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project});
  final EditorProject project;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _imageService = ImageService();
  final _uuid = const Uuid();
  final _undo = <Map<String, dynamic>>[];
  final _redo = <Map<String, dynamic>>[];
  img.Image? _base;
  int? _selected;
  bool _busy = false;
  double _previewScale = 1;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  Future<void> _loadBase() async {
    try {
      final image = await _imageService.decode(widget.project.originalPath);
      if (mounted) setState(() => _base = image);
    } catch (e) {
      if (mounted) _message('Could not open original image: $e');
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  void _checkpoint() {
    _undo.add({
      'layers': widget.project.layers.map((e) => e.toJson()).toList(),
    });
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(Map<String, dynamic> state) {
    final layers = (state['layers'] as List<dynamic>)
        .map((e) => EditorLayer.fromJson(e as Map<String, dynamic>)).toList();
    setState(() {
      widget.project.layers = layers;
      _selected = null;
    });
    _autosave();
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add({'layers': widget.project.layers.map((e) => e.toJson()).toList()});
    _restore(_undo.removeLast());
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add({'layers': widget.project.layers.map((e) => e.toJson()).toList()});
    _restore(_redo.removeLast());
  }

  Future<void> _autosave() async {
    await context.read<AppState>().store.save(widget.project);
  }

  Future<void> _addText() async {
    final controller = TextEditingController(text: 'Your text');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add text'),
        content: TextField(controller: controller, autofocus: true, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Add')),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    _checkpoint();
    setState(() {
      widget.project.layers.add(EditorLayer(
        id: _uuid.v4(), type: LayerType.text, text: result,
      ));
      _selected = widget.project.layers.length - 1;
    });
    await _autosave();
  }

  Future<void> _addImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;
    final source = File(result.files.single.path!);
    final appDir = await getApplicationSupportDirectory();
    final assetDir = Directory(p.join(appDir.path, 'LayerStudio', 'assets', widget.project.id));
    await assetDir.create(recursive: true);
    final ext = p.extension(source.path);
    final target = File(p.join(assetDir.path, '${_uuid.v4()}$ext'));
    await source.copy(target.path);
    _checkpoint();
    setState(() {
      widget.project.layers.add(EditorLayer(
        id: _uuid.v4(), type: LayerType.image, assetPath: target.path,
      ));
      _selected = widget.project.layers.length - 1;
    });
    await _autosave();
  }

  void _updateSelected(void Function(EditorLayer layer) update) {
    if (_selected == null || _selected! >= widget.project.layers.length) return;
    _checkpoint();
    setState(() => update(widget.project.layers[_selected!]));
    _autosave();
  }

  Future<void> _export() async {
    if (_base == null || _busy) return;
    setState(() => _busy = true);
    try {
      final output = img.Image(width: _base!.width, height: _base!.height, numChannels: 4);
      img.compositeImage(output, _base!);
      for (final layer in widget.project.layers) {
        if (!layer.visible) continue;
        if (layer.type == LayerType.image && layer.assetPath != null) {
          final overlay = await _imageService.decode(layer.assetPath!);
          final targetWidth = math.max(1, (overlay.width * layer.scale).round());
          final targetHeight = math.max(1, (overlay.height * layer.scale).round());
          final resized = img.copyResize(overlay, width: targetWidth, height: targetHeight);
          img.compositeImage(
            output,
            resized,
            dstX: (layer.x * output.width - targetWidth / 2).round(),
            dstY: (layer.y * output.height - targetHeight / 2).round(),
            blend: img.BlendMode.alpha,
          );
        } else if (layer.type == LayerType.text) {
          final font = img.arial48;
          img.drawString(
            output,
            layer.text,
            font: font,
            x: (layer.x * output.width).round(),
            y: (layer.y * output.height).round(),
            color: img.ColorRgba8(
              (layer.color >> 16) & 255,
              (layer.color >> 8) & 255,
              layer.color & 255,
              ((layer.color >> 24) & 255 * layer.opacity).round().clamp(0, 255),
            ),
          );
        }
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export image',
        fileName: 'layer-studio.png',
        type: FileType.image,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (path == null) return;
      final ext = p.extension(path).toLowerCase();
      if (ext == '.jpg' || ext == '.jpeg') {
        await _imageService.exportJpeg(output, path);
      } else if (ext == '.webp') {
        await _imageService.exportWebp(output, path);
      } else {
        await _imageService.exportPng(output, path);
      }
      _message('Exported successfully');
    } catch (e) {
      _message('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final selected = _selected == null ? null : widget.project.layers[_selected!];
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.project.name),
          actions: [
            IconButton(tooltip: 'Undo', onPressed: _undo.isEmpty ? null : _undoAction, icon: const Icon(Icons.undo)),
            IconButton(tooltip: 'Redo', onPressed: _redo.isEmpty ? null : _redoAction, icon: const Icon(Icons.redo)),
            IconButton(tooltip: 'Save', onPressed: _autosave, icon: const Icon(Icons.save_outlined)),
            IconButton(tooltip: 'Export', onPressed: _busy ? null : _export, icon: const Icon(Icons.file_download_outlined)),
          ],
        ),
        body: LayoutBuilder(builder: (context, constraints) {
          final desktop = constraints.maxWidth > 760;
          final canvas = Center(
            child: InteractiveViewer(
              minScale: .2,
              maxScale: 5,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: widget.project.width.toDouble(),
                  height: widget.project.height.toDouble(),
                  child: _base == null
                      ? const ColoredBox(color: Color(0xFF333333), child: Center(child: CircularProgressIndicator()))
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            RawImage(image: _imageToUi(_base!), fit: BoxFit.fill),
                            for (var i = 0; i < widget.project.layers.length; i++)
                              if (widget.project.layers[i].visible)
                                _layerWidget(widget.project.layers[i], i),
                          ],
                        ),
                ),
              ),
            ),
          );
          final tools = _tools(selected, isAr);
          if (desktop) {
            return Row(children: [
              Expanded(child: canvas),
              SizedBox(width: 310, child: Material(color: Theme.of(context).colorScheme.surface, child: tools)),
            ]);
          }
          return Column(children: [
            Expanded(child: canvas),
            SizedBox(height: 290, child: Material(color: Theme.of(context).colorScheme.surface, child: tools)),
          ]);
        }),
      ),
    );
  }

  ImageProvider? _imageToUi(img.Image image) {
    return MemoryImage(Uint8List.fromList(img.encodePng(image)));
  }

  Widget _layerWidget(EditorLayer layer, int index) {
    final selected = _selected == index;
    return Positioned(
      left: layer.x * widget.project.width - 100 * layer.scale,
      top: layer.y * widget.project.height - 30 * layer.scale,
      child: GestureDetector(
        onTap: () => setState(() => _selected = index),
        onPanUpdate: layer.locked ? null : (details) {
          setState(() {
            layer.x += details.delta.dx / widget.project.width;
            layer.y += details.delta.dy / widget.project.height;
          });
        },
        child: Transform.rotate(
          angle: layer.rotation,
          child: Transform.scale(
            scale: layer.scale,
            child: Container(
              decoration: selected ? BoxDecoration(border: Border.all(color: Colors.blueAccent, width: 2)) : null,
              padding: const EdgeInsets.all(4),
              child: layer.type == LayerType.text
                  ? Text(layer.text, style: TextStyle(
                      fontFamily: layer.fontFamily,
                      fontSize: layer.fontSize,
                      color: Color(layer.color).withOpacity(layer.opacity),
                      fontWeight: layer.bold ? FontWeight.bold : FontWeight.normal,
                      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
                    ))
                  : (layer.assetPath != null && File(layer.assetPath!).existsSync()
                      ? Image.file(File(layer.assetPath!), width: 180, fit: BoxFit.contain)
                      : const Icon(Icons.broken_image)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tools(EditorLayer? selected, bool isAr) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(onPressed: _addText, icon: const Icon(Icons.text_fields), label: Text(isAr ? 'نص' : 'Text')),
          FilledButton.tonalIcon(onPressed: _addImage, icon: const Icon(Icons.add_photo_alternate), label: Text(isAr ? 'صورة / شعار' : 'Image / logo')),
        ]),
        const SizedBox(height: 14),
        Text(isAr ? 'الطبقات' : 'Layers', style: Theme.of(context).textTheme.titleMedium),
        for (var i = widget.project.layers.length - 1; i >= 0; i--)
          ListTile(
            dense: true,
            selected: _selected == i,
            leading: Icon(widget.project.layers[i].type == LayerType.text ? Icons.text_fields : Icons.image_outlined),
            title: Text(widget.project.layers[i].type == LayerType.text ? widget.project.layers[i].text : 'Image layer', maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => setState(() => _selected = i),
            trailing: Wrap(children: [
              IconButton(icon: Icon(widget.project.layers[i].visible ? Icons.visibility : Icons.visibility_off, size: 18), onPressed: () { _updateAt(i, (l) => l.visible = !l.visible); }),
              IconButton(icon: Icon(widget.project.layers[i].locked ? Icons.lock : Icons.lock_open, size: 18), onPressed: () { _updateAt(i, (l) => l.locked = !l.locked); }),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () { _checkpoint(); setState(() { widget.project.layers.removeAt(i); _selected = null; }); _autosave(); }),
            ]),
          ),
        if (selected != null) ...[
          const Divider(),
          Text(isAr ? 'خصائص العنصر' : 'Selected layer', style: Theme.of(context).textTheme.titleMedium),
          if (selected.type == LayerType.text) ...[
            TextFormField(initialValue: selected.text, decoration: const InputDecoration(labelText: 'Text'), onChanged: (v) => _updateSelected((l) => l.text = v)),
            Slider(value: selected.fontSize.clamp(12, 160), min: 12, max: 160, label: selected.fontSize.round().toString(), onChanged: (v) => _updateSelected((l) => l.fontSize = v)),
            Wrap(spacing: 6, children: [
              _colorButton(Colors.white, 0xFFFFFFFF, selected),
              _colorButton(Colors.black, 0xFF000000, selected),
              _colorButton(Colors.red, 0xFFFF5252, selected),
              _colorButton(Colors.amber, 0xFFFFC107, selected),
              _colorButton(Colors.blue, 0xFF448AFF, selected),
              IconButton(onPressed: () => _updateSelected((l) => l.bold = !l.bold), icon: const Icon(Icons.format_bold)),
              IconButton(onPressed: () => _updateSelected((l) => l.italic = !l.italic), icon: const Icon(Icons.format_italic)),
            ]),
          ],
          Text(isAr ? 'الحجم' : 'Scale', style: Theme.of(context).textTheme.bodySmall),
          Slider(value: selected.scale.clamp(.2, 4), min: .2, max: 4, onChanged: (v) => _updateSelected((l) => l.scale = v)),
          Text(isAr ? 'الدوران' : 'Rotation', style: Theme.of(context).textTheme.bodySmall),
          Slider(value: selected.rotation.clamp(-math.pi, math.pi), min: -math.pi, max: math.pi, onChanged: (v) => _updateSelected((l) => l.rotation = v)),
          Text(isAr ? 'الشفافية' : 'Opacity', style: Theme.of(context).textTheme.bodySmall),
          Slider(value: selected.opacity.clamp(0, 1), min: 0, max: 1, onChanged: (v) => _updateSelected((l) => l.opacity = v)),
        ],
      ],
    );
  }

  Widget _colorButton(Color color, int value, EditorLayer layer) => InkWell(
    onTap: () => _updateSelected((l) => l.color = value),
    child: Container(width: 28, height: 28, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.grey))),
  );

  void _updateAt(int index, void Function(EditorLayer layer) update) {
    _checkpoint();
    setState(() => update(widget.project.layers[index]));
    _autosave();
  }
}
