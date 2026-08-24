import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// The generated query, with a line gutter and semantic colouring.
///
/// Colour carries meaning rather than decoration: `@parameters` are the values
/// the query depends on, so they read loudest; the provenance comments the
/// generator writes recede so they never compete with the SQL itself.
///
/// Lines are never wrapped — one logical line is one visual line, which keeps
/// the gutter honest and matches how the query is read beside uniPaaS.
class SqlView extends StatefulWidget {
  final String sql;

  const SqlView({super.key, required this.sql});

  @override
  State<SqlView> createState() => _SqlViewState();
}

class _SqlViewState extends State<SqlView> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sql = widget.sql;
    final colors = AppColors.of(context);
    final lines = sql.split('\n');

    final codeStyle = GoogleFonts.firaCode(
      color: colors.sqlText,
      fontSize: 13,
      height: 1.6,
    );
    final gutterStyle = GoogleFonts.firaCode(
      color: colors.gutterText,
      fontSize: 12,
      height: 1.6 * 13 / 12, // match the code line box exactly
    );

    final gutterWidth = 28.0 + lines.length.toString().length * 8.0;

    return Container(
      color: colors.codeBg,
      child: Scrollbar(
        controller: _vertical,
        child: SingleChildScrollView(
          controller: _vertical,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: gutterWidth,
                  padding: const EdgeInsets.only(top: 20, bottom: 20, right: 12),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: colors.gutterLine)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        Text('${i + 1}', style: gutterStyle),
                    ],
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _horizontal,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 32, 24),
                        child: SelectableText.rich(
                          TextSpan(
                            style: codeStyle,
                            children: _highlight(sql, colors, codeStyle),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const Set<String> _keywords = {
  'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'INNER', 'LEFT', 'RIGHT',
  'FULL', 'OUTER', 'JOIN', 'ON', 'ORDER', 'BY', 'GROUP', 'HAVING', 'INSERT',
  'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'DECLARE', 'AS', 'TOP', 'APPLY',
  'CROSS', 'WITH', 'NOLOCK', 'IF', 'EXISTS', 'BEGIN', 'END', 'BETWEEN', 'IS',
  'NULL', 'DESC', 'ASC', 'CASE', 'WHEN', 'THEN', 'ELSE', 'CAST', 'CONVERT',
  'DISTINCT', 'UNION', 'ALL', 'IN', 'LIKE', 'EXEC', 'RETURN', 'PRINT',
  'INT', 'BIGINT', 'NVARCHAR', 'VARCHAR', 'DECIMAL', 'NUMERIC', 'DATETIME',
  'DATE', 'TIME', 'BIT', 'MAX',
};

bool _isWordStart(String c) => RegExp(r'[A-Za-z_]').hasMatch(c);
bool _isWordPart(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);
bool _isDigit(String c) => RegExp(r'[0-9]').hasMatch(c);

/// Splits the query into coloured spans. The text itself is never altered, so
/// selecting and copying still yields exactly what the generator produced.
List<TextSpan> _highlight(String sql, AppColors colors, TextStyle base) {
  final spans = <TextSpan>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString()));
    buffer.clear();
  }

  void emit(String text, Color color, {FontWeight? weight}) {
    flush();
    spans.add(TextSpan(
      text: text,
      style: TextStyle(color: color, fontWeight: weight),
    ));
  }

  var i = 0;
  while (i < sql.length) {
    final ch = sql[i];

    // Comment to end of line. Banner and heading comments read a shade
    // stronger so the section breaks stay findable while scrolling.
    if (ch == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      var end = sql.indexOf('\n', i);
      if (end == -1) end = sql.length;
      final text = sql.substring(i, end);
      final isBanner = text.contains('===') ||
          text.contains('---') ||
          RegExp(r'^--\s*(Main|Child) Task').hasMatch(text);
      emit(text, isBanner ? colors.syntaxCommentStrong : colors.syntaxComment,
          weight: isBanner ? FontWeight.w500 : null);
      i = end;
      continue;
    }

    // String literal, with '' as the escape.
    if (ch == "'") {
      var j = i + 1;
      while (j < sql.length) {
        if (sql[j] == "'") {
          if (j + 1 < sql.length && sql[j + 1] == "'") {
            j += 2;
            continue;
          }
          j++;
          break;
        }
        j++;
      }
      emit(sql.substring(i, j), colors.syntaxString);
      i = j;
      continue;
    }

    // Parameter: the value the query is waiting on.
    if (ch == '@' && i + 1 < sql.length && _isWordStart(sql[i + 1])) {
      var j = i + 1;
      while (j < sql.length && _isWordPart(sql[j])) {
        j++;
      }
      emit(sql.substring(i, j), colors.syntaxParam, weight: FontWeight.w500);
      i = j;
      continue;
    }

    // Bracketed identifier: mute the brackets, keep the name legible.
    if (ch == '[') {
      final close = sql.indexOf(']', i);
      if (close != -1 && !sql.substring(i, close).contains('\n')) {
        emit('[', colors.syntaxPunctuation);
        emit(sql.substring(i + 1, close), colors.sqlText);
        emit(']', colors.syntaxPunctuation);
        i = close + 1;
        continue;
      }
    }

    if (_isDigit(ch)) {
      var j = i;
      while (j < sql.length && (_isDigit(sql[j]) || sql[j] == '.')) {
        j++;
      }
      emit(sql.substring(i, j), colors.syntaxNumber);
      i = j;
      continue;
    }

    if (_isWordStart(ch)) {
      var j = i;
      while (j < sql.length && _isWordPart(sql[j])) {
        j++;
      }
      final word = sql.substring(i, j);
      if (_keywords.contains(word.toUpperCase())) {
        emit(word, colors.syntaxKeyword, weight: FontWeight.w600);
      } else {
        buffer.write(word);
      }
      i = j;
      continue;
    }

    if ('(),;=<>+*/.'.contains(ch)) {
      emit(ch, colors.syntaxPunctuation);
      i++;
      continue;
    }

    buffer.write(ch);
    i++;
  }

  flush();
  return spans;
}
