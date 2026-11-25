import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'editor_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  Future<void> _newProject() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowedExtensions: null,
      withData: false,
    );
    if (!mounted || result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    if (!mounted) return;
    final state = context.read<AppState>();
    final project = await state.store.create(path);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(project: project),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final pages = [
      _Dashboard(onNew: _newProject, onProjects: () => setState(() => tab = 1)),
      const ProjectsScreen(),
      const SettingsScreen(),
    ];
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Layer Studio', style: TextStyle(fontWeight: FontWeight.w800)),
          centerTitle: false,
        ),
        body: pages[tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: isAr ? 'الرئيسية' : 'Home'),
            NavigationDestination(icon: const Icon(Icons.folder_open_outlined), label: isAr ? 'المشاريع' : 'Projects'),
            NavigationDestination(icon: const Icon(Icons.settings_outlined), label: isAr ? 'الإعدادات' : 'Settings'),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.onNew, required this.onProjects});
  final VoidCallback onNew;
  final VoidCallback onProjects;

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFF675CE0), Color(0xFF9B75DC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.layers_rounded, color: Colors.white, size: 42),
                  const SizedBox(height: 20),
                  Text(isAr ? 'اصنع تصميمك بطريقتك' : 'Create your next composition',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(isAr ? 'أضف النصوص والشعارات إلى صورك بسهولة، دون اتصال بالإنترنت.' : 'Add text and logos to your images, completely offline.',
                    style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onNew,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(isAr ? 'مشروع جديد' : 'Create new project'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF5549C8)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: Text(isAr ? 'مساحة عملك' : 'Your workspace', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              TextButton(onPressed: onProjects, child: Text(isAr ? 'كل المشاريع' : 'All projects')),
            ]),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  const CircleAvatar(child: Icon(Icons.folder_copy_outlined)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(isAr ? 'مشاريعك محفوظة على هذا الجهاز' : 'Your projects stay on this device')),
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
