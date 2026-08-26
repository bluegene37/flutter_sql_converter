// Covers the Locate-driven relationship scan that feeds the schema browser.
//
//   flutter test test/relationship_scanner_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/models/schema_relationship.dart';
import 'package:flutter_sql_converter/services/relationship_scanner_service.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';

/// Wraps dataview logic lines in the minimum program structure the scanner
/// walks: one task, its main source, its expressions, one logic unit.
String programXml({
  String description = 'Test Program',
  String mainTableObj = '1',
  List<String> expressions = const [],
  required String logicLines,
}) {
  final expressionNodes = expressions
      .map((syntax) =>
          '<Expression><ExpSyntax val="$syntax"/></Expression>')
      .join();
  return '''
<Application><ProgramsRepository><Programs>
  <Task MainProgram="N">
    <Header Description="$description" id="99"/>
    <Information><DB comp="-1" obj="$mainTableObj"/></Information>
    <TaskLogic>
      <LogicUnit id="1">
        <LogicLines>
          <LogicLine><DATAVIEW_SRC IDX="2" Type="M"/></LogicLine>
          $logicLines
        </LogicLines>
      </LogicUnit>
    </TaskLogic>
    <Expressions>$expressionNodes</Expressions>
  </Task>
</Programs></ProgramsRepository></Application>
''';
}

String select(
  String fieldId,
  String columnVal, {
  String type = 'R',
  String isParameter = 'N',
  String? locateMax,
  String? locateMin,
}) {
  final locate = (locateMax == null && locateMin == null)
      ? ''
      : '<Locate ${locateMax != null ? 'MAX="$locateMax" ' : ''}'
          '${locateMin != null ? 'MIN="$locateMin"' : ''}/>';
  return '''
<LogicLine><Select FieldID="$fieldId">
  <Column val="$columnVal"/>
  <Type val="$type"/>
  <IsParameter val="$isParameter"/>
  $locate
</Select></LogicLine>''';
}

String link(String tableObj, {String comp = '-1'}) =>
    '<LogicLine><LNK Mode="O"><DB comp="$comp" obj="$tableObj"/></LNK></LogicLine>';

const String endLink = '<LogicLine><END_LINK/></LogicLine>';

void main() {
  group('scanProgram', () {
    test('names the program after the first task header description', () {
      final scan = RelationshipScanner.scanProgram(
        programXml(description: 'Batch Reprice', logicLines: ''),
        fallbackName: 'Prg_99.xml',
      );

      expect(scan.programName, 'Batch Reprice');
    });

    test('falls back to the filename when no header description exists', () {
      const xml = '<Application><Task><Header id="99"/></Task></Application>';

      final scan =
          RelationshipScanner.scanProgram(xml, fallbackName: 'Prg_99.xml');

      expect(scan.programName, 'Prg_99.xml');
    });

    test('records a link when a Locate points at an earlier dataview field',
        () {
      final xml = programXml(
        mainTableObj: '1',
        expressions: const ['{0,1}'],
        logicLines: [
          select('1', '7'),
          link('5'),
          select('2', '3', locateMax: '1'),
          endLink,
        ].join(),
      );

      final scan =
          RelationshipScanner.scanProgram(xml, fallbackName: 'Prg_99.xml');

      expect(
        scan.relationships,
        {
          const RawRelationship(
            fromTableKey: '1',
            fromColumnIsn: '7',
            toTableKey: '5',
            toColumnIsn: '3',
          ),
        },
      );
    });

    test('reads the source field from MIN when MAX is absent', () {
      final xml = programXml(
        expressions: const ['{0,1}'],
        logicLines: [
          select('1', '7'),
          link('5'),
          select('2', '3', locateMin: '1'),
        ].join(),
      );

      final scan =
          RelationshipScanner.scanProgram(xml, fallbackName: 'Prg_99.xml');

      expect(scan.relationships.single.fromColumnIsn, '7');
    });

    test('ignores a Locate whose expression is not a bare field reference', () {
      final xml = programXml(
        expressions: const ['{0,1}+1'],
        logicLines: [
          select('1', '7'),
          link('5'),
          select('2', '3', locateMax: '1'),
        ].join(),
      );

      final scan =
          RelationshipScanner.scanProgram(xml, fallbackName: 'Prg_99.xml');

      expect(scan.relationships, isEmpty);
    });

    test('ignores virtual fields and parameters on both ends of the link', () {
      final virtualSource = programXml(
        expressions: const ['{0,1}'],
        logicLines: [
          select('1', '7', type: 'V'),
          link('5'),
          select('2', '3', locateMax: '1'),
        ].join(),
      );
      final parameterTarget = programXml(
        expressions: const ['{0,1}'],
        logicLines: [
          select('1', '7'),
          link('5'),
          select('2', '3', isParameter: 'Y', locateMax: '1'),
        ].join(),
      );

      expect(
        RelationshipScanner.scanProgram(virtualSource, fallbackName: 'x')
            .relationships,
        isEmpty,
      );
      expect(
        RelationshipScanner.scanProgram(parameterTarget, fallbackName: 'x')
            .relationships,
        isEmpty,
      );
    });

    test('END_LINK restores the table the link was entered from', () {
      final xml = programXml(
        mainTableObj: '1',
        expressions: const ['{0,1}'],
        logicLines: [
          select('1', '7'),
          link('5'),
          endLink,
          // Back on the main source, so the Locate below targets table 1.
          select('2', '3', locateMax: '1'),
        ].join(),
      );

      final scan =
          RelationshipScanner.scanProgram(xml, fallbackName: 'Prg_99.xml');

      expect(scan.relationships.single.toTableKey, '1');
    });

    test('keeps a link into another component addressable by component key',
        () {
      final xml = programXml(
        expressions: const ['{0,1}'],
        logicLines: [
          select('1', '7'),
          link('5', comp: '3'),
          select('2', '3', locateMax: '1'),
        ].join(),
      );

      final scan =
          RelationshipScanner.scanProgram(xml, fallbackName: 'Prg_99.xml');

      // Object 5 of component 3 is a different table from the local object 5.
      expect(scan.relationships.single.toTableKey, '3:5');
    });

    test('a task with no Locate contributes nothing', () {
      final xml = programXml(
        logicLines: [select('1', '7'), link('5'), select('2', '3')].join(),
      );

      expect(
        RelationshipScanner.scanProgram(xml, fallbackName: 'x').relationships,
        isEmpty,
      );
    });
  });

  group('resolveRelationships', () {
    late SchemaService schema;

    setUp(() {
      schema = SchemaService();
      schema.parseDataSourcesString('''
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
''');
    });

    test('turns object ids into names and merges the programs that use a link',
        () {
      const raw = RawRelationship(
        fromTableKey: '1',
        fromColumnIsn: '7',
        toTableKey: '5',
        toColumnIsn: '3',
      );

      final graph = RelationshipScanner.resolve(
        {
          raw.encode(): {'Job Entry', 'Batch Reprice'},
        },
        schema,
      );

      expect(graph.relationships, hasLength(1));
      final rel = graph.relationships.single;
      expect(rel.fromTable, 'dJobs');
      expect(rel.fromColumn, 'jobCustomer');
      expect(rel.toTable, 'mCustomers');
      expect(rel.toColumn, 'cusCode');
      expect(rel.programs, ['Batch Reprice', 'Job Entry']);
    });

    test('drops links whose table or column is not in the repository', () {
      final unknownTable = const RawRelationship(
        fromTableKey: '1',
        fromColumnIsn: '7',
        toTableKey: '404',
        toColumnIsn: '3',
      ).encode();
      final unknownColumn = const RawRelationship(
        fromTableKey: '1',
        fromColumnIsn: '404',
        toTableKey: '5',
        toColumnIsn: '3',
      ).encode();

      final graph = RelationshipScanner.resolve(
        {
          unknownTable: {'A'},
          unknownColumn: {'B'},
        },
        schema,
      );

      expect(graph.relationships, isEmpty);
    });

    test('indexes each link under both of its tables and its programs', () {
      final graph = RelationshipScanner.resolve(
        {
          const RawRelationship(
            fromTableKey: '1',
            fromColumnIsn: '7',
            toTableKey: '5',
            toColumnIsn: '3',
          ).encode(): {'Job Entry'},
        },
        schema,
      );

      expect(graph.outgoingFor('dJobs'), hasLength(1));
      expect(graph.incomingFor('mCustomers'), hasLength(1));
      expect(graph.outgoingFor('mCustomers'), isEmpty);
      expect(graph.forProgram('Job Entry'), hasLength(1));
      expect(graph.programs, ['Job Entry']);
      expect(graph.degreeOf('dJobs'), 1);
    });
  });

  group('corpus', () {
    // These pin the Dart scan to relationships the original Python extractor
    // found in the same files. Skipped when the export is not checked out.
    final sourceDir = Directory('source');

    test('reproduces the known link in Prg_2896', () async {
      if (!sourceDir.existsSync()) return;
      final schema = SchemaService();
      await schema.loadDataSourcesXml('source/DataSources.xml');

      final scan = RelationshipScanner.scanProgram(
        File('source/Prg_2896.xml').readAsStringSync(),
        fallbackName: 'Prg_2896.xml',
      );
      final graph = RelationshipScanner.resolve(
        {for (final r in scan.relationships) r.encode(): {scan.programName}},
        schema,
      );

      expect(scan.programName, 'batch - updateAssignedFullName');
      expect(graph.relationships.map((r) => r.toString()), [
        'dJobAssigned.jadAssigned -> dRegisteredUsers.regUserID',
      ]);
    });

    test('reproduces the known link in Prg_4356', () async {
      if (!sourceDir.existsSync()) return;
      final schema = SchemaService();
      await schema.loadDataSourcesXml('source/DataSources.xml');

      final scan = RelationshipScanner.scanProgram(
        File('source/Prg_4356.xml').readAsStringSync(),
        fallbackName: 'Prg_4356.xml',
      );
      final graph = RelationshipScanner.resolve(
        {for (final r in scan.relationships) r.encode(): {scan.programName}},
        schema,
      );

      expect(scan.programName, 'Batch-ProcessJobKeywords');
      expect(graph.relationships.map((r) => r.toString()), [
        'dJobs.jobID -> dJobKeyWords.jkwJobID',
      ]);
    });

    test('a self-referencing link survives resolution', () async {
      if (!sourceDir.existsSync()) return;
      final schema = SchemaService();
      await schema.loadDataSourcesXml('source/DataSources.xml');

      final scan = RelationshipScanner.scanProgram(
        File('source/Prg_2448.xml').readAsStringSync(),
        fallbackName: 'Prg_2448.xml',
      );
      final graph = RelationshipScanner.resolve(
        {for (final r in scan.relationships) r.encode(): {scan.programName}},
        schema,
      );

      expect(graph.relationships.single.toString(),
          'dJobs.jobWorkOrder -> dJobs.jobWorkOrder');
      expect(graph.relationships.single.isSelfReference, isTrue);
    });
  });
}
