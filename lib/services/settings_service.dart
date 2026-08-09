import 'dart:convert';
import 'dart:io';

class SettingsService {
  static String get configFilePath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return '$home/.flutter_sql_converter_settings.json';
  }

  static Future<void> saveSourceDirectory(String path) async {
    if (path.trim().isEmpty) return;
    try {
      final file = File(configFilePath);
      final data = <String, dynamic>{
        'source_directory': path.trim(),
        'last_updated': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(json.encode(data), flush: true);
    } catch (e) {
      // ignore: avoid_print
      print('Error saving settings to $configFilePath: $e');
    }
  }

  static Future<String?> loadSourceDirectory() async {
    try {
      final file = File(configFilePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = json.decode(content) as Map<String, dynamic>;
          final dir = data['source_directory']?.toString().trim();
          if (dir != null && dir.isNotEmpty) {
            return dir;
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error loading settings from $configFilePath: $e');
    }
    return null;
  }
}
