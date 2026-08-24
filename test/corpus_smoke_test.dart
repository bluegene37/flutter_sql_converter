// Parses and generates SQL for every program in source/, reporting failures
// and coverage. Skips silently when the source export is not present.
//
//   flutter test test/corpus_smoke_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';
import 'package:flutter_sql_converter/services/sql_generator_service.dart';
import 'package:flutter_sql_converter/services/xml_parser_service.dart';

void main() {
  test('every program parses and generates SQL', () async {
    final dir = Directory('source');
    if (!dir.existsSync()) {
      // ignore: avoid_print
      print('No source/ directory; skipping corpus smoke test.');
      return;
    }

    final schema = SchemaService();
    await schema.loadDataSourcesXml('source/DataSources.xml');
    final comps = File('source/Comps.xml');
    if (comps.existsSync()) schema.loadComponentsXml(comps.readAsStringSync());

    final parser = XmlParserService(schema);
    final mainProgram = File('source/Prg_1.xml');
    if (mainProgram.existsSync()) {
      parser.parseMainProgramGlobals(mainProgram.readAsStringSync());
    }

    final generator = SqlGeneratorService();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'Prg_\d+\.xml$').hasMatch(f.path))
        .toList();

    var parsed = 0;
    var tasks = 0;
    var tasksWithSource = 0;
    var tasksWithWhere = 0;
    var joinsTotal = 0;
    var joinsWithoutConditions = 0;
    var unresolvedColumns = 0;
    var unresolvedTables = 0;
    final unresolvedByTable = <String, int>{};
    final failures = <String>[];

    for (final file in files) {
      try {
        final program = parser.parseProgramString(file.readAsStringSync(), file.path);
        if (program == null) {
          failures.add('${file.path}: parser returned null');
          continue;
        }
        parsed++;

        for (final task in program.allTasksFlattened) {
          tasks++;
          if (task.hasDataSource) tasksWithSource++;
          if (task.whereConditions.isNotEmpty || task.sqlWhereClause.isNotEmpty) {
            tasksWithWhere++;
          }
          for (final join in task.joins) {
            joinsTotal++;
            if (join.conditions.isEmpty) joinsWithoutConditions++;
            if (join.targetTableName.startsWith('Table_')) unresolvedTables++;
          }
          for (final col in task.columns) {
            if (col.colName.startsWith('Col_')) {
              unresolvedColumns++;
              unresolvedByTable[col.tableRealName] =
                  (unresolvedByTable[col.tableRealName] ?? 0) + 1;
            }
          }
        }

        final sql = generator.generateSql(
          program: program,
          parameters: program.extractedParameters,
        );
        if (sql.isEmpty) failures.add('${file.path}: empty SQL');
      } catch (e) {
        failures.add('${file.path}: $e');
      }
    }

    // ignore: avoid_print
    print('''
Programs parsed     : $parsed / ${files.length}
Tasks               : $tasks  (with a data source: $tasksWithSource)
Tasks with a WHERE  : $tasksWithWhere
Joins               : $joinsTotal  (no ON conditions: $joinsWithoutConditions)
Unresolved tables   : $unresolvedTables
Unresolved columns  : $unresolvedColumns
Failures            : ${failures.length}''');

    final worst = unresolvedByTable.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in worst.take(10)) {
      // ignore: avoid_print
      print('  unresolved columns in ${e.key}: ${e.value}');
    }

    for (final f in failures.take(20)) {
      // ignore: avoid_print
      print('  $f');
    }

    expect(failures, isEmpty);
    expect(parsed, equals(files.length));
  }, timeout: const Timeout(Duration(minutes: 15)));
}
