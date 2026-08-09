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
  final Set<String> _loadedDataSourcesPaths = {};

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

  Future<void> loadDataSourcesXmlFromDir(String dirPath) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final candidates = [
      '$dirPath/DataSources.xml',
      '$dirPath/source/DataSources.xml',
      '${Directory(dirPath).parent.path}/DataSources.xml',
      '${Directory(dirPath).parent.path}/source/DataSources.xml',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        await loadDataSourcesXml(file.path);
        break;
      }
    }
  }

  Future<void> loadDataSourcesXml(String xmlFilePath) async {
    if (_loadedDataSourcesPaths.contains(xmlFilePath)) return;
    final file = File(xmlFilePath);
    if (!await file.exists()) return;
    _loadedDataSourcesPaths.add(xmlFilePath);

    try {
      final xml = await file.readAsString();
      int pos = 0;

      while (pos < xml.length) {
        final dataObjIdx = xml.indexOf('<DataObject', pos);
        if (dataObjIdx == -1) break;

        final nextObjIdx = xml.indexOf('<DataObject', dataObjIdx + 11);
        final endIdx = (nextObjIdx != -1) ? nextObjIdx : xml.length;

        final idStart = xml.indexOf('id="', dataObjIdx);
        if (idStart != -1 && idStart < endIdx) {
          final idValStart = idStart + 4;
          final idValEnd = xml.indexOf('"', idValStart);
          if (idValEnd != -1 && idValEnd < endIdx) {
            final tId = xml.substring(idValStart, idValEnd);

            final nameStart = xml.indexOf('name="', dataObjIdx);
            String tName = '';
            if (nameStart != -1 && nameStart < endIdx) {
              final nameValStart = nameStart + 6;
              final nameValEnd = xml.indexOf('"', nameValStart);
              if (nameValEnd != -1 && nameValEnd < endIdx) {
                tName = xml.substring(nameValStart, nameValEnd);
              }
            }
            if (tName.isNotEmpty) {
              _tableIdMap[tId] = tName;
            }

            int colPos = dataObjIdx;
            int colIdx = 1;
            while (colPos < endIdx) {
              final colStart = xml.indexOf('<Column ', colPos);
              if (colStart == -1 || colStart >= endIdx) break;

              final cIdStart = xml.indexOf('id="', colStart);
              if (cIdStart == -1 || cIdStart >= endIdx) break;
              final cIdValStart = cIdStart + 4;
              final cIdValEnd = xml.indexOf('"', cIdValStart);
              if (cIdValEnd == -1 || cIdValEnd >= endIdx) break;
              final cId = xml.substring(cIdValStart, cIdValEnd);

              final cNameStart = xml.indexOf('name="', colStart);
              String rawName = '';
              if (cNameStart != -1 && cNameStart < endIdx) {
                final cNameValStart = cNameStart + 6;
                final cNameValEnd = xml.indexOf('"', cNameValStart);
                if (cNameValEnd != -1 && cNameValEnd < endIdx) {
                  rawName = xml.substring(cNameValStart, cNameValEnd);
                }
              }

              final nextColStart = xml.indexOf('<Column ', colStart + 8);
              final colBound = (nextColStart != -1 && nextColStart < endIdx) ? nextColStart : endIdx;

              String dbCol = '';
              final dbColStart = xml.indexOf('<DbColumnName', colStart);
              if (dbColStart != -1 && dbColStart < colBound) {
                final dbValStart = xml.indexOf('val="', dbColStart);
                if (dbValStart != -1 && dbValStart < colBound) {
                  final dbValEnd = xml.indexOf('"', dbValStart + 5);
                  if (dbValEnd != -1 && dbValEnd < colBound) {
                    dbCol = xml.substring(dbValStart + 5, dbValEnd).trim();
                  }
                }
              }

              final cName = dbCol.isNotEmpty ? dbCol : rawName;
              if (cName.isNotEmpty) {
                _colIdMap['$tId.$cId'] = cName;
                _colAliasMap['$tId.$cId'] = rawName.isNotEmpty ? rawName : cName;

                _colIdMap['$tId.$colIdx'] = cName;
                _colAliasMap['$tId.$colIdx'] = rawName.isNotEmpty ? rawName : cName;
              }

              colIdx++;
              colPos = (nextColStart != -1 && nextColStart < endIdx) ? nextColStart : endIdx;
            }
          }
        }

        pos = endIdx;
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing DataSources.xml: $e');
    }
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
