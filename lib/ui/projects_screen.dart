import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/editor_project.dart';
import '../state/app_state.dart';
import 'editor_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  Future<List<EditorProject>>? _future;

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(String en, String ar) => _isArabic ? ar : en;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= context.read<AppState>().projects();
  }

  Future<void> _refresh() async {
    final next = context.read<AppState>().projects();
    setState(() => _future = next);
    await next;
  }

  Future<void> _open(EditorProject project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(project: project)),
    );
    if (mounted) await _refresh();
  }

  Future<void> _delete(EditorProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Delete project?', 'حذف المشروع؟')),
        content: Text(_t(
          'The project and its copied assets will be removed from this device.',
          'سيتم حذف المشروع والملفات التابعة له من هذا الجهاز.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<AppState>().store.delete(project.id);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('Could not delete project', 'تعذر حذف المشروع')}: $error'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<EditorProject>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 10),
                Text(_t('Could not load projects', 'تعذر تحميل المشاريع')),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(_t('Try again', 'إعادة المحاولة')),
                ),
              ],
            ),
          );
        }

        final projects = snapshot.data ?? const <EditorProject>[];
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
                          _t('Your projects', 'مشاريعك'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _t(
                            '${projects.length} projects saved on this device',
                            '${projects.length} مشروع محفوظ على هذا الجهاز',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    tooltip: _t('Refresh', 'تحديث'),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(
              child: projects.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.folder_open_outlined,
                                size: 38,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _t('No saved projects', 'لا توجد مشاريع محفوظة'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _t(
                                'Start a design from the Home tab. Your work will appear here.',
                                'ابدأ تصميماً من تبويب الرئيسية وستجد مشاريعك هنا.',
                              ),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 920
                            ? 3
                            : constraints.maxWidth >= 560
                                ? 2
                                : 1;
                        return RefreshIndicator(
                          onRefresh: _refresh,
                          child: GridView.builder(
                            padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 18, 26),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: columns == 1 ? 2.15 : 1.18,
                            ),
                            itemCount: projects.length,
                            itemBuilder: (context, index) {
                              final project = projects[index];
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _open(project),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: columns == 1 ? 132 : double.infinity,
                                        child: columns == 1
                                            ? _ProjectThumbnail(project: project)
                                            : null,
                                      ),
                                      if (columns != 1)
                                        Expanded(
                                          child: _ProjectThumbnail(project: project),
                                        ),
                                      Expanded(
                                        flex: columns == 1 ? 3 : 2,
                                        child: Padding(
                                          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 4, 12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                project.name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${project.width} × ${project.height}',
                                                style: theme.textTheme.labelSmall?.copyWith(
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                project.updatedAt.toLocal().toString().split('.').first,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.labelSmall?.copyWith(
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: _t('Project options', 'خيارات المشروع'),
                                        onSelected: (value) {
                                          if (value == 'delete') _delete(project);
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(_t('Delete', 'حذف')),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
}

class _ProjectThumbnail extends StatelessWidget {
  const _ProjectThumbnail({required this.project});

  final EditorProject project;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Image.file(
        File(project.originalPath),
        fit: BoxFit.cover,
        cacheWidth: 520,
        cacheHeight: 360,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}
