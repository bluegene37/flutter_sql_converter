// Widget-level coverage for the schema browser: the three modes, filtering,
// and the table inspector.
//
//   flutter test test/schema_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_sql_converter/models/schema_relationship.dart';
import 'package:flutter_sql_converter/services/schema_service.dart';
import 'package:flutter_sql_converter/views/schema_view.dart';
import 'package:flutter_sql_converter/utils/format.dart';
import 'package:flutter_sql_converter/widgets/schema_chrome.dart';

/// Table names also appear on data-source pills and in table rows, so filter
/// chips have to be addressed by their widget, not by their label alone.
Finder _filterChip(String label) => find.descendant(
      of: find.byType(SchemaFilterChip),
      matching: find.text(label),
    );

const String _dataSources = '''
<Application><DataSourceRepository><DataObjects>
  <DataObject id="1" name="dJobs" PhysicalName="dJobs" data_source="MyFlo">
    <Columns>
      <Column id="1" name="jobID"><DbColumnName val="jobID"/></Column>
      <Column id="7" name="jobCustomer"><DbColumnName val="jobCustomer"/></Column>
    </Columns>
  </DataObject>
  <DataObject id="5" name="mCustomers" PhysicalName="mCustomers" data_source="MyFlo">
    <Columns>
      <Column id="3" name="cusCode"><DbColumnName val="cusCode"/></Column>
    </Columns>
  </DataObject>
  <DataObject id="9" name="oScratchPad" PhysicalName="oScratchPad" data_source="Memory">
    <Columns>
      <Column id="1" name="tmpValue"><DbColumnName val="tmpValue"/></Column>
    </Columns>
  </DataObject>
</DataObjects></DataSourceRepository></Application>
''';

final SchemaGraph _graph = SchemaGraph.from(
  const [
    SchemaRelationship(
      fromTable: 'dJobs',
      fromColumn: 'jobCustomer',
      toTable: 'mCustomers',
      toColumn: 'cusCode',
      programs: ['Job Entry', 'Batch Reprice'],
    ),
  ],
  programFiles: const {'Job Entry': 'Prg_10.xml'},
);

Future<void> _pumpSchemaView(
  WidgetTester tester, {
  SchemaGraph? graph,
  void Function(String programName)? onOpenProgram,
  bool isScanning = false,
  Size size = const Size(1600, 1100),
  FocusNode? searchFocusNode,
}) async {
  final schema = SchemaService()..parseDataSourcesString(_dataSources);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(
      body: SchemaView(
        schemaService: schema,
        graph: graph ?? _graph,
        isScanning: isScanning,
        scanDone: 0,
        scanTotal: 0,
        onRescan: () {},
        onOpenProgram: onOpenProgram,
        searchFocusNode: searchFocusNode,
      ),
    ),
  ));
  // The scan indicator spins forever, so a settle would never return.
  if (isScanning) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('counts carry thousands separators', () {
    expect(formatCount(7), '7');
    expect(formatCount(999), '999');
    expect(formatCount(3414), '3,414');
    expect(formatCount(20879), '20,879');
    expect(formatCount(1234567), '1,234,567');
  });

  testWidgets('cards view lists every table with its relationship count',
      (tester) async {
    await _pumpSchemaView(tester);

    expect(find.text('dJobs'), findsOneWidget);
    expect(find.text('mCustomers'), findsOneWidget);
    expect(find.text('oScratchPad'), findsOneWidget);

    // dJobs points at mCustomers, so both ends show one relationship.
    expect(find.text('1 relationship'), findsNWidgets(2));
    expect(find.text('3 tables'), findsOneWidget);
    expect(find.text('1 link'), findsOneWidget);
  });

  testWidgets('search narrows the tables to matches on name or column',
      (tester) async {
    await _pumpSchemaView(tester);

    await tester.enterText(find.byType(TextField).first, 'cusCode');
    await tester.pumpAndSettle();

    expect(find.text('mCustomers'), findsOneWidget);
    expect(find.text('dJobs'), findsNothing);
  });

  testWidgets('the source filter keeps only tables on that connection',
      (tester) async {
    await _pumpSchemaView(tester);

    await tester.tap(_filterChip('Memory'));
    await tester.pumpAndSettle();

    expect(find.text('oScratchPad'), findsOneWidget);
    expect(find.text('dJobs'), findsNothing);
  });

  testWidgets('the prefix filter keeps only tables of that role',
      (tester) async {
    await _pumpSchemaView(tester);

    await tester.tap(_filterChip('m · Master'));
    await tester.pumpAndSettle();

    expect(find.text('mCustomers'), findsOneWidget);
    expect(find.text('dJobs'), findsNothing);
    expect(find.text('oScratchPad'), findsNothing);
  });

  testWidgets('the list view shows physical names and counts', (tester) async {
    await _pumpSchemaView(tester);

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    expect(find.text('PHYSICAL NAME'), findsOneWidget);
    expect(find.text('RELATIONSHIPS'), findsOneWidget);
    // The logical and physical names of dJobs are the same, so the row prints
    // it in both columns.
    expect(find.text('dJobs'), findsNWidgets(2));
  });

  testWidgets('the programs view shows what a program links', (tester) async {
    await _pumpSchemaView(tester);

    await tester.tap(find.text('Programs'));
    await tester.pumpAndSettle();

    expect(find.text('2 programs with relationships'), findsOneWidget);
    expect(
      find.text('Select a program to see the tables it links.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Batch Reprice'));
    await tester.pumpAndSettle();

    expect(find.text('FROM COLUMN'), findsOneWidget);
    expect(find.text('jobCustomer'), findsOneWidget);
    expect(find.text('cusCode'), findsOneWidget);
  });

  testWidgets('opening a table shows its columns and its relationships',
      (tester) async {
    await _pumpSchemaView(tester);

    await tester.tap(find.text('dJobs'));
    await tester.pumpAndSettle();

    expect(find.text('References'), findsOneWidget);
    expect(find.text('DB COLUMN'), findsOneWidget);
    // Both programs that use the link are named.
    expect(find.text('Job Entry'), findsOneWidget);
    expect(find.text('Batch Reprice'), findsOneWidget);
  });

  testWidgets('following a relationship moves the inspector to that table',
      (tester) async {
    await _pumpSchemaView(tester);

    await tester.tap(find.text('dJobs'));
    await tester.pumpAndSettle();

    // The dialog's own heading, plus the pill naming the far end of the link.
    await tester.tap(find.text('mCustomers').last);
    await tester.pumpAndSettle();

    expect(find.text('Referenced by'), findsOneWidget);
    expect(find.text('References'), findsNothing);
  });

  testWidgets('a table with no links says so rather than showing an empty list',
      (tester) async {
    await _pumpSchemaView(tester);

    await tester.tap(find.text('oScratchPad'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('the scan found no relationships'),
      findsOneWidget,
    );
  });

  testWidgets('a program chip hands the program to the generator',
      (tester) async {
    String? opened;
    await _pumpSchemaView(tester, onOpenProgram: (name) => opened = name);

    await tester.tap(find.text('dJobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Job Entry'));
    await tester.pumpAndSettle();

    expect(opened, 'Job Entry');
  });

  group('toolbar layout', () {
    testWidgets('the filters sit on their own row below the search',
        (tester) async {
      await _pumpSchemaView(tester);

      // Both filter groups are present, and the mode switch shares the search
      // row rather than competing with them.
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('Role'), findsOneWidget);
      expect(find.text('Cards'), findsOneWidget);
    });

    testWidgets('the filter row disappears in the programs view',
        (tester) async {
      await _pumpSchemaView(tester);

      await tester.tap(find.text('Programs'));
      await tester.pumpAndSettle();

      // Programs are not narrowed by connection or name role.
      expect(find.text('Source'), findsNothing);
      expect(find.text('Role'), findsNothing);
      // The mode switch is still there, because it moved to the search row.
      expect(find.text('Cards'), findsOneWidget);
    });

    testWidgets('connections are ordered by how many tables they hold',
        (tester) async {
      await _pumpSchemaView(tester);

      final chips = tester
          .widgetList<SchemaFilterChip>(find.byType(SchemaFilterChip))
          .toList();
      final sources =
          chips.where((c) => c.count != null).map((c) => c.label).toList();

      // MyFlo holds two of the three tables, Memory one.
      expect(sources, ['MyFlo', 'Memory']);
      expect(chips.firstWhere((c) => c.label == 'MyFlo').count, 2);
    });

    testWidgets('a narrow window drops the counts before the mode switch',
        (tester) async {
      await _pumpSchemaView(tester, size: const Size(820, 900));

      // The count pills give way (the search hint still mentions tables)...
      expect(find.text('3 tables'), findsNothing);
      expect(find.text('4 columns'), findsNothing);
      // ...but the relationship count, the reason this screen exists, stays.
      expect(find.text('1 link'), findsOneWidget);
      // ...and the toggle keeps working as icons.
      expect(find.text('Cards'), findsNothing);
      expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Source'), findsNothing);
    });
  });

  testWidgets('a focus node from the parent drives the search box',
      (tester) async {
    // MainView owns this node so Cmd+F can reach the schema search box while
    // the generator's own field is offstage in the IndexedStack.
    final node = FocusNode();
    addTearDown(node.dispose);

    await _pumpSchemaView(tester, searchFocusNode: node);
    node.requestFocus();
    await tester.pumpAndSettle();

    expect(node.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField).first, 'cusCode');
    await tester.pumpAndSettle();
    expect(find.text('dJobs'), findsNothing);
  });

  testWidgets('a table with long column names does not overflow its card',
      (tester) async {
    // Import tables carry names like ZMYFLO_MATMAS_CNTRL.SEGMENT, one per chip
    // row, so the preview needs more rows than the fixed-height card has. Wrap
    // overflows silently (only Flex reports it), so the assertion is geometric:
    // no chip may paint outside the box that holds it.
    final schema = SchemaService()
      ..parseDataSourcesString('''
<Application><DataSourceRepository><DataObjects>
  <DataObject id="1" name="CSRMATZMYFLO_IDOC" PhysicalName="CSRMATZMYFLO_IDOC"
              data_source="Default XML Database">
    <Columns>
      <Column id="1" name="ZMYFLO_MATMAS_CNTRL.SEGMENT.HEADER"/>
      <Column id="2" name="ZMYFLO_COND_ZSMC_CNTRL.SEGMENT.DETAIL"/>
      <Column id="3" name="MATERIAL_DESCRIPTION_LONG_TEXT_FIELD"/>
      <Column id="4" name="CUSTOMER_NUMBER_QUALIFIER_SEGMENT"/>
      <Column id="5" name="ZMYFLO_MATMAS_CNTRL.SEGMENT.TRAILER"/>
      <Column id="6" name="EXTRA_COLUMN_BEYOND_THE_PREVIEW"/>
    </Columns>
  </DataObject>
</DataObjects></DataSourceRepository></Application>
''');

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: SchemaView(
          schemaService: schema,
          graph: SchemaGraph.from(const [
            SchemaRelationship(
              fromTable: 'CSRMATZMYFLO_IDOC',
              fromColumn: 'MATERIAL_DESCRIPTION_LONG_TEXT_FIELD',
              toTable: 'CSRMATZMYFLO_IDOC',
              toColumn: 'CUSTOMER_NUMBER_QUALIFIER_SEGMENT',
              programs: ['Import Materials'],
            ),
          ]),
          isScanning: false,
          scanDone: 0,
          scanTotal: 0,
          onRescan: () {},
          onOpenProgram: null,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('CSRMATZMYFLO_IDOC'), findsOneWidget);
    expect(find.text('2 relationships'), findsOneWidget);

    // Every chip must sit inside the chip area. Without the clip the area is
    // pinned to the leftover card height while the chips lay out well past it,
    // painting over the relationship count and the card's bottom edge.
    final chipArea = tester.getRect(find.byType(Wrap).first);
    for (final name in const [
      'ZMYFLO_MATMAS_CNTRL.SEGMENT.HEADER',
      'ZMYFLO_MATMAS_CNTRL.SEGMENT.TRAILER',
    ]) {
      expect(tester.getRect(find.text(name)).bottom,
          lessThanOrEqualTo(chipArea.bottom),
          reason: '$name paints outside the chip area');
    }
  });

  testWidgets('the browser stays usable while the scan is still running',
      (tester) async {
    await _pumpSchemaView(
      tester,
      graph: SchemaGraph.empty,
      isScanning: true,
    );

    expect(
      find.textContaining('Scanning program logic for table relationships'),
      findsOneWidget,
    );
    expect(find.text('dJobs'), findsOneWidget);
  });
}
