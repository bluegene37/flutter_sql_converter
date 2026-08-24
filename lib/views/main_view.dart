import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/unipaas_models.dart';
import '../services/schema_service.dart';
import '../services/xml_parser_service.dart';
import '../services/sql_generator_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/drag_handle.dart';
import '../widgets/sql_view.dart';

class MainView extends StatefulWidget {
  final VoidCallback onToggleTheme;

  const MainView({super.key, required this.onToggleTheme});

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> {
  final SchemaService _schemaService = SchemaService();
  late final XmlParserService _xmlParserService;
  final SqlGeneratorService _sqlGeneratorService = SqlGeneratorService();

  String _sourceDirectory = '/Users/bluegene37/StudioProjects/flutter_sql_converter/source';
  List<ProgramMetadata> _filteredPrograms = [];
  ProgramMetadata? _selectedProgramMeta;
  ParsedProgram? _parsedProgram;
  ParsedTask? _selectedTask;
  List<ProgramParameter> _activeParameters = [];
  String _generatedSql =
      '-- Select a program from the left panel and click Generate SQL';
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _injectValues = false;

  // Panel geometry. Both side panels are draggable because a fixed width is
  // wrong for a window that gets resized all day.
  double _leftWidth = 300;
  double _rightWidth = 320;
  bool _paramsOpen = true;
  bool _hideEmptyPrograms = false;

  /// Task tree under the selected program: whether it is showing, and which
  /// parents are collapsed (keyed by hierarchy path, e.g. "1.2").
  bool _treeOpen = true;
  final Set<String> _collapsedTasks = {};
  final TextEditingController _searchController = TextEditingController();
  final Map<String, TextEditingController> _paramControllers = {};

  bool get _canGenerate {
    if (_selectedProgramMeta == null) return false;
    if (!_selectedProgramMeta!.hasTables) return false;
    if (_parsedProgram != null && !_parsedProgram!.hasTables) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _xmlParserService = XmlParserService(_schemaService);
    _initApp();
  }

  Future<void> _initApp() async {
    setState(() => _isLoading = true);
    await _schemaService.loadSchema();

    String? savedDir;
    try {
      savedDir = await SettingsService.loadSourceDirectory();
    } catch (_) {}

    try {
      if (savedDir == null || savedDir.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        savedDir = prefs.getString('saved_source_directory');
      }
    } catch (_) {}

    if (savedDir != null && savedDir.isNotEmpty && Directory(savedDir).existsSync()) {
      _sourceDirectory = savedDir;
    } else {
      final workspaceSource = '${Directory.current.path}/source';
      if (Directory(workspaceSource).existsSync()) {
        _sourceDirectory = workspaceSource;
      } else if (Directory('/Users/bluegene37/StudioProjects/flutter_sql_converter/source').existsSync()) {
        _sourceDirectory = '/Users/bluegene37/StudioProjects/flutter_sql_converter/source';
      } else if (Directory('/Users/myFlo_unipaas/source').existsSync()) {
        _sourceDirectory = '/Users/myFlo_unipaas/source';
      } else if (Directory(r'c:\Data\MV101Apps\MyFlo\source').existsSync()) {
        _sourceDirectory = r'c:\Data\MV101Apps\MyFlo\source';
      }
    }

    await SettingsService.saveSourceDirectory(_sourceDirectory);
    _filteredPrograms = _schemaService.programs.toList();
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      setState(() => _isLoading = false);
      return;
    }
    await _scanSourceDirectory();
  }

  Future<void> _changeSourceDirectory() async {
    final colors = AppColors.of(context);
    final controller = TextEditingController(text: _sourceDirectory);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardBg,
        title: Row(
          children: [
            Icon(Icons.folder, color: colors.accentIcon),
            const SizedBox(width: 8),
            Text(
              'Select XML Source Folder',
              style: GoogleFonts.outfit(
                color: colors.textPrimary,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter or pick the folder containing UniPaas XML programs:',
              style: GoogleFonts.inter(
                color: colors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: GoogleFonts.inter(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Folder Path',
                labelStyle: GoogleFonts.inter(color: colors.textMuted),
                filled: true,
                fillColor: colors.panelBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  final dir = await FilePicker.getDirectoryPath(
                    dialogTitle: 'Select UniPaas XML Source Folder',
                    initialDirectory: controller.text.isNotEmpty
                        ? controller.text
                        : null,
                  );
                  if (dir != null) {
                    controller.text = dir;
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Browse folder error: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text('Browse Folder...', style: GoogleFonts.inter()),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentSecondary,
                foregroundColor: colors.textOnAccent,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: colors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final newPath = controller.text.trim();
              Navigator.pop(context);
              if (newPath.isNotEmpty) {
                setState(() {
                  _sourceDirectory = newPath;
                });
                _scanSourceDirectory(showSuccessMessage: true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.textOnAccent,
            ),
            child: Text(
              'Apply & Analyze',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scanSourceDirectory({bool showSuccessMessage = false}) async {
    setState(() => _isLoading = true);
    final targetDir = _sourceDirectory;

    try {
      await SettingsService.saveSourceDirectory(targetDir);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_source_directory', targetDir);
    } catch (_) {}

    // Load DataSources.xml in background so scanning remains instant (skip in widget test environment)
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _schemaService.loadDataSourcesXmlFromDir(targetDir).then((_) {
        // Comps.xml names the data objects owned by other components, whose
        // ids do not exist in DataSources.xml.
        return _schemaService.loadComponentsXmlFromDir(targetDir);
      }).then((_) {
        if (mounted) setState(() {});
      });
    }

    final dir = Directory(targetDir);
    if (!await dir.exists()) {
      setState(() => _isLoading = false);
      if (mounted) {
        final colors = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Folder path does not exist: $targetDir',
                    style: GoogleFonts.inter(
                      color: colors.snackbarText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: colors.snackbarBg,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.xml'))
        .cast<File>()
        .toList();

    if (files.isEmpty) {
      setState(() => _isLoading = false);
      if (mounted) {
        final colors = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_outlined, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No .xml files found in $targetDir',
                    style: GoogleFonts.inter(
                      color: colors.snackbarText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: colors.snackbarBg,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final existingByFilename = <String, ProgramMetadata>{};
    for (final p in _schemaService.programs) {
      existingByFilename[p.filename.toLowerCase()] = p;
    }

    final scannedPrograms = await Future.wait(
      files.map((file) async {
        final filename = file.uri.pathSegments.last;
        bool hasTables = false;
        try {
          final content = await file.readAsString();
          final dbMatches = RegExp(
            r'<(?:DB|DataObject)\s+[^>]*?obj="([^"]+)"',
          ).allMatches(content);
          final hasValidDb = dbMatches.any(
            (m) => m.group(1) != '0' && m.group(1)!.isNotEmpty,
          );
          final hasLnk = content.contains('<LNK ');
          hasTables = hasValidDb || hasLnk;
        } catch (_) {
          hasTables = true;
        }

        if (existingByFilename.containsKey(filename.toLowerCase())) {
          return existingByFilename[filename.toLowerCase()]!.copyWith(
            hasTables: hasTables,
          );
        } else {
          final idMatch = RegExp(
            r'Prg_(\d+)\.xml',
            caseSensitive: false,
          ).firstMatch(filename);
          final progId = idMatch?.group(1) ?? filename.replaceAll('.xml', '');
          return ProgramMetadata(
            id: progId,
            filename: filename,
            name: 'Program $progId',
            parameters: [],
            hasTables: hasTables,
          );
        }
      }),
    );

    final orderMap = <String, int>{};
    for (final candidate in [
      '$targetDir/ProgramHeaders.xml',
      '$targetDir/source/ProgramHeaders.xml',
      '${dir.parent.path}/ProgramHeaders.xml',
    ]) {
      final f = File(candidate);
      if (await f.exists()) {
        try {
          final content = await f.readAsString();
          final matches = RegExp(
            r'<Program>\s*<Header\s+[^>]*?id="([^"]+)"',
          ).allMatches(content);
          int idx = 0;
          for (final m in matches) {
            final id = m.group(1)!;
            if (!orderMap.containsKey(id)) {
              orderMap[id] = idx++;
            }
          }
          if (orderMap.isNotEmpty) break;
        } catch (_) {}
      }
    }

    scannedPrograms.sort((a, b) {
      final idxA = orderMap[a.id];
      final idxB = orderMap[b.id];
      if (idxA != null && idxB != null) return idxA.compareTo(idxB);
      if (idxA != null) return -1;
      if (idxB != null) return 1;
      final numA = int.tryParse(a.id);
      final numB = int.tryParse(b.id);
      if (numA != null && numB != null) return numA.compareTo(numB);
      return a.filename.compareTo(b.filename);
    });

    if (scannedPrograms.isNotEmpty) {
      _schemaService.programs.clear();
      _schemaService.programs.addAll(scannedPrograms);
    }

    _filterPrograms(_searchController.text);
    if (_selectedProgramMeta != null) {
      final newMatch = _schemaService.programs
          .where(
            (p) =>
                p.filename.toLowerCase() ==
                _selectedProgramMeta!.filename.toLowerCase(),
          )
          .firstOrNull;
      if (newMatch != null) {
        await _selectProgram(newMatch, targetTask: _selectedTask);
      }
    }
    setState(() => _isLoading = false);

    if (showSuccessMessage && mounted) {
      final colors = AppColors.of(context);
      final readyCount = scannedPrograms.where((p) => p.hasTables).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Analyzed folder! Found ${scannedPrograms.length} XML programs ($readyCount ready with tables).',
                  style: GoogleFonts.inter(
                    color: colors.snackbarText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: colors.snackbarBg,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _rescanAndRefresh() async {
    final currentTask = _selectedTask;
    final currentMeta = _selectedProgramMeta;
    await _scanSourceDirectory(showSuccessMessage: true);
    if (currentMeta != null) {
      await _selectProgram(currentMeta, targetTask: currentTask);
    }
  }

  void _filterPrograms(String query) {
    if (query.isEmpty) {
      setState(() => _filteredPrograms = _schemaService.programs.toList());
    } else {
      final q = query.toLowerCase();
      final results = _schemaService.programs
          .where(
            (p) =>
                p.id.toLowerCase().contains(q) ||
                p.name.toLowerCase().contains(q) ||
                p.filename.toLowerCase().contains(q),
          )
          .toList();
      setState(() => _filteredPrograms = results);
    }
  }

  /// Replaces the editable parameter list, keeping one entry and one text
  /// controller per name.
  void _setActiveParameters(List<ProgramParameter> params) {
    final byName = <String, ProgramParameter>{};
    for (final p in params) {
      byName.putIfAbsent(p.name, () => p);
    }
    _activeParameters = byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    for (final ctrl in _paramControllers.values) {
      ctrl.dispose();
    }
    _paramControllers.clear();
    for (final p in _activeParameters) {
      _paramControllers[p.name] = TextEditingController(text: p.currentValue);
    }
  }

  Future<void> _selectProgram(ProgramMetadata meta, {ParsedTask? targetTask}) async {
    setState(() {
      _selectedProgramMeta = meta;
      _selectedTask = targetTask;
      _treeOpen = true;
      _collapsedTasks.clear();
      _setActiveParameters(meta.parameters.map((p) => p.copyWith()).toList());
      _generatedSql =
          '-- Parsing ${meta.filename}...\n-- Click Generate SQL to build the MSSQL query.';
    });

    final filePath = '$_sourceDirectory/${meta.filename}';
    final parsed = await _xmlParserService.parseProgramFile(filePath);
    setState(() {
      _parsedProgram = parsed;
      if (parsed != null) {
        final usedExpressions = <String>[];
        for (final task in parsed.allTasksFlattened) {
          for (final join in task.joins) {
            for (final cond in join.conditions) {
              usedExpressions.add(cond.sourceExpression.toLowerCase());
            }
          }
          for (final cond in task.whereConditions) {
            usedExpressions.add(cond.valueExpression.toLowerCase());
          }
        }

        // Keyed by name, because that is what a DECLARE is keyed by: the same
        // name reached from two different tasks is still one value to fill in.
        // The parser's version wins since it carries the real SQL type.
        final combinedParams = <String, ProgramParameter>{};
        for (final p in parsed.extractedParameters) {
          combinedParams.putIfAbsent(p.name, () => p.copyWith());
        }
        for (final p in meta.parameters) {
          combinedParams.putIfAbsent(p.name, () => p.copyWith());
        }

        final relevantParams = <ProgramParameter>[];
        for (final p in combinedParams.values) {
          final nameLower = p.name.toLowerCase();
          final fieldLower = 'param_${p.fieldId}'.toLowerCase();
          final varLower = 'var_${p.colId}'.toLowerCase();

          bool isUsed = false;
          for (final expr in usedExpressions) {
            if (expr.contains('@$nameLower') ||
                expr.contains('@$fieldLower') ||
                expr.contains('@$varLower') ||
                RegExp(
                  r'\b' + RegExp.escape(nameLower) + r'\b',
                ).hasMatch(expr)) {
              isUsed = true;
              break;
            }
          }
          if (isUsed) {
            relevantParams.add(p);
          }
        }

        _setActiveParameters(relevantParams);
        _generateSql();
      } else {
        _generatedSql = '-- Error: Could not parse XML file at $filePath';
      }
    });
  }

  void _generateSql() {
    if (_parsedProgram == null) return;
    if (!_canGenerate) {
      setState(() {
        _generatedSql =
            '-- No database tables present in this program.\n-- Nothing to generate.';
      });
      return;
    }
    setState(() => _isGenerating = true);

    for (final p in _activeParameters) {
      final ctrl = _paramControllers[p.name];
      if (ctrl != null) {
        p.currentValue = ctrl.text.trim();
      }
    }

    final sql = _sqlGeneratorService.generateSql(
      program: _parsedProgram!,
      parameters: _activeParameters,
      selectedTask: _selectedTask,
      injectValues: _injectValues,
      programNumber: _selectedProgramMeta == null
          ? ''
          : _programNumber(_selectedProgramMeta!, 0),
    );

    setState(() {
      _generatedSql = sql;
      _isGenerating = false;
    });
  }

  void _copyToClipboard() {
    final colors = AppColors.of(context);
    Clipboard.setData(ClipboardData(text: _generatedSql));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              'MSSQL Query copied to clipboard!',
              style: GoogleFonts.inter(
                color: colors.snackbarText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: colors.snackbarBg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  /// Programs the list is currently showing, after the search box and the
  /// "only programs with tables" filter.
  List<ProgramMetadata> get _visiblePrograms => _hideEmptyPrograms
      ? _filteredPrograms.where((p) => p.hasTables).toList()
      : _filteredPrograms;

  /// The parameters inspector earns its space only when there is something to
  /// fill in, so an empty column never sits between the list and the query.
  bool get _showParameters =>
      _paramsOpen && _canGenerate && _activeParameters.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      body: Column(
        children: [
          _buildHeader(),
          if (_isLoading)
            LinearProgressIndicator(
              color: colors.accent,
              backgroundColor: colors.panelBg,
              minHeight: 2,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Leave the query at least half the window however the side
                // panels are dragged.
                final maxSide = constraints.maxWidth * 0.5;
                return Row(
                  children: [
                    SizedBox(
                      width: _leftWidth.clamp(220.0, maxSide),
                      child: _buildProgramsPanel(),
                    ),
                    DragHandle(
                      onDrag: (dx) => setState(
                        () => _leftWidth = (_leftWidth + dx).clamp(220.0, maxSide),
                      ),
                    ),
                    Expanded(child: _buildOutputPanel()),
                    if (_showParameters) ...[
                      DragHandle(
                        onDrag: (dx) => setState(
                          () => _rightWidth = (_rightWidth - dx).clamp(260.0, maxSide),
                        ),
                      ),
                      SizedBox(
                        width: _rightWidth.clamp(260.0, maxSide),
                        child: _buildParametersPanel(),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    final colors = AppColors.of(context);

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // App Logo and Name
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.data_object, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            'SQL Generator',
            style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 18),

          // Read-only Folder Path Display
          Flexible(
            child: Container(
              height: 36,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: colors.panelBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_outlined, color: colors.accentIcon, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Tooltip(
                      message: _sourceDirectory,
                      child: SelectableText(
                        _sourceDirectory,
                        maxLines: 1,
                        style: GoogleFonts.firaCode(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Change XML source folder',
                    child: InkWell(
                      onTap: _changeSourceDirectory,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.cardBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.borderSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open, size: 13, color: colors.accent),
                            const SizedBox(width: 4),
                            Text(
                              'Browse',
                              style: GoogleFonts.inter(
                                color: colors.textPrimary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Programs Ready Counter
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.successBg.withValues(
                alpha: colors.isDark ? 0.35 : 1.0,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colors.successBorder.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 15, color: colors.successText),
                const SizedBox(width: 7),
                Text(
                  _isLoading
                      ? 'Scanning…'
                      : '${_formatCount(_schemaService.programs.length)} Programs Ready',
                  style: GoogleFonts.inter(
                    color: colors.successText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Rescan Button
          _HeaderButton(
            icon: Icons.refresh,
            iconColor: colors.textPrimary,
            label: 'Rescan',
            tooltip: 'Rescan XML folder for new or updated files',
            onTap: _isLoading ? null : _rescanAndRefresh,
          ),
          const SizedBox(width: 10),

          // Theme Toggle - Extreme Right
          _HeaderButton(
            icon: colors.isDark ? Icons.light_mode : Icons.dark_mode,
            iconColor: colors.isDark ? const Color(0xFFFBBF24) : colors.accent,
            tooltip: colors.isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onTap: widget.onToggleTheme,
          ),
        ],
      ),
    );
  }

  static String _formatCount(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Programs
  // ---------------------------------------------------------------------------

  Widget _buildProgramsPanel() {
    final colors = AppColors.of(context);
    final programs = _visiblePrograms;

    return Container(
      color: colors.panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _filterPrograms,
              style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search programs',
                hintStyle: GoogleFonts.inter(color: colors.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: colors.textMuted, size: 17),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 15, color: colors.textMuted),
                        splashRadius: 14,
                        onPressed: () {
                          _searchController.clear();
                          _filterPrograms('');
                        },
                      ),
                filled: true,
                fillColor: colors.cardBg,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.inputFocusBorder),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatCount(programs.length)} shown',
                    style: GoogleFonts.inter(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Tooltip(
                  message: _hideEmptyPrograms
                      ? 'Showing only programs with database tables'
                      : 'Showing all programs',
                  child: InkWell(
                    onTap: () => setState(() => _hideEmptyPrograms = !_hideEmptyPrograms),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _hideEmptyPrograms
                            ? colors.accent.withValues(alpha: 0.15)
                            : colors.cardBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _hideEmptyPrograms ? colors.accent : colors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _hideEmptyPrograms
                                ? Icons.filter_alt
                                : Icons.filter_alt_outlined,
                            size: 13,
                            color: _hideEmptyPrograms ? colors.accent : colors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'With tables',
                            style: GoogleFonts.inter(
                              color: _hideEmptyPrograms ? colors.accent : colors.textSecondary,
                              fontSize: 11,
                              fontWeight: _hideEmptyPrograms ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (programs.isEmpty && !_isLoading)
                  _EmptyState(
                    icon: Icons.search_off,
                    title: 'No programs match',
                    body: _searchController.text.isEmpty
                        ? 'Pick a different folder to scan.'
                        : 'Try a shorter search, or clear it to see everything.',
                  )
                else
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: programs.length,
                    itemBuilder: (context, index) =>
                        _buildProgramRow(programs[index], index),
                  ),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: colors.panelBg.withValues(alpha: 0.85),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colors.accent,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Reading XML files',
                              style: GoogleFonts.inter(
                                color: colors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The program number as shown in the list, which is also the first segment
  /// of every task number underneath it.
  String _programNumber(ProgramMetadata prog, int fallbackIndex) {
    final repoIdx = _schemaService.programs.indexWhere((p) => p.id == prog.id);
    return (repoIdx >= 0 ? repoIdx + 1 : fallbackIndex + 1).toString();
  }

  Widget _buildProgramRow(ProgramMetadata prog, int index) {
    final isSelected = _selectedProgramMeta?.id == prog.id;
    final showTree = isSelected && _treeOpen && _parsedProgram != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProgramHeaderRow(prog, index, isSelected),
        if (showTree) _buildTaskTree(_programNumber(prog, index)),
      ],
    );
  }

  Widget _buildProgramHeaderRow(ProgramMetadata prog, int index, bool isSelected) {
    final colors = AppColors.of(context);
    final isDisabled = !prog.hasTables;
    final hasTree = isSelected && (_parsedProgram?.tasks.isNotEmpty ?? false);
    // Selecting the program means "the whole program", which is also what the
    // All-tasks output shows.
    final wholeProgramSelected = isSelected && _selectedTask == null;

    return InkWell(
      onTap: isDisabled
          ? null
          : () {
              if (isSelected) {
                setState(() {
                  _selectedTask = null;
                  _treeOpen = true;
                  _generateSql();
                });
              } else {
                _selectProgram(prog);
              }
            },
      borderRadius: BorderRadius.circular(7),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.only(left: 4, right: 8, top: 7, bottom: 7),
        decoration: BoxDecoration(
          color: wholeProgramSelected
              ? colors.selectedBg
              : (isSelected ? colors.selectedBg.withValues(alpha: 0.45) : Colors.transparent),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: wholeProgramSelected ? colors.selectedBorder : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: hasTree
                  ? InkWell(
                      onTap: () => setState(() => _treeOpen = !_treeOpen),
                      borderRadius: BorderRadius.circular(4),
                      child: Icon(
                        _treeOpen ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 18,
                        color: colors.textSecondary,
                      ),
                    )
                  : null,
            ),
            SizedBox(
              width: 30,
              child: Text(
                '#${_programNumber(prog, index)}',
                textAlign: TextAlign.right,
                style: GoogleFonts.firaCode(
                  color: isDisabled
                      ? colors.textMuted.withValues(alpha: 0.5)
                      : (isSelected ? colors.accent : colors.textMuted),
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    prog.name,
                    style: GoogleFonts.inter(
                      color: isDisabled
                          ? colors.textMuted
                          : (isSelected ? colors.textPrimary : colors.textSecondary),
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          prog.filename,
                          style: GoogleFonts.firaCode(
                            color: colors.textMuted.withValues(alpha: isDisabled ? 0.5 : 0.85),
                            fontSize: 9.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // The root task below carries the same name and number,
                      // so say what picking the program itself means.
                      if (wholeProgramSelected) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· whole program',
                          style: GoogleFonts.inter(
                            color: colors.accent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isDisabled)
              Tooltip(
                message: 'No database tables, so there is nothing to generate',
                child: Icon(Icons.block, size: 12, color: colors.textMuted.withValues(alpha: 0.6)),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Task tree
  // ---------------------------------------------------------------------------

  /// Tasks in tree order, skipping anything inside a collapsed parent.
  List<ParsedTask> _visibleTasks() {
    final visible = <ParsedTask>[];
    void walk(ParsedTask task) {
      visible.add(task);
      if (_collapsedTasks.contains(task.hierarchyPath)) return;
      for (final child in task.subTasks) {
        walk(child);
      }
    }

    for (final root in _parsedProgram?.tasks ?? const <ParsedTask>[]) {
      walk(root);
    }
    return visible;
  }

  Widget _buildTaskTree(String programNumber) {
    final colors = AppColors.of(context);
    final tasks = _visibleTasks();
    final total = _parsedProgram!.allTasksFlattened.length;
    final anyParents = _parsedProgram!.allTasksFlattened.any((t) => t.hasSubTasks);

    return Container(
      margin: const EdgeInsets.only(left: 13, bottom: 8),
      padding: const EdgeInsets.only(left: 5),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.accent.withValues(alpha: 0.35), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (anyParents)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2, bottom: 3),
              child: Row(
                children: [
                  Text(
                    '$total ${total == 1 ? 'task' : 'tasks'}',
                    style: GoogleFonts.inter(
                      color: colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  _TreeAction(
                    label: _collapsedTasks.isEmpty ? 'Collapse all' : 'Expand all',
                    onTap: () => setState(() {
                      if (_collapsedTasks.isEmpty) {
                        _collapsedTasks.addAll(_parsedProgram!.allTasksFlattened
                            .where((t) => t.hasSubTasks)
                            .map((t) => t.hierarchyPath));
                      } else {
                        _collapsedTasks.clear();
                      }
                    }),
                  ),
                ],
              ),
            ),
          for (final task in tasks) _buildTaskRow(task, programNumber),
        ],
      ),
    );
  }

  Widget _buildTaskRow(ParsedTask task, String programNumber) {
    final colors = AppColors.of(context);
    final isSelected = identical(_selectedTask, task);
    final isCollapsed = _collapsedTasks.contains(task.hierarchyPath);
    final accent = task.isChild ? colors.accentSecondary : colors.accent;

    return InkWell(
      onTap: () => setState(() {
        _selectedTask = task;
        _generateSql();
      }),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        margin: EdgeInsets.only(left: task.level * 11.0, bottom: 1),
        padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: isSelected ? accent : Colors.transparent),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: task.hasSubTasks
                  ? InkWell(
                      onTap: () => setState(() {
                        if (isCollapsed) {
                          _collapsedTasks.remove(task.hierarchyPath);
                        } else {
                          _collapsedTasks.add(task.hierarchyPath);
                        }
                      }),
                      borderRadius: BorderRadius.circular(3),
                      child: Icon(
                        isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                    )
                  : Icon(
                      Icons.remove,
                      size: 8,
                      color: colors.textMuted.withValues(alpha: 0.4),
                    ),
            ),
            const SizedBox(width: 2),
            Text(
              task.numberWithin(programNumber),
              style: GoogleFonts.firaCode(
                color: isSelected ? accent : colors.textMuted,
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                task.description,
                style: GoogleFonts.inter(
                  color: isSelected ? colors.textPrimary : colors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCollapsed && task.subTasks.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                '+${_countDescendants(task)}',
                style: GoogleFonts.firaCode(color: colors.textMuted, fontSize: 9),
              ),
            ],
            if (!task.hasDataSource) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'No data source, so this task produces no SQL',
                child: Icon(
                  Icons.remove_circle_outline,
                  size: 10,
                  color: colors.textMuted.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static int _countDescendants(ParsedTask task) =>
      task.allDescendantsFlattened.length - 1;

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  Widget _buildOutputPanel() {
    final colors = AppColors.of(context);
    return Column(
      children: [
        _buildOutputToolbar(),
        Expanded(
          child: _selectedProgramMeta == null
              ? Container(
                  color: colors.codeBg,
                  child: _EmptyState(
                    icon: Icons.bolt_outlined,
                    title: 'Choose a program to convert',
                    body: 'Pick one from the list on the left. Its uniPaaS dataview, '
                        'links and ranges become a MSSQL query here.',
                  ),
                )
              : SqlView(sql: _generatedSql),
        ),
      ],
    );
  }

  Widget _buildOutputToolbar() {
    final colors = AppColors.of(context);
    final allTasks = _parsedProgram?.allTasksFlattened ?? const <ParsedTask>[];
    final joinCount = allTasks.fold(0, (sum, t) => sum + t.joins.length);
    final hasOutput = _canGenerate &&
        _generatedSql.isNotEmpty &&
        !_generatedSql.startsWith('-- No database tables');

    return LayoutBuilder(
      builder: (context, constraints) {
        // Under pressure the identity gives up space first, then the counts;
        // the actions stay put so Generate is never scrolled out of reach.
        final showStats = constraints.maxWidth > 880 && _parsedProgram != null;
        final showLabels = constraints.maxWidth > 720;

        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.headerBg,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Flexible(child: _buildIdentity(allTasks)),
              if (showStats) ...[
                const SizedBox(width: 14),
                _StatPill(label: 'tasks', value: allTasks.length, color: colors.statTasks),
                const SizedBox(width: 6),
                _StatPill(label: 'joins', value: joinCount, color: colors.statJoins),
              ],
              const Spacer(),
              if (_canGenerate && _activeParameters.isNotEmpty) ...[
                _ToolbarButton(
                  icon: Icons.tune,
                  label: showLabels ? '${_activeParameters.length} Params' : '${_activeParameters.length}',
                  isActive: _paramsOpen,
                  tooltip: _paramsOpen ? 'Hide parameters panel' : 'Show parameters panel (${_activeParameters.length} active)',
                  onTap: () => setState(() => _paramsOpen = !_paramsOpen),
                ),
                const SizedBox(width: 8),
              ],
              _buildModeToggle(showLabels),
              const SizedBox(width: 8),
              Tooltip(
                message: _canGenerate ? 'Generate T-SQL query' : 'No tables available to generate SQL',
                child: ElevatedButton.icon(
                  onPressed: _canGenerate ? _generateSql : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.textOnAccent,
                    disabledBackgroundColor: colors.disabledBg,
                    disabledForegroundColor: colors.textMuted,
                    elevation: 0,
                    minimumSize: const Size(0, 36),
                    padding: EdgeInsets.symmetric(horizontal: showLabels ? 14 : 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt, size: 16),
                  label: Text(
                    showLabels ? 'Generate SQL' : 'Generate',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ToolbarButton(
                icon: Icons.copy_all_outlined,
                label: showLabels ? 'Copy' : null,
                tooltip: hasOutput ? 'Copy SQL query to clipboard' : 'No SQL output to copy',
                onTap: hasOutput ? _copyToClipboard : null,
              ),
            ],
          ),
        );
      },
    );
  }

  /// What you are looking at. The tree on the left is what chooses it, so this
  /// states the selection rather than offering a second way to change it.
  Widget _buildIdentity(List<ParsedTask> allTasks) {
    final colors = AppColors.of(context);
    final meta = _selectedProgramMeta;

    if (meta == null) {
      return Text(
        'No program selected',
        style: GoogleFonts.inter(color: colors.textMuted, fontSize: 13),
      );
    }

    final programNumber = _programNumber(meta, 0);
    final task = _selectedTask;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task == null ? '#$programNumber' : task.numberWithin(programNumber),
          style: GoogleFonts.firaCode(
            color: colors.accent,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            task?.description ?? meta.name,
            style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (task == null && allTasks.length > 1) ...[
          const SizedBox(width: 9),
          Text(
            'all tasks',
            style: GoogleFonts.inter(color: colors.textMuted, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  Widget _buildModeToggle(bool showLabels) {
    final colors = AppColors.of(context);

    Widget segment(String text, IconData icon, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: _canGenerate ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: selected
                    ? colors.textOnAccent
                    : (_canGenerate ? colors.textSecondary : colors.textMuted),
              ),
              if (showLabels) ...[
                const SizedBox(width: 5),
                Text(
                  text,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? colors.textOnAccent
                        : (_canGenerate ? colors.textSecondary : colors.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Parameters: keeps @variables in the query.\nValues: replaces variables with literal values.',
      child: Container(
        height: 36,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            segment('Params', Icons.alternate_email, !_injectValues, () {
              setState(() {
                _injectValues = false;
                _generateSql();
              });
            }),
            const SizedBox(width: 2),
            segment('Values', Icons.tag, _injectValues, () {
              setState(() {
                _injectValues = true;
                _generateSql();
              });
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------

  Widget _buildParametersPanel() {
    final colors = AppColors.of(context);

    return Container(
      color: colors.panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(
              color: colors.headerBg,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Text(
                  'Parameters',
                  style: GoogleFonts.outfit(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_activeParameters.length}',
                    style: GoogleFonts.firaCode(
                      color: colors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Hide parameters',
                  icon: Icon(Icons.close, size: 16, color: colors.textMuted),
                  splashRadius: 15,
                  onPressed: () => setState(() => _paramsOpen = false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              _injectValues
                  ? 'These values are written into the query as literals.'
                  : 'Fill these in to switch the query to literal values.',
              style: GoogleFonts.inter(
                color: colors.textMuted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _activeParameters.length,
              itemBuilder: (context, index) =>
                  _buildParameterField(_activeParameters[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterField(ProgramParameter param) {
    final colors = AppColors.of(context);
    final ctrl = _paramControllers[param.name];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '@${param.name}',
                  style: GoogleFonts.firaCode(
                    color: colors.syntaxParam,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: param.isParameter ? colors.paramBadgeBg : colors.varBadgeBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: param.isParameter ? colors.paramBadgeBorder : colors.varBadgeBorder,
                  ),
                ),
                child: Text(
                  param.isParameter ? 'PARAM' : 'VAR',
                  style: GoogleFonts.inter(
                    color: param.isParameter ? colors.paramBadgeText : colors.varBadgeText,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            SqlGeneratorService.sqlTypeFor(param.type),
            style: GoogleFonts.firaCode(color: colors.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            onChanged: (val) {
              param.currentValue = val;
              if (_injectValues) {
                _generateSql();
              }
            },
            style: GoogleFonts.firaCode(color: colors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'NULL',
              hintStyle: GoogleFonts.firaCode(color: colors.inputHint, fontSize: 12),
              filled: true,
              fillColor: colors.inputBg,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small shared pieces
// -----------------------------------------------------------------------------

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String? label;
  final IconData? trailing;
  final String? tooltip;
  final VoidCallback? onTap;

  const _HeaderButton({
    required this.icon,
    this.iconColor,
    this.label,
    this.trailing,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onTap != null;

    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 9 : 12),
        decoration: BoxDecoration(
          color: colors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: enabled ? (iconColor ?? colors.textSecondary) : colors.textMuted,
            ),
            if (label != null) ...[
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label!,
                  style: GoogleFonts.inter(
                    color: enabled ? colors.textPrimary : colors.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 6),
              Icon(trailing, size: 14, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String? tooltip;
  final bool isActive;
  final VoidCallback? onTap;

  const _ToolbarButton({
    required this.icon,
    this.label,
    this.tooltip,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onTap != null;

    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 12),
        decoration: BoxDecoration(
          color: isActive ? colors.accent.withValues(alpha: 0.15) : colors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? colors.accent : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: enabled
                  ? (isActive ? colors.accent : colors.textPrimary)
                  : colors.textMuted,
            ),
            if (label != null) ...[
              const SizedBox(width: 7),
              Text(
                label!,
                style: GoogleFonts.inter(
                  color: enabled
                      ? (isActive ? colors.accent : colors.textPrimary)
                      : colors.textMuted,
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class _TreeAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TreeAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: colors.accentIcon,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: GoogleFonts.firaCode(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color.withValues(alpha: 0.85),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyState({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 26, color: colors.textMuted),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: colors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                body,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: colors.textMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
