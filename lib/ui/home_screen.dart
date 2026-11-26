import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../models/editor_project.dart';
import '../state/app_state.dart';
import 'editor_screen.dart';
import 'logo_library_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _creating = false;
  Future<List<EditorProject>>? _projectsFuture;

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(String en, String ar) => _isArabic ? ar : en;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _projectsFuture ??= context.read<AppState>().projects();
  }

  Future<void> _refreshProjects() async {
    final next = context.read<AppState>().projects();
    setState(() => _projectsFuture = next);
    await next;
  }

  Future<void> _newProject() async {
    if (_creating) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result == null || result.files.single.path == null) return;

      setState(() => _creating = true);
      final project = await context.read<AppState>().store.createDraft(
            result.files.single.path!,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditorScreen(project: project, isDraft: true)),
      );
      if (!mounted) return;
      await _refreshProjects();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_t('Could not create project', 'تعذر إنشاء المشروع')}: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openProject(EditorProject project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(project: project)),
    );
    if (mounted) await _refreshProjects();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Dashboard(
        projects: _projectsFuture ?? Future.value(const <EditorProject>[]),
        creating: _creating,
        onNew: _newProject,
        onOpen: _openProject,
        onProjects: () => setState(() => _tab = 1),
        onLogos: () => setState(() => _tab = 2),
      ),
      const ProjectsScreen(),
      const LogoLibraryScreen(),
      const SettingsScreen(),
    ];

    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          titleSpacing: 18,
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SvgPicture.asset(
                  'assets/branding/app_icon.svg',
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              const Text('Layer Studio'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _t('Settings', 'الإعدادات'),
              onPressed: () => setState(() => _tab = 3),
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: IndexedStack(index: _tab, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: _t('Home', 'الرئيسية'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder_rounded),
              label: _t('Projects', 'المشاريع'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.bookmarks_outlined),
              selectedIcon: const Icon(Icons.bookmarks_rounded),
              label: _t('Logos', 'الشعارات'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_rounded),
              selectedIcon: const Icon(Icons.tune_rounded),
              label: _t('Settings', 'الإعدادات'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.projects,
    required this.creating,
    required this.onNew,
    required this.onOpen,
    required this.onProjects,
    required this.onLogos,
  });

  final Future<List<EditorProject>> projects;
  final bool creating;
  final VoidCallback onNew;
  final ValueChanged<EditorProject> onOpen;
  final VoidCallback onProjects;
  final VoidCallback onLogos;

  bool _isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(BuildContext context, String en, String ar) =>
      _isArabic(context) ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF352078),
                    Color(0xFF6E48D8),
                    Color(0xFF9870E8),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6E48D8).withValues(alpha: .18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    end: -30,
                    top: -54,
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .07),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 40,
                    bottom: -90,
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .06),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              _t(context, 'CREATIVE WORKSPACE', 'مساحة تصميمك'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                letterSpacing: .7,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFFFFE4A3),
                            size: 27,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _t(
                          context,
                          'Your next design\nstarts here.',
                          'تصميمك الجديد\nيبدأ من هنا.',
                        ),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              height: 1.12,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _t(
                          context,
                          'Combine photos, text and reusable logos in one simple workspace.',
                          'اجمع الصور والنصوص والشعارات المحفوظة في مساحة عمل واحدة سهلة.',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: .82),
                              height: 1.5,
                            ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: creating ? null : onNew,
                        icon: creating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF3A267E),
                                ),
                              )
                            : const Icon(Icons.add_photo_alternate_rounded),
                        label: Text(
                          creating
                              ? _t(context, 'Preparing…', 'جارٍ التجهيز…')
                              : _t(context, 'Start a new design', 'ابدأ تصميم جديد'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF432A99),
                          minimumSize: const Size(0, 50),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              _t(context, 'Quick access', 'وصول سريع'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 620;
                final width = wide
                    ? (constraints.maxWidth - 24) / 3
                    : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: _QuickAccessCard(
                        icon: Icons.folder_copy_outlined,
                        title: _t(context, 'My projects', 'مشاريعي'),
                        description: _t(context, 'Continue where you left off', 'تابع تصميماتك السابقة'),
                        onTap: onProjects,
                        tint: const Color(0xFF7657E8),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _QuickAccessCard(
                        icon: Icons.bookmarks_outlined,
                        title: _t(context, 'Logo library', 'مكتبة الشعارات'),
                        description: _t(context, 'Keep your logos ready', 'شعاراتك محفوظة وجاهزة'),
                        onTap: onLogos,
                        tint: const Color(0xFF168D9B),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _QuickAccessCard(
                        icon: Icons.wifi_off_rounded,
                        title: _t(context, 'Works offline', 'يعمل دون إنترنت'),
                        description: _t(context, 'Your files stay on this device', 'ملفاتك محفوظة على جهازك'),
                        onTap: onProjects,
                        tint: const Color(0xFFBD7B32),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t(context, 'Recent projects', 'أحدث المشاريع'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: onProjects,
                  child: Text(_t(context, 'View all', 'عرض الكل')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<EditorProject>>(
              future: projects,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final recent = (snapshot.data ?? []).take(4).toList();
                if (recent.isEmpty) {
                  return _EmptyRecentProjects(
                    title: _t(context, 'No designs yet', 'لا توجد تصميمات بعد'),
                    subtitle: _t(
                      context,
                      'Choose an image to create your first project.',
                      'اختر صورة وابدأ أول مشروع لك.',
                    ),
                    action: _t(context, 'Create project', 'إنشاء مشروع'),
                    onPressed: onNew,
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth > 620
                        ? (constraints.maxWidth - 24) / 3
                        : 220.0;
                    return SizedBox(
                      height: 226,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: recent.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) => SizedBox(
                          width: cardWidth,
                          child: _RecentProjectCard(
                            project: recent[index],
                            onTap: () => onOpen(recent[index]),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentProjectCard extends StatelessWidget {
  const _RecentProjectCard({
    required this.project,
    required this.onTap,
  });

  final EditorProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: Image.file(
                  File(project.originalPath),
                  fit: BoxFit.cover,
                  cacheWidth: 440,
                  cacheHeight: 260,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined, size: 34),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${project.width} × ${project.height}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecentProjects extends StatelessWidget {
  const _EmptyRecentProjects({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 38,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.add),
              label: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}
