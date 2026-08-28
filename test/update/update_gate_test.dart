import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sql_converter/services/update/update_controller.dart';
import 'package:flutter_sql_converter/services/update/update_info.dart';
import 'package:flutter_sql_converter/services/update/update_service.dart';
import 'package:flutter_sql_converter/widgets/update_gate.dart';

Map<String, dynamic> release(String tag) => {
      'tag_name': tag,
      'html_url': 'https://example.com/releases/$tag',
      'assets': <dynamic>[],
    };

UpdateController controllerWith({
  String latestTag = 'v1.1.0',
  UpdatePlatform platform = UpdatePlatform.macos,
}) {
  return UpdateController(
    service: UpdateService(
      currentVersion: '1.0.0',
      platform: platform,
      fetchRelease: (_) async => release(latestTag),
    ),
  );
}

Widget host(UpdateController controller) {
  return MaterialApp(
    home: UpdateGate(
      controller: controller,
      child: const Scaffold(body: Text('app body')),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the update dialog when a newer release exists', (
    tester,
  ) async {
    await tester.pumpWidget(host(controllerWith()));
    await tester.pumpAndSettle();

    expect(find.text('app body'), findsOneWidget);
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.textContaining('1.1.0'), findsWidgets);
    expect(find.textContaining('1.0.0'), findsWidgets);
  });

  testWidgets('shows nothing when up to date', (tester) async {
    await tester.pumpWidget(host(controllerWith(latestTag: 'v1.0.0')));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
  });

  testWidgets('Later closes the dialog for the session', (tester) async {
    final controller = controllerWith();
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
    expect(controller.availableUpdate, isNull);
    // Nothing persisted: "Later" is session-only.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update_skipped_version'), isNull);
  });

  testWidgets('Skip persists the skipped version', (tester) async {
    final controller = controllerWith();
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update_skipped_version'), '1.1.0');
  });

  testWidgets('non-Windows platforms offer Download, not silent install', (
    tester,
  ) async {
    await tester.pumpWidget(host(controllerWith()));
    await tester.pumpAndSettle();

    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Install & Restart'), findsNothing);
  });

  testWidgets('Windows with an installer asset offers Install & Restart', (
    tester,
  ) async {
    final controller = UpdateController(
      service: UpdateService(
        currentVersion: '1.0.0',
        platform: UpdatePlatform.windows,
        fetchRelease: (_) async => {
          'tag_name': 'v1.1.0',
          'html_url': 'https://example.com/releases/v1.1.0',
          'assets': [
            {
              'name': 'MagicSoftSQL-x86_64-1.1.0-Installer.exe',
              'browser_download_url': 'https://example.com/installer.exe',
              'size': 10,
            },
          ],
        },
      ),
    );
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    expect(find.text('Install & Restart'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });
}
