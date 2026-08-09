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
  final Set<String> _expandedProgramIds = {};
  List<ProgramParameter> _activeParameters = [];
  String _generatedSql =
      '-- Select a program from the left panel and click Generate SQL';
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _injectValues = false;
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

  Future<void> _selectProgram(ProgramMetadata meta, {ParsedTask? targetTask}) async {
    setState(() {
      _selectedProgramMeta = meta;
      _selectedTask = targetTask;
      _expandedProgramIds.add(meta.id);
      _activeParameters = meta.parameters.map((p) => p.copyWith()).toList();
      _paramControllers.clear();
      for (final p in _activeParameters) {
        _paramControllers[p.fieldId] = TextEditingController(
          text: p.currentValue,
        );
      }
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

        final combinedParams = <String, ProgramParameter>{};
        for (final p in meta.parameters) {
          combinedParams[p.fieldId.isNotEmpty ? p.fieldId : p.name] = p
              .copyWith();
        }
        for (final p in parsed.extractedParameters) {
          final key = p.fieldId.isNotEmpty ? p.fieldId : p.name;
          if (!combinedParams.containsKey(key)) {
            combinedParams[key] = p.copyWith();
          }
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

        _activeParameters = relevantParams;
        _paramControllers.clear();
        for (final p in _activeParameters) {
          _paramControllers[p.fieldId] = TextEditingController(
            text: p.currentValue,
          );
        }

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
      final ctrl = _paramControllers[p.fieldId];
      if (ctrl != null) {
        p.currentValue = ctrl.text.trim();
      }
    }

    final sql = _sqlGeneratorService.generateSql(
      program: _parsedProgram!,
      parameters: _activeParameters,
      selectedTask: _selectedTask,
      injectValues: _injectValues,
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
              minHeight: 3,
            ),
          Expanded(
            child: Row(
              children: [
                _buildProgramListPanel(),
                Container(width: 1, color: colors.border),
                _buildParametersPanel(),
                Container(width: 1, color: colors.border),
                Expanded(child: _buildRightPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final colors = AppColors.of(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.data_object, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'SQL Generator',
            style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: InkWell(
                      onTap: _changeSourceDirectory,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.accentIcon),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open, color: colors.accentIcon, size: 16),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Source: $_sourceDirectory',
                                style: GoogleFonts.inter(
                                  color: colors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.edit, color: colors.accentIcon, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.successBg.withValues(
                        alpha: colors.isDark ? 0.4 : 1.0,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.successBorder),
                    ),
                    child: Text(
                      '${_schemaService.programs.length} Programs Ready',
                      style: GoogleFonts.inter(
                        color: colors.successText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'Rescan XML folder for new or updated files',
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _rescanAndRefresh,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: Text(
                        'Rescan XMLs',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accentSecondary,
                        foregroundColor: colors.textOnAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Far right Theme toggle button
          Tooltip(
            message: colors.isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            child: InkWell(
              onTap: widget.onToggleTheme,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      colors.isDark ? Icons.light_mode : Icons.dark_mode,
                      color: colors.isDark ? Colors.amberAccent : colors.accent,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      colors.isDark ? 'Light Mode' : 'Dark Mode',
                      style: GoogleFonts.inter(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramListPanel() {
    final colors = AppColors.of(context);
    return Container(
      width: 280,
      color: colors.panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _filterPrograms,
              style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search programs...',
                hintStyle: GoogleFonts.inter(
                  color: colors.textMuted,
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: colors.textMuted,
                  size: 18,
                ),
                filled: true,
                fillColor: colors.cardBg,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'PROGRAM LIST (${_filteredPrograms.length})',
              style: GoogleFonts.inter(
                color: colors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _filteredPrograms.length,
                  itemBuilder: (context, index) {
                    final prog = _filteredPrograms[index];
                    final isSelected = _selectedProgramMeta?.id == prog.id;
                    final isExpanded = _expandedProgramIds.contains(prog.id);
                    final isDisabled = !prog.hasTables;
                    final repoIdx = _schemaService.programs.indexWhere(
                      (p) => p.id == prog.id,
                    );
                    final displayIndex = (repoIdx >= 0 ? repoIdx + 1 : index + 1)
                        .toString();

                    final currentParsedTasks = (isExpanded && isSelected && _parsedProgram != null)
                        ? _parsedProgram!.allTasksFlattened
                        : <ParsedTask>[];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: isDisabled
                              ? null
                              : () {
                                  if (_expandedProgramIds.contains(prog.id)) {
                                    setState(() {
                                      _expandedProgramIds.remove(prog.id);
                                    });
                                  } else {
                                    setState(() {
                                      _expandedProgramIds.add(prog.id);
                                    });
                                    if (_selectedProgramMeta?.id != prog.id) {
                                      _selectProgram(prog);
                                    }
                                  }
                                },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.selectedBg
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: isSelected
                                  ? Border.all(color: colors.selectedBorder)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDisabled
                                        ? colors.cardBg
                                        : (isSelected
                                              ? colors.accent
                                              : colors.borderSubtle),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    displayIndex,
                                    style: GoogleFonts.inter(
                                      color: isDisabled
                                          ? colors.textMuted
                                          : colors.textOnAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        prog.name,
                                        style: GoogleFonts.inter(
                                          color: isDisabled
                                              ? colors.inputHint
                                              : (isSelected
                                                    ? colors.textPrimary
                                                    : (colors.isDark
                                                          ? const Color(0xFFE2E8F0)
                                                          : colors.textPrimary)),
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        prog.filename,
                                        style: GoogleFonts.inter(
                                          color: isDisabled
                                              ? colors.borderSubtle
                                              : (isSelected
                                                    ? colors.textSecondary
                                                    : colors.textMuted),
                                          fontSize: 10,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isDisabled)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.cardBg,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'NO TABLES',
                                      style: GoogleFonts.inter(
                                        color: colors.textMuted,
                                        fontSize: 9,
                                      ),
                                    ),
                                  )
                                else
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                                    color: colors.textMuted,
                                    size: 14,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (isSelected && currentParsedTasks.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 14, top: 2, bottom: 6),
                            padding: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: colors.accent.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedTask = null;
                                      _generateSql();
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _selectedTask == null
                                          ? colors.accent.withValues(alpha: 0.15)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.list_alt,
                                          size: 12,
                                          color: _selectedTask == null ? colors.accent : colors.textMuted,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'All Tasks (Full Program)',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: _selectedTask == null ? FontWeight.bold : FontWeight.normal,
                                              color: _selectedTask == null ? colors.textPrimary : colors.textSecondary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                ...currentParsedTasks.map((t) {
                                  final isTaskSelected = _selectedTask == t;
                                  final prefixIndent = '  ' * t.level;
                                  final titleText = '$prefixIndent${t.isChild ? "↳ Sub-Task" : "Main Task"} #${t.taskIsn}: ${t.description}';
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedTask = t;
                                        _generateSql();
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isTaskSelected
                                            ? (t.isChild ? colors.accentSecondary.withValues(alpha: 0.2) : colors.accent.withValues(alpha: 0.2))
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                        border: isTaskSelected
                                            ? Border.all(
                                                color: t.isChild ? colors.accentSecondary : colors.accent,
                                                width: 1,
                                              )
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            t.isChild ? Icons.subdirectory_arrow_right : Icons.task_alt,
                                            size: 11,
                                            color: isTaskSelected
                                                ? colors.textPrimary
                                                : (t.isChild ? Colors.amber : colors.textMuted),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              titleText,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: isTaskSelected ? FontWeight.bold : FontWeight.normal,
                                                color: isTaskSelected ? colors.textPrimary : colors.textSecondary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: colors.panelBg.withValues(alpha: 0.8),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colors.accent,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Analyzing XMLs...',
                              style: GoogleFonts.inter(
                                color: colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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

  Widget _buildParametersPanel() {
    final colors = AppColors.of(context);
    return Container(
      width: 310,
      color: colors.panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'INPUT PARAMETERS & VARS',
                  style: GoogleFonts.inter(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_activeParameters.isNotEmpty)
                  Text(
                    '${_activeParameters.length}',
                    style: GoogleFonts.inter(
                      color: colors.accentIcon,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: (_activeParameters.isEmpty || !_canGenerate)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _selectedProgramMeta == null
                            ? 'Select a program to configure parameters'
                            : (!_canGenerate
                                  ? 'No database tables present in this program.\nNothing to generate.'
                                  : 'No parameters used in range/locate for this program'),
                        style: GoogleFonts.inter(
                          color: colors.textMuted,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _activeParameters.length,
                    itemBuilder: (context, index) {
                      final param = _activeParameters[index];
                      final ctrl = _paramControllers[param.fieldId];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    param.name,
                                    style: GoogleFonts.inter(
                                      color: colors.isDark
                                          ? const Color(0xFFE2E8F0)
                                          : colors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: param.isParameter
                                        ? colors.paramBadgeBg.withValues(
                                            alpha: 0.2,
                                          )
                                        : colors.varBadgeBg.withValues(
                                            alpha: 0.2,
                                          ),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: param.isParameter
                                          ? colors.paramBadgeBorder
                                          : colors.varBadgeBorder,
                                    ),
                                  ),
                                  child: Text(
                                    param.isParameter
                                        ? 'PARAM (${param.type})'
                                        : 'VAR (${param.type})',
                                    style: GoogleFonts.inter(
                                      color: param.isParameter
                                          ? colors.paramBadgeText
                                          : colors.varBadgeText,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: ctrl,
                              onChanged: (val) {
                                param.currentValue = val;
                              },
                              style: GoogleFonts.inter(
                                color: colors.textPrimary,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter value...',
                                hintStyle: GoogleFonts.inter(
                                  color: colors.inputHint,
                                  fontSize: 11,
                                ),
                                filled: true,
                                fillColor: colors.inputBg,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: colors.inputFocusBorder,
                                  ),
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
      ),
    );
  }

  Widget _buildRightPanel() {
    final colors = AppColors.of(context);
    final allTasks = _parsedProgram?.allTasksFlattened ?? [];
    return Column(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.headerBg,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'MSSQL QUERY OUTPUT',
                  style: GoogleFonts.inter(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_parsedProgram != null) ...[
                  const SizedBox(width: 12),
                  _buildStatPill(
                    'Tasks: ${allTasks.length}',
                    Colors.cyanAccent,
                  ),
                  const SizedBox(width: 6),
                  _buildStatPill(
                    'Joins: ${allTasks.fold(0, (sum, t) => sum + t.joins.length)}',
                    Colors.purpleAccent,
                  ),
                ],
                const SizedBox(width: 16),
                Text(
                  'Output Mode:',
                  style: GoogleFonts.inter(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(
                    '@Parameterized',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: !_injectValues
                          ? colors.textOnAccent
                          : colors.textSecondary,
                    ),
                  ),
                  selected: !_injectValues,
                  selectedColor: colors.accentSecondary,
                  backgroundColor: colors.chipBg,
                  onSelected: _canGenerate
                      ? (val) {
                          setState(() {
                            _injectValues = false;
                            _generateSql();
                          });
                        }
                      : null,
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(
                    'Injected Literals',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _injectValues
                          ? colors.textOnAccent
                          : colors.textSecondary,
                    ),
                  ),
                  selected: _injectValues,
                  selectedColor: colors.accent,
                  backgroundColor: colors.chipBg,
                  onSelected: _canGenerate
                      ? (val) {
                          setState(() {
                            _injectValues = true;
                            _generateSql();
                          });
                        }
                      : null,
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _canGenerate ? _generateSql : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.textOnAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ).copyWith(
                    backgroundColor:
                        WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return colors.disabledBg;
                      }
                      return colors.accent;
                    }),
                  ),
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.bolt, size: 16),
                  label: Text(
                    'Generate SQL',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (_canGenerate &&
                          _generatedSql.isNotEmpty &&
                          !_generatedSql.startsWith(
                            '-- No database tables',
                          ))
                      ? _copyToClipboard
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.cardBg,
                    foregroundColor: colors.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(color: colors.borderSubtle),
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(
                    'Copy SQL',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_parsedProgram != null && allTasks.isNotEmpty)
          _buildTaskSubListBar(allTasks),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: colors.codeBg,
            child: SingleChildScrollView(
              child: SelectableText(
                _generatedSql,
                style: GoogleFonts.firaCode(
                  color: colors.sqlText,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskSubListBar(List<ParsedTask> allTasks) {
    final colors = AppColors.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.panelBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree_outlined, size: 16, color: colors.textMuted),
          const SizedBox(width: 8),
          Text(
            'SUB-PROGRAMS / TASKS:',
            style: GoogleFonts.inter(
              color: colors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(
                      'All Tasks (${allTasks.length})',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _selectedTask == null
                            ? colors.textOnAccent
                            : colors.textSecondary,
                        fontWeight: _selectedTask == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: _selectedTask == null,
                    selectedColor: colors.accent,
                    backgroundColor: colors.cardBg,
                    onSelected: (val) {
                      setState(() {
                        _selectedTask = null;
                        _generateSql();
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                  ...allTasks.map((task) {
                    final isSelected = _selectedTask == task;
                    final prefix = task.level > 0 ? '${"  " * task.level}↳ ' : '';
                    final labelText = '$prefix${task.isChild ? "Child Task" : "Main Task"} #${task.taskIsn}: ${task.description}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Icon(
                          task.isChild ? Icons.subdirectory_arrow_right : Icons.task_alt,
                          size: 13,
                          color: isSelected ? Colors.white : (task.isChild ? Colors.amberAccent : colors.accentIcon),
                        ),
                        label: Text(
                          labelText,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: isSelected
                                ? colors.textOnAccent
                                : colors.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: task.isChild ? colors.accentSecondary : colors.accent,
                        backgroundColor: colors.cardBg,
                        onSelected: (val) {
                          setState(() {
                            _selectedTask = task;
                            _generateSql();
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
