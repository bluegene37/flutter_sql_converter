// The disk cache is what keeps the schema browser instant after the first
// sweep, so it has to survive a round trip and notice a changed export.
//
//   flutter test test/relationship_cache_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/services/relationship_scanner_service.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';

/// A program that links dJobs.jobCustomer to mCustomers.cusCode.
const String _program = '''
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="Job Entry" id="10"/>
    <Information><DB comp="-1" obj="1"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC/></LogicLine>
      <LogicLine><Select FieldID="1">
        <Column val="7"/><Type val="R"/><IsParameter val="N"/>
      </Select></LogicLine>
      <LogicLine><LNK Mode="O"><DB comp="-1" obj="5"/></LNK></LogicLine>
      <LogicLine><Select FieldID="2">
        <Column val="3"/><Type val="R"/><IsParameter val="N"/>
        <Locate MAX="1"/>
      </Select></LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
    <Expressions><Expression><ExpSyntax val="{0,1}"/></Expression></Expressions>
  </Task>
</Programs></ProgramsRepository></Application>
''';

const String _dataSources = '''
<Application><DataSourceRepository><DataObjects>
  <DataObject id="1" name="dJobs" PhysicalName="dJobs" data_source="MyFlo">
    <Columns>
      <Column id="7" name="jobCustomer"><DbColumnName val="jobCustomer"/></Column>
    </Columns>
  </DataObject>
  <DataObject id="5" name="mCustomers" PhysicalName="mCustomers" data_source="MyFlo">
    <Columns>
      <Column id="3" name="cusCode"><DbColumnName val="cusCode"/></Column>
    </Columns>
  </DataObject>
</DataObjects></DataSourceRepository></Application>
''';

void main() {
  late Directory sourceDir;
  late File cacheFile;
  late SchemaService schema;
  late RelationshipScannerService scanner;

  setUp(() async {
    sourceDir = await Directory.systemTemp.createTemp('rel_scan_source');
    cacheFile = File('${sourceDir.path}/cache.json');
    File('${sourceDir.path}/Prg_10.xml').writeAsStringSync(_program);

    schema = SchemaService()..parseDataSourcesString(_dataSources);
    scanner = RelationshipScannerService(cacheFilePath: cacheFile.path);
  });

  tearDown(() async {
    if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
  });

  test('a folder sweep finds the link and names the program', () async {
    final result = await scanner.scanDirectory(sourceDir.path, schema);

    expect(result.fromCache, isFalse);
    expect(result.filesScanned, 1);
    expect(result.filesFailed, 0);
    expect(result.graph.relationships.single.toString(),
        'dJobs.jobCustomer -> mCustomers.cusCode');
    expect(result.graph.relationships.single.programs, ['Job Entry']);
    expect(result.graph.fileForProgram('Job Entry'), 'Prg_10.xml');
  });

  test('the second sweep of an unchanged folder comes from the cache',
      () async {
    await scanner.scanDirectory(sourceDir.path, schema);
    expect(cacheFile.existsSync(), isTrue);

    final second = await scanner.scanDirectory(sourceDir.path, schema);

    expect(second.fromCache, isTrue);
    expect(second.graph.relationships.single.toString(),
        'dJobs.jobCustomer -> mCustomers.cusCode');
    // The program-to-file map has to survive the round trip, or the jump into
    // the SQL generator stops working after a restart.
    expect(second.graph.fileForProgram('Job Entry'), 'Prg_10.xml');
  });

  test('adding a program to the folder invalidates the cache', () async {
    await scanner.scanDirectory(sourceDir.path, schema);

    File('${sourceDir.path}/Prg_11.xml').writeAsStringSync(
      _program.replaceAll('Job Entry', 'Batch Reprice'),
    );

    final rescan = await scanner.scanDirectory(sourceDir.path, schema);

    expect(rescan.fromCache, isFalse);
    expect(rescan.filesScanned, 2);
    expect(
      rescan.graph.relationships.single.programs,
      ['Batch Reprice', 'Job Entry'],
    );
  });

  test('forcing a rescan ignores the cache', () async {
    await scanner.scanDirectory(sourceDir.path, schema);

    final forced =
        await scanner.scanDirectory(sourceDir.path, schema, useCache: false);

    expect(forced.fromCache, isFalse);
    expect(forced.graph.relationships, hasLength(1));
  });

  test('the cache is not reused for a different folder', () async {
    await scanner.scanDirectory(sourceDir.path, schema);

    final other = await Directory.systemTemp.createTemp('rel_scan_other');
    addTearDown(() => other.delete(recursive: true));
    File('${other.path}/Prg_10.xml').writeAsStringSync(_program);

    final result = await scanner.scanDirectory(other.path, schema);

    expect(result.fromCache, isFalse);
  });

  test('a cache written by an older scanner is discarded', () async {
    await scanner.scanDirectory(sourceDir.path, schema);

    // Simulate a cache left behind by a scanner whose output would differ.
    final stale = cacheFile.readAsStringSync().replaceFirst('"v2:', '"v1:');
    cacheFile.writeAsStringSync(stale);

    final result = await scanner.scanDirectory(sourceDir.path, schema);

    expect(result.fromCache, isFalse);
  });

  test('a folder that genuinely has no links still caches its empty result',
      () async {
    // A program with no Locate contributes nothing, so the graph is empty —
    // but the answer is real and must not be recomputed on every launch.
    File('${sourceDir.path}/Prg_10.xml').writeAsStringSync(
      _program.replaceAll('<Locate MAX="1"/>', ''),
    );

    final first = await scanner.scanDirectory(sourceDir.path, schema);
    expect(first.graph.isEmpty, isTrue);
    expect(first.fromCache, isFalse);

    final second = await scanner.scanDirectory(sourceDir.path, schema);
    expect(second.fromCache, isTrue);
    expect(second.graph.isEmpty, isTrue);
  });

  test('a folder with no program files yields an empty graph', () async {
    final empty = await Directory.systemTemp.createTemp('rel_scan_empty');
    addTearDown(() => empty.delete(recursive: true));

    final result = await scanner.scanDirectory(empty.path, schema);

    expect(result.graph.isEmpty, isTrue);
    expect(result.filesScanned, 0);
  });

  test('a missing folder yields an empty graph rather than throwing', () async {
    final result =
        await scanner.scanDirectory('${sourceDir.path}/does-not-exist', schema);

    expect(result.graph.isEmpty, isTrue);
  });

  test('progress is reported and reaches the file count', () async {
    final seen = <int>[];
    await scanner.scanDirectory(
      sourceDir.path,
      schema,
      useCache: false,
      onProgress: (done, total) {
        expect(total, 1);
        seen.add(done);
      },
    );

    expect(seen.last, 1);
  });

  test('an unreadable program is counted, not fatal', () async {
    File('${sourceDir.path}/Prg_12.xml').writeAsStringSync('<not valid xml');

    final result =
        await scanner.scanDirectory(sourceDir.path, schema, useCache: false);

    // Malformed XML yields no relationships but must not lose the good file.
    expect(result.filesScanned, 2);
    expect(result.graph.relationships, hasLength(1));
  });
}
