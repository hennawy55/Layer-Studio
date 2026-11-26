import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../services/image_import_picker.dart';
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
  final _imagePicker = ImageImportPicker();

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(String en, String ar) => _isArabic ? ar : en;

  Future<void> _newProject() async {
    if (_creating) return;
    try {
      final path = await _imagePicker.pickImage();
      if (!mounted || path == null) return;

      setState(() => _creating = true);
      final project = await context.read<AppState>().store.createDraft(path);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorScreen(project: project, isDraft: true),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeDashboard(
        creating: _creating,
        onNew: _newProject,
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
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/branding/layer_studio_icon.png',
                  width: 40,
                  height: 40,
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

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    required this.creating,
    required this.onNew,
  });

  final bool creating;
  final VoidCallback onNew;

  bool _isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar';

  String _t(BuildContext context, String en, String ar) =>
      _isArabic(context) ? ar : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(
                constraints.maxWidth < 500 ? 22 : 36,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF151C49),
                    Color(0xFF34217A),
                    Color(0xFF5C37BC),
                    Color(0xFF157C98),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6E48D8).withValues(alpha: .20),
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    end: -46,
                    top: -56,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .055),
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
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .16),
                              ),
                            ),
                            child: Text(
                              _t(context, 'LAYER STUDIO', 'Layer Studio'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF83F2FF),
                            size: 28,
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      Text(
                        _t(
                          context,
                          'Every layer tells\na better story.',
                          'كل طبقة تصنع\nتصميماً أفضل.',
                        ),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Text(
                          _t(
                            context,
                            'Create polished designs from your photos, text and saved logos in one focused workspace.',
                            'أنشئ تصميمات متقنة من صورك ونصوصك وشعاراتك المحفوظة داخل مساحة عمل بسيطة.',
                          ),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: .84),
                            height: 1.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      FilledButton.icon(
                        onPressed: creating ? null : onNew,
                        icon: creating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF322075),
                                ),
                              )
                            : const Icon(Icons.add_photo_alternate_rounded),
                        label: Text(
                          creating
                              ? _t(context, 'Preparing image…', 'جارٍ تجهيز الصورة…')
                              : _t(context, 'Create a design', 'إنشاء تصميم'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF352078),
                          minimumSize: const Size(0, 54),
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _t(
                          context,
                          'Your saved projects and logo library are available from the navigation bar.',
                          'مشاريعك المحفوظة ومكتبة الشعارات متاحتان من شريط التنقل بالأسفل.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: .72),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
