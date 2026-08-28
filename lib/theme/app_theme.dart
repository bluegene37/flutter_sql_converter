import 'package:flutter/material.dart';

/// Centralized semantic color tokens for light and dark themes.
class AppColors {
  final Brightness brightness;

  // Backgrounds
  final Color scaffoldBg;
  final Color headerBg;
  final Color panelBg;
  final Color cardBg;
  final Color codeBg;

  // Borders
  final Color border;
  final Color borderSubtle;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnAccent;

  // Accent colors
  final Color accent;
  final Color accentSecondary;
  final Color accentIcon;

  // SQL output
  final Color sqlText;

  // SQL syntax. The generated query is the product, so it gets a real palette
  // rather than a single flat colour.
  final Color syntaxKeyword;
  final Color syntaxString;
  final Color syntaxParam;
  final Color syntaxNumber;
  final Color syntaxComment;
  final Color syntaxCommentStrong;
  final Color syntaxPunctuation;
  final Color gutterText;
  final Color gutterLine;

  // Stat pills
  final Color statTasks;
  final Color statJoins;

  // Status
  final Color successBg;
  final Color successBorder;
  final Color successText;

  // Interactive
  final Color selectedBg;
  final Color selectedBorder;
  final Color hoverBg;
  final Color chipBg;
  final Color disabledBg;

  // Parameter badges
  final Color paramBadgeBg;
  final Color paramBadgeBorder;
  final Color paramBadgeText;
  final Color varBadgeBg;
  final Color varBadgeBorder;
  final Color varBadgeText;

  // Input fields
  final Color inputBg;
  final Color inputHint;
  final Color inputFocusBorder;

  // Snackbar
  final Color snackbarBg;
  final Color snackbarText;

  const AppColors._({
    required this.brightness,
    required this.scaffoldBg,
    required this.headerBg,
    required this.panelBg,
    required this.cardBg,
    required this.codeBg,
    required this.border,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnAccent,
    required this.accent,
    required this.accentSecondary,
    required this.accentIcon,
    required this.sqlText,
    required this.syntaxKeyword,
    required this.syntaxString,
    required this.syntaxParam,
    required this.syntaxNumber,
    required this.syntaxComment,
    required this.syntaxCommentStrong,
    required this.syntaxPunctuation,
    required this.gutterText,
    required this.gutterLine,
    required this.statTasks,
    required this.statJoins,
    required this.successBg,
    required this.successBorder,
    required this.successText,
    required this.selectedBg,
    required this.selectedBorder,
    required this.hoverBg,
    required this.chipBg,
    required this.disabledBg,
    required this.paramBadgeBg,
    required this.paramBadgeBorder,
    required this.paramBadgeText,
    required this.varBadgeBg,
    required this.varBadgeBorder,
    required this.varBadgeText,
    required this.inputBg,
    required this.inputHint,
    required this.inputFocusBorder,
    required this.snackbarBg,
    required this.snackbarText,
  });

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppColors._(
    brightness: Brightness.dark,
    scaffoldBg: Color(0xFF0B0F19),
    headerBg: Color(0xFF111827),
    panelBg: Color(0xFF0F172A),
    cardBg: Color(0xFF1E293B),
    codeBg: Color(0xFF0B0F19),
    border: Color(0xFF1E293B),
    borderSubtle: Color(0xFF334155),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    textOnAccent: Colors.white,
    accent: Color(0xFF06B6D4),
    accentSecondary: Color(0xFF3B82F6),
    accentIcon: Color(0xFF38BDF8),
    // Body text of the query reads calm; colour is reserved for meaning.
    sqlText: Color(0xFFE2E8F0),
    syntaxKeyword: Color(0xFF38BDF8),
    syntaxString: Color(0xFFFCD34D),
    syntaxParam: Color(0xFFC084FC),
    syntaxNumber: Color(0xFFFB923C),
    syntaxComment: Color(0xFF64748B),
    syntaxCommentStrong: Color(0xFF94A3B8),
    syntaxPunctuation: Color(0xFF64748B),
    gutterText: Color(0xFF3F4C63),
    gutterLine: Color(0xFF1E293B),
    statTasks: Color(0xFF22D3EE),
    statJoins: Color(0xFFC084FC),
    successBg: Color(0xFF064E3B),
    successBorder: Color(0xFF059669),
    successText: Color(0xFF34D399),
    selectedBg: Color(0xFF1E293B),
    selectedBorder: Color(0xFF06B6D4),
    hoverBg: Color(0xFF334155),
    chipBg: Color(0xFF1E293B),
    disabledBg: Color(0xFF1E293B),
    paramBadgeBg: Color(0xFF1E3A8A),
    paramBadgeBorder: Color(0xFF2563EB),
    paramBadgeText: Color(0xFF93C5FD),
    varBadgeBg: Color(0xFF334155),
    varBadgeBorder: Color(0xFF475569),
    varBadgeText: Color(0xFFCBD5E1),
    inputBg: Color(0xFF1E293B),
    inputHint: Color(0xFF475569),
    inputFocusBorder: Color(0xFF06B6D4),
    snackbarBg: Color(0xFF1E293B),
    snackbarText: Colors.white,
  );

  // Light mode follows the genexis.dev "paper & ink" palette: warm cream
  // surfaces, near-black ink text, terracotta accent.
  static const light = AppColors._(
    brightness: Brightness.light,
    scaffoldBg: Color(0xFFF2EDE3), // paper
    headerBg: Color(0xFFFAF7F0), // paper-raised
    panelBg: Color(0xFFE7E0D0), // paper-deep
    cardBg: Color(0xFFFAF7F0),
    codeBg: Color(0xFFFAF7F0),
    border: Color(0xFFDED6C4), // paper-recess
    borderSubtle: Color(0xFFC7BEA9),
    textPrimary: Color(0xFF16161A), // ink
    textSecondary: Color(0xFF5A564E), // ink-soft
    textMuted: Color(0xFF9A9384),
    textOnAccent: Color(0xFFFAF7F0),
    accent: Color(0xFFB4402C), // lead
    accentSecondary: Color(0xFF8E3122), // lead-deep
    accentIcon: Color(0xFFB4402C),
    sqlText: Color(0xFF16161A),
    syntaxKeyword: Color(0xFF8E3122),
    syntaxString: Color(0xFF79740E),
    syntaxParam: Color(0xFF8F3F71),
    syntaxNumber: Color(0xFFAF3A03),
    syntaxComment: Color(0xFF9A9384),
    syntaxCommentStrong: Color(0xFF66625A), // graphite
    syntaxPunctuation: Color(0xFF9A9384),
    gutterText: Color(0xFFB5AD9A),
    gutterLine: Color(0xFFDED6C4),
    statTasks: Color(0xFF8E3122),
    statJoins: Color(0xFF8F3F71),
    successBg: Color(0xFFE5E8D3),
    successBorder: Color(0xFF7B8447),
    successText: Color(0xFF556130),
    selectedBg: Color(0xFFEFDCD3), // lead-wash over paper
    selectedBorder: Color(0xFFB4402C),
    hoverBg: Color(0xFFE7E0D0),
    chipBg: Color(0xFFE7E0D0),
    disabledBg: Color(0xFFE7E0D0),
    paramBadgeBg: Color(0xFFF2DDD5),
    paramBadgeBorder: Color(0xFFD9A08F),
    paramBadgeText: Color(0xFF8E3122),
    varBadgeBg: Color(0xFFE7E0D0),
    varBadgeBorder: Color(0xFFC7BEA9),
    varBadgeText: Color(0xFF5A564E),
    inputBg: Color(0xFFFAF7F0),
    inputHint: Color(0xFF9A9384),
    inputFocusBorder: Color(0xFFB4402C),
    snackbarBg: Color(0xFF2B2B2E), // crease
    snackbarText: Color(0xFFFAF7F0),
  );

  /// Get the [AppColors] for the current theme brightness.
  static AppColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? dark : light;
  }
}
