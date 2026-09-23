import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/models/unipaas_models.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';
import 'package:flutter_sql_converter/services/sql_generator_service.dart';
import 'package:flutter_sql_converter/services/xml_parser_service.dart';
import 'package:flutter_sql_converter/widgets/direct_sql_dialog.dart';

void main() {
  group('Direct SQL Parsing and Generation', () {
    const sampleDirectSqlXml = '''<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<Application>
  <Header>
    <Version val="11009"/>
    <WithIsn val="Y"/>
  </Header>
  <ProgramsRepository>
    <Programs>
      <Task MainProgram="N">
        <Header Description="Direct SQL Root Program" ISN_2="1" id="5000">
          <SQL val="Y"/>
        </Header>
        <Resource>
          <Columns>
            <Column id="1" name="v_CustId">
              <PropertyList model="FIELD">
                <Model attr_obj="FIELD_NUMERIC" id="1"/>
                <_Whole id="182" val="10"/>
                <DbColumnName id="178" val="CustID"/>
                <Type id="179" val="INTEGER"/>
              </PropertyList>
            </Column>
            <Column id="2" name="v_CustName">
              <PropertyList model="FIELD">
                <Model attr_obj="FIELD_ALPHA" id="1"/>
                <Picture id="157" valUnicode="50"/>
                <DbColumnName id="178" val="CustName"/>
                <Type id="179" val="VARCHAR(50)"/>
              </PropertyList>
            </Column>
          </Columns>
        </Resource>
        <Information>
          <DB comp="-1"/>
        </Information>
        <SQL_FORM DB="MyFlo" RESTAB="MyFlo">
          <SQL_STMT_U val="SELECT CustID, CustName FROM tblCustomers WHERE Active = :1 ORDER BY CustName"/>
          <INARG>
            <Arguments>
              <Argument>
                <id val="1"/>
                <Exp val="1"/>
              </Argument>
            </Arguments>
          </INARG>
          <OUTARG>
            <Arguments>
              <Argument Variable="1">
                <id val="1"/>
              </Argument>
              <Argument Variable="2">
                <id val="2"/>
              </Argument>
            </Arguments>
          </OUTARG>
        </SQL_FORM>
        <TaskLogic>
          <LogicUnit id="1">
            <LogicLines>
              <LogicLine>
                <DATAVIEW_SRC Type="Q"/>
              </LogicLine>
              <LogicLine>
                <Select FieldID="1" id="1">
                  <Column val="1"/>
                  <Type val="V"/>
                </Select>
              </LogicLine>
              <LogicLine>
                <Select FieldID="2" id="2">
                  <Column val="2"/>
                  <Type val="V"/>
                </Select>
              </LogicLine>
            </LogicLines>
          </LogicUnit>
        </TaskLogic>
        <Expressions>
          <Expression id="1">
            <ExpSyntax val="1"/>
            <ExpAttribute val="N"/>
          </Expression>
        </Expressions>
      </Task>
    </Programs>
  </ProgramsRepository>
</Application>
''';

    test('parses standalone Direct SQL task correctly', () {
      final schema = SchemaService();
      final parser = XmlParserService(schema);

      final program = parser.parseProgramString(sampleDirectSqlXml, 'source/Prg_5000.xml');
      expect(program, isNotNull);
      expect(program!.tasks.length, 1);

      final task = program.tasks.first;
      expect(task.isDirectSql, isTrue);
      expect(task.hasDataSource, isTrue);
      expect(task.directSql, isNotNull);

      final direct = task.directSql!;
      expect(direct.database, 'MyFlo');
      expect(direct.resultDatabase, 'MyFlo');
      expect(direct.sqlStatement, 'SELECT CustID, CustName FROM tblCustomers WHERE Active = :1 ORDER BY CustName');
      expect(direct.inputArguments.length, 1);
      expect(direct.inputArguments[0].index, 1);
      expect(direct.inputArguments[0].expVal, '1');

      expect(direct.outputArguments.length, 2);
      expect(direct.outputArguments[0].index, 1);
      expect(direct.outputArguments[0].varName, 'v_CustId');
      expect(direct.outputArguments[1].index, 2);
      expect(direct.outputArguments[1].varName, 'v_CustName');

      // SQL Generation
      final generator = SqlGeneratorService();
      final sql = generator.generateSql(
        program: program,
        parameters: task.parameters,
        selectedTask: task,
        programNumber: '5000',
      );

      expect(sql, contains('-- Direct SQL Query'));
      expect(sql, contains('-- Database: MyFlo'));
      expect(sql, contains('-- Input Arguments: 1 | Output Arguments: 2'));
      expect(sql, contains('SELECT CustID, CustName FROM tblCustomers WHERE Active = :1 ORDER BY CustName;'));
    });

    test('parses Prg_1040.xml task 182 Check Complete Reports SQL-NEW when available', () async {
      const path1040 = '/Users/bluegene37/Documents/Work/MyFlo/source/Prg_1040.xml';
      final file = File(path1040);
      if (!file.existsSync()) {
        // Skip if running in environment without real repo
        return;
      }

      final schema = SchemaService();
      final dataSourcesFile = File('/Users/bluegene37/Documents/Work/MyFlo/source/DataSources.xml');
      if (dataSourcesFile.existsSync()) {
        await schema.loadDataSourcesXml(dataSourcesFile.path);
      }
      final compsFile = File('/Users/bluegene37/Documents/Work/MyFlo/source/Comps.xml');
      if (compsFile.existsSync()) {
        schema.loadComponentsXml(compsFile.readAsStringSync());
      }

      final parser = XmlParserService(schema);
      final prg1File = File('/Users/bluegene37/Documents/Work/MyFlo/source/Prg_1.xml');
      if (prg1File.existsSync()) {
        parser.parseMainProgramGlobals(prg1File.readAsStringSync());
      }

      final program = await parser.parseProgramFile(path1040);
      expect(program, isNotNull);

      final task182 = program!.allTasksFlattened.firstWhere((t) => t.taskIsn == '182');
      expect(task182.description, 'Check Complete Reports SQL-NEW');
      expect(task182.isDirectSql, isTrue);
      expect(task182.hasDataSource, isTrue);

      final direct = task182.directSql!;
      expect(direct.database, 'MyFlo');
      expect(direct.resultDatabase, 'MyFlo');
      expect(direct.sqlStatement, contains('select * from ('));
      expect(direct.sqlStatement, contains('select 5 as orderby,JobID,dsrReportCode'));
      expect(direct.inputArguments.length, 4);
      expect(direct.outputArguments.length, 25);
      expect(direct.outputArguments[0].varName, 'orderby_IGNORE');
      expect(direct.outputArguments[1].varName, 'jqhJobId');

      final generator = SqlGeneratorService();
      final sql = generator.generateSql(
        program: program,
        parameters: task182.parameters,
        selectedTask: task182,
        programNumber: '5365',
      );

      expect(sql, contains('-- Direct SQL Query'));
      expect(sql, contains('-- Database: MyFlo'));
      expect(sql, contains('-- Input Arguments: 4 | Output Arguments: 25'));
      expect(sql, contains('select * from ('));
      expect(sql, contains('-- Secondary Link Queries for this Direct SQL task\'s record cycle'));
      expect(sql, contains('FROM [dSystem] WITH (NOLOCK)'));
    });
  });

  group('DirectSqlCommandDialog Widget', () {
    testWidgets('renders DirectSqlCommandDialog with database, query and parameters', (tester) async {
      final direct = DirectSqlInfo(
        database: 'TestDb',
        resultDatabase: 'ResultDb',
        sqlStatement: 'SELECT * FROM TestTable WHERE id = :1',
        inputArguments: [
          DirectSqlArgument(index: 1, id: '1', expVal: '1', expressionSyntax: '@jobID'),
        ],
        outputArguments: [
          DirectSqlOutArgument(index: 1, variable: '1', varName: 'outCol1', sqlType: 'INTEGER'),
          DirectSqlOutArgument(index: 2, variable: '2', varName: 'outCol2', sqlType: 'VARCHAR(50)'),
        ],
      );

      final task = ParsedTask(
        taskId: '100',
        taskIsn: '1',
        hierarchyPath: '1.1',
        description: 'Test Direct SQL Task',
        mainTableObj: '',
        mainTableName: '',
        columns: [],
        joins: [],
        whereConditions: [],
        directSql: direct,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectSqlCommandDialog(
              task: task,
              programName: 'Test Program',
              programNumber: '100',
            ),
          ),
        ),
      );

      expect(find.textContaining('SQL Command: #100.1.1'), findsOneWidget);
      expect(find.text('TestDb'), findsOneWidget);
      expect(find.text('ResultDb'), findsOneWidget);
      expect(find.text('Direct SQL'), findsOneWidget);
      expect(find.textContaining('SELECT * FROM TestTable'), findsOneWidget);
      expect(find.text('Input Arguments'), findsOneWidget);
      expect(find.text('Output Arguments'), findsOneWidget);

      // Check input argument :1
      expect(find.text(':1'), findsOneWidget);
      expect(find.text('@jobID'), findsOneWidget);

      // Switch to Output Arguments tab
      await tester.tap(find.text('Output Arguments'));
      await tester.pumpAndSettle();

      expect(find.text('outCol1'), findsOneWidget);
      expect(find.text('INTEGER'), findsOneWidget);
      expect(find.text('outCol2'), findsOneWidget);
      expect(find.text('VARCHAR(50)'), findsOneWidget);
    });
  });
}
