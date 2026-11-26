import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/editor_layer.dart';
import '../models/editor_project.dart';
import '../models/logo_asset.dart';
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
  const EditorScreen({
    super.key,
    required this.project,
    this.isDraft = false,
  });

  final EditorProject project;
  final bool isDraft;

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
  final TransformationController _zoomController = TransformationController();
  final ValueNotifier<int> _canvasRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _controlsRevision = ValueNotifier<int>(0);
  Map<String, dynamic>? _savedProjectSnapshot;
  int? _selected;
  bool _baseLoaded = false;
  bool _busy = false;
  bool _saving = false;
  bool _dirty = false;
  bool _allowPop = false;
  bool _exitDialogOpen = false;
  bool _zoomInitialized = false;
  bool _moveSelectedFromAnywhere = false;
  bool _continuousEditActive = false;
  bool _isDraft = false;
  int _editRevision = 0;
  String? _loadError;

  static const double _maxPreviewCanvasSide = 2048;
  static const int _maxPreviewImageSide = 1400;

  double get _previewScale => math.min(
        1.0,
        _maxPreviewCanvasSide /
            math.max(widget.project.width, widget.project.height),
      );
  double get _workspaceWidth => math.max(1.0, widget.project.width * _previewScale);
  double get _workspaceHeight => math.max(1.0, widget.project.height * _previewScale);

  int _previewDimension(int value, int other) {
    final factor = math.min(1.0, _maxPreviewImageSide / math.max(value, other));
    return math.max(1, (value * factor).round());
  }

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(String en, String ar) => _isArabic ? ar : en;

  bool get _moveAnywhereActive =>
      _moveSelectedFromAnywhere &&
      _selected != null &&
      _selected! < widget.project.layers.length &&
      !widget.project.layers[_selected!].locked;

  @override
  void initState() {
    super.initState();
    _store = context.read<AppState>().store;
    _isDraft = widget.isDraft;
    _dirty = widget.isDraft;
    _savedProjectSnapshot = _captureProject();
    _loadBase();
  }

  @override
  void dispose() {
    // Project changes stay in memory until the user explicitly chooses Save.
    _zoomController.dispose();
    _canvasRevision.dispose();
    _controlsRevision.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    try {
      // Legacy projects are normalized once; current projects open without
      // decoding full-resolution source images just to inspect their metadata.
      if (widget.project.formatVersion < 2) {
        final source = File(widget.project.originalPath);
        if (!await source.exists()) throw StateError('Original image is missing.');

        final baseExtension = p.extension(source.path).toLowerCase();
        final baseIsJpeg = baseExtension == '.jpg' || baseExtension == '.jpeg';
        final baseTarget = File(p.join(
          source.parent.path,
          baseIsJpeg ? 'original-upright.jpg' : 'original-upright.png',
        ));
        final baseDimensions = await _imageService.normalizeToFile(
          source.path,
          baseTarget.path,
          asJpeg: baseIsJpeg,
          jpegQuality: 96,
        );
        widget.project.originalPath = baseTarget.path;
        widget.project.width = baseDimensions.width;
        widget.project.height = baseDimensions.height;

        for (final layer in widget.project.layers) {
          if (layer.type != LayerType.image || layer.assetPath == null) continue;
          final overlay = File(layer.assetPath!);
          if (!await overlay.exists() ||
              p.extension(overlay.path).toLowerCase() == '.svg') {
            continue;
          }
          final extension = p.extension(overlay.path).toLowerCase();
          final isJpeg = extension == '.jpg' || extension == '.jpeg';
          final normalizedPath = p.join(
            overlay.parent.path,
            '${_uuid.v4()}-upright${isJpeg ? '.jpg' : '.png'}',
          );
          final dimensions = await _imageService.normalizeToFile(
            overlay.path,
            normalizedPath,
            asJpeg: isJpeg,
            jpegQuality: 95,
          );
          layer.assetPath = normalizedPath;
          layer.assetWidth = dimensions.width;
          layer.assetHeight = dimensions.height;
        }

        // Migration metadata is persisted only with explicit user approval.
      } else if (!await File(widget.project.originalPath).exists()) {
        throw StateError('Original image is missing.');
      }

      if (mounted) {
        setState(() {
          _baseLoaded = true;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = error.toString());
        _message('${_t('Could not open image', 'تعذر فتح الصورة')}: $error');
      }
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
      widget.project.layers = snapshot.map(EditorLayer.fromJson).toList();
      _selected = null;
      _moveSelectedFromAnywhere = false;
    });
    _canvasRevision.value++;
    _controlsRevision.value++;
    _markDirty();
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

  void _markDirty() {
    _editRevision++;
    if (!_dirty && mounted) {
      setState(() => _dirty = true);
    }
  }

  Future<bool> _saveNow() async {
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (!mounted) return false;
    }

    final revisionAtStart = _editRevision;
    // Save an immutable snapshot, so edits made while disk I/O is in progress
    // remain visibly unsaved and cannot be accidentally included or cleared.
    final snapshot = EditorProject.fromJson(_captureProject());

    if (mounted) setState(() => _saving = true);
    try {
      await _store.save(snapshot);
      widget.project.updatedAt = snapshot.updatedAt;
      _isDraft = false;
      _savedProjectSnapshot = snapshot.toJson();

      final allChangesSaved = _editRevision == revisionAtStart;
      if (mounted) setState(() => _dirty = !allChangesSaved);
      if (mounted) {
        _message(
          allChangesSaved
              ? _t('Project saved successfully', 'تم حفظ المشروع بنجاح')
              : _t(
                  'Snapshot saved. Newer changes are still unsaved.',
                  'تم حفظ النسخة الحالية، وما زالت هناك تعديلات أحدث غير محفوظة.',
                ),
        );
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
    widget.project.formatVersion = saved.formatVersion;
    widget.project.layers = saved.layers.map((layer) => layer.copy()).toList();
    _undo.clear();
    _redo.clear();
    _canvasRevision.value++;
    _controlsRevision.value++;
    if (mounted) setState(() => _dirty = false);
  }

  Future<void> _confirmLeave() async {
    if (_exitDialogOpen || (!_dirty && !_isDraft) || !mounted) return;
    _exitDialogOpen = true;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Unsaved changes', 'تغييرات غير محفوظة')),
        content: Text(_t(
          _isDraft
              ? 'This is a new draft. Save it to keep it in your projects, or discard it.'
              : 'Your changes have not been saved. Save them before leaving?',
          _isDraft
              ? 'هذا مشروع جديد غير محفوظ. احفظه للاحتفاظ به ضمن مشاريعك أو تجاهله.'
              : 'لديك تعديلات لم تحفظها. هل تريد حفظها قبل الخروج؟',
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
      final saved = await _saveNow();
      if (!saved || !mounted) return;
    } else if (action == 'discard') {
      try {
        if (_isDraft) {
          await _store.delete(widget.project.id);
        } else {
          await _restoreLastSavedProject();
        }
      } catch (error) {
        if (mounted) {
          _message('${_t('Could not discard changes', 'تعذر تجاهل التعديلات')}: $error');
        }
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
    _markDirty();
    _controlsRevision.value++;
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
    _markDirty();
    _controlsRevision.value++;
  }

  Future<void> _addImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'svg'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.single.path == null) return;
    await _addImagePath(result.files.single.path!);
  }

  Future<void> _addImagePath(String sourcePath) async {
    try {
      final source = File(sourcePath);
      final projectAssets = await _store.assetsDirectory(widget.project.id);
      final assetDir = Directory(p.join(projectAssets.path, 'overlays'));
      await assetDir.create(recursive: true);

      final extension = p.extension(source.path).toLowerCase();
      var assetWidth = 0;
      var assetHeight = 0;
      late final File target;
      if (extension == '.svg') {
        target = File(p.join(assetDir.path, '${_uuid.v4()}.svg'));
        await source.copy(target.path);
      } else {
        final keepJpeg = extension == '.jpg' || extension == '.jpeg';
        target = File(p.join(
          assetDir.path,
          '${_uuid.v4()}${keepJpeg ? '.jpg' : '.png'}',
        ));
        final dimensions = await _imageService.normalizeToFile(
          source.path,
          target.path,
          asJpeg: keepJpeg,
          jpegQuality: 95,
        );
        assetWidth = dimensions.width;
        assetHeight = dimensions.height;
      }

      if (!mounted) return;
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
        _moveSelectedFromAnywhere = false;
      });
      _canvasRevision.value++;
      _controlsRevision.value++;
      _markDirty();
    } catch (error) {
      if (mounted) {
        _message('${_t('Could not add image', 'تعذرت إضافة الصورة')}: $error');
      }
    }
  }

  Future<void> _openLogoLibrary() async {
    final library = context.read<AppState>().logoLibrary;
    var logos = await library.listLogos();
    if (!mounted) return;

    final selectedLogo = await showDialog<LogoAsset>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final size = MediaQuery.sizeOf(dialogContext);
          return AlertDialog(
            title: Text(_t('Logo library', 'مكتبة الشعارات')),
            content: SizedBox(
              width: math.min(540.0, size.width - 48),
              height: math.min(460.0, size.height * .62),
              child: logos.isEmpty
                  ? Center(
                      child: Text(
                        _t(
                          'Your saved logos will appear here.',
                          'الشعارات التي تحفظها ستظهر هنا.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : GridView.builder(
                      itemCount: logos.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: .88,
                      ),
                      itemBuilder: (context, index) {
                        final logo = logos[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.pop(dialogContext, logo),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: logo.isSvg
                                        ? SvgPicture.file(
                                            File(logo.path),
                                            fit: BoxFit.contain,
                                          )
                                        : Image.file(
                                            File(logo.path),
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.broken_image_outlined),
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    logo.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ),
                                SizedBox(
                                  height: 34,
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: _t('Delete logo', 'حذف الشعار'),
                                      onPressed: () async {
                                        final confirmed = await showDialog<bool>(
                                          context: dialogContext,
                                          builder: (confirmContext) => AlertDialog(
                                            title: Text(_t('Delete logo?', 'حذف الشعار؟')),
                                            content: Text(_t(
                                              'This removes it from your saved logo library. Existing project layers will remain unchanged.',
                                              'سيُحذف من مكتبة الشعارات فقط، وستظل الطبقات الموجودة في المشاريع كما هي.',
                                            )),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(confirmContext, false),
                                                child: Text(_t('Cancel', 'إلغاء')),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(confirmContext, true),
                                                child: Text(_t('Delete', 'حذف')),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed != true) return;
                                        try {
                                          await library.deleteLogo(logo.id);
                                          setDialogState(() {
                                            logos = logos
                                                .where((item) => item.id != logo.id)
                                                .toList();
                                          });
                                        } catch (error) {
                                          if (mounted) {
                                            _message('${_t('Could not delete logo', 'تعذر حذف الشعار')}: $error');
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_t('Close', 'إغلاق')),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: [
                      'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'svg',
                    ],
                    allowMultiple: false,
                    withData: false,
                  );
                  if (result == null || result.files.single.path == null) return;
                  try {
                    final added = await library.addLogo(result.files.single.path!);
                    setDialogState(() => logos = [...logos, added]);
                  } catch (error) {
                    if (mounted) {
                      _message('${_t('Could not save logo', 'تعذر حفظ الشعار')}: $error');
                    }
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(_t('Add logo', 'إضافة شعار')),
              ),
            ],
          );
        },
      ),
    );

    if (selectedLogo != null && mounted) {
      // Copy the selected library asset into this project. Deleting a logo
      // from the library later must not break projects that already use it.
      await _addImagePath(selectedLogo.path);
    }
  }

  void _selectLayer(int index) {
    setState(() => _selected = index);
  }

  void _updateSelected(void Function(EditorLayer layer) update) {
    if (_selected == null || _selected! >= widget.project.layers.length) {
      return;
    }
    if (!_continuousEditActive) _checkpoint();
    update(widget.project.layers[_selected!]);
    _canvasRevision.value++;
    _controlsRevision.value++;
    _markDirty();
  }

  void _updateAt(int index, void Function(EditorLayer layer) update) {
    if (index < 0 || index >= widget.project.layers.length) return;
    _checkpoint();
    update(widget.project.layers[index]);
    _canvasRevision.value++;
    _controlsRevision.value++;
    _markDirty();
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
    _canvasRevision.value++;
    _controlsRevision.value++;
    _markDirty();
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
            PopupMenuButton<String>(
              tooltip: _t('More editing actions', 'المزيد من أدوات التحرير'),
              onSelected: (value) {
                switch (value) {
                  case 'undo':
                    _undoAction();
                    break;
                  case 'redo':
                    _redoAction();
                    break;
                  case 'rename':
                    _renameProject();
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'undo',
                  enabled: _undo.isNotEmpty,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.undo),
                    title: Text(_t('Undo', 'تراجع')),
                  ),
                ),
                PopupMenuItem(
                  value: 'redo',
                  enabled: _redo.isNotEmpty,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.redo),
                    title: Text(_t('Redo', 'إعادة')),
                  ),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: Text(_t('Rename project', 'إعادة تسمية المشروع')),
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: _t('Save', 'حفظ'),
              onPressed: _saving ? null : _saveNow,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
            IconButton(
              tooltip: _t('Export', 'تصدير'),
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth > 760;
            final canvas = _buildCanvas();
            final tools = ValueListenableBuilder<int>(
              valueListenable: _controlsRevision,
              builder: (context, revision, child) => _buildTools(selected),
            );

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

            final panelHeight = math.min(
              260.0,
              math.max(100.0, constraints.maxHeight * .32),
            );

            return Column(
              children: [
                Expanded(
                  child: ClipRect(child: canvas),
                ),
                SizedBox(
                  height: panelHeight,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 8,
                    child: Column(
                      children: [
                        Container(
                          height: 48,
                          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 10, 0),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _t('Design tools', 'أدوات التصميم'),
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              if (_dirty)
                                Text(
                                  _t('Not saved', 'غير محفوظ'),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(child: tools),
                      ],
                    ),
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
          availableWidth / _workspaceWidth,
          availableHeight / _workspaceHeight,
        ).clamp(0.02, 1.0).toDouble();

        if (!_zoomInitialized && _baseLoaded) {
          _zoomInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final offsetX = (constraints.maxWidth - _workspaceWidth * fitScale) / 2;
            final offsetY = (constraints.maxHeight - _workspaceHeight * fitScale) / 2;
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
              ? Center(
                  child: _loadError == null
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image_outlined, size: 42),
                              const SizedBox(height: 12),
                              Text(
                                _t('The project could not be opened', 'تعذر فتح المشروع'),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() => _loadError = null);
                                  _loadBase();
                                },
                                icon: const Icon(Icons.refresh),
                                label: Text(_t('Try again', 'إعادة المحاولة')),
                              ),
                            ],
                          ),
                        ),
                )
              : InteractiveViewer(
                  transformationController: _zoomController,
                  constrained: false,
                  panEnabled: !_moveAnywhereActive,
                  scaleEnabled: !_moveAnywhereActive,
                  minScale: fitScale * 0.5,
                  maxScale: fitScale * 8,
                  boundaryMargin: EdgeInsets.all(
                    math.max(widget.project.width, widget.project.height).toDouble(),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _workspaceWidth,
                    height: _workspaceHeight,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _canvasRevision,
                      builder: (context, revision, child) => Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          RepaintBoundary(
                            child: Image.file(
                              File(widget.project.originalPath),
                              width: _workspaceWidth,
                              height: _workspaceHeight,
                              cacheWidth: _workspaceWidth.ceil(),
                              cacheHeight: _workspaceHeight.ceil(),
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                          if (_moveAnywhereActive)
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanStart: (_) => _checkpoint(),
                              onPanUpdate: (details) {
                                final layer = widget.project.layers[_selected!];
                                layer.x += details.delta.dx / _workspaceWidth;
                                layer.y += details.delta.dy / _workspaceHeight;
                                _canvasRevision.value++;
                              },
                              onPanEnd: (_) => _markDirty(),
                              child: const SizedBox.expand(),
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
        _workspaceWidth * .30,
        _workspaceHeight * .30 * aspectRatio,
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
    final width = layer.assetWidth > 0 ? layer.assetWidth : 1200;
    final height = layer.assetHeight > 0 ? layer.assetHeight : 1200;
    return Image.file(
      file,
      width: displayWidth,
      cacheWidth: _previewDimension(width, height),
      cacheHeight: _previewDimension(height, width),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
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
        for (var i = 0; i < 8; i++) {
          final angle = (i / 8) * math.pi * 2;
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
      left: layer.x * _workspaceWidth,
      top: layer.y * _workspaceHeight,
      child: RepaintBoundary(
        key: ValueKey(layer.id),
        child: FractionalTranslation(
          translation: const Offset(-.5, -.5),
          child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _selectLayer(index),
          onPanStart: layer.locked
              ? null
              : (_) {
                  _checkpoint();
                },
          onPanUpdate: layer.locked
              ? null
              : (details) {
                  layer.x += details.delta.dx / _workspaceWidth;
                  layer.y += details.delta.dy / _workspaceHeight;
                  _canvasRevision.value++;
                },
          onPanEnd: layer.locked ? null : (_) => _markDirty(),
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
    ),
  );
  }

  TextAlign _textAlign(String alignment) => switch (alignment) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      };

  Widget _buildTools(
    EditorLayer? selected, {
    ScrollController? scrollController,
  }) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 28),
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
              label: Text(_t('Image', 'صورة')),
            ),
            FilledButton.tonalIcon(
              onPressed: _openLogoLibrary,
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: Text(_t('Logo library', 'مكتبة الشعارات')),
            ),
          ],
        ),
        if (selected != null) ...[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _moveAnywhereActive,
            onChanged: selected.locked
                ? null
                : (value) => setState(() => _moveSelectedFromAnywhere = value),
            title: Text(_t(
              'Move selected layer from anywhere',
              'تحريك العنصر المحدد من أي مكان',
            )),
            subtitle: Text(_t(
              'Drag on empty canvas space to move it. Canvas pan and zoom pause while this is enabled.',
              'اسحب من أي مساحة فارغة لتحريكه. يتوقف تحريك وتكبير لوحة العمل مؤقتاً أثناء التفعيل.',
            )),
          ),
        ],
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
                      _canvasRevision.value++;
                      _controlsRevision.value++;
                      _markDirty();
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
                _canvasRevision.value++;
                _markDirty();
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
          onChangeStart: (_) {
            _continuousEditActive = true;
            _checkpoint();
          },
          onChanged: onChanged,
          onChangeEnd: (_) {
            _continuousEditActive = false;
            _markDirty();
          },
        ),
      ],
    );
  }

}
