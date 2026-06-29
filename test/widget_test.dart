import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_sql_converter/main.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('App launches and displays loading indicator while loading schema', (WidgetTester tester) async {
    await tester.pumpWidget(const UniPaasConverterApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
