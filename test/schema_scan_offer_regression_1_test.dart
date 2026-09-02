// Regression: ISSUE-001 — re-applying the source folder while the schema
// browser was the visible tab cleared the relationship graph and neither
// reloaded the cached one nor offered a scan, leaving every table linkless
// with no way back short of toggling tabs.
// Found by /qa on 2026-09-02
// Report: .gstack/qa-reports/qa-report-magicsoftsql-2026-09-02.md
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Asserted against the source on purpose, for the same reason as
// qa_regression_test.dart: _loadCachedRelationships and the folder sweep
// both return early under FLUTTER_TEST, so a pumped MainView can neither
// clear the graph nor raise the offer, and a widget-level check would pass
// with the bug in place.
String _methodBody(String source, String signature, String nextSignature) {
  final start = source.indexOf(signature);
  expect(start, greaterThan(-1), reason: '$signature not found in main_view');
  final end = source.indexOf(nextSignature, start);
  expect(end, greaterThan(start), reason: '$nextSignature not found after $signature');
  return source.substring(start, end);
}

void main() {
  final source = File('lib/views/main_view.dart').readAsStringSync();

  group('ISSUE-001 folder sweep re-offers the relationship scan', () {
    test('the folder sweep clears the pending offer', () {
      final body = _methodBody(
        source,
        'Future<void> _scanSourceDirectory(',
        'Future<void> _rescanAndRefresh(',
      );
      expect(body.contains('_relationshipScanPending = false'), isTrue,
          reason: 'a new folder must drop the offer that belonged to the old one');
      expect(body.contains('_hasScannedRelationships = false'), isTrue);
    });

    test('the folder sweep puts the offer back when the schema tab is showing',
        () {
      final body = _methodBody(
        source,
        'Future<void> _scanSourceDirectory(',
        'Future<void> _rescanAndRefresh(',
      );
      final reset = body.indexOf('_relationshipScanPending = false');
      final reload = body.indexOf('_loadCachedRelationships()', reset);
      expect(reload, greaterThan(reset),
          reason: 'after clearing the graph the sweep must re-run the cached '
              'graph check, or the schema tab shows tables without links and '
              'no scan button until the user happens to switch tabs');

      final guard = body.lastIndexOf('_mode == AppMode.schema', reload);
      expect(guard, greaterThan(reset),
          reason: 'the re-check belongs to the visible schema tab only; the '
              'generator tab must not start fingerprinting on every folder change');
    });

    test('switching to the schema tab still runs the cached graph check', () {
      final body = _methodBody(
        source,
        'void _switchMode(AppMode mode)',
        'Future<void> _loadCachedRelationships()',
      );
      expect(body.contains('_loadCachedRelationships()'), isTrue,
          reason: 'the tab switch is the other path that raises the offer');
      expect(body.contains('_ensureRelationshipScan('), isFalse,
          reason: 'opening the schema tab must offer the sweep, never start it');
    });
  });
}
