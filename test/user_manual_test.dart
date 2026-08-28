import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_sql_converter/models/manual_topic.dart';
import 'package:flutter_sql_converter/views/dialogs/user_manual_data.dart';
import 'package:flutter_sql_converter/views/dialogs/user_manual_dialog.dart';
import 'package:flutter_sql_converter/views/main_view.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('ManualTopic & ManualSection Models', () {
    test('ManualSection equality and copyWith', () {
      const sec1 = ManualSection(
        title: 'Title A',
        description: 'Desc A',
        steps: ['Step 1', 'Step 2'],
        tip: 'Tip A',
        shortcuts: ['Cmd + G'],
        tags: ['SQL'],
      );

      final sec2 = sec1.copyWith();
      expect(sec1, equals(sec2));
      expect(sec1.hashCode, equals(sec2.hashCode));

      final sec3 = sec1.copyWith(title: 'Title B');
      expect(sec1 == sec3, isFalse);
      expect(sec3.title, 'Title B');
      expect(sec3.steps, ['Step 1', 'Step 2']);
    });

    test('ManualTopic equality and copyWith', () {
      const topic1 = ManualTopic(
        id: 'test_id',
        title: 'Test Topic',
        subtitle: 'Test Subtitle',
        icon: Icons.star,
        badge: 'Core',
        keywords: ['test', 'topic'],
        sections: [
          ManualSection(
            title: 'Section 1',
            description: 'Section 1 Description',
          ),
        ],
      );

      final topic2 = topic1.copyWith();
      expect(topic1, equals(topic2));
      expect(topic1.hashCode, equals(topic2.hashCode));

      final topic3 = topic1.copyWith(title: 'New Title');
      expect(topic1 == topic3, isFalse);
      expect(topic3.title, 'New Title');
    });

    test('ManualTopic.matches() comprehensively matches queries across fields', () {
      const topic = ManualTopic(
        id: 'sql_gen',
        title: 'SQL Generator',
        subtitle: 'Synthesize T-SQL Queries',
        icon: Icons.terminal,
        badge: 'Core Tool',
        keywords: ['declare', 'injection'],
        sections: [
          ManualSection(
            title: 'Join Conditions',
            description: 'Mapping LNK elements to LEFT JOIN',
            steps: ['Open program', 'Click generate'],
            tip: 'Use parameter injection for testing',
            shortcuts: ['Cmd + G', 'Ctrl + G'],
            tags: ['OuterJoin', 'MSSQL'],
          ),
        ],
      );

      // Empty query
      expect(topic.matches(''), isTrue);
      expect(topic.matches('   '), isTrue);

      // Matches ID, Title, Subtitle, Badge, Keywords
      expect(topic.matches('sql_gen'), isTrue);
      expect(topic.matches('GENERATOR'), isTrue);
      expect(topic.matches('synthesize'), isTrue);
      expect(topic.matches('core tool'), isTrue);
      expect(topic.matches('declare'), isTrue);

      // Matches Section Title, Description, Steps, Tip, Shortcuts, Tags
      expect(topic.matches('join conditions'), isTrue);
      expect(topic.matches('mapping lnk'), isTrue);
      expect(topic.matches('click generate'), isTrue);
      expect(topic.matches('injection for testing'), isTrue);
      expect(topic.matches('cmd + g'), isTrue);
      expect(topic.matches('outerjoin'), isTrue);

      // Unmatched query
      expect(topic.matches('nonexistent_query_xyz'), isFalse);
    });
  });

  group('UserManualData Central Repository', () {
    test('contains all expected core documentation topics with valid structure', () {
      expect(UserManualData.topics, isNotEmpty);
      expect(UserManualData.topics.length, greaterThanOrEqualTo(8));

      final ids = UserManualData.topics.map((t) => t.id).toSet();
      expect(ids.length, equals(UserManualData.topics.length),
          reason: 'All topic IDs must be unique');

      // Verify essential topics exist
      expect(ids.contains('getting_started'), isTrue);
      expect(ids.contains('sql_generator'), isTrue);
      expect(ids.contains('parameters'), isTrue);
      expect(ids.contains('program_tree'), isTrue);
      expect(ids.contains('schema_browser'), isTrue);
      expect(ids.contains('expressions'), isTrue);
      expect(ids.contains('shortcuts'), isTrue);
      expect(ids.contains('troubleshooting'), isTrue);

      for (final topic in UserManualData.topics) {
        expect(topic.id, isNotEmpty);
        expect(topic.title, isNotEmpty);
        expect(topic.subtitle, isNotEmpty);
        expect(topic.sections, isNotEmpty);

        for (final section in topic.sections) {
          expect(section.title, isNotEmpty);
          expect(section.description, isNotEmpty);
        }
      }
    });

    test('getTopicById returns matching topic or null', () {
      final topic = UserManualData.getTopicById('shortcuts');
      expect(topic, isNotNull);
      expect(topic!.id, 'shortcuts');
      expect(topic.title, contains('Keyboard Shortcuts'));

      final missing = UserManualData.getTopicById('non_existent');
      expect(missing, isNull);
    });
  });

  group('UserManualDialog Widget Tests', () {
    Widget createDialogTestbed({String? initialTopicId}) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => UserManualDialog.show(
                context,
                initialTopicId: initialTopicId,
              ),
              child: const Text('Open Manual'),
            ),
          ),
        ),
      );
    }

    testWidgets('renders topic list and selects first topic by default',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createDialogTestbed());
      await tester.tap(find.text('Open Manual'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('User Manual & Knowledge Base'), findsOneWidget);
      expect(find.text('Getting Started & Overview'), findsWidgets);
      expect(find.text('System Architecture & Purpose'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('switches selected topic when a sidebar item is tapped',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createDialogTestbed());
      await tester.tap(find.text('Open Manual'));
      await tester.pump(const Duration(milliseconds: 300));

      // Tap on 'SQL Query Generator' in sidebar
      final sqlGeneratorItem = find.text('SQL Query Generator');
      expect(sqlGeneratorItem, findsOneWidget);
      await tester.tap(sqlGeneratorItem);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Interactive Query Workbench'), findsOneWidget);
      expect(find.text('Parameter Generation Modes'), findsOneWidget);
    });

    testWidgets('supports deep-linking to initialTopicId', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createDialogTestbed(initialTopicId: 'shortcuts'));
      await tester.tap(find.text('Open Manual'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Global Application Hotkeys'), findsOneWidget);
      expect(find.text('Editor & Dialog Navigation'), findsOneWidget);
    });

    testWidgets('live search filters topics and handles empty state with reset',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createDialogTestbed());
      await tester.tap(find.text('Open Manual'));
      await tester.pump(const Duration(milliseconds: 300));

      // Enter search query that matches 'expressions'
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Transpilation');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Expressions & Magic Translation'), findsWidgets);
      expect(find.text('UniPaaS Expression Transpilation'), findsOneWidget);

      // Enter search query that matches nothing
      await tester.enterText(searchField, 'completely_unknown_search_term_123');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No matching topics'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);

      // Click Clear Search
      await tester.tap(find.text('Clear Search'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Getting Started & Overview'), findsWidgets);
      expect(find.text('No matching topics'), findsNothing);
    });

    testWidgets('footer keyboard shortcuts button jumps directly to shortcuts topic',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createDialogTestbed());
      await tester.tap(find.text('Open Manual'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Getting Started & Overview'), findsWidgets);

      final shortcutsFooterBtn =
          find.widgetWithText(OutlinedButton, 'Keyboard Shortcuts');
      expect(shortcutsFooterBtn, findsOneWidget);
      await tester.tap(shortcutsFooterBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Global Application Hotkeys'), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createDialogTestbed());
      await tester.tap(find.text('Open Manual'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('User Manual & Knowledge Base'), findsOneWidget);

      final closeBtn = find.widgetWithText(ElevatedButton, 'Close');
      await tester.tap(closeBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('User Manual & Knowledge Base'), findsNothing);
    });
  });

  group('MainView Manual Integration Tests', () {
    testWidgets('header includes Manual button and clicking it opens UserManualDialog',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MainView(onToggleTheme: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Find the Manual button in header
      final manualButton = find.byTooltip('User Guide & Manual (F1)');
      expect(manualButton, findsOneWidget);

      await tester.tap(manualButton);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('User Manual & Knowledge Base'), findsOneWidget);
      expect(find.text('Getting Started & Overview'), findsWidgets);
    });

    testWidgets('About App dialog includes button to open User Manual',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MainView(onToggleTheme: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Open About Dialog
      final aboutButton = find.byTooltip('About MagicSoftSQL');
      expect(aboutButton, findsOneWidget);
      await tester.tap(aboutButton);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('MagicSoftSQL'), findsWidgets);
      expect(find.text('User Manual (F1)'), findsOneWidget);

      // Tap User Manual from About Dialog
      await tester.tap(find.text('User Manual (F1)'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('User Manual & Knowledge Base'), findsOneWidget);
    });

    testWidgets('F1 key press opens UserManualDialog contextually',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MainView(onToggleTheme: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Send F1 key event
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('User Manual & Knowledge Base'), findsOneWidget);
    });
  });
}
