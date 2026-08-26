import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/schema_relationship.dart';
import '../models/unipaas_models.dart';
import '../services/schema_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/schema_chrome.dart';
import '../widgets/schema_detail_dialog.dart';
import '../widgets/schema_programs_view.dart';
import '../widgets/schema_table_views.dart';

enum SchemaViewMode { grid, list, programs }

/// Browses the database the way the uniPaaS programs actually use it: the
/// tables from the data-source repository, and the links between them recovered
/// by scanning every program's dataview logic.
class SchemaView extends StatefulWidget {
  final SchemaService schemaService;
  final SchemaGraph graph;

  /// True while the folder sweep is running; the browser stays usable and
  /// shows tables without their relationship counts until it lands.
  final bool isScanning;
  final int scanDone;
  final int scanTotal;

  final VoidCallback onRescan;

  /// Hands a program to the SQL generator tab. Null when the program cannot be
  /// matched back to a file.
  final void Function(String programName)? onOpenProgram;

  /// Supplied by the parent when a global shortcut needs to reach the search
  /// box; the browser makes its own node when it is left out.
  final FocusNode? searchFocusNode;

  const SchemaView({
    super.key,
    required this.schemaService,
    required this.graph,
    required this.isScanning,
    required this.scanDone,
    required this.scanTotal,
    required this.onRescan,
    required this.onOpenProgram,
    this.searchFocusNode,
  });

  @override
  State<SchemaView> createState() => _SchemaViewState();
}

class _SchemaViewState extends State<SchemaView> {
  final TextEditingController _searchController = TextEditingController();

  /// Only disposed when this widget created it; a node passed in belongs to
  /// the parent.
  FocusNode? _ownedSearchFocusNode;
  FocusNode get _searchFocusNode =>
      widget.searchFocusNode ?? (_ownedSearchFocusNode ??= FocusNode());

  SchemaViewMode _mode = SchemaViewMode.grid;
  String _query = '';
  String _dataSourceFilter = 'all';
  String _prefixFilter = 'all';
  TableSortField _sortField = TableSortField.name;
  bool _ascending = true;
  String? _selectedProgram;

  /// Tables the browser can show at all: anything the data-source repository
  /// named. Cached because filtering runs on every keystroke.
  List<SchemaTable>? _allTablesCache;
  int _allTablesCacheSize = -1;

  @override
  void dispose() {
    _searchController.dispose();
    _ownedSearchFocusNode?.dispose();
    super.dispose();
  }

  List<SchemaTable> get _allTables {
    final tables = widget.schemaService.tables;
    if (_allTablesCache == null || _allTablesCacheSize != tables.length) {
      _allTablesCache = tables.values
          .where((t) => t.name.isNotEmpty || t.physicalName.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _allTablesCacheSize = tables.length;
    }
    return _allTablesCache!;
  }

  /// The connections actually present with how many tables each holds, so the
  /// filter never offers a source this export does not have. Ordered by size:
  /// one connection usually holds almost everything, and alphabetical order
  /// buries it behind a tail of one-off connections.
  List<(String, int)> get _dataSources {
    final counts = <String, int>{};
    for (final table in _allTables) {
      if (table.dataSource.isEmpty) continue;
      counts[table.dataSource] = (counts[table.dataSource] ?? 0) + 1;
    }

    return counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) {
        final bySize = b.$2.compareTo(a.$2);
        return bySize != 0 ? bySize : a.$1.toLowerCase().compareTo(b.$1.toLowerCase());
      });
  }

  int get _totalColumns => _allTables.fold<int>(
        0,
        (sum, table) => sum + table.columnsInOrder.length,
      );

  List<SchemaTable> get _filteredTables {
    final query = _query.trim().toLowerCase();

    return _sorted(_allTables.where((table) {
      if (_dataSourceFilter != 'all' && table.dataSource != _dataSourceFilter) {
        return false;
      }
      if (_prefixFilter != 'all' && !table.name.startsWith(_prefixFilter)) {
        return false;
      }
      if (query.isEmpty) return true;

      if (table.name.toLowerCase().contains(query)) return true;
      if (table.physicalName.toLowerCase().contains(query)) return true;
      if (table.dataSource.toLowerCase().contains(query)) return true;
      return table.columnsInOrder.any((c) =>
          c.name.toLowerCase().contains(query) ||
          c.dbColumnName.toLowerCase().contains(query));
    }).toList());
  }

  List<SchemaTable> _sorted(List<SchemaTable> tables) {
    int compare(SchemaTable a, SchemaTable b) {
      switch (_sortField) {
        case TableSortField.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case TableSortField.physicalName:
          return a.physicalName
              .toLowerCase()
              .compareTo(b.physicalName.toLowerCase());
        case TableSortField.dataSource:
          return a.dataSource
              .toLowerCase()
              .compareTo(b.dataSource.toLowerCase());
        case TableSortField.columnCount:
          return a.columnsInOrder.length.compareTo(b.columnsInOrder.length);
        case TableSortField.relationships:
          return widget.graph
              .degreeOf(a.name)
              .compareTo(widget.graph.degreeOf(b.name));
      }
    }

    tables.sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
    return tables;
  }

  List<String> get _filteredPrograms {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.graph.programs;
    return widget.graph.programs
        .where((p) => p.toLowerCase().contains(query))
        .toList();
  }

  void _sortBy(TableSortField field) {
    setState(() {
      if (_sortField == field) {
        _ascending = !_ascending;
      } else {
        _sortField = field;
        // Counts are most useful biggest-first; names read best A-Z.
        _ascending = field != TableSortField.columnCount &&
            field != TableSortField.relationships;
      }
    });
  }

  SchemaTable? _lookupTable(String name) {
    for (final table in _allTables) {
      if (table.name == name) return table;
    }
    for (final table in _allTables) {
      if (table.physicalName == name) return table;
    }
    return null;
  }

  void _openTable(SchemaTable table) {
    showTableDetail(
      context,
      table: table,
      graph: widget.graph,
      lookupTable: _lookupTable,
      onOpenProgram: widget.onOpenProgram,
    );
  }

  void _openTableByName(String name) {
    final table = _lookupTable(name);
    if (table != null) _openTable(table);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Column(
      children: [
        _buildToolbar(colors),
        if (widget.isScanning) _buildScanProgress(colors),
        Expanded(child: _buildBody(colors)),
      ],
    );
  }

  Widget _buildBody(AppColors colors) {
    if (_allTables.isEmpty) {
      return SchemaEmptyHint(
        icon: Icons.table_chart_outlined,
        message: widget.isScanning
            ? 'Reading the data-source repository…'
            : 'No tables found in this folder.',
        detail: widget.isScanning
            ? null
            : 'DataSources.xml is what names the tables. Check the source folder.',
      );
    }

    if (_mode == SchemaViewMode.programs) {
      return SchemaProgramsView(
        graph: widget.graph,
        programs: _filteredPrograms,
        selectedProgram: _selectedProgram,
        onSelect: (program) => setState(() => _selectedProgram = program),
        onOpenTable: _openTableByName,
        onOpenInGenerator: widget.onOpenProgram,
      );
    }

    final tables = _filteredTables;
    if (tables.isEmpty) {
      return SchemaEmptyHint(
        icon: Icons.search_off,
        message: 'No table matches these filters.',
        detail: _query.isEmpty ? null : 'Searched names, columns and sources.',
      );
    }

    if (_mode == SchemaViewMode.grid) {
      return SchemaTableGrid(
        tables: tables,
        graph: widget.graph,
        onOpen: _openTable,
      );
    }

    return SchemaTableList(
      tables: tables,
      graph: widget.graph,
      sortField: _sortField,
      ascending: _ascending,
      onSort: _sortBy,
      onOpen: _openTable,
    );
  }

  Widget _buildScanProgress(AppColors colors) {
    final total = widget.scanTotal;
    final value = total > 0 ? widget.scanDone / total : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: colors.panelBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            total > 0
                ? 'Scanning program logic for table relationships… '
                    '${widget.scanDone} of $total'
                : 'Scanning program logic for table relationships…',
            style: GoogleFonts.inter(
              color: colors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                color: colors.accent,
                backgroundColor: colors.border,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(AppColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The counts and the toggle's labels give way as the window narrows;
        // the mode switch and the search box never do.
        final width = constraints.maxWidth;
        final showToggleLabels = width >= 1120;
        final showColumnCount = width >= 1000;
        final showTableCount = width >= 860;

        // Programs are not narrowed by data source or name role, so the filter
        // row goes away entirely rather than sitting there empty.
        final showFilters = _mode != SchemaViewMode.programs;

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: colors.headerBg,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // What you are looking at comes before how to narrow it, and
                  // sits beside the search box because it decides what that box
                  // searches.
                  _buildModeToggle(colors, showLabels: showToggleLabels),
                  const SizedBox(width: 12),
                  Expanded(child: _buildSearchField(colors)),
                  const SizedBox(width: 12),
                  ..._buildCounts(
                    colors,
                    showTableCount: showTableCount,
                    showColumnCount: showColumnCount,
                  ),
                  Tooltip(
                    message: 'Re-scan every program for table relationships',
                    child: IconButton(
                      onPressed: widget.isScanning ? null : widget.onRescan,
                      icon: Icon(Icons.refresh,
                          size: 17, color: colors.textSecondary),
                      splashRadius: 18,
                    ),
                  ),
                ],
              ),
              if (showFilters) ...[
                const SizedBox(height: 9),
                _buildFilterRow(colors),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField(AppColors colors) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (value) => setState(() => _query = value),
        style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 12.5),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.inputBg,
          hintText: _mode == SchemaViewMode.programs
              ? 'Search programs…'
              : 'Search tables, columns or data sources…',
          hintStyle: GoogleFonts.inter(color: colors.inputHint, fontSize: 12.5),
          prefixIcon: Icon(Icons.search, size: 16, color: colors.textMuted),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 32),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, size: 15, color: colors.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.inputFocusBorder),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCounts(
    AppColors colors, {
    required bool showTableCount,
    required bool showColumnCount,
  }) {
    final relationships = widget.graph.relationships.length;

    return [
      if (showTableCount) ...[
        SchemaStatPill(
          icon: Icons.table_chart_outlined,
          label: '${formatCount(_allTables.length)} tables',
          color: colors.accent,
        ),
        const SizedBox(width: 6),
      ],
      if (showColumnCount) ...[
        SchemaStatPill(
          icon: Icons.view_column_outlined,
          label: '${formatCount(_totalColumns)} columns',
          color: colors.statTasks,
        ),
        const SizedBox(width: 6),
      ],
      SchemaStatPill(
        icon: Icons.link,
        label: relationships == 1
            ? '1 link'
            : '${formatCount(relationships)} links',
        color: colors.statJoins,
      ),
      const SizedBox(width: 6),
    ];
  }

  Widget _buildFilterRow(AppColors colors) {
    return SizedBox(
      height: 26,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _label('Source', colors),
          const SizedBox(width: 7),
          SchemaFilterChip(
            label: 'All',
            selected: _dataSourceFilter == 'all',
            onTap: () => setState(() => _dataSourceFilter = 'all'),
          ),
          for (final source in _dataSources) ...[
            const SizedBox(width: 5),
            SchemaFilterChip(
              label: source.$1,
              count: source.$2,
              selected: _dataSourceFilter == source.$1,
              onTap: () => setState(() => _dataSourceFilter = source.$1),
            ),
          ],
          const SizedBox(width: 16),
          _label('Role', colors),
          const SizedBox(width: 7),
          SchemaFilterChip(
            label: 'All',
            selected: _prefixFilter == 'all',
            onTap: () => setState(() => _prefixFilter = 'all'),
          ),
          for (final prefix in _namePrefixes) ...[
            const SizedBox(width: 5),
            SchemaFilterChip(
              label: prefix.$1,
              selected: _prefixFilter == prefix.$2,
              onTap: () => setState(() => _prefixFilter = prefix.$2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text, AppColors colors) => Text(
        text,
        style: GoogleFonts.inter(
          color: colors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      );

  Widget _buildModeToggle(AppColors colors, {required bool showLabels}) {
    const modes = [
      (SchemaViewMode.grid, Icons.grid_view, 'Cards'),
      (SchemaViewMode.list, Icons.view_list, 'List'),
      (SchemaViewMode.programs, Icons.account_tree_outlined, 'Programs'),
    ];

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.panelBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, icon, label) in modes)
            Tooltip(
              message: showLabels ? '' : label,
              child: InkWell(
                onTap: () => setState(() => _mode = mode),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  padding: EdgeInsets.symmetric(
                    horizontal: showLabels ? 10 : 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _mode == mode ? colors.cardBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _mode == mode
                          ? colors.borderSubtle
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 13,
                        color: _mode == mode ? colors.accent : colors.textMuted,
                      ),
                      if (showLabels) ...[
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            color: _mode == mode
                                ? colors.textPrimary
                                : colors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// uniPaaS names tables by role: d for data, m for master, h for history,
  /// o for objects the application defines itself.
  static const List<(String, String)> _namePrefixes = [
    ('d · Data', 'd'),
    ('m · Master', 'm'),
    ('h · History', 'h'),
    ('o · Object', 'o'),
  ];

}
