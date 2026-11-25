import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.initialize();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const LayerStudioApp(),
    ),
  );
}

class LayerStudioApp extends StatelessWidget {
  const LayerStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'Layer Studio',
      debugShowCheckedModeBanner: false,
      locale: Locale(state.locale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: state.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6258D8)),
        scaffoldBackgroundColor: const Color(0xFFF6F6FA),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9A91FF),
          brightness: Brightness.dark,
        ),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      home: const HomeScreen(),
    );
  }
}
