import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/schema_relationship.dart';
import '../models/unipaas_models.dart';
import '../theme/app_theme.dart';
import 'schema_chrome.dart';

/// How the table list is ordered.
enum TableSortField { name, physicalName, dataSource, columnCount, relationships }

/// Card view of the tables. Each card previews the first few columns so a
/// table can be recognised without opening it.
class SchemaTableGrid extends StatelessWidget {
  final List<SchemaTable> tables;
  final SchemaGraph graph;
  final void Function(SchemaTable table) onOpen;

  const SchemaTableGrid({
    super.key,
    required this.tables,
    required this.graph,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const targetWidth = 320.0;
        final columns = (constraints.maxWidth / targetWidth).floor().clamp(1, 6);

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 168,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) => _TableCard(
            table: tables[index],
            degree: graph.degreeOf(tables[index].name),
            onTap: () => onOpen(tables[index]),
          ),
        );
      },
    );
  }
}

class _TableCard extends StatefulWidget {
  final SchemaTable table;
  final int degree;
  final VoidCallback onTap;

  const _TableCard({
    required this.table,
    required this.degree,
    required this.onTap,
  });

  @override
  State<_TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<_TableCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final table = widget.table;
    final preview = table.columnsInOrder.take(5).toList();
    final remaining = table.columnsInOrder.length - preview.length;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: colors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered ? colors.selectedBorder : colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          table.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: colors.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (table.physicalName != table.name)
                          Text(
                            table.physicalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaCode(
                              color: colors.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (table.dataSource.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: TablePill(
                        name: table.dataSource,
                        color: _dataSourceColor(table.dataSource, colors),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                '${table.columnsInOrder.length} columns',
                style: GoogleFonts.inter(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 7),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final column in preview)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.chipBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          column.name,
                          style: GoogleFonts.firaCode(
                            color: colors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    if (remaining > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '+$remaining more',
                          style: GoogleFonts.inter(
                            color: colors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.degree > 0)
                Row(
                  children: [
                    Icon(Icons.link, size: 11, color: colors.statJoins),
                    const SizedBox(width: 5),
                    Text(
                      widget.degree == 1
                          ? '1 relationship'
                          : '${widget.degree} relationships',
                      style: GoogleFonts.inter(
                        color: colors.statJoins,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _dataSourceColor(String dataSource, AppColors colors) {
  switch (dataSource) {
    case 'Memory':
      return colors.syntaxNumber;
    case '':
      return colors.textMuted;
    default:
      return colors.accentSecondary;
  }
}

/// Dense sortable view of the same tables.
class SchemaTableList extends StatelessWidget {
  final List<SchemaTable> tables;
  final SchemaGraph graph;
  final TableSortField sortField;
  final bool ascending;
  final void Function(TableSortField field) onSort;
  final void Function(SchemaTable table) onOpen;

  const SchemaTableList({
    super.key,
    required this.tables,
    required this.graph,
    required this.sortField,
    required this.ascending,
    required this.onSort,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: colors.panelBg,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              SchemaHeaderCell(
                label: 'TABLE',
                flex: 4,
                onTap: () => onSort(TableSortField.name),
                active: sortField == TableSortField.name,
                ascending: ascending,
              ),
              SchemaHeaderCell(
                label: 'PHYSICAL NAME',
                flex: 4,
                onTap: () => onSort(TableSortField.physicalName),
                active: sortField == TableSortField.physicalName,
                ascending: ascending,
              ),
              SchemaHeaderCell(
                label: 'DATA SOURCE',
                flex: 3,
                onTap: () => onSort(TableSortField.dataSource),
                active: sortField == TableSortField.dataSource,
                ascending: ascending,
              ),
              SchemaHeaderCell(
                label: 'COLUMNS',
                flex: 2,
                onTap: () => onSort(TableSortField.columnCount),
                active: sortField == TableSortField.columnCount,
                ascending: ascending,
              ),
              SchemaHeaderCell(
                label: 'RELATIONSHIPS',
                flex: 2,
                onTap: () => onSort(TableSortField.relationships),
                active: sortField == TableSortField.relationships,
                ascending: ascending,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: tables.length,
            itemBuilder: (context, index) => _TableRow(
              table: tables[index],
              degree: graph.degreeOf(tables[index].name),
              onTap: () => onOpen(tables[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _TableRow extends StatefulWidget {
  final SchemaTable table;
  final int degree;
  final VoidCallback onTap;

  const _TableRow({
    required this.table,
    required this.degree,
    required this.onTap,
  });

  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final table = widget.table;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? colors.hoverBg.withValues(alpha: 0.4) : null,
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  table.name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  table.physicalName,
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
                  child: table.dataSource.isEmpty
                      ? Text(
                          '—',
                          style: GoogleFonts.inter(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        )
                      : TablePill(
                          name: table.dataSource,
                          color: _dataSourceColor(table.dataSource, colors),
                        ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${table.columnsInOrder.length}',
                  style: GoogleFonts.firaCode(
                    color: colors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${widget.degree}',
                  style: GoogleFonts.firaCode(
                    color: widget.degree > 0
                        ? colors.statJoins
                        : colors.textMuted,
                    fontSize: 11.5,
                    fontWeight:
                        widget.degree > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
