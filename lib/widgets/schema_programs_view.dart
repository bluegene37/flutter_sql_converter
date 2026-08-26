import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/schema_relationship.dart';
import '../theme/app_theme.dart';
import 'schema_chrome.dart';

/// Programs on the left, the table links that program relies on on the right.
/// This is the "which program uses this connection" side of the browser.
class SchemaProgramsView extends StatelessWidget {
  final SchemaGraph graph;
  final List<String> programs;
  final String? selectedProgram;
  final void Function(String program) onSelect;
  final void Function(String tableName) onOpenTable;
  final void Function(String program)? onOpenInGenerator;

  const SchemaProgramsView({
    super.key,
    required this.graph,
    required this.programs,
    required this.selectedProgram,
    required this.onSelect,
    required this.onOpenTable,
    required this.onOpenInGenerator,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Row(
      children: [
        SizedBox(
          width: 280,
          child: Container(
            decoration: BoxDecoration(
              color: colors.panelBg,
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: colors.border)),
                  ),
                  child: Text(
                    programs.length == 1
                        ? '1 program with relationships'
                        : '${programs.length} programs with relationships',
                    style: GoogleFonts.inter(
                      color: colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Expanded(
                  child: programs.isEmpty
                      ? const SchemaEmptyHint(
                          icon: Icons.search_off,
                          message: 'No program matches the search.',
                        )
                      : ListView.builder(
                          itemCount: programs.length,
                          itemBuilder: (context, index) {
                            final program = programs[index];
                            return _ProgramRow(
                              name: program,
                              linkCount: graph.forProgram(program).length,
                              selected: program == selectedProgram,
                              onTap: () => onSelect(program),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: selectedProgram == null
              ? const SchemaEmptyHint(
                  icon: Icons.account_tree_outlined,
                  message: 'Select a program to see the tables it links.',
                  detail:
                      'Each row is a key match the program performs between two tables.',
                )
              : _ProgramRelationships(
                  program: selectedProgram!,
                  relationships: graph.forProgram(selectedProgram!),
                  onOpenTable: onOpenTable,
                  onOpenInGenerator: onOpenInGenerator,
                ),
        ),
      ],
    );
  }
}

class _ProgramRow extends StatefulWidget {
  final String name;
  final int linkCount;
  final bool selected;
  final VoidCallback onTap;

  const _ProgramRow({
    required this.name,
    required this.linkCount,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ProgramRow> createState() => _ProgramRowState();
}

class _ProgramRowState extends State<_ProgramRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.selectedBg
                : (_hovered ? colors.hoverBg.withValues(alpha: 0.35) : null),
            border: Border(
              left: BorderSide(
                width: 2,
                color: widget.selected
                    ? colors.selectedBorder
                    : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: widget.selected
                        ? colors.textPrimary
                        : colors.textSecondary,
                    fontSize: 12,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.linkCount}',
                style: GoogleFonts.firaCode(
                  color: colors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgramRelationships extends StatelessWidget {
  final String program;
  final List<SchemaRelationship> relationships;
  final void Function(String tableName) onOpenTable;
  final void Function(String program)? onOpenInGenerator;

  const _ProgramRelationships({
    required this.program,
    required this.relationships,
    required this.onOpenTable,
    required this.onOpenInGenerator,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tablesTouched = <String>{
      for (final relationship in relationships) ...[
        relationship.fromTable,
        relationship.toTable,
      ],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      program,
                      style: GoogleFonts.outfit(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        SchemaStatPill(
                          icon: Icons.link,
                          label: relationships.length == 1
                              ? '1 link'
                              : '${relationships.length} links',
                          color: colors.statJoins,
                        ),
                        SchemaStatPill(
                          icon: Icons.table_chart_outlined,
                          label: '${tablesTouched.length} tables',
                          color: colors.statTasks,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onOpenInGenerator != null)
                TextButton.icon(
                  onPressed: () => onOpenInGenerator!(program),
                  icon: const Icon(Icons.code, size: 15),
                  label: Text(
                    'Generate SQL',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(foregroundColor: colors.accent),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: colors.panelBg,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: const Row(
            children: [
              SchemaHeaderCell(label: 'FROM TABLE', flex: 3),
              SchemaHeaderCell(label: 'FROM COLUMN', flex: 3),
              SchemaHeaderCell(label: 'TO TABLE', flex: 3),
              SchemaHeaderCell(label: 'TO COLUMN', flex: 3),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: relationships.length,
            itemBuilder: (context, index) {
              final relationship = relationships[index];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom:
                        BorderSide(color: colors.border.withValues(alpha: 0.6)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TablePill(
                          name: relationship.fromTable,
                          color: colors.accent,
                          onTap: () => onOpenTable(relationship.fromTable),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        relationship.fromColumn,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.firaCode(
                          color: colors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TablePill(
                          name: relationship.toTable,
                          color: colors.statJoins,
                          onTap: () => onOpenTable(relationship.toTable),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        relationship.toColumn,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.firaCode(
                          color: colors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
