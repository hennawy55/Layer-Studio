import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/editor_layer.dart';
import '../models/editor_project.dart';
import '../services/render_service.dart';
import '../state/app_state.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project});

  final EditorProject project;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _renderer = RenderService();
  final _uuid = const Uuid();
  final _undo = <List<Map<String, dynamic>>>[];
  final _redo = <List<Map<String, dynamic>>>[];
  Timer? _saveTimer;
  int? _selected;
  bool _baseLoaded = false;
  bool _busy = false;
  bool _saving = false;
  int _exportQuality = 95;

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(String en, String ar) => _isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBase() async {
    try {
      final file = File(widget.project.originalPath);
      if (!await file.exists()) {
        throw const FileSystemException('Original image is missing.');
      }
      if (mounted) setState(() => _baseLoaded = true);
    } catch (error) {
      if (mounted) _message('${_t('Could not open image', 'تعذر فتح الصورة')}: $error');
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  List<Map<String, dynamic>> _snapshot() =>
      widget.project.layers.map((layer) => layer.toJson()).toList();

  void _checkpoint() {
    _undo.add(_snapshot());
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(List<Map<String, dynamic>> snapshot) {
    setState(() {
      widget.project.layers = snapshot
          .map(EditorLayer.fromJson)
          .toList();
      _selected = null;
    });
    _autosave();
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  void _autosave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 650), _saveNow);
  }

  Future<void> _saveNow() async {
    if (_saving) return;
    _saveTimer?.cancel();
    setState(() => _saving = true);
    try {
      await context.read<AppState>().store.save(widget.project);
    } catch (error) {
      if (mounted) _message('${_t('Save failed', 'فشل الحفظ')}: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _renameProject() async {
    final controller = TextEditingController(text: widget.project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Rename project', 'إعادة تسمية المشروع')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(
            labelText: _t('Project name', 'اسم المشروع'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(_t('Save', 'حفظ')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => widget.project.name = name);
    _autosave();
  }

  Future<void> _addText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Add text', 'إضافة نص')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
          decoration: InputDecoration(
            hintText: _t('Write something…', 'اكتب النص هنا…'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(_t('Add', 'إضافة')),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;

    _checkpoint();
    setState(() {
      widget.project.layers.add(EditorLayer(
        id: _uuid.v4(),
        type: LayerType.text,
        text: text.trim(),
        fontFamily: 'Cairo',
      ));
      _selected = widget.project.layers.length - 1;
    });
    _autosave();
  }

  Future<void> _addImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final source = File(result.files.single.path!);
      final appDir = await getApplicationSupportDirectory();
      final assetDir = Directory(p.join(
        appDir.path,
        'LayerStudio',
        'projects',
        widget.project.id,
        'assets',
        'overlays',
      ));
      await assetDir.create(recursive: true);

      final extension = p.extension(source.path).toLowerCase();
      final target = File(p.join(assetDir.path, '${_uuid.v4()}$extension'));
      await source.copy(target.path);

      _checkpoint();
      setState(() {
        widget.project.layers.add(EditorLayer(
          id: _uuid.v4(),
          type: LayerType.image,
          assetPath: target.path,
        ));
        _selected = widget.project.layers.length - 1;
      });
      _autosave();
    } catch (error) {
      _message('${_t('Could not add image', 'تعذرت إضافة الصورة')}: $error');
    }
  }

  void _selectLayer(int index) {
    setState(() => _selected = index);
  }

  void _updateSelected(void Function(EditorLayer layer) update) {
    if (_selected == null || _selected! >= widget.project.layers.length) {
      return;
    }
    _checkpoint();
    setState(() => update(widget.project.layers[_selected!]));
    _autosave();
  }

  void _updateAt(int index, void Function(EditorLayer layer) update) {
    if (index < 0 || index >= widget.project.layers.length) return;
    _checkpoint();
    setState(() => update(widget.project.layers[index]));
    _autosave();
  }

  void _moveLayer(int index, int offset) {
    final next = index + offset;
    if (next < 0 || next >= widget.project.layers.length) return;
    _checkpoint();
    setState(() {
      final layer = widget.project.layers.removeAt(index);
      widget.project.layers.insert(next, layer);
      if (_selected == index) _selected = next;
      else if (_selected == next) _selected = index;
    });
    _autosave();
  }

  Future<void> _export() async {
    if (!_baseLoaded || _busy) return;

    var format = 'png';
    var quality = 95;
    final options = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_t('Export image', 'تصدير الصورة')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: format,
                decoration: InputDecoration(
                  labelText: _t('Format', 'الصيغة'),
                ),
                items: const [
                  DropdownMenuItem(value: 'png', child: Text('PNG')),
                  DropdownMenuItem(value: 'jpg', child: Text('JPG')),
                  DropdownMenuItem(value: 'webp', child: Text('WebP')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => format = value);
                },
              ),
              if (format != 'png') ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Text(_t('Quality', 'الجودة'))),
                    Text('$quality%'),
                  ],
                ),
                Slider(
                  value: quality.toDouble(),
                  min: 50,
                  max: 100,
                  divisions: 50,
                  onChanged: (value) =>
                      setDialogState(() => quality = value.round()),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _t(
                  'Output dimensions: original image size',
                  'أبعاد التصدير: نفس أبعاد الصورة الأصلية',
                ),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_t('Continue', 'متابعة')),
            ),
          ],
        ),
      ),
    );
    if (options != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await _renderer.render(
        widget.project,
        extension: format,
        jpegQuality: quality,
        webpQuality: quality,
      );

      if (Platform.isAndroid) {
        await Gal.putImageBytes(
          bytes,
          album: 'Layer Studio',
          name: 'layer-studio-${DateTime.now().millisecondsSinceEpoch}',
        );
        if (mounted) {
          _message(_t('Saved to the Layer Studio album', 'تم الحفظ في ألبوم Layer Studio'));
        }
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: _t('Save exported image', 'حفظ الصورة المصدّرة'),
          fileName: 'layer-studio.$format',
          type: FileType.custom,
          allowedExtensions: [format],
        );
        if (path == null) return;
        await File(path).writeAsBytes(bytes, flush: true);
        if (mounted) _message(_t('Image exported successfully', 'تم تصدير الصورة بنجاح'));
      }
    } catch (error) {
      if (mounted) _message('${_t('Export failed', 'فشل التصدير')}: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected == null
        ? null
        : widget.project.layers[_selected!];

    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            onTap: _renameProject,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(widget.project.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined, size: 16),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: _t('Undo', 'تراجع'),
              onPressed: _undo.isEmpty ? null : _undoAction,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: _t('Redo', 'إعادة'),
              onPressed: _redo.isEmpty ? null : _redoAction,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: _t('Save', 'حفظ'),
              onPressed: _saving ? null : _saveNow,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
            ),
            IconButton(
              tooltip: _t('Export', 'تصدير'),
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth > 760;
            final canvas = _buildCanvas();
            final tools = _buildTools(selected);

            if (desktop) {
              return Row(
                children: [
                  Expanded(child: canvas),
                  SizedBox(
                    width: 330,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: tools,
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                Expanded(child: canvas),
                SizedBox(
                  height: math.min(340.0, constraints.maxHeight * .49),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: tools,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF181820)
          : const Color(0xFFE7E7EE),
      alignment: Alignment.center,
      child: !_baseLoaded
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
              minScale: .2,
              maxScale: 5,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: widget.project.width.toDouble(),
                  height: widget.project.height.toDouble(),
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      Image.file(
                        File(widget.project.originalPath),
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                      for (var i = 0; i < widget.project.layers.length; i++)
                        if (widget.project.layers[i].visible)
                          _buildLayer(widget.project.layers[i], i),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildLayer(EditorLayer layer, int index) {
    final isSelected = _selected == index;
    final child = layer.type == LayerType.text
        ? Text(
            layer.text,
            textAlign: switch (layer.align) {
              'left' => TextAlign.left,
              'right' => TextAlign.right,
              _ => TextAlign.center,
            },
            textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(layer.text)
                ? TextDirection.rtl
                : TextDirection.ltr,
            style: TextStyle(
              fontFamily: layer.fontFamily,
              fontSize: layer.fontSize,
              color: Color(layer.color).withOpacity(layer.opacity),
              fontWeight: layer.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
            ),
          )
        : (layer.assetPath != null && File(layer.assetPath!).existsSync()
            ? Image.file(
                File(layer.assetPath!),
                width: 180,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              )
            : const Icon(Icons.broken_image_outlined));

    return Positioned(
      left: layer.x * widget.project.width,
      top: layer.y * widget.project.height,
      child: FractionalTranslation(
        translation: const Offset(-.5, -.5),
        child: GestureDetector(
          onTap: () => _selectLayer(index),
          onPanStart: layer.locked ? null : (_) => _checkpoint(),
          onPanUpdate: layer.locked
              ? null
              : (details) {
                  setState(() {
                    layer.x += details.delta.dx / widget.project.width;
                    layer.y += details.delta.dy / widget.project.height;
                  });
                },
          onPanEnd: layer.locked ? null : (_) => _autosave(),
          child: Transform.rotate(
            angle: layer.rotation,
            child: Transform.scale(
              scale: layer.scale,
              child: Opacity(
                opacity: layer.opacity.clamp(0.0, 1.0).toDouble(),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: isSelected
                      ? BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        )
                      : null,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTools(EditorLayer? selected) {
    final isDesktop = MediaQuery.sizeOf(context).width > 760;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _addText,
              icon: const Icon(Icons.text_fields),
              label: Text(_t('Text', 'نص')),
            ),
            FilledButton.tonalIcon(
              onPressed: _addImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_t('Image / logo', 'صورة / شعار')),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                _t('Layers', 'الطبقات'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${widget.project.layers.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = widget.project.layers.length - 1; i >= 0; i--)
          Card(
            color: _selected == i
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            child: ListTile(
              dense: true,
              selected: _selected == i,
              leading: Icon(
                widget.project.layers[i].type == LayerType.text
                    ? Icons.text_fields
                    : Icons.image_outlined,
              ),
              title: Text(
                widget.project.layers[i].type == LayerType.text
                    ? widget.project.layers[i].text
                    : _t('Image layer', 'طبقة صورة'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectLayer(i),
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  switch (action) {
                    case 'visible':
                      _updateAt(i, (layer) => layer.visible = !layer.visible);
                      break;
                    case 'locked':
                      _updateAt(i, (layer) => layer.locked = !layer.locked);
                      break;
                    case 'up':
                      _moveLayer(i, 1);
                      break;
                    case 'down':
                      _moveLayer(i, -1);
                      break;
                    case 'delete':
                      _checkpoint();
                      setState(() {
                        widget.project.layers.removeAt(i);
                        _selected = null;
                      });
                      _autosave();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'visible',
                    child: Text(widget.project.layers[i].visible
                        ? _t('Hide', 'إخفاء')
                        : _t('Show', 'إظهار')),
                  ),
                  PopupMenuItem(
                    value: 'locked',
                    child: Text(widget.project.layers[i].locked
                        ? _t('Unlock', 'إلغاء القفل')
                        : _t('Lock', 'قفل')),
                  ),
                  PopupMenuItem(value: 'up', child: Text(_t('Bring forward', 'تقديم للأمام'))),
                  PopupMenuItem(value: 'down', child: Text(_t('Send backward', 'إرسال للخلف'))),
                  PopupMenuItem(value: 'delete', child: Text(_t('Delete', 'حذف'))),
                ],
              ),
            ),
          ),
        if (selected != null) ...[
          const Divider(height: 24),
          Text(
            _t('Selected layer', 'العنصر المحدد'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (selected.type == LayerType.text) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('text-${selected.id}'),
              initialValue: selected.text,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _t('Text content', 'محتوى النص'),
                border: const OutlineInputBorder(),
              ),
              textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
              onChanged: (value) {
                selected.text = value;
                _autosave();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selected.fontFamily,
              decoration: InputDecoration(
                labelText: _t('Font', 'الخط'),
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Cairo', child: Text('Cairo')),
                DropdownMenuItem(value: 'Open Sans', child: Text('Open Sans')),
              ],
              onChanged: (value) {
                if (value != null) _updateSelected((layer) => layer.fontFamily = value);
              },
            ),
            const SizedBox(height: 8),
            _slider(
              _t('Font size', 'حجم الخط'),
              selected.fontSize.clamp(12.0, 180.0).toDouble(),
              12,
              180,
              (value) => _updateSelected((layer) => layer.fontSize = value),
            ),
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: _t('Bold', 'عريض'),
                  onPressed: () => _updateSelected((layer) => layer.bold = !layer.bold),
                  icon: Icon(Icons.format_bold, color: selected.bold ? Theme.of(context).colorScheme.primary : null),
                ),
                IconButton(
                  tooltip: _t('Italic', 'مائل'),
                  onPressed: () => _updateSelected((layer) => layer.italic = !layer.italic),
                  icon: Icon(Icons.format_italic, color: selected.italic ? Theme.of(context).colorScheme.primary : null),
                ),
                IconButton(
                  tooltip: _t('Align left', 'محاذاة لليسار'),
                  onPressed: () => _updateSelected((layer) => layer.align = 'left'),
                  icon: const Icon(Icons.format_align_left),
                ),
                IconButton(
                  tooltip: _t('Center', 'توسيط'),
                  onPressed: () => _updateSelected((layer) => layer.align = 'center'),
                  icon: const Icon(Icons.format_align_center),
                ),
                IconButton(
                  tooltip: _t('Align right', 'محاذاة لليمين'),
                  onPressed: () => _updateSelected((layer) => layer.align = 'right'),
                  icon: const Icon(Icons.format_align_right),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                _colorButton(Colors.white, 0xFFFFFFFF, selected),
                _colorButton(Colors.black, 0xFF000000, selected),
                _colorButton(Colors.red, 0xFFFF5252, selected),
                _colorButton(Colors.amber, 0xFFFFC107, selected),
                _colorButton(Colors.blue, 0xFF448AFF, selected),
                _colorButton(Colors.green, 0xFF4CAF50, selected),
              ],
            ),
          ],
          _slider(
            _t('Scale', 'الحجم'),
            selected.scale.clamp(.2, 5.0).toDouble(),
            .2,
            5,
            (value) => _updateSelected((layer) => layer.scale = value),
          ),
          _slider(
            _t('Rotation', 'الدوران'),
            selected.rotation.clamp(-math.pi, math.pi).toDouble(),
            -math.pi,
            math.pi,
            (value) => _updateSelected((layer) => layer.rotation = value),
          ),
          _slider(
            _t('Opacity', 'الشفافية'),
            selected.opacity.clamp(0.0, 1.0).toDouble(),
            0,
            1,
            (value) => _updateSelected((layer) => layer.opacity = value),
          ),
        ],
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value.toStringAsFixed(2)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _colorButton(Color color, int value, EditorLayer layer) {
    final selectedColor = layer.color == value;
    return InkWell(
      onTap: () => _updateSelected((item) => item.color = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selectedColor ? Theme.of(context).colorScheme.primary : Colors.grey,
            width: selectedColor ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
