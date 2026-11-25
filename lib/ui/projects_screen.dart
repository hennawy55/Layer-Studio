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
  late Future<List<EditorProject>> future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future = context.read<AppState>().projects();
  }

  Future<void> _refresh() async {
    setState(() => future = context.read<AppState>().projects());
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return FutureBuilder<List<EditorProject>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final projects = snapshot.data ?? [];
        if (projects.isEmpty) return Center(child: Text(isAr ? 'لا توجد مشاريع محفوظة بعد' : 'No saved projects yet'));
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(18),
            itemCount: projects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final project = projects[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.image_outlined)),
                  title: Text(project.name),
                  subtitle: Text('${project.width} × ${project.height} • ${project.updatedAt.toLocal()}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'delete') {
                        await context.read<AppState>().store.delete(project.id);
                        await _refresh();
                      }
                    },
                    itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(isAr ? 'حذف' : 'Delete'))],
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(project: project))).then((_) => _refresh()),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
