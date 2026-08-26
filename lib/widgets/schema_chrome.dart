import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Thousands separators, so a five-figure count reads at a glance.
String formatCount(int n) {
  final digits = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Colour families for the SQL types the schema browser shows, so a column
/// list can be read by shape before it is read by name.
Color sqlTypeColor(String sqlType, AppColors colors) {
  final type = sqlType.toUpperCase();
  if (type.startsWith('INT') || type.startsWith('BIGINT')) {
    return colors.statTasks;
  }
  if (type.startsWith('DECIMAL')) return colors.syntaxNumber;
  if (type.startsWith('DATETIME') || type.startsWith('TIME')) {
    return colors.syntaxString;
  }
  if (type.startsWith('BIT')) return colors.successText;
  return colors.syntaxParam;
}

/// A pill that toggles one facet of the table filter.
class SchemaFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  const SchemaFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? colors.selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? colors.selectedBorder : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? colors.accent : colors.textSecondary,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: GoogleFonts.firaCode(
                  color: selected ? colors.accent : colors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small labelled figure, used for the table/column/relationship counts.
class SchemaStatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const SchemaStatPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A table name rendered as a clickable chip. Tapping it moves the browser to
/// that table, which is how relationships are followed.
class TablePill extends StatelessWidget {
  final String name;
  final Color color;
  final VoidCallback? onTap;

  const TablePill({
    super.key,
    required this.name,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        name,
        style: GoogleFonts.firaCode(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    if (onTap == null) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}

/// A type name rendered in its family colour.
class SqlTypeBadge extends StatelessWidget {
  final String sqlType;

  const SqlTypeBadge({super.key, required this.sqlType});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = sqlTypeColor(sqlType, colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        sqlType,
        style: GoogleFonts.firaCode(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Section heading inside the detail panel.
class SchemaSectionTitle extends StatelessWidget {
  final String title;
  final int? count;
  final IconData icon;

  const SchemaSectionTitle({
    super.key,
    required this.title,
    required this.icon,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.accentIcon),
          const SizedBox(width: 7),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 7),
            Text(
              '$count',
              style: GoogleFonts.firaCode(
                color: colors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder shown where a pane has nothing to display yet.
class SchemaEmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? detail;

  const SchemaEmptyHint({
    super.key,
    required this.icon,
    required this.message,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: colors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 5),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: colors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// Header cell of the list-style tables used across the schema browser.
class SchemaHeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final VoidCallback? onTap;
  final bool active;
  final bool ascending;
  final TextAlign align;

  const SchemaHeaderCell({
    super.key,
    required this.label,
    this.flex = 1,
    this.onTap,
    this.active = false,
    this.ascending = true,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final content = Row(
      mainAxisAlignment: align == TextAlign.right
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: active ? colors.accent : colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 3),
          Icon(
            active
                ? (ascending ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: 11,
            color: active ? colors.accent : colors.textMuted,
          ),
        ],
      ],
    );

    return Expanded(
      flex: flex,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: content,
              ),
            ),
    );
  }
}
