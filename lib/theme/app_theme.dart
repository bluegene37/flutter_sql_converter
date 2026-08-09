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
    sqlText: Color(0xFF38BDF8),
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

  static const light = AppColors._(
    brightness: Brightness.light,
    scaffoldBg: Color(0xFFF8FAFC),
    headerBg: Color(0xFFFFFFFF),
    panelBg: Color(0xFFF1F5F9),
    cardBg: Color(0xFFFFFFFF),
    codeBg: Color(0xFFF8FAFC),
    border: Color(0xFFE2E8F0),
    borderSubtle: Color(0xFFCBD5E1),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    textMuted: Color(0xFF94A3B8),
    textOnAccent: Colors.white,
    accent: Color(0xFF0891B2),
    accentSecondary: Color(0xFF2563EB),
    accentIcon: Color(0xFF0284C7),
    sqlText: Color(0xFF0369A1),
    successBg: Color(0xFFDCFCE7),
    successBorder: Color(0xFF16A34A),
    successText: Color(0xFF15803D),
    selectedBg: Color(0xFFE0F2FE),
    selectedBorder: Color(0xFF0891B2),
    hoverBg: Color(0xFFE2E8F0),
    chipBg: Color(0xFFE2E8F0),
    disabledBg: Color(0xFFE2E8F0),
    paramBadgeBg: Color(0xFFDBEAFE),
    paramBadgeBorder: Color(0xFF93C5FD),
    paramBadgeText: Color(0xFF1E40AF),
    varBadgeBg: Color(0xFFF1F5F9),
    varBadgeBorder: Color(0xFFCBD5E1),
    varBadgeText: Color(0xFF475569),
    inputBg: Color(0xFFFFFFFF),
    inputHint: Color(0xFF94A3B8),
    inputFocusBorder: Color(0xFF0891B2),
    snackbarBg: Color(0xFF0F172A),
    snackbarText: Colors.white,
  );

  /// Get the [AppColors] for the current theme brightness.
  static AppColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? dark : light;
  }
}
