import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/editor_layer.dart';
import '../models/editor_project.dart';
import '../services/render_service.dart';
import '../services/image_service.dart';
import '../services/project_store.dart';
import '../state/app_state.dart';

const _fontFamilies = <String>[
  'Cairo',
  'Almarai',
  'Alexandria',
  'Amiri',
  'Changa',
  'Fustat',
  'Mada',
  'Harmattan',
  'Kufam',
  'Marhey',
  'Oi',
  'Rakkas',
  'Open Sans',
  'Montserrat',
  'Oswald',
  'Lato',
  'Poppins',
  'Lora',
  'Nunito',
  'Raleway',
  'Merriweather',
  'Roboto',
  'Inter',
  'Archivo',
];

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project});

  final EditorProject project;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _renderer = RenderService();
  final _imageService = ImageService();
  late final ProjectStore _store;
  final _uuid = const Uuid();
  final _undo = <List<Map<String, dynamic>>>[];
  final _redo = <List<Map<String, dynamic>>>[];
  Timer? _saveTimer;
  final TransformationController _zoomController = TransformationController();
  Map<String, dynamic>? _savedProjectSnapshot;
  int? _selected;
  bool _baseLoaded = false;
  bool _busy = false;
  bool _saving = false;
  bool _dirty = false;
  bool _allowPop = false;
  bool _exitDialogOpen = false;
  bool _zoomInitialized = false;

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(String en, String ar) => _isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _store = context.read<AppState>().store;
    _savedProjectSnapshot = _captureProject();
    _loadBase();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _zoomController.dispose();
    unawaited(_store.save(widget.project));
    super.dispose();
  }

  Future<void> _loadBase() async {
    try {
      var changed = false;
      final source = File(widget.project.originalPath);
      if (!await source.exists()) {
        throw StateError('Original image is missing.');
      }

      final normalizedBase = await _imageService.decode(source.path);
      if (p.extension(source.path).toLowerCase() != '.png' ||
          widget.project.width != normalizedBase.width ||
          widget.project.height != normalizedBase.height) {
        final target = File(p.join(source.parent.path, 'original-upright.png'));
        await _imageService.writePng(normalizedBase, target.path);
        widget.project.originalPath = target.path;
        widget.project.width = normalizedBase.width;
        widget.project.height = normalizedBase.height;
        changed = true;
      }

      // Migrate older raster overlays too, so projects created by previous
      // builds no longer depend on platform-specific EXIF decoding.
      for (final layer in widget.project.layers) {
        if (layer.type != LayerType.image ||
            layer.assetPath == null ||
            p.extension(layer.assetPath!).toLowerCase() == '.svg') {
          continue;
        }
        final overlayFile = File(layer.assetPath!);
        if (!await overlayFile.exists()) continue;

        final normalizedOverlay = await _imageService.decode(overlayFile.path);
        if (p.extension(overlayFile.path).toLowerCase() != '.png') {
          final target = File(
            p.join(overlayFile.parent.path, '${_uuid.v4()}-upright.png'),
          );
          await _imageService.writePng(normalizedOverlay, target.path);
          layer.assetPath = target.path;
          changed = true;
        }
        if (layer.assetWidth != normalizedOverlay.width ||
            layer.assetHeight != normalizedOverlay.height) {
          layer.assetWidth = normalizedOverlay.width;
          layer.assetHeight = normalizedOverlay.height;
          changed = true;
        }
      }

      if (changed) {
        await _store.save(widget.project);
        _savedProjectSnapshot = _captureProject();
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

  Map<String, dynamic> _captureProject() =>
      jsonDecode(jsonEncode(widget.project.toJson())) as Map<String, dynamic>;

  void _autosave() {
    if (!_dirty && mounted) {
      setState(() => _dirty = true);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      _saveNow();
    });
  }

  Future<bool> _saveNow({bool manual = false}) async {
    _saveTimer?.cancel();
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (!mounted) return false;
    }

    if (mounted) setState(() => _saving = true);
    try {
      await _store.save(widget.project);
      if (manual) {
        _savedProjectSnapshot = _captureProject();
        if (mounted) setState(() => _dirty = false);
        if (mounted) _message(_t('Project saved successfully', 'تم حفظ المشروع بنجاح'));
      }
      return true;
    } catch (error) {
      if (mounted) _message('${_t('Save failed', 'فشل الحفظ')}: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreLastSavedProject() async {
    final snapshot = _savedProjectSnapshot;
    if (snapshot == null) return;
    final saved = EditorProject.fromJson(snapshot);
    widget.project.name = saved.name;
    widget.project.originalPath = saved.originalPath;
    widget.project.width = saved.width;
    widget.project.height = saved.height;
    widget.project.createdAt = saved.createdAt;
    widget.project.updatedAt = saved.updatedAt;
    widget.project.layers = saved.layers.map((layer) => layer.copy()).toList();
    await _store.save(widget.project);
    if (mounted) setState(() => _dirty = false);
  }

  Future<void> _confirmLeave() async {
    if (_exitDialogOpen || !_dirty || !mounted) return;
    _exitDialogOpen = true;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Unsaved changes', 'تغييرات غير محفوظة')),
        content: Text(_t(
          'You have changes that were not manually saved. Save before leaving?',
          'لديك تعديلات لم تحفظها يدوياً. هل تريد حفظها قبل الخروج؟',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'stay'),
            child: Text(_t('Stay', 'البقاء')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: Text(_t('Discard', 'تجاهل التعديلات')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: Text(_t('Save & exit', 'حفظ وخروج')),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (!mounted || action == null || action == 'stay') return;

    if (action == 'save') {
      final saved = await _saveNow(manual: true);
      if (!saved || !mounted) return;
    } else if (action == 'discard') {
      try {
        await _restoreLastSavedProject();
      } catch (error) {
        if (mounted) _message('${_t('Could not restore saved version', 'تعذرت استعادة النسخة المحفوظة')}: $error');
        return;
      }
    }

    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
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
    controller.dispose();
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
    controller.dispose();
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
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'svg'],
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
      var assetWidth = 0;
      var assetHeight = 0;
      late final File target;

      if (extension == '.svg') {
        target = File(p.join(assetDir.path, '${_uuid.v4()}.svg'));
        await source.copy(target.path);
      } else {
        final normalized = await _imageService.decode(source.path);
        target = File(p.join(assetDir.path, '${_uuid.v4()}.png'));
        await _imageService.writePng(normalized, target.path);
        assetWidth = normalized.width;
        assetHeight = normalized.height;
      }

      _checkpoint();
      setState(() {
        widget.project.layers.add(EditorLayer(
          id: _uuid.v4(),
          type: LayerType.image,
          assetPath: target.path,
          assetWidth: assetWidth,
          assetHeight: assetHeight,
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

    return PopScope(
      canPop: !_dirty || _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _dirty) {
          _confirmLeave();
        }
      },
      child: Directionality(
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
              onPressed: _saving ? null : () => _saveNow(manual: true),
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
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(1.0, constraints.maxWidth - 32);
        final availableHeight = math.max(1.0, constraints.maxHeight - 32);
        final fitScale = math.min(
          availableWidth / widget.project.width,
          availableHeight / widget.project.height,
        ).clamp(0.02, 1.0).toDouble();

        if (!_zoomInitialized && _baseLoaded) {
          _zoomInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final offsetX = (constraints.maxWidth - widget.project.width * fitScale) / 2;
            final offsetY = (constraints.maxHeight - widget.project.height * fitScale) / 2;
            _zoomController.value = Matrix4.identity()
              ..translate(offsetX, offsetY)
              ..scale(fitScale);
          });
        }

        return Container(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF181820)
              : const Color(0xFFE7E7EE),
          alignment: Alignment.center,
          child: !_baseLoaded
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(
                  transformationController: _zoomController,
                  constrained: false,
                  minScale: fitScale * 0.5,
                  maxScale: fitScale * 8,
                  boundaryMargin: EdgeInsets.all(
                    math.max(widget.project.width, widget.project.height).toDouble(),
                  ),
                  clipBehavior: Clip.hardEdge,
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
        );
      },
    );
  }

  Widget _rawLayerImage(EditorLayer layer) {
    final aspectRatio = layer.assetWidth > 0 && layer.assetHeight > 0
        ? layer.assetWidth / layer.assetHeight
        : 1.0;
    final displayWidth = math.max(
      1.0,
      math.min(
        widget.project.width * .30,
        widget.project.height * .30 * aspectRatio,
      ),
    );

    if (layer.assetPath == null || !File(layer.assetPath!).existsSync()) {
      return SizedBox(
        width: displayWidth,
        height: displayWidth / aspectRatio,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    final file = File(layer.assetPath!);
    if (p.extension(layer.assetPath!).toLowerCase() == '.svg') {
      return SvgPicture.file(file, width: displayWidth, fit: BoxFit.contain);
    }
    return Image.file(
      file,
      width: displayWidth,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }

  Widget _buildLayer(EditorLayer layer, int index) {
    final isSelected = _selected == index;
    final effectiveTextColor = layer.overlayOpacity > 0
        ? Color.alphaBlend(
            Color(layer.overlayColor).withValues(
              alpha: (layer.overlayOpacity * Color(layer.overlayColor).a)
                  .clamp(0.0, 1.0)
                  .toDouble(),
            ),
            Color(layer.color),
          )
        : Color(layer.color);

    Widget visual;
    if (layer.type == LayerType.text) {
      final textDirection =
          RegExp(r'[\u0600-\u06FF]').hasMatch(layer.text)
              ? TextDirection.rtl
              : TextDirection.ltr;
      final shadows = layer.shadowBlur > 0 ||
              layer.shadowOffsetX != 0 ||
              layer.shadowOffsetY != 0
          ? [
              Shadow(
                color: Color(layer.shadowColor),
                blurRadius: layer.shadowBlur,
                offset: Offset(layer.shadowOffsetX, layer.shadowOffsetY),
              ),
            ]
          : const <Shadow>[];
      final common = TextStyle(
        fontFamily: layer.fontFamily,
        fontSize: layer.fontSize,
        fontWeight: layer.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      );
      visual = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (layer.strokeWidth > 0)
            Text(
              layer.text,
              textAlign: _textAlign(layer.align),
              textDirection: textDirection,
              style: common.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeJoin = StrokeJoin.round
                  ..strokeWidth = layer.strokeWidth * 2
                  ..color = Color(layer.strokeColor),
              ),
            ),
          Text(
            layer.text,
            textAlign: _textAlign(layer.align),
            textDirection: textDirection,
            style: common.copyWith(color: effectiveTextColor, shadows: shadows),
          ),
        ],
      );
    } else {
      final raw = _rawLayerImage(layer);
      final shadow = layer.shadowBlur > 0 ||
              layer.shadowOffsetX != 0 ||
              layer.shadowOffsetY != 0
          ? Transform.translate(
              offset: Offset(layer.shadowOffsetX, layer.shadowOffsetY),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: layer.shadowBlur,
                  sigmaY: layer.shadowBlur,
                ),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Color(layer.shadowColor),
                    BlendMode.srcIn,
                  ),
                  child: raw,
                ),
              ),
            )
          : null;
      final outlined = <Widget>[];
      if (layer.strokeWidth > 0) {
        for (var i = 0; i < 20; i++) {
          final angle = (i / 20) * math.pi * 2;
          outlined.add(
            Transform.translate(
              offset: Offset(
                math.cos(angle) * layer.strokeWidth,
                math.sin(angle) * layer.strokeWidth,
              ),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Color(layer.strokeColor),
                  BlendMode.srcIn,
                ),
                child: raw,
              ),
            ),
          );
        }
      }
      final tinted = layer.overlayOpacity > 0
          ? ColorFiltered(
              colorFilter: ColorFilter.mode(
                Color(layer.overlayColor).withValues(
                  alpha: (layer.overlayOpacity * Color(layer.overlayColor).a)
                      .clamp(0.0, 1.0)
                      .toDouble(),
                ),
                BlendMode.srcATop,
              ),
              child: raw,
            )
          : raw;
      visual = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (shadow != null) shadow,
          ...outlined,
          tinted,
        ],
      );
    }

    return Positioned(
      left: layer.x * widget.project.width,
      top: layer.y * widget.project.height,
      child: FractionalTranslation(
        translation: const Offset(-.5, -.5),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _selectLayer(index),
          onPanStart: layer.locked
              ? null
              : (_) {
                  _checkpoint();
                  _autosave();
                },
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
              child: Transform.flip(
                flipX: layer.flipX,
                flipY: layer.flipY,
                child: Opacity(
                  opacity: layer.opacity.clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(
                      minWidth: 72,
                      minHeight: 64,
                    ),
                    decoration: isSelected
                        ? BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          )
                        : null,
                    child: visual,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextAlign _textAlign(String alignment) => switch (alignment) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      };

  Widget _buildTools(EditorLayer? selected) {
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
              items: _fontFamilies
                  .map((family) => DropdownMenuItem(
                        value: family,
                        child: Text(family),
                      ))
                  .toList(),
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
            _colorControl(
              _t('Text color', 'لون النص'),
              Color(selected.color),
              () => _chooseColor(
                Color(selected.color),
                (layer, color) => layer.color = color,
              ),
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _updateSelected((layer) => layer.flipX = !layer.flipX),
                icon: const Icon(Icons.flip),
                label: Text(_t('Flip H', 'قلب أفقي')),
              ),
              OutlinedButton.icon(
                onPressed: () => _updateSelected((layer) => layer.flipY = !layer.flipY),
                icon: const Icon(Icons.flip_camera_android_outlined),
                label: Text(_t('Flip V', 'قلب رأسي')),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(_t('Effects', 'التأثيرات')),
            subtitle: Text(_t('Stroke • Color overlay • Shadow', 'ستروك • تلوين • ظل')),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [
              _colorControl(
                _t('Stroke color', 'لون الستروك'),
                Color(selected.strokeColor),
                () => _chooseColor(
                  Color(selected.strokeColor),
                  (layer, color) => layer.strokeColor = color,
                ),
              ),
              _slider(
                _t('Stroke width', 'سُمك الستروك'),
                selected.strokeWidth.clamp(0.0, 24.0).toDouble(),
                0,
                24,
                (value) => _updateSelected((layer) => layer.strokeWidth = value),
              ),
              const Divider(height: 20),
              _colorControl(
                _t('Color overlay', 'لون الأوفرلاي'),
                Color(selected.overlayColor),
                () => _chooseColor(
                  Color(selected.overlayColor),
                  (layer, color) => layer.overlayColor = color,
                ),
              ),
              _slider(
                _t('Overlay strength', 'قوة الأوفرلاي'),
                selected.overlayOpacity.clamp(0.0, 1.0).toDouble(),
                0,
                1,
                (value) => _updateSelected((layer) => layer.overlayOpacity = value),
              ),
              const Divider(height: 20),
              _colorControl(
                _t('Shadow color', 'لون الظل'),
                Color(selected.shadowColor),
                () => _chooseColor(
                  Color(selected.shadowColor),
                  (layer, color) => layer.shadowColor = color,
                ),
              ),
              _slider(
                _t('Shadow blur', 'تمويه الظل'),
                selected.shadowBlur.clamp(0.0, 50.0).toDouble(),
                0,
                50,
                (value) => _updateSelected((layer) => layer.shadowBlur = value),
              ),
              _slider(
                _t('Shadow horizontal offset', 'إزاحة الظل أفقياً'),
                selected.shadowOffsetX.clamp(-50.0, 50.0).toDouble(),
                -50,
                50,
                (value) => _updateSelected((layer) => layer.shadowOffsetX = value),
              ),
              _slider(
                _t('Shadow vertical offset', 'إزاحة الظل رأسياً'),
                selected.shadowOffsetY.clamp(-50.0, 50.0).toDouble(),
                -50,
                50,
                (value) => _updateSelected((layer) => layer.shadowOffsetY = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _slider(
            selected.type == LayerType.image
                ? _t('Image scale (up to 20×)', 'تكبير الصورة (حتى 20×)')
                : _t('Text scale (up to 10×)', 'تكبير النص (حتى 10×)'),
            selected.scale
                .clamp(.1, selected.type == LayerType.image ? 20.0 : 10.0)
                .toDouble(),
            .1,
            selected.type == LayerType.image ? 20 : 10,
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

  Future<Color?> _showColorPicker(Color initial) async {
    var hsv = HSVColor.fromColor(initial);
    var alpha = initial.opacity;
    final result = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final color = hsv.withAlpha(alpha).toColor();
          return AlertDialog(
            title: Text(_t('Choose any color', 'اختر أي لون')),
            content: SizedBox(
              width: math.min(360.0, MediaQuery.sizeOf(dialogContext).width - 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 46,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(dialogContext).dividerColor),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _pickerSlider(
                    dialogContext,
                    _t('Hue', 'درجة اللون'),
                    hsv.hue,
                    0,
                    360,
                    (value) => setDialogState(() => hsv = hsv.withHue(value)),
                  ),
                  _pickerSlider(
                    dialogContext,
                    _t('Saturation', 'التشبع'),
                    hsv.saturation,
                    0,
                    1,
                    (value) => setDialogState(() => hsv = hsv.withSaturation(value)),
                  ),
                  _pickerSlider(
                    dialogContext,
                    _t('Brightness', 'السطوع'),
                    hsv.value,
                    0,
                    1,
                    (value) => setDialogState(() => hsv = hsv.withValue(value)),
                  ),
                  _pickerSlider(
                    dialogContext,
                    _t('Alpha / transparency', 'الشفافية'),
                    alpha,
                    0,
                    1,
                    (value) => setDialogState(() => alpha = value),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                    style: Theme.of(dialogContext).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_t('Cancel', 'إلغاء')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, color),
                child: Text(_t('Apply', 'تطبيق')),
              ),
            ],
          );
        },
      ),
    );
    return result;
  }

  Widget _pickerSlider(
    BuildContext dialogContext,
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
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _chooseColor(
    Color current,
    void Function(EditorLayer layer, int color) apply,
  ) async {
    final color = await _showColorPicker(current);
    if (color == null || !mounted) return;
    _updateSelected((layer) => apply(layer, color.value));
  }

  Widget _colorControl(String label, Color color, VoidCallback onPressed) {
    final hex = color.value.toRadixString(16).padLeft(8, '0').toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '#$hex',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_t('Pick', 'اختيار')),
              ],
            ),
          ),
        ],
      ),
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

}
