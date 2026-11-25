import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(isAr ? 'المظهر' : 'Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(child: Column(children: [
          RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: state.themeMode, title: Text(isAr ? 'حسب الجهاز' : 'System'), onChanged: (v) => state.setTheme(v!)),
          RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: state.themeMode, title: Text(isAr ? 'فاتح' : 'Light'), onChanged: (v) => state.setTheme(v!)),
          RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: state.themeMode, title: Text(isAr ? 'داكن' : 'Dark'), onChanged: (v) => state.setTheme(v!)),
        ])),
        const SizedBox(height: 24),
        Text(isAr ? 'اللغة' : 'Language', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(child: Column(children: [
          RadioListTile<String>(value: 'en', groupValue: state.locale, title: const Text('English'), onChanged: (v) => state.setLocale(v!)),
          RadioListTile<String>(value: 'ar', groupValue: state.locale, title: const Text('العربية'), onChanged: (v) => state.setLocale(v!)),
        ])),
        const SizedBox(height: 24),
        const ListTile(leading: Icon(Icons.wifi_off), title: Text('Offline by design'), subtitle: Text('Images and projects remain on this device.')),
        const ListTile(leading: Icon(Icons.info_outline), title: Text('Layer Studio'), subtitle: Text('Version 1.0.0')),
      ],
    );
  }
}
