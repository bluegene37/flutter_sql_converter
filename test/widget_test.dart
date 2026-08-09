import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_sql_converter/main.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';
import 'package:flutter_sql_converter/services/xml_parser_service.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('App launches and displays loading indicator while loading schema', (WidgetTester tester) async {
    await tester.pumpWidget(const UniPaasConverterApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test('XmlParserService correctly resolves {32768,2} to MainProgram global variable g_UserID', () {
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

  test('XmlParserService correctly resolves parameter name p_dept instead of Var_1', () {
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
}
