import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_sql_converter/main.dart';
import 'package:flutter_sql_converter/models/unipaas_models.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';
import 'package:flutter_sql_converter/services/sql_generator_service.dart';
import 'package:flutter_sql_converter/services/xml_parser_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('App launches and displays loading indicator while loading schema', (WidgetTester tester) async {
    await tester.pumpWidget(const UniPaasConverterApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('XmlParserService correctly resolves {32768,2} to MainProgram global variable g_UserID', (WidgetTester tester) async {
    final parser = XmlParserService(SchemaService());

    const mainProgXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application>
  <ProgramsRepository>
    <Programs>
      <Task MainProgram="Y">
        <Header Description="Main Program" id="1"/>
        <Resource>
          <Columns>
            <Column id="31" name="g_DepartmentID"/>
            <Column id="25" name="g_UserID"/>
          </Columns>
        </Resource>
        <TaskLogic>
          <LogicUnit>
            <LogicLines>
              <LogicLine>
                <Select FieldID="1" id="1"><Column val="31"/></Select>
              </LogicLine>
              <LogicLine>
                <Select FieldID="2" id="2"><Column val="25"/></Select>
              </LogicLine>
            </LogicLines>
          </LogicUnit>
        </TaskLogic>
      </Task>
    </Programs>
  </ProgramsRepository>
</Application>''';

    parser.ensureMainProgramLoaded(''); // loads via internal method
    // Inject xml via internal parse method
    final parsedMain = parser.parseProgramString(mainProgXml, 'Prg_1.xml');
    expect(parsedMain, isNotNull);

    const childProgXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application>
  <ProgramsRepository>
    <Programs>
      <Task>
        <Header Description="System Master File" id="5"/>
        <Information>
          <DB>
            <DataObject obj="dCompanies"/>
          </DB>
        </Information>
        <Expressions>
          <Expression id="1">
            <ExpSyntax val="{32768,2}"/>
          </Expression>
        </Expressions>
        <TaskLogic>
          <LogicUnit>
            <LogicLines>
              <LogicLine>
                <LNK Mode="R">
                  <DB obj="dStaff"/>
                </LNK>
              </LogicLine>
              <LogicLine>
                <Select FieldID="1">
                  <Column val="1"/>
                  <Type val="R"/>
                  <Locate MIN="1"/>
                </Select>
              </LogicLine>
              <LogicLine>
                <END_LINK/>
              </LogicLine>
            </LogicLines>
          </LogicUnit>
        </TaskLogic>
      </Task>
    </Programs>
  </ProgramsRepository>
</Application>''';

    final parsedChild = parser.parseProgramString(childProgXml, 'Prg_5.xml');
    expect(parsedChild, isNotNull);
    final joinCond = parsedChild!.tasks.first.joins.first.conditions.first;
    expect(joinCond.sourceExpression, equals('@g_UserID'));
  });

  testWidgets('XmlParserService correctly resolves parameter name p_dept instead of Var_1', (WidgetTester tester) async {
    final parser = XmlParserService(SchemaService());

    const subTaskXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application>
  <ProgramsRepository>
    <Programs>
      <Task>
        <Header Description="Calculate time interval" id="5"/>
        <Resource>
          <Columns>
            <Column id="3" name="p_dept"/>
            <Column id="2" name="v_time"/>
          </Columns>
        </Resource>
        <Expressions>
          <Expression id="1"><ExpSyntax val="1"/></Expression>
          <Expression id="2"><ExpSyntax val="2"/></Expression>
          <Expression id="3"><ExpSyntax val="3"/></Expression>
          <Expression id="4">
            <ExpSyntax val="{0,6}"/>
          </Expression>
        </Expressions>
        <TaskLogic>
          <LogicUnit>
            <LogicLines>
              <LogicLine>
                <Select FieldID="6">
                  <Column val="1"/>
                  <Type val="V"/>
                  <IsParameter val="Y"/>
                </Select>
              </LogicLine>
              <LogicLine>
                <LNK Mode="W">
                  <DB comp="-1" obj="271"/>
                </LNK>
              </LogicLine>
              <LogicLine>
                <Select FieldID="4">
                  <ASS val="4"/>
                  <Column val="2"/>
                  <Type val="R"/>
                </Select>
              </LogicLine>
              <LogicLine>
                <END_LINK/>
              </LogicLine>
            </LogicLines>
          </LogicUnit>
        </TaskLogic>
      </Task>
    </Programs>
  </ProgramsRepository>
</Application>''';

    final parsed = parser.parseProgramString(subTaskXml, 'Prg_5_sub.xml');
    expect(parsed, isNotNull);

    final param = parsed!.extractedParameters.firstWhere((p) => p.name == 'p_dept');
    expect(param.name, equals('p_dept'));
    expect(param.isParameter, isTrue);
  });

  testWidgets('XmlParserService extracts exact SQL types for MainProgram global variables', (WidgetTester tester) async {
    final parser = XmlParserService(SchemaService());

    const mainProgXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application>
  <ProgramsRepository>
    <Programs>
      <Task MainProgram="Y">
        <Header Description="Main Program" id="1"/>
        <Resource>
          <Columns>
            <Column id="31" name="g_DepartmentID">
              <PropertyList model="FIELD">
                <Model attr_obj="FIELD_NUMERIC"/>
                <_Whole val="8"/>
              </PropertyList>
            </Column>
            <Column id="25" name="g_UserID">
              <PropertyList model="FIELD">
                <Model attr_obj="FIELD_NUMERIC"/>
                <_Whole val="8"/>
              </PropertyList>
            </Column>
            <Column id="16" name="g_User Access Level">
              <PropertyList model="FIELD">
                <Model attr_obj="FIELD_ALPHA"/>
                <Picture valUnicode="20"/>
              </PropertyList>
            </Column>
            <Column id="20" name="g_Date Logged On">
              <PropertyList model="FIELD">
                <Model attr_obj="FIELD_DATE"/>
              </PropertyList>
            </Column>
          </Columns>
        </Resource>
        <TaskLogic>
          <LogicUnit>
            <LogicLines>
              <LogicLine><Select FieldID="1" id="1"><Column val="31"/></Select></LogicLine>
              <LogicLine><Select FieldID="2" id="2"><Column val="25"/></Select></LogicLine>
              <LogicLine><Select FieldID="3" id="3"><Column val="16"/></Select></LogicLine>
              <LogicLine><Select FieldID="5" id="5"><Column val="20"/></Select></LogicLine>
            </LogicLines>
          </LogicUnit>
        </TaskLogic>
      </Task>
    </Programs>
  </ProgramsRepository>
</Application>''';

    parser.parseProgramString(mainProgXml, 'Prg_1.xml');

    const childProgXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application>
  <ProgramsRepository>
    <Programs>
      <Task>
        <Header Description="Test Program" id="2"/>
        <Expressions>
          <Expression id="1"><ExpSyntax val="{32768,1}"/></Expression>
          <Expression id="2"><ExpSyntax val="{32768,2}"/></Expression>
          <Expression id="3"><ExpSyntax val="{32768,3}"/></Expression>
          <Expression id="4"><ExpSyntax val="{32768,5}"/></Expression>
        </Expressions>
        <TaskLogic>
          <LogicUnit>
            <LogicLines>
              <LogicLine><DATAVIEW_SRC/></LogicLine>
            </LogicLines>
          </LogicUnit>
        </TaskLogic>
      </Task>
    </Programs>
  </ProgramsRepository>
</Application>''';

    final parsedChild = parser.parseProgramString(childProgXml, 'Prg_999.xml');
    expect(parsedChild, isNotNull);

    final params = parsedChild!.extractedParameters;
    expect(params.firstWhere((p) => p.name == 'g_DepartmentID').type, equals('INT'));
    expect(params.firstWhere((p) => p.name == 'g_UserID').type, equals('INT'));
    expect(params.firstWhere((p) => p.name == 'g_User_Access_Level').type, equals('NVARCHAR(20)'));
    expect(params.firstWhere((p) => p.name == 'g_Date_Logged_On').type, equals('DATETIME'));
  });

  testWidgets('SqlGeneratorService omits unused global parameters from SQL output', (WidgetTester tester) async {
    final generator = SqlGeneratorService();
    final program = ParsedProgram(
      id: '5',
      filename: 'Prg_5.xml',
      name: 'System Master File',
      tasks: [
        ParsedTask(
          taskId: '5',
          taskIsn: '1',
          parentTaskId: null,
          level: 0,
          description: 'Main Task',
          mainTableObj: 'dCompanies',
          mainTableName: 'dCompanies',
          columns: [],
          joins: [
            TableJoin(
              joinType: 'LEFT OUTER JOIN',
              targetTableObj: 'dStaff',
              targetTableName: 'dStaff',
              mode: 'R',
              conditions: [
                JoinCondition(targetColName: 'stfSysID', sourceExpression: '@g_UserID'),
              ],
            ),
          ],
          whereConditions: [],
          parameters: [],
          subTasks: [],
        ),
      ],
      extractedParameters: [
        ProgramParameter(fieldId: '1', colId: '', name: 'g_DepartmentID', type: 'INT', isParameter: true),
        ProgramParameter(fieldId: '2', colId: '', name: 'g_UserID', type: 'INT', isParameter: true),
        ProgramParameter(fieldId: '3', colId: '', name: 'g_User_Access_Level', type: 'NVARCHAR(20)', isParameter: true),
      ],
    );

    final sql = generator.generateSql(
      program: program,
      parameters: program.extractedParameters,
    );

    expect(sql, contains('DECLARE @g_UserID INT = NULL;'));
    expect(sql, isNot(contains('DECLARE @g_DepartmentID')));
    expect(sql, isNot(contains('DECLARE @g_User_Access_Level')));
  });

  test('SchemaService correctly maps DataSources.xml table and column IDs including Column 2 skvDepartment', () async {
    final schemaService = SchemaService();

    final tempFile = File('${Directory.systemTemp.path}/test_datasources.xml');
    await tempFile.writeAsString('''<Application>
<DataObject id="271" name="mStopClockTimeIntervals">
  <Columns>
    <Column id="1" name="skvTime">
      <PropertyList model="FIELD"><DbColumnName id="178" val="skvTime"/></PropertyList>
    </Column>
    <Column id="2" name="skvDepartment">
      <PropertyList model="FIELD"><DbColumnName id="178" val="skvDepartment"/></PropertyList>
    </Column>
  </Columns>
</DataObject>
</Application>''');

    await schemaService.loadDataSourcesXml(tempFile.path);

    final tableName = schemaService.getTableName('271');
    expect(tableName, equals('mStopClockTimeIntervals'));
    expect(schemaService.getColumnName('271', '1'), equals('skvTime'));
    expect(schemaService.getColumnName('271', '2'), equals('skvDepartment'));

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  });
}
