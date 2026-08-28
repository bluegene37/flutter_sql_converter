import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/app_info.dart';

void main() {
  test('app name matches the product name', () {
    expect(AppInfo.appName, 'MagicSoftSQL');
  });

  test('appVersion mirrors pubspec.yaml version stripped of build metadata',
      () {
    // The update checker compares AppInfo.appVersion against release tags.
    // If this constant lags behind pubspec.yaml, a fresh install re-offers
    // the version it already runs — so the two must move in lockstep.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    final pubspecVersion = match!.group(1)!.split('+').first;
    expect(AppInfo.appVersion, pubspecVersion);
  });
}
