import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/schema_relationship.dart';
import '../models/unipaas_models.dart';
import '../theme/app_theme.dart';
import 'schema_chrome.dart';

/// Opens the table inspector: columns, what the table points at, and what
/// points back at it. Following a relationship replaces the contents rather
/// than stacking dialogs, so the back arrow walks the trail.
Future<void> showTableDetail(
  BuildContext context, {
  required SchemaTable table,
  required SchemaGraph graph,
  required SchemaTable? Function(String tableName) lookupTable,
  required void Function(String programName)? onOpenProgram,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => _TableDetailDialog(
      initialTable: table,
      graph: graph,
      lookupTable: lookupTable,
      onOpenProgram: onOpenProgram,
    ),
  );
}

class _TableDetailDialog extends StatefulWidget {
  final SchemaTable initialTable;
  final SchemaGraph graph;
  final SchemaTable? Function(String tableName) lookupTable;
  final void Function(String programName)? onOpenProgram;

  const _TableDetailDialog({
    required this.initialTable,
    required this.graph,
    required this.lookupTable,
    required this.onOpenProgram,
  });

  @override
  State<_TableDetailDialog> createState() => _TableDetailDialogState();
}

class _TableDetailDialogState extends State<_TableDetailDialog> {
  late SchemaTable _table = widget.initialTable;
  final List<SchemaTable> _trail = [];
  final ScrollController _scrollController = ScrollController();
  String _columnFilter = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _goTo(String tableName) {
    final target = widget.lookupTable(tableName);
    if (target == null || target.id == _table.id) return;
    setState(() {
      _trail.add(_table);
      _table = target;
      _columnFilter = '';
    });
    _scrollController.jumpTo(0);
  }

  void _goBack() {
    if (_trail.isEmpty) return;
    setState(() {
      _table = _trail.removeLast();
      _columnFilter = '';
    });
    _scrollController.jumpTo(0);
  }

  List<SchemaColumn> get _visibleColumns {
    if (_columnFilter.isEmpty) return _table.columnsInOrder;
    final query = _columnFilter.toLowerCase();
    return _table.columnsInOrder
        .where((c) =>
            c.name.toLowerCase().contains(query) ||
            c.dbColumnName.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final outgoing = widget.graph.outgoingFor(_table.name);
    final incoming = widget.graph.incomingFor(_table.name);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Container(
          decoration: BoxDecoration(
            color: colors.panelBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(colors, outgoing.length, incoming.length),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildColumnsSection(colors),
                      if (outgoing.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        SchemaSectionTitle(
                          title: 'References',
                          icon: Icons.call_made,
                          count: outgoing.length,
                        ),
                        Text(
                          'Columns of this table that are used to look a row up '
                          'in another table.',
                          style: GoogleFonts.inter(
                            color: colors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final relationship in outgoing)
                          _RelationshipCard(
                            leftLabel: relationship.fromColumn,
                            rightTable: relationship.toTable,
                            rightColumn: relationship.toColumn,
                            programs: relationship.programs,
                            onOpenTable: () => _goTo(relationship.toTable),
                            onOpenProgram: widget.onOpenProgram,
                          ),
                      ],
                      if (incoming.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        SchemaSectionTitle(
                          title: 'Referenced by',
                          icon: Icons.call_received,
                          count: incoming.length,
                        ),
                        Text(
                          'Other tables that look rows up in this one.',
                          style: GoogleFonts.inter(
                            color: colors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final relationship in incoming)
                          _RelationshipCard(
                            leftLabel:
                                '${relationship.fromTable}.${relationship.fromColumn}',
                            rightTable: 'this table',
                            rightColumn: relationship.toColumn,
                            programs: relationship.programs,
                            onOpenTable: () => _goTo(relationship.fromTable),
                            onOpenProgram: widget.onOpenProgram,
                            reversed: true,
                          ),
                      ],
                      if (outgoing.isEmpty && incoming.isEmpty) ...[
                        const SizedBox(height: 22),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.cardBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.border),
                          ),
                          child: Text(
                            'No program links this table to another through a '
                            'key match, so the scan found no relationships for it.',
                            style: GoogleFonts.inter(
                              color: colors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors, int outgoing, int incoming) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_trail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Tooltip(
                message: 'Back to ${_trail.last.name}',
                child: InkWell(
                  onTap: _goBack,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.arrow_back,
                        size: 17, color: colors.textSecondary),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _table.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (_table.isView) ...[
                      const SizedBox(width: 8),
                      TablePill(name: 'VIEW', color: colors.syntaxString),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_table.physicalName != _table.name)
                      SchemaStatPill(
                        icon: Icons.storage,
                        label: _table.physicalName,
                        color: colors.textSecondary,
                      ),
                    if (_table.dataSource.isNotEmpty)
                      SchemaStatPill(
                        icon: Icons.lan_outlined,
                        label: _table.dataSource,
                        color: colors.accentSecondary,
                      ),
                    SchemaStatPill(
                      icon: Icons.view_column_outlined,
                      label: '${_table.columnsInOrder.length} columns',
                      color: colors.statTasks,
                    ),
                    SchemaStatPill(
                      icon: Icons.link,
                      label: '$outgoing out · $incoming in',
                      color: colors.statJoins,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 18, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnsSection(AppColors colors) {
    final columns = _visibleColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SchemaSectionTitle(
                title: 'Columns',
                icon: Icons.view_column_outlined,
                count: _table.columnsInOrder.length,
              ),
            ),
            SizedBox(
              width: 200,
              height: 30,
              child: TextField(
                onChanged: (value) => setState(() => _columnFilter = value),
                style: GoogleFonts.inter(
                  color: colors.textPrimary,
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: colors.inputBg,
                  hintText: 'Filter columns',
                  hintStyle:
                      GoogleFonts.inter(color: colors.inputHint, fontSize: 12),
                  prefixIcon:
                      Icon(Icons.search, size: 15, color: colors.textMuted),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.inputFocusBorder),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: colors.cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: colors.panelBg,
                child: const Row(
                  children: [
                    SizedBox(width: 34, child: SizedBox()),
                    SchemaHeaderCell(label: 'NAME', flex: 4),
                    SchemaHeaderCell(label: 'DB COLUMN', flex: 4),
                    SchemaHeaderCell(label: 'TYPE', flex: 3),
                  ],
                ),
              ),
              if (columns.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No column matches "$_columnFilter".',
                    style: GoogleFonts.inter(
                      color: colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: columns.length,
                    itemBuilder: (context, index) {
                      final column = columns[index];
                      final position =
                          _table.columnsInOrder.indexOf(column) + 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: index == 0
                                  ? Colors.transparent
                                  : colors.border.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '$position',
                                style: GoogleFonts.firaCode(
                                  color: colors.textMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text(
                                column.name,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: colors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text(
                                column.dbColumnName,
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
                                child: SqlTypeBadge(sqlType: column.sqlType),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One link, with the programs whose logic relies on it.
class _RelationshipCard extends StatelessWidget {
  final String leftLabel;
  final String rightTable;
  final String rightColumn;
  final List<String> programs;
  final VoidCallback onOpenTable;
  final void Function(String programName)? onOpenProgram;
  final bool reversed;

  const _RelationshipCard({
    required this.leftLabel,
    required this.rightTable,
    required this.rightColumn,
    required this.programs,
    required this.onOpenTable,
    required this.onOpenProgram,
    this.reversed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              reversed
                  ? TablePill(
                      name: leftLabel,
                      color: colors.accentSecondary,
                      onTap: onOpenTable,
                    )
                  : Text(
                      leftLabel,
                      style: GoogleFonts.firaCode(
                        color: colors.accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
              Icon(Icons.arrow_forward, size: 13, color: colors.textMuted),
              Text(
                rightColumn,
                style: GoogleFonts.firaCode(
                  color: colors.statJoins,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'in',
                style:
                    GoogleFonts.inter(color: colors.textMuted, fontSize: 11.5),
              ),
              reversed
                  ? Text(
                      rightTable,
                      style: GoogleFonts.inter(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    )
                  : TablePill(
                      name: rightTable,
                      color: colors.accentSecondary,
                      onTap: onOpenTable,
                    ),
            ],
          ),
          const SizedBox(height: 9),
          _ProgramList(programs: programs, onOpenProgram: onOpenProgram),
        ],
      ),
    );
  }
}

/// The programs that use a link. Long lists collapse behind a "show all".
class _ProgramList extends StatefulWidget {
  final List<String> programs;
  final void Function(String programName)? onOpenProgram;

  const _ProgramList({required this.programs, required this.onOpenProgram});

  @override
  State<_ProgramList> createState() => _ProgramListState();
}

class _ProgramListState extends State<_ProgramList> {
  static const int _collapsedCount = 6;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final all = widget.programs;
    final shown = _expanded ? all : all.take(_collapsedCount).toList();
    final hidden = all.length - shown.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3, right: 7),
          child: Icon(Icons.article_outlined, size: 12, color: colors.textMuted),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final program in shown)
                _ProgramChip(
                  name: program,
                  onTap: widget.onOpenProgram == null
                      ? null
                      : () => widget.onOpenProgram!(program),
                ),
              if (hidden > 0)
                InkWell(
                  onTap: () => setState(() => _expanded = true),
                  borderRadius: BorderRadius.circular(5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    child: Text(
                      '+$hidden more',
                      style: GoogleFonts.inter(
                        color: colors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (_expanded && all.length > _collapsedCount)
                InkWell(
                  onTap: () => setState(() => _expanded = false),
                  borderRadius: BorderRadius.circular(5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    child: Text(
                      'show fewer',
                      style: GoogleFonts.inter(
                        color: colors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgramChip extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const _ProgramChip({required this.name, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.chipBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Text(
        name,
        style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11),
      ),
    );

    if (onTap == null) return chip;
    return Tooltip(
      message: 'Open "$name" in the SQL generator',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: chip),
      ),
    );
  }
}
