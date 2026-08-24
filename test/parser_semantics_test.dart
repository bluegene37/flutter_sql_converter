// Locks in how uniPaaS numeric references are read. Each rule here was
// established by measuring the whole source/ export; getting one wrong
// silently produces plausible but incorrect SQL, so they are pinned.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/models/unipaas_models.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';
import 'package:flutter_sql_converter/services/sql_generator_service.dart';
import 'package:flutter_sql_converter/services/xml_parser_service.dart';

/// Two tables: obj 7 with deliberately non-sequential column ISNs, obj 9 with
/// a unique index so a Link Query over it stays a plain join.
const _dataSources = '''<?xml version="1.0" encoding="UTF-8"?>
<Application>
  <DataObjects>
    <DataObject PhysicalName="dJobs" data_source="MyFlo" id="7" name="dJobs">
      <ObjectType val="T"/>
      <Columns>
        <Column id="1" name="jobID">
          <PropertyList model="FIELD">
            <Model attr_obj="FIELD_NUMERIC" id="1"/>
            <_Whole id="182" val="10"/>
            <DbColumnName id="178" val="jobID"/>
          </PropertyList>
        </Column>
        <Column id="9" name="jobStatus">
          <PropertyList model="FIELD">
            <Model attr_obj="FIELD_ALPHA" id="1"/>
            <Picture id="157" valUnicode="20"/>
            <DbColumnName id="178" val="jobStatus"/>
          </PropertyList>
        </Column>
        <Column id="4" name="jobCompany">
          <PropertyList model="FIELD">
            <Model attr_obj="FIELD_NUMERIC" id="1"/>
            <_Whole id="182" val="6"/>
            <DbColumnName id="178" val="jobCompany"/>
          </PropertyList>
        </Column>
      </Columns>
      <Indexes>
        <Index id="1" name="jobsPk">
          <Mode val="S"/>
          <Primary val="Y"/>
          <Segments>
            <Segment><Size val="4"/><Column val="1"/><Order val="A"/></Segment>
          </Segments>
        </Index>
      </Indexes>
    </DataObject>
    <DataObject PhysicalName="dCustomers" data_source="MyFlo" id="9" name="dCustomers">
      <ObjectType val="T"/>
      <Columns>
        <Column id="1" name="custID">
          <PropertyList model="FIELD">
            <Model attr_obj="FIELD_NUMERIC" id="1"/>
            <_Whole id="10" val="10"/>
            <DbColumnName id="178" val="custID"/>
          </PropertyList>
        </Column>
        <Column id="2" name="custName">
          <PropertyList model="FIELD">
            <Model attr_obj="FIELD_ALPHA" id="1"/>
            <Picture id="157" valUnicode="50"/>
            <DbColumnName id="178" val="custName"/>
          </PropertyList>
        </Column>
      </Columns>
      <Indexes>
        <Index id="1" name="custPk">
          <Mode val="S"/>
          <Primary val="Y"/>
          <Segments>
            <Segment><Size val="4"/><Column val="1"/><Order val="A"/></Segment>
          </Segments>
        </Index>
      </Indexes>
    </DataObject>
  </DataObjects>
</Application>''';

SchemaService _schema() => SchemaService()..parseDataSourcesString(_dataSources);

void main() {
  test('Locate/Range MIN and MAX are expression positions, not ids', () {
    // Expression ids are shuffled: position 1 has id 5, position 2 has id 1.
    // A position reading picks 'ACTIVE'; an id reading would pick 42.
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="T" id="1" ISN_2="1"/>
    <Information><DB comp="-1" obj="7"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
      <LogicLine>
        <Select FieldID="1"><Column val="9"/><Type val="R"/><Range MAX="2" MIN="2"/></Select>
      </LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
    <Expressions>
      <Expression id="5"><ExpSyntax val="42"/><ExpAttribute val="N"/></Expression>
      <Expression id="1"><ExpSyntax val="'ACTIVE'"/><ExpAttribute val="A"/></Expression>
    </Expressions>
  </Task>
</Programs></ProgramsRepository></Application>''';

    final program = XmlParserService(_schema()).parseProgramString(xml, 'Prg_1.xml')!;
    final where = program.tasks.single.whereConditions.single;

    expect(where.colName, equals('jobStatus'));
    expect(where.operator, equals('='));
    expect(where.valueExpression, equals("'ACTIVE'"));
  });

  test('a real column addresses DataSources by ISN, not by position', () {
    // Column val 9 is the third column of dJobs but its ISN is 9.
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="T" id="1" ISN_2="1"/>
    <Information><DB comp="-1" obj="7"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
      <LogicLine><Select FieldID="1"><Column val="9"/><Type val="R"/></Select></LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
  </Task>
</Programs></ProgramsRepository></Application>''';

    final program = XmlParserService(_schema()).parseProgramString(xml, 'Prg_1.xml')!;
    expect(program.tasks.single.columns.single.colName, equals('jobStatus'));
  });

  test('a virtual column addresses the task variable list by position', () {
    // Column val 2 is the second declared variable, whose id is 77.
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="T" id="1" ISN_2="1"/>
    <Resource><Columns>
      <Column id="31" name="v_First"><PropertyList model="FIELD">
        <Model attr_obj="FIELD_ALPHA" id="1"/><Picture id="157" valUnicode="10"/>
      </PropertyList></Column>
      <Column id="77" name="p_Second"><PropertyList model="FIELD">
        <Model attr_obj="FIELD_NUMERIC" id="1"/><_Whole id="182" val="4"/>
      </PropertyList></Column>
    </Columns></Resource>
    <Information><DB comp="-1" obj="7"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
      <LogicLine>
        <Select FieldID="1"><Column val="2"/><Type val="V"/><IsParameter val="Y"/></Select>
      </LogicLine>
      <LogicLine>
        <Select FieldID="2"><Column val="1"/><Type val="R"/><Range MAX="1" MIN="1"/></Select>
      </LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
    <Expressions>
      <Expression id="1"><ExpSyntax val="{0,1}"/><ExpAttribute val="N"/></Expression>
    </Expressions>
  </Task>
</Programs></ProgramsRepository></Application>''';

    final program = XmlParserService(_schema()).parseProgramString(xml, 'Prg_1.xml')!;
    expect(program.tasks.single.whereConditions.single.valueExpression, equals('@p_Second'));
  });

  test('range shapes map to =, >= and BETWEEN', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="T" id="1" ISN_2="1"/>
    <Information><DB comp="-1" obj="7"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
      <LogicLine><Select FieldID="1"><Column val="1"/><Type val="R"/><Range MAX="2" MIN="1"/></Select></LogicLine>
      <LogicLine><Select FieldID="2"><Column val="4"/><Type val="R"/><Range MIN="1"/></Select></LogicLine>
      <LogicLine><Select FieldID="3"><Column val="9"/><Type val="R"/><Range MAX="3" MIN="3"/></Select></LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
    <Expressions>
      <Expression id="1"><ExpSyntax val="10"/><ExpAttribute val="N"/></Expression>
      <Expression id="2"><ExpSyntax val="20"/><ExpAttribute val="N"/></Expression>
      <Expression id="3"><ExpSyntax val="'X'"/><ExpAttribute val="A"/></Expression>
    </Expressions>
  </Task>
</Programs></ProgramsRepository></Application>''';

    final wheres = XmlParserService(_schema())
        .parseProgramString(xml, 'Prg_1.xml')!
        .tasks
        .single
        .whereConditions;

    expect(wheres[0].operator, equals('BETWEEN'));
    expect(wheres[0].valueExpression, equals('10'));
    expect(wheres[0].upperExpression, equals('20'));
    expect(wheres[1].operator, equals('>='));
    expect(wheres[2].operator, equals('='));
  });

  test('link mode picks the join type and the same table linked twice is aliased', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="T" id="1" ISN_2="1"/>
    <Information><DB comp="-1" obj="7"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
      <LogicLine><LNK Direction="A" Key="1" Mode="J"><DB comp="-1" obj="9"/></LNK></LogicLine>
      <LogicLine><Select FieldID="1"><Column val="1"/><Type val="R"/><Locate MAX="1" MIN="1"/></Select></LogicLine>
      <LogicLine><END_LINK/></LogicLine>
      <LogicLine><LNK Direction="A" Key="1" Mode="O"><DB comp="-1" obj="9"/></LNK></LogicLine>
      <LogicLine><Select FieldID="2"><Column val="2"/><Type val="R"/></Select></LogicLine>
      <LogicLine><END_LINK/></LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
    <Expressions>
      <Expression id="1"><ExpSyntax val="1"/><ExpAttribute val="N"/></Expression>
    </Expressions>
  </Task>
</Programs></ProgramsRepository></Application>''';

    final joins =
        XmlParserService(_schema()).parseProgramString(xml, 'Prg_1.xml')!.tasks.single.joins;

    expect(joins[0].joinType, equals('INNER JOIN'));
    expect(joins[0].alias, equals('dCustomers'));
    expect(joins[1].joinType, equals('LEFT OUTER JOIN'));
    expect(joins[1].alias, equals('dCustomers_2'));
  });

  test('a child task reads {1,N} as a value from the parent record', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="Parent" id="1" ISN_2="1"/>
    <Information><DB comp="-1" obj="7"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
      <LogicLine><Select FieldID="3"><Column val="4"/><Type val="R"/></Select></LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
    <Task>
      <Header Description="Child" id="1" ISN_2="2"/>
      <Information><DB comp="-1" obj="9"/></Information>
      <TaskLogic><LogicUnit><LogicLines>
        <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
        <LogicLine><Select FieldID="1"><Column val="1"/><Type val="R"/><Range MAX="1" MIN="1"/></Select></LogicLine>
      </LogicLines></LogicUnit></TaskLogic>
      <Expressions>
        <Expression id="1"><ExpSyntax val="{1,3}"/><ExpAttribute val="N"/></Expression>
      </Expressions>
    </Task>
  </Task>
</Programs></ProgramsRepository></Application>''';

    final program = XmlParserService(_schema()).parseProgramString(xml, 'Prg_1.xml')!;
    final child = program.tasks.single.subTasks.single;

    // The parent's dJobs row is not in the child's FROM clause, so its column
    // arrives as a value rather than a dangling table reference.
    expect(child.whereConditions.single.valueExpression, equals('@dJobs_jobCompany'));
    expect(
      program.extractedParameters.firstWhere((p) => p.name == 'dJobs_jobCompany').type,
      equals('INT'),
    );
  });

  test('a table owned by another component is not resolved against the local schema', () {
    // Object 9 exists locally as dCustomers, but comp="3" makes this a
    // different object entirely.
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="T" id="1" ISN_2="1"/>
    <Information><DB comp="3" obj="9"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
  </Task>
</Programs></ProgramsRepository></Application>''';

    const comps = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ComponentsRepository><Components>
  <Component id="3" name="FinancialSystems">
    <ComponentDataObjects>
      <Object><id val="65"/><ItemIsn val="9"/><PublicName val="AccountsTable"/></Object>
    </ComponentDataObjects>
  </Component>
</Components></ComponentsRepository></Application>''';

    final schema = _schema()..loadComponentsXml(comps);
    final task = XmlParserService(schema).parseProgramString(xml, 'Prg_1.xml')!.tasks.single;

    expect(task.mainTableName, equals('AccountsTable'));
    expect(task.externalTables, contains('AccountsTable'));
  });

  test('generated SQL keeps range operators and orders by the read index', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="T" id="1" ISN_2="1"/>
    <Information><Key><Column val="1"/></Key><DB comp="-1" obj="7"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC IDX="1" Type="M"/></LogicLine>
      <LogicLine><Select FieldID="1"><Column val="1"/><Type val="R"/><Range MAX="2" MIN="1"/></Select></LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
    <Expressions>
      <Expression id="1"><ExpSyntax val="10"/><ExpAttribute val="N"/></Expression>
      <Expression id="2"><ExpSyntax val="20"/><ExpAttribute val="N"/></Expression>
    </Expressions>
  </Task>
</Programs></ProgramsRepository></Application>''';

    final program = XmlParserService(_schema()).parseProgramString(xml, 'Prg_1.xml')!;
    final sql = SqlGeneratorService().generateSql(
      program: program,
      parameters: program.extractedParameters,
    );

    expect(sql, contains('FROM [dJobs] WITH (NOLOCK)'));
    expect(sql, contains('WHERE [dJobs].[jobID] BETWEEN 10 AND 20'));
    expect(sql, contains('ORDER BY [dJobs].[jobID]'));
  });

  test("uniPaaS typed literals become SQL values", () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
  <Task>
    <Header Description="T" id="1" ISN_2="1"/>
    <Information><DB comp="-1" obj="7"/></Information>
    <TaskLogic><LogicUnit><LogicLines>
      <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
      <LogicLine><Select FieldID="1"><Column val="9"/><Type val="R"/><Range MAX="1" MIN="1"/></Select></LogicLine>
    </LogicLines></LogicUnit></TaskLogic>
    <Expressions>
      <Expression id="1"><ExpSyntax val="'TRUE'LOG"/><ExpAttribute val="B"/></Expression>
    </Expressions>
  </Task>
</Programs></ProgramsRepository></Application>''';

    final program = XmlParserService(_schema()).parseProgramString(xml, 'Prg_1.xml')!;
    expect(program.tasks.single.whereConditions.single.valueExpression, equals('1'));
  });

  test('index segments address DataSources columns by position', () {
    // Segment Column val 1 is the first column of dJobs, whose ISN is also 1.
    final schema = _schema();
    final order = schema.getIndexOrder('7', '1');
    expect(order.single.colName, equals('jobID'));
    expect(schema.isUniqueIndex('7', '1'), isTrue);
  });

  test('column types come through from DataSources', () {
    final schema = _schema();
    expect(schema.getColumnSqlType('7', '1'), equals('BIGINT'));
    expect(schema.getColumnSqlType('7', '9'), equals('NVARCHAR(20)'));
    expect(schema.getColumnSqlType('7', '4'), equals('INT'));
  });

  test('tasks are numbered the way uniPaaS Studio numbers them', () {
    // A root task with two children, the first of which has a child of its own.
    String task(String desc, String inner) => '''
      <Task>
        <Header Description="$desc" id="1" ISN_2="9"/>
        <Information><DB comp="-1" obj="7"/></Information>
        <TaskLogic><LogicUnit><LogicLines>
          <LogicLine><DATAVIEW_SRC Type="M"/></LogicLine>
        </LogicLines></LogicUnit></TaskLogic>
        $inner
      </Task>''';

    final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Application><ProgramsRepository><Programs>
${task('Root', '${task('First child', task('Grandchild', ''))}${task('Second child', '')}')}
</Programs></ProgramsRepository></Application>''';

    final program = XmlParserService(_schema()).parseProgramString(xml, 'Prg_1.xml')!;
    final flat = program.allTasksFlattened;

    expect(flat.map((t) => t.hierarchyPath).toList(), ['', '1', '1.1', '2']);
    // Shown under program 12, this reads exactly like Studio's "Task 12.1".
    expect(flat.map((t) => t.numberWithin('12')).toList(),
        ['#12', '#12.1', '#12.1.1', '#12.2']);
    expect(flat[1].hasSubTasks, isTrue);
    expect(flat[2].hasSubTasks, isFalse);
  });

  test('a decimal never gets a scale larger than its precision', () {
    expect(
      UnipaasTypeMapper.sqlType(attrObj: 'FIELD_NUMERIC', whole: 2, dec: 3),
      equals('DECIMAL(5, 3)'),
    );
  });
}
