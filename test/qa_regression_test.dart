// Regression: ISSUE-001, ISSUE-002, ISSUE-003 — found by /qa on 2026-08-30
// Report: .gstack/qa-reports/qa-report-magicsoftsql-2026-08-30.md
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {

  // ISSUE-001 — the parameter inspector's inputs had onChanged but no
  // onSubmitted, so pressing Enter in one did nothing, while the manual
  // ("Press Enter or click Generate SQL"), the About sheet and the README all
  // promised it re-synthesized the query.
  //
  // Asserted against the source rather than the widget tree on purpose: the
  // parameters inspector only renders once a program with parameters is
  // selected, which needs a UniPaaS repository on disk. A pumped MainView in
  // CI has exactly one TextField (the search box), so a widget-level version
  // of this check inspects nothing and passes while the bug ships.
  group('ISSUE-001 parameter inputs submit on Enter', () {
    test('the parameter value field wires up onSubmitted', () {
      final source = File('lib/views/main_view.dart').readAsStringSync();

      // The parameter input is the field hinted "NULL"; find its declaration.
      final hint = source.indexOf("hintText: 'NULL'");
      expect(hint, greaterThan(-1),
          reason: 'parameter value field not found — did the hint text change?');

      final open = source.lastIndexOf('TextField(', hint);
      expect(open, greaterThan(-1));

      final declaration = source.substring(open, hint);
      expect(
        declaration.contains('onSubmitted:'),
        isTrue,
        reason: 'Enter in a parameter field must re-synthesize the query; the '
            'manual, the About sheet and the README all promise it does',
      );
    });
  });

  // ISSUE-002 — the repository-position badge lived in a 30px box. At Fira
  // Code 10.5 a 4-digit position ("#5428") overflowed and wrapped, rendering
  // as "#542" with a stray "8" beneath it, so the list showed a different,
  // smaller number than the detail header for the same program.
  //
  // Source-asserted for the same reason as ISSUE-001: without a repository on
  // disk the programs list is empty, so a widget-level check finds no badges
  // and passes against the unfixed code.
  group('ISSUE-002 program position badge never wraps', () {
    test('the badge is single-line and its box fits the widest position', () {
      final source = File('lib/views/main_view.dart').readAsStringSync();

      final badge = source.indexOf(r"'#${_programNumber(prog, index)}'");
      expect(badge, greaterThan(-1),
          reason: 'program position badge not found — did it get renamed?');

      // Walk back to the SizedBox that constrains it, and forward to the end
      // of the Text() that renders it.
      final boxStart = source.lastIndexOf('SizedBox(', badge);
      expect(boxStart, greaterThan(-1));
      final block = source.substring(boxStart, source.indexOf('),', badge));

      final width = RegExp(r'width:\s*([0-9.]+)').firstMatch(block);
      expect(width, isNotNull, reason: 'badge box has no explicit width');
      // Fira Code advances ~0.6em, so at fontSize 10.5 the widest badge this
      // app can render ("#99999") needs ~37.8px. 30 wrapped "#5428" onto two
      // lines, so the list read "#542" with a stray "8" under it.
      expect(double.parse(width!.group(1)!), greaterThanOrEqualTo(38.0),
          reason: 'badge box too narrow: a 4-digit position will wrap');

      expect(block.contains('maxLines: 1'), isTrue,
          reason: 'badge must be pinned to a single line');
      expect(block.contains('softWrap: false'), isTrue,
          reason: 'badge must not soft-wrap');
    });
  });

  // ISSUE-003 — the source-folder fallback chain hardcoded absolute paths
  // from a developer's machine, including a Windows path that could exist on
  // a customer's disk and silently point the app at unrelated files.
  group('ISSUE-003 no developer machine paths ship in the fallback chain', () {
    test('main_view.dart contains no absolute /Users or drive-letter paths',
        () {
      final source = File('lib/views/main_view.dart').readAsStringSync();

      final offenders = <String>[];
      for (final line in const LineSplitter().convert(source)) {
        final code = line.trimLeft();
        if (code.startsWith('//')) continue; // prose about the fix is fine
        if (RegExp(r"""['"]/Users/""").hasMatch(code) ||
            RegExp(r"""['"][a-zA-Z]:\\""").hasMatch(code)) {
          offenders.add(line.trim());
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'absolute machine-specific paths must not ship: $offenders',
      );
    });
  });
}
