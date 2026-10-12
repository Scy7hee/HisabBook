import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/navigation/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HisabBookApp());
}

class HisabBookApp extends StatefulWidget {
  const HisabBookApp({super.key});

  @override
  State<HisabBookApp> createState() => _HisabBookAppState();
}

class _HisabBookAppState extends State<HisabBookApp> {
  static const String _themePreferenceKey = 'isDarkTheme';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    try {
      final savedIsDark = await _preferences.getBool(_themePreferenceKey);

      if (!mounted || savedIsDark == null) return;

      setState(() {
        _themeMode = savedIsDark ? ThemeMode.dark : ThemeMode.light;
      });
    } catch (error) {
      debugPrint('Could not load theme preference: $error');
    }
  }

  Future<void> _toggleTheme() async {
    final nextMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;

    // Update the UI immediately.
    setState(() {
      _themeMode = nextMode;
    });

    // Persist the selection for the next app launch.
    try {
      await _preferences.setBool(
        _themePreferenceKey,
        nextMode == ThemeMode.dark,
      );
    } catch (error) {
      debugPrint('Could not save theme preference: $error');
    }
  }

  ThemeData _buildDarkTheme() {
    const navy = Color(0xFF101827);
    const panel = Color(0xFF192436);
    const emerald = Color(0xFF39D6A0);
    const muted = Color(0xFF9BAAC0);
    const border = Color(0xFF29364B);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: navy,
      colorScheme: const ColorScheme.dark(
        primary: emerald,
        onPrimary: navy,
        secondary: Color(0xFF7C9CFF),
        surface: panel,
        onSurface: Colors.white,
        error: Color(0xFFFF8793),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111C2C),
        labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: emerald, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    const background = Color(0xFFF5F7F6);
    const green = Color(0xFF167D65);
    const text = Color(0xFF17232F);
    const muted = Color(0xFF64748B);
    const border = Color(0xFFD9E2E0);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: green,
        onPrimary: Colors.white,
        secondary: Color(0xFF207C89),
        surface: Colors.white,
        onSurface: text,
        error: Color(0xFFC63F50),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: green, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HisabBook',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: _themeMode,
      home: AppShell(onToggleTheme: _toggleTheme),
    );
  }
}
