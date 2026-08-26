// Sweeps the whole source export and reports what the relationship scan found.
// Skips silently when the export is not checked out.
//
//   flutter test test/relationship_corpus_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/services/relationship_scanner_service.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';

void main() {
  test('the whole corpus scans into a relationship graph', () async {
    final dir = Directory('source');
    if (!dir.existsSync()) {
      // ignore: avoid_print
      print('No source/ directory; skipping relationship corpus test.');
      return;
    }

    final schema = SchemaService();
    await schema.loadDataSourcesXml('source/DataSources.xml');

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'Prg_\d+\.xml$').hasMatch(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final stopwatch = Stopwatch()..start();
    final raw = <String, Set<String>>{};
    var failed = 0;

    for (final file in files) {
      try {
        final scan = RelationshipScanner.scanProgram(
          file.readAsStringSync(),
          fallbackName: file.uri.pathSegments.last,
        );
        for (final relationship in scan.relationships) {
          raw
              .putIfAbsent(relationship.encode(), () => <String>{})
              .add(scan.programName);
        }
      } catch (_) {
        failed++;
      }
    }

    final graph = RelationshipScanner.resolve(raw, schema);
    stopwatch.stop();

    // ignore: avoid_print
    print('Scanned ${files.length} programs in ${stopwatch.elapsed.inSeconds}s '
        '($failed unreadable): ${raw.length} raw links, '
        '${graph.relationships.length} resolved, '
        '${graph.programs.length} programs, '
        '${graph.relationships.where((r) => r.isSelfReference).length} self-referencing.');

    expect(files.length, greaterThan(1000));
    expect(graph.relationships.length, greaterThan(3000));
    expect(graph.programs, isNotEmpty);

    // Every resolved link must name both of its ends.
    for (final relationship in graph.relationships) {
      expect(relationship.fromTable, isNotEmpty);
      expect(relationship.fromColumn, isNotEmpty);
      expect(relationship.toTable, isNotEmpty);
      expect(relationship.toColumn, isNotEmpty);
      expect(relationship.programs, isNotEmpty);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
