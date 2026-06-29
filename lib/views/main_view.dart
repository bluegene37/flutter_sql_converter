import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/unipaas_models.dart';
import '../services/schema_service.dart';
import '../services/xml_parser_service.dart';
import '../services/sql_generator_service.dart';

class MainView extends StatefulWidget {
  const MainView({super.key});

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> {
  final SchemaService _schemaService = SchemaService();
  late final XmlParserService _xmlParserService;
  final SqlGeneratorService _sqlGeneratorService = SqlGeneratorService();

  String _sourceDirectory = '/Users/myFlo_unipaas/source';
  List<ProgramMetadata> _filteredPrograms = [];
  ProgramMetadata? _selectedProgramMeta;
  ParsedProgram? _parsedProgram;
  List<ProgramParameter> _activeParameters = [];
  String _generatedSql = '-- Select a program from the left panel and click Generate SQL';
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
    if (!Directory(_sourceDirectory).existsSync()) {
      if (Directory(r'c:\Data\MV101Apps\MyFlo\source').existsSync()) {
        _sourceDirectory = r'c:\Data\MV101Apps\MyFlo\source';
      }
    }
    _filteredPrograms = _schemaService.programs.toList();
    await _scanSourceDirectory();
  }

  Future<void> _changeSourceDirectory() async {
    final controller = TextEditingController(text: _sourceDirectory);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            const Icon(Icons.folder, color: Color(0xFF38BDF8)),
            const SizedBox(width: 8),
            Text('Select XML Source Folder', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter or pick the folder containing UniPaas XML programs:', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: GoogleFonts.inter(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Folder Path',
                labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                final dir = await FilePicker.getDirectoryPath(
                  dialogTitle: 'Select UniPaas XML Source Folder',
                  initialDirectory: controller.text.isNotEmpty ? controller.text : null,
                );
                if (dir != null) {
                  controller.text = dir;
                }
              },
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text('Browse Folder...', style: GoogleFonts.inter()),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (controller.text.trim().isNotEmpty && controller.text.trim() != _sourceDirectory) {
                setState(() {
                  _sourceDirectory = controller.text.trim();
                });
                _scanSourceDirectory();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF06B6D4), foregroundColor: Colors.white),
            child: Text('Apply & Analyze', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _scanSourceDirectory() async {
    setState(() => _isLoading = true);
    final dir = Directory(_sourceDirectory);
    if (await dir.exists()) {
      final files = await dir.list().where((e) => e is File && e.path.toLowerCase().endsWith('.xml')).cast<File>().toList();
      
      final existingByFilename = <String, ProgramMetadata>{};
      for (final p in _schemaService.programs) {
        existingByFilename[p.filename.toLowerCase()] = p;
      }

      final scannedPrograms = await Future.wait(files.map((file) async {
        final filename = file.uri.pathSegments.last;
        bool hasTables = false;
        try {
          final content = await file.readAsString();
          final dbMatches = RegExp(r'<(?:DB|DataObject)\s+[^>]*?obj="([^"]+)"').allMatches(content);
          final hasValidDb = dbMatches.any((m) => m.group(1) != '0' && m.group(1)!.isNotEmpty);
          final hasLnk = content.contains('<LNK ');
          hasTables = hasValidDb || hasLnk;
        } catch (_) {
          hasTables = true;
        }

        if (existingByFilename.containsKey(filename.toLowerCase())) {
          return existingByFilename[filename.toLowerCase()]!.copyWith(hasTables: hasTables);
        } else {
          final idMatch = RegExp(r'Prg_(\d+)\.xml', caseSensitive: false).firstMatch(filename);
          final progId = idMatch?.group(1) ?? filename.replaceAll('.xml', '');
          return ProgramMetadata(
            id: progId,
            filename: filename,
            name: 'Program $progId',
            parameters: [],
            hasTables: hasTables,
          );
        }
      }));

      final orderMap = <String, int>{};
      for (final candidate in [
        '$_sourceDirectory/ProgramHeaders.xml',
        '$_sourceDirectory/source/ProgramHeaders.xml',
        '${dir.parent.path}/ProgramHeaders.xml',
      ]) {
        final f = File(candidate);
        if (await f.exists()) {
          try {
            final content = await f.readAsString();
            final matches = RegExp(r'<Program>\s*<Header\s+[^>]*?id="([^"]+)"').allMatches(content);
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
    }
    _filterPrograms(_searchController.text);
    if (_selectedProgramMeta != null) {
      final newMatch = _schemaService.programs.where((p) => p.filename.toLowerCase() == _selectedProgramMeta!.filename.toLowerCase()).firstOrNull;
      if (newMatch != null) {
        await _selectProgram(newMatch);
      }
    }
    setState(() => _isLoading = false);
  }

  void _filterPrograms(String query) {
    if (query.isEmpty) {
      setState(() => _filteredPrograms = _schemaService.programs.toList());
    } else {
      final q = query.toLowerCase();
      final results = _schemaService.programs.where((p) =>
        p.id.toLowerCase().contains(q) ||
        p.name.toLowerCase().contains(q) ||
        p.filename.toLowerCase().contains(q)
      ).toList();
      setState(() => _filteredPrograms = results);
    }
  }

  Future<void> _selectProgram(ProgramMetadata meta) async {
    setState(() {
      _selectedProgramMeta = meta;
      _activeParameters = meta.parameters.map((p) => p.copyWith()).toList();
      _paramControllers.clear();
      for (final p in _activeParameters) {
        _paramControllers[p.fieldId] = TextEditingController(text: p.currentValue);
      }
      _generatedSql = '-- Parsing ${meta.filename}...\n-- Click Generate SQL to build the MSSQL query.';
    });

    final filePath = '$_sourceDirectory/${meta.filename}';
    final parsed = await _xmlParserService.parseProgramFile(filePath);
    setState(() {
      _parsedProgram = parsed;
      if (parsed != null) {
        final usedExpressions = <String>[];
        for (final task in parsed.tasks) {
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
          combinedParams[p.fieldId.isNotEmpty ? p.fieldId : p.name] = p.copyWith();
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
                RegExp(r'\b' + RegExp.escape(nameLower) + r'\b').hasMatch(expr)) {
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
          _paramControllers[p.fieldId] = TextEditingController(text: p.currentValue);
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
        _generatedSql = '-- No database tables present in this program.\n-- Nothing to generate.';
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
      injectValues: _injectValues,
    );

    setState(() {
      _generatedSql = sql;
      _isGenerating = false;
    });
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _generatedSql));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_outline, color: Colors.greenAccent),
            SizedBox(width: 8),
            Text('MSSQL Query copied to clipboard!'),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4)))
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Row(
                    children: [
                      _buildProgramListPanel(),
                      Container(width: 1, color: const Color(0xFF1E293B)),
                      _buildParametersPanel(),
                      Container(width: 1, color: const Color(0xFF1E293B)),
                      Expanded(child: _buildRightPanel()),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.data_object, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'UniPaas to MSSQL Studio',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: _changeSourceDirectory,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF38BDF8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_open, color: Color(0xFF38BDF8), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Source: $_sourceDirectory',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit, color: Color(0xFF38BDF8), size: 14),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF059669)),
            ),
            child: Text(
              '${_schemaService.programs.length} Programs Ready',
              style: GoogleFonts.inter(color: const Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramListPanel() {
    return Container(
      width: 280,
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _filterPrograms,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search programs...',
                hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 18),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'PROGRAM LIST (${_filteredPrograms.length})',
              style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _filteredPrograms.length,
              itemBuilder: (context, index) {
                final prog = _filteredPrograms[index];
                final isSelected = _selectedProgramMeta?.id == prog.id;
                final isDisabled = !prog.hasTables;
                final repoIdx = _schemaService.programs.indexWhere((p) => p.id == prog.id);
                final displayIndex = (repoIdx >= 0 ? repoIdx + 1 : index + 1).toString();
                return InkWell(
                  onTap: isDisabled ? null : () => _selectProgram(prog),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: isSelected ? Border.all(color: const Color(0xFF06B6D4)) : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDisabled
                                ? const Color(0xFF1E293B)
                                : (isSelected ? const Color(0xFF06B6D4) : const Color(0xFF334155)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            displayIndex,
                            style: GoogleFonts.inter(
                              color: isDisabled ? const Color(0xFF64748B) : Colors.white,
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
                                      ? const Color(0xFF475569)
                                      : (isSelected ? Colors.white : const Color(0xFFE2E8F0)),
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                prog.filename,
                                style: GoogleFonts.inter(
                                  color: isDisabled
                                      ? const Color(0xFF334155)
                                      : (isSelected ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('NO TABLES', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 9)),
                          )
                        else
                          const Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 14),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParametersPanel() {
    return Container(
      width: 310,
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'INPUT PARAMETERS & VARS',
                  style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                if (_activeParameters.isNotEmpty)
                  Text(
                    '${_activeParameters.length}',
                    style: GoogleFonts.inter(color: const Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
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
                        style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 12),
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
                                    style: GoogleFonts.inter(color: const Color(0xFFE2E8F0), fontSize: 12, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: param.isParameter ? const Color(0xFF3B82F6).withValues(alpha: 0.2) : const Color(0xFF475569).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: param.isParameter ? const Color(0xFF3B82F6) : const Color(0xFF475569)),
                                  ),
                                  child: Text(
                                    param.isParameter ? 'PARAM (${param.type})' : 'VAR (${param.type})',
                                    style: GoogleFonts.inter(color: param.isParameter ? const Color(0xFF60A5FA) : const Color(0xFF94A3B8), fontSize: 9),
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
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'Enter value...',
                                hintStyle: GoogleFonts.inter(color: const Color(0xFF475569), fontSize: 11),
                                filled: true,
                                fillColor: const Color(0xFF1E293B),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: Color(0xFF06B6D4)),
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
    return Column(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Color(0xFF111827),
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Row(
            children: [
              Text(
                'MSSQL QUERY OUTPUT',
                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              if (_parsedProgram != null) ...[
                const SizedBox(width: 12),
                _buildStatPill('Tasks: ${_parsedProgram!.tasks.length}', Colors.cyanAccent),
                const SizedBox(width: 6),
                _buildStatPill('Joins: ${_parsedProgram!.tasks.fold(0, (sum, t) => sum + t.joins.length)}', Colors.purpleAccent),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Output Mode:', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12)),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text('@Parameterized', style: GoogleFonts.inter(fontSize: 12, color: !_injectValues ? Colors.white : const Color(0xFF94A3B8))),
                          selected: !_injectValues,
                          selectedColor: const Color(0xFF3B82F6),
                          backgroundColor: const Color(0xFF1E293B),
                          onSelected: _canGenerate ? (val) {
                            setState(() {
                              _injectValues = false;
                              _generateSql();
                            });
                          } : null,
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('Injected Literals', style: GoogleFonts.inter(fontSize: 12, color: _injectValues ? Colors.white : const Color(0xFF94A3B8))),
                          selected: _injectValues,
                          selectedColor: const Color(0xFF06B6D4),
                          backgroundColor: const Color(0xFF1E293B),
                          onSelected: _canGenerate ? (val) {
                            setState(() {
                              _injectValues = true;
                              _generateSql();
                            });
                          } : null,
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _canGenerate ? _generateSql : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF06B6D4),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ).copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.disabled)) return const Color(0xFF1E293B);
                              return const Color(0xFF06B6D4);
                            }),
                          ),
                          icon: _isGenerating
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.bolt, size: 16),
                          label: Text('Generate SQL', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: (_canGenerate && _generatedSql.isNotEmpty && !_generatedSql.startsWith('-- No database tables')) ? _copyToClipboard : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E293B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            side: const BorderSide(color: Color(0xFF334155)),
                          ),
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text('Copy SQL', style: GoogleFonts.inter(fontSize: 13)),
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
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: const Color(0xFF0B0F19),
            child: SingleChildScrollView(
              child: SelectableText(
                _generatedSql,
                style: GoogleFonts.firaCode(
                  color: const Color(0xFF38BDF8),
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
        style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
