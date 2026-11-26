import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/editor_project.dart';
import '../services/project_store.dart';
import '../services/logo_library_store.dart';

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;
  late ProjectStore store;
  late LogoLibraryStore logoLibrary;
  ThemeMode themeMode = ThemeMode.system;
  String locale = 'en';

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    store = ProjectStore();
    await store.initialize();
    logoLibrary = LogoLibraryStore();
    await logoLibrary.initialize();
    locale = _prefs.getString('locale') ?? 'en';
    themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == (_prefs.getString('theme') ?? 'system'),
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setLocale(String value) async {
    locale = value;
    await _prefs.setString('locale', value);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) async {
    themeMode = value;
    await _prefs.setString('theme', value.name);
    notifyListeners();
  }

  Future<Directory> projectsDirectory() => getApplicationSupportDirectory();

  Future<List<EditorProject>> projects() => store.listProjects();
}
