// Harness for eyeballing generated SQL against the real uniPaaS application.
//
//   flutter test test/generate_samples.dart
//
// Writes one .sql file per program into build/sql_samples/ and prints them.
// Pass program ids on the command line via SAMPLE_PROGRAMS, e.g.
//   SAMPLE_PROGRAMS=1003,9408 flutter test test/generate_samples.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';
import 'package:flutter_sql_converter/services/sql_generator_service.dart';
import 'package:flutter_sql_converter/services/xml_parser_service.dart';

const _defaultPrograms = ['9408', '1054', '1022', '1003'];

void main() {
  test('generate SQL samples', () async {
    final sourceDir = Directory('source');
    if (!sourceDir.existsSync()) {
      // ignore: avoid_print
      print('No source/ directory; skipping.');
      return;
    }

    final schema = SchemaService();
    final started = DateTime.now();
    await schema.loadDataSourcesXml('source/DataSources.xml');
    final comps = File('source/Comps.xml');
    if (comps.existsSync()) schema.loadComponentsXml(comps.readAsStringSync());
    // ignore: avoid_print
    print('Loaded ${schema.tables.length} data objects in '
        '${DateTime.now().difference(started).inMilliseconds}ms');

    final parser = XmlParserService(schema);
    parser.parseMainProgramGlobals(File('source/Prg_1.xml').readAsStringSync());
    // ignore: avoid_print
    print('Main Program globals: ${parser.mainProgramGlobals.length}');

    final generator = SqlGeneratorService();
    final outDir = Directory('build/sql_samples')..createSync(recursive: true);

    final ids = (Platform.environment['SAMPLE_PROGRAMS'] ?? '').isEmpty
        ? _defaultPrograms
        : Platform.environment['SAMPLE_PROGRAMS']!.split(',');

    for (final id in ids) {
      final path = 'source/Prg_${id.trim()}.xml';
      final file = File(path);
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('!! missing $path');
        continue;
      }

      final program = parser.parseProgramString(file.readAsStringSync(), path);
      if (program == null) {
        // ignore: avoid_print
        print('!! failed to parse $path');
        continue;
      }

      final sql = generator.generateSql(
        program: program,
        parameters: program.extractedParameters,
      );
      File('${outDir.path}/Prg_$id.sql').writeAsStringSync(sql);

      // ignore: avoid_print
      print('\n${'=' * 78}\n$path  ->  ${program.name}\n${'=' * 78}\n$sql');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
