import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'views/main_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UniPaasConverterApp());
}

class UniPaasConverterApp extends StatelessWidget {
  const UniPaasConverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniPaas to MSSQL Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        primaryColor: const Color(0xFF06B6D4),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF06B6D4),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF111827),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const MainView(),
    );
  }
}
