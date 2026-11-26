import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../models/logo_asset.dart';
import '../state/app_state.dart';

class LogoLibraryScreen extends StatefulWidget {
  const LogoLibraryScreen({super.key});

  @override
  State<LogoLibraryScreen> createState() => _LogoLibraryScreenState();
}

class _LogoLibraryScreenState extends State<LogoLibraryScreen> {
  Future<List<LogoAsset>>? _logos;
  bool _adding = false;

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(String en, String ar) => _isArabic ? ar : en;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _logos ??= context.read<AppState>().logoLibrary.listLogos();
  }

  Future<void> _reload() async {
    final future = context.read<AppState>().logoLibrary.listLogos();
    setState(() => _logos = future);
    await future;
  }

  Future<void> _addLogo() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'svg',
        ],
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result == null || result.files.single.path == null) return;

      await context.read<AppState>().logoLibrary.addLogo(
            result.files.single.path!,
          );
      if (!mounted) return;
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('Logo saved to your library', 'تم حفظ الشعار في المكتبة'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('Could not save logo', 'تعذر حفظ الشعار')}: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deleteLogo(LogoAsset logo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Remove logo?', 'حذف الشعار؟')),
        content: Text(_t(
          'This removes the saved copy from your library. Projects that already use it will not be changed.',
          'سيتم حذف النسخة المحفوظة من المكتبة فقط، ولن تتأثر المشاريع التي تستخدم الشعار بالفعل.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('Remove', 'حذف')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<AppState>().logoLibrary.deleteLogo(logo.id);
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t('Could not remove logo', 'تعذر حذف الشعار')}: $error')),
        );
      }
    }
  }

  Widget _logoPreview(LogoAsset logo) {
    if (logo.isSvg) {
      return SvgPicture.file(
        File(logo.path),
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Image.file(
      File(logo.path),
      fit: BoxFit.contain,
      cacheWidth: 420,
      cacheHeight: 420,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 34),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<LogoAsset>>(
      future: _logos,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final logos = snapshot.data ?? const <LogoAsset>[];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('Your saved logos', 'شعاراتك المحفوظة'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          logos.isEmpty
                              ? _t('Add logos once and reuse them in any project.', 'أضف الشعارات مرة واحدة واستخدمها في أي مشروع.')
                              : _t('${logos.length} saved logos • available offline', '${logos.length} شعار محفوظ • متاح دون إنترنت'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _adding ? null : _addLogo,
                    icon: _adding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(_t('Add', 'إضافة')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: logos.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.bookmarks_outlined,
                                  size: 38,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _t('Your logo library is empty', 'مكتبة الشعارات فارغة'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _t(
                                  'Save the logos you use often. They will be ready to add to any design without searching through your photos again.',
                                  'احفظ الشعارات التي تستخدمها باستمرار، وستجدها جاهزة للإضافة إلى أي تصميم دون البحث عنها وسط الصور كل مرة.',
                                ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                onPressed: _adding ? null : _addLogo,
                                icon: const Icon(Icons.add_photo_alternate_outlined),
                                label: Text(_t('Save your first logo', 'احفظ أول شعار')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 900
                            ? 5
                            : constraints.maxWidth >= 580
                                ? 4
                                : 2;
                        return RefreshIndicator(
                          onRefresh: _reload,
                          child: GridView.builder(
                            padding: const EdgeInsetsDirectional.fromSTEB(18, 10, 18, 24),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: .94,
                            ),
                            itemCount: logos.length,
                            itemBuilder: (context, index) {
                              final logo = logos[index];
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => _showLogoDetails(logo),
                                        child: Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.all(10),
                                          child: _logoPreview(logo),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 4, 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              logo.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelLarge?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: _t('More', 'المزيد'),
                                            onSelected: (value) {
                                              if (value == 'delete') _deleteLogo(logo);
                                            },
                                            itemBuilder: (_) => [
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text(_t('Remove from library', 'حذف من المكتبة')),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLogoDetails(LogoAsset logo) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(logo.name),
        content: SizedBox(
          width: 300,
          height: 220,
          child: _logoPreview(logo),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('Close', 'إغلاق')),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteLogo(logo);
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(_t('Remove', 'حذف')),
          ),
        ],
      ),
    );
  }
}
