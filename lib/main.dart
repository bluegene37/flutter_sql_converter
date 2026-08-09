import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'views/main_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UniPaasConverterApp());
}

class UniPaasConverterApp extends StatefulWidget {
  const UniPaasConverterApp({super.key});

  @override
  State<UniPaasConverterApp> createState() => _UniPaasConverterAppState();
}

class _UniPaasConverterAppState extends State<UniPaasConverterApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SQL Generator',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        primaryColor: const Color(0xFF0891B2),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0891B2),
          secondary: Color(0xFF2563EB),
          surface: Color(0xFFFFFFFF),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF0F172A),
          contentTextStyle: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          behavior: SnackBarBehavior.floating,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        primaryColor: const Color(0xFF06B6D4),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF06B6D4),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF111827),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E293B),
          contentTextStyle: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          behavior: SnackBarBehavior.floating,
        ),
        useMaterial3: true,
      ),
      home: MainView(onToggleTheme: _toggleTheme),
    );
  }
}
