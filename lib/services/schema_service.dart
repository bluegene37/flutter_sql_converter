import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/unipaas_models.dart';

class SchemaService {
  final Map<String, String> _tableIdMap = {};
  final Map<String, String> _colIdMap = {};
  final Map<String, String> _colAliasMap = {};
  List<ProgramMetadata> _programs = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  List<ProgramMetadata> get programs => _programs;

  Future<void> loadSchema([String? customJsonPath]) async {
    String jsonString;
    if (customJsonPath != null && File(customJsonPath).existsSync()) {
      jsonString = await File(customJsonPath).readAsString();
    } else {
      jsonString = await rootBundle.loadString('assets/schema_data.json');
    }

    final data = json.decode(jsonString) as Map<String, dynamic>;

    _tableIdMap.clear();
    _colIdMap.clear();
    _colAliasMap.clear();

    final tables = data['tables'] as List<dynamic>? ?? [];
    for (final t in tables) {
      final tObj = t['id']?.toString() ?? '';
      final tName = t['name']?.toString() ?? '';
      _tableIdMap[tObj] = tName;

      final cols = t['columns'] as List<dynamic>? ?? [];
      for (final c in cols) {
        final cId = c['id']?.toString() ?? '';
        final rawName = c['name']?.toString() ?? '';
        final dbCol = c['dbColumnName']?.toString().trim() ?? '';
        final cName = dbCol.isNotEmpty ? dbCol : rawName;
        _colIdMap['$tObj.$cId'] = cName;
        _colAliasMap['$tObj.$cId'] = rawName.isNotEmpty ? rawName : cName;
      }
    }

    final progs = data['programs'] as List<dynamic>? ?? [];
    _programs = progs.map((x) => ProgramMetadata.fromJson(x)).toList();

    _isLoaded = true;
  }

  String getTableName(String tableObj) {
    if (tableObj.isEmpty) return '';
    return _tableIdMap[tableObj] ?? 'Table_$tableObj';
  }

  String getColumnName(String tableObj, String colId) {
    if (tableObj.isEmpty || colId.isEmpty) return 'UnknownColumn';
    return _colIdMap['$tableObj.$colId'] ?? 'Col_$colId';
  }

  String getColumnAlias(String tableObj, String colId, {required String fallback}) {
    if (tableObj.isEmpty || colId.isEmpty) return fallback;
    return _colAliasMap['$tableObj.$colId'] ?? fallback;
  }

  ProgramMetadata? findProgramByIdOrFilename(String query) {
    for (final p in _programs) {
      if (p.id == query || p.filename == query || p.name == query) {
        return p;
      }
    }
    return null;
  }
}
