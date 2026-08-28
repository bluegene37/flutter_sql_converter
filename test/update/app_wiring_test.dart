import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sql_converter/main.dart';
import 'package:flutter_sql_converter/widgets/update_check_button.dart';
import 'package:flutter_sql_converter/widgets/update_gate.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('UpdateGate is mounted once on the stable root screen', (
    tester,
  ) async {
    await tester.pumpWidget(const UniPaasConverterApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(UpdateGate), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('header exposes a Check for updates button', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const UniPaasConverterApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(UpdateCheckButton), findsOneWidget);
    expect(find.byTooltip('Check for updates'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
